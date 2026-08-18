---
title: 실행계획 노드가 나타나는 조건 — 스캔·조인·정렬 예시로 확인
description: Seq Scan이 Hash Join으로, Nested Loop이 Merge Join으로 바뀌는 조건을 실제 EXPLAIN 결과로 확인한다
pubDate: 2026-08-18
category: "데이터베이스"
tags: ["기본개념", "Database", "PostgreSQL"]
---

## 왜 필요한가

[실행계획 읽기 — 스캔, 조인, rows와 loops](/posts/query-plan-basics/)에서 각 노드가 하는 일과 `cost`·`rows`·`loops` 표기의 의미를 정리했다. 그런데 "이 노드가 왜 하필 지금 나왔는지"는 다른 질문이다. Seq Scan을 보고 무조건 인덱스가 없다고 짐작하거나, Hash Join을 보고 통계가 잘못됐다고 넘겨짚는 경우가 있다.

이 글은 같은 데이터, 비슷한 쿼리에서 조건 하나만 바꿔가며 노드가 바뀌는 지점을 직접 확인한다.

## 핵심 정리

| 노드 | 나타나는 조건 | 이 글의 예시 |
|---|---|---|
| Seq Scan | 조건을 만족하는 행의 비율이 높아 인덱스를 타는 쪽이 오히려 손해일 때 | `status`가 세 값 중 하나 (약 60%) |
| Index Scan | 결과가 소수이고, 힙에서 읽을 위치가 인덱스 항목마다 흩어지지 않을 때 | 기본키 단건 조회 |
| Index Only Scan | 필요한 컬럼이 전부 인덱스에 있어 힙을 읽지 않아도 될 때 | 커버링 인덱스로 두 컬럼만 조회 |
| Bitmap Heap Scan | 결과가 중간 규모라, 인덱스 항목을 모아 힙 접근 순서를 정렬한 뒤 한 번에 읽는 쪽이 유리할 때 | 하루치 시간 범위 조회 |
| Nested Loop | outer 쪽 행이 적고, inner 쪽을 인덱스로 바로 찾을 수 있을 때 | 고객 1명의 주문 조인 |
| Hash Join | 조인 조건에 쓸 인덱스가 없거나, 양쪽이 커서 인덱스 반복 탐색이 더 비쌀 때 | 같은 조인에서 인덱스만 제거 |
| Merge Join | 양쪽을 이미 정렬된 순서로 읽을 수 있고, 결과도 그 순서로 필요할 때 | 전체 조인 + `customer_id` 기준 정렬 |
| Sort | 요청한 정렬 순서를 뒷받침하는 인덱스가 없을 때 | `amount` 기준 정렬 |
| HashAggregate | 그룹 수가 적어 해시 테이블이 메모리에 들어갈 때 | `status`로 그룹핑 |
| GroupAggregate | 그룹 수가 많아 해시 테이블이 버겁거나, 입력이 이미 정렬돼 있을 때 | (강제 재현) `customer_id`로 그룹핑 |

## 예시

PostgreSQL 16에 두 테이블을 두고 재현했다. `customers`는 500행, `orders`는 `customer_id`로 `customers`를 참조하는 30만 행이다.

```sql
CREATE TABLE customers (
    id     serial PRIMARY KEY,
    name   text NOT NULL,
    grade  text NOT NULL          -- BRONZE / SILVER / GOLD / VIP, 균등 분포
);

CREATE TABLE orders (
    id          serial PRIMARY KEY,
    customer_id int NOT NULL REFERENCES customers(id),
    status      text NOT NULL,     -- 5개 값, 균등 분포
    amount      numeric NOT NULL,
    created_at  timestamp NOT NULL -- 2024-01-01 ~ 2025-12-30, 균등 분포
);
```

### 스캔

`status`에 인덱스(`idx_orders_status`)가 있는 상태에서, 조건이 매치하는 비율만 바꿔봤다.

**조건 60%대 → Seq Scan.** 인덱스가 있어도 손대지 않는다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status IN ('PAID', 'PENDING', 'SHIPPED');
```

```
Seq Scan on orders  (cost=0.00..6507.00 rows=180010 width=31) (actual rows=180336 loops=1)
  Filter: (status = ANY ('{PAID,PENDING,SHIPPED}'::text[]))
  Rows Removed by Filter: 119664
  Buffers: shared hit=2382
```

인덱스로 18만 건을 하나씩 찾아 힙을 오가느니, 2,382개 블록을 순서대로 읽는 쪽이 싸다고 본 것이다. 인덱스가 눈에 안 보인다고 없는 게 아니라, 이 조건에서는 쓰지 않는 게 맞는 선택이다.

**기본키 단건 조회 → Index Scan.** 결과가 1행이라 가장 명확한 경우다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE id = 12345;
```

```
Index Scan using orders_pkey on orders  (cost=0.42..8.44 rows=1 width=31) (actual rows=1 loops=1)
  Index Cond: (id = 12345)
  Buffers: shared hit=4
```

