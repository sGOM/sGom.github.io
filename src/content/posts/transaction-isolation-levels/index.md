---
title: 트랜잭션 격리 수준은 DBMS마다 다르게 동작한다
description: 표준 정의만 외우면 실무에서 틀리는 이유와, 테스트로 직접 확인한 기록
pubDate: 2026-08-05
updatedDate: 2026-08-24
tags: ["파고들기", "Database", "트랜잭션", "테스트"]
category: "데이터베이스"
---

## 전제

[격리 수준과 세 가지 이상 현상](/posts/isolation-levels-and-anomalies/)에서 정리한 SQL 표준 4단계와 세 이상 현상을 알고 있다고 보고 출발한다. 이 글은 그 표가 실제 DBMS에서 어떻게 어긋나는지를 다룬다.

## 무엇이 문제인가

같은 조회를 두 번 실행했는데 결과가 다른 경우가 있다. 한 트랜잭션 안에서 같은 행을 두 번 읽었는데 값이 바뀌어 있거나, 같은 조건으로 조회했는데 행 수가 달라진다.

원인은 애플리케이션 코드가 아니라 격리 수준에 있다. 격리 수준을 모르면 재현도 설명도 못 한다.

## 동작 원리

표준의 4단계 표는 최소 기준이며, 실제 DBMS의 동작은 이와 정확히 일치하지 않는다. 표를 그대로 외워 실무에 적용하면 틀리는 이유다.

MySQL InnoDB는 기본 격리 수준이 REPEATABLE READ다. 표준 정의상 REPEATABLE READ는 Phantom Read를 허용하지만, InnoDB는 갭 락(gap lock)과 넥스트키 락(next-key lock)으로 잠금을 동반하는 읽기(locking read)에서 Phantom Read를 상당 부분 막는다.

PostgreSQL은 기본 격리 수준이 READ COMMITTED이고, MVCC(다중 버전 동시성 제어)로 동작한다. MVCC는 읽는 트랜잭션과 쓰는 트랜잭션이 서로 다른 버전의 행을 보게 해, 읽기가 쓰기를 막지 않는다.

PostgreSQL의 REPEATABLE READ는 트랜잭션 시작 시점의 스냅샷을 보므로 Phantom Read가 발생하지 않는다. 대신 같은 데이터를 동시에 수정하는 충돌이 생기면 직렬화 실패(serialization failure)로 트랜잭션이 끝나므로, 애플리케이션에 재시도 로직이 필요하다.

## 직접 확인

아래는 H2(2.x, MVStore 모드)에서 REPEATABLE READ를 검증한 테스트다. 읽기 트랜잭션 시작 후 다른 트랜잭션이 새 행을 INSERT하고 커밋해도 그 행이 보이지 않는지 확인한다.

`worker`와 `Signal`은 두 트랜잭션의 실행 순서를 스레드로 고정해 결과가 흔들리지 않게 하는 테스트 헬퍼다.

```kotlin
Given("REPEATABLE_READ") {
    When("읽기 트랜잭션 도중 다른 트랜잭션이 행을 새로 INSERT 하고 커밋하면") {
        Then("H2 의 스냅샷 격리 덕분에 팬텀 리드까지 함께 막힌다") {
            // 표준 SQL 은 REPEATABLE_READ 에서 팬텀 리드를 허용하지만,
            // 스냅샷 기반으로 구현한 DB(H2 MVStore, PostgreSQL 등)는 함께 막힌다.
            // "격리 수준의 이름"이 아니라 "DB 의 실제 구현"을 확인해야 하는 이유.
            val firstCount = AtomicLong()
            val secondCount = AtomicLong()
            val readerCountedOnce = Signal("readerCountedOnce")
            val writerCommitted = Signal("writerCommitted")

            val reader = worker("reader") {
                txExecutor.newTransaction(isolation = Isolation.REPEATABLE_READ) {
                    firstCount.set(logsRepository.countByMessage(PHANTOM_MESSAGE))
                    readerCountedOnce.send()
                    writerCommitted.await()
                    secondCount.set(logsRepository.countByMessage(PHANTOM_MESSAGE))
                }
            }
            val writer = worker("writer") {
                readerCountedOnce.await()
                txExecutor.newTransaction { logsRepository.save(Logs(PHANTOM_MESSAGE)) }
                writerCommitted.send()
            }

            runConcurrently(reader, writer).forEach { it.rethrowIfFailed() }

            firstCount.get() shouldBe 0
            secondCount.get() shouldBe 0
        }
    }
}
```

저장소: [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)

**이 결과는 H2가 보장하는 동작이 아니다.** H2 문서는 REPEATABLE READ를 "Dirty reads and non-repeatable reads aren't possible, phantom reads are possible"로 규정하고, 팬텀 리드까지 막는다고 명시한 수준은 따로 있는 `SNAPSHOT`이다. ([H2 — Transaction Isolation](https://h2database.com/html/advanced.html))

즉 위 테스트가 통과하는 것은 MVStore 구현이 문서가 약속한 것보다 더 강하게 격리하기 때문이고, 버전이 바뀌면 달라질 수 있는 자리다. 팬텀 차단이 필요하면 이름이 REPEATABLE READ인 것에 기대지 말고 `SNAPSHOT`을 지정해야 한다.

이름을 외우는 것으로는 부족하다는 이 글의 주장이 여기서 한 겹 더 들어간다. 같은 이름의 격리 수준이 DBMS마다 다를 뿐 아니라, **문서가 보장하는 것과 구현이 실제로 하는 것도 다를 수 있다.**

## 언제 쓰고 언제 안 쓰나

바꿀 구체적인 이유가 없으면 기본값을 유지한다.

READ COMMITTED로 낮추면 잠금 경합은 줄지만, 같은 트랜잭션 안에서 반복 조회한 값이 달라질 수 있다. 코드가 그 가능성을 감당하는지 먼저 따진다. SERIALIZABLE은 정합성이 중요한 짧은 트랜잭션에 한정해 검토한다.

무엇보다 어떤 DBMS를 쓰는지 확인하는 것이 격리 수준 표를 외우는 것보다 먼저다. 같은 이름의 격리 수준도 DBMS마다 구현이 다르다.

## 참고

- [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)
- [MySQL 8.0 Reference Manual — InnoDB Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
- [PostgreSQL Documentation — Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
