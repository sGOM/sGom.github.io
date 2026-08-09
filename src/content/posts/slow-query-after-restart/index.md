---
title: 배포할 때마다 목록 조회가 120초 걸렸다
description: 기동 시 대량 적재가 auto-analyze 기준에 미달해 통계가 갱신되지 않았다
pubDate: 2026-08-09
category: "데이터베이스"
tags: ["오답노트", "Database", "PostgreSQL", "성능"]
---

## 상황

모니터링 시스템의 이벤트 목록 조회 API가 배포 이후 응답하지 않는다는 제보를 받았다. 평소 수십 ms로 끝나던 조회가 타임아웃까지 갔고, 로그에는 120초를 넘긴 요청이 남아 있었다. 배포 직전과 직후의 코드 차이에는 이 조회와 관련된 변경이 없었다.

이벤트 테이블은 수백만 행 규모이고, 조회는 그 테이블과 "관심 항목 매핑 테이블"을 조인해 최근 이벤트를 추린다. 매핑 테이블은 1만 행 규모의 소형 테이블이며, 서비스가 기동할 때마다 새 인스턴스 식별자로 950행이 추가된다.

## 환경

- PostgreSQL 16
- autovacuum 기본 설정 (`autovacuum_analyze_threshold = 50`, `autovacuum_analyze_scale_factor = 0.1`)
- 매핑 테이블 약 10,000행, 기동 시 적재량 950행

## 증상

- 이벤트 목록 조회 응답 시간이 평소 수십 ms에서 120초 이상으로 늘었다.
- **배포·재기동 직후에 시작됐고, 시간이 지나도 저절로 회복되지 않았다.**
- 같은 시각 다른 API는 정상이었다. CPU와 커넥션 풀 사용률에도 이상이 없었다.
- 슬로우 쿼리 로그에 남은 것은 이벤트 목록 조회 하나뿐이었다.
- 조회 대상 데이터의 건수는 평소와 같았다.

## 가설과 검증

> 가설 1: 배포에 포함된 코드 변경이 쿼리를 바꿨을 것이다

배포 diff에서 해당 조회 경로와 매핑 테이블을 건드린 변경을 찾지 못했다. 실제 실행된 SQL을 로그로 떠서 이전 버전과 비교했고, 문자열까지 동일했다. **틀렸다.**

> 가설 2: 인덱스가 빠졌거나 깨졌을 것이다

`pg_indexes`로 두 테이블의 인덱스를 확인했다. 배포 전후로 정의가 같았고 유효했다. 뒤에 확인한 실행계획에서는 그 인덱스를 실제로 타고 있었다. **틀렸다.**

> 가설 3: 데이터가 급증해 스캔량이 늘었을 것이다

이벤트 테이블 행 수와 조회 범위의 건수를 세어 봤다. 평소와 같은 규모였다. 처리해야 할 데이터가 늘어난 것이 아니었다. **틀렸다.**

> 가설 4: 실행계획이 바뀌었을 것이다

`EXPLAIN (ANALYZE, BUFFERS)`를 떴다. 여기서 원인이 드러났다.

```
Nested Loop
  ->  Index Only Scan on 매핑테이블  (rows=1)  (actual rows=950 loops=1)
  ->  Bitmap Heap Scan on 이벤트테이블         (actual rows=... loops=950)
                                                           ^^^^^^^^
```

매핑 테이블의 추정 행 수가 **1**인데 실제는 **950**이었다. 옵티마이저는 "outer가 1행이면 inner를 한 번만 돌면 된다"고 계산해 Nested Loop을 골랐고, 실제 outer가 950행이라 이벤트 테이블 스캔이 950번 반복됐다. 회당 100ms대의 스캔이 950번이면 95초다.

> 가설 5: 통계가 갱신되지 않아 추정치가 틀렸을 것이다

`pg_stats`에서 매핑 테이블의 인스턴스 식별자 컬럼을 확인했다. `most_common_vals`에 **이전 인스턴스들의 식별자만** 들어 있었고, 방금 적재된 새 식별자는 없었다. `pg_stat_user_tables`의 `last_autoanalyze`는 배포 이전 시각에 멈춰 있었다. **맞았다.**

