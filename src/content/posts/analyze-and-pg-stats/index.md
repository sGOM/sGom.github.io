---
title: ANALYZE와 통계 정보 — 플래너가 보는 pg_stats 읽기
description: ANALYZE가 표본에서 무엇을 기록하는지, pg_stats의 각 컬럼이 어떤 추정에 쓰이는지, 통계가 맞는데도 추정이 빗나가는 경우를 재현해 정리한다
pubDate: 2026-08-27
category: "데이터베이스"
tags: ["파고들기", "Database", "PostgreSQL"]
---

## 전제

- [실행계획 읽기 — 스캔, 조인, rows와 loops](/posts/query-plan-basics/)
- [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/)

뒤 글은 통계에 없는 값이 어떻게 추정치 1로 무너지는지를 다뤘다. 이 글은 그 통계 자체가 무엇을 담고 있는지, 그리고 통계가 정상일 때 추정이 어디까지 맞는지를 본다.

## 풀리지 않는 질문

"통계를 갱신하라"는 조언은 흔한데, 갱신한 뒤 무엇이 달라졌는지 확인하는 방법은 잘 알려져 있지 않다. `pg_stats`를 열어봐도 배열 두 개와 소수점 숫자들이라 어느 값이 어느 추정에 쓰이는지 바로 보이지 않는다.

확인이 필요한 지점은 셋이다. `ANALYZE`가 실제로 몇 행을 보는지, 그 표본에서 무엇을 기록하는지, 그리고 기록이 정확한데도 추정이 빗나가는 경우가 있는지다.

마지막 것이 실무에서 더 자주 문제가 된다. 통계가 낡아서가 아니라 플래너의 계산 방식 때문에 빗나가는 종류가 따로 있다.

## 구조

### 환경

`postgres:16` 이미지(16.15) 기본 설정이다. 50만 행 주문 테이블을 쓴다.

```sql
CREATE TABLE ord (
  id         bigserial PRIMARY KEY,
  user_id    int    NOT NULL,   -- 1 ~ 10000, 균등
  status     text   NOT NULL,   -- DONE 475,000 / PENDING 20,000 / FAILED 5,000
  created_at date   NOT NULL,   -- 240일에 균등
  amount     int    NOT NULL
);
```

### pg_stats의 컬럼

`ANALYZE`는 결과를 `pg_statistic`에 넣고, 사람이 읽을 수 있게 풀어놓은 뷰가 `pg_stats`다. 이 글에 필요한 것은 여섯이다.

| 컬럼 | 담는 것 | 쓰이는 곳 |
|---|---|---|
| `null_frac` | NULL인 행의 비율 | `IS NULL` 선택도, 다른 선택도의 분모 보정 |
| `avg_width` | 값의 평균 바이트 | 결과 폭 추정, 정렬·해시 메모리 계산 |
| `n_distinct` | 서로 다른 값의 개수. 음수면 행 수에 대한 비율 | MCV에 없는 값의 등가 선택도 |
| `most_common_vals` | 자주 나오는 값 목록(MCV) | 그 값에 대한 등가 선택도 |
| `most_common_freqs` | MCV 각 값의 빈도 | 같음 |
| `histogram_bounds` | MCV를 뺀 나머지를 같은 개수로 나눈 경계값 | 범위 조건 선택도 |
| `correlation` | 값 순서와 물리적 저장 순서의 상관계수 (−1 ~ 1) | 인덱스 스캔의 랜덤 읽기 비용 추정 |

