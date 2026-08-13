---
title: Kotlin 프로퍼티가 여러 JVM 요소로 컴파일되는 이유
description: use-site target이 왜 필요한지 실제 바이트코드를 javap로 확인한다
pubDate: 2026-08-13
category: "Kotlin"
tags: ["파고들기", "Kotlin", "애노테이션", "바이트코드"]
---

## 전제

use-site target 종류와 언제 어떤 걸 쓰는지는 [Kotlin 애노테이션 use-site target](/posts/kotlin-annotation-use-site-target/)에서 표로 정리했다. 타깃을 안 쓰면 컴파일러가 `param` → `property` → `field` 순으로 첫 번째 적용 가능한 타깃을 고른다는 것도 그 글에서 다뤘다.

## 왜 필요한가

`property`로 간다는 게 정확히 무슨 뜻인지가 남는다. Kotlin 프로퍼티는 JVM 스펙에 없는 개념이라 클래스 파일에 "프로퍼티"라는 요소 자체가 없다. 그럼 `property` 타깃을 고른 애노테이션은 대체 어디에 붙는가. 이 글은 그 답을 바이트코드로 직접 본다.

## 동작 원리

Kotlin 프로퍼티가 JVM으로 컴파일되는 규칙은 이렇다.

- `val`이면 backing field + getter가 생긴다.
- `var`면 여기에 setter가 더해진다.
- 주 생성자 파라미터로 선언했다면 생성자 파라미터도 더해진다.
- `by`로 위임했다면 위임 인스턴스를 담는 `프로퍼티이름$delegate` 필드가 대신 생긴다.

애노테이션에 타깃을 안 쓰면, 컴파일러는 애노테이션의 `@Target`을 보고 이 중 적용 가능한 타깃을 `param` → `property` → `field` 순서로 검사해 첫 번째로 맞는 것을 고른다. 문제는 `property`가 골라졌을 때다. 지금까지 나열한 것 중 `property`에 대응하는 실제 JVM 요소가 없다. 컴파일러는 이 경우 `get프로퍼티이름$annotations()`라는 내용 없는 정적 메서드를 합성해서 거기에 애노테이션을 붙인다. 실행되는 코드가 아니라, 애노테이션을 걸어 둘 자리다.

Kotlin 2.2부터는 이 우선순위 규칙 자체가 바뀔 예정이다. `-Xannotation-default-target=param-property` 플래그를 켜면 `param`이 적용 가능할 때 `param`과 `property` 양쪽에 동시에 붙는다(기존에는 `param` 하나만 골랐다). 아직 옵트인이고 기본값은 이전 규칙(`first-only`)이다.

## 코드로 따라가기

```kotlin
annotation class Ann

class Example(
    @field:Ann val foo: String,
    @get:Ann val bar: String,
    @param:Ann val quux: String
)
```

```kotlin
annotation class Ann

class Holder {
    @Ann val plain: String = "x"          // 타깃 미지정, 생성자 파라미터 아님

    @delegate:Ann
    val lazyValue: String by lazy { "z" }
}

class Ctor(@Ann val inCtor: String)        // 타깃 미지정, 생성자 파라미터

fun @receiver:Ann String.shout(): String = this.uppercase()
```

## 직접 확인

Kotlin 2.2.0 컴파일러(JetBrains 공식 배포, `kotlin-compiler-2.2.0.zip`)로 위 코드를 컴파일하고 `javap -p -v`(JDK 26.0.1)로 클래스 파일을 뜯었다.

**명시적 타깃 — `Example`**

```
$ kotlinc-jvm Sample.kt -include-runtime -d sample.jar
$ javap -p -v Example.class
```

```
  private final java.lang.String foo;
    RuntimeVisibleAnnotations:
      0: #7()
        Ann

  public Example(java.lang.String, java.lang.String, java.lang.String);
    ...
    RuntimeVisibleParameterAnnotations:
      parameter 2:
        0: #7()
          Ann

  public final java.lang.String getBar();
    ...
    RuntimeVisibleAnnotations:
      0: #7()
        Ann
```

`@field:Ann`은 `foo` 필드에, `@param:Ann`은 생성자의 세 번째 파라미터(`quux`)에, `@get:Ann`은 `getBar()`에 그대로 붙었다.

**타깃 미지정 — `Holder.plain`**

