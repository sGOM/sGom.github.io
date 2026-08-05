---
title: 같은 클래스 안에서 부른 @Transactional은 왜 동작하지 않을까
description: Spring AOP의 프록시 기반 동작을 테스트로 확인했습니다
pubDate: 2026-08-07
tags: ["Spring", "트랜잭션", "AOP"]
series: "트랜잭션을 테스트로 확인하기"
seriesOrder: 3
---

## 왜 필요한가

`@Transactional`을 분명히 붙였는데 저장한 데이터가 롤백되지 않는 상황이 있습니다. 어노테이션은 코드에 그대로 있으므로, 코드만 눈으로 봐서는 원인이 드러나지 않습니다. 예외도 없고 경고 로그도 없이 트랜잭션이 조용히 무시되기 때문에, 데이터가 남아 있는 것을 확인하고 나서야 뭔가 잘못됐다는 것을 알게 됩니다.

## 핵심 개념

Spring AOP는 기본적으로 프록시 기반으로 동작합니다. 스프링이 빈을 주입할 때 실제로 넘겨주는 것은 개발자가 작성한 원본 객체가 아니라, 그 객체를 감싼 프록시입니다. `@Transactional`을 포함한 선언적 트랜잭션 처리는 이 프록시가 담당합니다. 즉 트랜잭션의 시작과 커밋·롤백은 원본 객체가 아니라 프록시 계층에서 일어나는 일입니다.

## 동작 원리

호출이 프록시를 거치면 프록시가 트랜잭션을 시작한 뒤 원본 객체의 메서드를 실행합니다. 문제는 같은 클래스 안에서 `this.method()`로 자기 자신의 메서드를 부르는 경우입니다. 이 호출은 프록시를 거치지 않고 원본 객체 안에서 곧바로 실행되므로, 그 메서드에 `@Transactional`이 붙어 있어도 트랜잭션이 시작되지 않습니다. 어노테이션 자체는 무시되는 것이 아니라, 애초에 그 어노테이션을 처리할 프록시를 통과하지 않은 것입니다.

같은 이유로 `private`이나 `final` 메서드에 붙인 `@Transactional`도 동작하지 않습니다. CGLIB 프록시는 원본 클래스를 상속해서 메서드를 오버라이드하는 방식으로 동작하는데, `private` 메서드는 오버라이드할 수 없고 `final` 메서드도 마찬가지이기 때문입니다. Kotlin은 클래스와 메서드가 기본적으로 `final`이라, `kotlin-spring` 컴파일러 플러그인이 `@Transactional`이 붙은 대상을 자동으로 `open`으로 바꿔주지 않으면 이 문제가 훨씬 자주 발생합니다.

해결 방법은 우선순위 순으로 정리됩니다. 첫째, 트랜잭션이 필요한 메서드를 별도의 빈으로 분리해 외부에서 호출하는 방법이 가장 단순하고 우선적으로 권할 만합니다. 둘째, 자기 자신을 프록시로 다시 주입받아 그 프록시를 통해 호출하는 방법이 있습니다. 생성자에서 자기 자신을 직접 주입받으면 순환 참조가 되므로 `ObjectProvider` 같은 지연 조회 방식을 씁니다. 셋째, `AopContext.currentProxy()`로 현재 프록시를 얻어 호출하는 방법도 있는데, `@EnableAspectJAutoProxy(exposeProxy = true)` 설정이 필요합니다.

## 직접 확인

아래는 CGLIB 프록시라는 사실 자체를 검증한 테스트입니다. 스프링이 주입한 빈이 원본 클래스가 아니라 그것을 상속한 별도의 프록시 클래스라는 것을 확인합니다.

