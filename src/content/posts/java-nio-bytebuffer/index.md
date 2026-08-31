---
title: ByteBuffer의 flip은 왜 필요한가
description: 하나의 버퍼가 읽기와 쓰기를 겸하는 방식과, heap 버퍼와 direct 버퍼의 차이
pubDate: 2026-08-25
category: "JAVA"
tags: ["파고들기", "Java", "IO", "버퍼"]
---

## 전제

버퍼가 무엇을 줄이는지는 [자바 I/O 버퍼](/posts/io-buffer-basics/)에서 다뤘다. 이 글은 `java.nio`의 `ByteBuffer`가 그 버퍼를 어떤 상태로 표현하는지 본다.

## 왜 필요한가

`java.io`의 스트림에는 `flip` 같은 것이 없다. `BufferedOutputStream`은 쓰기만 하고 `BufferedInputStream`은 읽기만 하니, 버퍼 안에서 어디까지가 유효한 데이터인지 각자 알아서 관리하면 된다.

`ByteBuffer`는 하나의 객체로 둘 다 한다. 채널에서 읽어와 담는 것도 이 버퍼이고, 담긴 것을 꺼내 쓰는 것도 같은 버퍼다. 그래서 "지금 이 버퍼가 어디까지 채워졌고 어디까지 읽었는가"를 밖에서 볼 수 있어야 하고, 담는 모드와 꺼내는 모드를 전환하는 동작이 필요하다.

## 구조

`ByteBuffer`는 정수 네 개로 상태를 표현하고, 데이터는 그와 별도로 `byte[]`나 힙 밖 메모리에 둔다.

| 값 | 뜻 |
|---|---|
| `capacity` | 버퍼가 담을 수 있는 총 크기. 만든 뒤 바뀌지 않는다 |
| `limit` | 읽거나 쓸 수 있는 경계. 이 위치는 접근할 수 없다 |
| `position` | 다음에 읽거나 쓸 위치 |
| `mark` | `reset()`으로 돌아올 지점. 지정하지 않으면 -1 |

[`Buffer` 클래스 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/nio/Buffer.html)는 네 값의 관계를 불변식으로 못박는다.

> The following invariant holds for the mark, position, limit, and capacity values:
> `0 <= mark <= position <= limit <= capacity`

`remaining()`은 `limit - position`이다. 쓰는 중이라면 앞으로 더 담을 수 있는 양이고, 읽는 중이라면 아직 안 읽은 양이다. 같은 계산식이 모드에 따라 다른 뜻이 되는 것이 `ByteBuffer`를 헷갈리게 만드는 지점이다.

## 동작 원리

`flip`이 하는 일은 세 줄이다.

```java
public Buffer flip() {
    limit = position;
    position = 0;
    mark = -1;
    return this;
}
```

쓰기를 끝낸 시점의 `position`은 곧 "여기까지 채웠다"는 표시다. 그 값을 `limit`으로 옮기면 읽을 수 있는 경계가 되고, `position`을 0으로 되돌리면 처음부터 읽는다. 데이터는 한 바이트도 움직이지 않는다. 경계 값 몇 개를 바꿔 같은 배열을 다르게 보는 것이다.

`clear`도 데이터를 지우지 않는다.

```java
public Buffer clear() {
    position = 0;
    limit = capacity;
    mark = -1;
    return this;
}
```

이름과 달리 배열은 그대로 두고 경계만 초기 상태로 되돌린다. 이후 `put`이 앞에서부터 덮어쓰기 때문에 결과적으로 비운 것처럼 동작할 뿐이다.

`compact`는 다르다. 아직 안 읽은 부분을 배열 앞으로 옮기고 `position`을 그 뒤에 놓는다. 다 읽지 못한 채로 다음 데이터를 더 받아야 하는 경우에 쓴다.

## 직접 확인

각 연산 뒤 세 값을 찍었다. JDK 26이다.

```java
ByteBuffer b = ByteBuffer.allocate(8);      // show("allocate(8)", b)
b.put((byte) 'a').put((byte) 'b').put((byte) 'c');
b.flip();
b.get();
b.compact();
b.clear();
System.out.println("get(0) after clear -> '" + (char) b.get(0) + "'");
```

`show`는 연산마다 `position`, `limit`, `capacity`, `remaining()`을 찍는 출력 함수다.

```
allocate(8)    pos=0   lim=8   cap=8   remaining=8
put a,b,c      pos=3   lim=8   cap=8   remaining=5
flip()         pos=0   lim=3   cap=8   remaining=3
get() -> 'a'
get()          pos=1   lim=3   cap=8   remaining=2
compact()      pos=2   lim=8   cap=8   remaining=6
clear()        pos=0   lim=8   cap=8   remaining=8
get(0) after clear -> 'b'
```

