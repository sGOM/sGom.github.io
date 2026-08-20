---
title: Spring과 Spring Boot의 차이
description: Boot는 Framework의 대안이 아니라 그 위에 얹는 레이어다. 무엇이 달라지는지 축별로 갈라놓고, 자동설정이 물러나는 방식까지 본다
pubDate: 2026-08-20
category: "Spring"
tags: ["기본개념", "Spring", "Spring Boot"]
---

## 왜 필요한가

"Spring으로 만들까 Spring Boot로 만들까"라는 질문은 성립하지 않는다. 둘은 고르는 대상이 아니다. Boot로 만든 애플리케이션도 결국 Spring Framework의 `ApplicationContext`를 띄우고, 그 안에서 빈을 주입받는다.

그런데도 이 질문이 계속 나오는 이유는 "Spring"이라는 말이 두 가지를 가리키기 때문이다. 무엇이 무엇 위에 얹혀 있는지부터 갈라놓아야 한다.

## 용어 정리

| 이름 | 정체 | 없으면 |
|---|---|---|
| Spring Framework | DI 컨테이너, AOP, 트랜잭션 추상화, Spring MVC를 담은 핵심 라이브러리 | 빈 주입도 `@Transactional`도 없다 |
| Spring Boot | Framework 위에 설정 자동화·의존성 묶음·내장 서버·운영 기능을 얹은 레이어 | 설정을 전부 직접 쓴다. 동작 자체는 가능하다 |
| Spring 생태계 | Data, Security, Batch, Cloud 등 Framework를 기반으로 한 프로젝트 묶음 | — |

셋 다 일상적으로 "스프링"이라 불린다. **Boot는 Framework를 감싸지 대체하지 않는다.** Boot 애플리케이션에서 Boot가 얹은 부분을 걷어내면 Framework가 남지만, 그 반대는 성립하지 않는다.

## 핵심 정리

Framework만 쓸 때와 Boot를 얹었을 때 실제로 달라지는 지점은 다섯 축이다.

| 축 | Framework 단독 | Boot |
|---|---|---|
| 설정 | `@Configuration`이나 XML에 필요한 빈을 직접 등록 | 클래스패스를 보고 후보를 자동 등록. 같은 빈을 직접 정의하면 물러난다 |
| 의존성·버전 | 라이브러리 조합과 버전 궁합을 직접 맞춘다 | `spring-boot-starter-*`로 묶어 받고, 버전은 BOM이 정한다 |
| 서버·패키징 | WAR로 빌드해 외부 WAS에 올린다 | 내장 서버를 포함한 실행 가능 jar. `java -jar`로 뜬다 |
| 진입점 | `web.xml` 또는 `WebApplicationInitializer` 구현 | `main()`에서 `SpringApplication.run()` |
| 운영 | 헬스체크·메트릭을 직접 만든다 | Actuator가 엔드포인트로 제공 |

핵심은 첫 줄이다. 설정 축을 이해하면 나머지 넷도 같은 결로 읽힌다.

## 예시

같은 웹 애플리케이션을 띄우는 최소 코드를 나란히 둔다.

Framework만 쓰면 서블릿 컨테이너에 `DispatcherServlet`을 등록하는 일부터 직접 한다.

```java
public class WebAppInitializer extends AbstractAnnotationConfigDispatcherServletInitializer {

    @Override
    protected Class<?>[] getRootConfigClasses() {
        return new Class<?>[] { RootConfig.class };
    }

    @Override
    protected Class<?>[] getServletConfigClasses() {
        return new Class<?>[] { WebConfig.class };
    }

    @Override
    protected String[] getServletMappings() {
        return new String[] { "/" };
    }
}

@Configuration
@EnableWebMvc
@ComponentScan("com.example")
public class WebConfig {

    @Bean
    public DataSource dataSource() {
        // 드라이버, URL, 커넥션 풀 설정을 여기서 직접 조립한다
    }

    @Bean
    public ViewResolver viewResolver() { /* ... */ }
}
```

빌드 결과는 WAR이고, 톰캣 같은 WAS에 배포해야 돈다.

Boot를 얹으면 남는 코드는 이것뿐이다.

```java
@SpringBootApplication
public class MyApplication {

    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}
```

```yaml
# application.yml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
    username: app
```

`DispatcherServlet`도 `DataSource`도 뷰 리졸버도 그대로 등록된다. 사라진 게 아니라 등록하는 주체가 바뀐 것이다.

## 항목별 설명

Boot가 저 빈들을 언제 어떻게 등록하는지가 나머지 차이를 전부 설명한다.

