---
title: "데드락 대응 기법 — Coffman 4조건과 그 대가"
description: "데드락 대응 기법을 Coffman의 네 조건 중 무엇을 깨는지로 나누고, 예방·회피·탐지의 차이와 각 기법이 치르는 대가를 정리한다."
pubDate: 2026-08-31
category: "OS"
tags: ["기본개념", "동시성", "Java"]
---

## 왜 필요한가

락 두 개를 서로 반대 순서로 잡는 코드는 평소에 잘 돌다가 어느 순간 멈춘다.

```java
Thread t1 = new Thread(() -> grab(A, B), "T1");  // A 먼저
Thread t2 = new Thread(() -> grab(B, A), "T2");  // B 먼저
```

T1이 A를 잡고 B를 기다리는 사이 T2가 B를 잡아버리면 둘 다 깨어나지 못한다. 프로세스는 살아 있고 CPU도 쓰지 않아서, 스레드 덤프를 뜨기 전까지는 그냥 느린 것과 구분되지 않는다.

대응 방법은 하나가 아니다. 각 기법이 무엇을 포기하는지 알아야 고를 수 있다.

## 용어 정리

세 전략이 한국어로는 모두 "데드락을 피한다"로 뭉뚱그려지지만 서로 다른 것을 한다.

| 전략 | 개입 시점 | 하는 일 |
|---|---|---|
| 예방(prevention) | 설계 | 네 조건 중 하나를 구조적으로 성립하지 못하게 한다 |
| 회피(avoidance) | 자원 요청 | 할당해도 안전 상태가 유지될 때만 요청을 들어준다 |
| 탐지·복구(detection & recovery) | 발생 후 | 대기 그래프에서 순환을 찾아 일부를 중단하거나 롤백한다 |

아래에서 회피는 은행원 알고리즘류만 가리킨다. 락 순서를 통일하는 것은 회피가 아니라 예방이다.

## 핵심 정리

