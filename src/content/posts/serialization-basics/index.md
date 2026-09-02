---
title: 직렬화와 역직렬화 기본개념 — 객체를 바이트 열로 펴는 일
description: 메모리 위의 객체를 파일과 소켓이 받을 수 있는 바이트 열로 바꾸는 직렬화가 왜 필요한지, 자바 네이티브 직렬화와 JSON, 프로토콜 버퍼가 무엇을 다르게 하는지 정리한다
pubDate: 2026-08-31
category: "Java"
tags: ["기본개념", "Java", "직렬화"]
---

## 왜 필요한가

객체는 힙에 흩어진 참조 그래프다. `Member` 인스턴스가 가진 `name`은 문자열 자체가 아니라 문자열 객체가 놓인 주소이고, 그 주소는 그 JVM의 그 실행 안에서만 뜻이 있다. 프로세스가 끝나면 사라지고, 다른 장비로 주소만 보내면 아무것도 가리키지 못한다.

파일과 소켓이 받는 것은 순서가 있는 바이트 열뿐이다. 그래서 주소로 이어진 그래프를 한 줄로 펴야 하고, 받는 쪽은 그 바이트 열로 그래프를 다시 세워야 한다. 앞이 직렬화, 뒤가 역직렬화다.

## 용어 정리

