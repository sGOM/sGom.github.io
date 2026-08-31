---
title: 데드락이 잡히는 순간 — 락 대기 그래프와 재현 테스트
description: PostgreSQL이 데드락을 즉시 잡지 않고 1초를 기다렸다가 대기 그래프의 순환을 찾는 과정을, 두 종류의 데드락을 재현하고 대기 상태를 직접 들여다보며 정리한다
pubDate: 2026-08-27
category: "데이터베이스"
tags: ["파고들기", "Database", "PostgreSQL", "트랜잭션"]
---

## 전제

- [트랜잭션과 ACID](/posts/transaction-and-acid/)
- [예외를 잡았는데 왜 롤백될까](/posts/transactional-propagation/)

뒤 글은 "바깥이 잠근 행을 안쪽이 다시 잠그면 자기 자신과 데드락에 빠진다"고 한 줄로 지나갔다. 이 글은 그 데드락이 어떻게 감지되고 누가 죽는지를 본다.

## 왜 필요한가

`deadlock detected` 에러는 스택 트레이스가 두 트랜잭션에 걸쳐 있어서 로그만 보면 원인이 잘 안 잡힌다. 살아남은 쪽은 정상 커밋되므로 애플리케이션 로그에도 흔적이 반쪽만 남는다.

풀리지 않는 질문이 셋 있다. 데이터베이스는 두 트랜잭션이 서로를 기다린다는 것을 어떻게 아는지, 왜 하필 그중 하나만 죽는지, 그리고 명시적으로 락을 건 적이 없는데도 데드락이 나는 경우는 무엇인지다.

## 구조

### 환경

`postgres:16` 이미지(16.15) 기본 설정이다. 관련된 설정 셋은 이렇다.

```
           name            | setting | unit
---------------------------+---------+------
 deadlock_timeout          | 1000    | ms
 lock_timeout              | 0       | ms
 max_locks_per_transaction | 64      |
```

계좌 두 개짜리 테이블을 쓴다.

```sql
CREATE TABLE acct (id int PRIMARY KEY, owner text, balance int);
INSERT INTO acct VALUES (1,'kim',10000), (2,'lee',10000);
```

### 행 락은 어디에 기록되나

`UPDATE`가 행을 잠글 때 PostgreSQL은 락 테이블에 "이 행이 잠겼다"를 기록하지 않는다. 행 자체의 `xmax`에 잠근 트랜잭션의 xid를 적는다. 행 수만큼 메모리를 쓰지 않으려는 설계다.

그래서 기다리는 쪽은 행을 기다릴 수 없고, **그 xid를 기다린다.** 자기가 원하는 행의 `xmax`에서 xid를 읽어, 그 트랜잭션 id에 대한 `ShareLock`을 요청한다. 트랜잭션은 끝날 때까지 자기 xid에 `ExclusiveLock`을 쥐고 있으므로, 요청은 그 트랜잭션이 끝나야 승인된다.

`xmax`가 무엇인지는 [MVCC와 스냅샷](/posts/mvcc-and-snapshots/)에 있다. 데드락 메시지가 행이 아니라 트랜잭션 번호를 말하는 이유가 이 구조다.

## 직접 확인

### 대기가 어떻게 보이는가

세션 A가 `id = 1`을 갱신하고 트랜잭션을 열어둔 채, 세션 B가 같은 행을 갱신하려 한다. 세 번째 세션에서 그 순간을 들여다봤다.

```
 pid | 기다리는 상대 | wait_event_type |  wait_event   |             query
-----+---------------+-----------------+---------------+------------------------------
 499 | {}            | Timeout         | PgSleep       | SELECT pg_sleep(8);
 500 | {499}         | Lock            | transactionid | UPDATE acct SET balance = ...
 501 | {}            |                 |               | SELECT pid, pg_blocking_pids...
```

`pg_blocking_pids(500)`이 `{499}`다. 이 함수 하나가 대기 그래프의 간선 하나를 보여준다. `wait_event`가 `transactionid`인 것이 앞서 말한 구조다. B는 행이 아니라 A의 트랜잭션 번호를 기다린다.

같은 시점의 `pg_locks`에서 B가 쥔 것과 못 쥔 것이다.