## 원인

이 서비스는 기동 시 매핑 테이블을 **새 인스턴스 식별자로 다시 적재**한다. 배포할 때마다 새 식별자로 950행이 들어가고, 이전 식별자의 행은 그대로 남아 테이블은 1만 행까지 누적돼 있었다.

문제는 그 950행이 auto-analyze를 발동시키지 못했다는 것이다. PostgreSQL의 발동 조건은 다음과 같다.

```
n_mod_since_analyze > autovacuum_analyze_threshold
                      + autovacuum_analyze_scale_factor × reltuples
```

기본값 `threshold = 50`, `scale_factor = 0.1`에 이 테이블의 행 수를 넣으면 이렇게 된다.

```
발동 기준 = 50 + 0.1 × 10,000 = 1,050
적재량    = 950
```

**100행 차이로 미달이다.** 발동 조건을 넘지 못했으므로 auto-analyze는 돌지 않았고, 다음 배포까지 통계는 옛날 상태로 남았다. 시간이 지나도 회복되지 않은 이유가 여기 있다.

여기서 문턱이 테이블 크기에 비례한다는 점이 중요하다. 매핑 테이블이 커질수록 `0.1 × reltuples`도 함께 커지므로, 적재량이 일정하면 **테이블이 자랄수록 발동은 더 어려워진다.** 초기에는 정상이던 것이 어느 시점부터 재현되기 시작한 구조다.

통계에 새 식별자가 없으면 옵티마이저는 비-MCV 선택도 공식으로 추정한다.

```
선택도 = (1 - sum(most_common_freqs)) / (n_distinct - MCV 개수)
```

매핑 테이블은 작아서 `ANALYZE`가 전수에 가깝게 표본을 뜬다. 그 결과 그 시점에 존재하던 식별자가 **전부 MCV 목록에 들어가고** 빈도의 합이 1.0이 된다. `n_distinct`와 MCV 개수도 같아진다. 분자와 분모가 동시에 0이 되어 선택도가 0이 되고, 옵티마이저는 행 추정치를 최소 1로 올려 잡는다. 실제 950행이 1행으로 둔갑하는 지점이다.

즉 배포 자체가 원인이 아니라, **배포가 트리거한 적재가 통계를 무효화하면서 갱신은 시키지 못하는 크기**였다는 것이 원인이다.

## 해결

적재 코드 끝에 명시적 `ANALYZE` 한 줄을 넣었다.

```python
def analyze_table(target: Engine | Connection, table: str) -> None:
    if not table.replace("_", "").isalnum():
        raise ValueError(f"테이블명이 올바르지 않습니다: {table!r}")

    if isinstance(target, Connection):
        # ANALYZE 는 VACUUM 과 달리 트랜잭션 안에서도 실행할 수 있다.
        target.execute(text(f"ANALYZE {table}"))
        return

    with target.begin() as conn:
        conn.execute(text(f"ANALYZE {table}"))
```

같은 구조를 빈 PostgreSQL에 재현해 조치 전후를 측정했다. 이벤트 테이블 30만 행, 식별자당 매핑 1,000행으로 단순화했고, auto-analyze는 `autovacuum_enabled = off`로 아예 꺼서 "통계가 갱신되지 않은 상태"를 고정했다. 운영에서 문턱 미달로 만들어진 상태를 랩에서는 설정으로 만든 것이라, 재현하는 것은 원인이 아니라 **그 결과**다.

각 3회 실행한 중앙값이다.

| | 옵티마이저가 고른 조인 | 매핑 추정/실제 | 이벤트 스캔 반복 | 버퍼(shared) | 실행 시간 |
|---|---|---|---|---|---|
| ANALYZE 전 | Nested Loop | 1 / 1,000 | 1,000회 | 1,727,016 | 1,355.1 ms |
| ANALYZE 후 | Hash Join | 1,000 / 1,000 | 1회 | 1,742 | 2.0 ms |

버퍼 991배, 시간 678배 차이다. 플랜은 Nested Loop에서 Hash Join으로 바뀌었고 이벤트 스캔이 1회로 떨어졌다. **데이터·쿼리·인덱스는 그대로이고 통계만 바뀌었다.**

