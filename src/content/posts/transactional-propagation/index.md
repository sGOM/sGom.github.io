---
title: 예외를 잡았는데 왜 롤백될까
description: "@Transactional 전파 속성과 rollback-only 표시를 테스트로 확인했다"
pubDate: 2026-08-06
tags: ["Spring", "트랜잭션", "테스트"]
series: "트랜잭션을 테스트로 확인하기"
seriesOrder: 2
---

## 왜 필요한가

안쪽 메서드에서 발생한 예외를 바깥에서 try-catch로 잡았는데도, 최종 커밋 시점에 `UnexpectedRollbackException`이 발생하며 전체가 실패하는 경우가 있다. 예외를 분명히 처리했는데 롤백되므로 코드만 봐서는 이유가 드러나지 않는다. 원인은 `@Transactional`의 전파 속성과 rollback-only 표시에 있다.

## 핵심 개념

`@Transactional`의 `propagation` 속성은 메서드가 이미 진행 중인 트랜잭션을 만났을 때 어떻게 동작할지 정한다. 실무에서 주로 다루는 세 가지는 다음과 같다.

| 전파 속성 | 동작 |
|---|---|
| REQUIRED (기본값) | 진행 중인 트랜잭션이 있으면 참여하고, 없으면 새로 시작한다. |
| REQUIRES_NEW | 진행 중인 트랜잭션을 일시 중단하고 항상 새 트랜잭션을 시작한다. |
| NESTED | 진행 중인 트랜잭션이 있으면 세이브포인트를 사용해 중첩하고, 없으면 REQUIRED와 같이 새로 시작한다. |

나머지 네 가지는 다음과 같이 동작한다.

- **SUPPORTS**: 진행 중인 트랜잭션이 있으면 참여하고, 없으면 트랜잭션 없이 실행한다.
- **MANDATORY**: 진행 중인 트랜잭션이 반드시 있어야 하며, 없으면 예외가 발생한다.
- **NEVER**: 트랜잭션 없이 실행되어야 하며, 진행 중인 트랜잭션이 있으면 예외가 발생한다.
- **NOT_SUPPORTED**: 진행 중인 트랜잭션을 일시 중단하고 트랜잭션 없이 실행한다.

## 동작 원리

REQUIRED로 참여한 안쪽 메서드에서 예외가 발생하면, 그 예외가 프록시를 빠져나가는 순간 공유 중인 물리 트랜잭션에 rollback-only 표시가 붙는다. 바깥이 이 예외를 try-catch로 잡아 정상 종료해도 표시는 남아 있으므로, 커밋 시점에 `UnexpectedRollbackException`이 발생하며 전체가 롤백된다. "예외를 분명히 잡았는데 왜 롤백되는가"의 답이 여기 있다. REQUIRED로 참여한 메서드들은 논리적으로는 여러 트랜잭션이지만 실제로는 하나의 물리 트랜잭션을 공유하므로, 일부만 롤백하는 것은 불가능하다.

함께 알아야 할 함정이 두 가지 더 있다. 첫째, Spring의 `@Transactional`은 프록시 기반으로 동작하므로 같은 클래스 안에서 메서드를 직접 호출하는 자기 호출(self-invocation)에는 적용되지 않는다. 프록시를 거치지 않기 때문이다. 둘째, 기본 롤백 대상은 unchecked 예외(`RuntimeException`과 그 하위 클래스, `Error`)이고, checked 예외는 기본적으로 롤백을 유발하지 않으므로 롤백시키려면 `rollbackFor` 속성을 지정해야 한다.

## 직접 확인

같은 시나리오 — 안쪽에서 예외가 발생하고 바깥이 try-catch로 잡는 경우 — 를 REQUIRED와 REQUIRES_NEW로 각각 실행한 테스트다. Spring Boot + Kotlin + Kotest 환경에서 검증했다.

REQUIRED로 참여한 경우, 안쪽 예외는 바깥에서 잡히지만 rollback-only 오염 때문에 커밋 시점에 실패한다.

```kotlin
When("안쪽이 예외를 던지고 바깥이 그 예외를 try-catch 로 삼키면") {
    Then("바깥은 정상 종료하지만 커밋 시점에 UnexpectedRollbackException 이 터지고 전부 롤백된다") {
        // 안쪽 프록시를 예외가 빠져나가는 순간 공유 트랜잭션에 rollback-only 가 찍힌다.
        // 바깥은 예외를 잡고 추가로 save() 까지 했지만 아무 의미가 없다.
        val exception = shouldThrow<UnexpectedRollbackException> {
            outerService.requiredCallingRequiredAndCatch()
        }

        exception.message!!.contains("rollback-only") shouldBe true

        // 바깥의 저장 + 안쪽의 저장 + catch 후 복구 시도까지 전부 사라진다.
        logsRepository.count() shouldBe 0
    }
}
```

REQUIRES_NEW로 호출한 경우, 안쪽은 별도의 물리 트랜잭션이므로 안쪽만 롤백되고 바깥은 오염 없이 정상 커밋된다.

```kotlin
When("안쪽이 예외를 던지고 바깥이 그 예외를 잡으면") {
    Then("안쪽만 롤백되고 바깥은 rollback-only 오염 없이 정상 커밋된다") {
        // 같은 상황을 REQUIRED 로 하면 UnexpectedRollbackException 이 터졌다.
        // REQUIRES_NEW 는 롤백 대상이 물리적으로 분리돼 있어 예외를 잡고 복구까지 할 수 있다.
        outerService.requiredCallingRequiresNewAndCatch()

        logsRepository.countByMessage(InnerService.INNER_MESSAGE) shouldBe 0
        logsRepository.countByMessage(OuterService.OUTER_MESSAGE) shouldBe 1
        logsRepository.countByMessage(OuterService.RECOVERY_MESSAGE) shouldBe 1
    }
}
```

저장소: [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)

## 언제 쓰고 언제 안 쓰나

REQUIRES_NEW는 본 작업이 실패해도 반드시 남겨야 하는 기록 — 로그, 이력, 알림 발송 기록 — 을 저장할 때 쓴다. 다만 별도 커넥션을 쓰므로 커넥션 풀 크기를 함께 고려해야 하고, 부모가 잠근 행을 자식이 다시 잠그면 자기 자신과 데드락(self-deadlock)에 빠질 수 있다는 점도 주의해야 한다. NESTED는 세이브포인트 기반이라 자식만 부분적으로 롤백할 수 있지만, 바깥 트랜잭션이 롤백되면 세이브포인트 이전 상태를 포함해 전체가 함께 롤백된다.

## 참고

- [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)
- [Spring Framework Documentation — Transaction Propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
