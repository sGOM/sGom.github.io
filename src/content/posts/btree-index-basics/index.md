---
title: 인덱스 B-tree 기본개념 — 선택도, 카디널리티, 복합 인덱스 순서
description: 인덱스를 걸었는데 안 타거나 탔는데도 안 빨라지는 경우를, 선택도와 카디널리티의 구분과 복합 인덱스의 컬럼 순서 규칙으로 정리한다
pubDate: 2026-08-27
category: "데이터베이스"
tags: ["기본개념", "Database", "PostgreSQL"]
---

## 왜 필요한가

인덱스를 걸었는데 실행계획에 Seq Scan이 나오는 경우가 있다. 반대로 Index Scan이 나오는데도 기대만큼 빨라지지 않는 경우도 있다.

둘 다 인덱스가 고장 난 것이 아니다. 앞은 조건이 남기는 행이 너무 많아서고, 뒤는 인덱스로 찾은 행들이 테이블 여기저기 흩어져 있어서다. 판단 기준은 인덱스의 존재 여부가 아니라 이 글에서 정리할 두 값이다.

## 용어 정리

- **카디널리티(cardinality)**: 컬럼에 들어 있는 서로 다른 값의 개수. 테이블이 가진 성질이라 쿼리와 무관하다.
- **선택도(selectivity)**: 조건 하나가 남길 행의 비율. 같은 컬럼이라도 조건에 따라 달라진다.
- **복합 인덱스(composite index)**: 컬럼 여러 개를 **순서대로** 이어 하나의 키로 만든 인덱스. `(a, b)`와 `(b, a)`는 다른 인덱스다.
- **B-tree**: 키를 정렬해 층으로 나눈 트리. 리프에 키와 행의 물리적 위치가 함께 있어서, 키로 내려간 다음 옆으로 이어 읽으면 범위 조회가 된다.

카디널리티가 높으면 선택도가 좋아지는 경향이 있지만 같은 말은 아니다. 카디널리티 3인 컬럼도 값 분포가 치우쳐 있으면 어떤 값에 대해서는 선택도가 아주 좋다. 아래 예시의 `status`가 그렇다.

## 핵심 정리

조건의 형태가 인덱스를 쓸 수 있는지를 먼저 정한다.

| 조건 형태 | B-tree 인덱스 | 비고 |
|---|---|---|
| `col = 값` | 쓴다 | |
| `col > 값`, `BETWEEN` | 쓴다 | 리프를 이어 읽는다 |
| `col IN (a, b)` | 쓴다 | `= ANY`로 바뀐다 |
| `col IS NULL` | 쓴다 | PostgreSQL은 NULL도 인덱스에 넣는다 |
| `col LIKE '값%'` | 기본 collation에서는 못 쓴다 | `text_pattern_ops`로 만들면 쓴다 |
| `col LIKE '%값'` | 못 쓴다 | 시작점을 모른다 |
| `함수(col) = 값` | 못 쓴다 | 인덱스에는 `col`이 들어 있다. 표현식 인덱스가 따로 필요하다 |

쓸 수 있는 형태여도 실제로 쓸지는 선택도가 정한다.

| 남는 행의 비율 | 옵티마이저의 선택 |
|---|---|
| 낮다 (수 % 이하) | 인덱스로 찾는다 |
| 중간 | 위치만 모아 정렬한 뒤 한 번에 읽는다 (Bitmap) |
| 높다 (수십 % 이상) | 테이블을 순차로 훑는다 (Seq Scan) |

복합 인덱스 `(a, b, c)`가 조건을 받아들이는 규칙은 다음과 같다.

| 조건 | 인덱스 사용 |
|---|---|
| `a = ?` | 쓴다 |
| `a = ? AND b = ?` | 쓴다 |
| `a = ? AND c = ?` | 쓴다. `a`로 좁힌 구간 안에서 `c`를 걸러낸다 |
| `b = ?`, `c = ?` (선두 `a` 없음) | **못 쓴다** |
| `ORDER BY a, b` | 정렬을 생략한다 |
| `ORDER BY b` | 정렬이 필요하다 |

선두 컬럼이 조건에 없으면 인덱스로 찾아 들어갈 지점이 없다. 가운데 컬럼은 없어도 된다.

## 항목별 설명

