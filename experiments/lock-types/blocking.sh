#!/usr/bin/env bash
# 락 대기를 세 세션으로 관찰한다.
#   A: 행을 잠그고 붙잡고 있는다
#   B: 같은 행을 고치려다 대기에 걸린다
#   C: 그 순간의 pg_locks와 pg_blocking_pids를 읽는다
#
# bash experiments/lock-types/blocking.sh
# 먼저 experiments/lock-types/setup.sql로 DB를 만들어 둔다.
set -u
C="docker compose -f experiments/compose.yml exec -T postgres psql -U postgres -d lock-types -X"

# A: 행 락을 쥐고 10초 버틴다.
$C -c "BEGIN; SELECT balance FROM acct WHERE id = 1 FOR UPDATE; SELECT pg_sleep(10);" >/dev/null 2>&1 &
sleep 2

# B: 같은 행을 고치려다 막힌다. 8초 뒤 lock_timeout으로 끊긴다.
$C -c "SET lock_timeout = '8s'; BEGIN; UPDATE acct SET balance = balance - 1 WHERE id = 1;" >/dev/null 2>&1 &
sleep 3

# C: 대기 상태를 읽는다.
$C <<'SQL'
SELECT locktype, transactionid, mode, granted, pid
FROM pg_locks
WHERE locktype = 'transactionid'
ORDER BY granted DESC;

SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type, wait_event
FROM pg_stat_activity
WHERE datname = 'lock-types' AND cardinality(pg_blocking_pids(pid)) > 0;
SQL

wait
