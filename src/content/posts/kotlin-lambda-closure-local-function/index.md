---
title: 람다, 익명 함수, 클로저, 로컬 함수 구분하기 — 객체 표현식과 함수 참조까지
description: 이름이 헷갈리는 여섯 용어를 return 동작과 변수 캡처 기준으로 가르고, 함수 안에 함수를 두는 선택이 무엇을 얻고 무엇을 잃는지 바이트코드로 확인한다
pubDate: 2026-08-31
category: "Kotlin"
tags: ["기본개념", "Kotlin", "람다", "클로저"]
---

## 왜 필요한가

`list.map { it * 2 }`에서 `{ it * 2 }`를 부르는 이름이 사람마다 다르다. 람다라고도, 익명 함수라고도, 클로저라고도 한다. Kotlin에서 앞의 둘은 서로 다른 문법이고 `return`을 썼을 때 어디로 돌아가는지가 다르다. 셋째는 문법이 아니라 성질이다.

용어를 뭉뚱그려도 평소에는 굴러간다. `forEach` 안에 쓴 `return` 한 줄이 바깥 함수까지 빠져나가는 코드를 만나면 그때 구분이 필요해진다.

아래 코드와 실행 결과는 모두 kotlinc-jvm 2.2.21(JVM 타깃 21)에서 확인했다.

## 용어 정리

