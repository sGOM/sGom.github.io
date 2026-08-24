# 발행 글 전체 내용 검증 — 2026-08-24

대상: `src/content/posts/` 발행 글 29편. 기준은 **기술적 사실 정확성**과 **글 내부·시리즈 간 정합성**.

## 등급

| 등급 | 뜻 | 수정 여부 |
|---|---|---|
| 확인 | 공식문서를 직접 받아 대조했거나, 코드를 실제로 실행해 확인함 | 수정 대상 |
| 불일치 | 글끼리 다른 말을 함 | 어느 쪽이 틀렸는지 명백할 때만 수정 |
| 의심 | 읽기에 어색하나 1차 출처로 확인하지 못함 | 보고만 |

## 검증 환경

글에 실린 코드는 가능한 한 전부 다시 돌렸다.

| 도구 | 용도 |
|---|---|
| `java`/`javac` 26.0.1 | JVM·GC 재현, `Set.of(...).contains(null)`, `javap` |
| `kotlinc` 2.2.0 (내려받아 사용) | 코루틴 상태 머신 바이트코드, `@all` use-site target 실측 |
| PostgreSQL 16.15 (docker) | 통계 오추정 → Nested Loop 폭발 재현, 조인 플랜 대조 |
| H2 2.3.232 (JDBC 직접 접속) | REPEATABLE READ 팬텀 리드 |
| `git` 2.45.1 | 워크트리 동작 |
| `python` + `numpy` 2.5.0 | 힙 구현, BPSK 신호 시뮬레이션 |
| `node` 24.15.0, `curl` | 1차 출처(공식문서·소스) 대조 |

돌리지 못한 것은 `kotlinc` 1.9.24(JDK 26의 버전 문자열을 파싱하지 못해 실행 실패. 2.2.0으로 대체했다)와 `jdbc-driver-value-paths`의 MySQL 실험뿐이다.

`jdbc-driver-value-paths`는 `docs/review-status.md`에서 `[V]` 상태라 **지적만 하고 수정하지 않았다.**

---

## 1. 트랜잭션 기초 — `transaction-and-acid` · `isolation-levels-and-anomalies` · `transaction-isolation-levels`

### [확인·수정함] H2 REPEATABLE READ가 Phantom Read를 막는다는 서술