`compact()` 다음 `position`이 2인 것은 안 읽은 `b`, `c`를 0번과 1번으로 옮겼기 때문이다. `clear()` 뒤에 `get(0)`이 `b`를 돌려주는 것은 배열이 지워지지 않았다는 증거다. `get(0)`은 `position`을 보지 않는 절대 위치 접근이라, `position`이 0으로 돌아간 것과 무관하게 배열에 남은 값을 그대로 읽는다.

`flip`을 빼먹으면 조용히 잘못된 값이 나온다.

```java
ByteBuffer b = ByteBuffer.allocate(8);
b.put((byte) 'a').put((byte) 'b').put((byte) 'c');
System.out.printf("no flip : pos=%d lim=%d, get() -> %d%n", b.position(), b.limit(), b.get());

b.clear();
b.put((byte) 'a').put((byte) 'b').put((byte) 'c');
b.flip();
System.out.printf("flip    : pos=%d lim=%d, get() -> %d ('%c')%n", b.position(), b.limit(), b.get(0), (char) b.get());
```

```
no flip : pos=3 lim=8, get() -> 0
flip    : pos=0 lim=3, get() -> 97 ('a')
```

`position`이 3에 있으니 방금 쓴 데이터가 아니라 그 뒤의 빈 자리를 읽는다. `get()`은 `position`이 `limit`에 닿았을 때 `BufferUnderflowException`을 던지는데, `flip`을 안 했으니 `limit`이 `capacity`인 8이다. 버퍼를 끝까지 채웠을 때만 예외가 나므로 테스트 데이터가 버퍼보다 작으면 이 실수가 통과한다.

## 대안과 트레이드오프

`allocate`와 `allocateDirect`는 배열이 어디에 놓이는지가 다르다.

```java
ByteBuffer h = ByteBuffer.allocate(8);
ByteBuffer d = ByteBuffer.allocateDirect(8);
```

```
allocate               isDirect=false  hasArray=true
allocateDirect         isDirect=true   hasArray=false
```

heap 버퍼는 자바 힙 안의 `byte[]`다. GC가 객체를 옮길 수 있으므로, 커널에 주소를 넘기는 채널 연산에서는 JDK가 임시 direct 버퍼로 복사한 뒤 넘긴다. direct 버퍼는 힙 밖에 잡혀 주소가 고정돼 있어 그 복사가 없다.

## 성능

64KB 버퍼로 4MB 파일을 4000번 읽었다. 파일을 열고 끝까지 읽는 것을 한 회로 세고, 예열로 각각 한 번씩 돌린 뒤 측정했다. JDK 26, Windows 11.

```java
static long read(Path p, ByteBuffer buf) throws IOException {
    long t = System.nanoTime();
    for (int r = 0; r < 4000; r++) {
        try (FileChannel ch = FileChannel.open(p, StandardOpenOption.READ)) {
            buf.clear();
            while (ch.read(buf) > 0) buf.clear();
        }
    }
    return (System.nanoTime() - t) / 1_000_000;
}
```

```
heap   : 5967 ms      direct : 5397 ms      (1회차)
heap   : 5832 ms      direct : 4816 ms      (2회차)
```

두 번 모두 direct가 빨랐지만 폭이 9.6%와 17.4%로 벌어져, 이 수치 자체를 단정하기에는 반복이 적다. 복사 한 번이 사라지는 것치고 차이가 작은 것은, 이 실험에서 파일이 이미 OS 페이지 캐시에 있어 I/O가 싸고 채널 열기와 시스템 호출이 시간을 더 많이 쓰기 때문으로 보인다.

할당 비용은 방향이 반대다. 64KB 버퍼를 2만 번 할당했다.

```
allocate(64KB) x 20000       : 147 ms
allocateDirect(64KB) x 20000 : 779 ms
```

direct 할당이 5.3배 느리다. 네이티브 메모리를 확보하고 0으로 채우는 비용이 들기 때문이다. heap 버퍼는 스레드마다 할당된 힙 영역에서 잘라 쓰므로 훨씬 싸다.

해제도 다르다. direct 버퍼의 메모리는 GC가 직접 회수하지 않고 `Cleaner`가 처리하며, 그 시점이 GC에 물려 있어 예측하기 어렵다.

## 언제 쓰고 언제 안 쓰나

direct 버퍼는 오래 살려 두고 재사용할 때 값어치를 한다. 소켓이나 파일 채널에 붙여 두고 계속 쓰는 버퍼가 그런 경우다. 요청마다 만들고 버리면 할당 비용이 전송에서 아낀 시간을 먹는다.

작은 데이터를 다루거나 `byte[]`로 넘겨야 하는 코드가 이어진다면 heap 버퍼를 쓴다. direct 버퍼는 `hasArray()`가 `false`라 `array()`를 부르면 `UnsupportedOperationException`이 난다.

## 참고

- [`Buffer` (Java SE 26 API)](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/nio/Buffer.html)
- [`ByteBuffer` (Java SE 26 API)](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/nio/ByteBuffer.html)
- [`Buffer.java` (OpenJDK 소스)](https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/nio/Buffer.java)
