---
title: Kotlin 애노테이션 use-site target
description: Kotlin 프로퍼티에 애노테이션을 붙일 때 field·get·set·param 중 어디로 갈지 정하는 use-site target을 표로 정리한다
pubDate: 2026-08-13
category: "Kotlin"
tags: ["기본개념", "Kotlin", "애노테이션"]
---

## 왜 필요한가

Kotlin의 `val`/`var` 프로퍼티 하나는 컴파일되면 여러 JVM 요소로 나뉜다. backing field와 getter가 기본이고, `var`면 setter가 더해지고, 주 생성자 파라미터로 선언했다면 생성자 파라미터까지 붙는다.

```kotlin
class Example(val foo: String)
```

`foo`는 필드 하나, getter 하나, 생성자 파라미터 하나로 컴파일된다. 여기에 `@Ann val foo: String`처럼 타깃 없이 애노테이션을 붙이면, 컴파일러가 이 중 하나를 골라 붙인다. 리플렉션으로 필드를 뒤지는 라이브러리와 getter를 뒤지는 라이브러리가 다른 곳을 본다면, 애노테이션을 붙였는데도 인식되지 않는 상황이 생긴다. use-site target은 이 위치를 명시하는 문법이다.

## 핵심 정리

| 타깃 | 붙는 곳 | 비고 |
|---|---|---|
| `file` | 파일 전체 | `package` 선언 위, import 앞에 쓴다 |
| `param` | 주 생성자 파라미터 | 생성자 파라미터로 선언된 프로퍼티에만 |
| `property` | Kotlin 프로퍼티 자체 | JVM에 대응하는 요소가 없다. Java로 선언한 애노테이션에는 못 쓴다 |
| `field` | backing field | |
| `get` | getter | |
| `set` | setter | `var`에만 |
| `setparam` | setter의 파라미터 | `var`에만 |
| `delegate` | 위임 인스턴스를 담는 필드 | `by` 위임 프로퍼티에만 |
| `receiver` | 확장 함수/프로퍼티의 리시버 파라미터 | 확장 함수·프로퍼티에만 |
| `all` (2.2~, 실험적) | `param`+`field`+`get`(+`setparam`) 한 번에 | `-Xannotation-target-all` 플래그 필요 |

## 예시

```kotlin
class Example(
    @field:Ann val foo: String,
    @get:Ann val bar: String,
    @param:Ann val quux: String
)
```

Kotlin 2.2.0으로 컴파일해 `javap`로 확인하면 `foo`는 private 필드에, `bar`는 `getBar()`에, `quux`는 생성자 파라미터에 애노테이션이 붙는다. 셋 다 코드에 쓴 위치 그대로다.

`by` 위임 프로퍼티는 위임 인스턴스를 담는 필드가 따로 생기므로 거기에 붙이려면 `delegate`를 쓴다.

```kotlin
class Holder {
    @delegate:Ann
    val lazyValue: String by lazy { "z" }
}
```

`lazyValue`가 아니라 컴파일러가 만든 `lazyValue$delegate` 필드(타입 `kotlin.Lazy`)에 애노테이션이 붙는다.

## 혼동하기 쉬운 것

**타깃을 안 쓰면 어디로 가는가.** 컴파일러는 애노테이션의 `@Target`을 보고 적용 가능한 타깃 중 `param` → `property` → `field` 순서로 첫 번째를 고른다. 실제로 확인한 결과:

```kotlin
class Ctor(@Ann val inCtor: String)          // 생성자 파라미터 -> param에만

class Holder {
    @Ann val plain: String = "x"             // 본문 프로퍼티 -> property로
}
```

`inCtor`는 생성자 파라미터로 선언됐으므로 `param`이 적용 가능해 거기서 멈춘다. `plain`은 생성자 파라미터가 아니라 `param`이 적용 불가능하고, `property`가 적용 가능하므로 `property`로 간다. `property`는 JVM에 실체가 없어서, 컴파일러는 `getPlain$annotations()`라는 빈 정적 메서드를 만들어 거기에 애노테이션을 붙인다. 필드가 아니다.

이 우선순위와 합성 메서드가 생기는 이유는 [Kotlin 프로퍼티가 여러 JVM 요소로 컴파일되는 이유](/posts/kotlin-annotation-use-site-target-deep-dive/)에서 바이트코드로 다룬다.

**`property`와 `field`도 다르다.** `property`는 Kotlin 메타데이터 수준의 개념이라 Kotlin으로 선언한 애노테이션에만 쓸 수 있다. Java로 선언한 애노테이션은 `property` 타깃 자체가 적용 불가능하므로, 기본 타깃 우선순위에서 자동으로 건너뛰고 `field`로 간다.

## 언제 어떤 것을 쓰나

- 리플렉션으로 필드를 직접 읽는 라이브러리(Gson 등)라면 `@field:`
- getter 규칙을 따르는 라이브러리(Bean Validation 등)라면 `@get:`
- 생성자 주입 프레임워크라면 대개 기본 타깃(`param`)만으로 충분하다
- 위임 프로퍼티에 애노테이션 프로세서를 적용하려면 `@delegate:`
- 여러 타깃에 동시에 붙여야 하면 `@all:`을 검토할 수 있지만, 2.2 기준 실험적 기능이라 옵트인 플래그가 필요하고 안정성 보장이 없다

## 더 깊이

- [Kotlin 프로퍼티가 여러 JVM 요소로 컴파일되는 이유](/posts/kotlin-annotation-use-site-target-deep-dive/) — 컴파일러가 기본 타깃을 고르는 규칙과 실제 바이트코드를 확인한 기록

## 참고

- [Kotlin Docs — Annotations: Annotation use-site targets](https://kotlinlang.org/docs/annotations.html#annotation-use-site-targets)
- [Kotlin Docs — What's New in Kotlin 2.2: New defaulting rules for use-site annotation targets](https://kotlinlang.org/docs/whatsnew22.html)
