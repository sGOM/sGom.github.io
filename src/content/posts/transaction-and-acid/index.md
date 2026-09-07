---
title: 트랜잭션과 ACID
description: 트랜잭션이 무엇을 보장하고 무엇을 보장하지 않는지 네 속성으로 정리한다
pubDate: 2026-08-09
updatedDate: 2026-09-07
category: "데이터베이스"
tags: ["기본개념", "Database", "트랜잭션"]
---

## 왜 필요한가

계좌 이체는 출금과 입금 두 개의 UPDATE로 이뤄진다. 출금은 성공했는데 입금 직전에 서버가 죽으면 돈이 사라진다. 두 문장을 "전부 되거나 전부 안 되는" 하나의 단위로 묶는 장치가 트랜잭션이다.

트랜잭션은 이 문제만 푸는 것이 아니다. 동시에 실행되는 다른 트랜잭션으로부터의 간섭, 커밋 이후의 유실까지 함께 다룬다. 무엇을 어디까지 보장하는지 구분하지 못하면, 트랜잭션으로 풀 수 없는 문제를 트랜잭션으로 풀려다 시간을 쓴다.

## 용어 정리

- **트랜잭션**: 하나의 작업 단위로 묶인 데이터베이스 연산의 묶음. [`START TRANSACTION`](https://www.postgresql.org/docs/current/sql-begin.html)(여는 문법은 DBMS마다 다르다)으로 시작해 `COMMIT` 또는 `ROLLBACK`으로 끝난다.
- **커밋**: 트랜잭션의 변경을 확정한다. 커밋 이후에는 다른 트랜잭션도 그 변경을 볼 수 있다.
- **롤백**: 트랜잭션의 변경을 전부 취소하고 시작 시점 상태로 되돌린다.
- **자동 커밋(auto-commit)**: 문장 하나하나가 곧 하나의 트랜잭션이 되는 모드. 명시적으로 트랜잭션을 열지 않으면 대부분의 DBMS와 드라이버가 이 모드로 동작한다.

## 핵심 정리

트랜잭션이 보장하는 네 속성을 ACID라 부른다.

| 속성 | 보장하는 것 | 깨지면 생기는 일 |
|---|---|---|
| Atomicity (원자성) | 트랜잭션 안의 연산이 전부 반영되거나 전부 취소된다 | 출금만 되고 입금은 안 된 상태로 남는다 |
| Consistency (일관성) | 트랜잭션 전후로 데이터가 제약조건을 만족한다 | 잔액이 음수가 되거나 없는 회원을 참조하는 주문이 생긴다 |
| Isolation (격리성) | 동시에 실행되는 트랜잭션이 서로의 중간 상태를 보지 않는다 | 커밋되지 않은 값을 읽거나, 같은 조회의 결과가 도중에 바뀐다 |
| Durability (지속성) | 커밋된 변경은 장애가 나도 남는다 | 커밋 응답을 받은 주문이 재기동 후 사라진다 |

## 항목별 설명

**Atomicity**의 구현은 DBMS마다 다르다. MySQL InnoDB는 변경 전 값을 [언두 로그(undo log)](https://dev.mysql.com/doc/refman/8.0/en/innodb-undo-logs.html)에 남겨 두고 롤백 시 그것으로 되돌린다. PostgreSQL에는 언두 로그가 없다. 새 버전을 힙에 따로 쌓아 두고 트랜잭션 상태만 중단으로 표시하면, 그 버전은 누구에게도 보이지 않는 채 남았다가 VACUUM이 걷어간다([MVCC와 스냅숏](/posts/mvcc-and-snapshots/)). 어느 쪽이든 "전부 아니면 전무"는 결과에 대한 약속이지, 중간에 실패하지 않는다는 약속이 아니다.

**Consistency**는 나머지 셋과 성격이 다르다. 원자성·격리성·지속성은 DBMS가 제공하지만, 일관성은 DBMS가 제공하는 제약조건(NOT NULL, UNIQUE, FK, CHECK)과 애플리케이션이 지키는 규칙이 함께 만든다. 아래 이체 예시로 나누면 경계가 보인다. "잔액은 음수가 될 수 없다"는 `CHECK (balance >= 0)`으로 DB가 지킨다. "이체 전후로 두 계좌 잔액의 합은 같다"는 DB가 모른다. 출금 UPDATE 하나만 실행하고 커밋해도 제약조건은 전부 통과한다. 이 규칙을 지키는 것은 두 문장을 한 트랜잭션에 묶기로 정한 애플리케이션 쪽이다.

**Isolation**이 말하는 이상은 "동시에 돌았지만 하나씩 차례로 돈 것과 같다"는 것이다. 격리 수준은 이 이상과 같은 말이 아니라, 이상을 어디까지 포기할지 정하는 눈금이다. 완전한 격리(SERIALIZABLE)는 비싸므로 대부분의 DBMS는 수준을 낮춰 동시성을 얻는다. 어느 수준에서 무엇이 허용되는지가 [격리 수준과 세 가지 이상 현상](/posts/isolation-levels-and-anomalies/)의 주제다.

**Durability**는 커밋 시점에 변경 내용을 리두 로그(WAL, redo log)에 먼저 기록하고 디스크에 동기화하는 방식으로 구현된다. 디스크 자체가 파손되는 경우까지는 막지 못하므로, 복제와 백업은 별도로 필요하다.

## 예시

계좌 이체를 명시적 트랜잭션으로 묶으면 두 UPDATE가 하나의 단위가 된다. `BEGIN`은 PostgreSQL과 MySQL 문법이다.

```sql
BEGIN;
UPDATE account SET balance = balance - 10000 WHERE id = 1;
UPDATE account SET balance = balance + 10000 WHERE id = 2;
COMMIT;
```

두 번째 UPDATE 직전에 장애가 나면 DBMS가 재기동하면서 이 트랜잭션을 롤백하므로, 첫 번째 UPDATE도 없던 일이 된다. 상태 변화는 다음 둘 중 하나뿐이다.

| 시점 | 1번 잔액 | 2번 잔액 |
|---|---|---|
| 시작 | 50000 | 30000 |
| 커밋 성공 | 40000 | 40000 |
| 롤백 | 50000 | 30000 |

같은 두 문장을 자동 커밋 모드로 실행하면 각각이 독립된 트랜잭션이 되어 "출금만 확정된" 세 번째 상태가 실제로 만들어진다.

## 혼동하기 쉬운 것

**원자성과 격리성**은 서로 다른 것을 막는다. 원자성은 *내* 트랜잭션이 절반만 반영되는 것을 막고, 격리성은 *남의* 트랜잭션 중간 상태가 나에게 보이는 것을 막는다. 원자성만 있고 격리성이 없으면, 커밋 전 절반만 반영된 상태를 다른 트랜잭션이 읽을 수 있다.

**롤백과 예외 처리**도 자동으로 연결되지 않는다. 애플리케이션이 예외를 잡아도 트랜잭션이 롤백 표시된 상태라면 커밋은 실패한다. Spring에서 이것이 어떻게 드러나는지는 [예외를 잡았는데 왜 롤백될까](/posts/transactional-propagation/)에 있다.

## 더 깊이

- [격리 수준과 세 가지 이상 현상](/posts/isolation-levels-and-anomalies/) — ACID의 I를 어디까지 포기할지 정하는 눈금
- [트랜잭션 격리 수준은 DBMS마다 다르게 동작한다](/posts/transaction-isolation-levels/) — 표준 정의와 실제 구현의 차이

## 참고

- [PostgreSQL Documentation — Transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html)
- [MySQL 8.0 Reference Manual — InnoDB and the ACID Model](https://dev.mysql.com/doc/refman/8.0/en/mysql-acid.html)
