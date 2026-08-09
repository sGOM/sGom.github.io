---
title: 행 추정치 1이 조인 플랜을 뒤집는 과정
description: 통계에 없는 값의 선택도가 0이 되고, 1로 clamp된 추정치가 Nested Loop을 부르기까지
pubDate: 2026-08-09
category: "데이터베이스"
tags: ["파고들기", "Database", "PostgreSQL", "테스트"]
---

## 전제

[실행계획 읽기 — 스캔, 조인, rows와 loops](/posts/query-plan-basics/)에서 정리한 `rows`·`actual rows`·`loops`의 의미를 알고 있다고 보고 출발한다.

## 왜 필요한가

"통계가 오래돼서 플랜이 나빠졌다"는 설명은 흔하다. 그런데 왜 하필 **1**로 추정되는지, 왜 그 1이 하필 **Nested Loop**을 부르는지까지는 잘 이어지지 않는다.

추정이 1이라는 것은 근사가 조금 빗나간 결과가 아니다. 선택도 계산이 0으로 무너진 뒤 최소값으로 대체된, 성질이 다른 값이다. 그리고 1은 Nested Loop의 비용 모델에서 가장 유리한 입력이다. 이 두 사실이 만나면 옵티마이저는 자신 있게 최악의 플랜을 고른다.

## 겉으로 보이는 것

같은 테이블, 같은 컬럼, 같은 형태의 쿼리인데 값만 다르면 추정이 세 자릿수로 갈린다.

```sql
explain select * from va where ws_id = 'aaaa...';   -- Seq Scan (rows=1000)
explain select * from va where ws_id = 'bbbb...';   -- Index Only Scan (rows=1)
```

두 값 모두 실제로는 1,000행이다. 인덱스도 같고 통계 갱신 시각도 하나다. 겉으로는 옵티마이저가 한쪽에서만 이상하게 구는 것처럼 보인다.

## 동작 원리

갈림길은 **그 값이 통계의 MCV 목록에 있는가**다.

PostgreSQL은 `ANALYZE` 시점에 컬럼별로 `most_common_vals`(MCV, 자주 나오는 값 목록), `most_common_freqs`(각 값의 빈도), `n_distinct`(서로 다른 값의 개수)를 `pg_statistic`에 기록한다. 등가 조건의 선택도는 이 셋으로 계산된다.

**값이 MCV에 있으면** 해당 빈도를 그대로 선택도로 쓴다. 추정은 대체로 정확하다.

**값이 MCV에 없으면** 남은 값들이 균등 분포한다고 보고 나눈다.

```
선택도 = (1 - sum(most_common_freqs)) / (n_distinct - MCV 개수)
```

문제는 **MCV 목록이 그 컬럼의 값을 전부 담고 있는** 경우다. 그러면 `most_common_freqs`의 합이 1.0이 되고 `n_distinct`와 MCV 개수도 같아진다.

```
선택도 = (1 - 1.0) / (n_distinct - MCV 개수) = 0 / 0
```

분자가 0이므로 선택도는 0이 된다.

이 조건은 생각보다 쉽게 만들어진다. 기본 `default_statistics_target`은 100이라 MCV를 100개까지 담고, 소형 테이블은 `ANALYZE`가 전수에 가깝게 표본을 뜬다. 서로 다른 값이 100종 미만인 소형 테이블이면 값이 하나든 열이든 결과는 같다. 값의 종류가 적다는 것이 오히려 함정이 되는 구조다. 여기에 테이블 행 수를 곱해도 0이다. 옵티마이저는 0행이라는 추정을 그대로 쓰지 않고 최소 1로 올려 잡는다 — `clamp_row_est()`가 하는 일이다.

```c
/* src/backend/optimizer/path/costsize.c — 주석 생략 */
double
clamp_row_est(double nrows)
{
    if (nrows > MAXIMUM_ROWCOUNT || isnan(nrows))
        nrows = MAXIMUM_ROWCOUNT;
    else if (nrows <= 1.0)
        nrows = 1.0;
    else
        nrows = rint(nrows);

    return nrows;
}
```

`rows=1`은 "1행쯤 될 것 같다"는 추정이 아니라 **"계산이 0 이하로 나왔다"는 신호**다. 실행계획에서 `rows=1`을 보면 이 가능성을 먼저 의심해야 하는 이유다.

여기서 두 번째 단계가 이어진다. Nested Loop의 비용은 대략 이렇게 계산된다.

```
비용 ≈ outer 비용 + (outer 행 수 × inner 1회 비용)
```

`outer 행 수`가 1이면 두 번째 항이 inner 1회 비용으로 줄어든다. 인덱스로 좁혀 한 행만 가져오는 조회는 Hash Join처럼 해시 테이블을 만드는 준비 비용이 없으므로, 이 상태의 Nested Loop은 거의 항상 가장 싸 보인다. 옵티마이저 입장에서는 합리적인 선택이다.

