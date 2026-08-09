---
title: 실행계획 읽기 — 스캔, 조인, rows와 loops
description: EXPLAIN 출력에서 무엇을 먼저 보고 무엇을 무시해도 되는지 정리한다
pubDate: 2026-08-09
category: "데이터베이스"
tags: ["기본개념", "Database", "PostgreSQL"]
---

## 왜 필요한가

같은 쿼리가 개발 DB에서는 10ms, 운영에서는 120초가 되는 일이 있다. SQL도 인덱스도 같은데 결과가 다르면 남은 변수는 옵티마이저가 고른 실행 방법이다.

실행계획은 그 선택을 보여준다. 다만 출력에는 숫자가 너무 많아서, 무엇을 먼저 보는지 모르면 읽어도 결론이 나오지 않는다.

## 용어 정리

- **실행계획(plan)**: 옵티마이저가 정한 실행 절차. 노드로 이뤄진 트리이며, **아래에서 위로** 데이터가 흐른다.
- **통계(statistics)**: 옵티마이저가 비용을 계산하는 근거. 각 컬럼의 값 분포와 행 수. `ANALYZE`가 갱신한다.
- **선택도(selectivity)**: 조건이 남길 행의 비율. 통계에서 계산한다.
- **추정치(estimate)와 실측치(actual)**: 실행 전 계산한 값과 실제로 나온 값.

`EXPLAIN`은 계획만 보여주고, `EXPLAIN ANALYZE`는 쿼리를 실제로 실행해 실측치까지 채운다. DML에 `ANALYZE`를 붙이면 실제로 반영되므로 트랜잭션으로 감싸고 롤백해야 한다.

## 핵심 정리

노드는 크게 스캔과 조인으로 나뉜다.

| 노드 | 하는 일 | 유리한 상황 |
|---|---|---|
| Seq Scan | 테이블 전체를 훑는다 | 대부분의 행을 읽어야 할 때 |
| Index Scan | 인덱스로 행을 찾고 테이블에서 읽는다 | 소수의 행만 골라낼 때 |
| Index Only Scan | 인덱스만으로 끝낸다 (테이블 접근 없음) | 필요한 컬럼이 전부 인덱스에 있을 때 |
| Bitmap Heap Scan | 인덱스로 위치를 모아 정렬한 뒤 한 번에 읽는다 | 중간 규모의 행을 읽을 때 |
| Nested Loop | 바깥(outer) 행마다 안쪽(inner)을 반복 실행한다 | **outer가 적을 때** |
| Hash Join | 한쪽으로 해시 테이블을 만들고 다른 쪽을 한 번 훑는다 | 양쪽이 클 때, 등가 조건일 때 |
| Merge Join | 양쪽을 정렬해 맞춰 나간다 | 이미 정렬돼 있을 때 |

각 노드에 붙는 숫자는 다음과 같다.

| 표기 | 뜻 | 단위 |
|---|---|---|
| `cost=A..B` | 첫 행까지의 추정 비용 A, 마지막 행까지 B | 임의 단위 (ms 아님) |
| `rows=N` | **추정** 행 수. 1회 실행 기준 | 행 |
| `actual time=A..B` | 실제 소요 시간. 1회 실행 기준 | ms |
| `actual rows=N` | **실측** 행 수. 1회 실행 기준 평균 | 행 |
| `loops=N` | 이 노드가 몇 번 실행됐는지 | 회 |
| `Buffers: shared hit=A read=B` | 캐시에서 읽은 블록 A, 디스크에서 읽은 블록 B | 8KB 블록 |

## 항목별 설명

**가장 먼저 볼 것은 `rows`와 `actual rows`의 차이다.** 둘이 자릿수 단위로 벌어지는 노드가 있으면 옵티마이저가 잘못된 전제로 계획을 세운 것이다. 그 아래 숫자들은 전부 그 전제 위에서 계산된 값이라 볼 필요가 없다.

