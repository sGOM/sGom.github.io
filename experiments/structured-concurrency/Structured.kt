// 구조화된 동시성: Job 트리, 취소 전파, CancellationException의 예외성.
//
// 준비:
//   curl -sSO https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.9.0/kotlinx-coroutines-core-jvm-1.9.0.jar
//
// 실행:
//   kotlinc -cp lib/kotlinx-coroutines-core-jvm-1.9.0.jar \
//     experiments/structured-concurrency/Structured.kt -include-runtime -d sc.jar
//   java -Dstdout.encoding=UTF-8 -cp "sc.jar;lib/kotlinx-coroutines-core-jvm-1.9.0.jar" StructuredKt

import kotlinx.coroutines.*

// 처리되지 않은 예외를 한 줄로 줄인다. 없으면 스택 트레이스가 출력을 덮는다.
val quiet = CoroutineExceptionHandler { _, e ->
    println("  [처리 안 된 예외] ${e::class.simpleName}: ${e.message}")
}

fun state(j: Job) = when {
    j.isCancelled -> "cancelled"
    j.isCompleted -> "completed"
    j.isActive    -> "active"
    else          -> "new"
}

fun main() {
    println("=== 1. launch는 부모-자식 관계를 만든다 ===")
    runBlocking {
        val parent = launch {
            val a = launch { delay(10_000) }
            val b = launch { delay(10_000) }
            delay(50)
            println("  부모의 자식 수: ${coroutineContext.job.children.count()}")
            println("  a의 부모가 곧 이 Job인가: ${coroutineContext.job.children.contains(a)}")
            println("  a=${state(a)} b=${state(b)}")
            coroutineContext.job.cancel()          // 부모를 취소한다
        }
        parent.join()
        println("  부모 취소 뒤 parent=${state(parent)}")
    }

    println()
    println("=== 2. 자식 하나가 실패하면 형제까지 취소된다 ===")
    runBlocking {
        val scope = CoroutineScope(Dispatchers.Default + quiet)
        val sibling = scope.launch {
            try {
                delay(10_000)
            } catch (e: CancellationException) {
                println("  형제: 취소됨 (${e::class.simpleName})")
                throw e
            }
        }
        val failing = scope.launch {
            delay(50)
            throw IllegalStateException("child failed")
        }
        failing.join(); sibling.join()
        println("  실패한 자식=${state(failing)}  형제=${state(sibling)}  스코프=${state(scope.coroutineContext.job)}")
        // 취소된 스코프에 새로 띄우면 어떻게 되는지.
        val late = scope.launch { delay(10_000) }
        late.join()
        println("  취소된 스코프에 새로 띄운 코루틴=${state(late)}")
    }

    println()
    println("=== 3. CancellationException은 부모를 죽이지 않는다 ===")
    runBlocking {
        val scope = CoroutineScope(Dispatchers.Default + quiet)
        val sibling = scope.launch { delay(300); println("  형제: 끝까지 실행됨") }
        val cancelled = scope.launch { delay(50); throw CancellationException("thrown by hand") }
        cancelled.join()
        println("  던진 자식=${state(cancelled)}  스코프=${state(scope.coroutineContext.job)}")
        sibling.join()
    }

    println()
    println("=== 4. 취소된 코루틴에서는 suspend 호출이 안 된다 ===")
    runBlocking {
        val job = launch {
            try {
                delay(10_000)
            } finally {
                print("  finally에서 delay 시도: ")
                try {
                    delay(10)
                    println("성공")
                } catch (e: CancellationException) {
                    println("${e::class.simpleName}")
                }
                withContext(NonCancellable) {
                    delay(10)
                    println("  NonCancellable 안에서는 성공")
                }
            }
        }
        delay(50)
        job.cancelAndJoin()
    }

    println()
    println("=== 5. 취소는 협조적이다 ===")
    runBlocking {
        // 중단점이 없는 루프. 2초를 채울 때까지 돈다.
        val deadline = System.nanoTime() + 2_000_000_000
        val blind = launch(Dispatchers.Default) {
            var i = 0L
            while (System.nanoTime() < deadline) i++
            println("  중단점 없는 루프: 끝까지 돌았다")
        }
        delay(50)
        var t0 = System.nanoTime()
        blind.cancelAndJoin()
        println("  중단점 없는 루프 cancelAndJoin: ${(System.nanoTime() - t0) / 1_000_000}ms")

        // 같은 루프에 ensureActive()만 넣는다.
        val deadline2 = System.nanoTime() + 2_000_000_000
        val checking = launch(Dispatchers.Default) {
            var i = 0L
            while (System.nanoTime() < deadline2) { ensureActive(); i++ }
            println("  확인하는 루프: 끝까지 돌았다")
        }
        delay(50)
        t0 = System.nanoTime()
        checking.cancelAndJoin()
        println("  확인하는 루프 cancelAndJoin:   ${(System.nanoTime() - t0) / 1_000_000}ms")
    }
    println()
    println("=== 6. supervisorScope에서는 형제가 살아남는다 ===")
    runBlocking {
        supervisorScope {
            val sibling = launch(quiet) {
                try { delay(300); println("  형제: 끝까지 실행됨") }
                catch (e: CancellationException) { println("  형제: 취소됨") }
            }
            val failing = launch(quiet) {
                delay(50)
                throw IllegalStateException("child failed")
            }
            failing.join()
            println("  실패한 자식=${state(failing)}  형제=${state(sibling)}")
            sibling.join()
        }
    }

    println()
}
