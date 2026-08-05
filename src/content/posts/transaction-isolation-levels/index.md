---
title: 트랜잭션 격리 수준은 DBMS마다 다르게 동작합니다
description: 표준 정의만 외우면 실무에서 틀리는 이유와, 테스트로 직접 확인한 기록
pubDate: 2026-08-05
tags: ["Database", "트랜잭션", "테스트"]
---

## 왜 필요한가

같은 조회를 두 번 실행했는데 결과가 다르면, 코드에는 문제가 없는데도 원인을 찾지 못하는 상황이 생깁니다. 한 트랜잭션 안에서 같은 행을 두 번 읽었을 뿐인데 값이 바뀌어 있거나, 같은 조건으로 두 번 조회했는데 행의 개수가 달라지는 경우가 그렇습니다. 로직을 아무리 다시 봐도 이상한 곳이 없는 이유는, 문제가 애플리케이션 코드가 아니라 트랜잭션 격리 수준에 있기 때문입니다. 격리 수준을 모르면 이런 현상을 재현할 수도, 설명할 수도 없습니다.

## 핵심 개념

격리 수준은 동시에 실행되는 트랜잭션이 서로의 변경을 얼마나 볼 수 있는지를 정하는 설정입니다. SQL 표준은 4단계를 정의하고, 각 단계가 허용하거나 막는 이상 현상을 아래처럼 규정합니다.

| 격리 수준 | Dirty Read | Non-Repeatable Read | Phantom Read |
|---|---|---|---|
| READ UNCOMMITTED | 발생 가능 | 발생 가능 | 발생 가능 |
| READ COMMITTED | 방지 | 발생 가능 | 발생 가능 |
| REPEATABLE READ | 방지 | 방지 | 발생 가능 |
| SERIALIZABLE | 방지 | 방지 | 방지 |

세 이상 현상의 정의는 다음과 같습니다.

- **Dirty Read**: 아직 커밋되지 않은 다른 트랜잭션의 변경을 읽는 현상입니다.
- **Non-Repeatable Read**: 같은 트랜잭션 안에서 같은 행을 두 번 읽었을 때 값이 달라지는 현상입니다.
- **Phantom Read**: 같은 조건으로 두 번 조회했을 때 행의 개수가 달라지는 현상입니다.

## 동작 원리

위 표는 SQL 표준이 정의한 최소 기준일 뿐이고, 실제 DBMS의 동작은 이 표와 정확히 일치하지 않습니다. 표를 그대로 외워서 실무에 적용하면 틀리는 경우가 있는 이유입니다.

MySQL InnoDB는 기본 격리 수준이 REPEATABLE READ입니다. 표준 정의상 REPEATABLE READ는 Phantom Read를 허용하지만, InnoDB는 갭 락(gap lock)과 넥스트키 락(next-key lock)을 사용해 잠금을 동반하는 읽기(locking read)에서 Phantom Read를 상당 부분 막습니다.

PostgreSQL은 기본 격리 수준이 READ COMMITTED이고, MVCC(다중 버전 동시성 제어) 기반으로 동작합니다. MVCC는 읽는 트랜잭션과 쓰는 트랜잭션이 서로 다른 버전의 행을 보게 하므로, 읽기가 쓰기를 막지 않습니다. PostgreSQL의 REPEATABLE READ는 트랜잭션 시작 시점의 스냅샷을 보는 방식으로 구현되어 있어 Phantom Read가 발생하지 않는 대신, 같은 데이터를 동시에 수정하는 충돌이 생기면 직렬화 실패(serialization failure)로 트랜잭션이 종료되어 애플리케이션이 재시도 로직을 갖춰야 합니다.

## 직접 확인

아래는 H2(2.x, MVStore 모드) 환경에서 REPEATABLE READ를 검증한 테스트입니다. H2도 스냅샷 방식으로 REPEATABLE READ를 구현하고 있어, 읽기 트랜잭션이 시작된 후 다른 트랜잭션이 새 행을 INSERT하고 커밋해도 그 행이 보이지 않는지를 확인합니다. `worker`와 `Signal`은 두 트랜잭션의 실행 순서를 스레드로 고정해 결과가 흔들리지 않게 하는 테스트 헬퍼입니다.

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

## 언제 쓰고 언제 안 쓰나

기본값을 바꿀 구체적인 이유가 없으면 기본값을 유지하는 편이 낫습니다. READ COMMITTED로 낮추면 잠금 경합이 줄어드는 대신 같은 트랜잭션 안에서 반복 조회한 값이 달라질 수 있으므로, 그 가능성을 코드가 감당할 수 있는지 먼저 따져야 합니다. SERIALIZABLE은 정합성이 절대적으로 중요한 짧은 트랜잭션에 한정해서 검토할 만합니다. 무엇보다, 어떤 DBMS를 쓰는지 확인하는 것이 격리 수준 표를 외우는 것보다 먼저입니다. 같은 이름의 격리 수준도 DBMS마다 구현이 다르기 때문입니다.

## 참고

- [github.com/sGOM/spring-transactional-test](https://github.com/sGOM/spring-transactional-test)
- [MySQL 8.0 Reference Manual — InnoDB Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
- [PostgreSQL Documentation — Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