조인 방식을 강제하지 않고 옵티마이저에게 맡긴 결과다. 오추정 상태에서는 옵티마이저가 스스로 Nested Loop을 골랐다.

운영에서도 조치 후 배포부터 이벤트 목록 조회가 평소 응답 시간을 유지했다.

재현과 검증은 테스트로 고정했다.

```python
def test_통계가_정확하면_큰_테이블을_한_번만_스캔한다(after_restart):
    analyze_table(after_restart, "va")

    plan = explain(after_restart, JOIN_SQL, analyze=True, buffers=True)

    va_node = require_node(plan, relation="v")
    evt_node = require_node(plan, relation="e")

    assert estimated_rows(va_node) == pytest.approx(ROWS_PER_WS, rel=0.2)
    assert loops(evt_node) == 1
```

저장소: [github.com/sGOM/db-test-lab](https://github.com/sGOM/db-test-lab)

## 남은 문제

"오추정이 반드시 Nested Loop을 부른다"고까지는 말할 수 없다. 이 환경에서는 옵티마이저가 스스로 골랐고 강제한 경우와 결과가 거의 같았지만(1,355.1 ms 대 1,374.4 ms), 플랜 선택은 비용 계산의 미세한 차이로 갈린다. 그래서 재현 테스트에는 어느 환경에서나 같은 결과가 나오도록 `enable_hashjoin = off` 등을 걸어 두었다. 결정적으로 재현되는 것은 오추정 자체(`rows=1`)이고, 그 뒤의 플랜 선택은 환경에 따라 달라질 수 있다.

또 이 조치는 이 적재 경로 하나만 막는다. 같은 패턴 — 소형 테이블에 새 값으로 적재하고 곧바로 조회 — 이 다른 곳에 있으면 같은 문제가 반복된다.

대상 테이블에 한해 `autovacuum_analyze_scale_factor`를 낮추는 선택지도 있었다. 0.05로 잡으면 발동 기준이 `50 + 0.05 × 10,000 = 550`이 되어 950행이 조건을 넘긴다. 다만 이것은 문턱을 현재 행 수 기준으로 다시 맞추는 것일 뿐이라, 테이블이 2만 행으로 자라면 기준이 1,050으로 올라가 같은 문제가 돌아온다. 크기에 비례하는 문턱을 고정 적재량으로 넘으려는 구조 자체가 불안정해 채택하지 않았다.

## 배운 것

**응답 시간이 자릿수 단위로 튀면 코드보다 실행계획을 먼저 본다.** 코드 diff를 뒤지는 데 쓴 시간이 가장 아까웠다. `EXPLAIN (ANALYZE, BUFFERS)` 한 번이면 세 번째 가설까지 건너뛸 수 있었다.

**실행계획에서는 `rows`와 `actual rows`의 차이를 가장 먼저 본다.** 자릿수가 벌어진 노드를 찾으면 그 아래 숫자는 전부 잘못된 전제 위의 값이라 볼 필요가 없다.

**"기다리면 auto-analyze가 고쳐준다"는 조건부다.** 적재량이 `threshold + scale_factor × reltuples`를 넘어야 성립한다. 문턱이 테이블 크기에 비례하므로, 적재량이 일정한 반복 작업은 **테이블이 자랄수록 발동에서 멀어진다.** 이번 건은 100행 차이였다. 한동안 멀쩡하다가 어느 날부터 재현되기 시작하는 문제는 이 형태를 의심할 만하다.

**통계 문제를 의심하면 `pg_stat_user_tables.last_autoanalyze`를 먼저 본다.** 그 값이 예상보다 오래됐다면 발동 조건을 계산해 본다. `pg_class.reltuples`에 `scale_factor`를 곱하는 계산 한 번이면 "왜 안 돌았는지"가 나온다.

## 참고

- [github.com/sGOM/db-test-lab](https://github.com/sGOM/db-test-lab)
- [PostgreSQL Documentation — Row Estimation Examples](https://www.postgresql.org/docs/current/row-estimation-examples.html)
- [PostgreSQL Documentation — The Autovacuum Daemon](https://www.postgresql.org/docs/current/routine-vacuuming.html#AUTOVACUUM)