**카디널리티는 `pg_stats`에 저장된다.** `n_distinct`가 그 값이고, 음수면 "행 수에 대한 비율"이라는 뜻이다. `-1`은 모든 행의 값이 다르다는 의미다. → [PostgreSQL — pg_stats](https://www.postgresql.org/docs/current/view-pg-stats.html)

**선택도는 옵티마이저가 매번 계산한다.** 같은 인덱스라도 조건에 넣는 값에 따라 계산 결과가 달라지고, 그 결과가 Seq Scan과 Index Scan을 가른다. 인덱스가 "가끔 안 탄다"고 느껴지는 이유다.

**복합 인덱스는 정렬된 키를 이어 붙인 것이다.** `(a, b, c)`는 `a`로 먼저 정렬하고 같은 `a` 안에서 `b`로, 같은 `b` 안에서 `c`로 정렬한 하나의 키다. 전화번호부가 성으로 먼저 정렬돼 있는 것과 같아서, 성을 모르면 이름만으로는 찾을 자리가 없다.

**정렬에도 쓰인다.** 인덱스가 이미 그 순서로 정렬돼 있으면 `ORDER BY`가 별도 정렬 단계를 만들지 않는다. 실행계획에서 Sort 노드가 사라지는 것으로 확인한다.

## 예시

`postgres:16`(16.15), 50만 행 주문 테이블이다. `status`는 세 값이 치우쳐 있고 `user_id`는 만 개 근처다.

```sql
CREATE TABLE ord (
  id         bigserial PRIMARY KEY,
  user_id    int    NOT NULL,   -- 1 ~ 10000
  status     text   NOT NULL,   -- DONE 475,000 / PENDING 20,000 / FAILED 5,000
  created_at date   NOT NULL,
  amount     int    NOT NULL
);
CREATE INDEX idx_status ON ord (status);
CREATE INDEX idx_user_status_created ON ord (user_id, status, created_at);
```

### 카디널리티

```
   컬럼     | n_distinct
------------+------------
 amount     |  -0.170318
 created_at |        240
 id         |         -1
 status     |          3
 user_id    |       9951
```

`id`의 `-1`은 50만 행이 전부 다른 값이라는 뜻이고, `amount`의 `-0.170318`은 서로 다른 값이 행 수의 17% 정도라는 뜻이다. `status`는 3, `user_id`는 9951이다. 표본에서 추정한 값이라 실제 10,000과 조금 다르다.

### 같은 인덱스가 값에 따라 다르게 쓰인다

`idx_status` 하나만 두고 조건 값만 바꾼 결과다.

```
-- status = 'FAILED' (5,000행, 1%)
 Index Scan using idx_status on ord (actual time=0.046..2.536 rows=5000 loops=1)
   Index Cond: (status = 'FAILED'::text)
   Buffers: shared hit=3685
 Execution Time: 2.708 ms

-- status = 'PENDING' (20,000행, 4%)
 Index Scan using idx_status on ord (actual time=0.013..5.024 rows=20000 loops=1)
   Index Cond: (status = 'PENDING'::text)
   Buffers: shared hit=3695
 Execution Time: 5.700 ms

-- status = 'DONE' (475,000행, 95%)
 Seq Scan on ord (actual time=0.008..49.442 rows=475000 loops=1)
   Filter: (status = 'DONE'::text)
   Rows Removed by Filter: 25000
   Buffers: shared hit=3677
 Execution Time: 64.042 ms
```

같은 컬럼, 같은 인덱스, 같은 형태의 조건인데 마지막만 Seq Scan이다. 카디널리티는 셋 다 3으로 같고, 달라진 것은 선택도뿐이다.

### 선두 컬럼을 건너뛰면 못 쓴다

`idx_user_status_created`는 `(user_id, status, created_at)` 순서다. 선두인 `user_id` 없이 뒤의 두 컬럼만 조건에 넣었다.

```
-- WHERE status = 'FAILED' AND created_at = '2026-05-01'
 Index Scan using idx_status on ord (actual time=0.039..5.050 rows=417 loops=1)
   Index Cond: (status = 'FAILED'::text)
   Filter: (created_at = '2026-05-01'::date)
   Rows Removed by Filter: 4583
   Buffers: shared hit=3685
```

두 컬럼 다 `idx_user_status_created`에 들어 있는데 그 인덱스는 쓰이지 않았다. 옵티마이저는 `idx_status`로 5,000행을 꺼낸 뒤 4,583행을 버리는 쪽을 골랐다.

### 가운데 컬럼은 건너뛸 수 있다

같은 인덱스에서 이번에는 가운데인 `status`를 뺐다.

```
-- WHERE user_id = 7 AND created_at = '2026-07-19'
 Index Scan using idx_user_status_created on ord (actual time=0.019..0.021 rows=2 loops=1)
   Index Cond: ((user_id = 7) AND (created_at = '2026-07-19'::date))
   Buffers: shared hit=5
```

이번에는 쓰였고 `created_at`이 `Index Cond`에 들어갔다. 선두 `user_id = 7`로 좁혀진 구간이 작아서, 그 안을 훑으며 `created_at`을 맞춰보는 편이 싸다고 판단한 것이다. 블록 5개로 끝났다.

선두 컬럼은 읽기 시작할 지점을 정하고, 뒤 컬럼들은 그 구간을 훑으며 걸러낸다. 선두가 없으면 시작 지점이 없어서 인덱스 전체를 훑어야 하고, 그럴 바에는 다른 인덱스나 Seq Scan이 낫다.

`Index Cond`에 들어갔다고 해서 그 조건이 읽을 구간을 줄여준 것은 아니다. 구간을 정하는 것은 선두부터 끊기지 않고 이어지는 등치 조건까지고, 나머지는 그 구간 안에서 걸러내는 데 쓰인다.

### 정렬 단계가 사라진다

인덱스 순서와 `ORDER BY`가 맞는지에 따라 Sort 노드가 생겼다 없어진다.

```
-- WHERE user_id = 7 ORDER BY status, created_at   (인덱스 순서와 같다)
 Index Scan using idx_user_status_created on ord (actual rows=58 loops=1)
   Index Cond: (user_id = 7)

-- WHERE user_id = 7 ORDER BY created_at           (인덱스 순서와 다르다)
 Sort (actual time=0.066..0.069 rows=58 loops=1)
   Sort Key: created_at
   Sort Method: quicksort  Memory: 28kB
   ->  Index Scan using idx_user_status_created on ord (actual rows=58 loops=1)
         Index Cond: (user_id = 7)
```

`(user_id, status, created_at)` 인덱스는 `user_id = 7` 구간 안에서 이미 `status, created_at` 순으로 정렬돼 있다. 그래서 위쪽은 읽는 순서가 곧 답이고, 아래쪽은 58행을 다시 정렬해야 한다.

행이 58개라 시간 차이는 없다. 정렬 대상이 수만 행이 되고 `work_mem`을 넘기면 디스크 정렬로 넘어가면서 차이가 커진다.

(위 두 계획은 Bitmap 스캔을 꺼서 뽑았다. 58행 규모에서는 옵티마이저가 Bitmap Heap Scan을 고르는데, 그 노드는 순서를 흩뜨려서 어느 쪽이든 Sort가 붙는다.)

### 인덱스만으로 끝내기

조회하는 컬럼이 전부 인덱스 안에 있으면 테이블에 가지 않는다.

```
-- SELECT user_id, status, created_at FROM ord WHERE user_id = 7
 Index Only Scan using idx_user_status_created on ord (actual rows=58 loops=1)
   Index Cond: (user_id = 7)
   Heap Fetches: 0
   Buffers: shared hit=4

-- SELECT * FROM ord WHERE user_id = 7
 Bitmap Heap Scan on ord (actual rows=58 loops=1)
   Recheck Cond: (user_id = 7)
   Heap Blocks: exact=58
   Buffers: shared hit=61
   ->  Bitmap Index Scan on idx_user_status_created (actual rows=58 loops=1)
         Index Cond: (user_id = 7)
         Buffers: shared hit=3
```

같은 58행인데 블록 4개와 61개다. `SELECT *`는 인덱스에 없는 `amount`와 `id`를 가지러 힙 블록 58개를 더 읽는다. 인덱스에서 읽은 양은 양쪽 다 3~4블록으로 같다.

## 혼동하기 쉬운 것

**Index Scan이 나왔다고 테이블을 덜 읽는 것은 아니다.** 위 `status = 'FAILED'`는 5,000행(1%)만 골라냈는데 `Buffers: shared hit=3685`다. Seq Scan이 읽은 3,677블록보다 많다. 5,000행이 테이블 전체에 고르게 흩어져 있어서, 인덱스로 위치를 정확히 알아도 결국 거의 모든 블록을 건드린다. 실행계획에서 노드 이름만 보지 말고 `Buffers`를 함께 봐야 하는 이유다.

**카디널리티가 높은 컬럼을 앞에 두라는 규칙은 반쪽이다.** 실제 기준은 등치(`=`) 조건으로 자주 쓰이는 컬럼을 앞에 두는 것이다. 위 인덱스는 카디널리티 3짜리 `status`를 가운데 두고도 잘 동작한다. 선두 `user_id`가 구간을 충분히 좁혀주기 때문이다. 반대로 카디널리티가 높아도 그 컬럼이 조건에 안 들어오면 선두로서 아무 값이 없다.

**"선두 컬럼이 필요하다"와 "가운데 컬럼은 없어도 된다"는 모순이 아니다.** 선두는 인덱스 안에서 읽기 시작할 지점을 정하고, 나머지는 그 지점부터 이어 읽으며 거르는 조건이다. 시작 지점이 없으면 이어 읽을 곳이 정해지지 않는다.

**인덱스는 조회를 빠르게 하는 대신 쓰기를 느리게 한다.** 위 테이블은 29 MB인데 인덱스 셋이 각각 3408 kB, 14 MB, 11 MB다. `INSERT` 한 번에 인덱스 셋을 모두 갱신하고, 그만큼 디스크에도 더 쓴다.

## 구현체별 차이

| DBMS | 다른 점 |
|---|---|
| PostgreSQL | 힙과 인덱스가 분리돼 있다. Index Only Scan은 visibility map이 최신일 때만 힙을 건너뛰므로 `VACUUM` 상태에 좌우된다 |
| MySQL (InnoDB) | PK가 클러스터드 인덱스라 테이블 자체가 PK 순으로 정렬돼 있다. 보조 인덱스의 리프에는 PK 값이 들어가고, 그 PK로 다시 찾아간다 |
| Oracle | 단일 컬럼 B-tree 인덱스에 NULL만 있는 항목을 넣지 않는다. `IS NULL` 조회에 그 인덱스를 쓸 수 없다 |

접두사 `LIKE`도 갈린다. PostgreSQL은 기본 collation(여기서는 `en_US.utf8`)에서 `LIKE '값%'`에 일반 인덱스를 쓰지 않고, `text_pattern_ops`로 만든 인덱스가 있어야 범위 조건으로 바꿔 탄다. → [PostgreSQL — Operator Classes](https://www.postgresql.org/docs/current/indexes-opclass.html)

## 언제 어떤 것을 쓰나

**어떤 조건으로 조회하는지부터 적는다.** 인덱스는 컬럼이 아니라 쿼리에 맞춰 만든다. `WHERE`에 자주 함께 오는 컬럼들을, 등치 조건으로 쓰이는 것을 앞에 두고 묶는다.

**컬럼 순서는 `(등치 조건, 등치 조건, 범위 조건)` 순으로 둔다.** 읽어야 할 인덱스 구간의 시작과 끝은 선두부터 이어지는 등치 조건이 정한다. 범위 조건이 앞에 오면 그 지점부터 구간이 넓어지고, 뒤 컬럼이 아무리 선택적이어도 그 넓은 구간을 다 읽어야 한다.

**`(a, b)`가 있으면 `(a)`는 따로 만들지 않는다.** 선두 컬럼만 쓰는 조회는 `(a, b)`가 그대로 처리한다. 반대로 `(b)`로 조회한다면 별도 인덱스가 필요하다.

**인덱스를 걸기 전에 선택도를 먼저 본다.** 조건이 테이블의 절반을 남긴다면 인덱스를 만들어도 옵티마이저가 쓰지 않는다. 그 경우 인덱스는 쓰기 비용과 저장 공간만 늘린다.

**계획을 확인한다.** 만든 뒤 `EXPLAIN (ANALYZE, BUFFERS)`로 실제로 쓰이는지, 쓰이면서 블록을 얼마나 읽는지 본다. 읽는 법은 [실행계획 읽기](/posts/query-plan-basics/)에 있다.

## 더 깊이

- [실행계획 읽기 — 스캔, 조인, rows와 loops](/posts/query-plan-basics/)
- [실행계획 노드가 나타나는 조건 — 스캔·조인·정렬 예시로 확인](/posts/query-plan-node-triggers/)
- [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/)

## 참고

- [PostgreSQL — Indexes](https://www.postgresql.org/docs/current/indexes.html)
- [PostgreSQL — Multicolumn Indexes](https://www.postgresql.org/docs/current/indexes-multicolumn.html)
- [PostgreSQL — Index-Only Scans and Covering Indexes](https://www.postgresql.org/docs/current/indexes-index-only-scans.html)
- [PostgreSQL — pg_stats](https://www.postgresql.org/docs/current/view-pg-stats.html)
- [MySQL 8.0 Reference Manual — Clustered and Secondary Indexes](https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html)