실제 outer가 1,000행이면 그 두 번째 항이 그대로 1,000배가 된다. inner 스캔이 1,000번 반복된다. **추정 오차가 1,000배면 실행 비용도 1,000배가 되는 구조**다.

## 직접 확인

빈 PostgreSQL 16에 같은 구조를 만들어 재현했다. 소형 테이블 `va`(uuid당 1,000행)와 대형 테이블 `evt`(30만 행)를 두고, `autovacuum_enabled = off`로 "통계가 갱신되지 않은 상태"를 고정한다.

```python
conn.execute(text("""
    CREATE TABLE va (
        ws_id     uuid   NOT NULL,
        infra_id  bigint NOT NULL,
        item_code bigint NOT NULL,
        PRIMARY KEY (ws_id, infra_id, item_code)
    ) WITH (autovacuum_enabled = off)
"""))
```

구 uuid로 1,000행을 넣고 `VACUUM ANALYZE`까지 한 상태가 출발선이다. 여기에 새 uuid로 1,000행을 더 넣고 **ANALYZE하지 않는다.**

먼저 통계에 새 값이 없다는 것을 확인한다.

```python
def test_적재_직후_통계에는_새_uuid가_없다(after_restart):
    row = after_restart.execute(text("""
        SELECT n_distinct, most_common_vals::text AS mcv
          FROM pg_stats
         WHERE schemaname = :schema AND tablename = 'va' AND attname = 'ws_id'
    """), {"schema": REPRO_SCHEMA}).one()

    assert row.n_distinct == 1
    assert WS_OLD in row.mcv
    assert WS_NEW not in row.mcv
```

`n_distinct == 1`, MCV에는 구 uuid만. 위 공식의 분모와 분자가 동시에 0이 되는 조건이 그대로 갖춰졌다.

다음은 추정치다.

```python
def test_MCV에_없는_값은_1행으로_오추정된다(after_restart):
    plan_old = explain(after_restart, _select_by_ws(WS_OLD), analyze=True)
    plan_new = explain(after_restart, _select_by_ws(WS_NEW), analyze=True)

    # 실제 행 수는 둘 다 1,000
    assert actual_rows(plan_old) == ROWS_PER_WS
    assert actual_rows(plan_new) == ROWS_PER_WS

    assert misestimation_ratio(plan_old) < 2      # MCV에 있는 값은 대략 맞는다
    assert estimated_rows(plan_new) == 1          # 없는 값은 1로 clamp된다
    assert misestimation_ratio(plan_new) >= 100   # 세 자릿수 과소추정
```

`estimated_rows(plan_new) == 1`이 정확히 성립한다. 근사가 아니라 clamp의 결과이므로 값이 정확히 1이고, 이 단언은 강제 설정 없이 결정적으로 통과한다.

세 번째로 이 추정이 조인을 뒤집는 것을 확인한다. 여기서는 재현을 결정적으로 만들기 위해 조인 방식을 강제했다.

```python
def test_오추정된_outer가_큰_테이블_스캔을_1000번_반복시킨다(after_restart):
    knobs = (
        "join_collapse_limit = 1",
        "enable_hashjoin = off",
        "enable_mergejoin = off",
        "enable_material = off",
    )
    ...
    assert "Nested Loop" in node_types(plan)

    va_node = require_node(plan, relation="v")
    evt_node = require_node(plan, relation="e")

    # outer: 추정 1행 vs 실제 1,000행
    assert estimated_rows(va_node) == 1
    assert actual_rows(va_node) == ROWS_PER_WS

    # inner: 같은 스캔이 outer 행 수만큼 반복된다
    assert loops(evt_node) == ROWS_PER_WS
```

**이 강제는 밝혀야 할 부분이다.** 플랜 선택은 비용 차이로 갈리므로, 환경에 따라 옵티마이저가 Hash Join을 고를 수도 있다. 강제는 테스트를 어느 환경에서나 같은 결과로 만들기 위한 것이다.

다만 강제가 결과를 만들어낸 것은 아니다. 같은 조건에서 아무것도 강제하지 않고 옵티마이저에게 맡긴 실행도 함께 측정했는데, **옵티마이저 스스로 Nested Loop을 골랐다.**

마지막으로 `ANALYZE` 한 줄의 효과다.

```python
def test_통계가_정확하면_큰_테이블을_한_번만_스캔한다(after_restart):
    analyze_table(after_restart, "va")

    plan = explain(after_restart, JOIN_SQL, analyze=True, buffers=True)

    assert estimated_rows(require_node(plan, relation="v")) == pytest.approx(ROWS_PER_WS, rel=0.2)
    assert loops(require_node(plan, relation="e")) == 1
```

측정값이다. 통계 상태(ANALYZE 전후) × 조인 방식(옵티마이저 선택 / Nested Loop 강제) 네 조합을 각각 3회 실행한 중앙값이다.

