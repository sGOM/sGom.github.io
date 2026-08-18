---
title: 코틀린 suspend 함수는 스레드 없이 어떻게 중단하고 재개하는가
description: suspend 함수가 컴파일 시점에 상태 머신으로 변환되는 과정을 바이트코드로 직접 확인하고, 콜백 기반 API 위에서 스레드를 블로킹하지 않고 중단·재개되는 동작을 재현한다.
pubDate: 2026-08-15
category: "Kotlin"
tags: ["파고들기", "Kotlin", "코루틴", "바이트코드"]
---

## 전제

[코틀린 코루틴 기본 개념 정리](/posts/kotlin-coroutine-basics/)에서 코루틴이 스레드보다 가볍고, `delay` 같은 중단 함수는 스레드를 블로킹하지 않는다고 정리했다. 이 글은 그 동작이 컴파일러 수준에서 실제로 어떻게 구현되는지를 다룬다.

## 왜 필요한가

`suspend fun`으로 표시한 함수는 겉보기에 평범한 함수 호출처럼 읽힌다. 스레드가 스택을 그대로 둔 채 멈췄다가 나중에 그 자리에서 이어 실행되는 건 OS 스레드로는 불가능하다(스레드를 멈추려면 블로킹해야 하고, 블로킹은 스레드를 점유한다). 코루틴은 스레드를 점유하지 않고도 "멈췄다가 이어 실행"을 해낸다. JVM 자체에는 이런 기능이 없으므로, 이 동작은 코틀린 컴파일러가 생성하는 코드에서 나온다.

## 겉으로 보이는 것

```kotlin
suspend fun twoSteps(): Int {
    println("첫 구간")
    delay(10)
    println("두번째 구간")
    delay(10)
    println("세번째 구간")
    return 42
}
```

소스만 보면 위에서 아래로 순차 실행되는 함수다. 하지만 `delay(10)` 호출 시점에 실행이 실제로 중단되고, 이 함수를 호출한 스택 프레임은 사라진다. 나중에 재개될 때는 새로운 호출이지만 마치 그 자리에서 이어지듯 동작한다. 이걸 가능하게 하는 게 CPS(Continuation-Passing Style) 변환과 상태 머신이다.

## 동작 원리

컴파일러는 `suspend` 함수를 두 가지로 바꾼다.

1. **숨은 파라미터 추가**: `twoSteps(): Int`는 바이트코드에서 `twoSteps(Continuation<? super Integer>): Object`가 된다. 함수의 "다음에 뭘 할지"를 나타내는 콜백(`Continuation`)을 인자로 받는 형태로 바뀐다.
2. **상태 머신 생성**: 함수 안에서 다른 suspend 함수를 호출하는 지점(중단 지점)마다 번호(`label`)를 매기고, 함수 본문 전체를 `label` 값에 따라 분기하는 `switch`/`tableswitch`로 감싼다. 이 상태를 들고 있는 `label`, `result` 필드는 컴파일러가 만든 `ContinuationImpl` 서브클래스 인스턴스에 저장된다.

함수가 중단 지점에 도달하면, 다음 두 가지 중 하나가 일어난다.

- 호출한 suspend 함수(`delay` 등)가 즉시 결과를 낼 수 있으면, 그 결과를 들고 `switch`의 다음 케이스로 곧장 진행한다. 겉에서 보면 중단 없이 실행된 것처럼 보인다.
- 즉시 결과를 낼 수 없으면(비동기 대기가 필요하면) `COROUTINE_SUSPENDED`라는 특수 센티널 값을 리턴하며 함수를 빠져나온다. 호출 스택은 이 시점에 완전히 풀린다 — 스레드는 이 함수를 기다리지 않고 다른 일을 할 수 있다. 나중에 결과가 준비되면, 저장해둔 `Continuation`(=상태 머신 객체)의 `resumeWith`가 호출되고, 이는 다시 원래 함수를 그 `label` 값으로 호출한다. `switch`는 그 `label`에 해당하는 케이스로 곧장 뛰어 중단된 지점부터 이어간다.

