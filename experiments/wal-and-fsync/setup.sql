-- 커밋이 디스크에 남는 순간 실험 (PostgreSQL WAL).
-- docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/wal-and-fsync/setup.sql

SELECT version();

DROP DATABASE IF EXISTS "wal-and-fsync";
CREATE DATABASE "wal-and-fsync";
\c "wal-and-fsync"

CREATE EXTENSION pg_walinspect;
CREATE EXTENSION pg_buffercache;

SELECT current_setting('wal_level')          AS wal_level,
       current_setting('synchronous_commit') AS synchronous_commit,
       current_setting('fsync')              AS fsync,
       current_setting('wal_segment_size')   AS wal_segment_size;

-- autovacuum이 끼어들면 버퍼 상태와 WAL 양이 실행마다 달라진다.
CREATE TABLE acct (
  id     int PRIMARY KEY,
  amount int NOT NULL
) WITH (autovacuum_enabled = off);

INSERT INTO acct SELECT g, 0 FROM generate_series(1, 100) g;
CHECKPOINT;

\echo '=== 1. 커밋 하나가 남긴 WAL의 양 ==='
-- LSN을 psql 변수에 담는다. 보조 테이블을 쓰면 그 INSERT의 WAL이 구간에 섞인다.
SELECT pg_current_wal_lsn() AS before_lsn \gset

BEGIN;
UPDATE acct SET amount = amount + 1000 WHERE id = 1;
COMMIT;

SELECT pg_current_wal_lsn() AS after_lsn \gset

SELECT :'before_lsn'::pg_lsn AS before_lsn,
       :'after_lsn'::pg_lsn  AS after_lsn,
       pg_wal_lsn_diff(:'after_lsn', :'before_lsn') AS bytes;

\echo '=== 2. 그 구간에 실제로 쌓인 WAL 레코드 ==='
SELECT resource_manager, record_type, record_length, fpi_length, description
FROM pg_get_wal_records_info(:'before_lsn', :'after_lsn')
ORDER BY start_lsn;

\echo '=== 3. 커밋 직후: WAL은 디스크에, 데이터 페이지는 아직 메모리에 ==='
SELECT pg_current_wal_lsn()       AS wrote,
       pg_current_wal_flush_lsn() AS flushed,
       pg_current_wal_flush_lsn() >= :'after_lsn'::pg_lsn AS commit_is_on_disk;

SELECT relblocknumber, isdirty
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('acct')
  AND reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY relblocknumber;

\echo '=== 4. 체크포인트 뒤 ==='
CHECKPOINT;
SELECT relblocknumber, isdirty
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('acct')
  AND reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY relblocknumber;

\echo '=== 5. synchronous_commit = on: 커밋 1000번 ==='
SELECT pg_stat_reset_shared('wal');
SET synchronous_commit = on;
SELECT pg_current_wal_lsn() AS on_start \gset
SELECT clock_timestamp() AS t0 \gset
SELECT format('UPDATE acct SET amount = amount + 1 WHERE id = %s;', 1 + g % 100)
FROM generate_series(1, 1000) g \gexec
SELECT round((extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000)::numeric, 1) AS elapsed_ms;
SELECT pg_stat_force_next_flush();
SELECT wal_records, wal_fpi, wal_bytes, wal_write, wal_sync FROM pg_stat_wal;

SELECT pg_current_wal_lsn() AS on_end \gset
SELECT record_type, count(*), sum(record_length) AS bytes, sum(fpi_length) AS fpi_bytes
FROM pg_get_wal_records_info(:'on_start', :'on_end')
GROUP BY record_type ORDER BY 2 DESC;

\echo '=== 6. synchronous_commit = off: 같은 커밋 1000번 ==='
SELECT pg_stat_reset_shared('wal');
SET synchronous_commit = off;
SELECT pg_current_wal_lsn() AS off_start \gset
SELECT clock_timestamp() AS t0 \gset
SELECT format('UPDATE acct SET amount = amount + 1 WHERE id = %s;', 1 + g % 100)
FROM generate_series(1, 1000) g \gexec
SELECT round((extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000)::numeric, 1) AS elapsed_ms;
SELECT pg_stat_force_next_flush();
SELECT wal_records, wal_fpi, wal_bytes, wal_write, wal_sync FROM pg_stat_wal;
RESET synchronous_commit;
-- 커밋은 이미 리턴했는데 그 WAL이 아직 디스크에 없는 양.
-- 이 구간은 pg_get_wal_records_info로 읽지 못한다. 아직 flush되지 않았기 때문이다.
SELECT pg_current_wal_lsn()   AS write_lsn,
       pg_current_wal_flush_lsn() AS flush_lsn,
       pg_wal_lsn_diff(pg_current_wal_lsn(), pg_current_wal_flush_lsn()) AS not_yet_flushed_bytes;