| 통계 | 조인 | va 추정/실제 | evt 스캔 반복 | 버퍼(shared) | 실행 시간 |
|---|---|---|---|---|---|
| ANALYZE 전 | 옵티마이저 선택 → **Nested Loop** | 1 / 1,000 | 1,000회 | 1,727,016 | **1,355.1 ms** |
| ANALYZE 전 | Nested Loop 강제 | 1 / 1,000 | 1,000회 | 1,727,016 | 1,374.4 ms |
| ANALYZE 후 | 옵티마이저 선택 → **Hash Join** | 1,000 / 1,000 | 1회 | 1,742 | **2.0 ms** |
| ANALYZE 후 | Nested Loop 강제 | 1 / 1 | 1회 | 1,734 | 2.1 ms |

읽을 것이 세 가지 있다.

**1행과 2행이 사실상 같다.** 버퍼는 동일하고 시간 차는 1.4%다. 강제는 결정성을 위한 장치일 뿐, 오추정 상태에서 옵티마이저가 스스로 고른 플랜도 같은 Nested Loop이었다.

**3행과 4행을 보면 Nested Loop 자체는 문제가 아니다.** 통계가 정확한 상태에서는 Nested Loop을 강제해도 2.1 ms로 끝난다. 조인 순서가 뒤집혀 `evt`가 outer가 되고, `va`는 행마다 1건씩 찾는 inner가 되기 때문이다(`va` 추정/실제가 나란히 1이다). 반복 횟수가 늘지 않으니 폭발할 것이 없다.

**1행과 4행은 같은 Nested Loop인데 시간이 645배 차이난다.** 조인 방식도, 데이터도, 쿼리도, 인덱스도 같다. 다른 것은 통계뿐이다. "Nested Loop이 나쁘다"가 아니라 **"틀린 추정 위에 세운 Nested Loop이 나쁘다"**가 정확한 진술인 이유다.

전체로는 버퍼 991배, 시간 678배 차이다.

저장소: [github.com/sGOM/db-test-lab](https://github.com/sGOM/db-test-lab)

## 경계 조건

이 구조가 성립하려면 조건이 겹쳐야 한다.

- **조건 컬럼이 통계에 없는 새 값**이어야 한다. 기존 값이면 MCV 빈도로 대략 맞게 추정된다.
- 마지막 `ANALYZE` 시점에 그 컬럼의 **모든 값이 MCV에 담겨 있어야** 빈도 합이 1.0이 되어 분자가 0이 된다. MCV에 담기지 못한 값이 하나라도 있었다면 선택도가 작은 양수가 되고, 추정치도 1이 아닌 값이 나온다. 이 조건은 값의 종류가 적은 소형 테이블에서 잘 성립한다.
- **소형 테이블이 outer**여야 한다. 오추정된 쪽이 inner면 반복 횟수가 늘지 않는다.
- inner가 **비싼 스캔**이어야 체감된다. inner가 인덱스 한 건 조회면 1,000번 반복해도 티가 나지 않는다.

## 대안과 트레이드오프

| 방법 | 효과 | 대가 |
|---|---|---|
| 적재 직후 명시적 `ANALYZE` | 공백이 사라진다. 원인을 직접 없앤다 | 적재 코드가 통계를 알아야 한다. 적재 경로마다 넣어야 한다 |
| `autovacuum_analyze_scale_factor` 인하 | 해당 테이블 전반에 듣는다 | auto-analyze 빈도가 올라간다. 여전히 지연이 있다 |
| `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS` 상향 | 값 분포가 넓은 컬럼의 추정이 정교해진다 | **이 문제에는 듣지 않는다.** MCV가 값을 더 담을수록 빈도 합이 1.0에 가까워져 오히려 0/0 조건에 들어맞기 쉬워진다 |
| `pg_hint_plan`으로 조인 방식 고정 | 즉시 듣는다 | 원인은 그대로다. 데이터가 바뀌면 힌트가 오히려 짐이 된다 |

첫 번째가 원인을 직접 없애는 유일한 방법이다. 나머지는 추정이 틀릴 확률을 낮추거나 틀려도 버티게 하는 것이라 성격이 다르다.

## 언제 쓰고 언제 안 쓰나

**적재 직후 명시적 `ANALYZE`는 "소형 테이블 + 새로운 값 + 곧바로 조회"** 세 조건이 겹칠 때만 넣는다. 대량 배치 적재는 어차피 auto-analyze 조건을 넘기므로 필요 없고, 조회가 한참 뒤에 오는 테이블도 마찬가지다.

반대로 서버 기동 시 재적재하는 참조 테이블은 세 조건이 정확히 겹친다. 기동 직후가 곧 조회가 시작되는 시점이기 때문이다.

## 참고

- [github.com/sGOM/db-test-lab](https://github.com/sGOM/db-test-lab)
- [PostgreSQL Documentation — Row Estimation Examples](https://www.postgresql.org/docs/current/row-estimation-examples.html)
- [PostgreSQL Documentation — Planner Statistics](https://www.postgresql.org/docs/current/planner-stats.html)
- [postgres/src/backend/optimizer/path/costsize.c — `clamp_row_est`](https://github.com/postgres/postgres/blob/master/src/backend/optimizer/path/costsize.c)
