-- 죽은 튜플과 테이블 팽창 실험.
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/vacuum-and-table-bloat/setup.sql

SELECT version();

DROP DATABASE IF EXISTS "vacuum-and-table-bloat";
CREATE DATABASE "vacuum-and-table-bloat";
\c "vacuum-and-table-bloat"

CREATE EXTENSION pgstattuple;

-- autovacuum이 중간에 끼어들면 같은 스크립트가 다른 숫자를 낸다.
CREATE TABLE acct (
  id     int PRIMARY KEY,
  owner  text NOT NULL,
  amount int  NOT NULL
) WITH (autovacuum_enabled = off);

INSERT INTO acct
SELECT g, 'owner-' || g, g % 1000
FROM generate_series(1, 200000) g;
CREATE INDEX acct_owner_idx ON acct (owner);
ANALYZE acct;

CREATE VIEW sizes AS
SELECT pg_size_pretty(pg_relation_size('acct')) AS heap,
       pg_size_pretty(pg_relation_size('acct_owner_idx')) AS idx;
CREATE VIEW tup AS
SELECT tuple_count, dead_tuple_count, round(free_percent::numeric, 2) AS free_pct
FROM pgstattuple('acct');

\echo '=== 1. 적재 직후'
SELECT * FROM sizes; SELECT * FROM tup;

\echo '=== 2. 인덱스에 없는 컬럼을 전건 UPDATE'
UPDATE acct SET amount = amount + 1;
SELECT pg_stat_force_next_flush();
SELECT * FROM sizes; SELECT * FROM tup;
SELECT n_tup_upd, n_tup_hot_upd, n_live_tup, n_dead_tup
FROM pg_stat_user_tables WHERE relname = 'acct';

\echo '=== 3. VACUUM'
VACUUM acct;
SELECT * FROM sizes; SELECT * FROM tup;
SELECT avg_leaf_density, leaf_fragmentation FROM pgstatindex('acct_owner_idx');

\echo '=== 4. 비운 자리에 20만 건 더 넣기'
INSERT INTO acct
SELECT g, 'owner-' || g, 0 FROM generate_series(200001, 400000) g;
SELECT * FROM sizes; SELECT * FROM tup;

\echo '=== 5. REINDEX'
REINDEX INDEX acct_owner_idx;
SELECT * FROM sizes;

\echo '=== 6. 잘라내기: 어느 페이지가 비었느냐가 정한다'
CREATE TABLE trunc (id int PRIMARY KEY, pad text NOT NULL)
  WITH (autovacuum_enabled = off);
INSERT INTO trunc SELECT g, repeat('x', 20) FROM generate_series(1, 200000) g;
SELECT pg_relation_size('trunc') / 8192 AS pages;

\echo '--- 앞쪽 500페이지를 비우고 VACUUM'
DELETE FROM trunc WHERE (ctid::text::point)[0] < 500;
VACUUM trunc;
SELECT pg_relation_size('trunc') / 8192 AS pages,
       round(free_percent::numeric, 2) AS free_pct FROM pgstattuple('trunc');

\echo '--- 뒤쪽 500페이지를 비우고 VACUUM'
DELETE FROM trunc WHERE (ctid::text::point)[0] >= 583;
VACUUM trunc;
SELECT pg_relation_size('trunc') / 8192 AS pages,
       round(free_percent::numeric, 2) AS free_pct FROM pgstattuple('trunc');

\echo '=== 7. VACUUM FULL'
VACUUM FULL trunc;
SELECT pg_relation_size('trunc') / 8192 AS pages,
       round(free_percent::numeric, 2) AS free_pct FROM pgstattuple('trunc');

\echo '=== 8. fillfactor와 HOT'
CREATE TABLE ff100 (id int PRIMARY KEY, owner text NOT NULL, amount int NOT NULL)
  WITH (autovacuum_enabled = off, fillfactor = 100);
CREATE TABLE ff70  (id int PRIMARY KEY, owner text NOT NULL, amount int NOT NULL)
  WITH (autovacuum_enabled = off, fillfactor = 70);
CREATE TABLE ff70i (id int PRIMARY KEY, owner text NOT NULL, amount int NOT NULL)
  WITH (autovacuum_enabled = off, fillfactor = 70);
INSERT INTO ff100 SELECT g, 'owner-' || g, 0 FROM generate_series(1, 200000) g;
INSERT INTO ff70  SELECT g, 'owner-' || g, 0 FROM generate_series(1, 200000) g;
INSERT INTO ff70i SELECT g, 'owner-' || g, 0 FROM generate_series(1, 200000) g;
CREATE INDEX ff100_owner_idx ON ff100 (owner);
CREATE INDEX ff70_owner_idx  ON ff70  (owner);
CREATE INDEX ff70i_owner_idx ON ff70i (owner);
ANALYZE ff100, ff70, ff70i;

SELECT relname, pg_size_pretty(pg_relation_size(oid)) AS heap_before,
       pg_size_pretty(pg_relation_size(relname || '_owner_idx')) AS owner_idx_before
FROM pg_class WHERE relname IN ('ff100','ff70','ff70i') AND relkind = 'r' ORDER BY relname;

UPDATE ff100 SET amount = amount + 1;      -- 인덱스에 없는 컬럼
UPDATE ff70  SET amount = amount + 1;      -- 인덱스에 없는 컬럼 + 페이지에 여유
UPDATE ff70i SET owner  = owner || 'x';    -- 인덱스에 있는 컬럼
SELECT pg_stat_force_next_flush();

SELECT relname, n_tup_upd, n_tup_hot_upd,
       pg_size_pretty(pg_relation_size(relid)) AS heap_after,
       pg_size_pretty(pg_relation_size(relname || '_owner_idx')) AS owner_idx_after
FROM pg_stat_user_tables WHERE relname IN ('ff100','ff70','ff70i') ORDER BY relname;

SELECT c.relname, i.leaf_pages, round(i.avg_leaf_density::numeric, 1) AS avg_leaf_density
FROM (VALUES ('ff100_owner_idx'), ('ff70_owner_idx'), ('ff70i_owner_idx')) v(n),
     LATERAL pgstatindex(v.n) i, pg_class c
WHERE c.relname = v.n ORDER BY 1;

\echo '=== 9. autovacuum 기준값'
SELECT name, setting FROM pg_settings
WHERE name IN ('autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
               'autovacuum_vacuum_insert_threshold', 'autovacuum_vacuum_insert_scale_factor',
               'autovacuum_naptime', 'vacuum_freeze_min_age')
ORDER BY name;