```
  private final java.lang.String plain;
    descriptor: Ljava/lang/String;
    flags: (0x0012) ACC_PRIVATE, ACC_FINAL
    RuntimeInvisibleAnnotations:
      0: #52()
        org.jetbrains.annotations.NotNull
                                              ← Ann이 없다

  public static void getPlain$annotations();
    descriptor: ()V
    flags: (0x1009) ACC_PUBLIC, ACC_STATIC, ACC_SYNTHETIC
    Code:
      stack=0, locals=0, args_size=0
         0: return
    Deprecated: true
    RuntimeVisibleAnnotations:
      0: #54()
        Ann
```

`plain` 필드에는 `Ann`이 없다. 대신 몸체가 `return` 하나뿐인 합성 정적 메서드 `getPlain$annotations()`가 생기고, 거기에 `Ann`이 붙는다. 이 메서드는 `ACC_SYNTHETIC`이고 `Deprecated: true`까지 붙어 있어서, 일반 코드에서 호출하거나 자동완성에 걸릴 일이 없게 만들어 놨다. 리플렉션으로 프로퍼티의 애노테이션을 읽는 코드(`KProperty.annotations`)가 참조하는 자리다.

**타깃 미지정, 생성자 파라미터 — `Ctor`**

```
  public Ctor(java.lang.String);
    ...
    RuntimeVisibleParameterAnnotations:
      parameter 0:
        0: #7()
          Ann
```

`getPlain$annotations()` 같은 합성 메서드는 생기지 않는다. `param`이 우선순위에서 먼저 걸려 거기서 멈추기 때문이다.

**delegate — `Holder.lazyValue`**

```
  private final kotlin.Lazy lazyValue$delegate;
    descriptor: Lkotlin/Lazy;
    flags: (0x0012) ACC_PRIVATE, ACC_FINAL
    RuntimeVisibleAnnotations:
      0: #54()
        Ann
```

`lazyValue`가 아니라 위임 인스턴스를 담는 `lazyValue$delegate` 필드(타입 `kotlin.Lazy`)에 붙는다.

**receiver — `shout`**

확장 함수는 정적 메서드로 컴파일되고 리시버가 첫 번째 파라미터가 된다.

```
  public static final java.lang.String shout(java.lang.String);
    ...
    RuntimeVisibleParameterAnnotations:
      parameter 0:
        0: #8()
          Ann
```

`@receiver:Ann`은 이 첫 번째 파라미터의 애노테이션으로 들어간다.

## 경계 조건

`property` 타깃은 Java로 선언한 애노테이션에는 적용할 수 없다. Java 애노테이션의 `@Target`에는 `PROPERTY`라는 개념 자체가 없기 때문이다. 타깃을 안 쓴 Java 애노테이션은 이 때문에 우선순위에서 `property`를 자동으로 건너뛰고 `field`로 간다. Kotlin 공식 문서 예시도 이 경우를 `@param:X @field:X`와 동등하다고 설명한다(2.2의 새 규칙 기준).

`@all` 타깃은 실험적이다. 플래그 없이 쓰면 컴파일 자체가 막힌다.

```
$ kotlinc-jvm -Xannotation-target-all X # 없이 컴파일
error: the feature "annotation all use site target" is experimental and should be
enabled explicitly. This can be done by supplying the compiler argument
'-Xannotation-target-all', but note that no stability guarantees are provided.
```

`-Xannotation-target-all`을 켜고 `@all:Ann val email: String`(주 생성자 파라미터)을 컴파일하면 `param`, `field`, `get`(getter) 세 곳 모두에 `Ann`이 붙는 것을 확인했다. `var`였다면 `setparam`까지 네 곳에 붙는다.

## 대안과 트레이드오프

`@all`은 `param`/`field`/`get`/`setparam`을 하나하나 나열하는 반복을 줄여 주지만, 2.2 기준 안정성 보장이 없는 실험적 기능이라 컴파일러 버전이 바뀌면 동작이 달라질 수 있다. 타깃을 하나씩 명시하는 방식은 장황해도 Kotlin 버전에 관계없이 동작한다.

## 참고

- [Kotlin Docs — Annotations: Annotation use-site targets](https://kotlinlang.org/docs/annotations.html#annotation-use-site-targets)
- [Kotlin Docs — What's New in Kotlin 2.2: New defaulting rules for use-site annotation targets](https://kotlinlang.org/docs/whatsnew22.html)
- [Kotlin Docs — JVM records: annotating record components](https://kotlinlang.org/docs/jvm-records.html)
