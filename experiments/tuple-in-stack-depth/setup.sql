-- (a, b) IN ((..), (..)) 튜플 목록이 max_stack_depth를 넘기는 과정을 재현한다.
--
--   psql -U postgres -f experiments/tuple-in-stack-depth/setup.sql
--
-- 경계 튜플 수는 재귀 한 단계가 쓰는 스택에 달려 있고, 그 값은 컴파일러와 최적화
-- 옵션에 좌우된다. 아래 하드코딩된 경계값(3438/6887/13786/20684/25858과 6890)은
-- PostgreSQL 16.13 Ubuntu 빌드(16.13-0ubuntu0.24.04.1, gcc 13.3.0), ulimit -s 8192kB
-- 에서 이분 탐색으로 찾은 값이다. 다른 빌드에서는 경계가 달라지므로, 그 환경에서는
-- N이 통과하고 N+1이 실패하는 결과가 그대로 나오지 않을 수 있다.
-- 9번 블록은 ulimit -s가 8192kB일 때의 값을 쓴다.
--
-- 튜플 목록은 \gexec로 생성한다. 목록을 직접 적으면 파일이 수 MB가 된다.

\set ON_ERROR_STOP off
\timing on

DROP DATABASE IF EXISTS "tuple-in-stack-depth";
CREATE DATABASE "tuple-in-stack-depth";
\c "tuple-in-stack-depth"

SELECT version();
SHOW max_stack_depth;

CREATE TABLE order_item (
    order_id int NOT NULL,
    line_no  int NOT NULL,
    qty      int NOT NULL,
    PRIMARY KEY (order_id, line_no)
);

INSERT INTO order_item
SELECT i, 1, i % 9 + 1 FROM generate_series(1, 200000) i;

ANALYZE order_item;


\echo '=== 1. 에러 전문 (SQLSTATE와 발생 지점) ==='
\set VERBOSITY verbose
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ','))
FROM generate_series(1, 10000) i \gexec
\set VERBOSITY default


\echo '=== 2. SQL 모양별 성공과 실패, 그리고 걸린 시간 ==='
-- 각 모양을 3회 실행한다. \timing이 보고하는 것은 psql과 서버 사이의 왕복 시간이다.
-- 적재 직후 첫 실행은 캐시가 차 있지 않아 느리므로 중앙값을 본다.

\echo '--- 2a. 복합키 IN, 튜플 6,890개 (경계, 통과) ---'
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) AS q
FROM generate_series(1, 6890) i \gset
:q
:q
:q

\echo '--- 2b. 복합키 IN, 튜플 6,891개 (경계, 실패) ---'
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) AS q
FROM generate_series(1, 6891) i \gset
:q
:q
:q

\echo '--- 2c. 복합키 IN, 튜플 10,000개 (실패) ---'
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) AS q
FROM generate_series(1, 10000) i \gset
:q
:q
:q

\echo '--- 2d. 단일 컬럼 IN, 값 100,000개 (통과) ---'
SELECT format('SELECT count(*) FROM order_item WHERE order_id IN (%s);',
              string_agg(i::text, ',')) AS q
FROM generate_series(1, 100000) i \gset
:q
:q
:q

\echo '--- 2e. OR 체인 10,000개 (통과) ---'
SELECT format('SELECT count(*) FROM order_item WHERE %s;',
              string_agg(format('(order_id = %s AND line_no = 1)', i), ' OR ')) AS q
FROM generate_series(1, 10000) i \gset
:q
:q
:q

\echo '--- 2f. IN (VALUES ...), 튜플 10,000개 (통과) ---'
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
              string_agg(format('(%s,1)', i), ',')) AS q
FROM generate_series(1, 10000) i \gset
:q
:q
:q

\echo '--- 2g. IN (VALUES ...), 튜플 100,000개 (통과) ---'
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
              string_agg(format('(%s,1)', i), ',')) AS q
FROM generate_series(1, 100000) i \gset
:q
:q
:q


\echo '=== 3. 같은 SQL의 길이 (길이가 기준이 아님을 확인) ==='

WITH t AS (
    SELECT n, (SELECT string_agg(format('(%s,1)', i), ',') FROM generate_series(1, n) i) AS tup
    FROM (VALUES (6890), (6891), (10000), (100000)) v(n)
)
SELECT '복합키 IN 6,890' AS shape,
       length(format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
                     (SELECT tup FROM t WHERE n = 6890))) AS bytes
UNION ALL SELECT '복합키 IN 6,891',
       length(format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
                     (SELECT tup FROM t WHERE n = 6891)))
UNION ALL SELECT '복합키 IN 10,000',
       length(format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
                     (SELECT tup FROM t WHERE n = 10000)))
UNION ALL SELECT '단일 컬럼 IN 100,000',
       length(format('SELECT count(*) FROM order_item WHERE order_id IN (%s);',
                     (SELECT string_agg(i::text, ',') FROM generate_series(1, 100000) i)))
UNION ALL SELECT 'OR 체인 10,000',
       length(format('SELECT count(*) FROM order_item WHERE %s;',
                     (SELECT string_agg(format('(order_id = %s AND line_no = 1)', i), ' OR ')
                      FROM generate_series(1, 10000) i)))
UNION ALL SELECT 'IN (VALUES) 10,000',
       length(format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
                     (SELECT tup FROM t WHERE n = 10000)))
UNION ALL SELECT 'IN (VALUES) 100,000',
       length(format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
                     (SELECT tup FROM t WHERE n = 100000)));


