---
title: Spring AOP 프록시
description: 스프링이 주입하는 것은 원본 객체가 아니라 프록시다. 그 구조와 제약을 정리한다
pubDate: 2026-08-09
category: "Spring"
tags: ["기본개념", "Spring", "AOP"]
---

## 왜 필요한가

`@Transactional`, `@Async`, `@Cacheable`은 메서드 본문을 건드리지 않고 동작을 바꾼다. 이 일이 어디서 일어나는지 모르면, 어노테이션이 조용히 무시되는 상황을 설명할 수 없다.

답은 프록시다. 스프링이 주입하는 것은 작성한 객체가 아니라 그것을 감싼 다른 객체이고, 부가 기능은 전부 그 껍질에서 일어난다. 껍질을 통과하지 않은 호출에는 아무것도 적용되지 않는다.

## 용어 정리

| 용어 | 뜻 |
|---|---|
| 조인 포인트(Join point) | 부가 기능을 끼워 넣을 수 있는 지점. Spring AOP에서는 **메서드 실행**뿐이다 |
| 포인트컷(Pointcut) | 조인 포인트 중 어디에 적용할지 고르는 표현식 |
| 어드바이스(Advice) | 끼워 넣을 부가 기능 자체 |
| 애스펙트(Aspect) | 포인트컷과 어드바이스를 묶은 단위 |
| 타깃(Target) | 부가 기능이 적용되는 원본 객체 |
| 프록시(Proxy) | 타깃을 감싸 어드바이스를 실행하는 대리 객체 |

## 핵심 정리

스프링이 프록시를 만드는 방식은 두 가지다.

| | JDK 동적 프록시 | CGLIB 프록시 |
|---|---|---|
| 만드는 방법 | 인터페이스를 구현한 클래스를 런타임에 생성 | 대상 클래스를 **상속**한 클래스를 런타임에 생성 |
| 전제 조건 | 대상이 인터페이스를 구현해야 한다 | 상속 가능해야 한다 |
| 적용 안 되는 메서드 | 인터페이스에 없는 메서드 | `private`, `final` 메서드 |
| 적용 안 되는 클래스 | 없음 | `final` 클래스 |
| 주입되는 타입 | 인터페이스 타입만 | 구체 클래스 타입도 가능 |

Spring Boot는 2.0부터 `proxyTargetClass = true`가 기본값이라, 인터페이스가 있어도 CGLIB를 쓴다.

## 항목별 설명

**프록시는 별도 클래스다.** 원본을 상속하거나 인터페이스를 구현한 다른 클래스이지 원본 자신이 아니다. `getClass()`를 찍어보면 이름에 `$$SpringCGLIB$$` 같은 접미사가 붙어 있다.

**CGLIB이 상속으로 동작한다**는 사실에서 제약이 전부 따라 나온다. `private` 메서드는 오버라이드할 수 없어 프록시가 가로챌 수 없고, `final` 메서드도 마찬가지다. Kotlin은 클래스와 메서드가 기본적으로 `final`이라 `kotlin-spring` 컴파일러 플러그인이 대상을 자동으로 `open`으로 바꿔주지 않으면 프록시 생성 자체가 실패한다.

## 예시

프록시를 거치는 호출과 거치지 않는 호출을 나란히 두면 차이가 드러난다.

```java
@Service
public class OrderService {

    @Transactional
    public void save(Order order) { ... }

    // 프록시를 거치지 않는다 — this.save()와 같다
    public void saveAll(List<Order> orders) {
        orders.forEach(this::save);
    }
}
```

```
컨트롤러 → [프록시] → OrderService.saveAll()  ← 여기까지만 프록시를 통과했다
                          └→ this.save()      ← 원본 객체 내부 호출. 트랜잭션 없음
```

`saveAll()`은 프록시를 통과했지만 그 안의 `save()`는 통과하지 않는다. `@Transactional`이 붙어 있어도 트랜잭션은 열리지 않는다.

## 혼동하기 쉬운 것

**어노테이션이 안 붙은 것과 프록시를 안 거친 것**은 증상이 같다. 둘 다 아무 일도 일어나지 않는다. 차이는 코드에 어노테이션이 보이느냐뿐이라, 후자가 훨씬 찾기 어렵다. 어노테이션이 무시되는 것처럼 보이면 호출 경로부터 확인한다.

**Spring AOP와 AspectJ**는 다르다. Spring AOP는 프록시 기반이라 메서드 실행 조인 포인트만 지원하고 스프링 빈에만 적용된다. AspectJ는 바이트코드를 위빙하므로 필드 접근·생성자·`private` 메서드까지 잡을 수 있고 자기 호출도 가로챈다. 위의 제약은 전부 Spring AOP의 제약이다.

**프록시는 `@Transactional`만의 것이 아니다.** `@Async`, `@Cacheable`, `@Retryable`, `@PreAuthorize` 모두 같은 구조 위에 있고 같은 제약을 받는다.

## 직접 확인

주입받은 빈이 프록시인지는 `AopUtils`로 확인한다.

```java
AopUtils.isAopProxy(orderService);                  // true
AopUtils.isCglibProxy(orderService);                // true
orderService.getClass();                            // OrderService$$SpringCGLIB$$0
AopProxyUtils.ultimateTargetClass(orderService);    // OrderService
```

## 더 깊이

- [같은 클래스 안에서 부른 @Transactional은 왜 동작하지 않을까](/posts/transactional-self-invocation/) — 자기 호출로 트랜잭션이 사라지는 것을 테스트로 확인한 기록

## 참고

- [Spring Framework Documentation — Aspect Oriented Programming with Spring](https://docs.spring.io/spring-framework/reference/core/aop.html)
- [Spring Framework Documentation — Proxying Mechanisms](https://docs.spring.io/spring-framework/reference/core/aop/proxying.html)
