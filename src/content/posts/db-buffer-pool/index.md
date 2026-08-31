---
title: 큰 테이블은 왜 반복해서 읽어도 버퍼 풀에 남지 않는가
description: shared hit과 read를 읽는 법, 그리고 링 버퍼가 스캔 프로세스마다 생긴다는 것을 실측으로 확인한다
pubDate: 2026-08-25
category: "데이터베이스"
tags: ["파고들기", "Database", "PostgreSQL", "성능", "버퍼"]
---

## 전제

버퍼가 요청 횟수를 줄이는 원리는 [자바 I/O 버퍼](/posts/io-buffer-basics/)에서 다뤘다. DBMS의 버퍼 풀도 같은 목적이지만, 여기서는 무엇을 남기고 무엇을 버릴지 고르는 문제가 하나 더 붙는다.

## 왜 필요한가

DBMS는 테이블을 바이트가 아니라 고정 크기 블록 단위로 다룬다. PostgreSQL의 기본 블록 크기는 8192바이트고, 한 행을 읽으려 해도 그 행이 들어 있는 블록을 통째로 가져온다. 디스크에서 블록을 가져오는 비용은 메모리에서 읽는 것보다 자릿수 단위로 크기 때문에, DBMS는 서버 프로세스들이 함께 쓰는 공유 메모리에 블록을 담아둔다. 이 공간이 버퍼 풀이다.

여기까지는 캐시의 상식대로다. 그런데 128MB 버퍼 풀에 37MB짜리 테이블을 세 번 연속으로 읽어도 대부분 캐시되지 않는다. 자리가 부족해서가 아니다. 버퍼 풀은 그러고도 대부분 비어 있다.

## 핵심 개념

| 용어 | 무엇인가 |
|---|---|
| 블록(페이지) | 읽기와 쓰기의 최소 단위. PostgreSQL 기본 8192바이트 |
| 버퍼 풀 | 블록을 담아두는 메모리. 모든 백엔드 프로세스가 함께 쓴다. `shared hit`의 `shared`가 이 공유를 가리킨다 |
| OS 페이지 캐시 | 운영체제가 파일 내용을 담아두는 별도 메모리. 버퍼 풀 아래에 한 층 더 있다 |
| `shared hit` | 요청한 블록이 버퍼 풀에 있었다 |
| `shared read` | 버퍼 풀에 없어서 아래 층에 요청했다 |
| dirty 버퍼 | 메모리에서 수정됐고 아직 디스크에 반영되지 않은 블록 |

| 항목 | PostgreSQL 17 기본값 | 확인 방법 |
|---|---|---|
| 버퍼 풀 크기 | 128MB | `SHOW shared_buffers;` |
| 블록 크기 | 8192바이트 | `SHOW block_size;` |
| 버퍼 개수 | 16384개 | 128MB / 8KB |
| 단일 쿼리가 쓸 수 있다고 가정하는 캐시 크기 | 4GB | `SHOW effective_cache_size;` |