```
   locktype    | relation  | transactionid |       mode       | granted | pid
---------------+-----------+---------------+------------------+---------+-----
 relation      | acct_pkey |               | RowExclusiveLock | t       | 500
 relation      | acct      |               | RowExclusiveLock | t       | 500
 virtualxid    |           |               | ExclusiveLock    | t       | 500
 transactionid |           |           800 | ExclusiveLock    | t       | 500
 tuple         | acct      |               | ExclusiveLock    | t       | 500
 transactionid |           |           799 | ShareLock        | f       | 500
```

마지막 줄만 `granted = f`다. B는 자기 트랜잭션 800에 대한 `ExclusiveLock`은 이미 쥐었고, A의 트랜잭션 799에 대한 `ShareLock`을 기다리는 중이다. 테이블 락(`RowExclusiveLock`)은 둘 다 문제없이 받았다. `RowExclusiveLock`끼리는 충돌하지 않기 때문이다. 두 `UPDATE`가 같은 테이블을 건드려도 테이블 수준에서는 막히지 않는다.

**여기 어디에도 "행 1번이 잠겼다"는 줄은 없다.** 잠긴 행의 정보는 힙의 `xmax`에 있다.

### 반대 순서로 잠그면

이제 두 세션이 같은 두 행을 반대 순서로 잠근다. 계좌 이체를 서로 반대 방향으로 실행하는 코드다.

| 시각 | 세션 A | 세션 B |
|---|---|---|
| 0.0 | `UPDATE ... WHERE id = 1` | |
| 0.5 | | `UPDATE ... WHERE id = 2` |
| 2.0 | `UPDATE ... WHERE id = 2` → 대기 | |
| 2.5 | | `UPDATE ... WHERE id = 1` → 대기 |

```
-- 세션 A
ERROR:  deadlock detected
DETAIL:  Process 478 waits for ShareLock on transaction 798; blocked by process 479.
Process 479 waits for ShareLock on transaction 797; blocked by process 478.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,2) in relation "acct"
ROLLBACK

-- 세션 B
UPDATE 1
COMMIT
```

A만 죽고 B는 정상 커밋됐다. `DETAIL` 두 줄이 그대로 순환이다. 478은 798을 기다리고 798은 479가 쥐고 있으며, 479는 797을 기다리고 797은 478이 쥐고 있다.

서버 로그에는 각 프로세스가 실행 중이던 문장까지 남는다.

```
ERROR:  deadlock detected
DETAIL:  Process 478 waits for ShareLock on transaction 798; blocked by process 479.
	Process 479 waits for ShareLock on transaction 797; blocked by process 478.
	Process 478: UPDATE acct SET balance = balance + 100 WHERE id = 2;
	Process 479: UPDATE acct SET balance = balance + 100 WHERE id = 1;
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,2) in relation "acct"
```

클라이언트가 받는 에러에는 `Process 478: ...` 두 줄이 없다. `HINT`가 서버 로그를 보라고 하는 것이 이 두 줄을 말한다. 어느 문장 짝이 부딪혔는지는 서버 로그에만 있다.

### 락을 건 적이 없는데도 난다

두 번째 종류는 명시적인 `UPDATE`도 `FOR UPDATE`도 없다. 유니크 제약이 있는 테이블에 두 세션이 같은 두 값을 반대 순서로 넣는다.

```sql
CREATE TABLE tag (name text PRIMARY KEY);
```

| 시각 | 세션 A | 세션 B |
|---|---|---|
| 0.0 | `INSERT 'kotlin'` | |
| 0.5 | | `INSERT 'spring'` |
| 2.0 | `INSERT 'spring'` → 대기 | |
| 2.5 | | `INSERT 'kotlin'` → 대기 |

```
ERROR:  deadlock detected
DETAIL:  Process 551 waits for ShareLock on transaction 805; blocked by process 552.
	Process 552 waits for ShareLock on transaction 804; blocked by process 551.
	Process 551: INSERT INTO tag VALUES ('spring');
	Process 552: INSERT INTO tag VALUES ('kotlin');
CONTEXT:  while inserting index tuple (0,3) in relation "tag_pkey"
```

