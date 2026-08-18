---
title: 코틀린 코루틴 기본 개념 정리
description: 코루틴이 스레드와 어떻게 다른지, suspend 함수와 CoroutineScope·Job·Dispatcher가 하는 역할을 표와 예시로 정리한다.
pubDate: 2026-08-15
category: "Kotlin"
tags: ["기본개념", "Kotlin", "코루틴"]
---

## 왜 필요한가

스레드는 하나 만드는 데 수 KB\~수 MB의 스택 메모리가 들고, 컨텍스트 스위칭 비용도 OS 스케줄러가 담당한다. 네트워크 요청처럼 대기 시간이 긴 작업을 스레드로 처리하면, 스레드는 대기 중에도 자원을 점유한 채 블로킹된다. 동시에 처리할 작업이 수천 개로 늘어나면 스레드 수도 그만큼 늘어나야 하고, 이는 메모리와 스케줄링 비용으로 이어진다.

코루틴은 스레드를 블로킹하지 않고 실행을 일시 중단(suspend)했다가 나중에 재개하는 방식으로 이 문제를 해결한다. 코루틴 자체는 스레드보다 훨씬 가벼워서 수만 개를 동시에 띄울 수 있고, 하나의 스레드 위에서 여러 코루틴이 번갈아 실행된다.

## 용어 정리

- **코루틴(Coroutine)**: 중단하고 재개할 수 있는 실행 단위. 스레드처럼 OS가 관리하는 게 아니라 코틀린 런타임(라이브러리)이 관리한다.
- **suspend 함수**: 중단 지점을 가질 수 있는 함수. `suspend` 키워드로 표시하며, 다른 suspend 함수나 코루틴 빌더 안에서만 호출할 수 있다.
- **CoroutineScope**: 코루틴의 생명주기를 묶는 범위. 스코프가 취소되면 그 안에서 시작한 코루틴도 함께 취소된다.
- **Job**: 코루틴 하나의 실행을 다루는 핸들. 상태 조회, 취소, 완료 대기에 쓴다.
- **Dispatcher**: 코루틴이 어느 스레드(풀)에서 실행될지 정하는 요소. `Dispatchers.Default`, `Dispatchers.IO`, `Dispatchers.Main` 등이 있다.

## 핵심 정리

| 항목 | 스레드 | 코루틴 |
|---|---|---|
| 생성 비용 | 무겁다 (OS 스레드, 스택 수 MB) | 가볍다 (객체 하나, 스택 없음) |
| 동시 실행 개수 | 수백\~수천 개가 한계 | 수만 개 이상 가능 |
| 대기 중 자원 점유 | 블로킹된 스레드가 자원을 점유 | 중단된 코루틴은 스레드를 반환 |
| 관리 주체 | OS 커널 | 코틀린 런타임(라이브러리) |
| 취소 | 스레드 인터럽트, 직접 처리 필요 | `Job.cancel()`로 구조화된 취소 |
| 컨텍스트 스위칭 | 커널 개입, 상대적으로 비쌈 | 라이브러리 레벨, 상대적으로 저렴 |

## 항목별 설명

**CoroutineScope**는 코루틴을 개별로 관리하지 않고 묶어서 관리하기 위한 경계다. 예를 들어 화면이 사라질 때 그 화면에서 시작한 코루틴을 전부 취소하려면, 화면과 스코프의 생명주기를 맞춰두면 된다. 이렇게 스코프 단위로 취소가 전파되는 구조를 구조화된 동시성(structured concurrency)이라 부른다.

**Job**은 `launch`가 반환하는 값으로, 코루틴 하나의 상태(신규, 활성, 완료, 취소 등)를 나타낸다. `job.join()`으로 완료를 기다리거나 `job.cancel()`로 취소할 수 있다.

**Dispatcher**는 코루틴이 실제로 어느 스레드에서 도는지를 결정한다. CPU 연산에는 `Dispatchers.Default`, 네트워크나 디스크 I/O처럼 블로킹 호출이 섞인 작업에는 `Dispatchers.IO`를 쓴다. Dispatcher를 바꿔도 코루틴 코드 자체는 그대로 유지된다는 점이 스레드를 직접 다루는 것과 다르다.

## 예시

```kotlin
suspend fun fetchUser(id: Long): User {
    delay(100) // 네트워크 호출을 흉내낸 지연. 스레드를 블로킹하지 않는다.
    return User(id, "user-$id")
}

fun main() = runBlocking {
    val job = launch(Dispatchers.IO) {
        val user = fetchUser(1)
        println(user)
    }
    job.join() // 코루틴이 끝날 때까지 대기
}
```

`delay(100)`은 `Thread.sleep(100)`과 달리 스레드를 점유하지 않는다. 코루틴은 이 지점에서 중단되고, 스레드는 다른 코루틴을 실행하는 데 쓰인다.

## 혼동하기 쉬운 것

- **suspend 함수 = 비동기 함수는 아니다.** `suspend`는 "중단 가능하다"는 표시일 뿐이고, 실제로 비동기로 실행되려면 `launch`나 `async` 같은 코루틴 빌더로 감싸야 한다. suspend 함수를 그냥 호출하면 호출한 코루틴 안에서 순차적으로 실행된다.
- **블로킹과 중단(suspending)은 다르다.** 블로킹은 스레드를 점유한 채 멈추는 것이고, 중단은 스레드를 반환하고 나중에 재개하는 것이다. `Thread.sleep`은 블로킹, `delay`는 중단이다.
- **`launch`와 `async`는 반환값 유무로 나뉜다.** `launch`는 결과가 필요 없는 작업에, `async`는 `Deferred<T>`로 결과를 받아야 하는 작업에 쓴다. `async`로 시작한 작업은 `await()`를 호출하지 않으면 예외가 조용히 묻힐 수 있다.

## 언제 어떤 것을 쓰나

- 결과값이 필요 없는 fire-and-forget 작업이면 `launch`.
- 결과값이 필요하거나 여러 작업을 병렬로 돌려 결과를 모아야 하면 `async` + `awaitAll`.
- CPU 위주 연산은 `Dispatchers.Default`, 블로킹 I/O가 섞인 작업은 `Dispatchers.IO`, UI 갱신처럼 특정 스레드에서만 실행해야 하면 `Dispatchers.Main`.

## 더 깊이

suspend 함수가 스레드 없이 중단·재개되는 원리는 [코틀린 suspend 함수는 스레드 없이 어떻게 중단하고 재개하는가](/posts/kotlin-coroutine-basics-deep-dive/)에서 바이트코드로 확인한다.

## 참고

- [Kotlin 공식 문서 - Coroutines guide](https://kotlinlang.org/docs/coroutines-guide.html)
- [Kotlin 공식 문서 - Coroutine context and dispatchers](https://kotlinlang.org/docs/coroutine-context-and-dispatchers.html)