**커버링 인덱스로 필요한 컬럼만 조회 → Index Only Scan.** `(customer_id, status)` 인덱스가 있는 상태에서 그 두 컬럼만 뽑으면 힙을 아예 건너뛴다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, status FROM orders WHERE customer_id = 250;
```

```
Index Only Scan using idx_orders_customer_status on orders  (cost=0.42..17.90 rows=770 width=11) (actual rows=632 loops=1)
  Index Cond: (customer_id = 250)
  Heap Fetches: 0
  Buffers: shared hit=1 read=4
```

`Heap Fetches: 0`이 핵심이다. 0보다 크면 visibility map이 갱신되지 않은 행이 있어 결국 힙을 읽었다는 뜻이다.

**하루치 시간 범위 조회(약 0.15%) → Bitmap Heap Scan.** 결과가 442건으로 충분히 적은데도 Index Scan이 아니라 Bitmap Heap Scan이 나온다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
 WHERE created_at >= '2024-06-01' AND created_at < '2024-06-02';
```

```
Bitmap Heap Scan on orders  (cost=12.64..1081.27 rows=411 width=31) (actual rows=442 loops=1)
  Recheck Cond: ((created_at >= '2024-06-01 00:00:00') AND (created_at < '2024-06-02 00:00:00'))
  Heap Blocks: exact=405
  Buffers: shared hit=405 read=4
  ->  Bitmap Index Scan on idx_orders_created_at  (cost=0.00..12.53 rows=411 width=0) (actual rows=442 loops=1)
```

범위 조건은 매치하는 행이 인덱스 안에서는 붙어 있어도, 힙 안에서는 흩어져 있을 수 있다. Bitmap Heap Scan은 인덱스로 힙 블록 위치를 먼저 모으고 정렬해서, 같은 블록을 두 번 읽지 않는다. `enable_bitmapscan`을 꺼야 같은 쿼리에서 순수 Index Scan을 볼 수 있다 — 기본 비용 모델에서는 이 조건에 Bitmap Heap Scan이 근소하게 더 싸다.

### 조인

`customers`와 `orders`를 `customer_id`로 조인한다. 조인 조건은 그대로 두고 인덱스 유무만 바꿨다.

**고객 1명의 주문만 조인 → Nested Loop.** outer(`customers`)가 1행으로 좁혀지고, `(customer_id, status)` 인덱스로 inner를 바로 찾는다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.name, o.id, o.amount
  FROM customers c JOIN orders o ON o.customer_id = c.id
 WHERE c.name = 'customer_250';
```

```
Nested Loop  (cost=9.07..1408.44 rows=600 width=24) (actual rows=632 loops=1)
  Buffers: shared hit=571
  ->  Seq Scan on customers c  (actual rows=1 loops=1)
        Filter: (name = 'customer_250'::text)
  ->  Bitmap Heap Scan on orders o  (actual rows=632 loops=1)
        Recheck Cond: (c.id = customer_id)
        ->  Bitmap Index Scan on idx_orders_customer_status
              Index Cond: (customer_id = c.id)
```

실행 시간은 1.3 ms다.

**같은 쿼리, `customer_id` 인덱스만 제거 → Hash Join.** 쿼리도 데이터도 그대로고 인덱스만 없앴다.

```sql
DROP INDEX idx_orders_customer_status;

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.name, o.id, o.amount
  FROM customers c JOIN orders o ON o.customer_id = c.id
 WHERE c.name = 'customer_250';
```

```
Hash Join  (cost=10.26..6186.44 rows=600 width=24) (actual rows=632 loops=1)
  Hash Cond: (o.customer_id = c.id)
  Buffers: shared hit=2386
  ->  Seq Scan on orders o  (actual rows=300000 loops=1)
  ->  Hash  (actual rows=1 loops=1)
        ->  Seq Scan on customers c  (actual rows=1 loops=1)
              Filter: (name = 'customer_250'::text)
```

`orders`를 인덱스로 좁힐 방법이 없으니 30만 행을 전부 훑어 해시 테이블(`customers` 쪽, 1행)과 맞춰본다. 결과는 같은 632행인데 실행 시간이 1.3 ms에서 40 ms로 늘었다. **"조인 조건에 인덱스가 없다"가 Hash Join을 부르는 가장 흔한 경로**이지만, 인덱스가 있어도 매치되는 행이 많으면(예: VIP 등급 112명, 전체의 22%가 매치) 옵티마이저는 인덱스를 반복 조회하는 것보다 Seq Scan + Hash Join을 택한다. 인덱스 유무보다 "조인 후 남는 행이 얼마나 되는가"가 더 근본적인 기준이다.

**전체 조인 + `customer_id` 기준 정렬 요청 → Merge Join.** `customer_id`에 인덱스(`idx_orders_customer_id`)를 다시 만든 상태에서, 필터 없이 전부 조인하고 `customer_id` 순으로 정렬해 달라고 했다.

```sql
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id, o.id
  FROM customers c JOIN orders o ON o.customer_id = c.id
 ORDER BY c.id;
```

```
Merge Join  (cost=0.70..18855.40 rows=300000 width=8) (actual rows=300000 loops=1)
  Merge Cond: (c.id = o.customer_id)
  Buffers: shared hit=265762 read=257
  ->  Index Only Scan using customers_pkey on customers c  (actual rows=500 loops=1)
        Heap Fetches: 0
  ->  Index Scan using idx_orders_customer_id on orders o  (actual rows=300000 loops=1)
