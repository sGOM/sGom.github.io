---
title: 자바 직렬화 스트림을 바이트 단위로 뜯어보기
description: 71바이트짜리 직렬화 파일을 바이트별로 해부하고, 필드를 하나도 건드리지 않고 게터만 추가해도 serialVersionUID가 바뀌어 역직렬화가 깨지는 것을 JDK 26에서 재현한다
pubDate: 2026-08-31
category: "Java"
tags: ["파고들기", "Java", "직렬화"]
---

## 전제

[직렬화와 역직렬화 기본개념](/posts/serialization-basics/)에서 자바 네이티브 직렬화가 값 외에 클래스 이름과 필드 이름까지 바이트에 싣는다고 정리했다. 이 글은 그 바이트를 하나씩 갈라 읽고, 클래스가 바뀌었을 때 무엇이 어긋나 역직렬화가 실패하는지를 재현한다.

## 왜 필요한가

운영 중이던 클래스에 게터 하나를 추가하고 배포했더니 예전에 저장해 둔 데이터를 못 읽는다.

```
java.io.InvalidClassException: Member; local class incompatible:
	stream classdesc serialVersionUID = -6345628487835475387,
	local class serialVersionUID = 3368667655942480009
```

필드는 하나도 건드리지 않았다. `serialVersionUID`를 선언한 적도 없다. 그런데 두 값이 다르다고 한다. 이 숫자가 어디서 나오는지 알아야 답이 나온다.

## 동작 원리

직렬화 스트림은 4바이트 헤더로 시작하고, 그 뒤에 객체가 이어진다. 객체 하나는 클래스 서술자(classDesc)와 필드 값 두 부분이다. 클래스 서술자가 클래스 이름과 `serialVersionUID`, 필드 목록을 담고 그 뒤에 값이 온다.

스트림에 나오는 표식과 플래그는 [명세 6.4.2](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/protocol.html)가 정한다.

| 상수 | 값 | 뜻 |
|---|---|---|
| `STREAM_MAGIC` | `0xaced` | 스트림 시작 표식 |
| `TC_NULL` | `0x70` | null 참조 |
| `TC_CLASSDESC` | `0x72` | 클래스 서술자 시작 |
| `TC_OBJECT` | `0x73` | 객체 시작 |
| `TC_STRING` | `0x74` | 문자열 |
| `TC_ENDBLOCKDATA` | `0x78` | 블록 끝 |
| `SC_SERIALIZABLE` | `0x02` | `Serializable` 구현 클래스라는 플래그 |

필드가 적히는 순서는 선언 순서가 아니다. [명세 4.3](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/class.html)이 정한 순서가 따로 있다.

> The descriptors for primitive typed fields are written first sorted by field name followed by descriptors for the object typed fields sorted by field name.

원시 타입 필드를 이름순으로 먼저 쓰고, 그다음 객체 타입 필드를 이름순으로 쓴다.

`serialVersionUID`를 선언하지 않으면 런타임이 계산한다. [명세 4.6](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/class.html)에 따르면 클래스 정의를 바이트 열로 편 뒤 뜬 SHA-1 해시의 앞 8바이트다.

> The serialVersionUID is computed using the signature of a stream of bytes that reflect the class definition. The National Institute of Standards and Technology (NIST) Secure Hash Algorithm (SHA-1) is used to compute a signature for the stream. The first two 32-bit quantities are used to form a 64-bit hash.

이 해시 입력에 들어가는 것이 필드만은 아니다. 클래스 이름과 수정자, 구현한 인터페이스 이름, 필드 목록에 더해 **private이 아닌 생성자와 메서드의 이름과 시그니처까지 들어간다.** 필드를 그대로 두고 public 메서드를 하나 추가하는 것만으로 값이 달라지는 이유다.

## 직접 확인

JDK 26에서 확인했다. 스택트레이스와 컴파일러 경고의 줄 번호는 버전에 따라 달라진다.

```
$ java -version
java version "26.0.1" 2026-04-21
```

아래 각 절은 따로 표기하지 않는 한 바로 다음에 오는 원본 `Member`에서 다시 시작한다. 앞 절에서 더한 게터나 필드는 다음 절로 넘어가지 않는다.

### 71바이트 해부

기본개념 글에서 쓴 것과 같은 클래스다.

```java
public class Member implements Serializable {
    private String name;
    private int age;
    private transient String password;
    // 생성자와 toString 생략
}
```

```
$ od -A d -t x1z member.ser
0000000 ac ed 00 05 73 72 00 06 4d 65 6d 62 65 72 a7 ef  >....sr..Member..<
0000016 cc 82 c9 f7 a2 45 02 00 02 49 00 03 61 67 65 4c  >.....E...I..ageL<
0000032 00 04 6e 61 6d 65 74 00 12 4c 6a 61 76 61 2f 6c  >..namet..Ljava/l<
0000048 61 6e 67 2f 53 74 72 69 6e 67 3b 78 70 00 00 00  >ang/String;xp...<
0000064 21 74 00 03 68 65 6f                             >!t..heo<
0000071
```

