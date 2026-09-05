-- @Transactional이 커넥션을 붙잡는 구간 실험. DB 쪽 준비만 한다.
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/transactional-connection-pool/setup.sql
-- 측정은 같은 디렉터리의 PoolHold.java로 한다. 실행법은 그 파일 머리에 있다.

SELECT version();

DROP DATABASE IF EXISTS "transactional-connection-pool";
CREATE DATABASE "transactional-connection-pool";
\c "transactional-connection-pool"

CREATE TABLE acct (id int PRIMARY KEY, balance int NOT NULL);
INSERT INTO acct SELECT g, 0 FROM generate_series(1, 100) g;

SELECT count(*) AS rows FROM acct;