`CONTEXT`가 다르다. 앞의 것은 `while updating tuple`, 이번에는 `while inserting index tuple`이다.

유니크 인덱스에 값을 넣을 때 같은 값이 이미 있는데 그 행을 만든 트랜잭션이 아직 안 끝났으면, 커밋될지 롤백될지 알아야 중복인지 판정할 수 있다. 그래서 그 트랜잭션을 기다린다. 대기 대상은 앞의 경우와 똑같이 트랜잭션 id다.

여러 태그를 한 번에 저장하는 배치나 upsert가 서로 다른 순서로 들어오면 이 형태가 나온다. 코드에는 `LOCK`도 `FOR UPDATE`도 없다.

### 순서를 맞추면 사라진다

앞의 이체 예제에서 두 세션이 **같은 순서**로 잠그게 바꿨다. 둘 다 `id = 1` 먼저, `id = 2` 다음이다.

```
--- A ---   A 커밋됨
--- B ---   B 커밋됨
```

둘 다 성공했다. B는 A가 끝날 때까지 기다렸다가 이어서 실행했을 뿐이다. `pg_stat_database.deadlocks` 카운터도 1에서 늘지 않았다.

순환이 생기려면 서로가 서로의 뒤에 서야 한다. 모두가 같은 순서로 줄을 서면 뒤에 선 쪽이 앞을 기다리기만 하고 그 반대가 없다.

### 감지보다 먼저 끊기

기다리는 쪽에 `lock_timeout`을 걸면 데드락 감지기가 도착하기 전에 스스로 물러난다.

```sql
SET lock_timeout = '500ms';
```

```
ERROR:  canceling statement due to lock timeout
ROLLBACK
```

`deadlock detected`가 아니라 `lock timeout`이다. 500ms가 `deadlock_timeout` 1,000ms보다 짧아서, 순환 탐지가 시작되기도 전에 대기가 취소됐다.

에러 종류가 달라지면 애플리케이션이 붙잡을 조건도 달라진다. 데드락은 SQLSTATE `40P01`, 락 타임아웃은 `55P03`이다.

## 동작 원리

### 1초를 기다렸다가 검사한다

대기가 시작될 때마다 순환을 찾지는 않는다. 순서는 이렇다.

1. 락을 요청한다. 승인되면 끝이다
2. 승인되지 않으면 대기 큐에 들어가 잠든다
3. `deadlock_timeout`(기본 1초)이 지나면 깨어나 대기 그래프를 만든다
4. 그래프에서 자기가 포함된 순환을 찾는다
5. 순환이 있으면 에러를 내고, 없으면 다시 잠든다

3번이 이 설계의 요점이다. 대부분의 락 대기는 정상적으로 풀리고, 순환 탐지는 서버 전체의 락 상태를 훑는 작업이라 싸지 않다. 그래서 "1초를 기다려도 안 풀리는 대기"에만 비용을 낸다.

대가는 데드락이 항상 최소 1초를 잡아먹는다는 것이다. 두 세션이 이미 순환에 빠진 시점부터 에러가 나기까지 그 시간이 그대로 흐른다.

### 누가 죽는가

**순환을 발견한 프로세스가 자기 트랜잭션을 취소한다.** 별도의 심판이 있어서 피해가 적은 쪽을 고르는 것이 아니다.

발견하는 쪽은 대기를 먼저 시작해 `deadlock_timeout`이 먼저 만료된 프로세스다. 위 두 재현에서 죽은 478과 551은 각각 상대보다 0.5초 먼저 기다리기 시작한 쪽이다.

여기서 두 가지가 따라온다. 희생자는 트랜잭션의 크기나 중요도와 무관하고, 같은 코드가 다시 부딪히면 다른 쪽이 죽을 수도 있다. 재시도 로직은 어느 쪽이 죽어도 동작해야 한다.

### 대기 그래프는 트랜잭션 id로 이어진다

행 락을 락 테이블에 넣지 않는 설계 덕분에 그래프가 단순해진다.

| | 기록되는 곳 | 대기 방식 |
|---|---|---|
| 테이블 락 | `pg_locks` | 해당 락 객체를 기다린다 |
| 행 락 | 행의 `xmax` | 잠근 **트랜잭션 id**에 `ShareLock`을 요청한다 |
| 유니크 키 충돌 | 인덱스 튜플 | 같음 |