바이트별로 갈라 읽으면 이렇다.

| 위치 | 바이트 | 뜻 |
|---|---|---|
| 0–1 | `ac ed` | `STREAM_MAGIC` |
| 2–3 | `00 05` | 스트림 버전 5 |
| 4 | `73` | `TC_OBJECT`, 객체 시작 |
| 5 | `72` | `TC_CLASSDESC`, 클래스 서술자 시작 |
| 6–7 | `00 06` | 클래스 이름 길이 6 |
| 8–13 | `4d 65 6d 62 65 72` | `Member` |
| 14–21 | `a7 ef cc 82 c9 f7 a2 45` | `serialVersionUID` |
| 22 | `02` | `SC_SERIALIZABLE` |
| 23–24 | `00 02` | 필드 개수 2 |
| 25 | `49` | `I`, int |
| 26–30 | `00 03 61 67 65` | 길이 3, `age` |
| 31 | `4c` | `L`, 객체 타입 |
| 32–37 | `00 04 6e 61 6d 65` | 길이 4, `name` |
| 38–40 | `74 00 12` | `TC_STRING`, 길이 18 |
| 41–58 | `4c 6a … 3b` | `Ljava/lang/String;` |
| 59 | `78` | `TC_ENDBLOCKDATA` |
| 60 | `70` | `TC_NULL`, 상위 클래스 서술자 없음 |
| 61–64 | `00 00 00 21` | `age` = 33 |
| 65–70 | `74 00 03 68 65 6f` | `TC_STRING`, 길이 3, `heo` |

읽히는 것이 세 가지다. 필드 개수가 `00 02`이므로 `transient`인 `password`는 목록에서부터 빠졌다. 필드 순서는 선언 순서인 `name`, `age`가 아니라 원시 타입인 `age`가 먼저다. 실제 값은 61번지부터의 10바이트뿐이고 앞의 61바이트는 전부 클래스 메타데이터다.

14번지의 8바이트가 문제의 `serialVersionUID`다. 런타임이 계산한 값과 맞는지 확인해 본다.

```java
ObjectStreamClass desc = ObjectStreamClass.lookup(Member.class);
System.out.printf("serialVersionUID = 0x%016x%n", desc.getSerialVersionUID());
```

```
serialVersionUID = 0xa7efcc82c9f7a245
```

스트림에 박힌 `a7 ef cc 82 c9 f7 a2 45`와 같다. 부호 있는 long으로 읽으면 `-6345628487835475387`이고, 이것이 예외 메시지의 `stream classdesc serialVersionUID` 값이다.

### 게터만 추가하면 깨진다

필드는 그대로 두고 게터 한 줄을 넣는다.

```java
public String getName() { return name; }
```

```
serialVersionUID = 0x2ebfe96296cca089
```

값이 바뀌었다. 이 클래스로 예전 파일을 읽으면 실패한다.

```
Exception in thread "main" java.io.InvalidClassException: Member; local class incompatible: stream classdesc serialVersionUID = -6345628487835475387, local class serialVersionUID = 3368667655942480009
	at java.base/java.io.ObjectStreamClass.initNonProxy(ObjectStreamClass.java:496)
	at java.base/java.io.ObjectInputStream.readNonProxyDesc(ObjectInputStream.java:1927)
	at java.base/java.io.ObjectInputStream.readClassDesc(ObjectInputStream.java:1785)
	at java.base/java.io.ObjectInputStream.readOrdinaryObject(ObjectInputStream.java:2101)
```

`0x2ebfe96296cca089`를 부호 있는 long으로 읽으면 `3368667655942480009`다. 데이터 모양은 그대로인데 신원 값만 어긋나서 스트림 전체가 거부된다.

컴파일러는 이 상황을 미리 알려준다.

```
$ javac -Xlint:serial Member.java
Member.java:3: warning: [serial] serializable class Member has no definition of serialVersionUID
public class Member implements Serializable {
       ^
1 warning
```

### 값을 고정하면 필드 추가가 통과한다

`serialVersionUID`를 직접 선언하면 런타임이 계산하지 않고 그 값을 쓴다.

```java
public class Member implements Serializable {
    private static final long serialVersionUID = 1L;
    // 이하 동일
}
```

이 클래스로 다시 쓰면 14번지의 8바이트가 `00 00 00 00 00 00 00 01`로 바뀐다.

```
0000000 ac ed 00 05 73 72 00 06 4d 65 6d 62 65 72 00 00  >....sr..Member..<
0000016 00 00 00 00 00 01 02 00 02 49 00 03 61 67 65 4c  >.........I..ageL<
```

여기서 필드를 하나 추가한다. `serialVersionUID` 선언은 그대로 둔다.

```java
private String email;   // 새 필드
```

방금 `1L`로 쓴 파일을 이 클래스로 읽으면 통과한다.

```
Member{name=heo, age=33, email=null, password=null}
```

