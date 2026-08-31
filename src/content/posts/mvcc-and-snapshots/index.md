---
title: MVCC와 스냅샷 — 격리 수준이 락 없이 구현되는 방법
description: PostgreSQL이 행마다 여러 버전을 남기고 트랜잭션마다 스냅샷을 떠서 격리 수준을 구현하는 과정을, 튜플 헤더와 스냅샷 값을 직접 들여다보며 확인한다
pubDate: 2026-08-27
category: "데이터베이스"
tags: ["파고들기", "Database", "PostgreSQL", "트랜잭션"]
---

## 전제

- [격리 수준과 세 가지 이상 현상](/posts/isolation-levels-and-anomalies/)
- [트랜잭션 격리 수준은 DBMS마다 다르게 동작한다](/posts/transaction-isolation-levels/)

뒤 글은 "PostgreSQL은 MVCC(다중 버전 동시성 제어)로 동작한다. MVCC는 읽는 트랜잭션과 쓰는 트랜잭션이 서로 다른 버전의 행을 보게 해, 읽기가 쓰기를 막지 않는다"는 두 문장으로 넘어갔다. 이 글은 그 두 문장을 연다.

## 왜 필요한가

격리 수준 표는 무엇이 금지되는지만 말하고 어떻게 지켜지는지는 말하지 않는다. READ COMMITTED가 Dirty Read를 막는다는 것은 규정이고, 그 규정이 성립하려면 DBMS가 무언가를 해야 한다.

가장 쉬운 구현은 락이다. 읽는 행에 공유 락을 걸면 커밋되지 않은 값을 읽을 일이 없다. 그런데 PostgreSQL에서 `SELECT`는 행 락을 걸지 않고, 그런데도 Dirty Read가 나지 않으며, REPEATABLE READ에서는 표준이 허용하는 Phantom Read까지 함께 막힌다. 락을 걸지 않았는데 락으로 얻는 것보다 강한 격리가 나온다.

세 가지가 답을 이룬다. 행 하나가 여러 버전으로 저장되는 방식, 트랜잭션이 어느 버전을 볼지 정하는 스냅샷, 그리고 그 스냅샷을 언제 뜨느냐다. 격리 수준은 마지막 하나만 바꾼다.

## 구조

### 환경

`postgres:16` 이미지(16.15) 기본 설정이다. 실험 테이블은 전부 `autovacuum_enabled = off`로 만들어, 뒤에서 다룰 죽은 행이 관측 도중 치워지지 않게 고정했다.

트랜잭션 id(xid)는 서버 전역에서 순차로 매겨진다. 아래 실험들은 한 서버에서 순서대로 돌렸으므로 실험마다 xid 값이 다르다. 값 자체가 아니라 값들 사이의 대소 관계를 본다.

실행 결과는 psql 출력 그대로 옮기되 `(1 row)` 같은 부수 출력만 덜어냈다. 여러 세션을 동시에 돌린 실험은 각 세션의 출력을 따로 실었다.

### 행마다 붙어 있는 시스템 컬럼

모든 행에는 사용자가 만들지 않은 시스템 컬럼이 붙는다. 이 글에 필요한 것은 셋이다.

| 컬럼 | 뜻 |
|---|---|
| `xmin` | 이 버전을 만든 트랜잭션의 xid |
| `xmax` | 이 버전을 지우거나 갱신한 트랜잭션의 xid. 아직 없으면 0 |
| `ctid` | 이 버전의 물리적 위치. `(블록 번호, 블록 안 라인 번호)` |