즉 "스택을 멈췄다가 이어간다"는 착시는 실제로는 스택을 완전히 버리고, 지역 변수를 필드에 저장해뒀다가 새 호출에서 그 필드를 읽어 이어 실행하는 방식으로 만들어진다.

## 코드로 따라가기

위 `twoSteps` 함수를 `kotlinc 1.9.24`로 컴파일하고 `javap -c -p`로 바이트코드를 까보면 이 구조가 그대로 드러난다.

`twoSteps` 함수 본문의 앞부분은 이렇게 시작한다.

```
public static final java.lang.Object twoSteps(kotlin.coroutines.Continuation<? super java.lang.Integer>);
  Code:
     0: aload_0
     1: instanceof    #11    // class StateMachineKt$twoSteps$1
     ...
    54: aload_2
    55: getfield      #15    // Field StateMachineKt$twoSteps$1.label:I
    58: tableswitch   { // 0 to 2
                   0: 84
                   1: 116
                   2: 150
             default: 171
        }
```

`label` 필드 값을 읽어 `tableswitch`로 뛰는 부분이 상태 머신의 핵심이다. `label`이 0이면 함수 맨 처음부터, 1이면 첫 번째 `delay` 이후부터, 2면 두 번째 `delay` 이후부터 실행을 재개한다.

`label == 0` 케이스(오프셋 84)를 보면 이런 흐름이다.

```
    84: aload_1
    85: invokestatic  #36  // Method kotlin/ResultKt.throwOnFailure:(Ljava/lang/Object;)V
    88: ldc           #38  // "첫 구간" 문자열 상수
    ...
    97: ldc2_w        #50  // long 10l
   100: aload_2
   101: aload_2
   102: iconst_1
   103: putfield      #15  // label = 1로 갱신
   106: invokestatic  #57  // Method kotlinx/coroutines/DelayKt.delay:(JLkotlin/coroutines/Continuation;)Ljava/lang/Object;
   109: dup
   110: aload_3             // COROUTINE_SUSPENDED
   111: if_acmpne     121   // delay 결과가 SUSPENDED가 아니면 121로 계속 진행
   114: aload_3
   115: areturn             // SUSPENDED면 여기서 함수를 빠져나간다
```

`"첫 구간"`을 출력한 뒤 `label`을 1로 미리 갱신해두고 `delay`를 호출한다. `delay`의 반환값이 `COROUTINE_SUSPENDED`면(114\~115) 그대로 리턴해서 스택을 빠져나오고, 아니면(121로 점프) 곧장 다음 구간으로 넘어간다. `label`을 미리 1로 써둔 덕분에, 나중에 이 함수가 다시 호출될 때 `tableswitch`가 자동으로 두 번째 케이스(오프셋 116)로 진입한다.

한편 `ContinuationImpl` 서브클래스인 `StateMachineKt$twoSteps$1`의 `invokeSuspend`는 결과를 `result` 필드에 채워 넣고 `label`의 최상위 비트를 세팅한 뒤, 다시 원래의 `twoSteps` 함수를 자기 자신(Continuation)을 인자로 넘겨 호출한다.

```
public final java.lang.Object invokeSuspend(java.lang.Object);
  Code:
     0: aload_0
     1: aload_1
     2: putfield      #34   // Field result:Ljava/lang/Object;
     ...
    20: invokestatic  #45   // Method StateMachineKt.twoSteps:(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;
    23: areturn
```

정리하면, "재개"란 새 스레드 스택으로 같은 함수를 다시 호출하면서 `label` 필드를 읽어 `tableswitch`로 중단 지점까지 곧장 건너뛰는 것이다. 스택 프레임을 저장해뒀다가 복원하는 게 아니라, 애초에 필요한 상태(`label`, 지역 변수)를 힙에 있는 필드로 만들어 스택 프레임 자체가 필요 없게 만든 것이다.

## 직접 확인

바이트코드만 봐서는 "정말 스레드를 블로킹하지 않고 나중에 재개되는가"가 와닿지 않는다. 코루틴 라이브러리를 배제하고, 코틀린 표준 라이브러리의 `suspendCoroutine`만으로 콜백 기반 API 위에 중단 함수를 직접 만들어 실행 순서를 확인했다.

