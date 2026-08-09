---
title: "@Transactional 전파 속성 7가지"
description: 진행 중인 트랜잭션을 만났을 때의 동작 7가지와 기본 롤백 규칙을 정리한다
pubDate: 2026-08-09
category: "Spring"
tags: ["기본개념", "Spring", "트랜잭션"]
---

## 전제

[트랜잭션과 ACID](/posts/transaction-and-acid/)에서 다룬 커밋·롤백 단위가, Spring에서는 메서드 경계로 선언된다.

## 왜 필요한가

`@Transactional`이 붙은 메서드가 다른 `@Transactional` 메서드를 부르면 트랜잭션이 두 개 생기는지 하나인지가 정해져야 한다. 이것을 정하는 것이 `propagation` 속성이다.

기본값 REQUIRED만 쓰다 보면 이 선택지가 있다는 사실 자체를 잊는다. 그러다 "안쪽에서 난 예외를 잡았는데 전체가 롤백되는" 상황을 만나면 코드만으로는 설명하지 못한다.

## 용어 정리

- **물리 트랜잭션**: 실제 커넥션에서 열린 DB 트랜잭션. 커밋·롤백의 실제 단위다.
- **논리 트랜잭션**: `@Transactional`이 붙은 메서드 호출 하나하나의 범위. 여러 논리 트랜잭션이 하나의 물리 트랜잭션을 공유할 수 있다.
- **일시 중단(suspend)**: 진행 중인 트랜잭션을 잠시 보류하고 별도 커넥션에서 새 트랜잭션을 여는 것. 보류된 트랜잭션은 새 트랜잭션이 끝난 뒤 재개된다.

## 핵심 정리

| 전파 속성 | 진행 중인 트랜잭션이 있으면 | 없으면 |
|---|---|---|
| REQUIRED (기본값) | 참여한다 | 새로 시작한다 |
| REQUIRES_NEW | 일시 중단하고 새로 시작한다 | 새로 시작한다 |
| NESTED | 세이브포인트를 만들어 중첩한다 | 새로 시작한다 |
| SUPPORTS | 참여한다 | 트랜잭션 없이 실행한다 |
| NOT_SUPPORTED | 일시 중단하고 트랜잭션 없이 실행한다 | 트랜잭션 없이 실행한다 |
| MANDATORY | 참여한다 | 예외를 던진다 |
| NEVER | 예외를 던진다 | 트랜잭션 없이 실행한다 |

MANDATORY와 NEVER가 던지는 예외는 `IllegalTransactionStateException`이다.

## 항목별 설명

**REQUIRED**로 참여한 메서드들은 논리적으로는 여러 트랜잭션이지만 물리 트랜잭션은 하나다. 커밋과 롤백이 통째로 움직이므로 일부만 롤백할 수 없다.

**REQUIRES_NEW**는 별도 커넥션에서 별도 물리 트랜잭션을 연다. 롤백 범위가 물리적으로 분리되지만, 그만큼 커넥션을 하나 더 점유한다. 바깥이 잠근 행을 안쪽이 다시 잠그면 자기 자신과 데드락에 빠진다.

**NESTED**는 하나의 물리 트랜잭션 안에 세이브포인트를 찍는다. 안쪽만 세이브포인트까지 되돌릴 수 있지만, 바깥이 롤백되면 세이브포인트 이전까지 전부 함께 롤백된다. JDBC 세이브포인트로 구현되어 `DataSourceTransactionManager`에서 동작하며, 세이브포인트를 지원하지 않는 트랜잭션 매니저에서는 예외가 발생한다.

## 예시

전파 속성별로 물리 트랜잭션이 몇 개 열리는지가 갈린다.

```java
@Transactional                                       // 바깥: REQUIRED
public void outer() {
    save("outer");
    inner();                                         // 안쪽의 propagation에 따라 달라진다
}
```

| 안쪽의 propagation | 물리 트랜잭션 수 | 안쪽에서 예외가 나고 바깥이 잡으면 |
|---|---|---|
| REQUIRED | 1개 (공유) | 커밋 시점에 `UnexpectedRollbackException`, 전부 롤백 |
| REQUIRES_NEW | 2개 (분리) | 안쪽만 롤백, 바깥은 정상 커밋 |
| NESTED | 1개 + 세이브포인트 | 안쪽만 세이브포인트까지 롤백 |

## 혼동하기 쉬운 것

**REQUIRES_NEW와 NESTED**는 "안쪽만 롤백된다"는 결과가 비슷해 헷갈린다. 갈림길은 바깥이 롤백될 때다. REQUIRES_NEW는 이미 커밋된 별도 트랜잭션이라 살아남고, NESTED는 같은 물리 트랜잭션이라 함께 사라진다.

**롤백 대상 예외의 기본값**도 자주 틀린다. 선언적 트랜잭션은 unchecked 예외(`RuntimeException`과 그 하위, `Error`)에서만 롤백하고, checked 예외는 롤백을 유발하지 않는다.

| 던진 예외 | 기본 동작 |
|---|---|
| `RuntimeException` 및 하위 | 롤백 |
| `Error` | 롤백 |
| checked `Exception` | **커밋** |

checked 예외로 롤백시키려면 `@Transactional(rollbackFor = Exception.class)`를 지정한다.

**전파 속성은 프록시를 거쳐야 적용된다.** 같은 클래스 안에서 `this.inner()`로 부르면 `propagation`을 무엇으로 적어도 아무 일도 일어나지 않는다. 이유는 [Spring AOP 프록시](/posts/spring-aop-proxy/)에 있다.

## 언제 어떤 것을 쓰나

기본값 REQUIRED를 쓴다. 바꿀 이유는 대체로 하나다 — **본 작업이 실패해도 반드시 남겨야 하는 기록**이 있을 때 그 부분만 REQUIRES_NEW로 분리한다. 감사 로그, 발송 이력, 실패 이력이 여기 해당한다.

MANDATORY와 NEVER는 동작을 바꾸기보다 전제를 강제하는 용도다. "이 메서드는 반드시 트랜잭션 안에서 불려야 한다"를 문서 대신 코드로 못박을 때 쓴다.

## 더 깊이

- [예외를 잡았는데 왜 롤백될까](/posts/transactional-propagation/) — rollback-only 표시가 붙는 순간을 테스트로 확인한 기록

## 참고

- [Spring Framework Documentation — Transaction Propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
