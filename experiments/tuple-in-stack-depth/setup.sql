-- (a, b) IN ((..), (..)) 튜플 목록이 max_stack_depth를 넘기는 과정을 재현한다.
--
--   docker compose -f experiments/compose.yml exec -T postgres psql -U postgres \
--     < experiments/tuple-in-stack-depth/setup.sql
--
-- 튜플 목록은 \gexec로 생성한다. 목록을 직접 적으면 파일이 수백 KB가 된다.

\set ON_ERROR_STOP off

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

\echo '=== 1. 복합키 IN, 튜플 5,000개 ==='
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ','))
FROM generate_series(1, 5000) i \gexec

\echo '=== 2. 복합키 IN, 튜플 10,000개 ==='
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ','))
FROM generate_series(1, 10000) i \gexec

\echo '=== 3. 단일 컬럼 IN, 값 10,000개 ==='
SELECT format('SELECT count(*) FROM order_item WHERE order_id IN (%s);',
              string_agg(i::text, ','))
FROM generate_series(1, 10000) i \gexec

\echo '=== 4. OR 체인 10,000개 ==='
SELECT format('SELECT count(*) FROM order_item WHERE %s;',
              string_agg(format('(order_id = %s AND line_no = 1)', i), ' OR '))
FROM generate_series(1, 10000) i \gexec

\echo '=== 5. IN (VALUES ...), 튜플 10,000개 ==='
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
              string_agg(format('(%s,1)', i), ','))
FROM generate_series(1, 10000) i \gexec

\echo '=== 6. IN (VALUES ...), 튜플 100,000개 ==='
SELECT format('SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (VALUES %s);',
              string_agg(format('(%s,1)', i), ','))
FROM generate_series(1, 100000) i \gexec

-- 아래는 재귀 깊이가 튜플 수에 정비례하는지 확인한다.
-- 계획 수립 시간을 빼려고 PREPARE(파스 분석)까지만 돌린다.
-- 각 설정에서 N개는 통과하고 N+1개는 stack depth limit exceeded가 나야 한다.
-- 한 단계가 쓰는 스택은 빌드에 따라 달라지므로, 다른 빌드에서는 경계도 달라진다.

\echo '=== 7. max_stack_depth별 경계 (PREPARE) ==='

SET max_stack_depth = '1MB';
SELECT format('PREPARE b1 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 3438) i \gexec
SELECT format('PREPARE b2 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 3439) i \gexec

SET max_stack_depth = '2MB';
SELECT format('PREPARE b3 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 6887) i \gexec
SELECT format('PREPARE b4 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 6888) i \gexec

SET max_stack_depth = '4MB';
SELECT format('PREPARE b5 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 13786) i \gexec
SELECT format('PREPARE b6 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 13787) i \gexec

SET max_stack_depth = '6MB';
SELECT format('PREPARE b7 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 20684) i \gexec
SELECT format('PREPARE b8 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 20685) i \gexec

-- ulimit -s 8192kB 환경에서 허용되는 최대치
SET max_stack_depth = '7680kB';
SELECT format('PREPARE b9 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 25858) i \gexec
SELECT format('PREPARE b10 AS SELECT count(*) FROM order_item WHERE (order_id, line_no) IN (%s);',
              string_agg(format('(%s,1)', i), ',')) FROM generate_series(1, 25859) i \gexec

-- 통과한 것만 남는다: b1, b3, b5, b7, b9
SELECT name FROM pg_prepared_statements ORDER BY name;

RESET max_stack_depth;

\echo '=== 8. 컬럼 수를 늘려도 경계는 같다 (2MB) ==='

SET max_stack_depth = '2MB';
SELECT format('PREPARE c1 AS SELECT count(*) FROM order_item WHERE (order_id, line_no, qty) IN (%s);',
              string_agg(format('(%s,1,1)', i), ',')) FROM generate_series(1, 6887) i \gexec
SELECT format('PREPARE c2 AS SELECT count(*) FROM order_item WHERE (order_id, line_no, qty) IN (%s);',
              string_agg(format('(%s,1,1)', i), ',')) FROM generate_series(1, 6888) i \gexec
RESET max_stack_depth;

\echo '=== 9. max_stack_depth는 ulimit -s에서 512kB를 뺀 값을 넘지 못한다 ==='
SET max_stack_depth = '8MB';

\echo '=== 10. 파라미터 타입 추론이 두 모양에서 갈린다 ==='
PREPARE q2 AS SELECT count(*) FROM order_item
 WHERE (order_id, line_no) IN (($1,$2),($3,$4));
SELECT parameter_types FROM pg_prepared_statements WHERE name = 'q2';

PREPARE q3 AS SELECT count(*) FROM order_item
 WHERE (order_id, line_no) IN (VALUES ($1,$2),($3,$4));

PREPARE q4 AS SELECT count(*) FROM order_item
 WHERE (order_id, line_no) IN (VALUES ($1::int,$2::int),($3::int,$4::int));
EXECUTE q4(1, 1, 2, 1);