[`effective_cache_size`](https://www.postgresql.org/docs/17/runtime-config-query.html#GUC-EFFECTIVE-CACHE-SIZE)는 메모리를 실제로 잡지 않는다. 버퍼 풀과 OS 페이지 캐시를 합쳐 어느 정도가 캐시될 것 같은지 플래너에게 알려주는 값이고, 인덱스 스캔과 순차 스캔 중 무엇을 고를지를 좌우한다.

PostgreSQL이 버퍼 풀에만 의존하지 않는다는 점은 [공식 문서](https://www.postgresql.org/docs/17/runtime-config-resource.html)가 `shared_buffers` 권장값을 설명하며 밝힌다.

> because PostgreSQL also relies on the operating system cache, it is unlikely that an allocation of more than 40% of RAM to `shared_buffers` will work better than a smaller amount

## 겉으로 보이는 것

`EXPLAIN`에 `BUFFERS`를 붙이면 노드마다 블록을 몇 개 어디서 가져왔는지 나온다.

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) SELECT count(*) FROM events;
```

```
 Finalize Aggregate (actual rows=1 loops=1)
   Buffers: shared hit=97 read=4639
   ->  Gather (actual rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=97 read=4639
         ->  Partial Aggregate (actual rows=1 loops=3)
               Buffers: shared hit=97 read=4639
               ->  Parallel Seq Scan on events (actual rows=166667 loops=3)
                     Buffers: shared hit=97 read=4639
 Planning:
   Buffers: shared hit=61
 Planning Time: 0.179 ms
 Execution Time: 17.905 ms
```

같은 `hit=97 read=4639`가 네 번 반복되는 것은 `BUFFERS`가 자식 노드의 사용량을 부모에 누산해 찍기 때문이다. 실제로 블록을 읽은 것은 맨 아래 `Parallel Seq Scan` 하나다.

`hit=97 read=4639`는 4736개 블록 중 97개만 버퍼 풀에 있었다는 뜻이다. `Planning` 아래 숫자는 플래너가 통계와 카탈로그를 읽느라 쓴 블록이라 실행과 따로 센다.

문제는 이 출력이 같은 테이블을 두 번째로 읽은 결과라는 점이다. PostgreSQL 17.11(Docker `postgres:17`, 기본 설정)에서 크기가 다른 두 테이블을 만들고 같은 집계를 세 번씩 돌렸다. 버퍼 풀을 비우려고 측정 전에 컨테이너를 재시작했다.

```sql
CREATE TABLE small  AS SELECT g AS id, md5(g::text) AS payload FROM generate_series(1, 100000) g;

CREATE TABLE events AS SELECT g AS id, md5(g::text) AS payload, now() AS created_at FROM generate_series(1, 500000) g;
CREATE INDEX ON events(id);
VACUUM ANALYZE events;   -- small에는 돌리지 않았다
```

```
 small_blocks | events_blocks | shared_buffers
--------------+---------------+----------------
          896 |          4736 | 128MB
```

```
--- small scan #1 ---   Buffers: shared read=896 dirtied=834
--- small scan #2 ---   Buffers: shared hit=896
--- small scan #3 ---   Buffers: shared hit=896
--- events scan #1 ---  Buffers: shared read=4736
--- events scan #2 ---  Buffers: shared hit=97 read=4639
--- events scan #3 ---  Buffers: shared hit=193 read=4543
```

작은 테이블은 두 번째 조회부터 전부 `hit`이다. 큰 테이블은 세 번을 읽어도 대부분 `read`로 남는다. `hit`은 두 번째와 세 번째 사이에 97에서 193으로 96 늘었다. `small`의 첫 스캔에만 `dirtied=834`가 붙은 것도 눈에 띈다. 읽기만 하는 쿼리인데 834개 블록이 수정됐다.

## 동작 원리

큰 순차 스캔이 버퍼 풀 전체를 자기 블록으로 덮으면, 반복해서 쓰이던 다른 블록이 전부 밀려난다. 한 번 읽고 마는 데이터가 계속 쓰이는 데이터를 쫓아내는 셈이다. PostgreSQL은 이를 막으려고 큰 스캔에 작은 링을 내주고 그 안에서만 블록을 돌려 쓴다. [소스의 README](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/storage/buffer/README)에 크기가 적혀 있다.

> For sequential scans, a 256KB ring is used. That's small enough to fit in L2 cache, which makes transferring pages from OS cache to shared buffer cache efficient.

256KB는 8KB 블록으로 32개다. 스캔이 4736개 블록을 읽어도 링에 걸린 버퍼가 계속 재사용되므로, 스캔이 끝난 뒤 남는 것은 마지막 한 바퀴 정도다. 실측은 여기서 하나가 더 남는데, 「직접 확인」에서 본다.

이 전략을 켜는 기준은 스캔할 블록 수가 버퍼 개수의 4분의 1을 넘는지다. [`heapam.c`의 `initscan`](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/access/heap/heapam.c)에 조건이 있다.

```c
if (!RelationUsesLocalBuffers(scan->rs_base.rs_rd) &&
    scan->rs_nblocks > NBuffers / 4)
{
    allow_strat = (scan->rs_base.rs_flags & SO_ALLOW_STRAT) != 0;
    allow_sync = (scan->rs_base.rs_flags & SO_ALLOW_SYNC) != 0;
}
else
    allow_strat = allow_sync = false;

if (allow_strat)
{
    /* During a rescan, keep the previous strategy object. */
    if (scan->rs_strategy == NULL)
        scan->rs_strategy = GetAccessStrategy(BAS_BULKREAD);
}
```

크기 조건이 `allow_strat`을 켜고, 그 플래그가 `BAS_BULKREAD` 전략을 잡는다. 링의 실체가 이 전략 객체다.

`NBuffers`가 16384이므로 경계는 4096블록이다. `small`은 896블록이라 아래이고 `events`는 4736블록이라 위다. 두 값 모두 `pg_relation_size(...)/8192`로 센 main fork 블록 수이고, 조건이 보는 `rs_nblocks`도 같은 기준이다.

이 분기는 링 버퍼만 켜는 것이 아니라 동기 스캔도 함께 켠다. 동기 스캔은 이미 같은 테이블을 읽는 중인 스캔이 있으면 그 위치에서 시작해 읽기를 공유하는 기능이고, 여기서는 다루지 않는다.

병렬 스캔에서도 링을 정하는 자리는 `initscan`이다. 병렬 스캔 초기화를 맡는 [`table_block_parallelscan_initialize`](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/access/table/tableam.c)가 공유 상태로 정하는 것은 동기 스캔 여부뿐이다.

```c
/* compare phs_syncscan initialization to similar logic in initscan */
bpscan->base.phs_syncscan = synchronize_seqscans &&
    !RelationUsesLocalBuffers(rel) &&
    bpscan->phs_nblocks > NBuffers / 4;
```

링은 리더와 워커가 각자 자기 `initscan`을 거치며 따로 잡는다. 프로세스가 셋이면 링도 셋이라는 뜻이다.

## 직접 확인

링이 32개라면 앞의 측정에서 증가폭이 96이었던 것이 설명되지 않는다. 96은 32의 세 배다. 실행계획에 `Workers Launched: 2`가 있었으니 리더까지 세 프로세스가 스캔에 참여했고, 앞 절의 코드대로라면 링도 셋이어야 한다.

프로세스 수를 바꿔 확인한다. 두 측정 모두 컨테이너를 재시작해 버퍼 풀을 비운 뒤 `events`를 한 번만 읽었다.

```sql
CREATE EXTENSION pg_buffercache;

SET max_parallel_workers_per_gather = 0;   -- 병렬 ON으로 재려면 이 줄을 뺀다
SELECT count(*) FROM events;

SELECT b.relforknumber, count(*)
FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE c.relname = 'events'
  AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY 1;
```

병렬을 끄면 스캔 프로세스가 하나다.

```
 relforknumber | count
---------------+-------
             0 |    33
```

기본 설정 그대로 두면 리더와 워커 둘, 셋이 된다.

```
 relforknumber | count
---------------+-------
             0 |    97
```

프로세스 하나면 33개, 셋이면 97개다. 32와 96에 각각 하나씩 더한 값이라, 링 크기 곱하기 프로세스 수에 상수 1이 붙는 꼴이다. 링은 스캔 하나가 아니라 스캔을 수행하는 프로세스마다 생긴다. 세 번 읽었을 때 289개가 남은 것도 97에 96을 두 번 더한 값이다.

남은 하나가 무엇인지는 블록 번호를 보면 갈린다. 병렬을 끈 쪽, 즉 33개가 남은 실행에서 봤다.

```sql
SELECT min(b.relblocknumber) AS min_blk, max(b.relblocknumber) AS max_blk, count(*)
FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE c.relname = 'events'
  AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database());
```

```
 min_blk | max_blk | count
---------+---------+-------
    4672 |    4735 |    33
```

`events`는 4736블록이므로 마지막 블록 번호가 4735다. 33개 중 32개는 4704부터 4735까지, 링이 마지막으로 채운 한 바퀴다. 나머지 하나인 4672는 그보다 정확히 32 앞선 블록, 즉 직전 바퀴의 첫 블록이다. 그 버퍼만 재사용되지 않고 남았다.

4672는 행이 들어 있는 마지막 블록이기도 하다. 그 뒤 4673번부터 4735번까지는 `VACUUM`이 잘라내지 못하고 남은 빈 페이지다.

```sql
SELECT max(substring(ctid::text from '\((\d+),')::bigint) FROM events;  -- 4672
```

링이 슬롯을 포기하고 새 버퍼로 갈아 끼우는 경로는 셋이다. 그 버퍼가 핀돼 있거나, 다른 백엔드가 만져 `usage_count`가 올랐거나, 수정으로 LSN이 갱신된 경우다. 핀은 스캔이 끝나면 풀리므로 사후 관측으로는 갈릴 수 없고, 실제로 다 읽은 뒤 재보면 33개 모두 `usagecount`가 1이다. 순차 스캔이 읽기를 앞질러 여러 블록을 미리 핀해 둔다는 점을 생각하면 첫 경로가 유력해 보이지만, 이 측정으로 확정할 수는 없다.

버퍼 풀 전체를 보면 이 테이블이 얼마나 적게 차지하는지 드러난다. 아래 둘은 앞의 세 번씩 스캔한 실행이 끝난 시점에 잰 것이다.

```sql
SELECT c.relname, count(*) AS buffers, pg_size_pretty(count(*) * 8192::bigint) AS size
FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname ORDER BY buffers DESC LIMIT 3;
```

```
   relname    | buffers |  size
--------------+---------+---------
 small        |     896 | 7168 kB
 events       |     289 | 2312 kB
 pg_attribute |      42 | 336 kB
```

점유량 상위 세 개다. 896블록짜리 `small`은 통째로 올라와 있고, 4736블록짜리 `events`는 289개만 있다.

빈 버퍼는 따로 센다. `pg_buffercache`에서 `relfilenode`가 비어 있는 행이 아무 블록도 담지 않은 버퍼다.

```sql
SELECT count(*) FILTER (WHERE relfilenode IS NULL) AS empty,
       count(*) FILTER (WHERE relfilenode IS NOT NULL) AS used
FROM pg_buffercache;
```

```
 empty | used
-------+------
 14906 |  1478
```

16384개 중 14906개가 비어 있다. `events`를 통째로 담고도 두 배 넘게 남는 자리를 두고 289개만 올라와 있는 것이다.

## 경계 조건

**`read`는 디스크에서 읽었다는 뜻이 아니다.** 버퍼 풀에 없어서 아래 층에 요청했다는 뜻이고, 그 요청은 OS 페이지 캐시에서 끝났을 수 있다. 위 실험에서 컨테이너 재시작은 버퍼 풀만 비우고 호스트의 페이지 캐시는 그대로 두므로, `events scan #2`는 `read=4639`이면서도 17.9ms로 끝났다. 실제 디스크까지 내려갔는지 보려면 `track_io_timing`을 켜고 `I/O Timings`를 봐야 한다.

**읽기만 하는 쿼리도 블록을 수정한다.** `small`의 첫 스캔에 붙은 `dirtied=834`가 그것이다. 조회가 각 행의 가시성을 판정하면서 그 결과를 블록에 힌트 비트로 적어 두기 때문이다.

`events`에 `dirtied`가 없는 것은 이 일을 앞서 `VACUUM`이 해뒀기 때문이다. 같은 문장으로 테이블 두 개를 만들고 한쪽에만 `VACUUM`을 돌린 뒤, 재시작하고 각각 한 번씩 읽으면 갈린다.

```sql
CREATE TABLE t_novac AS SELECT g AS id, md5(g::text) AS payload FROM generate_series(1, 100000) g;
CREATE TABLE t_vac   AS SELECT g AS id, md5(g::text) AS payload FROM generate_series(1, 100000) g;
VACUUM ANALYZE t_vac;
```

```
t_novac :  Buffers: shared read=896 dirtied=834
t_vac   :  Buffers: shared read=834
```

`dirtied`가 사라졌고 읽은 블록도 896에서 834로 줄었다. 뒤쪽 빈 페이지를 `VACUUM`이 잘라내기 때문인데, 같은 문장으로 `t_cut`을 하나 더 만들어 앞뒤로 재면 그대로 보인다.

```sql
SELECT pg_relation_size('t_cut')/8192;   -- VACUUM 직전: 896
VACUUM t_cut;
SELECT pg_relation_size('t_cut')/8192;   -- VACUUM 직후: 834
```

정확히 62블록이 잘렸다. `dirtied=834`가 `read=896`보다 62 적었던 것도 같은 62개이고, 그 페이지들에는 힌트 비트를 적을 행이 없다.

절단은 늘 일어나지 않는다. [`vacuumlazy.c`의 `should_attempt_truncation`](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/access/heap/vacuumlazy.c)이 잘라낼 수 있는 페이지가 1000개를 넘거나 전체의 16분의 1을 넘을 때만 시도한다.

```c
#define REL_TRUNCATE_MINIMUM	1000
#define REL_TRUNCATE_FRACTION	16
```

`t_cut`은 62개가 896의 16분의 1인 56을 넘어 잘렸다. 앞의 실험에서 `VACUUM ANALYZE events` 뒤에도 `events`가 4736블록이었던 것은 이 문턱을 넘지 못했기 때문이다. 절단하려면 짧게라도 배타 락이 필요해서, 얻는 것이 적으면 시도하지 않는다.

**모든 페이지를 고치는 스캔에는 링 전략이 듣지 않는다.** 링 안의 버퍼가 수정되어 LSN까지 갱신되면 재사용 전에 WAL을 기록해야 한다. PostgreSQL은 그 대신 그 버퍼를 링에서 빼고 일반 알고리즘으로 다른 버퍼를 채워 넣는다. 같은 README가 이 경우를 짚는다.

> In a scan that modifies every page in the scan, like a bulk UPDATE or DELETE, the buffers in the ring will always be dirtied and the ring strategy effectively degrades to the normal strategy.

큰 테이블을 통째로 갱신하는 문장은 버퍼 풀을 밀어낸다는 뜻이다. 힌트 비트 기록은 데이터 체크섬과 `wal_log_hints`가 모두 꺼진 기본 설정에서는 LSN을 건드리지 않아 여기 해당하지 않는다. 위 실험에서 링을 쓴 `events` 스캔은 `VACUUM`이 힌트 비트를 미리 써 둬서 그마저 쓸 일이 없었다.

**버퍼 풀 히트율이 높다고 쿼리가 빠른 것은 아니다.** 히트율은 요청한 블록 중 몇 개가 메모리에 있었는지일 뿐, 블록을 몇 개 요청했는지는 말하지 않는다. 인덱스가 없어 100만 블록을 읽는 쿼리는 히트율 100%여도 느리다. 느린 쿼리를 볼 때는 히트율보다 블록 총량을 먼저 본다.

## 대안과 트레이드오프

전체 스캔이 캐시를 밀어내는 문제는 PostgreSQL과 InnoDB가 모두 다루는데, 해법이 갈린다.

| | PostgreSQL | MySQL InnoDB |
|---|---|---|
| 설정 이름 | `shared_buffers` | `innodb_buffer_pool_size` |
| 기본 크기 | 128MB | [128MB](https://dev.mysql.com/doc/refman/8.4/en/innodb-parameters.html#sysvar_innodb_buffer_pool_size) |
| 스캔 대응 | 큰 스캔에 256KB 링을 할당해 격리 | LRU 리스트를 young과 old로 나눠 중간에 삽입 |
| 새 블록의 위치 | 링 안에서 순환 | old 서브리스트의 머리 |

InnoDB는 [버퍼 풀의 3/8을 old 서브리스트로 두고](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html), 읽어온 블록을 리스트 머리가 아니라 중간에 넣는다. 한 번 읽고 마는 블록은 young으로 올라가기 전에 밀려나므로 자주 쓰는 블록이 살아남는다.

두 방식은 반복 접근한 블록을 승격시키는가에서 갈린다. InnoDB는 old 서브리스트에 있는 블록이 다시 접근되면 young으로 올려 캐시에 남긴다(`innodb_old_blocks_time`으로 이 승격을 지연시킬 수 있다).

PostgreSQL에는 이에 해당하는 단계가 없다. 링 슬롯을 재사용하기 전에 검사는 한다. [`GetBufferFromRing`](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/storage/buffer/freelist.c)은 그 버퍼가 핀돼 있거나 `usage_count`가 1을 넘으면 재사용을 포기하고 `NULL`을 돌려주며, 호출자는 일반 알고리즘으로 새 버퍼를 받아 링 슬롯을 채운다.

> A higher usage_count indicates someone else has touched the buffer, so we shouldn't re-use it.

링에서 빠진 블록은 풀에 남지만, 캐시에 남기려고 올려 준 것이 아니라 링이 손을 뗀 것뿐이다. 링이 계속 도는 한 한 바퀴에 남는 양은 링 크기를 넘지 않는다.

측정에서 스캔마다 96블록씩 늘었으니 4736블록을 다 채우려면 같은 스캔을 50회 가까이 돌려야 하는 것으로 계산된다. 큰 테이블을 몇 번 더 읽는다고 버퍼 풀이 데워지지는 않는다는 뜻이다.

## 참고

- [Resource Consumption (PostgreSQL 17)](https://www.postgresql.org/docs/17/runtime-config-resource.html)
- [`pg_buffercache` (PostgreSQL 17)](https://www.postgresql.org/docs/17/pgbuffercache.html)
- [Buffer Manager README (PostgreSQL 17 소스)](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/storage/buffer/README)
- [The InnoDB Buffer Pool (MySQL 8.4)](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html)