```

양쪽 다 `customer_id`(또는 그와 같은 컬럼인 `id`) 순으로 인덱스를 스캔할 수 있고, 결과도 그 순서가 필요했다. 두 흐름을 나란히 훑으며 맞추면 별도 정렬 없이 끝난다. 정렬 요구가 없었다면 이 규모(30만 행 전부)에서는 Hash Join이 더 쌀 때가 많다 — Merge Join은 "정렬된 두 입력을 그대로 쓸 수 있을 때" 유리하다.

### 정렬과 집계

**정렬 기준 컬럼에 인덱스가 없을 때 → Sort.** `status = 'PAID'`로 6만 건을 골라 `amount` 순으로 정렬했다. `amount`에는 인덱스가 없다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'PAID' ORDER BY amount;
```

```
Sort  (cost=8565.09..8715.04 rows=59980 width=31) (actual rows=60285 loops=1)
  Sort Key: amount
  Sort Method: external merge  Disk: 2488kB
  Buffers: shared hit=2439, temp read=311 written=312
  ->  Bitmap Heap Scan on orders  (actual rows=60285 loops=1)
```

`Sort Method: external merge  Disk: 2488kB`를 보면 `work_mem` 안에 다 안 들어가 디스크에 임시 파일을 썼다는 뜻이다. `Sort Method: quicksort`였다면 메모리 안에서 끝난 경우다.

**그룹 수가 적을 때 → HashAggregate.** `status`는 5개 값뿐이다.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*), sum(amount) FROM orders GROUP BY status;
```

```
HashAggregate  (cost=7632.00..7632.06 rows=5 width=47) (actual rows=5 loops=1)
  Group Key: status
  Batches: 1  Memory Usage: 24kB
  ->  Seq Scan on orders  (actual rows=300000 loops=1)
```

정렬 없이 값마다 해시 버킷을 만들어 바로 집계한다. 그룹이 500개(`customer_id`)여도 메모리에 다 들어가므로 기본값 그대로면 여전히 HashAggregate가 나온다 — 아래는 그 선택을 강제로 끈 결과다.

**HashAggregate를 끄면(`enable_hashagg = off`) → GroupAggregate.** 실무에서 자연 발생하는 경우는 그룹 수가 `work_mem`을 넘어설 만큼 많을 때인데, 이 데이터셋에는 그런 컬럼이 없어 강제로 재현했다.

```sql
SET enable_hashagg = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, count(*) FROM orders GROUP BY customer_id ORDER BY customer_id;
```

```
GroupAggregate  (cost=0.42..7057.42 rows=500 width=12) (actual rows=500 loops=1)
  Group Key: customer_id
  ->  Index Only Scan using idx_orders_customer_id on orders  (actual rows=300000 loops=1)
        Heap Fetches: 0
```

`ORDER BY customer_id`를 걸었는데도 별도 Sort 노드가 없다. 인덱스로 이미 `customer_id` 순서로 읽고 있어서, 그 순서를 그대로 타고 그룹을 묶었기 때문이다. GroupAggregate는 입력이 이미 정렬돼 있을 때 정렬 비용 없이 쓸 수 있다는 게 장점이지만, 정렬된 입력이 없으면 Sort를 먼저 붙여야 해서 대개는 HashAggregate보다 비싸다.

## 혼동하기 쉬운 것

**"결과가 적으면 Index Scan"은 아니다.** 등가 조건의 단건 조회는 Index Scan이 맞지만, 범위 조건은 결과가 수백 건이어도 Bitmap Heap Scan이 흔하다. 인덱스 항목이 가리키는 힙 블록이 흩어져 있으면, 정렬해서 한 번에 읽는 쪽이 항목 하나마다 힙을 오가는 것보다 싸기 때문이다.

**"조인 조건에 인덱스가 없으면 Hash Join"은 방향은 맞지만 유일한 조건은 아니다.** 인덱스가 있어도 조인 후 남는 행이 많으면(위 VIP 예시처럼 전체의 20%대) 인덱스를 반복 조회하는 비용이 Seq Scan 한 번보다 커져 Hash Join이 나온다. 판단 기준은 "인덱스 유무"가 아니라 "inner를 인덱스로 찾는 것이 반복해서 싸게 먹히는가"다.

**GROUP BY가 항상 정렬을 요구하지는 않는다.** HashAggregate는 정렬 없이 그룹을 묶는다. GroupAggregate만 정렬된 입력을 전제로 한다.

## 더 깊이

- [실행계획 읽기 — 스캔, 조인, rows와 loops](/posts/query-plan-basics/) — 이 글에서 다루지 않은 `cost`·`rows`·`loops` 표기의 기본 의미
- [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/) — 통계가 틀렸을 때 Nested Loop이 선택되는 경로

## 참고

- [PostgreSQL Documentation — Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)
- [PostgreSQL Documentation — Index-Only Scans and Covering Indexes](https://www.postgresql.org/docs/current/indexes-index-only-scans.html)
