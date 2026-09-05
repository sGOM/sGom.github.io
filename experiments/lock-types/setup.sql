-- 락의 종류 실험 (PostgreSQL). 문장마다 어떤 락 모드를 잡는지 본다.
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/lock-types/setup.sql
-- 두 세션이 필요한 대기 실험은 같은 디렉터리의 blocking.sh, MySQL 쪽은 setup-mysql.sql.

SELECT version();

DROP DATABASE IF EXISTS "lock-types";
CREATE DATABASE "lock-types";
\c "lock-types"

CREATE TABLE acct (id int PRIMARY KEY, owner text, balance int);
INSERT INTO acct VALUES (1, 'kim', 10000), (2, 'lee', 10000);

-- 자기 백엔드가 쥔 락만 본다. pg_locks 자신을 읽느라 잡는 락도 같이 나온다.
CREATE VIEW my_locks AS
SELECT locktype, relation::regclass::text AS rel, mode, granted
FROM pg_locks
WHERE pid = pg_backend_pid()
ORDER BY locktype, rel, mode;

\echo '=== 1. SELECT ==='
BEGIN;
SELECT balance FROM acct WHERE id = 1;
SELECT * FROM my_locks;
COMMIT;

\echo '=== 2. SELECT ... FOR UPDATE ==='
BEGIN;
SELECT balance FROM acct WHERE id = 1 FOR UPDATE;
SELECT * FROM my_locks;
COMMIT;

\echo '=== 3. UPDATE ==='
BEGIN;
UPDATE acct SET balance = balance - 1 WHERE id = 1;
SELECT * FROM my_locks;
COMMIT;

\echo '=== 4. ALTER TABLE ==='
BEGIN;
ALTER TABLE acct ADD COLUMN memo text;
SELECT * FROM my_locks;
ROLLBACK;
