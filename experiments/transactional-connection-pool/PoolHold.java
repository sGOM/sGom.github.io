// @Transactional이 커넥션 풀의 커넥션을 붙잡는 구간을 잰다.
//
// 준비:
//   docker compose -f experiments/compose.yml up -d postgres
//   docker compose -f experiments/compose.yml exec -T postgres psql -U postgres \
//     < experiments/transactional-connection-pool/setup.sql
//
//   mkdir lib && cd lib
//   S=6.1.14
//   for a in spring-core spring-jcl spring-beans spring-aop spring-context \
//            spring-expression spring-tx spring-jdbc; do
//     curl -sSO https://repo1.maven.org/maven2/org/springframework/$a/$S/$a-$S.jar
//   done
//   curl -sSO https://repo1.maven.org/maven2/com/zaxxer/HikariCP/5.1.0/HikariCP-5.1.0.jar
//   curl -sSO https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar
//   curl -sSO https://repo1.maven.org/maven2/org/slf4j/slf4j-api/2.0.13/slf4j-api-2.0.13.jar
//   curl -sSO https://repo1.maven.org/maven2/org/slf4j/slf4j-simple/2.0.13/slf4j-simple-2.0.13.jar
//
// 실행:
//   java -Dstdout.encoding=UTF-8 -cp "lib/*" experiments/transactional-connection-pool/PoolHold.java

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.LazyConnectionDataSourceProxy;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.annotation.Transactional;

import javax.sql.DataSource;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;

public class PoolHold {

    static final String URL = "jdbc:postgresql://localhost:5433/transactional-connection-pool";
    static final int POOL_SIZE = 2;
    static final long WORK_MS = 500;   // 트랜잭션 안에서 DB를 쓰지 않고 보내는 시간

    static HikariDataSource pool;      // 실제 풀. 점유 수를 여기서 읽는다.

    static int active() {
        return pool.getHikariPoolMXBean().getActiveConnections();
    }

    static void log(String tag, String msg) {
        System.out.printf("%-28s active=%d  %s%n", tag, active(), msg);
    }

    static HikariDataSource newPool() {
        HikariConfig c = new HikariConfig();
        c.setJdbcUrl(URL);
        c.setUsername("postgres");
        c.setPassword("lab");
        c.setMaximumPoolSize(POOL_SIZE);
        c.setMinimumIdle(POOL_SIZE);
        c.setConnectionTimeout(2000);
        c.setPoolName("demo");
        return new HikariDataSource(c);
    }

    // 실험 1, 3용. DataSource를 그대로 트랜잭션 매니저에 준다.
    @Configuration
    @EnableTransactionManagement
    static class Eager {
        @Bean(destroyMethod = "") DataSource dataSource() { return pool; }
        @Bean PlatformTransactionManager tx(DataSource ds) { return new DataSourceTransactionManager(ds); }
        @Bean JdbcTemplate jdbc(DataSource ds) { return new JdbcTemplate(ds); }
        @Bean Service service() { return new Service(); }
    }

    // 실험 2용. LazyConnectionDataSourceProxy로 감싼다.
    @Configuration
    @EnableTransactionManagement
    static class Lazy {
        @Bean(destroyMethod = "") DataSource dataSource() { return new LazyConnectionDataSourceProxy(pool); }
        @Bean PlatformTransactionManager tx(DataSource ds) { return new DataSourceTransactionManager(ds); }
        @Bean JdbcTemplate jdbc(DataSource ds) { return new JdbcTemplate(ds); }
        @Bean Service service() { return new Service(); }
    }

    public static class Service {
        @org.springframework.beans.factory.annotation.Autowired JdbcTemplate jdbc;

        @Transactional
        public void withTx() throws InterruptedException {
            log("  트랜잭션 시작 직후", "아직 쿼리 안 함");
            long q0 = System.nanoTime();
            jdbc.update("UPDATE acct SET balance = balance + 1 WHERE id = 1");
            long queryMs = (System.nanoTime() - q0) / 1_000_000;
            log("  쿼리 직후", "쿼리에 쓴 시간 " + queryMs + "ms");
            Thread.sleep(WORK_MS);              // 외부 API 호출 자리
            log("  대기 " + WORK_MS + "ms 뒤", "커밋 전");
        }

        public void withoutTx() throws InterruptedException {
            log("  트랜잭션 없음, 쿼리 전", "");
            jdbc.update("UPDATE acct SET balance = balance + 1 WHERE id = 1");
            log("  트랜잭션 없음, 쿼리 후", "커넥션은 이미 반납됐다");
            Thread.sleep(WORK_MS);
            log("  트랜잭션 없음, 대기 뒤", "");
        }

        @Transactional
        public void hold(long ms) throws InterruptedException {
            jdbc.queryForObject("SELECT 1", Integer.class);
            Thread.sleep(ms);
        }
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("org.slf4j.simpleLogger.defaultLogLevel", "warn");
        pool = newPool();

        System.out.println("=== 1. @Transactional이 커넥션을 쥐는 구간 (풀 크기 " + POOL_SIZE + ") ===");
        try (var ctx = new AnnotationConfigApplicationContext(Eager.class)) {
            Service s = ctx.getBean(Service.class);
            log("메서드 호출 전", "");
            s.withTx();
            log("메서드 반환 후", "");

            System.out.println();
            System.out.println("=== 2. 같은 코드에서 @Transactional만 뺀 경우 ===");
            log("메서드 호출 전", "");
            s.withoutTx();
            log("메서드 반환 후", "");
        }

        System.out.println();
        System.out.println("=== 3. LazyConnectionDataSourceProxy를 끼운 경우 ===");
        try (var ctx = new AnnotationConfigApplicationContext(Lazy.class)) {
            Service s = ctx.getBean(Service.class);
            log("메서드 호출 전", "");
            s.withTx();
            log("메서드 반환 후", "");
        }

        System.out.println();
        System.out.println("=== 4. 풀보다 많은 스레드가 동시에 @Transactional에 들어가면 ===");
        try (var ctx = new AnnotationConfigApplicationContext(Eager.class)) {
            Service s = ctx.getBean(Service.class);
            int threads = POOL_SIZE + 1;
            CountDownLatch start = new CountDownLatch(1);
            CountDownLatch done = new CountDownLatch(threads);
            AtomicInteger failed = new AtomicInteger();
            for (int i = 0; i < threads; i++) {
                final int id = i;
                new Thread(() -> {
                    try {
                        start.await();
                        long t0 = System.nanoTime();
                        s.hold(3000);
                        System.out.printf("  스레드 %d 성공  대기+작업 %d ms%n",
                                id, (System.nanoTime() - t0) / 1_000_000);
                    } catch (Exception e) {
                        failed.incrementAndGet();
                        Throwable root = e;
                        while (root.getCause() != null) root = root.getCause();
                        System.out.printf("  스레드 %d 실패  %s%n", id, root.getMessage());
                    } finally {
                        done.countDown();
                    }
                }).start();
            }
            start.countDown();
            done.await();
            System.out.printf("  실패 %d건 / 스레드 %d개, 풀 %d개, connectionTimeout 2000ms%n",
                    failed.get(), threads, POOL_SIZE);
        }

        pool.close();
    }
}