`@SpringBootApplication`은 세 어노테이션을 합친 것이고, 이 중 [`@EnableAutoConfiguration`](https://docs.spring.io/spring-boot/reference/using/auto-configuration.html)이 자동설정을 켠다.

```java
@SpringBootConfiguration   // @Configuration
@EnableAutoConfiguration   // 자동설정
@ComponentScan             // 이 클래스의 패키지 이하 스캔
```

`@EnableAutoConfiguration`은 클래스패스의 jar들에서 다음 파일을 모아 후보 목록을 만든다.

```
META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
```

한 줄에 클래스 하나씩 적힌 목록이다. 컴포넌트 스캔으로 발견되는 게 아니라 이 파일에 이름이 적혀야만 후보가 된다.

후보 클래스는 [`@AutoConfiguration`](https://docs.spring.io/spring-boot/reference/features/developing-auto-configuration.html)이 붙은 평범한 `@Configuration`이다. 다만 조건이 달려 있다.

```java
@AutoConfiguration
@ConditionalOnClass(DataSource.class)
public class MyDataSourceAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public DataSource dataSource(DataSourceProperties properties) {
        // 클래스패스에 DataSource가 있고, 내가 등록한 DataSource가 없을 때만 만들어진다
    }
}
```

두 조건이 하는 일이 다르다.

- `@ConditionalOnClass` — 해당 클래스가 클래스패스에 있을 때만 적용한다. 그래서 `spring-boot-starter-web`을 넣는 것만으로 톰캣 설정이 켜지고, 뺀 프로젝트에서는 조용히 건너뛴다.
- `@ConditionalOnMissingBean` — 같은 타입의 빈이 아직 없을 때만 만든다. `DataSource`를 직접 등록해 두면 자동설정은 물러난다.

이 물러남이 성립하는 이유는 순서 때문이다. **자동설정은 사용자가 정의한 빈이 모두 등록된 뒤에 적용된다**([Condition Annotations](https://docs.spring.io/spring-boot/reference/features/developing-auto-configuration.html#features.developing-auto-configuration.condition-annotations.bean-conditions)). 자동설정이 먼저 돌았다면 `@ConditionalOnMissingBean`은 항상 참이 되어 사용자 빈과 충돌했을 것이다.

그래서 Boot는 "설정을 못 하게 막는 도구"가 아니다. 아무것도 안 하면 기본값이 들어가고, 직접 정의하면 그 자리만 정의한 쪽이 가져간다. 통째로 갈아엎지 않고 필요한 빈만 덮어쓸 수 있다.

## 직접 확인

무엇이 적용되고 무엇이 걸러졌는지는 짐작하지 않고 볼 수 있다. `--debug`로 띄우면 조건 평가 리포트가 찍힌다.

```bash
java -jar myapp.jar --debug
```

리포트는 수백 줄이라 두 항목만 발췌한다. 각 줄 끝의 괄호는 판정을 내린 `Condition` 구현 클래스다.

```
============================
CONDITIONS EVALUATION REPORT
============================


Positive matches:
-----------------

   DataSourceAutoConfiguration matched:
      - @ConditionalOnClass found required classes 'javax.sql.DataSource', 'org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType' (OnClassCondition)


Negative matches:
-----------------

   MongoAutoConfiguration:
      Did not match:
         - @ConditionalOnClass did not find required class 'com.mongodb.client.MongoClient' (OnClassCondition)
```

특정 자동설정을 꺼야 하면 프로퍼티로 제외한다.

```yaml
spring:
  autoconfigure:
    exclude: org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration
```

FQCN은 버전에 묶인다. 위는 Boot 3.x 기준이고, 자동설정이 모듈별로 쪼개진 Boot 4.x에서는 같은 클래스가 `org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration`에 있다. 클래스패스에 없는 이름을 적으면 예외도 경고도 없이 무시되므로, 제외가 먹지 않으면 경로부터 확인한다.

## 혼동하기 쉬운 것

**"Boot를 쓰면 Framework는 안 쓴다."** Boot 프로젝트의 의존성 트리에 `spring-core`, `spring-context`, `spring-web`이 그대로 들어 있다. `@Component`, `@Transactional`, `@RequestMapping`은 전부 Framework의 것이다. Boot가 추가한 것은 `@SpringBootApplication` 계열, `@ConditionalOn*`, `@ConfigurationProperties`, `@SpringBootTest` 등이다.

**"Boot에는 설정이 없다."** 설정이 없는 게 아니라 기본값이 미리 정해져 있는 것이다. 내장 서버가 8080에서 뜨는 것도 누군가 그렇게 등록해 둔 결과이고, `server.port`로 바꿀 수 있다.

**"starter 안에 자동설정 코드가 있다."** starter는 대부분 의존성 목록만 든 빈 껍데기다. 자동설정 클래스는 starter가 끌어오는 별도 모듈에 들어 있다. starter의 역할은 "이 기능에 필요한 조합을 검증된 버전으로 한 번에 받기"다.

## 참고

- [Spring Boot — Auto-configuration](https://docs.spring.io/spring-boot/reference/using/auto-configuration.html)
- [Spring Boot — Creating Your Own Auto-configuration](https://docs.spring.io/spring-boot/reference/features/developing-auto-configuration.html)
- [Spring Framework — The IoC Container](https://docs.spring.io/spring-framework/reference/core/beans.html)
