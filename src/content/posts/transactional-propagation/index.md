---
title: 예외를 잡았는데 왜 롤백될까
description: "@Transactional 전파 속성과 rollback-only 표시를 테스트로 확인했다"
pubDate: 2026-08-06
tags: ["파고들기", "Spring", "트랜잭션", "테스트"]
category: "Spring"
---

## 전제

[@Transactional 전파 속성 7가지](/posts/transaction-propagation-types/)에서 정리한 전파 속성의 정의와 기본 롤백 규칙을 알고 있다고 보고 출발한다.

## 왜 필요한가

안쪽 메서드에서 발생한 예외를 바깥에서 try-catch로 잡았는데도, 최종 커밋 시점에 `UnexpectedRollbackException`이 발생하며 전체가 실패하는 경우가 있다. 예외를 분명히 처리했는데 롤백되므로 코드만 봐서는 이유가 드러나지 않는다. 원인은 `@Transactional`의 전파 속성과 rollback-only 표시에 있다.

## 동작 원리

REQUIRED로 참여한 안쪽 메서드에서 예외가 발생하면, 그 예외가 프록시를 빠져나가는 순간 공유 중인 물리 트랜잭션에 rollback-only 표시가 붙는다. 바깥이 이 예외를 try-catch로 잡아 정상 종료해도 표시는 남아 있으므로, 커밋 시점에 `UnexpectedRollbackException`이 발생하며 전체가 롤백된다. "예외를 분명히 잡았는데 왜 롤백되는가"의 답이 여기 있다. REQUIRED로 참여한 메서드들은 논리적으로는 여러 트랜잭션이지만 실제로는 하나의 물리 트랜잭션을 공유하므로, 일부만 롤백하는 것은 불가능하다.

rollback-only 표시가 붙는 조건은 예외의 종류에 달려 있다. 기본 롤백 대상은 unchecked 예외뿐이므로, checked 예외를 던지는 안쪽 메서드는 애초에 표시를 남기지 않는다. 같은 구조인데도 롤백이 일어나지 않는 경우가 여기서 갈린다.

## 직접 확인

검증한 시나리오는 하나다. 바깥이 저장하고, 안쪽을 부르고, 안쪽이 저장한 뒤 예외를 던지고, 바깥이 그 예외를 잡은 다음 복구용 저장을 한 번 더 한다. 여기서 안쪽의 전파 속성만 바꿔가며 결과를 비교한다. Spring Boot + Kotlin + Kotest 환경에서 확인했다.

구조는 다음과 같다.

```kotlin
@Transactional                            // 바깥: REQUIRED (기본값)
fun outer() {
    save(OUTER_MESSAGE)                   // ①
    try {
        inner()
    } catch (e: RuntimeException) {
        // 잡았다. 바깥은 이대로 정상 종료로 향한다
    }
    save(RECOVERY_MESSAGE)                // ② 예외를 처리했으니 복구 작업을 이어서 한다
}

@Transactional(propagation = REQUIRED)    // 안쪽: 바깥 트랜잭션에 참여한다
fun inner() {
    save(INNER_MESSAGE)                   // ③
    throw RuntimeException()
}
```

관전 포인트는 저장 ①②③의 생사다. 바깥이 예외를 잡고 정상 종료하므로 직관적으로는 셋 다 남아야 한다.

결과는 다르다. 셋 다 사라지고, 그 전에 커밋 자체가 실패한다.

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

`count()`가 0이라는 것은 ①②③이 전부 사라졌다는 뜻이다. 예외가 안쪽 프록시를 빠져나온 순간 공유 트랜잭션에 rollback-only가 찍혔고, 바깥이 예외를 잡은 것도 그 뒤에 실행한 ②도 이미 정해진 결말을 되돌리지 못한다.

이제 안쪽의 전파 속성 한 줄만 바꾼다. 바깥 코드는 그대로다.

```kotlin
@Transactional(propagation = REQUIRES_NEW)   // 안쪽: 별도의 물리 트랜잭션을 연다
fun inner() {
    save(INNER_MESSAGE)
    throw RuntimeException()
}
```

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

③(`INNER_MESSAGE`)만 0으로 사라지고, ①(`OUTER_MESSAGE`)과 ②(`RECOVERY_MESSAGE`)는 각각 1로 남는다. 안쪽이 별도의 물리 트랜잭션이라 롤백 범위가 안쪽에 갇히고, 바깥은 오염되지 않아 예외를 잡고 복구까지 마칠 수 있다.

두 결과를 가른 것은 `propagation` 한 줄뿐이다.

저장소: [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)

## 언제 쓰고 언제 안 쓰나

REQUIRES_NEW는 본 작업이 실패해도 반드시 남겨야 하는 기록 — 로그, 이력, 알림 발송 기록 — 을 저장할 때 쓴다. 다만 별도 커넥션을 쓰므로 커넥션 풀 크기를 함께 고려해야 하고, 부모가 잠근 행을 자식이 다시 잠그면 자기 자신과 데드락(self-deadlock)에 빠질 수 있다는 점도 주의해야 한다. NESTED는 세이브포인트 기반이라 자식만 부분적으로 롤백할 수 있지만, 바깥 트랜잭션이 롤백되면 세이브포인트 이전 상태를 포함해 전체가 함께 롤백된다.

## 참고

- [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)
- [Spring Framework Documentation — Transaction Propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
