-- 락의 종류 실험 (MySQL InnoDB). 레코드 락과 갭 락을 본다.
-- docker compose -f experiments/compose.yml exec -T mysql mysql -uroot -plab --table < experiments/lock-types/setup-mysql.sql

SELECT VERSION();

DROP DATABASE IF EXISTS `lock-types`;
CREATE DATABASE `lock-types`;
USE `lock-types`;

CREATE TABLE acct (id INT PRIMARY KEY, balance INT) ENGINE=InnoDB;
INSERT INTO acct VALUES (1, 100), (5, 100), (10, 100);

SELECT @@transaction_isolation;

-- id 2~8 구간에는 5 하나만 있다. 없는 행까지 잠기는지 본다.
BEGIN;
SELECT id FROM acct WHERE id BETWEEN 2 AND 8 FOR UPDATE;

SELECT OBJECT_NAME, INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
FROM performance_schema.data_locks
WHERE OBJECT_NAME = 'acct'
ORDER BY LOCK_TYPE, LOCK_DATA;
COMMIT;

-- 같은 질의를 READ COMMITTED에서. 갭 락이 사라진다.
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT @@transaction_isolation;
BEGIN;
SELECT id FROM acct WHERE id BETWEEN 2 AND 8 FOR UPDATE;

SELECT OBJECT_NAME, INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
FROM performance_schema.data_locks
WHERE OBJECT_NAME = 'acct'
ORDER BY LOCK_TYPE, LOCK_DATA;
COMMIT;
