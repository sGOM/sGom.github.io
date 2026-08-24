---
title: Kotlin List.contains를 Set으로 바꾸면 빨라지는 이유
description: 리스트 원소 포함 여부를 반복 확인할 때 Set으로 미리 바꾸는 것과 그냥 List로 쓰는 것을 벤치마크로 비교하고, 차이의 근거를 stdlib 소스에서 찾는다
pubDate: 2026-08-14
updatedDate: 2026-08-24
category: "Kotlin"
tags: ["파고들기", "Kotlin", "컬렉션", "성능"]
---

## 왜 필요한가

리스트 A의 원소가 리스트 B에 몇 개 포함되는지 셀 때 `b.contains(x)`를 그대로 쓰는 코드가 흔하다. B를 `Set`으로 미리 바꾸면 빨라진다는 건 알려진 이야기다.

그런데 컴파일이나 JIT 과정에서 이미 같은 최적화가 일어난다면, 명시적으로 `Set`으로 바꾸는 코드는 있으나 마나 한 셈이다. 실제로 그런 최적화가 있는지 확인한다.

## 겉으로 보이는 것

`b.contains(x)` 호출은 `b`의 타입이 `List<Int>`든 `Set<Int>`든 코드 모양이 똑같다. 호출부만 보면 컴파일러가 타입에 따라 알아서 다른 전략을 골라 쓸 여지가 있어 보인다.

## 동작 원리

Kotlin의 `List`, `Set`은 코틀린 전용 클래스가 아니라 JVM에서 각각 `java.util.List`, `java.util.Set`에 그대로 대응하는 매핑 타입이다. `contains`는 `Collection` 인터페이스에 선언된 추상 연산자 함수이고, 실제 동작은 런타임에 `b`가 어떤 클래스의 인스턴스인지에 따라 가상 디스패치(virtual dispatch)된다.

- `b`가 `ArrayList`라면 `contains`는 `indexOf`를 호출해 앞에서부터 순서대로 원소를 비교한다. 찾거나 끝에 닿을 때까지 순회하므로 평균·최악 모두 O(n)이다.
- `b`가 `HashSet`이라면 `contains`는 `hashCode()`로 버킷을 찾아 그 버킷 안의 소수 원소만 비교한다. 평균 O(1)이다.

컴파일러는 어느 시점에도 `ArrayList`를 `HashSet`으로 바꿔주지 않는다. "이 컬렉션이 반복적으로 조회될 것"이라는 정보는 실행 전 정적 분석으로 알 수 없기 때문이다.

해시 테이블 기반 자료구조는 `toHashSet()`을 직접 호출해야 만들어진다.

## 코드로 따라가기

