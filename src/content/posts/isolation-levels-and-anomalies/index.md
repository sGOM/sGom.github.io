---
title: 격리 수준과 세 가지 이상 현상
description: SQL 표준이 정의한 4단계 격리 수준과 각 단계가 허용하는 이상 현상을 정리한다
pubDate: 2026-08-09
category: "데이터베이스"
tags: ["기본개념", "Database", "트랜잭션"]
---

## 전제

[트랜잭션과 ACID](/posts/transaction-and-acid/)의 I(Isolation)를 단계로 나눈 것이 격리 수준이다.

## 왜 필요한가

격리를 완전하게 하면 동시성이 죽는다. 모든 트랜잭션을 한 줄로 세워 실행하면 서로 간섭할 일이 없지만 처리량도 그만큼 떨어진다. 그래서 DBMS는 "어디까지 간섭을 허용할지"를 단계로 나눠 고르게 한다.

허용한다는 것은 곧 특정 이상 현상이 나타날 수 있다는 뜻이다. 어느 단계가 무엇을 허용하는지 모르면, 코드는 그대로인데 결과가 달라지는 상황을 설명하지 못한다.

## 용어 정리

이상 현상(anomaly)은 격리가 불완전할 때 나타나는 읽기 결과다. 세 가지 모두 **읽는 쪽**에서 관측된다.

- **Dirty Read**: 아직 커밋되지 않은 다른 트랜잭션의 변경을 읽는다. 그 트랜잭션이 롤백되면 존재한 적 없는 값을 읽은 것이 된다.
- **Non-Repeatable Read**: 같은 트랜잭션 안에서 **같은 행**을 두 번 읽었는데 값이 달라진다. 사이에 다른 트랜잭션이 그 행을 UPDATE하고 커밋한 경우다.
- **Phantom Read**: 같은 조건으로 두 번 조회했는데 **행의 개수**가 달라진다. 사이에 다른 트랜잭션이 조건에 맞는 행을 INSERT하거나 DELETE하고 커밋한 경우다.

## 핵심 정리

SQL 표준은 격리 수준 4단계를 정의하고, 각 단계가 허용·차단하는 이상 현상을 다음과 같이 규정한다.

| 격리 수준 | Dirty Read | Non-Repeatable Read | Phantom Read |
|---|---|---|---|
| READ UNCOMMITTED | 발생 가능 | 발생 가능 | 발생 가능 |
| READ COMMITTED | 방지 | 발생 가능 | 발생 가능 |
| REPEATABLE READ | 방지 | 방지 | 발생 가능 |
| SERIALIZABLE | 방지 | 방지 | 방지 |

아래로 갈수록 격리가 강해지고 동시성은 낮아진다. 표는 **최소 기준**이다. 어떤 DBMS가 REPEATABLE READ에서 Phantom Read까지 막아도 표준을 위반한 것이 아니다.

## 예시

Non-Repeatable Read가 나타나는 순서다. READ COMMITTED에서 실행한다.

| 시각 | 트랜잭션 A | 트랜잭션 B |
|---|---|---|
| 1 | `BEGIN` | |
| 2 | `SELECT balance FROM account WHERE id=1` → **50000** | |
| 3 | | `UPDATE account SET balance=40000 WHERE id=1` |
| 4 | | `COMMIT` |
| 5 | `SELECT balance FROM account WHERE id=1` → **40000** | |

A는 아무것도 바꾸지 않았는데 같은 조회의 결과가 달라졌다. 3번이 커밋된 변경이므로 Dirty Read는 아니다. 격리 수준을 REPEATABLE READ로 올리면 5번은 다시 50000이 된다.

Phantom Read는 조회 대상이 행 하나가 아니라 범위라는 점만 다르다.

| 시각 | 트랜잭션 A | 트랜잭션 B |
|---|---|---|
| 1 | `SELECT count(*) FROM logs WHERE level='ERROR'` → **3** | |
| 2 | | `INSERT INTO logs(level) VALUES('ERROR')`, `COMMIT` |
| 3 | `SELECT count(*) FROM logs WHERE level='ERROR'` → **4** | |

## 혼동하기 쉬운 것

**Non-Repeatable Read와 Phantom Read**는 자주 뒤바뀐다. 기준은 "무엇이 달라졌는가"다. 이미 읽은 행의 **값**이 달라지면 Non-Repeatable Read, 조건에 맞는 행의 **집합**이 달라지면 Phantom Read다. 앞의 것은 UPDATE가, 뒤의 것은 INSERT와 DELETE가 만든다.

**격리 수준은 읽기 쪽 설정이다.** 트랜잭션 A의 격리 수준을 올려도 B가 쓰는 것을 막지는 못한다. A가 자기 조회 결과를 보호할 뿐이다. 반대로 갱신 유실(lost update)처럼 쓰기끼리 충돌하는 문제는 격리 수준만으로 해결되지 않아 `SELECT ... FOR UPDATE`나 낙관적 락이 따로 필요하다.

**SERIALIZABLE이 "한 줄로 실행"을 뜻하지는 않는다.** 결과가 어떤 직렬 실행 순서와 같아지도록 보장할 뿐, 실제로 동시 실행을 막는 방식은 구현마다 다르다.

## 구현체별 차이

같은 이름의 격리 수준도 DBMS마다 기본값과 실제 동작이 다르다.

| DBMS | 기본 격리 수준 | 특이점 |
|---|---|---|
| MySQL (InnoDB) | REPEATABLE READ | 갭 락·넥스트키 락으로 잠금 읽기의 Phantom Read를 상당 부분 막는다 |
| PostgreSQL | READ COMMITTED | READ UNCOMMITTED를 요청해도 READ COMMITTED로 동작한다 |
| Oracle | READ COMMITTED | REPEATABLE READ를 지원하지 않는다 |
| H2 | READ COMMITTED | MVStore 모드의 REPEATABLE READ는 스냅샷 기반이라 Phantom Read도 막힌다 |

표만 외우고 실무에 적용하면 틀리는 이유가 여기 있다. 자세한 내용과 재현 결과는 [트랜잭션 격리 수준은 DBMS마다 다르게 동작한다](/posts/transaction-isolation-levels/)에 있다.

## 언제 어떤 것을 쓰나

기본값을 바꿀 구체적인 이유가 없으면 기본값을 쓴다. 격리 수준을 올리기 전에 그 문제가 정말 읽기 격리 문제인지 먼저 확인한다. 갱신 유실이나 중복 삽입은 격리 수준이 아니라 락이나 제약조건으로 푼다.

## 더 깊이

- [트랜잭션 격리 수준은 DBMS마다 다르게 동작한다](/posts/transaction-isolation-levels/)

## 참고

- [PostgreSQL Documentation — Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- [MySQL 8.0 Reference Manual — InnoDB Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
