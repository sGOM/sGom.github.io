// @Transactional과 코루틴이 안 맞는 이유: 트랜잭션 컨텍스트가 ThreadLocal에 있다.
//
// 준비: experiments/transactional-connection-pool/PoolHold.java 머리의 jar 내려받기와 같고,
//       kotlinx-coroutines-core-jvm 도 필요하다. DB는 experiments/coroutine-transactional/setup.sql.
//
// 실행:
//   kotlinc는 -cp에 와일드카드를 받지 않는다. jar를 세미콜론으로 이어 적는다.
//   CP="lib/HikariCP.jar;lib/postgresql.jar;lib/spring-core.jar;..."   (lib의 jar 전부)
//   kotlinc -cp "$CP" experiments/coroutine-transactional/CoroutineTx.kt -include-runtime -d ctx.jar
//   java -Dstdout.encoding=UTF-8 -cp "ctx.jar;lib/*" CoroutineTxKt

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.coroutines.*
import org.springframework.context.annotation.AnnotationConfigApplicationContext
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.datasource.DataSourceTransactionManager
import org.springframework.jdbc.datasource.DataSourceUtils
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.annotation.EnableTransactionManagement
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionSynchronizationManager
import javax.sql.DataSource

lateinit var pool: HikariDataSource

fun tx(): String {
    val active = TransactionSynchronizationManager.isActualTransactionActive()
    val bound = TransactionSynchronizationManager.getResource(pool) != null
    return "트랜잭션=$active 커넥션바인딩=$bound 스레드=${Thread.currentThread().name}"
}

@Configuration
@EnableTransactionManagement
open class Config {
    @Bean(destroyMethod = "")
    open fun dataSource(): DataSource = pool
    @Bean open fun txManager(ds: DataSource): PlatformTransactionManager = DataSourceTransactionManager(ds)
    @Bean open fun jdbc(ds: DataSource) = JdbcTemplate(ds)
    @Bean open fun service() = OrderService()
}

open class OrderService {
    @org.springframework.beans.factory.annotation.Autowired
    lateinit var jdbc: JdbcTemplate

    @Transactional
    open fun blocking() {
        println("  메서드 안:            ${tx()}")
        jdbc.update("UPDATE acct SET balance = balance + 1 WHERE id = 1")
    }

    // suspend 함수에 @Transactional을 붙이면 어떻게 되는가.
    @Transactional
    open fun withDispatcherSwitch() = runBlocking {
        println("  runBlocking 안:       ${tx()}")
        withContext(Dispatchers.IO) {
            println("  withContext(IO) 안:   ${tx()}")
        }
        withContext(Dispatchers.Default) {
            println("  withContext(Default): ${tx()}")
        }
    }

    // 같은 트랜잭션의 커넥션을 다른 스레드에서 얻으면 무엇이 나오는가.
    @Transactional
    open fun connectionIdentity() = runBlocking {
        val outer = DataSourceUtils.getConnection(pool)
        println("  메서드 스레드의 커넥션:   ${System.identityHashCode(outer)}")
        withContext(Dispatchers.IO) {
            val inner = DataSourceUtils.getConnection(pool)
            println("  IO 스레드의 커넥션:      ${System.identityHashCode(inner)}  (같은가: ${outer === inner})")
            println("  autoCommit  메서드 스레드=${outer.autoCommit}  IO 스레드=${inner.autoCommit}")
            DataSourceUtils.releaseConnection(inner, pool)
        }
    }

    // suspend 함수에 @Transactional을 붙이면 프록시가 무엇을 하는가.
    @Transactional
    open suspend fun suspending() {
        println("  suspend 함수 진입:     ${tx()}")
        delay(10)
        println("  delay(10) 재개 뒤:     ${tx()}")
        withContext(Dispatchers.IO) {
            println("  withContext(IO) 안:   ${tx()}")
        }
    }

    @Transactional
    open fun rollbackAcrossThreads(): Unit = runBlocking {
        jdbc.update("UPDATE acct SET balance = 999 WHERE id = 2")
        withContext(Dispatchers.IO) {
            jdbc.update("UPDATE acct SET balance = 888 WHERE id = 3")
        }
        throw IllegalStateException("rollback")
    }
}

fun main() {
    System.setProperty("org.slf4j.simpleLogger.defaultLogLevel", "warn")
    val c = HikariConfig().apply {
        jdbcUrl = "jdbc:postgresql://localhost:5433/coroutine-transactional"
        username = "postgres"; password = "lab"
        maximumPoolSize = 5; poolName = "demo"
    }
    pool = HikariDataSource(c)

    println("Kotlin ${KotlinVersion.CURRENT}, Java ${System.getProperty("java.version")}, " +
            "Spring ${org.springframework.core.SpringVersion.getVersion()}")
    println()

    AnnotationConfigApplicationContext(Config::class.java).use { ctx ->
        val s = ctx.getBean(OrderService::class.java)
        val jdbc = ctx.getBean(JdbcTemplate::class.java)

        println("=== 1. 트랜잭션 밖과 안 ===")
        println("  메서드 밖:            ${tx()}")
        s.blocking()

        println()
        println("=== 2. 디스패처를 옮기면 컨텍스트가 사라진다 ===")
        s.withDispatcherSwitch()

        println()
        println("=== 3. 같은 트랜잭션인데 커넥션이 다르다 ===")
        s.connectionIdentity()

        println()
        println("=== 4. suspend 함수에 @Transactional을 붙이면 ===")
        runBlocking { s.suspending() }

        println()
        println("=== 5. 다른 스레드에서 한 UPDATE는 롤백되지 않는다 ===")
        jdbc.update("UPDATE acct SET balance = 0 WHERE id IN (2, 3)")
        try { s.rollbackAcrossThreads() } catch (e: IllegalStateException) {
            println("  예외로 롤백: ${e.message}")
        }
        val r2 = jdbc.queryForObject("SELECT balance FROM acct WHERE id = 2", Int::class.java)
        val r3 = jdbc.queryForObject("SELECT balance FROM acct WHERE id = 3", Int::class.java)
        println("  id=2 (메서드 스레드에서 UPDATE): balance=$r2")
        println("  id=3 (IO 스레드에서 UPDATE):    balance=$r3")
    }
    pool.close()
}