kotlinc 2.2.20 배포본의 `kotlin-stdlib-sources.jar` 소스([GitHub 원본](https://github.com/JetBrains/kotlin/blob/v2.2.20/libraries/stdlib/jvm/builtins/Collections.kt))에서 `contains`는 [`Collection`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-collection/) 인터페이스의 추상 함수다. [`List`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-list/)와 [`Set`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-set/)은 오버라이드만 표시하고 별도 구현을 갖지 않는다.

[`Collection.contains` 공식 문서](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-collection/contains.html)도 "동작은 구현체마다 다르며, 보통 `Any.equals`로 비교한다(behavior is implementation-specific, but usually, it uses `Any.equals` to compare elements)"고 명시한다.

```kotlin
// libraries/stdlib/jvm/builtins/Collections.kt
@file:kotlin.internal.JvmBuiltin
@file:kotlin.internal.SuppressBytecodeGeneration

public actual interface Collection<out E> : Iterable<E> {
    public actual operator fun contains(element: @UnsafeVariance E): Boolean
    // ...
}

public actual interface List<out E> : Collection<E> {
    actual override fun contains(element: @UnsafeVariance E): Boolean
    // ...
}

public actual interface Set<out E> : Collection<E> {
    actual override fun contains(element: @UnsafeVariance E): Boolean
    // ...
}
```

파일 맨 위의 `@file:kotlin.internal.JvmBuiltin`, `@file:kotlin.internal.SuppressBytecodeGeneration`은 stdlib 내부 전용 애노테이션이다. 둘 다 `internal`이라 kotlinlang.org 공식 API 문서에 나오지 않는다.

1차 출처는 [GitHub 소스(`kotlin/internal/Annotations.kt`, v2.2.20)](https://github.com/JetBrains/kotlin/blob/v2.2.20/libraries/stdlib/src/kotlin/internal/Annotations.kt#L114-L132)뿐이다. 정의에 붙은 doc 주석을 그대로 옮기면:

- `JvmBuiltin`: "Specifies that all file declarations are builtins and should be serialized to .kotlin_metadata" — 이 파일의 선언이 컴파일러가 이미 알고 있는 내장(builtin) 타입이라는 표시다. 실제 구현이 아니라 시그니처 정보만 `.kotlin_metadata`로 직렬화된다.
- `SuppressBytecodeGeneration`: "Do not generate bytecode for declarations in the file (and therefore do not lower them)" — 이 파일의 선언은 바이트코드로 컴파일되지 않는다.

두 애노테이션을 합치면, 이 `Collection`/`List`/`Set` 선언은 컴파일러와 IDE가 타입 검사에 쓰는 시그니처일 뿐 클래스 파일을 만들지 않는다.

JVM에서 이 타입들은 `java.util.Collection`, `java.util.List`, `java.util.Set`에 직접 대응한다. `contains`의 실제 구현은 `ArrayList`나 `HashSet` 같은 JDK 클래스가 갖는다.

Kotlin 레벨의 선언은 "무엇을 조회하는지"만 정의한다. "어떻게 찾는지"는 런타임에 선택된 구현 클래스가 정한다.

## 직접 확인

Kotlin 2.2.20, JDK 26.0.1(Windows)에서 실측했다. `measureNanoTime`으로 각 케이스를 워밍업 5회 후 반복 측정한 평균이다.

JMH 같은 전용 도구가 아니므로 절대치보다 배율의 경향을 본다.

```kotlin
fun countMatchesList(a: List<Int>, b: List<Int>): Int {
    var count = 0
    for (x in a) if (b.contains(x)) count++
    return count
}

fun countMatchesSet(a: List<Int>, b: List<Int>): Int {
    val bSet = b.toHashSet()
    var count = 0
    for (x in a) if (bSet.contains(x)) count++
    return count
}
```

| 케이스 | A 크기 | B 크기 | List.contains 평균 | toHashSet+contains 평균 | 배율 |
|---|---|---|---|---|---|
| 소규모 | 1,000 | 1,000 | 0.57ms | 0.20ms | 2.8배 |
| 중간 | 10,000 | 10,000 | 48.98ms | 0.60ms | 81.6배 |
| 대규모 | 50,000 | 50,000 | 1,405.22ms | 3.53ms | 398.5배 |
| A 작음 / B 큼 | 100 | 100,000 | 7.20ms | 5.67ms | 1.3배 |

두 방식 모두 같은 결과 개수를 반환하는 걸 확인했다. B의 크기가 커질수록 List 방식은 눈에 띄게 느려지고, Set 방식은 거의 일정하게 유지된다.

## 경계 조건

조회 횟수가 적으면 `toHashSet()`의 1회성 변환 비용(O(B))을 상쇄하지 못한다. 위 표의 "A 작음 / B 큼" 케이스(A=100, B=100,000)가 배율 1.3배에 그친 이유다.

## 대안과 트레이드오프

`toHashSet()`은 원소 수만큼 메모리를 더 쓴다. B가 커서 메모리가 빠듯하거나 한 번만 조회하고 버린다면 변환이 손해다.

B를 이후에도 재사용한다면 변환 비용은 한 번만 내고 계속 이득을 본다.

## 언제 쓰고 언제 안 쓰나

반복문 안에서 `contains`를 여러 번 호출한다면 `Set`으로 미리 바꾼다. 한 번만 조회하거나 A가 B에 비해 아주 작다면 변환 비용이 이득을 상쇄하므로 그대로 둔다.

## 참고

- [Kotlin API docs — Collection](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-collection/)
- [Kotlin API docs — Collection.contains](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-collection/contains.html)
- [Kotlin API docs — List](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-list/)
- [Kotlin API docs — Set](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/-set/)
- [GitHub JetBrains/kotlin — Collections.kt (v2.2.20)](https://github.com/JetBrains/kotlin/blob/v2.2.20/libraries/stdlib/jvm/builtins/Collections.kt)
- [GitHub JetBrains/kotlin — internal/Annotations.kt (v2.2.20)](https://github.com/JetBrains/kotlin/blob/v2.2.20/libraries/stdlib/src/kotlin/internal/Annotations.kt#L114-L132)