- **람다 표현식**: 중괄호로 쓰는 함수 리터럴. `{ x: Int -> x * 2 }`. 파라미터가 하나면 이름을 생략하고 `it`으로 받는다.
- **익명 함수**: `fun` 키워드로 선언하되 이름을 붙이지 않은 함수 리터럴. `fun(x: Int): Int = x * 2`.
- **클로저**: 바깥 스코프에서 붙잡은 변수 묶음. 문법의 이름이 아니라서 람다, 익명 함수, 로컬 함수, 객체 표현식, 바운드 참조가 모두 가질 수 있다.
- **로컬 함수**: 다른 함수 본문 안에 `fun`으로 선언한 이름 있는 함수. 이름이 있으니 익명이 아니다.
- **객체 표현식**: `object : Runnable { ... }`. 이름 없는 클래스의 인스턴스를 그 자리에서 만든다. Java의 익명 클래스에 해당한다. 함수가 아니라 객체다.
- **함수 참조**: `::double`, `s::hashCode`. 이미 선언된 함수를 값으로 가리킨다. 새 함수를 정의하지 않는다. 공식 문서는 프로퍼티 참조(`String::length`)와 생성자 참조까지 묶어 [호출 가능 참조(callable reference)](https://kotlinlang.org/docs/reflection.html#callable-references)라 부른다.

공식 문서는 람다 표현식과 익명 함수를 묶어 [함수 리터럴(function literal)](https://kotlinlang.org/docs/lambdas.html#lambda-expressions-and-anonymous-functions)이라 부르고, 함수 리터럴이 접근하는 바깥 변수 묶음을 [클로저(closure)](https://kotlinlang.org/docs/lambdas.html#closures)라 부른다. 즉 "람다냐 익명 함수냐"와 "클로저냐"는 서로 다른 축의 질문이다.

뒤의 둘은 함수 리터럴이 아니다. 코드에서 같은 자리에 들어가서 함께 묶이지만, 객체 표현식은 객체를 만드는 문법이고 함수 참조는 이미 있는 선언을 가리키는 문법이다.

## 핵심 정리

| | 문법 | 이름 | 반환 타입 | 본문 마지막 식 | 본문의 `return` |
|---|---|---|---|---|---|
| 람다 표현식 | `{ x -> ... }` | 없음 | 항상 추론 | 반환값이 된다 | 바깥 함수에서 반환 |
| 익명 함수 | `fun(x: T): R { ... }` | 없음 | 블록 본문이면 명시 | 반환값이 아니다 | 자기 자신에서 반환 |
| 로컬 함수 | `fun name(x: T): R { ... }` | 있음 | 블록 본문이면 명시 | 반환값이 아니다 | 자기 자신에서 반환 |

람다의 `return`이 바깥 함수에서 반환한다는 것은 인라인 함수에 넘긴 경우에 한한다. 인라인이 아니면 `return`을 쓰는 것 자체가 막히는데, 「혼동하기 쉬운 것」에서 다룬다.

객체 표현식과 함수 참조는 함수 리터럴이 아니라서 이 표에 없다. 객체 표현식 안의 `override fun`은 이름 있는 보통 함수이므로 표의 로컬 함수 행과 같이 움직인다.

클로저도 이 표의 열이 아니다. 표의 세 문법 전부 바깥 변수를 캡처할 수 있고, 캡처하면 클로저다. 객체 표현식과 바운드 함수 참조도 마찬가지다.

## 항목별 설명

### 반환 타입

람다는 본문 마지막 식의 타입이 곧 반환 타입이다. 익명 함수는 식 본문(`= x * 2`)이면 추론되지만 블록 본문(`{ ... }`)이면 반환 타입을 직접 적어야 하고, 적지 않으면 `Unit`으로 간주된다.

```kotlin
val f = fun(x: Int) { return x * 2 }
```

```
A1.kt:1:30: error: return type mismatch: expected 'Unit', actual 'Int'.
val f = fun(x: Int) { return x * 2 }
                             ^^^^^
```

### `return`이 어디로 가는가

둘의 실질적인 차이는 여기다. 람다 안의 `return`은 람다를 감싼 함수에서 반환하고, 익명 함수 안의 `return`은 익명 함수 자신에서만 반환한다. 공식 문서는 앞의 것을 [비지역 반환(non-local return)](https://kotlinlang.org/docs/inline-functions.html#non-local-jump-expressions)이라 부른다.

## 예시

### 람다와 익명 함수의 `return`

```kotlin
fun withLambda(nums: List<Int>): String {
    nums.forEach {
        if (it == 3) return "lambda return: withLambda ended here"
    }
    return "forEach was fully traversed"
}

fun withAnonymous(nums: List<Int>): String {
    nums.forEach(fun(n: Int) {
        if (n == 3) return
    })
    return "forEach was fully traversed"
}

fun main() {
    println(withLambda(listOf(1, 2, 3, 4)))
    println(withAnonymous(listOf(1, 2, 3, 4)))
}
```

```
lambda return: withLambda ended here
forEach was fully traversed
```

같은 자리에 놓인 같은 `return`이 하나는 `withLambda`를 끝내고 하나는 원소 하나만 건너뛴다. 람다에서 원소만 건너뛰려면 라벨을 붙여 `return@forEach`로 쓴다.

### 클로저

```kotlin
fun counter(): () -> Int {
    var count = 0
    return { count++ }
}

fun main() {
    val next = counter()
    println("${next()} ${next()} ${next()}")

    val another = counter()
    println("another=${another()} next=${next()}")
}
```

```
0 1 2
another=0 next=3
```

`counter()`가 끝나면 지역 변수 `count`의 수명도 끝나야 할 것 같지만, 반환된 람다가 `count`를 붙잡고 있어 호출할 때마다 값이 이어진다. `counter()`를 다시 호출하면 별도의 `count`가 생기므로 `another`와 `next`는 서로의 값을 건드리지 않는다.

Kotlin은 `var`도 캡처해서 고칠 수 있다. Java 람다가 [effectively final 지역 변수만 캡처하는 것](https://docs.oracle.com/javase/specs/jls/se21/html/jls-15.html#jls-15.27.2)과 다른 지점이다.

## 혼동하기 쉬운 것

### 람다는 클로저의 다른 이름이 아니다

클로저는 문법의 이름이 아니라 함수 리터럴이 붙잡은 바깥 변수 묶음을 가리킨다. 그래서 "이 람다는 클로저다"는 "이 람다가 바깥 변수를 캡처했다"는 뜻이다. 공식 문서는 캡처한 것이 아니라 접근할 수 있는 바깥 변수 묶음이라고 쓰는데, 그 기준이면 캡처가 없는 람다도 빈 클로저를 갖는 셈이다. 실제로 구분이 필요한 지점은 캡처 여부다.

캡처 여부는 인스턴스가 몇 개 만들어지는지로 드러난다.

```kotlin
fun makeFree(): (Int) -> Int = { it * 2 }
fun makeCapturing(factor: Int): (Int) -> Int = { it * factor }

fun main() {
    println("free:      " + (makeFree() === makeFree()))
    println("capturing: " + (makeCapturing(2) === makeCapturing(2)))
}
```

```
free:      true
capturing: false
```

캡처할 상태가 없는 람다는 매번 같은 인스턴스를 돌려준다. 들고 다닐 값이 없으니 하나만 있으면 된다. 반대로 `factor`를 캡처한 쪽은 캡처한 값을 담을 자리가 필요해 호출마다 새 인스턴스가 생긴다.

이 동일성은 JVM 백엔드의 컴파일 결과이지 언어 명세가 보장하는 값이 아니다. 캡처 여부를 눈으로 확인하는 용도로만 쓰고, 함수 값을 `===`로 비교하는 코드를 쓰지는 않는다.

### 익명 함수와 익명 클래스는 다르다

Java에서 넘어오면 걸리는 지점이다. Java의 익명 클래스에 대응하는 Kotlin 문법은 익명 함수가 아니라 객체 표현식이다.

```kotlin
fun makeCounterObject(): Runnable {
    var count = 0
    return object : Runnable {
        override fun run() { count++; println("run: count=$count") }
    }
}

fun main() {
    val r = makeCounterObject()
    r.run()
    r.run()
}
```

```
run: count=1
run: count=2
```

객체 표현식도 바깥 변수를 캡처하므로 클로저다. 앞의 `counter()`와 달리 값을 반환하지 않고 출력한다는 것만 다르다.

차이는 컴파일 결과에 남는다. 앞의 `counter()`를 담은 파일과 이 파일을 각각 컴파일해 보면 클래스 파일 개수가 다르다.

```
$ ls out-lambda          # 람다로 쓴 counter()
CounterKt.class

$ ls out-object          # 객체 표현식으로 쓴 makeCounterObject()
CounterObjectKt$makeCounterObject$1.class
CounterObjectKt.class
```

Kotlin 2.x JVM 백엔드는 람다를 `invokedynamic` 한 줄로 컴파일해 클래스 파일을 남기지 않는다. 객체 표현식은 이름만 없을 뿐 클래스라서 파일이 생긴다.

구현할 추상 메서드가 하나뿐인 인터페이스라면 객체 표현식 대신 람다를 넘길 수 있다. 공식 문서가 [SAM 변환](https://kotlinlang.org/docs/fun-interfaces.html#sam-conversions)이라 부르는 것으로, Kotlin 인터페이스는 `fun interface`로 선언해야 대상이 된다.

### 함수 참조는 새 함수를 만들지 않는다

`list.map { double(it) }`과 `list.map(::double)`은 같은 자리에 들어가지만 문법이 다르다. 앞은 그 자리에서 함수를 정의하고, 뒤는 이미 있는 `double`을 가리킨다.

캡처 여부도 같은 기준으로 갈린다. 수신 객체가 붙은 바운드 참조(`s::hashCode`)는 `s`를 붙잡으므로 클로저다.

```kotlin
fun double(x: Int): Int = x * 2

fun freeRef(): (Int) -> Int = ::double
fun boundRef(s: String): () -> Int = s::hashCode

fun main() {
    println("free ref:  " + (freeRef() === freeRef()))
    println("bound ref: " + (boundRef("ab") === boundRef("ab")))
}
```

```
free ref:  true
bound ref: false
```

캡처 없는 람다와 결과가 같다. 붙잡을 상태가 있으면 인스턴스가 새로 생기고, 없으면 하나를 재사용한다.

### 비인라인 함수에 넘긴 람다는 `return` 자체가 금지된다

앞의 `forEach` 예시가 동작한 것은 `forEach`가 `inline` 함수라서다. 인라인이 아닌 함수에 넘긴 람다는 함수 값으로 어딘가에 저장됐다가 나중에 호출될 수 있고, 그때 바깥 함수의 스택 프레임은 이미 사라진 뒤일 수 있다. 컴파일러는 프레임이 살아 있음을 증명할 수 없으므로 실제 호출 시점과 무관하게 금지한다.

```kotlin
fun run3(f: (Int) -> Unit) { f(3) }
fun caller() {
    run3 { if (it == 3) return }
}
```

```
BadRet.kt:3:25: error: 'return' is prohibited here.
    run3 { if (it == 3) return }
                        ^^^^^^
```

익명 함수는 이 제약을 받지 않는다. 애초에 자기 자신에서만 반환하기 때문이다.

## 직접 확인

로컬 함수를 컴파일해 무엇이 남는지 본다. JVM 타깃 21로 컴파일한 뒤 `javap -p -c`로 읽었다.

```kotlin
fun normalize(raw: List<String>, prefix: String): List<String> {
    fun clean(s: String): String = prefix + s.trim().lowercase()
    return raw.map { clean(it) }
}
```

JVM 백엔드에서 로컬 함수는 객체가 아니다. 바깥 클래스의 `private static` 메서드로 풀리고, 캡처한 `prefix`는 인자로 전달된다.

```
public final class LocalKt {
  public static final java.util.List<java.lang.String> normalize(java.util.List<java.lang.String>, java.lang.String);
    Code:
       ...
        88: invokestatic  #54    // Method normalize$clean:(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
       ...
  private static final java.lang.String normalize$clean(java.lang.String, java.lang.String);
```

람다를 `raw.map(::clean)`처럼 함수 참조로 바꿔도 결과는 같다. `map`이 인라인 함수라서 참조를 담을 객체 없이 같은 `invokestatic` 한 줄로 컴파일된다.

캡처한 변수를 읽기만 하면 여기서 끝난다. 고치는 순간 달라진다. 다음은 로컬 함수가 `var`를 고치는 별도 파일을 같은 방식으로 컴파일한 것이다. 바깥 함수와 로컬 함수가 같은 변수를 봐야 하므로 컴파일러가 값을 박스로 감싼다.

```kotlin
fun tally(raw: List<String>): Int {
    var skipped = 0
    fun count(s: String) { if (s.isBlank()) skipped++ }
    raw.forEach { count(it) }
    return skipped
}
```

```
public final class LocalVarKt {
  public static final int tally(java.util.List<java.lang.String>);
    Code:
       ...
         6: new           #18    // class kotlin/jvm/internal/Ref$IntRef
        10: invokespecial #22    // Method kotlin/jvm/internal/Ref$IntRef."<init>":()V
       ...
        61: invokestatic  #44    // Method tally$count:(Lkotlin/jvm/internal/Ref$IntRef;Ljava/lang/String;)V
       ...
        70: getfield      #48    // Field kotlin/jvm/internal/Ref$IntRef.element:I
       ...
  private static final void tally$count(kotlin.jvm.internal.Ref$IntRef, java.lang.String);
```

`Int` 하나를 세려고 `Ref.IntRef` 객체가 하나 생긴다.

## 언제 어떤 것을 쓰나

### 람다와 익명 함수

거의 항상 람다를 쓴다. 익명 함수는 블록 본문 안에서 여러 번 `return`으로 빠져나가고 싶은데 바깥 함수까지 끌려나가면 곤란할 때 고른다. `return@label`로도 같은 일을 하지만 라벨이 겹겹이 쌓이면 익명 함수가 읽기 쉽다.

### 람다와 함수 참조

받은 인자를 그대로 넘기기만 한다면 함수 참조가 짧다. `map { clean(it) }`보다 `map(::clean)`이 읽을 것이 적다. 인자 순서를 바꾸거나 일부만 넘기거나 조건을 끼워야 하면 람다를 쓴다.

### 함수 안에 함수를 둘 것인가

로컬 함수는 바깥 함수의 파라미터와 지역 변수를 그대로 쓸 수 있어서, 도우미 함수에 인자를 줄줄이 넘기던 코드를 줄인다. 로컬 함수도 `invokestatic` 호출이라 밖으로 뺀 함수와 비용이 같다. 판단 기준은 성능이 아니라 범위와 테스트다.

| | 로컬 함수 | 파일이나 클래스 수준으로 뺀 함수 |
|---|---|---|
| 보이는 범위 | 바깥 함수 안. 넓힐 방법이 없다 | 가시성 지정자로 정한다 |
| 입력 | 파라미터 + 캡처한 변수 | 파라미터만 |
| 단위 테스트 | 불가 | 가시성을 `internal` 이상으로 열면 가능 |
| 재사용 | 불가 | 가시성이 닿는 범위에서 가능 |

캡처는 얻는 것인 동시에 잃는 것이다. 함수의 입력이 시그니처에 다 드러나지 않아서, 로컬 함수가 길어지면 바깥 어느 변수에 의존하는지 본문을 다 읽어야 알 수 있다.

`Ref.IntRef`가 생기는 앞의 `tally`는 애초에 `raw.count { it.isBlank() }` 한 줄로 끝난다. 캡처한 변수를 고치는 코드를 만나면 값을 반환받는 쪽으로 바꿀 수 있는지 먼저 본다.

정리하면 이렇게 고른다.

- 바깥 함수 안에서만 의미가 있고, 캡처 덕에 인자 목록이 눈에 띄게 짧아지는 두세 줄짜리 도우미라면 로컬 함수.
- 따로 테스트하고 싶거나, 다른 곳에서도 쓰거나, 로컬 함수가 셋 이상 쌓여 바깥 함수가 껍데기만 남았다면 밖으로 뺀다. 같은 모듈의 테스트에서 호출하려면 가시성이 `internal` 이상, 다른 모듈에서 호출하려면 `public`이어야 한다.
- 캡처한 `var`를 고치는 로컬 함수는 반환값으로 바꿀 수 있는지 먼저 확인한다.

## 참고

- [Kotlin 공식 문서: Lambdas](https://kotlinlang.org/docs/lambdas.html)
- [Kotlin 공식 문서: Local functions](https://kotlinlang.org/docs/functions.html#local-functions)
- [Kotlin 공식 문서: Object expressions](https://kotlinlang.org/docs/object-declarations.html#object-expressions)
- [Kotlin 공식 문서: Functional (SAM) interfaces](https://kotlinlang.org/docs/fun-interfaces.html)
- [Kotlin 공식 문서: Callable references](https://kotlinlang.org/docs/reflection.html#callable-references)
- [Kotlin 공식 문서: Inline functions, non-local jump expressions](https://kotlinlang.org/docs/inline-functions.html#non-local-jump-expressions)
- [Kotlin 공식 문서: Return to labels](https://kotlinlang.org/docs/returns.html#return-to-labels)
