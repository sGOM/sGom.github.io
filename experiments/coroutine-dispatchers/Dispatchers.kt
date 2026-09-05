// Dispatchers.Default와 Dispatchers.IO가 실제로 몇 개의 스레드를 쓰고,
// 둘이 스레드를 나눠 쓰는지 본다.
//
// 준비:
//   curl -sSO https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.9.0/kotlinx-coroutines-core-jvm-1.9.0.jar
//
// 실행:
//   kotlinc -cp lib/kotlinx-coroutines-core-jvm-1.9.0.jar \
//     experiments/coroutine-dispatchers/Dispatchers.kt -include-runtime -d disp.jar
//   java -Dstdout.encoding=UTF-8 -cp "disp.jar;lib/kotlinx-coroutines-core-jvm-1.9.0.jar" DispatchersKt

import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap

fun cores() = Runtime.getRuntime().availableProcessors()

// 디스패처 위에서 n개의 코루틴을 동시에 붙잡아 두고, 그동안 쓰인 스레드 이름을 모은다.
fun busyThreads(dispatcher: CoroutineDispatcher, n: Int, holdMs: Long): Set<String> {
    val names = ConcurrentHashMap.newKeySet<String>()
    runBlocking {
        val jobs = (1..n).map {
            launch(dispatcher) {
                names += Thread.currentThread().name
                Thread.sleep(holdMs)          // 일부러 스레드를 막는다
            }
        }
        jobs.forEach { it.join() }
    }
    return names
}

fun main() {
    println("사용 가능한 프로세서: ${cores()}")
    println("Kotlin ${KotlinVersion.CURRENT}, Java ${System.getProperty("java.version")}")
    println("kotlinx.coroutines ${CoroutineScope::class.java.`package`?.implementationVersion ?: "1.9.0 (jar 표기 없음)"}")
    println()

    println("=== 1. Dispatchers.Default가 쓰는 스레드 수 ===")
    val d = busyThreads(Dispatchers.Default, 200, 300)
    println("  코루틴 200개를 동시에 걸었을 때 쓰인 스레드 ${d.size}개")
    println("  예: ${d.sorted().take(3)}")

    println()
    println("=== 2. Dispatchers.IO가 쓰는 스레드 수 ===")
    val io = busyThreads(Dispatchers.IO, 200, 300)
    println("  코루틴 200개를 동시에 걸었을 때 쓰인 스레드 ${io.size}개")
    println("  예: ${io.sorted().take(3)}")

    println()
    println("=== 3. 두 디스패처가 스레드를 나눠 쓰는가 ===")
    println("  Default 스레드 이름 접두사: ${d.map { it.substringBefore('-') }.toSet()}")
    println("  IO 스레드 이름 접두사:      ${io.map { it.substringBefore('-') }.toSet()}")

    println()
    println("=== 4. 같은 코루틴 안에서 옮겨 다니기 ===")
    runBlocking {
        println("  runBlocking          ${Thread.currentThread().name}")
        withContext(Dispatchers.Default) {
            println("  withContext(Default) ${Thread.currentThread().name}")
            withContext(Dispatchers.IO) {
                println("  withContext(IO)      ${Thread.currentThread().name}")
            }
        }
    }

    println()
    println("=== 5. Dispatchers.Main ===")
    try {
        runBlocking { withContext(Dispatchers.Main) { println("  실행됨") } }
    } catch (e: Throwable) {
        println("  ${e::class.simpleName}: ${e.message?.lineSequence()?.first()}")
    }

    println()
    println("=== 6. Default에서 블로킹하면 코루틴이 밀린다 ===")
    // 코어 수 + 1개를 걸고, 마지막 하나가 언제 시작되는지 본다.
    runBlocking {
        val t0 = System.nanoTime()
        fun ms() = (System.nanoTime() - t0) / 1_000_000
        val n = cores() + 1
        val jobs = (1..n).map { i ->
            launch(Dispatchers.Default) {
                if (i == n) println("  마지막(${i}번) 코루틴 시작: ${ms()}ms")
                Thread.sleep(500)               // 스레드를 막는 호출
            }
        }
        jobs.forEach { it.join() }
        println("  전부 끝: ${ms()}ms  (한 건에 500ms, 코루틴 ${n}개)")
    }
    // 같은 것을 IO에서
    runBlocking {
        val t0 = System.nanoTime()
        fun ms() = (System.nanoTime() - t0) / 1_000_000
        val n = cores() + 1
        val jobs = (1..n).map { i ->
            launch(Dispatchers.IO) {
                if (i == n) println("  IO에서 마지막(${i}번) 코루틴 시작: ${ms()}ms")
                Thread.sleep(500)
            }
        }
        jobs.forEach { it.join() }
        println("  IO에서 전부 끝: ${ms()}ms")
    }

    println()
    println("=== 7. limitedParallelism으로 잘라 쓰기 ===")
    val limited = Dispatchers.IO.limitedParallelism(4)
    val l = busyThreads(limited, 50, 200)
    println("  IO를 4로 잘라 코루틴 50개: 스레드 ${l.size}개")
}