**그다음은 `loops`다.** `loops`가 큰 노드는 Nested Loop의 inner 쪽이다. 그 노드의 `actual time`과 `actual rows`는 **1회분**이므로, 실제 비용은 `loops`를 곱해야 나온다.

**`cost`는 비교용이지 측정값이 아니다.** 단위는 "순차 페이지 읽기 1회 = 1.0"으로 잡은 임의 값이라 ms로 환산되지 않는다. 두 계획 중 옵티마이저가 왜 이쪽을 골랐는지 설명할 때만 쓴다.

## 예시

`loops`가 곱해진다는 것을 보여주는 출력이다. [db-test-lab](https://github.com/sGOM/db-test-lab)의 재현 결과에서 필요한 줄만 추린 것이라, 비용과 시간 표기는 생략했다.

```
Nested Loop
  ->  Index Only Scan using va_pkey on va v  (rows=1) (actual rows=1000 loops=1)
  ->  Bitmap Heap Scan on evt e              (rows=56) (actual rows=50 loops=1000)
```

읽는 순서는 이렇다.

1. `va` 노드에서 추정 `rows=1`, 실측 `actual rows=1000`. **1,000배 과소추정**이다.
2. 옵티마이저는 outer가 1행이라 봤으므로 "inner를 한 번만 돌면 된다"고 계산해 Nested Loop을 골랐다.
3. 실제 outer는 1,000행이라 inner의 `loops=1000`이 됐다. `evt` 스캔이 1,000번 반복됐다는 뜻이다.
4. `evt` 노드의 `actual rows=50`은 1회분이므로 실제로 처리한 행은 50 × 1,000 = 50,000이다.

통계를 갱신하면 같은 쿼리가 이렇게 바뀐다.

```
Hash Join
  ->  Bitmap Heap Scan on evt e  (rows=56) (actual rows=50 loops=1)
  ->  Hash
        ->  Seq Scan on va v     (rows=1000) (actual rows=1000 loops=1)
```

`loops`가 1로 떨어졌다. 데이터도 쿼리도 인덱스도 그대로다.

## 혼동하기 쉬운 것

**`rows`가 loop당 값이라는 점**을 놓치면 전체 규모를 크게 과소평가한다. `actual rows=50 loops=1000`은 50행이 아니라 50,000행이다.

**Seq Scan이 항상 나쁜 것은 아니다.** 테이블의 상당 부분을 읽어야 하면 인덱스를 타는 쪽이 오히려 느리다. 인덱스는 행마다 테이블을 되짚으므로 랜덤 접근이 늘어난다. "Seq Scan이 보이니 인덱스를 추가한다"는 판단은 근거가 되지 못한다.

**추정이 틀린 것과 계획이 나쁜 것도 다르다.** 추정이 크게 틀렸는데도 우연히 괜찮은 계획이 나올 수 있고, 그런 쿼리는 데이터가 조금만 바뀌어도 갑자기 뒤집힌다. 시간만 보고 넘어가면 이 시한폭탄을 놓친다.

**`EXPLAIN`만으로는 추정 오류를 알 수 없다.** 실측치가 없기 때문이다. 느린 쿼리를 조사할 때는 `EXPLAIN (ANALYZE, BUFFERS)`를 쓴다.

## 언제 어떤 것을 쓰나

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
```

느린 쿼리 조사의 기본형이다. 자동화된 검증에 쓸 때는 `FORMAT JSON`을 붙여 노드 트리로 받는다. 플랜 텍스트를 문자열로 비교하는 테스트는 DBMS 버전만 올라가도 깨진다.

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT ...;
```

## 더 깊이

- [행 추정치 1이 조인 플랜을 뒤집는 과정](/posts/planner-row-estimation/) — 통계가 비면 왜 추정치가 1이 되는지

## 참고

- [PostgreSQL Documentation — Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)
- [PostgreSQL Documentation — Row Estimation Examples](https://www.postgresql.org/docs/current/row-estimation-examples.html)