스트림에 없는 `email`은 예외 없이 기본값 `null`로 채워진다. 맨 앞의 71바이트 파일은 여전히 못 읽는다. 그 파일에는 계산된 UID가 박혀 있고 지금 클래스는 `1L`이라 값이 어긋난다. UID를 고정하는 것은 앞으로 쓸 데이터를 지키는 조치이지 이미 쓴 데이터를 되살리는 조치가 아니다.

### 역직렬화는 그 클래스의 생성자를 거치지 않는다

생성자에 출력과 검증을 넣고 쓰기와 읽기를 각각 돌린다.

```java
public Member(String name, int age, String password) {
    System.out.println("constructor called");
    if (age < 0) throw new IllegalArgumentException("age must be >= 0");
    this.name = name;
    this.age = age;
    this.password = password;
}
```

```
--- 쓰기 ---
constructor called
written: 71 bytes
--- 읽기 ---
Member{name=heo, age=33, password=null}
```

읽기 쪽에는 `constructor called`가 찍히지 않았다. 역직렬화는 객체를 할당한 뒤 필드에 값을 직접 밀어 넣는다. 생성자에 둔 `age < 0` 검사도 같이 건너뛴다.

생성자가 하나도 안 도는 것은 아니다. [명세 3.1](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/input.html)은 직렬화되지 않는 첫 상위 클래스의 무인자 생성자는 실행한다고 정한다. `Member`에게는 그것이 `Object`라 눈에 띄지 않을 뿐이다. 직렬화되지 않는 상위 클래스를 두면 드러난다.

```java
class Base {                       // Serializable 아님
    int seq;
    Base() {
        System.out.println("Base() called");
        this.seq = 99;
    }
}

public class Sub extends Base implements Serializable {
    private static final long serialVersionUID = 1L;
    private String name;

    Sub(String name) {
        System.out.println("Sub() called");
        this.name = name;
        this.seq = 7;               // Base의 필드
    }

    // toString 생략
}
```

```
--- 쓰기 ---
Base() called
Sub() called
--- 읽기 ---
Base() called
Sub{name=heo, seq=99}
```

읽을 때 `Base()`는 돌고 `Sub()`는 돌지 않는다. `seq`는 `Base`의 필드라 스트림에 실리지 않았고, 그래서 쓸 때 넣은 7이 아니라 `Base()` 생성자가 채운 99가 남는다.

## 경계 조건

`serialVersionUID`를 고정해도 모든 변경이 통과하지는 않는다. 위에서 확인한 필드 추가는 넘어가지만, [명세 5.6.1절](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/version.html)은 원시 타입 필드의 선언 타입을 바꾸는 것을 비호환 변경으로 못박는다. 스트림에 적힌 타입과 필드의 타입이 다르면 값을 옮길 방법이 없기 때문이다. 필드 삭제도 비호환 쪽에 들어간다. 지운 필드는 예전 버전 클래스가 읽을 때 기본값으로 채워지는데, 그 값이 정상 범위 밖이면 역직렬화 자체는 성공하고 나중에 엉뚱한 곳에서 깨진다.

생성자를 건너뛴다는 점은 그 자체로 더 큰 문제가 된다. 생성자에서 지키던 불변식이 역직렬화 경로에는 걸리지 않으므로, 정상 코드로는 만들 수 없는 상태의 객체가 바이트 열만으로 세워질 수 있다. 클래스패스에 있는 클래스라면 무엇이든 역직렬화 대상이 될 수 있다는 점까지 겹치면서, 신뢰할 수 없는 입력을 `readObject`에 넘기는 것 자체가 취약점이다. JDK는 [`ObjectInputFilter`](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/ObjectInputFilter.html)로 역직렬화 대상 클래스와 배열 길이를 걸러내는 장치를 두었고, `jdk.serialFilter` 시스템 속성으로 JVM 전체에 걸 수 있다.

## 언제 쓰고 언제 안 쓰나

`Serializable`을 붙이는 순간 그 클래스의 필드 이름과 타입, private이 아닌 메서드 시그니처가 외부 데이터 형식의 일부가 된다. 리팩터링이 곧 형식 변경이 된다는 뜻이다. 오래 남길 데이터라면 JSON이나 프로토콜 버퍼처럼 클래스와 분리된 형식이 낫다.

`Serializable`을 써야 한다면 최소한 두 가지는 지킨다. `serialVersionUID`를 직접 선언해 계산에 맡기지 않고, 신뢰할 수 없는 입력에는 `ObjectInputFilter`를 건다. [`Serializable` API 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/Serializable.html)의 경고는 그보다 단호하다.

> Deserialization of untrusted data is inherently dangerous and should be avoided.

## 참고

- [Java Object Serialization Specification](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/index.html)
- [명세 6.4.2 Terminal Symbols and Constants](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/protocol.html)
- [명세 4.6 Stream Unique Identifiers](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/class.html)
- [명세 3.1 The ObjectInputStream Class](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/input.html)
- [명세 5.6 Type Changes Affecting Serialization](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/version.html)
- [`java.io.Serializable` API 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/Serializable.html)
- [`java.io.ObjectInputFilter` API 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/ObjectInputFilter.html)
