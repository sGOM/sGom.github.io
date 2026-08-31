---
title: 계층 구조 저장 네 가지를 같은 트리로 재보기
description: Adjacency List·Closure Table·Path Enumeration·Nested Set을 9만 노드 트리 하나에 올려 조회·삽입·이동·저장 공간을 재고, 앞선 네 글이 남긴 조언이 실제로 맞는지 확인한다
pubDate: 2026-08-27
category: "데이터베이스"
tags: ["파고들기", "Database", "PostgreSQL", "계층구조", "성능"]
---

## 전제

- [계층 구조를 부모 참조로 저장하는 Adjacency List](/posts/adjacency-list/)
- [계층 구조를 저장하는 Closure Table](/posts/closure-table/)
- [계층 구조를 문자열로 저장하는 Path Enumeration](/posts/path-enumeration/)
- [계층 구조를 숫자 구간으로 저장하는 Nested Set](/posts/nested-set/)

네 글은 각각 "언제 쓰나"를 남겼다. 이 글은 그 조언들을 같은 데이터 위에서 검증한다.

## 왜 필요한가

앞선 네 글이 남긴 조언은 서로를 측정 없이 가리킨다. Adjacency List 글은 "트리가 깊어 재귀 비용이 부담되면 다른 방식으로 옮기라"고 했고, Closure Table 글은 "이동이 잦다면 Nested Set은 피하라"고 했으며, Nested Set 글은 "조회가 압도적으로 많으면 Nested Set"이라 했고, Path Enumeration 글은 "접두사 매칭은 인덱스를 탄다"고 단언했다. 넷 다 같은 데이터로 나란히 재본 결과는 아니다.

같은 트리를 네 스키마에 동시에 올려두고 같은 질문을 던지면 세 가지가 드러난다. 조언 중 무엇이 맞았는지, 어디서 순위가 뒤집히는지, 그리고 뒤집는 것이 저장 방식 자체인지 플래너의 판단인지다.

## 구조

### 데이터

분기 5, 깊이 8단계(depth 0~7)인 완전 트리를 쓴다. 노드 수는 (5⁸−1)/4 = 97,656개고, 모든 노드가 `name` 컬럼 하나를 페이로드로 갖는다.

완전 트리를 고른 이유는 서브트리 크기가 깊이만으로 결정되어 측정 지점을 크기별로 골라낼 수 있어서다.

| 측정 지점 | depth | 자기 포함 서브트리 크기 |
|---|---|---|
| 노드 2 | 1 | 19,531 (전체의 20%) |
| 노드 782 | 5 | 31 (전체의 0.03%) |
| 노드 97656 | 7 | 1 (리프, 자기 포함 조상 8개) |

### 스키마

네 방식 모두 조상·자손 조회에 필요한 인덱스를 기본 수준으로 갖췄다.

```sql
-- 1. Adjacency List
al (id PK, parent_id, name);            CREATE INDEX ON al (parent_id);

-- 2. Closure Table — 노드 본체는 별도 테이블
ct_node (id PK, name);
ct (ancestor_id, descendant_id, depth); PK (ancestor_id, descendant_id)
                                        CREATE INDEX ON ct (descendant_id, ancestor_id);

-- 3. Path Enumeration — id를 5자리로 0-padding
pe (id PK, path, name);                 CREATE INDEX ON pe (path text_pattern_ops);

-- 4. Nested Set
ns (id PK, lft, rgt, name);             CREATE INDEX ON ns (lft); CREATE INDEX ON ns (rgt);
```

