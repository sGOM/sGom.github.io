-- PreparedStatement의 custom plan / generic plan 전환 실험.
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/prepared-statement-generic-plan/setup.sql

SELECT version();

DROP DATABASE IF EXISTS "prepared-statement-generic-plan";
CREATE DATABASE "prepared-statement-generic-plan";
\c "prepared-statement-generic-plan"

CREATE TABLE ord (
  id     int PRIMARY KEY,
  status text NOT NULL,
  amount int  NOT NULL
);

-- status는 심하게 치우쳐 있다. DONE 99.9%, FAIL 0.1%
INSERT INTO ord
SELECT g,
       CASE WHEN g % 1000 = 0 THEN 'FAIL' ELSE 'DONE' END,
       g % 977
FROM generate_series(1, 1000000) g;

CREATE INDEX ord_status_idx ON ord (status);

-- 병렬 워커가 붙으면 플랜이 길어져 비교가 흐려진다
SET max_parallel_workers_per_gather = 0;
-- 시드 데이터는 결정적이지만 ANALYZE 표본은 실행마다 다르다.
-- 아래 비용 값의 끝자리는 실행마다 달라지고, 두 비용의 대소는 바뀌지 않는다.
VACUUM ANALYZE ord;

\echo '=== 통계'
SELECT n_distinct, most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'ord' AND attname = 'status';

\echo '=== A. 드문 값으로만 실행하면 generic plan을 안 고른다'
PREPARE rare(text) AS SELECT sum(amount) FROM ord WHERE status = $1;
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
\echo '--- 6회차'
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
SELECT name, generic_plans, custom_plans FROM pg_prepared_statements WHERE name = 'rare';

\echo '=== B. 흔한 값으로 다섯 번 실행한 뒤 드문 값을 넣는다'
PREPARE mixed(text) AS SELECT sum(amount) FROM ord WHERE status = $1;
EXPLAIN (COSTS OFF) EXECUTE mixed('DONE');
EXPLAIN (COSTS OFF) EXECUTE mixed('DONE');
EXPLAIN (COSTS OFF) EXECUTE mixed('DONE');
EXPLAIN (COSTS OFF) EXECUTE mixed('DONE');
EXPLAIN (COSTS OFF) EXECUTE mixed('DONE');
SELECT name, generic_plans, custom_plans FROM pg_prepared_statements WHERE name = 'mixed';
\echo '--- 6회차: 드문 값'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) EXECUTE mixed('FAIL');
SELECT name, generic_plans, custom_plans FROM pg_prepared_statements WHERE name = 'mixed';
\echo '--- 7회차: 드문 값'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) EXECUTE mixed('FAIL');
SELECT name, generic_plans, custom_plans FROM pg_prepared_statements WHERE name = 'mixed';

\echo '=== C. 같은 조건을 파라미터 없이'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT sum(amount) FROM ord WHERE status = 'FAIL';

\echo '=== D. plan_cache_mode'
SET plan_cache_mode = force_generic_plan;
EXPLAIN (COSTS OFF) EXECUTE rare('FAIL');
SET plan_cache_mode = force_custom_plan;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) EXECUTE mixed('FAIL');
RESET plan_cache_mode;
SELECT name, generic_plans, custom_plans FROM pg_prepared_statements ORDER BY name;

\echo '=== E. 비용 비교'
SET plan_cache_mode = force_custom_plan;
EXPLAIN EXECUTE mixed('DONE');
SET plan_cache_mode = force_generic_plan;
EXPLAIN EXECUTE mixed('DONE');
RESET plan_cache_mode;

\echo '=== F. 흔한 값을 generic plan으로 실행하면'
SET plan_cache_mode = force_generic_plan;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) EXECUTE mixed('DONE');
SET plan_cache_mode = force_custom_plan;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) EXECUTE mixed('DONE');
RESET plan_cache_mode;
