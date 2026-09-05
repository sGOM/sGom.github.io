-- 코루틴과 @Transactional 실험. DB 쪽 준비만 한다.
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/coroutine-transactional/setup.sql
-- 측정은 같은 디렉터리의 CoroutineTx.kt로 한다.

SELECT version();

DROP DATABASE IF EXISTS "coroutine-transactional";
CREATE DATABASE "coroutine-transactional";
\c "coroutine-transactional"

CREATE TABLE acct (id int PRIMARY KEY, balance int NOT NULL);
INSERT INTO acct VALUES (1, 0), (2, 0), (3, 0);
SELECT * FROM acct ORDER BY id;
