-- 역인덱스 파고들기 실험 (PostgreSQL GIN 내부).
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/inverted-index-deep-dive/setup.sql
-- MySQL 쪽은 같은 디렉터리의 setup-mysql.sql.

SELECT version();

DROP DATABASE IF EXISTS "inverted-index-deep-dive";
CREATE DATABASE "inverted-index-deep-dive";
\c "inverted-index-deep-dive"

CREATE EXTENSION pageinspect;

-- autovacuum이 pending list를 대신 비우면 같은 스크립트가 다른 숫자를 낸다.
CREATE TABLE docs (
  id   serial PRIMARY KEY,
  body text
) WITH (autovacuum_enabled = off);

-- common은 전 문서에, rare는 한 문서에만 넣는다. 포스팅 리스트 길이 차이를 만든다.
INSERT INTO docs (body)
SELECT format('common word doc%s topic%s', i, i % 50)
FROM generate_series(1, 200000) i;
UPDATE docs SET body = body || ' zebra' WHERE id = 12345;

CREATE INDEX docs_gin ON docs USING gin (to_tsvector('english', body))
  WITH (fastupdate = on);
ANALYZE docs;

\echo '=== 1. 인덱스 크기와 페이지 수 ==='
SELECT pg_size_pretty(pg_relation_size('docs')) AS heap,
       pg_size_pretty(pg_relation_size('docs_gin')) AS gin_size,
       pg_relation_size('docs_gin') / 8192 AS pages;

-- 색인된 포스팅 개수. 문서 하나당 텀 네 개.
SELECT count(*) AS postings
FROM docs, LATERAL unnest(tsvector_to_array(to_tsvector('english', body))) w;

\echo '=== 2. 메타 페이지 (색인 직후) ==='
SELECT n_pending_pages, n_pending_tuples, n_entry_pages, n_data_pages, n_entries
FROM gin_metapage_info(get_raw_page('docs_gin', 0));

\echo '=== 3. 페이지 종류 분포 ==='
SELECT flags::text, count(*)
FROM generate_series(1, pg_relation_size('docs_gin') / 8192 - 1) blk,
     LATERAL gin_page_opaque_info(get_raw_page('docs_gin', blk))
GROUP BY 1 ORDER BY 2 DESC;

\echo '=== 4. 포스팅 트리 리프 한 장의 압축 상태 ==='
-- 압축하지 않고 담으면 TID 하나에 몇 바이트가 드는지 기준값.
SELECT pg_column_size('(0,1)'::tid) AS tid_bytes;
-- data + leaf + compressed 페이지 하나를 골라 안에 담긴 TID 수와 바이트 수를 본다.
WITH leaf AS (
  SELECT blk
  FROM generate_series(1, pg_relation_size('docs_gin') / 8192 - 1) blk,
       LATERAL gin_page_opaque_info(get_raw_page('docs_gin', blk)) o
  WHERE o.flags @> ARRAY['data','leaf','compressed']
  ORDER BY blk LIMIT 1
)
SELECT (SELECT blk FROM leaf) AS block,
       count(*) AS segments,
       sum(array_length(tids, 1)) AS tids,
       sum(nbytes) AS bytes,
       round(sum(nbytes)::numeric / sum(array_length(tids, 1)), 2) AS bytes_per_tid
FROM gin_leafpage_items(get_raw_page('docs_gin', (SELECT blk FROM leaf)));

\echo '=== 4-2. 포스팅 트리에 담긴 TID 총량 ==='
-- 나머지 포스팅은 엔트리 페이지 안에 인라인으로 들어간다.
SELECT sum(array_length(tids, 1)) AS tids_in_data_pages,
       count(DISTINCT blk) AS compressed_leaf_pages
FROM generate_series(1, pg_relation_size('docs_gin') / 8192 - 1) blk,
     LATERAL gin_page_opaque_info(get_raw_page('docs_gin', blk)) o,
     LATERAL gin_leafpage_items(get_raw_page('docs_gin', blk))
WHERE o.flags @> ARRAY['data','leaf','compressed'];

\echo '=== 5. 검색: 흔한 텀과 드문 텀 ==='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM docs WHERE to_tsvector('english', body) @@ to_tsquery('english', 'common');
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT id FROM docs WHERE to_tsvector('english', body) @@ to_tsquery('english', 'zebra');

\echo '=== 6. INSERT 후 pending list ==='
INSERT INTO docs (body)
SELECT format('common word doc%s topic%s giraffe', i, i % 50)
FROM generate_series(200001, 201000) i;

SELECT n_pending_pages, n_pending_tuples
FROM gin_metapage_info(get_raw_page('docs_gin', 0));

\echo '=== 7. pending list가 있는 상태의 검색 계획 ==='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM docs WHERE to_tsvector('english', body) @@ to_tsquery('english', 'giraffe');

\echo '=== 8. pending list 병합 ==='
SELECT gin_clean_pending_list('docs_gin') AS pages_cleaned;
SELECT n_pending_pages, n_pending_tuples
FROM gin_metapage_info(get_raw_page('docs_gin', 0));

\echo '=== 9. 병합 후 같은 검색 ==='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM docs WHERE to_tsvector('english', body) @@ to_tsquery('english', 'giraffe');