데드락은 네 조건이 동시에 성립할 때만 생긴다. [Coffman, Elphick, Shoshani의 1971년 논문](https://dl.acm.org/doi/10.1145/356586.356588)에서 정리돼 [Coffman 조건](https://en.wikipedia.org/wiki/Deadlock_(computer_science))으로 불린다. 하나만 깨도 데드락은 성립하지 않는다.

| 조건 | 뜻 | 깨는 기법 | 대가 |
|---|---|---|---|
| 상호 배제 | 자원을 공유할 수 없어 한 번에 한 프로세스만 쓴다 | 자원을 공유 가능하게 바꾼다 | 자원 성격상 대부분 불가능하다 |
| 점유와 대기 | 자원을 쥔 채로 다른 자원을 기다린다 | 필요한 것을 한 번에 다 잡고, 하나라도 실패하면 전부 놓는다 | 기아, 자원 이용률 하락 |
| 비선점 | 쥔 쪽이 자발적으로 놓아야만 자원이 풀린다 | 타임아웃이나 롤백으로 빼앗는다 | 재시도 로직, 라이브락 |
| 순환 대기 | 대기 관계가 고리를 이룬다 | 자원에 전순서를 주고 그 순서로만 잡는다 | 순서 규약을 코드 전체에 유지해야 한다 |

## 항목별 설명

### 상호 배제는 사실상 깨지지 않는다

프린터를 두 프로세스가 동시에 쓰게 만들 수는 없다. 스풀링처럼 공유 가능한 대리 자원을 끼워 넣는 우회는 있다. 다만 락이 지키는 불변식 자체가 상호 배제를 요구해 일반해는 없다. 네 조건 중 하나만 깨면 된다는 말은 맞지만 넷이 똑같이 공격 가능하다는 뜻은 아니다.

### 점유와 대기는 원자적 획득으로 깬다

필요한 락을 처음에 전부 잡고, 하나라도 못 잡으면 잡은 것을 모두 놓고 처음부터 다시 한다. 대기 중에 아무것도 쥐고 있지 않으므로 고리가 생기지 않는다.

문제는 두 가지다. 무엇이 필요한지 미리 다 알아야 하는데 실행 중에 결정되는 경우가 많다. 그리고 재시도가 반복되면 특정 스레드가 계속 밀려 기아 상태에 빠질 수 있다.

### 비선점은 타임아웃으로 깬다

기다리는 쪽이 일정 시간 뒤 포기하고 쥔 것을 놓으면 고리가 풀린다. Java에서 `synchronized`에는 시간 제한이 없고, [`ReentrantLock.tryLock(long, TimeUnit)`](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/util/concurrent/locks/ReentrantLock.html)이 그 자리를 대신한다.

타임아웃은 순환이 만들어지는 것 자체를 막지 못한다. 만들어진 뒤 풀 뿐이다. 포기한 뒤 곧바로 같은 순서로 다시 시도하면 같은 상황이 반복된다. 재시도 간격에 무작위 요소를 넣지 않으면 서로 양보만 하다 진행이 없는 라이브락이 된다.

### 순환 대기는 전순서로 깬다

자원마다 번호를 매기고 항상 번호가 커지는 방향으로만 잡는다. 모두가 같은 방향으로 올라가면 고리가 만들어질 수 없다. 실무에서 쓰이는 기법은 대개 이것이다. 위키백과 [Deadlock](https://en.wikipedia.org/wiki/Deadlock_(computer_science)) 항목은 자연스러운 계층이 없을 때의 대안까지 적어 놓았다.

> Approaches that avoid circular waits include disabling interrupts during critical sections and using a hierarchy to determine a partial ordering of resources. If no obvious hierarchy exists, even the memory address of resources has been used to determine ordering and resources are requested in the increasing order of the enumeration.

계좌 두 개 사이의 이체처럼 순서를 붙일 근거가 없는 자원에는 식별자나 객체 주소를 순서로 쓴다. 그 값이 자원마다 유일해야 순서가 성립한다.

```java
void transfer(Account from, Account to, long amount) {
    Account first  = from.id() < to.id() ? from : to;
    Account second = from.id() < to.id() ? to : from;
    synchronized (first) {
        synchronized (second) { /* ... */ }
    }
}
```

`System.identityHashCode`처럼 유일하지 않은 값을 순서로 쓴다면 동점일 때 먼저 잡는 별도의 락을 하나 두어야 한다. 동점을 처리하지 않으면 그 경우에 순서가 사라져 데드락이 다시 열린다.

## 예시

두 스레드가 같은 락 두 개를 반대 순서로 잡게 하고, [`ThreadMXBean.findDeadlockedThreads`](https://docs.oracle.com/en/java/javase/26/docs/api/java.management/java/lang/management/ThreadMXBean.html)로 결과를 확인한다. `ordered` 인자를 주면 두 스레드가 같은 순서로 잡는다.

```java
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.lang.management.ThreadMXBean;

public class LockOrder {
    static final Object A = new Object();
    static final Object B = new Object();

    static void grab(Object first, Object second) {
        synchronized (first) {
            sleep(100);
            synchronized (second) {
                System.out.println(Thread.currentThread().getName() + " 완료");
            }
        }
    }

    static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }

    public static void main(String[] args) throws Exception {
        boolean ordered = args.length > 0 && args[0].equals("ordered");

        Thread t1 = new Thread(() -> grab(A, B), "T1");
        Thread t2 = new Thread(() -> grab(ordered ? A : B, ordered ? B : A), "T2");
        t1.start();
        t2.start();

        t1.join(1000);
        t2.join(1000);

        ThreadMXBean mx = ManagementFactory.getThreadMXBean();
        long[] ids = mx.findDeadlockedThreads();
        if (ids == null) {
            System.out.println("데드락 없음");
            return;
        }
        for (ThreadInfo info : mx.getThreadInfo(ids)) {
            System.out.println(info.getThreadName()
                    + " 가 " + info.getLockName()
                    + " 를 기다림 (보유자: " + info.getLockOwnerName() + ")");
        }
        System.exit(1);
    }
}
```

마지막 `System.exit`이 없으면 프로그램이 끝나지 않는다. 데드락에 걸린 두 스레드가 데몬 스레드가 아니라서 JVM이 종료를 기다리기 때문이다.

JDK 26, Windows 11에서 실행했다. 컴파일 없이 소스 파일을 그대로 넘기는 실행 방식은 [JEP 330](https://openjdk.org/jeps/330)으로 JDK 11부터 들어갔다. `-Dstdout.encoding=UTF-8`은 Windows 콘솔에서 한글이 깨지지 않게 하는 것이라 데드락과는 무관하다.

반대 순서로 잡으면 두 스레드 모두 상대가 쥔 락에 걸려 있다.

```
$ java -Dstdout.encoding=UTF-8 LockOrder.java
T1 가 java.lang.Object@27ce24aa 를 기다림 (보유자: T2)
T2 가 java.lang.Object@7ed7259e 를 기다림 (보유자: T1)
```

`grab` 안의 코드는 그대로 두고 호출부의 인자 순서만 통일하면 사라진다.

```
$ java -Dstdout.encoding=UTF-8 LockOrder.java ordered
T1 완료
T2 완료
데드락 없음
```

## 혼동하기 쉬운 것

**타임아웃은 비선점을 깨지만 대가를 사후에 치른다.** 순환이 실제로 형성됐다가 풀리므로 그때까지의 작업이 버려지고 재시도된다. 조건이 애초에 성립하지 않게 만드는 전순서 통일과는 비용 구조가 다르다. 발생 빈도가 높을수록 차이가 커진다.

**은행원 알고리즘은 교과서 밖에서 거의 쓰이지 않는다.** [은행원 알고리즘](https://en.wikipedia.org/wiki/Banker%27s_algorithm)은 각 프로세스가 앞으로 요청할 자원의 최대치를 미리 선언해야 동작한다. 위키백과 항목도 "in most systems, this information is unavailable, making it impossible to implement the Banker's algorithm"이라고 적는다. 프로세스 수가 실행 중에 변한다는 점도 전제와 맞지 않는다.

**데드락, 라이브락, 기아는 다르다.** 데드락은 서로를 기다리며 아무도 진행하지 못하는 상태다. 라이브락은 상태가 계속 바뀌는데도 진행이 없는 상태이고, 기아는 다른 스레드는 진행하는데 특정 스레드만 계속 밀리는 상태다. 타임아웃과 재시도는 데드락을 라이브락으로 바꿔 놓기 쉽다.

## 언제 어떤 것을 쓰나

| 층 | 실제로 쓰는 방식 |
|---|---|
| 애플리케이션 코드 | 락 전순서 통일이 1순위, 락 보유 구간 축소가 2순위. 그래도 남는 위험에 타임아웃 |
| DBMS | 탐지·복구. 순환을 찾아 한쪽 트랜잭션을 희생시킨다 |
| 범용 OS | 대부분 무시한다 |

PostgreSQL은 락 대기가 [`deadlock_timeout`](https://www.postgresql.org/docs/current/runtime-config-locks.html)(기본값 `1s`)을 넘길 때만 탐지를 돌린다. 문서는 그 이유를 "The check for deadlock is relatively expensive, so the server doesn't run it every time it waits for a lock"이라고 적는다. 매번 검사하는 대신 드물다고 가정하고 기다려 보는 쪽을 택한 것이다.

범용 OS가 아무 대책을 두지 않는 선택에는 [타조 알고리즘](https://en.wikipedia.org/wiki/Ostrich_algorithm)이라는 이름이 붙어 있다. 발생이 드물고 예방 비용이 크면 무시하는 편이 낫다는 판단이고, 위키백과는 UNIX와 Windows가 이 방식을 쓴다고 적는다.

세 층의 판단 기준은 같다. 데드락이 나는 비용과 그것을 통제하는 비용 중 어느 쪽이 싼가다. 애플리케이션은 통제가 싸서 예방하고, DBMS는 사후 처리가 싸서 탐지하고, 범용 OS는 발생이 드물어 무시한다.

## 참고

- [Deadlock (computer science) — Wikipedia](https://en.wikipedia.org/wiki/Deadlock_(computer_science))
- [System Deadlocks — Coffman, Elphick, Shoshani, ACM Computing Surveys 3(2), 1971](https://dl.acm.org/doi/10.1145/356586.356588)
- [Dining philosophers problem — Wikipedia](https://en.wikipedia.org/wiki/Dining_philosophers_problem)
- [Banker's algorithm — Wikipedia](https://en.wikipedia.org/wiki/Banker%27s_algorithm)
- [Ostrich algorithm — Wikipedia](https://en.wikipedia.org/wiki/Ostrich_algorithm)
- [PostgreSQL: deadlock_timeout](https://www.postgresql.org/docs/current/runtime-config-locks.html)