`UPDATE`는 기존 행을 고치지 않는다. 새 버전을 새 자리에 쓰고, 옛 버전의 `xmax`에 자기 xid를 적는다. `DELETE`도 지우지 않고 `xmax`만 적는다. 지우는 일은 나중에 `VACUUM`이 한다. → [PostgreSQL — Concurrency Control](https://www.postgresql.org/docs/current/mvcc-intro.html)

### 스냅샷의 세 부분

`pg_current_snapshot()`은 스냅샷을 `xmin:xmax:xip_list` 형식의 텍스트로 보여준다.

| 부분 | 뜻 |
|---|---|
| `xmin` | 이 값보다 작은 xid는 전부 완료됐다 |
| `xmax` | 이 값 이상의 xid는 스냅샷을 뜬 시점에 아직 시작하지 않았다 |
| `xip_list` | `xmin` 이상 `xmax` 미만이면서 아직 진행 중인 xid 목록 |

세 부분이 함께 "스냅샷을 뜬 순간에 무엇이 커밋돼 있었는가"를 표현한다. 스냅샷은 데이터의 복사본이 아니라 xid 경계선 몇 개다.

## 직접 확인

### UPDATE는 덮어쓰지 않는다

행 하나를 두 번 갱신하고 페이지를 직접 열어본다. [`pageinspect`](https://www.postgresql.org/docs/current/pageinspect.html)는 힙 페이지의 튜플 헤더를 그대로 보여주는 확장이다.

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE TABLE acc (id int PRIMARY KEY, balance int) WITH (autovacuum_enabled = off);
INSERT INTO acc VALUES (1, 50000);
UPDATE acc SET balance = 40000 WHERE id = 1;
UPDATE acc SET balance = 30000 WHERE id = 1;

SELECT lp, t_xmin, t_xmax, t_ctid FROM heap_page_items(get_raw_page('acc', 0));
```

```
 lp | t_xmin | t_xmax | t_ctid
----+--------+--------+--------
  1 |    765 |    766 | (0,2)
  2 |    766 |    767 | (0,3)
  3 |    767 |      0 | (0,3)
```

행 하나를 넣고 두 번 갱신했는데 페이지에는 세 개가 있다. 765가 만든 첫 버전은 766이 `xmax`에 적히면서 끝났고, `t_ctid`가 다음 버전 `(0,2)`를 가리킨다. 766이 만든 두 번째 버전도 767이 끝냈다. 마지막 버전만 `t_xmax`가 0이고 `t_ctid`가 자기 자신을 가리킨다.

한 버전의 `xmax`가 다음 버전의 `xmin`과 같다. 이 값이 버전들을 하나의 사슬로 잇는다.

같은 테이블을 평범하게 조회하면 한 행이다.

```
 ctid  | xmin | xmax | balance
-------+------+------+---------
 (0,3) |  767 |    0 |   30000
```

앞의 둘이 사라진 것이 아니라 보이지 않는 것이다. 판단은 조회하는 쪽이 한다.

### 격리 수준이 바꾸는 것은 스냅샷을 뜨는 시점이다

세션 A가 같은 행을 두 번 읽고, 그 사이에 세션 B가 값을 바꾸고 커밋한다. A의 격리 수준만 바꿔가며 두 번 돌렸다.

REPEATABLE READ:

```
 step | snapshot | balance
------+----------+---------
 A-1  | 747:747: |   40000

 step | snapshot | balance
------+----------+---------
 A-2  | 747:747: |   40000
```

위가 B의 커밋 전, 아래가 커밋 후다.

READ COMMITTED:

```
 step | snapshot | balance
------+----------+---------
 A-1  | 749:749: |   40000

 step | snapshot | balance
------+----------+---------
 A-2  | 750:750: |   99999
```

두 실험에서 B는 똑같이 행을 바꾸고 커밋했다. 달라진 것은 A의 스냅샷뿐이다. REPEATABLE READ는 `747:747:`을 두 문장 내내 그대로 쓰고, READ COMMITTED는 문장마다 새로 떠서 `749:749:`가 `750:750:`이 된다.

Non-Repeatable Read를 막는다는 규정이 이 한 줄 차이로 구현된다. B의 xid는 747이었고, A의 스냅샷 `xmax`도 747이다. 747 이상은 스냅샷을 뜬 시점에 시작하지 않은 것이므로, B가 그 뒤에 무엇을 하고 커밋하든 A에게는 보이지 않는다.

### 삭제 표시된 행이 그대로 보인다

위 REPEATABLE READ 실험에서 A가 두 번째 조회 때 시스템 컬럼까지 같이 본 결과다.

```
 ctid  | xmin | xmax | balance
-------+------+------+---------
 (0,3) |  735 |  747 |   40000
```

`xmax`가 747로 채워져 있다. B가 이 버전을 끝냈다는 표시가 A에게도 그대로 보인다. 그런데 A는 이 행을 살아 있는 것으로 취급한다. 747이 A의 스냅샷 기준으로 보이지 않는 트랜잭션이므로, 그 트랜잭션이 남긴 삭제 표시도 효력이 없다고 판단한다.

"보이지 않는 트랜잭션이 지운 행은 아직 지워지지 않은 것"이 MVCC의 핵심 판단이다.

### 진행 중인 트랜잭션은 목록에 들어간다

앞의 스냅샷들은 `xip_list`가 비어 있었다. 세션 A가 xid를 받고 계속 열어둔 채, 세션 B가 뒤이어 xid를 받고 먼저 커밋한 다음, 세션 C가 스냅샷을 뜬다.

```
 A의 xid (계속 진행 중)  ->  762
 B의 xid (곧 커밋)       ->  763
 C가 뜬 스냅샷           ->  762:764:762
```

`xmin`은 762, `xmax`는 764, `xip_list`는 762다. 다음에 나갈 xid가 764이므로 764 이상은 시작 전이고, 762와 763 중 762만 아직 진행 중이라 목록에 남았다. 763은 커밋됐으므로 목록에 없고, C에게 보인다.

같은 구간 안에 있는 두 트랜잭션이 하나는 보이고 하나는 안 보인다. `xip_list`가 그 구분을 맡는다.

### 읽기는 쓰기를 막지 않는다

위 실험들에서 B의 `UPDATE`와 `COMMIT`은 A의 트랜잭션이 열려 있는 동안 끝났다. A는 `pg_sleep(3)` 중이었고 B는 1초 시점에 커밋을 마쳤다. A가 대기를 걸지 않았기 때문이다.

락을 걸어 Dirty Read를 막는 구현이었다면 B는 A가 끝날 때까지 기다렸을 것이다. MVCC에서는 읽는 쪽이 볼 버전과 쓰는 쪽이 만들 버전이 애초에 다른 행이라 겹칠 일이 없다.

### REPEATABLE READ의 대가는 직렬화 실패다

읽기끼리는 겹치지 않지만 쓰기끼리는 겹친다. A가 REPEATABLE READ로 읽은 뒤, B가 같은 행을 바꾸고 커밋하고, 그다음 A가 그 행을 갱신하려 하면 이렇게 된다.

```
    step     | balance
-------------+---------
 A가 읽은 값 |   40000

ERROR:  could not serialize access due to concurrent update
ROLLBACK
```

A의 갱신 대상은 자기 스냅샷에 보이는 버전인데, 그 버전은 이미 B가 끝낸 상태다. 보이지 않는 트랜잭션이 만든 최신 버전 위에 덮어쓰면 B의 변경이 사라지므로, PostgreSQL은 갱신을 포기하고 트랜잭션을 끝낸다.

REPEATABLE READ를 고르면 애플리케이션에 재시도가 필요하다는 말이 이 에러를 가리킨다.

### READ COMMITTED의 UPDATE는 자기 스냅샷을 어긴다

같은 순서를 READ COMMITTED로 돌리면 에러가 나지 않는다. 결과가 그 대신 이상해진다.

```
    step     | balance
-------------+---------
 A가 읽은 값 |   40000

UPDATE 1

      step       | balance
-----------------+---------
 A의 UPDATE 결과 |  100000
```

A는 40000을 읽었고 `SET balance = balance + 1`을 실행했는데 결과가 40001이 아니라 100000이다. 사이에 B가 넣은 99999에 1을 더한 값이다.

`UPDATE`가 갱신할 행을 찾다가 다른 트랜잭션이 끝낸 버전을 만나면, READ COMMITTED에서는 그 트랜잭션이 끝나기를 기다렸다가 **새 버전을 다시 읽어** 조건을 재평가한다. 문장이 자기 스냅샷을 버리고 최신 버전 위에서 다시 계산한다. → [PostgreSQL — Read Committed Isolation Level](https://www.postgresql.org/docs/current/transaction-iso.html#XACT-READ-COMMITTED)

읽은 값을 애플리케이션에서 계산해 넣는 코드가 위험한 자리가 여기다. `balance + 1`은 데이터베이스가 다시 읽어 100000을 냈지만, A가 읽은 40000을 코드에서 더해 `SET balance = 40001`로 보냈다면 그 값이 그대로 들어가고 B의 변경은 사라진다.

### 열린 트랜잭션 하나가 VACUUM을 막는다

10만 행 테이블을 통째로 갱신하고 `VACUUM`을 실행했다. 다른 세션에서 REPEATABLE READ 트랜잭션 하나가 열린 채였다.

```
 갱신 전 크기
--------------
 3544 kB

UPDATE 100000

 pid | backend_xmin | state  |             query
-----+--------------+--------+--------------------------------
 192 |          759 | active | SELECT pg_sleep(10);
 193 |          760 | active | SELECT pid, backend_xmin, stat

VACUUM
 살아있는 행 | 죽은 행 |  크기
-------------+---------+---------
      100000 |  100000 | 7080 kB
```

`VACUUM`이 죽은 행 10만 개를 하나도 치우지 못했고 테이블은 3544 kB에서 7080 kB로 두 배가 됐다. [`pg_stat_activity.backend_xmin`](https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW)이 759다. 759를 스냅샷에 담은 트랜잭션이 살아 있는 한 그 스냅샷에 보이는 버전은 누구도 치울 수 없다.

그 트랜잭션이 끝난 뒤 같은 `VACUUM`을 다시 실행하면 이렇게 된다.

```
 살아있는 행 | 죽은 행 |  크기
-------------+---------+---------
      100000 |       0 | 7080 kB
```

죽은 행은 사라졌지만 크기는 7080 kB 그대로다. `VACUUM`은 공간을 재사용 가능하게 표시할 뿐 운영체제에 돌려주지 않는다. 되돌리려면 `VACUUM FULL`이나 재작성이 필요하고, 그쪽은 테이블을 통째로 잠근다. → [PostgreSQL — Routine Vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)

## 동작 원리

### 가시성 규칙

버전 하나가 보이는지는 두 판단의 곱이다.

1. `xmin`이 커밋됐고, 그 xid가 내 스냅샷 기준으로 보이는가
2. `xmax`가 없거나, 있더라도 그 xid가 내 스냅샷 기준으로 보이지 않는가

둘 다 참이면 보이고, 아니면 건너뛴다. "스냅샷 기준으로 보이는가"는 앞의 세 부분이 정한다. `xid < 스냅샷 xmin`이면 보이고, `xid >= 스냅샷 xmax`면 안 보이고, 그 사이면 `xip_list`에 있는지로 갈린다.

이 규칙 하나가 세 이상 현상을 한꺼번에 처리한다. 커밋되지 않은 트랜잭션의 xid는 `xip_list`에 있으므로 그 버전은 조건 1에서 걸러진다. Dirty Read가 막히는 이유고, 락이 필요 없었던 이유다.

### 스냅샷을 뜨는 시점이 격리 수준이다

| 격리 수준 | 스냅샷을 뜨는 시점 |
|---|---|
| READ COMMITTED | 문장마다 새로 |
| REPEATABLE READ | 트랜잭션의 첫 문장에서 한 번 |
| SERIALIZABLE | REPEATABLE READ와 같고, 충돌 감시가 추가된다 |

「직접 확인」 두 번째 실험의 `747:747:` 대 `749:749:`→`750:750:`이 이 표다.

REPEATABLE READ가 표준이 허용하는 Phantom Read까지 막는 것도 여기서 나온다. 스냅샷은 특정 행이 아니라 xid 경계선이라, 그 시점 이후에 커밋된 것은 `UPDATE`든 `INSERT`든 전부 같은 규칙에 걸린다. 값이 바뀌는 것과 행이 늘어나는 것을 따로 막을 방법이 없어서 함께 막힌다. 표준의 4단계 표가 최소 기준인 이유가 이런 구현 차이다.

### 읽기는 버전을 고르고, 쓰기는 순서를 다툰다

MVCC가 없애는 것은 읽기와 쓰기 사이의 경합이다. 쓰기끼리의 경합은 그대로 남고, 격리 수준은 그 충돌을 다루는 방식만 바꾼다.

| | 같은 행을 동시에 갱신할 때 |
|---|---|
| READ COMMITTED | 앞 트랜잭션을 기다렸다가 새 버전을 다시 읽어 재평가한다 |
| REPEATABLE READ | 기다렸다가, 그사이 바뀌었으면 직렬화 실패로 끝낸다 |

두 실험(100000과 `could not serialize access`)이 각각 한 줄씩이다. READ COMMITTED는 문장이 실패하지 않는 대신 애플리케이션이 읽은 값과 다른 값 위에서 계산될 수 있고, REPEATABLE READ는 그 어긋남을 에러로 드러내는 대신 재시도를 요구한다. 어느 쪽도 공짜가 아니다.

갱신 유실은 둘 다 못 막는다. 값을 읽어 애플리케이션에서 계산해 다시 쓰는 형태는 데이터베이스가 재평가할 표현식이 없어서, `SELECT ... FOR UPDATE`나 버전 컬럼을 쓰는 낙관적 락이 따로 필요하다.

### 옛 버전을 남기는 값

버전을 남기는 방식은 읽기 경합을 없앤 대가로 세 가지를 만든다.

옛 버전은 물리적으로 남는다. 「직접 확인」의 3544 kB → 7080 kB가 그 값이고, 갱신이 잦은 테이블일수록 힙과 인덱스가 함께 부푼다.

치우는 일은 별도 작업이 한다. `VACUUM`과 autovacuum이 그 일을 하고, 그것들이 밀리면 부푼 상태가 유지된다.

치울 수 있는 범위는 가장 오래된 스냅샷이 정한다. `backend_xmin` 759 하나가 죽은 행 10만 개를 붙잡은 것처럼, 열린 트랜잭션 하나의 영향이 그 트랜잭션이 건드리지도 않은 테이블까지 간다.

## 경계 조건

**긴 트랜잭션의 비용은 전역이다.** 애플리케이션이 트랜잭션을 열어둔 채 외부 API를 호출하거나 사용자 입력을 기다리면, 그동안 서버 전체의 정리 작업이 그 시점에 묶인다. 대기 시간이 그 세션만의 문제가 아니다.

**xid는 32비트다.** 약 40억을 쓰면 한 바퀴 돈다. PostgreSQL은 wraparound를 막으려고 오래된 xid를 동결하는데, 그 작업 역시 `VACUUM`이 하므로 앞의 제약이 그대로 걸린다. 이 글에서는 재현하지 않았다.

**SERIALIZABLE은 스냅샷만으로 되지 않는다.** 스냅샷은 각 트랜잭션이 일관된 시점을 보게 할 뿐, 두 트랜잭션이 서로의 읽기 영역에 쓰는 형태(write skew)는 걸러내지 못한다. PostgreSQL은 SSI(Serializable Snapshot Isolation)로 읽은 범위를 추적해 충돌을 감지한다. 이 글의 범위 밖이다.

**다른 DBMS는 다르게 구현한다.** 여기서 본 것은 PostgreSQL이 힙에 버전을 쌓는 방식이다. MySQL InnoDB는 옛 버전을 언두 로그에 두고 필요할 때 되돌려 만들고, Oracle도 언두 세그먼트를 쓴다. 힙이 부푸는 대신 언두가 부푸는 구조라 운영에서 볼 지표가 다르다.

**측정 규모가 작다.** 10만 행, 7 MB짜리 테이블이고 전부 메모리에 있다. 죽은 행이 디스크 I/O를 늘리는 효과는 여기서 관측되지 않는다.

## 언제 쓰고 언제 안 쓰나

**기본값 READ COMMITTED를 유지한다.** 문장마다 스냅샷을 뜨므로 오래된 스냅샷을 붙잡지 않고, 직렬화 실패도 나지 않는다. 바꿀 이유가 생기기 전까지는 이쪽이다.

**한 트랜잭션 안에서 여러 번 조회한 결과가 서로 맞아야 하면 REPEATABLE READ다.** 여러 테이블에 걸친 집계나 리포트가 여기 해당한다. 재시도 경로를 먼저 만들어 두고 바꾼다. 없으면 `could not serialize access` 에러가 그대로 사용자에게 나간다.

**읽고 계산해서 쓰는 코드는 격리 수준으로 풀지 않는다.** READ COMMITTED에서는 애플리케이션이 읽은 값이 이미 낡았을 수 있고, REPEATABLE READ에서는 에러가 난다. 잔액이나 재고처럼 갱신 유실이 곧 사고인 값은 `SELECT ... FOR UPDATE`로 잠그거나 버전 컬럼으로 충돌을 감지한다. 데이터베이스가 다시 읽어 계산할 수 있는 형태(`SET balance = balance - 100`)로 보내는 것도 방법이다.

**트랜잭션은 짧게 유지한다.** 격리 수준과 무관하게, 열려 있는 시간이 곧 `VACUUM`이 손대지 못하는 구간이다. 트랜잭션 안에서 외부 호출을 하지 않는 것이 가장 큰 한 가지다.

## 참고

- [PostgreSQL — Concurrency Control](https://www.postgresql.org/docs/current/mvcc-intro.html)
- [PostgreSQL — Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- [PostgreSQL — Routine Vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)
- [PostgreSQL — pageinspect](https://www.postgresql.org/docs/current/pageinspect.html)
- [PostgreSQL — System Columns](https://www.postgresql.org/docs/current/ddl-system-columns.html)