- 위치: `transaction-isolation-levels/index.md` 「직접 확인」, `isolation-levels-and-anomalies/index.md` 「구현체별 차이」 표 H2 행
- 원문의 주장: "H2도 스냅샷 방식이므로 REPEATABLE READ에서 팬텀 리드까지 함께 막힌다"
- H2 공식문서([Advanced — Transaction Isolation](https://h2database.com/html/advanced.html))는 정반대로 규정한다.
  - Repeatable read: "Dirty reads and non-repeatable reads aren't possible, **phantom reads are possible**."
  - Phantom reads: "Possible with: read uncommitted, read committed, **repeatable read**."
  - 팬텀 리드를 막는다고 명시한 수준은 별도의 `SNAPSHOT`이다. H2는 표준 4단계가 아니라 5단계를 제공한다.
- 다만 **실제 동작은 글이 맞다.** H2 2.3.232에 JDBC로 직접 붙여 확인했다.

  ```
  REPEATABLE_READ  first=0 second=0 -> phantom 막힘
  READ_COMMITTED   first=0 second=1 -> phantom 발생
  ```

- 즉 테스트가 통과하는 것은 MVStore 구현이 문서가 약속한 것보다 강하게 격리하기 때문이고, 벤더가 보장하는 동작은 아니다.
- **수정했다.** 테스트 결과는 그대로 두고, 그것이 보장된 동작이 아니라는 것과 보장 수준은 `SNAPSHOT`이라는 것을 문서 인용과 함께 덧붙였다. 결론을 뒤집는 대신 글의 원래 주장("이름이 아니라 구현을 봐야 한다")을 한 겹 더 밀어 "문서가 보장하는 것과 구현이 실제로 하는 것도 다를 수 있다"로 이었다. `isolation-levels-and-anomalies`의 표 H2 행도 `SNAPSHOT`을 가리키도록 고쳤다.

### 확인된 것

- 나머지 서술은 문제를 찾지 못했다. PostgreSQL의 READ UNCOMMITTED→READ COMMITTED 승격, Oracle의 REPEATABLE READ 미지원, InnoDB 갭 락 서술, 표준 4단계 표는 각 벤더 문서와 일치한다.
- 세 글 사이의 상호 링크와 전제 서술은 서로 어긋나지 않는다.

## 2. Spring 트랜잭션 — `transaction-propagation-types` · `transactional-propagation` · `transactional-self-invocation` · `spring-aop-proxy`

### [확인·수정함] `transactional-self-invocation`의 예시 코드가 바로 아래 테스트와 다른 예외를 던진다

- 위치: `transactional-self-invocation/index.md` 「직접 확인」의 `SelfInvocationService` 코드 블록
- 글은 `throw RuntimeException()`으로 적었는데, 그 아래 인용한 테스트는 `shouldThrow<InnerFailureException>`을 기대한다. 글 안에서 앞뒤가 맞지 않는다.
- 원본 저장소를 대조했다. `SelfInvocationService.transactionalWork()`는 `throw InnerFailureException("self-invocation 실험용 예외")`다.
- 원본대로 고쳤다. 인용한 테스트 블록 4개는 원본과 문자 단위로 일치함을 확인했다.

### [확인·수정함] `spring-aop-proxy` 비교표의 "적용 안 되는 클래스: 없음"

- 위치: `spring-aop-proxy/index.md` 「핵심 정리」 표, JDK 동적 프록시 열
- 인터페이스를 구현하지 않은 클래스는 JDK 동적 프록시로 감쌀 수 없다. 표만 떼어 보면 "어떤 클래스든 된다"로 읽힌다.
- `없음` → `인터페이스를 구현하지 않은 클래스`로 고쳤다.

### 확인된 것

- 전파 속성 7가지 표, `IllegalTransactionStateException`, 기본 롤백 규칙(unchecked만 롤백), NESTED의 세이브포인트 구현, `proxyTargetClass` 기본값(Spring Boot 2.0~) 서술은 Spring 문서와 일치한다.
- `transactional-propagation`이 인용한 `outer()`/`inner()` 구조는 원본 `OuterService.requiredCallingRequiredAndCatch()`·`requiredCallingRequiresNewAndCatch()`와 일치한다. 원본이 `catch (e: InnerFailureException)`인 것을 글에서 `catch (e: RuntimeException)`으로 단순화했으나 상위 타입이라 서술이 틀리지 않는다.
- 네 글의 상호 참조는 서로 맞물린다.

## 3. 실행계획 — `query-plan-basics` · `query-plan-node-triggers` · `planner-row-estimation` · `slow-query-after-restart`

PostgreSQL 16.15를 docker로 띄우고 `db-test-lab`의 재현 픽스처(`tests/test_planner_stats.py`)를 그대로 옮겨 실행했다. `evt` 30만 행, `va`는 uuid당 1,000행, `autovacuum_enabled = off`, `setseed(0.42)`, `max_parallel_workers_per_gather = 0`까지 동일하게 맞췄다.

### [확인·수정함] "분자와 분모가 동시에 0이 되어 선택도가 0이 된다"

- 위치: `planner-row-estimation/index.md` 「동작 원리」, `slow-query-after-restart/index.md` 「원인」
- 비-MCV 선택도 공식 `(1 - sum(most_common_freqs)) / (n_distinct - MCV 개수)` 자체는 [PostgreSQL 문서](https://www.postgresql.org/docs/current/row-estimation-examples.html)와 일치한다.
- 다만 PostgreSQL은 0을 0으로 나누지 않는다. `selfuncs.c`의 `var_eq_const()`를 받아 확인했다.

  ```c
  selec = 1.0 - sumcommon - nullfrac;
  CLAMP_PROBABILITY(selec);

  otherdistinct = get_variable_numdistinct(vardata, &isdefault) - sslot.nnumbers;
  if (otherdistinct > 1)
      selec /= otherdistinct;
  ```

  분모가 0이면 `if`에 걸려 나눗셈 자체가 실행되지 않고, 앞서 구한 분자(`1 - 1.0 = 0`)가 그대로 선택도가 된다. 결론은 글이 맞았지만 도달 경로가 달랐다.
- 두 글 모두 고쳤다. `planner-row-estimation`에는 위 코드와 `selfuncs.c` 출처 링크를 넣었고, `slow-query-after-restart`는 한 문장을 늘려 같은 내용을 담았다.

### [확인·오류 아님] `query-plan-basics`의 Hash Join 플랜에서 `evt`의 `actual rows=50 loops=1`

처음에는 앞 플랜(`actual rows=50 loops=1000`)의 loop당 값을 잘못 옮긴 것으로 의심했으나, **재현 결과 글이 맞다.** 수정하지 않았다.

```
-- ANALYZE 전 (재현)
->  Nested Loop  (actual rows=50 loops=1)
      Join Filter: ((v.infra_id = e.infra_id) AND (v.item_code = e.item_code))
      Rows Removed by Join Filter: 49950
      ->  Index Only Scan using va_pkey on va v  (rows=1) (actual rows=1000 loops=1)
      ->  Bitmap Heap Scan on evt e  (rows=57) (actual rows=50 loops=1000)

-- ANALYZE 후 (재현)
->  Hash Join  (actual rows=50 loops=1)
      ->  Bitmap Heap Scan on evt e  (rows=57) (actual rows=50 loops=1)
      ->  Hash  ->  Seq Scan on va v  (rows=1000) (actual rows=1000 loops=1)
```

`evt` 스캔에는 조인 조건이 아니라 자기 필터(`evt_time`, `list_id`)만 걸려 있어 어느 플랜에서든 50행을 낸다. Nested Loop에서는 그 50행이 1,000번 반복돼 5만 행이 나오고 그중 49,950행이 `Join Filter`에서 버려진다. 글의 "50 × 1,000 = 50,000" 해석도 그대로 맞다.

버퍼 수치도 글과 맞물린다. 재현 결과 ANALYZE 전 `shared hit=1727008`, 후 `shared hit=1742`로 글의 표(1,727,016 / 1,742)와 사실상 같다. 실행 시간도 1,428 ms → 2.9 ms로 글(1,355.1 ms → 2.0 ms)과 같은 자릿수다.

`rows=56`(글) 대 `rows=57`(재현)은 `now()` 기준 시각이 달라 생기는 오차 범위다.

### 확인된 것

- 통계 상태도 그대로 재현됐다. 새 uuid 적재 후 `ANALYZE` 없이 `pg_stats`를 보면 `n_distinct = 1`, `most_common_vals = {aaaa…}`, `most_common_freqs = {1}`이다. 글이 말한 "분자와 분모가 동시에 0이 되는 조건"이 실제로 갖춰진다.
- 오추정도 그대로다. MCV에 있는 uuid는 `rows=1875`(실제 1,000)로 대략 맞고, 없는 uuid는 `rows=1`로 clamp된다.
- `planner-row-estimation`이 인용한 `clamp_row_est()` C 코드는 [PostgreSQL 16 원본](https://github.com/postgres/postgres/blob/REL_16_STABLE/src/backend/optimizer/path/costsize.c)과 일치한다(글이 밝힌 대로 주석만 생략했다).
- `slow-query-after-restart`의 산술은 전부 맞다. `50 + 0.1 × 10,000 = 1,050` 대 적재량 950(미달), `0.05`로 낮췄을 때 `550`, 테이블이 2만 행이면 다시 `1,050`, 회당 100 ms × 950회 = 95초.
- 두 글의 측정 표는 서로 일치한다(1,727,016 / 1,742 버퍼 = 991배, 1,355.1 / 2.0 ms = 678배).
- `query-plan-node-triggers`의 재현 수치는 내부적으로 정합적이다. `orders` 30만 행 ÷ 730일 = 일 411행으로 `rows=411`·`actual rows=442`가 맞고, `status` 5값 중 3값 = 60%로 `rows=180010`·`actual rows=180336`이 맞고, VIP 112/500 = 22%가 본문 서술과 맞는다.
- auto-analyze 발동 조건, `default_statistics_target = 100`, `cost` 단위(순차 페이지 읽기 1회 = 1.0), `EXPLAIN ANALYZE`의 DML 주의 서술은 PostgreSQL 문서와 일치한다.
- `evt` 규모가 원본 재현 가이드(200만 행)와 다른 것은 오류가 아니다. 글이 참조하는 pytest 스위트가 `EVT_ROWS = 300000`을 기본값으로 쓰고 주석에 그 이유를 밝혀 두었다.

## 4. 계층 구조 — `adjacency-list` · `closure-table` · `nested-set` · `path-enumeration`

### [확인·수정함] `nested-set`의 SQL이 예약어를 컬럼 이름으로 쓴다

- 위치: `nested-set/index.md` 전반 — 「핵심 정리」 표, 예시 표 헤더, SQL 블록 4개
- `left`와 `right`를 컬럼 이름으로 쓴다. `WHERE left BETWEEN 2 AND 5`, `UPDATE org SET right = right + 2` 모두 **문법 오류**다.
- [PostgreSQL — SQL Key Words](https://www.postgresql.org/docs/current/sql-keywords-appendix.html) 기준 두 단어는 `reserved (can be function or type)`이다. 함수·타입 이름으로는 쓸 수 있지만 컬럼 이름으로는 못 쓴다. MySQL과 SQL 표준에서도 예약어다.
- Nested Set 구현이 관례적으로 `lft`/`rgt`를 쓰는 이유가 이것이다. 컬럼 이름을 바꾸고 「용어 정리」에 그 이유를 한 줄 넣었다.
- 함께 고친 것: 「예시」의 `비어난 자리` → `비운 자리` (없는 말)

### [확인·수정함] `closure-table`의 자기 참조 행 설명이 반대로 적혀 있다

- 위치: `closure-table/index.md` 「혼동하기 쉬운 것」
- 원문: "이 행이 없으면 … `depth >= 0` 조건이 자기 자신을 **걸러내지 못한다**"
- `depth >= 0`은 자기 자신을 **포함시키려고** 거는 조건이다. 자기 참조 행이 없으면 그 조건을 걸어도 자기 자신이 결과에 들어오지 않는 것이지, 걸러내기에 실패하는 것이 아니다.
- "…조건을 걸어도 자기 자신이 결과에 들어오지 않는다"로 고쳤다. (`git log`로 확인한 결과 이 문장은 가독성 개선 커밋 `b979714`이 만든 것이 아니라 처음부터 이렇게 쓰여 있었다.)

### [확인·수정함] `closure-table` 참고 문헌의 "처음 정리한 책"

- 위치: `closure-table/index.md` 「참고」
- 전이적 폐쇄를 테이블로 실체화하는 발상은 *SQL Antipatterns*(2010)보다 앞선다. Vadim Tropashko의 *SQL Design Patterns*(2006)가 이미 이 패턴을 다뤘고, Karwin의 책은 그것을 "Closure Table"이라는 이름으로 널리 알린 쪽이다.
- "이 이름으로 널리 알린 책"으로 고치고 Tropashko를 병기했다.

### [확인·수정함] `path-enumeration` 표의 조상 조회 표기가 본문과 다르다

- 위치: `path-enumeration/index.md` 「핵심 정리」 표 — 원문 "역방향 `LIKE '%자기경로'`"
- 본문이 드는 실제 형태는 `WHERE '/1/2/3/' LIKE path || '%'`다. 비교 대상과 패턴의 위치가 표와 반대라, 표의 식을 그대로 실행하면 조상이 아니라 엉뚱한 행을 고른다.
- 본문과 같은 `'자기경로' LIKE path || '%'`로 고쳤다.

### 확인된 것

- `nested-set`의 삽입 예시 계산은 맞다. `rgt >= 5`, `lft >= 5` 두 UPDATE를 원래 값에 적용하면 결과 표의 대표(1,10)·개발팀장(2,7)·백엔드(3,4)·프론트(5,6)·영업(8,9)이 정확히 나온다.
- `adjacency-list`의 재귀 CTE 지원 시점 표는 전부 맞다(PostgreSQL 8.4/2009, SQLite 3.8.3/2014, MySQL 8.0/2018, Oracle 11g R2/2009 + `CONNECT BY PRIOR`).
- `closure-table`의 삽입 SQL(부모의 조상 관계에 `depth + 1`을 더하고 자기 참조 행을 `UNION ALL`로 붙임)은 옳다.
- `path-enumeration`의 사전순 정렬 함정(`/1/10/`이 `/1/2/`보다 앞), 접두사·접미사 `LIKE`의 인덱스 차이, `ltree`의 `<@`(자손)·`@>`(조상) 연산자 방향은 모두 맞다.

## 5. 코루틴 — `kotlin-coroutine-basics` · `kotlin-coroutine-basics-deep-dive`

### [불일치·수정함] 상태 머신이 "함수 하나당 하나씩 생기는 게 아니다"

- 위치: `kotlin-coroutine-basics-deep-dive/index.md` 「경계 조건」
- 원문: "상태 머신은 **함수 하나당 하나씩 생기는 게 아니라**, 람다로 넘긴 suspend 블록마다 별도로 생성된다."
- 같은 글의 본문이 `twoSteps` 함수 하나에 대해 `StateMachineKt$twoSteps$1`이라는 상태 머신 클래스를 보여준다. 문장이 본문과 정면으로 어긋난다.
- "상태 머신은 **이름 붙은 suspend 함수에만** 생기는 게 아니라…"로 고쳤다.

### 확인된 것 — 인용된 바이트코드가 실제 컴파일 결과와 일치한다

`kotlinc`를 내려받아 글의 `twoSteps` 함수를 컴파일하고 `javap -c -p`로 다시 떴다. 글이 쓴 1.9.24는 JDK 26의 버전 문자열을 파싱하지 못해 실행되지 않아 2.2.0으로 돌렸는데, **오프셋과 상수 풀 인덱스까지 글과 완전히 같았다.**

```
        55: getfield      #15   // Field StateMachineKt$twoSteps$1.label:I
        58: tableswitch   { // 0 to 2
                       0: 84
                       1: 116
                       2: 150
                 default: 171
            }
        ...
        97: ldc2_w        #50   // long 10l
       100: aload_2
       101: aload_2
       102: iconst_1
       103: putfield      #15   // label = 1
       106: invokestatic  #57   // DelayKt.delay
       109: dup
       110: aload_3
       111: if_acmpne     121
       114: aload_3
       115: areturn
```

`invokeSuspend`도 같다(`2: putfield #34 // result`, `20: invokestatic #45 // twoSteps`, `23: areturn`). 글이 `...`으로 줄인 5~13 구간은 실제로 `ldc #39 // int -2147483648` + `ior` + `putfield`, 즉 본문이 서술한 "`label`의 최상위 비트를 세팅한 뒤"가 맞다.

- 「직접 확인」의 `suspendCoroutine` + `startCoroutine` 예제는 실행 순서를 따라가면 글에 실린 출력과 정확히 일치한다(1 → 2 → awaitValue:A → 3 → 5 → 4 → awaitValue:B → 7 → 6 → completion). `Result<Unit>`의 `toString`이 `Success(kotlin.Unit)`인 것도 맞다.
- 기본 개념 글의 스레드·코루틴 비교표, `delay` 대 `Thread.sleep`, `launch` 대 `async` 구분에서 문제를 찾지 못했다.

## 6. Kotlin 애노테이션·컬렉션 — `kotlin-annotation-use-site-target` · `…-deep-dive` · `kotlin-list-contains-vs-set-contains`

### [확인·수정함] `@all` 타깃 설명에서 `property`가 빠졌다 (두 글 모두)

- 위치: 기본개념 글 「핵심 정리」 표 마지막 행, 딥다이브 「경계 조건」
- [Kotlin 2.2 릴리스 노트](https://kotlinlang.org/docs/whatsnew22.html)는 `@all`의 대상을 `param`, **`property`**, `field`, `get`, `setparam`(+`@JvmRecord`면 record component)으로 나열한다. 두 글 다 `property`를 빼고 세 곳으로 적었다.
- **kotlinc 2.2.0으로 직접 컴파일해 확인했다.** `class Holder(@all:Ann val email: String)`을 `-Xannotation-target-all`로 컴파일하면 애노테이션이 **네 곳**에 붙는다.

  ```
  private final java.lang.String email;              <- field
  public Holder(java.lang.String);  parameter 0      <- param
  public final java.lang.String getEmail();          <- get
  public static void getEmail$annotations();         <- property (ACC_SYNTHETIC)
  ```

  `var`로 바꿔 컴파일하면 `setEmail(String)`의 파라미터까지 **다섯 곳**이다.
- 기본개념 글의 표에 `property`를 넣고, 딥다이브의 "세 곳"을 "네 곳"으로, "`var`였다면 네 곳"을 "다섯 곳"으로 고쳤다. `property` 몫이 `getEmail$annotations()` 합성 메서드로 나타나 `javap` 출력에서 세기 쉽게 빠진다는 단서도 함께 넣었다.

### 확인된 것 (1차 출처 대조)

- `kotlin-list-contains-vs-set-contains`가 인용한 stdlib 소스는 [v2.2.20 원본](https://github.com/JetBrains/kotlin/blob/v2.2.20/libraries/stdlib/jvm/builtins/Collections.kt)과 문자 단위로 일치한다. 파일 헤더의 `@file:kotlin.internal.JvmBuiltin`·`@file:kotlin.internal.SuppressBytecodeGeneration`, `Collection.contains`(89행)·`List.contains`(226행)·`Set.contains`(451행) 선언 모두 그대로다.
- 두 내부 애노테이션의 doc 주석 인용도 원본과 일치한다.
- 기본 타깃 우선순위 `param` → `property` → `field`, Java 애노테이션이 `property`를 건너뛰고 `field`로 가는 규칙, `-Xannotation-default-target=param-property`와 기본값 `first-only`는 모두 Kotlin 2.2 문서와 일치한다.
- 벤치마크 표의 배율은 자체 정합적이다. B 크기 제곱에 비례하는 List 쪽 증가(0.57 → 48.98 → 1,405.22 ms가 각각 100배·25배)와, HashSet 생성 비용이 크기에 선형인 것(50,000에 3.53 ms, 100,000에 5.67 ms)이 모두 맞물린다.

## 7. JVM — `jvm-basics` · `jvm-gc`

### [확인·수정함] `Evacuation Failure`를 G1의 Full GC 전환 신호로 설명한다

- 위치: `jvm-gc/index.md` 「동작 원리」 — "Full GC(`G1 Compaction Pause`)로 전환된다. **로그의 `Evacuation Failure`가 이 상황이다.**"
- 그렇지 않다. 같은 글이 바로 아래에 싣는 46MB G1 로그에도 `Evacuation Failure: Allocation`이 두 번 찍히지만 그 실행은 **Full GC 없이 끝난다**(글의 성능 표에도 G1 Full GC 0회로 적혀 있다).
- 재현으로도 같았다. 46MB·G1 3회 실행 모두 `Evacuation Failure`가 Young 정지에 찍혔고 Full GC는 0회였다. 실제 전환이 일어난 42MB 실행에서 찍힌 줄은 `Pause Full (G1 Compaction Pause)`이고 `Evacuation Failure` 문자열이 없다.
- 리전 복사 실패 표시일 뿐 Full GC 전환과 1:1이 아니라는 쪽으로 고쳤다. Serial·Parallel 쪽의 "로그의 `Allocation Failure`가 이 상황이다"는 실제로 `Pause Full (Allocation Failure)`로 찍히므로 그대로 뒀다.

### 확인된 것 (직접 실행)

`GcDemo`를 글에 적힌 그대로(`-Xms46m -Xmx46m`, 컬렉터만 교체) 각 3회 실행한 결과가 글의 표와 일치한다.

| 컬렉터 | 글의 표 | 재현 결과(3회 모두) |
|---|---|---|
| Serial | Young 13회 / Full 1회 | Young 13회 / Full 1회 |
| Parallel | Young 26~28회 / Full 1회 | Young 26회 / Full 1회 |
| G1 | Young 8~9회 / Full 0회 | Young 9회 / Full 0회 |

- 글이 인용한 Serial 로그 두 줄(`GC(12) … 33M->44M(44M)`, `GC(13) Pause Full … 44M->33M(44M)`)의 힙 수치가 재현 결과와 정확히 같다. Young GC 뒤에 사용량이 오히려 늘어난 `33M->44M`도 실제로 그렇게 찍힌다.
- "힙을 42MB로 더 줄이면 G1도 결국 Full GC로 전환된다(3회 모두 재현)"도 그대로 재현됐다.
- `jvm-basics`의 static 초기화 예제도 실행 결과가 글과 같다.
- `-XX:MaxTenuringThreshold` 기본 15, `-XX:InitiatingHeapOccupancyPercent` 기본 45, JDK 9부터 G1이 기본 컬렉터, Java 8의 PermGen→Metaspace 전환, Java 11부터 JRE 단독 배포 중단, 클래스 로더 3계층과 `Prohibited package name` 보호 장치 — 모두 맞다.

## 8. MyBatis · Spring Boot — `mybatis-parameter-binding` · `spring-vs-spring-boot`

두 글에서는 고칠 것을 찾지 못했다.

- MyBatis 공식문서 인용이 정확하다. [String Substitution](https://mybatis.org/mybatis-3/sqlmap-xml.html) 원문은 `#{}`에 대해 "While this is **safer, faster and almost always preferred**, sometimes you just want to directly inject an unmodified string into the SQL Statement"라고 쓴다.
- `Set.of(...).contains(null)`이 NPE를 던진다는 주석은 맞다. JDK 26에서 직접 실행해 확인했다.
- MySQL Connector/J의 `useServerPrepStmts` 기본값 `false`, pgjdbc의 `prepareThreshold` 기본값 5, `@Param`을 붙이면 `<foreach collection="list">`가 통하지 않는다는 서술, `'#{name}'`이 `'?'`가 되어 실패한다는 서술 모두 맞다.
- `@SpringBootApplication`의 3중 구성, `AutoConfiguration.imports` 후보 목록, `@ConditionalOnClass`/`@ConditionalOnMissingBean`의 역할 구분, "자동설정은 사용자 빈이 모두 등록된 뒤에 적용된다"는 순서 서술은 Spring Boot 문서와 일치한다.
- "클래스패스에 없는 이름을 `spring.autoconfigure.exclude`에 적으면 예외도 경고도 없이 무시된다"도 맞다. `AutoConfigurationImportSelector`는 **클래스패스에 존재하면서** 자동설정 클래스가 아닌 경우에만 `IllegalStateException`을 던진다.

## 9. 단독 글 — `git-worktree` · `heap-basics` · `refactoring-basics` · `bandwidth-and-spectrum-division`

네 글 모두 고칠 것을 찾지 못했다. 전부 재실행으로 확인했다.

### `git-worktree` — git 2.45.1에서 그대로 재현됨

| 글의 서술 | 재현 |
|---|---|
| `Preparing worktree (checking out 'feature-x')` / `HEAD is now at …` | 동일 |
| 같은 브랜치 중복 체크아웃 시 `fatal: 'feature-x' is already used by worktree at '…'` | 동일 |
| 링크드 워크트리의 `.git`이 `gitdir: …/.git/worktrees/wt-feature` 한 줄 | 동일 |
| 미추적 파일이 있으면 `fatal: '…' contains modified or untracked files, use --force to delete it` | 동일 |
| **`stash`가 워크트리 간 공유된다** | 동일. 메인에서 `git stash`한 항목이 링크드 쪽 `git stash list`에도 그대로 보였다 |

### `heap-basics` — 코드를 실행해 표와 대조

글의 `MinHeap`을 그대로 돌린 결과가 두 표의 모든 행과 일치한다. 본문이 설명하는 중간 단계(`push(1)`의 두 단계 sift-up, 첫 `pop()`의 sift-down)도 인덱스 계산과 맞는다.

### `refactoring-basics` — 인용 대조

- [Refactoring Malapropism](https://martinfowler.com/bliki/RefactoringMalapropism.html)과 `refactoring.com`의 정의 인용이 원문과 일치한다.
- 예시 두 개 모두 논지가 맞다. `?:`의 단축 평가가 사라져 `fetchDefaultName()`이 매번 불리는 문제, `!!`(→ `NullPointerException`)와 `Map.getValue()`(→ `NoSuchElementException`)의 예외 타입 차이 모두 정확하다.

### `bandwidth-and-spectrum-division` — 코드 블록을 그대로 실행

글의 Python 블록을 파일로 떼어 그대로 돌렸다. **출력이 글에 실린 결과와 한 글자도 다르지 않다.** `rng = np.random.default_rng(0)`으로 시드를 고정해 둔 덕이다.

- 간섭항 `sinc(Δ·T)·cos(πΔT(2k+1) + φ)`는 정합 필터를 직접 적분하면 그대로 나오고, 표의 `sinc` 열 값이 모두 `sin(πx)/(πx)`와 일치한다.
- 오류율 0.25의 유도, 섀넌 산술(`20·log₂101 = 133.2`, 가드밴드 1개면 5%·7개면 35% 손실), `B → ∞`에서 `S/(N₀·ln2)`로 수렴, 나이키스트의 기저대역 `2B`/대역통과 `B` 구분 모두 맞다.

## 10. `jdbc-driver-value-paths` (검수 완료 글 — 지적만, 수정 없음)

`docs/review-status.md`에서 `[V]`이므로 **아무것도 고치지 않았다.** 대조 결과 고칠 것도 나오지 않았다.

인용한 Connector/J 9.1.0 소스 세 조각을 [태그 `9.1.0`의 원본](https://github.com/mysql/mysql-connector-j/tree/9.1.0)과 대조했고 전부 일치한다.

- `StringValueEncoder.getBytes()`의 네 갈래 분기(94행부터), `AbstractValueEncoder.escapeBytesIfNeeded()`의 `// Send as hex` 블록, `isEscapeNeededForString()`의 일곱 case 모두 주석까지 그대로다.
- 본문만 서술하고 코드를 싣지 않은 `StringUtils.escapeString()`(1745행)도 서술이 맞다. 작은따옴표는 겹쳐 쓰고, 백슬래시는 두 개로, `\032`는 `\Z`로, 큰따옴표는 `useAnsiQuotedIdentifiers`일 때만 이스케이프하며, `¥`(¥)·`₩`(₩) case 둘이 실제로 있다. 링크에 붙은 행 번호도 정확하다.
- coercibility 서술(컬럼 2 < 리터럴 4, 낮은 쪽 콜레이션 채택)과 "By default, a hexadecimal literal is a binary string" 인용도 MySQL 문서와 맞다.
- 추론과 사실을 나눈 표기가 일관된다. `Execute` 줄의 텍스트에 대해 "관측된 사실은 여기까지다", "여기까지가 추론이다"로 경계를 그어 두었다.

## 종합

처음에 "판단이 필요하다"고 남겨 뒀던 항목은 재현과 1차 출처 대조로 전부 결론을 냈다. 총 **11편을 고쳤다.**

### 고친 것

| 글 | 무엇 |
|---|---|
| `nested-set` | `left`/`right`가 SQL 예약어라 SQL 블록이 전부 문법 오류 → `lft`/`rgt`, 이유 한 줄 추가. `비어난` → `비운` |
| `jvm-gc` | `Evacuation Failure`를 Full GC 전환 신호로 설명 — 같은 글의 로그와 어긋남 |
| `closure-table` | 자기 참조 행 설명이 결과를 반대로 말함 / 참고 문헌의 "처음 정리한 책" |
| `transactional-self-invocation` | 예시 코드의 예외 타입이 바로 아래 테스트와 불일치 |
| `kotlin-coroutine-basics-deep-dive` | 상태 머신 서술이 같은 글 본문과 모순 |
| `kotlin-annotation-use-site-target` | `@all` 대상에서 `property` 누락 |
| `kotlin-annotation-use-site-target-deep-dive` | `@all` 실측 "세 곳" → 실제로는 네 곳(`var`면 다섯) |
| `transaction-isolation-levels` | H2 REPEATABLE READ 팬텀 차단이 보장된 동작이 아니라는 것 + `SNAPSHOT` |
| `isolation-levels-and-anomalies` | 「구현체별 차이」 표의 H2 행 |
| `planner-row-estimation` | "0/0" → PostgreSQL이 나눗셈을 건너뛰는 구조 + `selfuncs.c` 인용·출처 |
| `slow-query-after-restart` | 같은 "0/0" 서술 |
| `spring-aop-proxy` | JDK 프록시의 "적용 안 되는 클래스: 없음" |
| `path-enumeration` | 「핵심 정리」 표의 조상 조회 식이 본문과 반대 |

### 오류가 아니었던 것

- `query-plan-basics`의 Hash Join 플랜 `actual rows=50 loops=1` — PostgreSQL 16.15로 재현한 결과 글이 맞다. `evt` 스캔에는 조인 조건이 아니라 자기 필터만 걸리므로 어느 플랜에서든 50행을 낸다.

### 남은 미확인

- `jdbc-driver-value-paths`의 MySQL 실험은 재현하지 않았다. 검수 완료 글이라 수정 대상이 아니고, 인용한 드라이버 소스는 전부 원본과 대조했다.

**커밋하지 않았다.** 수정은 전부 워킹 트리에만 있다.