\echo '=== 4. 스택을 넘기는 순간의 백트레이스 (서버 로그에 남는다) ==='
-- 결과는 클라이언트가 아니라 서버 로그에 BACKTRACE로 찍힌다.
-- expression_tree_walker_impl과 정적 함수 한 쌍이 100프레임을 채운다.
SET backtrace_functions = 'check_stack_depth';
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ','))
FROM generate_series(1, 10000) i \gexec
RESET backtrace_functions;


\echo '=== 5. max_stack_depth를 바꾸면 경계가 정비례로 밀린다 ==='
-- 계획 수립 시간을 빼려고 PREPARE(파스 분석)까지만 돌린다.
-- 각 설정에서 앞의 것은 통과하고 뒤의 것은 stack depth limit exceeded가 난다.

SET max_stack_depth = '1MB';
SELECT format('PREPARE b1 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 3438) i \gexec
SELECT format('PREPARE x1 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 3439) i \gexec

SET max_stack_depth = '2MB';
SELECT format('PREPARE b2 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 6887) i \gexec
SELECT format('PREPARE x2 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 6888) i \gexec

SET max_stack_depth = '4MB';
SELECT format('PREPARE b3 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 13786) i \gexec
SELECT format('PREPARE x3 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 13787) i \gexec

SET max_stack_depth = '6MB';
SELECT format('PREPARE b4 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 20684) i \gexec
SELECT format('PREPARE x4 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 20685) i \gexec

-- ulimit -s가 8192kB일 때 허용되는 최대치
SET max_stack_depth = '7680kB';
SELECT format('PREPARE b5 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 25858) i \gexec
SELECT format('PREPARE x5 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 25859) i \gexec

-- 통과한 것만 남는다: b1 ~ b5. x1 ~ x5는 하나도 없어야 한다.
SELECT name FROM pg_prepared_statements ORDER BY name;
RESET max_stack_depth;


\echo '=== 6. 컬럼 수를 늘려도 경계는 같다 (2MB) ==='
SET max_stack_depth = '2MB';
SELECT format('PREPARE c1 AS SELECT count(*) FROM order_item WHERE (order_id, line_no, qty) IN (%s);',
              string_agg(format('(%s,1,1)', i), ',')) FROM generate_series(1, 6887) i \gexec
SELECT format('PREPARE c2 AS SELECT count(*) FROM order_item WHERE (order_id, line_no, qty) IN (%s);',
              string_agg(format('(%s,1,1)', i), ',')) FROM generate_series(1, 6888) i \gexec
RESET max_stack_depth;


\echo '=== 7. 계획 시간과 실행 시간 (한계 아래인 튜플 5,000개) ==='
-- EXPLAIN은 프레임을 더 쌓으므로 6,890개에서는 EXPLAIN 자체가 실패한다.
-- 두 모양이 모두 통과하는 5,000개에서 비교한다.
-- 계획 본문을 5,000줄 찍지 않으려고 FORMAT JSON으로 받아 시간만 꺼낸다.

DO $$
DECLARE
    tuples text;
    j      json;
    i      int;
BEGIN
    SELECT string_agg(format('(%s,1)', g), ',') INTO tuples FROM generate_series(1, 5000) g;

    FOR i IN 1..3 LOOP
        EXECUTE format('EXPLAIN (ANALYZE, TIMING OFF, FORMAT JSON) '
                       'SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s)',
                       tuples) INTO j;
        RAISE NOTICE '튜플 IN 5,000     계획 % ms  실행 % ms',
                     j->0->>'Planning Time', j->0->>'Execution Time';
    END LOOP;

    FOR i IN 1..3 LOOP
        EXECUTE format('EXPLAIN (ANALYZE, TIMING OFF, FORMAT JSON) '
                       'SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s)',
                       tuples) INTO j;
        RAISE NOTICE 'IN (VALUES) 5,000 계획 % ms  실행 % ms',
                     j->0->>'Planning Time', j->0->>'Execution Time';
    END LOOP;
END $$;


\echo '=== 8. 두 모양의 계획 ==='
EXPLAIN (COSTS OFF) SELECT * FROM order_item WHERE (order_id, line_no) IN ((1,1),(2,1),(3,1));
EXPLAIN (COSTS OFF) SELECT * FROM order_item WHERE (order_id, line_no) IN (VALUES (1,1),(2,1),(3,1));

-- 키가 많아지면 해시 세미조인으로 넘어간다.
SELECT format('EXPLAIN (COSTS OFF) SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 10000) i \gexec


\echo '=== 9. 중복 키가 섞여도 건수가 같다 (세미조인) ==='
SELECT (SELECT count(*) FROM order_item
          WHERE (order_id, line_no) IN ((1,1),(2,1),(3,1),(1,1),(2,1)))        AS tuple_in,
       (SELECT count(*) FROM order_item
          WHERE (order_id, line_no) IN (VALUES (1,1),(2,1),(3,1),(1,1),(2,1))) AS values_in;


\echo '=== 10. max_stack_depth는 ulimit -s에서 512kB를 뺀 값을 넘지 못한다 ==='
SET max_stack_depth = '8MB';


\echo '=== 11. 파라미터 타입 추론이 두 모양에서 갈린다 ==='
PREPARE q2 AS SELECT count(*) FROM order_item
 WHERE (order_id, line_no) IN (($1,$2),($3,$4));
SELECT parameter_types FROM pg_prepared_statements WHERE name = 'q2';

PREPARE q3 AS SELECT count(*) FROM order_item
 WHERE (order_id, line_no) IN (VALUES ($1,$2),($3,$4));

PREPARE q4 AS SELECT count(*) FROM order_item
 WHERE (order_id, line_no) IN (VALUES ($1::int,$2::int),($3::int,$4::int));
EXECUTE q4(1, 1, 2, 1);