```kotlin
import kotlin.coroutines.*

class CallbackApi {
    private var listener: ((String) -> Unit)? = null
    fun onReady(f: (String) -> Unit) { listener = f }
    fun fireLater(value: String) { listener?.invoke(value) }
}

val api = CallbackApi()

suspend fun awaitValue(tag: String): String = suspendCoroutine { cont ->
    println("[awaitValue:$tag] 등록만 하고 즉시 리턴한다 (스레드 블로킹 없음)")
    api.onReady { value -> cont.resume(value) }
}

fun main() {
    println("[main] 1. 코루틴 시작 전")

    val completion = object : Continuation<Unit> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) {
            println("[completion] 코루틴 전체 완료: $result")
        }
    }

    val block: suspend () -> Unit = {
        println("[coroutine] 2. 첫 구간 실행, awaitValue 호출")
        val v1 = awaitValue("A")
        println("[coroutine] 4. 재개됨, v1=$v1")
        val v2 = awaitValue("B")
        println("[coroutine] 6. 재개됨, v2=$v2")
    }

    block.startCoroutine(completion)

    println("[main] 3. startCoroutine 호출 직후 — 코루틴이 끝나지 않았는데도 여기까지 실행됐다")
    println("[main] 5. 콜백을 나중에 수동으로 발생시킨다")
    api.fireLater("첫번째값")
    println("[main] 7. 두번째 콜백 발생시킨다")
    api.fireLater("두번째값")
}
```

`kotlinc-jvm 1.9.24`로 컴파일해 실행한 결과는 다음과 같다.

```
[main] 1. 코루틴 시작 전
[coroutine] 2. 첫 구간 실행, awaitValue 호출
[awaitValue:A] 등록만 하고 즉시 리턴한다 (스레드 블로킹 없음)
[main] 3. startCoroutine 호출 직후 — 코루틴이 끝나지 않았는데도 여기까지 실행됐다
[main] 5. 콜백을 나중에 수동으로 발생시킨다
[coroutine] 4. 재개됨, v1=첫번째값
[awaitValue:B] 등록만 하고 즉시 리턴한다 (스레드 블로킹 없음)
[main] 7. 두번째 콜백 발생시킨다
[coroutine] 6. 재개됨, v2=두번째값
[completion] 코루틴 전체 완료: Success(kotlin.Unit)
```

로그 앞의 번호가 실제 실행 순서다. `awaitValue`를 호출한 지점(2번)에서 `suspendCoroutine` 블록은 콜백만 등록하고 즉시 리턴하므로, 코루틴이 완료되지 않은 채로 `main` 함수의 다음 줄(3번)이 곧바로 실행된다. 코루틴을 시작한 스레드는 여기서 멈추지 않고 `main`의 나머지 코드를 계속 진행한다. `fireLater`로 콜백을 수동으로 발생시켜야만(5번) 코루틴이 재개되고(4번), 두 번째 `awaitValue` 호출도 같은 패턴을 반복한다. 콜백을 부르지 않으면 코루틴은 영원히 멈춘 채로 남는다 — 별도 스레드나 타이머가 없기 때문이다.

## 경계 조건

- `suspend` 함수는 다른 suspend 함수 안에서만 직접 호출할 수 있다. 컴파일러가 넘겨줄 `Continuation` 인자가 필요하기 때문이며, 일반 함수에서 호출하려면 `runBlocking`처럼 코루틴을 새로 시작하는 진입점을 거쳐야 한다.
- 상태 머신은 함수 하나당 하나씩 생기는 게 아니라, 람다로 넘긴 suspend 블록마다 별도로 생성된다. 위 예시의 `block`도 `awaitValue`와 별개로 자신만의 `ContinuationImpl` 서브클래스를 갖는다.

## 참고

- [Kotlin 공식 문서 - Coroutines guide](https://kotlinlang.org/docs/coroutines-guide.html)
- [KEEP - Coroutines design document](https://github.com/Kotlin/KEEP/blob/master/proposals/coroutines.md)