→ [PostgreSQL — pg_stats](https://www.postgresql.org/docs/current/view-pg-stats.html)

## 직접 확인

### ANALYZE는 표본만 본다

`ANALYZE VERBOSE`가 표본 크기를 알려준다.

```
INFO:  analyzing "public.ord"
INFO:  "ord": scanned 3677 of 3677 pages, containing 500000 live rows and 0 dead rows;
       30000 rows in sample, 500000 estimated total rows
```

페이지는 3,677개 전부 읽었는데 표본은 30,000행이다. 표본 크기는 `default_statistics_target` × 300이고 기본값이 100이라 30,000이 된다. 50만 행 중 6%다.

값을 1000으로 올리고 다시 실행하면 표본이 정확히 열 배가 된다.

```
INFO:  "ord": scanned 3677 of 3677 pages, containing 500000 live rows and 0 dead rows;
       300000 rows in sample, 500000 estimated total rows
```

테이블이 커져도 표본 크기는 이 공식이 정한다. 행 수에 비례하지 않는다.

### 기록된 통계

`id`, `user_id`, `status` 세 컬럼의 `pg_stats` 행이다. 배열은 앞부분만 잘랐다.

```
-[ RECORD 1 ]----+------------------------------------------------------------
attname           | id
null_frac         | 0
avg_width         | 8
n_distinct        | -1
most_common_vals  |
histogram_bounds  | {28,5304,10406,15688,20521,25623,30447,35376,40413,45281,...
correlation       | 1

-[ RECORD 2 ]----+------------------------------------------------------------
attname           | user_id
null_frac         | 0
avg_width         | 4
n_distinct        | 9951
most_common_vals  | {2858,9387,1180,4843,7951,2482,3438,6053,6664,7486}
most_common_freqs | {0.0004,0.0004,0.00036666667,0.00036666667,0.00036666667,...
histogram_bounds  | {1,95,201,307,411,514,617,721,829,929,1021,1118,1223,...
correlation       | -0.0007784238

-[ RECORD 3 ]----+------------------------------------------------------------
attname           | status
null_frac         | 0
avg_width         | 5
n_distinct        | 3
most_common_vals  | {DONE,PENDING,FAILED}
most_common_freqs | {0.95053333,0.040733334,0.008733333}
histogram_bounds  |
correlation       | 0.9043482
```

세 행이 각각 다른 것을 보여준다.

`id`는 `n_distinct`가 `-1`이다. 음수는 비율이고 `-1`은 모든 행의 값이 다르다는 뜻이다. 값이 전부 다르니 자주 나오는 값도 없어서 `most_common_vals`가 비었고, 대신 히스토그램만 있다. `correlation`이 정확히 1인 것은 `bigserial`이라 값 순서와 저장 순서가 같기 때문이다.

`status`는 정반대다. 서로 다른 값이 셋뿐이라 MCV가 전부를 담았고, 그래서 히스토그램이 비었다. **MCV가 값을 전부 담으면 히스토그램은 만들지 않는다.** 빈도 `0.95053333`은 실제 비율 0.95와 소수점 넷째 자리에서 갈린다. 표본 30,000행에서 센 값이다.

`user_id`는 둘이 섞여 있다. MCV 10개가 빈도 상위 값을 담고, 나머지를 히스토그램이 받는다. `correlation`이 −0.0008로 0에 가까운 것은 `user_id`를 난수로 넣어 값 순서와 저장 순서에 아무 관계가 없기 때문이다.

### 같은 명령을 두 번 돌리면 값이 달라진다

`user_id`의 실제 서로 다른 값은 10,000개다. 통계는 9,951로 기록했다. 같은 설정으로 `ANALYZE`를 다시 돌리면 이렇게 된다.

| ANALYZE 회차 | `n_distinct` | MCV 개수 | 히스토그램 경계 수 |
|---|---|---|---|
| 1회 (target 100) | 9951 | 10 | 101 |
| 2회 (target 100) | 9939 | 6 | 101 |

같은 데이터, 같은 설정인데 값이 다르다. 표본을 새로 뽑았기 때문이다. MCV 개수까지 10에서 6으로 줄었다. 균등 분포라 "자주 나오는 값"의 경계가 표본마다 흔들린다.

`user_id`의 `statistics` 값만 1000으로 올리면 이렇게 된다.

| | `n_distinct` | MCV 개수 | 히스토그램 경계 수 |
|---|---|---|---|
| target 100 | 9939 | 6 | 101 |
| target 1000 | **10000** | 894 | 1001 |

정확히 10,000이 나왔다. 표본이 30만 행으로 늘면서 서로 다른 값을 거의 다 봤기 때문이다. MCV도 894개, 히스토그램 경계도 1,001개로 늘었다.

대가는 두 가지다. `ANALYZE`가 읽는 표본이 열 배가 되고, 플래너가 매 쿼리마다 훑을 MCV 배열도 길어진다.

### 히스토그램의 범위 추정은 잘 맞는다

MCV에 없는 값의 범위 조건은 히스토그램으로 계산한다. 경계 101개가 표본을 100등분한 것이므로, 조건 구간이 경계 몇 칸에 걸치는지로 비율을 낸다.

```
-- WHERE user_id BETWEEN 1 AND 1000        (전체의 10%)
 Bitmap Heap Scan on ord (cost=1190.74..5579.43 rows=47446) (actual rows=50298)

-- WHERE created_at BETWEEN '2026-01-01' AND '2026-01-31'
 Seq Scan on ord (cost=0.00..11177.00 rows=63762) (actual rows=64603)
```

47,446 대 50,298으로 5.7% 차이, 63,762 대 64,603으로 1.3% 차이다. 통계가 최신이고 분포가 균등하면 범위 추정은 이 정도로 맞는다.

### 통계가 정확한데도 세 배 빗나간다

컬럼이 둘 이상 걸린 조건에서 성질이 달라진다. 지역과 도시처럼 한쪽이 다른 쪽을 결정하는 컬럼 두 개를 만들었다. 27만 행이고 도시는 9개, 지역은 3개이며 도시마다 3만 행씩 정확히 균등하다.

```sql
CREATE TABLE addr (id serial, region text, city text);
-- (수도권: 서울·인천·수원), (영남: 부산·대구·울산), (호남: 광주·전주·목포)
-- 각 조합 30,000행
```

```
-- WHERE region = '영남' AND city = '부산'   (실제 30,000행)
 Bitmap Heap Scan on addr (cost=139.00..2009.12 rows=10008) (actual rows=30000)
```

추정 10,008, 실제 30,000이다. 정확히 세 배 어긋났고, 이번에는 통계가 낡아서가 아니다. `ANALYZE`를 방금 돌렸고 두 컬럼의 통계 모두 정확하다.

플래너가 두 조건의 선택도를 **곱했기** 때문이다. `region = '영남'`은 1/3, `city = '부산'`은 1/9이므로 270,000 × 1/3 × 1/9 = 10,000이다. 두 조건이 서로 독립이라고 가정한 계산이다.

실제로는 `city = '부산'`이면 `region`은 이미 '영남'으로 정해져 있어서, 두 번째 조건이 아무것도 더 걸러내지 않는다. 정답은 270,000 × 1/9 = 30,000이다.

### 확장 통계가 그 가정을 끈다

컬럼 사이의 관계를 따로 수집하게 하면 달라진다.

```sql
CREATE STATISTICS addr_region_city (dependencies, ndistinct) ON region, city FROM addr;
ANALYZE addr;
```

```
-- 같은 쿼리
 Bitmap Heap Scan on addr (cost=405.80..2566.85 rows=29403) (actual rows=30000)
```

10,008이 29,403이 됐다. 실제 30,000에 2% 안쪽이다.

수집한 내용은 이렇게 생겼다.

```
     dependencies
----------------------
 {"3 => 2": 1.000000}
```

`3 => 2`는 세 번째 컬럼(`city`)이 두 번째 컬럼(`region`)을 결정한다는 뜻이고, `1.000000`은 그 종속이 100% 성립한다는 뜻이다. 플래너는 이 값을 보고 `region` 조건의 선택도를 곱하지 않는다. → [PostgreSQL — Multivariate Statistics](https://www.postgresql.org/docs/current/planner-stats.html#PLANNER-STATS-EXTENDED)

## 동작 원리

### 등가 조건의 선택도

`col = 값` 하나를 계산하는 순서다.

1. 값이 `most_common_vals`에 있으면 대응하는 `most_common_freqs`를 그대로 쓴다
2. 없으면 MCV가 차지하지 않은 나머지 비율을, MCV에 없는 서로 다른 값의 개수로 나눈다
3. 2의 분모가 0이 되면 최소값 1행으로 대체한다

`status = 'DONE'`은 1번이라 0.95053333이 그대로 선택도가 되고, MCV 열 개 바깥의 `user_id` 값은 2번이다. 3번이 [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/)에서 다룬 경우다.

MCV가 두 계산을 나누는 경계선이라, MCV 개수를 늘리는 것(`SET STATISTICS`)이 곧 1번으로 처리되는 값을 늘리는 것이다.

### 조건이 여럿일 때

조건 하나하나의 선택도는 위처럼 계산하고, 여러 개는 곱한다. 곱셈은 조건들이 서로 독립일 때만 맞는 계산이다.

| 두 컬럼의 관계 | 곱셈의 결과 |
|---|---|
| 독립 | 맞는다 |
| 한쪽이 다른 쪽을 결정한다 | 과소추정. `addr`의 10,008 대 30,000 |
| 서로 반대 방향 | 과대추정 |

과소추정은 플래너가 결과를 작게 보게 만들고, 작은 결과는 Nested Loop과 인덱스 스캔을 부른다. 실제 행이 많으면 그 반복이 그대로 비용이 된다. [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/)과 원인은 다르지만 도착점은 같다.

`CREATE STATISTICS`의 `dependencies`가 이 곱셈을 끄고, `ndistinct`는 `GROUP BY` 여러 컬럼의 그룹 수 추정에 쓰인다.

### correlation이 인덱스를 고르게 한다

`correlation`은 컬럼 값의 순서와 행이 디스크에 놓인 순서가 얼마나 맞아떨어지는지다. 1이면 완전히 같은 순서고, 0이면 관계가 없다.

이 값이 인덱스 스캔의 비용 추정에 들어간다. `correlation`이 1에 가까우면 인덱스 순서대로 읽는 것이 곧 디스크 순차 읽기라 싸고, 0에 가까우면 블록을 흩어 읽어야 해서 비싸다고 계산한다.

같은 선택도, 같은 인덱스인데도 `correlation`이 낮으면 플래너가 Seq Scan 쪽으로 기우는 이유다. `id`의 1과 `user_id`의 −0.0008이 같은 테이블 안에 있는 두 극단이다.

### ANALYZE는 표본 추정이다

표본에서 센 값이라 세 가지가 따라온다.

돌릴 때마다 값이 조금씩 달라진다. 위의 9951과 9939가 그렇다.

`n_distinct`는 특히 어렵다. 표본에 한 번만 나온 값이 실제로도 하나뿐인지, 아니면 표본에 덜 걸린 것인지 표본만으로는 구분되지 않는다. 균등 분포에서도 10,000을 9,951로 세는 이유다.

정확도를 올리는 방법은 표본을 키우는 것뿐이다. `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS`가 컬럼 단위로 그 값을 바꾼다.

## 경계 조건

**autovacuum이 `ANALYZE`도 돌린다.** 기본값은 `autovacuum_analyze_scale_factor` 0.1과 `autovacuum_analyze_threshold` 50이라, 바뀐 행이 (전체의 10% + 50)을 넘으면 실행한다. 대량 적재 직후처럼 그 임계치에 도달하기 전에 조회가 몰리는 구간에서는 수동 `ANALYZE`가 필요하다. → [PostgreSQL — The Autovacuum Daemon](https://www.postgresql.org/docs/current/routine-vacuuming.html#AUTOVACUUM)

**`n_distinct`는 직접 고정할 수 있다.** `ALTER TABLE ... ALTER COLUMN col SET (n_distinct = 10000)`으로 값을 박아둘 수 있다. 분포를 확실히 아는 컬럼에서 표본 오차를 없애는 방법이지만, 데이터가 바뀌어도 통계가 따라가지 않으므로 틀린 값을 고정할 위험도 같이 온다.

**확장 통계는 만들어야 생긴다.** 자동으로 만들어지지 않고, 어떤 컬럼 조합에 걸지 사람이 정해야 한다. 조합 수만큼 `ANALYZE` 비용이 는다.

**측정 규모가 작다.** 50만 행, 29 MB 테이블이고 전부 메모리에 있다. 추정 오차가 플랜을 뒤집더라도 실행 시간 차이가 크지 않아, 이 글의 수치는 추정값과 실측값의 비교로만 본다.

## 언제 쓰고 언제 안 쓰나

**추정이 빗나가면 먼저 통계 시각부터 본다.** `pg_stat_user_tables`의 `last_analyze`와 `last_autoanalyze`가 그 값이다. 낡았으면 `ANALYZE` 한 번으로 끝난다.

**통계가 최신인데도 빗나가면 어긋난 방식을 본다.** 조건이 컬럼 하나면 MCV와 히스토그램을, 여럿이면 독립 가정을 의심한다. `EXPLAIN`의 `rows`가 조건 하나짜리에서는 맞는데 `AND`로 묶으면 어긋나는 패턴이 후자다.

**`SET STATISTICS`는 값이 많고 분포가 치우친 컬럼에 쓴다.** 값 종류가 몇 개뿐이면 MCV가 이미 전부를 담고 있어서 올려도 달라지지 않는다.

**`CREATE STATISTICS`는 함께 조회되는 종속 컬럼에 건다.** 지역과 도시, 카테고리와 하위 카테고리, 국가 코드와 통화처럼 한쪽이 다른 쪽을 결정하는 조합이다. `WHERE`에 늘 함께 오는 것이 조건이고, 따로 조회되는 컬럼이면 만들 값이 없다.

## 참고

- [PostgreSQL — Statistics Used by the Planner](https://www.postgresql.org/docs/current/planner-stats.html)
- [PostgreSQL — Multivariate Statistics](https://www.postgresql.org/docs/current/planner-stats.html#PLANNER-STATS-EXTENDED)
- [PostgreSQL — pg_stats](https://www.postgresql.org/docs/current/view-pg-stats.html)
- [PostgreSQL — ANALYZE](https://www.postgresql.org/docs/current/sql-analyze.html)
- [PostgreSQL — Routine Vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)