```kotlin
Given("주입받은 빈의 정체") {
    When("주입된 인스턴스를 들여다보면") {
        Then("원본 클래스가 아니라 CGLIB 프록시다") {
            // 트랜잭션이 "프록시를 통과할 때"만 걸린다는 사실의 물리적 근거.
            AopUtils.isAopProxy(selfInvocationService).shouldBeTrue()
            AopUtils.isCglibProxy(selfInvocationService).shouldBeTrue()

            // 프록시 클래스는 원본을 상속한 별도 클래스다.
            selfInvocationService.javaClass shouldNotBe SelfInvocationService::class.java
            AopProxyUtils.ultimateTargetClass(selfInvocationService) shouldBe SelfInvocationService::class.java
        }
    }
}
```

다음은 같은 클래스 안에서 `this`로 호출한 경우입니다. 저장 후 예외를 던지는 메서드에 `@Transactional`이 붙어 있지만, 자기 호출이라 프록시를 거치지 않으므로 트랜잭션이 열리지 않고 저장이 그대로 커밋됩니다.

```kotlin
Given("같은 클래스 안에서 this 로 @Transactional 메서드를 호출할 때") {
    When("트랜잭션 상태를 확인하면") {
        Then("프록시를 거치지 않았으므로 물리 트랜잭션이 열려 있지 않다") {
            val snapshot = selfInvocationService.snapshotViaInternalCall()

            snapshot.actualTransactionActive.shouldBeFalse()
        }
    }

    When("그 메서드 안에서 저장 후 예외를 던지면") {
        Then("트랜잭션이 없으므로 저장은 자동 커밋되어 롤백되지 않는다") {
            // @Transactional 이 붙어 있는데도 롤백되지 않는다. 이것이 자기 호출 함정이다.
            shouldThrow<InnerFailureException> {
                selfInvocationService.callInternally()
            }

            logsRepository.count() shouldBe 1
        }
    }
}
```

반대로 자기 자신을 프록시로 다시 주입받아(`ObjectProvider`) 그 프록시를 통해 같은 메서드를 호출하면, 이번에는 호출이 프록시를 거치므로 트랜잭션이 정상적으로 열리고 예외 발생 시 롤백도 일어납니다. 컨트롤러 같은 외부에서 호출하는 경우와 트랜잭션 동작 방식이 동일합니다.

```kotlin
Given("자기 자신을 프록시로 주입받아 호출할 때") {
    When("트랜잭션 상태를 확인하면") {
        Then("정상적으로 물리 트랜잭션이 열린다") {
            val snapshot = selfInvocationService.snapshotViaProxy()

            snapshot.actualTransactionActive.shouldBeTrue()
            snapshot.transactionName!!.substringAfterLast('.') shouldBe "transactionalSnapshot"
        }
    }

    When("그 메서드 안에서 저장 후 예외를 던지면") {
        Then("이번에는 @Transactional 이 적용되어 정상적으로 롤백된다") {
            shouldThrow<InnerFailureException> {
                selfInvocationService.callThroughProxy()
            }

            logsRepository.count() shouldBe 0
        }
    }
}
```

같은 저장 로직인데도 자기 호출은 `count() shouldBe 1`로 남고, 프록시를 거친 호출은 `count() shouldBe 0`으로 사라집니다. 프록시를 거쳤는지 여부만 다를 뿐인데 롤백 여부가 갈리는 것을 그대로 보여줍니다.

저장소: [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)

## 언제 쓰고 언제 안 쓰나

이 함정은 `@Transactional`에만 한정되지 않습니다. `@Async`, `@Cacheable`처럼 프록시 기반 AOP로 구현된 어노테이션은 모두 같은 제약을 받습니다. 어노테이션이 붙은 메서드를 같은 클래스 안에서 호출하고 있다면, 그 어노테이션이 실제로는 적용되지 않았을 가능성을 먼저 의심해야 합니다. 리뷰에서도 자기 호출 여부는 눈으로 코드를 읽는 것만으로 확인할 수 있으므로 놓치기 쉬운 지점입니다.

## 참고

- [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)
- [Spring Framework Documentation — Using @Transactional (self-invocation)](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html)