세 경우 모두 대기 대상이 `pg_locks`의 항목 하나로 표현되고, 그 항목을 누가 쥐고 있는지도 `pg_locks`에 있다. 그래서 순환 탐지는 락 테이블만 훑으면 되고, 행 단위 정보를 볼 필요가 없다.

`pg_blocking_pids()`가 보여준 `{499}`가 그래프의 간선 하나이고, 데드락 메시지의 `DETAIL` 두 줄이 순환 전체다. → [PostgreSQL — Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-DEADLOCKS)

## 경계 조건

**두 세션짜리 순환만 재현했다.** 세 개 이상이 고리를 이루는 데드락도 같은 방식으로 감지되고, `DETAIL`에 줄이 그만큼 늘어난다. 원인 추적은 그만큼 어려워진다.

**자기 자신과의 데드락은 감지되지 않는 경우가 있다.** `REQUIRES_NEW`로 연 안쪽 트랜잭션이 바깥이 잠근 행을 잠그는 형태([전파 속성 글](/posts/transactional-propagation/)에서 다룬 경우)는 서로 다른 커넥션이라 감지된다. 반면 커넥션 풀이 말라서 안쪽 트랜잭션이 커넥션을 못 받고 기다리는 것은 데이터베이스 밖의 대기라 락 그래프에 나타나지 않는다. 그쪽은 무한정 걸린다.

**`deadlock_timeout`을 줄이면 감지가 빨라지지 않는다.** 정확히는 빨라지지만, 데드락이 아닌 평범한 대기에서도 순환 탐지가 자주 돌게 된다. 기본 1초는 그 균형점이다.

**측정 규모가 작다.** 행 두 개, 세션 두 개다. 실제 사고는 대개 배치 작업이 수천 행을 순서 없이 잠그는 형태라 순환이 훨씬 복잡하다.

## 언제 쓰고 언제 안 쓰나

**락 순서를 코드로 고정한다.** 가장 확실한 예방이다. 여러 행을 잠가야 하면 정렬해서 잠근다. 이체라면 계좌 id가 작은 쪽부터, 배치라면 `ORDER BY id`로 뽑은 순서대로다. 위 재현에서 순서만 맞추자 데드락이 사라졌다.

**여러 건을 넣을 때도 순서를 맞춘다.** 유니크 키 데드락은 `INSERT` 목록의 순서가 원인이다. 태그나 코드 값처럼 겹칠 수 있는 키를 여러 개 넣는다면 키 순으로 정렬해서 보낸다.

**재시도를 넣는다.** 데드락은 SQLSTATE `40P01`이고, 이 에러로 죽은 트랜잭션은 다시 실행하면 대체로 성공한다. 상대가 이미 끝났기 때문이다. 재시도 대상 에러 목록에 직렬화 실패(`40001`)도 함께 넣는다.

**`lock_timeout`은 대기 상한이 필요할 때 건다.** 데드락 예방은 아니다. API 응답처럼 정해진 시간 안에 끝나야 하는 경로에서, 락 대기가 무한정 길어지는 것을 막는 용도다. 값은 그 경로의 허용 응답 시간에서 정한다.

**터졌으면 서버 로그를 본다.** 클라이언트 에러에는 상대 문장이 없다. `DETAIL`의 `Process N: ...` 두 줄이 어느 쿼리 짝이 부딪혔는지 알려주고, 그것 없이는 순서를 고칠 지점을 찾기 어렵다. `pg_stat_database.deadlocks`로 빈도를 먼저 확인한다.

## 참고

- [PostgreSQL — Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- [PostgreSQL — Deadlocks](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-DEADLOCKS)
- [PostgreSQL — pg_locks](https://www.postgresql.org/docs/current/view-pg-locks.html)
- [PostgreSQL — PostgreSQL Error Codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
- [PostgreSQL — Lock Management (`deadlock_timeout`)](https://www.postgresql.org/docs/current/runtime-config-locks.html)
- [PostgreSQL — Client Connection Defaults (`lock_timeout`)](https://www.postgresql.org/docs/current/runtime-config-client.html)