`left`/`right` 대신 `lft`/`rgt`를 쓴다. [`LEFT`와 `RIGHT`는 예약어](https://www.postgresql.org/docs/current/sql-keywords-appendix.html)라 컬럼명으로 그대로 쓰면 문법 오류가 나고, `"left"`처럼 큰따옴표로 감싸야 한다.

### 측정 방법

조회는 `clock_timestamp()`로 감싼 PL/pgSQL 함수에서 20회 실행한 중앙값, 갱신은 서브트랜잭션을 매번 롤백하며 10회 실행한 중앙값이다.

**조회 측정과 플랜 인용은 모두 갱신 측정 이전에, 한 번의 스크립트 실행 안에서 순서대로 뽑았다.** 갱신 벤치마크는 롤백해도 dead tuple을 남기고, 그 결과 힙이 부풀면 같은 조회 쿼리가 다른 플랜을 받는다. 「갱신 뒤에 같은 조회가 빨라지는 경우」에서 다룬다. 다만 표의 ms 값과 `EXPLAIN ANALYZE`의 Execution Time은 실행 횟수가 달라(20회 중앙값 대 단발) 값이 다르다. 플랜은 구조를 보려고 인용하는 것이고, 시간은 표만 본다.

환경은 `postgres:16` 이미지(16.15) 기본 설정이다. `shared_buffers` 128MB, `work_mem` 4MB, 컨테이너에 12코어·7.7GB. 가장 큰 테이블이 32MB라 **데이터가 전부 메모리에 올라간 상태**의 측정값이고, 디스크 I/O가 끼는 규모에서는 결과가 달라진다.

네 방식이 실제로 같은 답을 내는지 먼저 확인했다. 노드 2의 자손 수는 네 방식 모두 19,531이다. 리프의 조상 목록은 재본 방식마다 자기 자신을 포함해 `1, 6, 31, 156, 781, 3906, 19531, 97656`으로 일치한다.

## 직접 확인

### 저장 공간

| | 힙 | 인덱스 | 합계 |
|---|---|---|---|
| Adjacency List | 5.0 MB | 3.2 MB | **8.2 MB** |
| Nested Set | 6.5 MB | 6.3 MB | **13 MB** |
| Path Enumeration | 9.5 MB | 9.1 MB | **19 MB** |
| Closure Table | 36 MB | 34 MB | **70 MB** |

Closure Table은 `ct`(64MB)와 `ct_node`(6.4MB)의 합이다. 관계 행이 756,836개로 노드 수의 7.75배다. 깊이 8단계 트리에서 노드 하나가 평균 7.75개 행을 만든다는 뜻이고, 트리가 깊어지면 이 배수가 그대로 커진다.

### 자손 전체 조회

`(id, name)`을 반환하는 쿼리로 통일했다. Closure Table만 `ct_node`와 조인해야 한다.

| | 큰 서브트리 (19,531행) | 작은 서브트리 (31행) |
|---|---|---|
| Adjacency List | 20.60 ms | 0.16 ms |
| Closure Table | 14.01 ms | 0.17 ms |
| Path Enumeration | 10.04 ms | **0.06 ms** |
| Nested Set | **3.34 ms** | **0.06 ms** |

Closure Table이 1등이 아니다. 같은 서브트리를 조인 없이 `descendant_id`만 반환하도록 따로 재면 2.05ms로 가장 빠르지만, 실제로 필요한 것은 노드의 내용이다. 둘을 나란히 다시 잰 회차에서는 조인을 포함한 쪽이 13.57ms로 6배가 된다.

Adjacency List의 재귀 CTE는 예상대로 가장 느리지만 격차는 6배 정도다. 31행에서는 0.16ms로 실질적 차이가 없다.

### 조상 전체 조회

리프 노드(depth 7)의 조상을 구한다. 자기 자신을 포함해 8행이다.

| | 시간 |
|---|---|
| Adjacency List (재귀 CTE) | 0.10 ms |
| Closure Table | 0.12 ms |
| Path Enumeration — `path` 파싱 후 `IN` | **0.04 ms** |
| Path Enumeration — 역방향 `LIKE` | 12.60 ms |
| Nested Set | 0.05 ms |

역방향 `LIKE`만 세 자릿수 차이로 떨어진다. `WHERE '/00001/…/97656/' LIKE path || '%'`는 비교 대상이 컬럼 값이라 인덱스를 쓸 수 없고 97,656행을 전부 훑는다. [Path Enumeration 글](/posts/path-enumeration/)이 "조상 조회는 애플리케이션에서 파싱하는 방식을 더 많이 쓴다"고 적은 근거가 이 12.60 대 0.04다.

나머지 셋은 8행짜리 조회라 사실상 구분되지 않는다. 깊이 8에서 재귀 8회는 비용이 아니다.

### 직계 자식 조회

가장 흔한 조회인데, 여기서 순위가 완전히 뒤집힌다.

| | 시간 |
|---|---|
| Adjacency List | **0.03 ms** |
| Closure Table (`depth = 1`) | 7.70 ms |
| Path Enumeration (`LIKE '/00001/00002/_____/'`) | 8.71 ms |
| Nested Set | 자기조인 필요, 재지 않았다 |

0.03ms 대 8ms다. `parent_id` 인덱스가 정확히 이 질문을 위해 존재하는 인덱스이기 때문이고, 나머지 둘은 자손 전체를 훑은 뒤 한 단계짜리만 걸러낸다.

Nested Set도 `lft`/`rgt`만으로 직계 자식을 구할 수는 있다. 구간 안에 들어 있으면서 자신을 감싸는 중간 노드가 하나도 없는 노드가 직계 자식이고, `NOT EXISTS` 자기조인으로 쓴다. 다만 구간 안의 19,531행마다 감싸는 노드가 있는지 확인해야 해서 위 표에 나란히 놓을 형태가 아니라 재지 않았다. 실무에서 `depth` 컬럼을 두고 `depth = 부모depth + 1`을 붙이는 것도 그래서다.

### 삽입

깊은 리프(depth 7) 밑에 노드 하나를 매다는 경우다.

| | 시간 | 건드리는 행 |
|---|---|---|
| Adjacency List | **0.02 ms** | 1 |
| Path Enumeration | 0.05 ms | 1 |
| Closure Table | 0.12 ms | 9 |
| Nested Set (트리 **끝**에 삽입) | 0.13 ms | 8 |

여기까지는 넷 다 비슷하다. 그런데 같은 삽입을 트리 **앞쪽**(노드 2 밑)에서 하면 Nested Set만 달라진다.

| Nested Set 삽입 지점 | 시간 | 갱신 행 |
|---|---|---|
| 트리 끝 | 0.13 ms | 8 |
| 트리 앞쪽 | **585.61 ms** | 78,126 |

같은 "노드 하나 추가"가 8행과 78,126행으로 갈린다. 삽입 지점보다 뒤에 있는 모든 노드의 `lft`/`rgt`를 2씩 밀어야 하고, 밀 행 수는 삽입 지점이 앞일수록 많아진다. Nested Set의 삽입 비용은 **삽입 지점 뒤에 남은 노드 수**가 정한다.

### 서브트리 이동

노드 하나를 서브트리째 다른 부모 밑으로 옮긴다.

| | 큰 서브트리 (19,531 노드) | 작은 서브트리 (31 노드) |
|---|---|---|
| Adjacency List | **0.04 ms** (1행) | **0.06 ms** (1행) |
| Path Enumeration | 143.57 ms (19,531행) | 0.34 ms (31행) |
| Closure Table | 356.96 ms (19,531 삭제 + 39,062 삽입) | 1.04 ms |
| Nested Set | 측정하지 않음 | 측정하지 않음 |

Nested Set의 이동은 재지 않았다. 구간을 통째로 옮기고 사이 구간을 메우는 시프트라 삽입과 같은 성질이고, 위의 앞쪽 삽입(78,126행)이 그 하한을 이미 보여준다.

Adjacency List가 압도적이다. `parent_id` 한 칸만 바꾸면 나머지 관계가 따라오기 때문이고, 서브트리 크기와 무관하게 항상 1행이다.

Closure Table의 이동은 두 문장으로 나눠야 한다. 한 문장으로 묶으려고 `WITH del AS (DELETE …) INSERT …` 형태를 쓰면 실패한다.

```
ERROR:  duplicate key value violates unique constraint "ct_pkey"
DETAIL:  Key (ancestor_id, descendant_id)=(1, 2) already exists.
```

data-modifying CTE의 모든 하위 문장은 [같은 스냅샷을 본다](https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-MODIFYING). `INSERT` 쪽에서는 `DELETE`가 지운 행이 아직 살아 있는 것으로 보이고, 옮긴 뒤에도 유지되는 관계(여기서는 루트 1과의 관계)를 다시 넣으려다 PK 충돌이 난다.

## 동작 원리

순위를 뒤집은 요인은 넷이고, 둘은 저장 방식에 내재한 성질이며 둘은 플래너의 판단이다.

### Closure Table의 조인 상대

19,531행 자손 조회의 플랜이다.

```
Hash Join (actual rows=19531)
  Hash Cond: (n.id = ct.descendant_id)
  Buffers: shared hit=586
  ->  Seq Scan on ct_node n (actual rows=97656)      -- 전체 노드를 훑는다
        Buffers: shared hit=528
  ->  Hash (actual rows=19531)
        ->  Index Only Scan using ct_pkey on ct (actual rows=19531)
              Index Cond: (ancestor_id = 2)
              Heap Fetches: 0
              Buffers: shared hit=58
```

`ct` 쪽은 Index Only Scan으로 58블록만 읽고 19,531개 관계를 뽑아낸다. 시간을 쓰는 쪽은 `ct_node` 전체를 훑는 Seq Scan(528블록)이다. id를 손에 쥔 뒤 노드 내용과 맞추는 단계가 남는 것인데, 나머지 세 방식은 이 단계가 없다. 노드 데이터와 계층 정보가 같은 행에 있기 때문이다.

Closure Table의 "조회가 단순 `SELECT` 하나"라는 요약은 **관계 조회**에 대한 말이다. 노드 내용까지 필요하면 조인 한 단계가 항상 붙고, 그 비용이 2.05ms를 13.57ms로 만든다.

직계 자식 조회(7.70ms)에는 문제가 하나 더 겹친다.

```
Hash Join  (cost=… rows=2598) (actual rows=5)
  ->  Seq Scan on ct_node n  (rows=97656) (actual rows=97656)
  ->  Hash (actual rows=5)
        ->  Bitmap Heap Scan on ct  (cost=… rows=2598) (actual rows=5)
              Recheck Cond: (ancestor_id = 2)
              Filter: (depth = 1)
              Rows Removed by Filter: 19526
```

`ancestor_id = 2 AND depth = 1`을 **2,598행으로 추정**했지만 실제는 5행이다. `ancestor_id = 2`로 19,531행을 읽어 19,526행을 버리고, 그 과대 추정이 Hash Join과 `ct_node` Seq Scan까지 부른다.

두 병목을 차례로 걷어내면 이렇게 움직인다.

| 구성 | 시간 |
|---|---|
| 기본 (PK + `descendant_id` 인덱스) | 7.70 ms |
| `(ancestor_id, depth, descendant_id)` 인덱스 추가 | 5.80 ms |
| 위 인덱스 + Nested Loop 강제 | **0.09 ms** |

인덱스만 추가해서는 4분의 1밖에 못 줄인다. 남은 병목이 조인 방식이기 때문이다. 0.09ms는 조인 방식을 세션 설정으로 강제해 얻은 값이라 병목의 위치를 가리키는 진단이지 그대로 쓸 해법은 아니다. 추정이 어긋나 조인 방식이 뒤집히는 과정은 [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/)에서 다룬 것과 같은 구조다. 그리고 이 인덱스 하나를 더하면 `ct`는 64MB에서 87MB로 커진다.

Adjacency List는 같은 질문을 `parent_id` 인덱스 조회 하나로 0.03ms에 끝낸다.

### Path Enumeration의 인덱스는 선택도에 달렸다

[Path Enumeration 글](/posts/path-enumeration/)은 "접두사 매칭(`LIKE 'x%'`)은 인덱스를 탄다"고 적었다. 문법상으로는 맞지만, 탈 수 있다는 것과 타기로 결정한다는 것은 다르다.

같은 형태의 쿼리가 선택도에 따라 다른 플랜을 받는다.

```
-- 전체의 0.03% (31행)
Index Scan using pe_path_idx on pe (actual rows=31)
  Index Cond: ((path ~>=~ '/00001/00002/00007/00032/00157/00782/')
           AND (path ~<~  '/00001/00002/00007/00032/00157/007820'))
  Buffers: shared hit=15

-- 전체의 20% (19,531행)
Seq Scan on pe (actual rows=19531)
  Filter: (path ~~ '/00001/00002/%')
  Rows Removed by Filter: 78125
  Buffers: shared hit=1216
```

31행짜리에서는 `LIKE` 패턴의 고정 접두사를 범위 조건(`~>=~`, `~<~`)으로 바꿔 인덱스를 타고 15블록만 읽는다. 19,531행짜리에서는 인덱스를 아예 쓰지 않고 힙 1,216블록을 전부 훑는다. 결과가 테이블의 20%나 되면, 인덱스로 찾아 힙을 흩어 읽는 비용이 순차 읽기보다 비싸다고 판단한 것이다. `pe.path`의 [correlation](https://www.postgresql.org/docs/current/view-pg-stats.html)은 0.673으로, `path` 순서와 힙의 물리적 순서가 어긋나 있어 흩어 읽기 비용 추정이 높게 잡힌다.

정확한 서술은 "접두사 매칭은 인덱스를 탄다"가 아니라 **"접두사 매칭은 인덱스를 탈 수 있는 형태이고, 실제로 탈지는 선택도가 정한다"**다. 서브트리가 전체의 작은 일부인 트리에서는 앞의 서술대로 동작하고, 루트 근처 서브트리를 조회하면 그렇지 않다.

### Nested Set의 갱신 비용은 위치가 정한다

`lft`/`rgt`는 트리 전체를 하나의 연속된 번호 공간에 매핑한다. 중간에 값 두 개를 끼우려면 그 뒤 번호를 전부 밀어야 하고, 배열 중간에 원소를 삽입하는 것과 같다.

앞쪽 삽입에서 갱신된 78,126행은 전체 97,656행의 80%다. 노드 2가 depth 1이라 그 뒤에 트리 대부분이 있기 때문이다. 반대로 마지막 리프 옆에 끼우면 밀 것이 8행뿐이다.

삽입이 로그 append처럼 항상 트리 끝에서 일어나는 구조라면 Nested Set의 갱신 비용은 무시할 수 있다. 임의 위치에 삽입되는 구조라면 노드 하나 추가에 테이블의 80%가 갱신될 수 있다고 봐야 한다.

### Adjacency List가 느린 이유는 재귀 자체가 아니다

19,531행 재귀 CTE의 플랜이다.

```
CTE Scan on d (actual rows=19531)
  Buffers: shared hit=43070
  CTE d
    ->  Recursive Union (actual rows=19531)
          ->  Index Scan using al_pkey on al (actual rows=1)
          ->  Nested Loop (actual rows=2790 loops=7)
                ->  WorkTable Scan on d d_1 (actual rows=2790 loops=7)
                ->  Index Scan using al_parent_idx on al a (actual rows=1 loops=19531)
                      Buffers: shared hit=43067
```

반복은 7회뿐이다. 깊이가 8단계니 당연하다. 비용은 `loops=19531`에 있다. 노드마다 `al_parent_idx`를 새로 탐색하고, 그 19,531번이 43,070블록을 읽는다. 한 번에 2.2블록씩이다. 같은 결과를 Nested Set은 222블록으로 읽는다.

깊이를 늘려도 반복 횟수만 늘 뿐 이 구조는 그대로다. 재귀 CTE의 비용은 깊이가 아니라 **결과 노드 수**에 붙는다. 그래서 트리가 아무리 깊어도 서브트리가 작으면(31행, 0.16ms) 싸고, 얕아도 서브트리가 크면 비싸다.

### 갱신 뒤에 같은 조회가 빨라지는 경우

갱신 벤치마크를 다 돌린 뒤 자손 전체 조회를 다시 재면 Path Enumeration이 10.04ms에서 5.13ms로 **빨라진다**. 플랜이 Seq Scan에서 Bitmap Heap Scan으로 바뀌었기 때문이다.

```
-- 갱신 벤치마크 후: pe 힙 9.5MB -> 28MB, dead tuple 195,320개
Bitmap Heap Scan on pe (actual rows=19531)
  Heap Blocks: exact=240
  Buffers: shared hit=419
  ->  Bitmap Index Scan on pe_path_idx (actual rows=19531)
```

갱신은 전부 롤백했지만 롤백된 행도 dead tuple로 힙에 남는다. 힙이 3배로 부풀자 Seq Scan 비용 추정이 함께 올라가 인덱스 쪽이 싸졌고, 살아 있는 19,531행은 여전히 240블록에 모여 있어 실제로도 빨랐다. correlation은 0.673으로 그대로다.

읽기 성능이 좋아졌다고 반길 일은 아니다. 같은 쿼리의 플랜이 테이블 팽창 상태에 따라 뒤집힌다는 뜻이고, [배포할 때마다 목록 조회가 120초 걸렸다](/posts/slow-query-after-restart/)에서 본 것처럼 이런 종류의 변수는 반대 방향으로도 움직인다.

## 경계 조건

**완전 트리라는 조건.** 분기 5로 고른 균형 트리다. 한쪽으로 치우친 편향 트리에서는 Closure Table의 저장 공간이 노드 수 제곱에 가까워지고 Nested Set의 앞쪽 삽입은 더 나빠진다. 반대로 한 번에 다루는 서브트리가 수십 행 규모에 그치면 조회 차이 대부분이 없어진다. 31행 자손 조회에서 넷이 0.06~0.17ms로 모였던 것이 그 경우다. 갱신 비용과 저장 공간은 다르다. 삽입 지점이 트리 앞쪽이면 다루는 서브트리 크기와 무관하게 78,126행이 갱신되고, 8.5배 공간 차이도 그대로다. 트리가 얕아도 루트 근처를 통째로 조회하면 결과 행 수는 그대로다.

**전부 메모리에 있는 상태.** 가장 큰 테이블이 32MB라 디스크 I/O가 없다. 디스크에서 읽어야 하는 규모라면 접근 블록 수가 곧 시간이 되고, 인덱스가 큰 Closure Table과 블록을 흩어 읽는 재귀 CTE가 더 불리해진다.

**페이로드가 `name` 하나.** 실제 테이블은 행이 더 크다. 행이 커지면 Closure Table은 관계 테이블 크기는 그대로인데 조인 상대만 커져 조인 비중이 늘고, 나머지 셋은 힙 블록 수가 함께 늘어난다.

**동시성은 재지 않았다.** Nested Set의 대량 `UPDATE`는 그 행들에 락을 건다. 단일 세션 측정값 585ms는 실제로는 그 시간 동안 트리 대부분이 잠긴다는 뜻이기도 하다.

## 언제 쓰고 언제 안 쓰나

측정값을 그대로 옮기면 이렇게 된다.

| | 자손 조회 | 조상 조회 | 직계 자식 | 삽입 | 이동 | 공간 |
|---|---|---|---|---|---|---|
| Adjacency List | 느림 | 빠름 | **최고** | **최고** | **최고** | **최소** |
| Closure Table | 조인 포함 시 보통 | 빠름 | 인덱스+조인 방식까지 손봐야 | 좋음 | 최악 | **최대(8.5배)** |
| Path Enumeration | 선택도 따라 다름 | 파싱하면 최고 | 나쁨 | 좋음 | 나쁨 | 보통 |
| Nested Set | **최고** | 빠름 | 자기조인 또는 `depth` 컬럼 | 위치 따라 최악 | 위치 따라 최악(미측정) | 좋음 |

판단 기준은 넷이다.

**기본값은 Adjacency List다.** 직계 자식·삽입·이동·저장 공간 네 항목에서 1위고, 가장 약한 자손 전체 조회조차 19,531행에서 20.60ms다. 이 값이 문제가 되는 화면이 실제로 있는지부터 확인하는 편이 낫다. 조상 조회는 깊이가 곧 재귀 횟수라 깊이 8이면 0.10ms다. [Adjacency List 글](/posts/adjacency-list/)이 "트리가 깊어 재귀 비용이 부담되면 옮기라"고 한 부분은 기준이 어긋났다. 비용을 정하는 것은 결과 행 수라, 깊다는 것만으로는 옮길 근거가 되지 않는다.

**자손 전체 조회가 병목이고 구조가 거의 안 바뀌면 Nested Set이다.** 3.34ms로 가장 빠르고 공간도 13MB로 적다. 단 삽입·이동이 트리 앞쪽에서 일어나는 순간 585ms가 나오므로, "거의 안 바뀐다"가 정말 사실인지가 전제다.

**경로를 화면에 쓰거나 정렬에 쓰면 Path Enumeration이다.** 브레드크럼과 댓글 정렬은 값 자체가 결과물이라 조회 비용을 따로 낼 필요가 없다. 조상 조회는 `LIKE`로 풀지 말고 `path`를 파싱해 `IN`으로 넘긴다. 12.60ms와 0.04ms가 여기서 갈린다.

**Closure Table은 조회 이득이 조인 비용과 8.5배 공간을 넘을 때만 고른다.** 관계 조회 자체는 2.05ms로 가장 빠르지만 노드 내용을 붙이면 13.57ms가 되고, 이동은 네 방식 중 가장 비싸다. [Closure Table 글](/posts/closure-table/)이 "이동이 잦다면 Nested Set을 피하고 Closure Table이나 Adjacency List"라고 한 부분은 절반만 맞다. 이동이 잦으면 남는 선택지는 Adjacency List뿐이다.

## 참고

- Bill Karwin, *SQL Antipatterns* — "Naive Trees" 장
- [PostgreSQL — Recursive Queries](https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-RECURSIVE)
- [PostgreSQL — Data-Modifying Statements in WITH](https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-MODIFYING)
- [PostgreSQL — Operator Classes (`text_pattern_ops`)](https://www.postgresql.org/docs/current/indexes-opclass.html)
- [PostgreSQL — pg_stats (correlation)](https://www.postgresql.org/docs/current/view-pg-stats.html)
