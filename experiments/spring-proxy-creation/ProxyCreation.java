// Spring 프록시가 언제 만들어지고 어떤 타입으로 만들어지는지 본다.
//
// 준비: experiments/transactional-connection-pool/PoolHold.java 머리의 jar 내려받기와 같다.
//       DB는 쓰지 않는다.
//
// 실행:
//   java -Dstdout.encoding=UTF-8 -cp "lib/*" experiments/spring-proxy-creation/ProxyCreation.java

import org.springframework.aop.framework.Advised;
import org.springframework.aop.support.AopUtils;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;

public class ProxyCreation {

    // 트랜잭션이 진짜로 시작·커밋되는지만 찍는다. DB는 필요 없다.
    static class LoggingTxManager extends AbstractPlatformTransactionManager {
        protected Object doGetTransaction() { return new Object(); }
        protected void doBegin(Object tx, org.springframework.transaction.TransactionDefinition d) {
            System.out.println("      [tx] begin");
        }
        protected void doCommit(DefaultTransactionStatus s) { System.out.println("      [tx] commit"); }
        protected void doRollback(DefaultTransactionStatus s) { System.out.println("      [tx] rollback"); }
    }

    public interface OrderService {
        void place();
        void placeTwice();
    }

    // 자기 자신을 주입받는 빈. 프록시가 만들어지는 경로가 달라진다.
    public interface SelfRefService {
        void place();
        void placeViaSelf();
    }

    public static class OrderServiceImpl implements OrderService, InitializingBean {
        public OrderServiceImpl() {
            System.out.println("  생성자        this = " + shortName(getClass()));
        }
        @Override public void afterPropertiesSet() {
            System.out.println("  초기화 콜백    this = " + shortName(getClass()));
        }
        @Override @Transactional public void place() {
            System.out.println("      place() 실행");
        }
        @Override public void placeTwice() {
            System.out.println("    placeTwice()에서 내부 호출");
            place();                              // 프록시를 거치지 않는다
        }
    }

    public static class SelfRefServiceImpl implements SelfRefService, InitializingBean {
        @org.springframework.beans.factory.annotation.Autowired
        SelfRefService self;                      // 자기 자신. 주입되는 것은 프록시다.

        // 초기화 콜백 시점에 self가 이미 프록시인지 본다. 프록시 생성 시점을 가른다.
        @Override public void afterPropertiesSet() {
            System.out.println("  초기화 콜백    this = " + shortName(getClass())
                    + ", self = " + (self == null ? "null" : shortName(self.getClass())));
        }

        @Override @Transactional public void place() {
            System.out.println("      place() 실행");
        }
        @Override public void placeViaSelf() {
            System.out.println("    placeViaSelf()에서 self.place()");
            System.out.println("    self = " + shortName(self.getClass()));
            self.place();                         // 프록시를 거친다
        }
    }

    // 인터페이스가 없는 빈. 프록시 타입 선택이 달라진다.
    public static class NoInterfaceService {
        @Transactional public void run() { }
    }

    // 프록시 생성 시점을 앞뒤로 끼워 본다.
    static class Watcher implements BeanPostProcessor {
        public Object postProcessBeforeInitialization(Object bean, String name) throws BeansException {
            if (name.startsWith("order") || name.startsWith("noInterface") || name.startsWith("selfRef"))
                System.out.println("  BPP before   " + name + " = " + shortName(bean.getClass()));
            return bean;
        }
        public Object postProcessAfterInitialization(Object bean, String name) throws BeansException {
            if (name.startsWith("order") || name.startsWith("noInterface") || name.startsWith("selfRef"))
                System.out.println("  BPP after    " + name + " = " + shortName(bean.getClass()));
            return bean;
        }
    }

    @Configuration
    @EnableTransactionManagement                       // proxyTargetClass 기본값 false
    static class JdkProxyConfig {
        @Bean PlatformTransactionManager tx() { return new LoggingTxManager(); }
        @Bean OrderService orderService() { return new OrderServiceImpl(); }
        @Bean NoInterfaceService noInterfaceService() { return new NoInterfaceService(); }
        @Bean SelfRefService selfRefService() { return new SelfRefServiceImpl(); }
        @Bean static Watcher watcher() { return new Watcher(); }
    }

    @Configuration
    @EnableTransactionManagement(proxyTargetClass = true)
    static class CglibProxyConfig {
        @Bean PlatformTransactionManager tx() { return new LoggingTxManager(); }
        @Bean OrderService orderService() { return new OrderServiceImpl(); }
    }

    static String shortName(Class<?> c) {
        String n = c.getName();
        return n.substring(n.lastIndexOf('.') + 1);
    }

    static void describe(Object bean) {
        System.out.println("  실제 타입      " + shortName(bean.getClass()));
        System.out.println("  JDK 프록시     " + AopUtils.isJdkDynamicProxy(bean));
        System.out.println("  CGLIB 프록시   " + AopUtils.isCglibProxy(bean));
        if (bean instanceof Advised a) {
            System.out.println("  대상 클래스    " + shortName(a.getTargetSource().getTargetClass()));
            System.out.println("  어드바이저     " + a.getAdvisors().length + "개, "
                    + shortName(a.getAdvisors()[0].getAdvice().getClass()));
        }
    }

    public static void main(String[] args) {
        System.out.println("=== 1. 프록시를 만드는 것은 BeanPostProcessor다 ===");
        try (var ctx = new AnnotationConfigApplicationContext(JdkProxyConfig.class)) {
            System.out.println();
            System.out.println("=== 2. 인터페이스가 있으면 JDK 동적 프록시 ===");
            describe(ctx.getBean(OrderService.class));

            System.out.println();
            System.out.println("=== 3. 인터페이스가 없으면 CGLIB ===");
            describe(ctx.getBean(NoInterfaceService.class));

            System.out.println();
            System.out.println("=== 4. 프록시를 만드는 빈 ===");
            for (String n : ctx.getBeanDefinitionNames())
                if (n.contains("AutoProxyCreator") || n.contains("internal"))
                    System.out.println("  " + n + " = " + shortName(ctx.getBean(n).getClass()));

            System.out.println();
            System.out.println("=== 5. 외부 호출과 내부 호출 ===");
            OrderService s = ctx.getBean(OrderService.class);
            System.out.println("  외부에서 place()");
            s.place();
            System.out.println("  외부에서 placeTwice() -> 내부에서 place()");
            s.placeTwice();
            System.out.println("  외부에서 placeViaSelf() -> 주입받은 self로 place()");
            ctx.getBean(SelfRefService.class).placeViaSelf();

            System.out.println();
            System.out.println("=== 7. 자기 참조 빈은 프록시가 다른 자리에서 만들어진다 ===");
            System.out.println("  컨테이너에 등록된 selfRefService = "
                    + shortName(ctx.getBean(SelfRefService.class).getClass()));
        }

        System.out.println();
        System.out.println("=== 6. proxyTargetClass = true 로 바꾸면 ===");
        try (var ctx = new AnnotationConfigApplicationContext(CglibProxyConfig.class)) {
            describe(ctx.getBean(OrderService.class));
        }
    }
}