| 용어 | 뜻 |
|---|---|
| 직렬화 (serialization) | 메모리의 객체를 바이트 열로 바꾼다 |
| 역직렬화 (deserialization) | 바이트 열을 읽어 객체를 다시 세운다 |
| [마샬링 (marshalling)](https://en.wikipedia.org/wiki/Marshalling_(computer_science)) | 직렬화를 한 단계로 포함하는 더 넓은 말. 살아 있는 객체를 다른 프로세스로 옮기는 일 전체를 가리키고, 자바 RMI처럼 값과 함께 클래스를 어디서 받아올지(코드베이스)까지 기록하는 경우가 여기 들어간다 |
| 인코딩 (encoding) | 표현을 바꾸는 일 전반을 가리키는 말. UTF-8 같은 문자 인코딩은 문자를 바이트로 바꾸는 일이라 객체 그래프와는 다루는 층이 다르다 |

직렬화한 바이트를 파일이나 DB에 남기면 영속화가 되지만, 두 낱말이 같은 뜻은 아니다. 직렬화는 형식을 바꾸는 일이고 영속화는 그 결과를 어디에 얼마나 오래 두느냐다.

## 핵심 정리

| | 자바 네이티브 직렬화 | JSON | 프로토콜 버퍼 |
|---|---|---|---|
| 형식 | 바이너리 | 텍스트 | 바이너리 |
| 사람이 읽나 | 못 읽는다 | 읽는다 | 못 읽는다 |
| 스키마 | 클래스 정의가 곧 스키마다 | 없어도 된다 | `.proto` 파일이 있어야 한다 |
| 클래스 이름이 바이트에 들어가나 | 들어간다 | 안 들어간다 | 안 들어간다 |
| 필드 이름이 바이트에 들어가나 | 들어간다 | 키로 들어간다 | 안 들어간다. [필드 번호만 들어간다](https://protobuf.dev/programming-guides/encoding/) |
| 다른 언어에서 읽나 | 사실상 자바끼리만 | 대부분의 언어에서 | 지원 언어의 생성 코드로 |

세 형식이 갈리는 지점은 스키마를 어디에 두느냐다. 자바 네이티브는 스키마를 바이트 안에 같이 넣고, JSON은 키 이름만 넣고 타입은 안 넣고, 프로토콜 버퍼는 `.proto`로 양쪽이 미리 합의한 뒤 바이트에서는 번호만 쓴다.

## 예시

자바 네이티브 직렬화는 `Serializable`을 구현하면 쓸 수 있다.

```java
public class Member implements Serializable {
    private String name;
    private int age;
    private transient String password;

    public Member(String name, int age, String password) {
        this.name = name;
        this.age = age;
        this.password = password;
    }

    @Override
    public String toString() {
        return "Member{name=" + name + ", age=" + age + ", password=" + password + "}";
    }
}
```

```java
try (ObjectOutputStream out = new ObjectOutputStream(new FileOutputStream("member.ser"))) {
    out.writeObject(new Member("heo", 33, "1q2w3e4r"));
}
```

71바이트짜리 파일이 나온다. 바이트를 그대로 떠 보면 이렇다. 아래 실행 결과는 모두 JDK 26에서 얻은 것이고, 스택트레이스의 줄 번호는 버전에 따라 달라진다.

```
$ od -A d -t x1z member.ser
0000000 ac ed 00 05 73 72 00 06 4d 65 6d 62 65 72 a7 ef  >....sr..Member..<
0000016 cc 82 c9 f7 a2 45 02 00 02 49 00 03 61 67 65 4c  >.....E...I..ageL<
0000032 00 04 6e 61 6d 65 74 00 12 4c 6a 61 76 61 2f 6c  >..namet..Ljava/l<
0000048 61 6e 67 2f 53 74 72 69 6e 67 3b 78 70 00 00 00  >ang/String;xp...<
0000064 21 74 00 03 68 65 6f                             >!t..heo<
0000071
```

오른쪽 텍스트 열에 `Member`, `age`, `name`, `Ljava/lang/String;`, `heo`가 보인다. 값만 담긴 게 아니라 클래스 이름과 필드 이름, 필드 타입까지 같이 들어 있다.

같은 객체를 JSON으로 쓰면 값과 키만 남는다.

```json
{"name":"heo","age":33}
```

23바이트다. 다만 클래스 서술자는 스트림당 한 번만 쓰인다. 같은 스트림에 하나를 더 써 보면 알 수 있다.

```java
out.writeObject(new Member("heo", 33, "x"));
out.writeObject(new Member("kim", 41, "y"));
```

파일 전체가 87바이트다. 뒷부분만 보면 두 번째 객체가 16바이트로 끝난다.

```
0000064 21 74 00 03 68 65 6f 73 71 00 7e 00 00 00 00 00  >!t..heosq.~.....<
0000080 29 74 00 03 6b 69 6d                             >)t..kim<
0000087
```

`73` 다음에 클래스 서술자 대신 `71 00 7e 00 00`이 왔다. 앞에서 쓴 서술자를 가리키는 역참조다. 그 뒤는 값 `00 00 00 29`(41)와 `kim`뿐이다. 객체가 늘수록 메타데이터 비율은 떨어진다.

## 혼동하기 쉬운 것

**직렬화는 암호화가 아니다.** 위 바이트 열에 `heo`가 평문 그대로 있고 클래스 이름 `Member`도 그대로 있다. 바이너리라서 텍스트 편집기로 열면 깨져 보일 뿐, 내용을 가리지는 않는다. 감춰야 할 값이면 직렬화와 별개로 암호화해야 한다.

`transient`는 보안 장치가 아니라 제외 표시다. 위 스트림에서 필드 개수가 `00 02`로 적혀 있고 `password`는 목록에도 값에도 없다. 값이 가려지는 게 아니라 아예 사라지므로, 되읽으면 타입 기본값이 들어온다.

```java
try (ObjectInputStream in = new ObjectInputStream(new FileInputStream("member.ser"))) {
    System.out.println(in.readObject());
}
```

```
Member{name=heo, age=33, password=null}
```

**직렬화가 되는지는 클래스 하나가 아니라 그래프 전체가 정한다.** 쓰는 시점에 실제로 참조하고 있는 객체 중 하나라도 `Serializable`이 아니면 그 자리에서 실패한다.

```java
import java.io.*;

class Coach {              // Serializable 아님
    String name = "kim";
}

public class Team implements Serializable {
    private String title = "A팀";
    private Coach coach = new Coach();

    public static void main(String[] args) throws Exception {
        try (ObjectOutputStream out = new ObjectOutputStream(new ByteArrayOutputStream())) {
            out.writeObject(new Team());
        }
    }
}
```

```
Exception in thread "main" java.io.NotSerializableException: Coach
	at java.base/java.io.ObjectOutputStream.writeObject0(ObjectOutputStream.java:1087)
	at java.base/java.io.ObjectOutputStream.defaultWriteFields(ObjectOutputStream.java:1453)
	at java.base/java.io.ObjectOutputStream.writeSerialData(ObjectOutputStream.java:1410)
	at java.base/java.io.ObjectOutputStream.writeOrdinaryObject(ObjectOutputStream.java:1319)
	at java.base/java.io.ObjectOutputStream.writeObject0(ObjectOutputStream.java:1081)
	at java.base/java.io.ObjectOutputStream.writeObject(ObjectOutputStream.java:327)
	at Team.main(Team.java:13)
```

`Team`에는 아무 문제가 없고 실패한 것은 `Coach`다. 같은 코드에서 `coach`를 `null`로 두거나 `transient`로 선언하면 예외 없이 통과한다. 판정하는 것은 선언 타입이 아니라 쓰기 시점에 매달려 있는 값이다.

## 언제 어떤 것을 쓰나

| 상황 | 형식 |
|---|---|
| 다른 언어와 주고받고, 눈으로 열어 확인할 일이 있다 | JSON |
| 양쪽이 스키마를 미리 합의할 수 있고 필드 이름 반복을 줄이고 싶다 | 프로토콜 버퍼 |

자바 프로세스끼리만 주고받는 경우에도 네이티브 직렬화는 권하지 않는다. 이유는 두 가지다. 클래스 정의가 곧 형식이라 `serialVersionUID`를 직접 선언해 두지 않았다면 필드를 건드리지 않고 public 메서드를 하나 추가하는 것만으로 예전에 쓴 데이터를 못 읽게 되고, 신뢰할 수 없는 바이트를 역직렬화하는 것 자체가 위험하다. `Serializable`의 API 문서도 [신뢰할 수 없는 데이터의 역직렬화는 본질적으로 위험하므로 피해야 한다](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/Serializable.html)고 경고한다.

## 더 깊이

위 71바이트가 각각 무엇이고, 게터 하나를 추가한 것만으로 왜 역직렬화가 깨지는지는 [자바 직렬화 스트림을 바이트 단위로 뜯어보기](/posts/serialization-deep-dive/)에서 재현한다.

## 참고

- [Java Object Serialization Specification](https://docs.oracle.com/en/java/javase/26/docs/specs/serialization/index.html)
- [`java.io.Serializable` API 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/Serializable.html)
- [Protocol Buffers Encoding](https://protobuf.dev/programming-guides/encoding/)
