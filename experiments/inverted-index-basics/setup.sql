-- 역인덱스 기본개념 실험 (PostgreSQL).
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/inverted-index-basics/setup.sql
-- MySQL 쪽은 같은 디렉터리의 setup-mysql.sql.

SELECT version();

DROP DATABASE IF EXISTS "inverted-index-basics";
CREATE DATABASE "inverted-index-basics";
\c "inverted-index-basics"

-- 색인될 값을 눈으로 보는 부분. 문서 세 개는 MySQL 실험과 같은 문장을 쓴다.
SELECT to_tsvector('english', 'The quick brown fox jumps over the lazy dog');
SELECT to_tsvector('english', 'Quick foxes run and run again');
SELECT to_tsvector('english', 'running runs ran runner');
SELECT to_tsvector('simple', '역인덱스는 검색어를 문서로 매핑한다');

-- autovacuum이 중간에 끼어들면 같은 스크립트가 다른 버퍼 수를 낸다.
CREATE TABLE docs (
  id   serial PRIMARY KEY,
  body text
) WITH (autovacuum_enabled = off);

INSERT INTO docs (body)
SELECT format('document number %s about %s and %s',
              i,
              (ARRAY['databases','indexes','networks','compilers','kernels'])[1 + i % 5],
              (ARRAY['postgres','mysql','lucene','sqlite','oracle'])[1 + i % 5])
FROM generate_series(1, 200000) i;

-- 20만 행 중 한 행에만 검색어를 심는다.
UPDATE docs SET body = body || ' inverted index posting list' WHERE id = 12345;

CREATE INDEX docs_body_btree ON docs (body);
CREATE INDEX docs_body_gin   ON docs USING gin (to_tsvector('english', body));
ANALYZE docs;

SELECT pg_size_pretty(pg_relation_size('docs'))            AS heap,
       pg_size_pretty(pg_relation_size('docs_body_btree')) AS btree,
       pg_size_pretty(pg_relation_size('docs_body_gin'))   AS gin;

-- 본문 속 단어: B-tree는 못 쓴다.
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT id FROM docs WHERE body LIKE '%posting%';

-- 같은 조건을 역인덱스로.
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT id FROM docs WHERE to_tsvector('english', body) @@ to_tsquery('english', 'posting');

-- 앞부분 일치는 기본 연산자 클래스로도 안 되고, text_pattern_ops를 줘야 된다.
SELECT datcollate FROM pg_database WHERE datname = current_database();
EXPLAIN (COSTS OFF) SELECT id FROM docs WHERE body LIKE 'document number 12345%';
CREATE INDEX docs_body_pattern ON docs (body text_pattern_ops);
EXPLAIN (COSTS OFF) SELECT id FROM docs WHERE body LIKE 'document number 12345%';
