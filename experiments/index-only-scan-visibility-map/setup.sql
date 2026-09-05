-- Index Only Scan과 visibility map 실험.
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/index-only-scan-visibility-map/setup.sql

SELECT version();

DROP DATABASE IF EXISTS "index-only-scan-visibility-map";
CREATE DATABASE "index-only-scan-visibility-map";
\c "index-only-scan-visibility-map"

CREATE EXTENSION pg_visibility;

CREATE TABLE ord (
  id          int PRIMARY KEY,
  customer_id int  NOT NULL,
  status      text NOT NULL,
  amount      int  NOT NULL
) WITH (autovacuum_enabled = off);

INSERT INTO ord
SELECT g, g % 5000, CASE WHEN g % 10 = 0 THEN 'FAIL' ELSE 'DONE' END, g % 977
FROM generate_series(1, 500000) g;

CREATE INDEX ord_cust_status_idx ON ord (customer_id, status);
SET max_parallel_workers_per_gather = 0;

\echo '=== 1. ANALYZE만 하고 VACUUM은 안 한 상태'
ANALYZE ord;
SELECT count(*) AS total_pages,
       count(*) FILTER (WHERE all_visible) AS all_visible_pages,
       count(*) FILTER (WHERE all_frozen)  AS all_frozen_pages
FROM pg_visibility_map('ord');
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT customer_id, status FROM ord WHERE customer_id BETWEEN 100 AND 199;

\echo '=== 2. VACUUM 후'
VACUUM ord;
SELECT count(*) AS total_pages,
       count(*) FILTER (WHERE all_visible) AS all_visible_pages,
       count(*) FILTER (WHERE all_frozen)  AS all_frozen_pages
FROM pg_visibility_map('ord');
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT customer_id, status FROM ord WHERE customer_id BETWEEN 100 AND 199;

\echo '=== 3. 한 행만 UPDATE하면'
UPDATE ord SET amount = amount + 1 WHERE id = 1;
SELECT count(*) FILTER (WHERE all_visible) AS all_visible_pages FROM pg_visibility_map('ord');
-- 표시가 풀린 블록이 어디인지, 갱신한 행이 어디로 갔는지.
SELECT blkno FROM pg_visibility_map('ord') WHERE NOT all_visible ORDER BY blkno;
SELECT id, ctid FROM ord WHERE id = 1;
-- 0번 블록에 담긴 id 범위. Heap Fetches가 몇이어야 하는지 여기서 나온다.
SELECT min(id) AS min_id, max(id) AS max_id, count(*) AS rows_in_block0
FROM ord WHERE (ctid::text::point)[0] = 0;
SELECT count(*) AS matching_rows_in_block0
FROM ord WHERE (ctid::text::point)[0] = 0 AND customer_id BETWEEN 100 AND 199;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT customer_id, status FROM ord WHERE customer_id BETWEEN 100 AND 199;

\echo '=== 4. 인덱스에 없는 컬럼을 하나 넣으면'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT customer_id, status, amount FROM ord WHERE customer_id BETWEEN 100 AND 199;

\echo '=== 5. INCLUDE로 amount를 붙이면'
CREATE INDEX ord_cust_status_inc_idx ON ord (customer_id, status) INCLUDE (amount);
VACUUM ANALYZE ord;
SELECT count(*) FILTER (WHERE all_visible) AS all_visible_pages,
       count(*) FILTER (WHERE NOT all_visible) AS not_all_visible_pages
FROM pg_visibility_map('ord');
SELECT blkno FROM pg_visibility_map('ord') WHERE NOT all_visible ORDER BY blkno;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT customer_id, status, amount FROM ord WHERE customer_id BETWEEN 100 AND 199;

\echo '=== 6. INCLUDE 컬럼은 조건에 쓸 수 없다'
EXPLAIN (COSTS OFF)
SELECT customer_id FROM ord WHERE customer_id BETWEEN 100 AND 199 AND amount = 5;

\echo '=== 7. 키에 넣은 인덱스와 크기 비교'
CREATE INDEX ord_cust_status_amount_idx ON ord (customer_id, status, amount);
SELECT relname, pg_relation_size(oid) AS bytes, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname LIKE 'ord_cust%' ORDER BY pg_relation_size(oid);
EXPLAIN (COSTS OFF)
SELECT customer_id FROM ord WHERE customer_id BETWEEN 100 AND 199 AND amount = 5;

\echo '=== 8. visibility map 파일 크기'
SELECT pg_size_pretty(pg_relation_size('ord')) AS heap,
       pg_size_pretty(pg_relation_size('ord', 'vm')) AS vm,
       pg_size_pretty(pg_relation_size('ord', 'fsm')) AS fsm;

\echo '=== 9. 3672 kB의 정체는 중복 제거다'
-- 같은 두 컬럼 인덱스를 중복 제거만 끄고 다시 만든다.
CREATE INDEX ord_cust_status_nodedup ON ord (customer_id, status)
  WITH (deduplicate_items = off);
SELECT relname, pg_relation_size(oid) AS bytes, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname LIKE 'ord_cust%' ORDER BY pg_relation_size(oid);
