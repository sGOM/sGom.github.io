---
title: Kotlin과 Java의 차이는 컴파일하면 어디에 남는가
description: null 안전성, 기본 인자, data class, object를 Java 등가 코드와 각각 컴파일해 javap로 대조한다
pubDate: 2026-08-24
category: "Kotlin"
tags: ["파고들기", "Kotlin", "Java", "바이트코드"]
---

## 전제

Kotlin 프로퍼티 하나가 backing field, getter, setter로 갈라지는 규칙은 [Kotlin 프로퍼티가 여러 JVM 요소로 컴파일되는 이유](/posts/kotlin-annotation-use-site-target-deep-dive/)에서 다뤘다. 이 글은 그 위에서 문법 단위 네 가지를 Java 등가 코드와 나란히 컴파일해 비교한다.

## 왜 필요한가

Kotlin과 Java는 같은 형식의 클래스 파일로 컴파일되고 서로 호출된다. 그런데 Kotlin에는 Java 문법으로 그대로 옮길 수 없는 것이 있다. `String`과 `String?`의 구분, 파라미터 기본값, `data class`, `object`가 그렇다.

JVM 스펙에는 이 중 어느 것도 없다. 그러면 컴파일러는 이것들을 무엇으로 바꾸는가. 그리고 그 결과물을 Java 쪽에서 부르면 어떻게 보이는가.

문법 비교로는 여기까지 답이 안 나온다. 양쪽을 실제로 컴파일해 `javap`로 대조한다.

## 검증 환경

| 항목 | 값 |
|---|---|
| Kotlin | 2.2.20 |
| JDK | 26.0.1 |
| Kotlin 컴파일 | `kotlinc -jvm-target 17` |
| Java 컴파일 | `javac --release 17` |

바이트코드 타깃을 양쪽 17로 맞춘 이유가 있다. `kotlinc`의 기본 `-jvm-target`은 1.8이고 이 JDK의 `javac` 기본값은 26이다. 그대로 두면 문자열 결합이 한쪽은 `StringBuilder`, 다른 쪽은 `invokedynamic`으로 나와 언어 차이가 아닌 것이 차이처럼 보인다.

## 동작 원리

| Kotlin 문법 | 컴파일 결과 |
|---|---|
| non-null 파라미터 | `@NotNull` 애노테이션 + 진입부에 `Intrinsics.checkNotNullParameter` 호출. Java에서 접근 가능한 함수에만 붙는다 |
| 파라미터 기본값 | 전체 파라미터를 받는 메서드 하나 + 비트마스크로 기본값을 채우는 `이름$default` 정적 메서드 |
| `data class` | `componentN`, `copy`, `equals`, `hashCode`, `toString`을 컴파일 시점에 코드로 전개 |
| `object` | `INSTANCE` 정적 필드를 가진 클래스, 생성자는 private |
| `companion object` | 바깥 클래스의 `Companion` 정적 필드 + `바깥클래스$Companion` 중첩 클래스 |

쓰임새는 넷 다 Java로 흉내 낼 수 있다. 갈리는 것은 컴파일 결과다. `object`는 손으로 쓴 싱글턴과 같은 모양이 되고, `data class`에 대응하는 Java 16의 `record`는 목적만 같고 결과물이 다르다. 나머지 둘은 Kotlin 컴파일러가 없는 것을 만들어 내므로 Java 호출부에서 모양이 드러난다.

## 직접 확인

### null 안전성

같은 일을 하는 메서드를 양쪽에 하나씩 둔다.

```kotlin
class Nullability {
    fun accept(name: String): Int = name.length
    fun acceptNullable(name: String?): Int = name?.length ?: 0
}
```

```java
class NullabilityJ {
    int accept(String name) { return name.length(); }
}
```

`javap -v -p`로 Kotlin 쪽 `accept`를 본다.

```
  public final int accept(java.lang.String);
    descriptor: (Ljava/lang/String;)I
    flags: (0x0011) ACC_PUBLIC, ACC_FINAL
    Code:
      stack=2, locals=2, args_size=2
         0: aload_1
         1: ldc           #15                 // String name
         3: invokestatic  #21                 // Method kotlin/jvm/internal/Intrinsics.checkNotNullParameter:(Ljava/lang/Object;Ljava/lang/String;)V
         6: aload_1
         7: invokevirtual #27                 // Method java/lang/String.length:()I
        10: ireturn
    // 생략
    RuntimeInvisibleParameterAnnotations:
      parameter 0:
        0: #13()
          org.jetbrains.annotations.NotNull
```

두 가지가 붙었다. 파라미터에 `@NotNull`이 달렸고, 메서드 본문 맨 앞에서 `Intrinsics.checkNotNullParameter`를 부른다. 상수 풀에서 꺼낸 파라미터 이름 `name`은 예외 메시지에 들어간다.

Java 쪽에는 아무것도 없다.

```
  int accept(java.lang.String);
    descriptor: (Ljava/lang/String;)I
    flags: (0x0000)
    Code:
      stack=1, locals=2, args_size=2
         0: aload_1
         1: invokevirtual #7                  // Method java/lang/String.length:()I
         4: ireturn
```

`javap -v`에서 `RuntimeInvisibleParameterAnnotations` 항목 자체가 나오지 않는다.

`String?`을 받는 쪽에는 검사가 없다. `?.`는 분기로 컴파일된다.

```
  public final int acceptNullable(java.lang.String);
    descriptor: (Ljava/lang/String;)I
    flags: (0x0011) ACC_PUBLIC, ACC_FINAL
    Code:
      stack=2, locals=2, args_size=2
         0: aload_1
         1: dup
         2: ifnull        11
         5: invokevirtual #27                 // Method java/lang/String.length:()I
         8: goto          13
        11: pop
        12: iconst_0
        13: ireturn
    // 생략
    RuntimeInvisibleParameterAnnotations:
      parameter 0:
        0: #30()
          org.jetbrains.annotations.Nullable
```

애노테이션은 `@Nullable`로 붙지만 `Intrinsics` 호출은 없다. null 검사 비용을 무는 것은 non-null 쪽이고, nullable 쪽은 코드에 쓴 `?.` 만큼만 분기한다.

검사가 모든 non-null 파라미터에 붙지는 않는다. 가시성을 바꿔 가며 확인한다.

```kotlin
class Visibility {
    fun pub(name: String): Int = name.length
    private fun priv(name: String): Int = name.length
    internal fun inter(name: String): Int = name.length
    fun callAll(n: String) = priv(n) + inter(n)
}
```

`callAll`은 `priv`와 `inter`가 미사용 경고를 내지 않게 두었다.

`javap -v -p` 출력에서 메서드 세 개만 뽑고, 줄 번호표·지역 변수표와 `descriptor`·`stack` 줄을 덜어 냈다.

```
  public final int pub(java.lang.String);
    flags: (0x0011) ACC_PUBLIC, ACC_FINAL
    Code:
         0: aload_1
         1: ldc           #15                 // String name
         3: invokestatic  #21                 // Method kotlin/jvm/internal/Intrinsics.checkNotNullParameter:(Ljava/lang/Object;Ljava/lang/String;)V
         6: aload_1
         7: invokevirtual #27                 // Method java/lang/String.length:()I
        10: ireturn
    RuntimeInvisibleParameterAnnotations:
      parameter 0:
        0: #13()
          org.jetbrains.annotations.NotNull

  private final int priv(java.lang.String);
    flags: (0x0012) ACC_PRIVATE, ACC_FINAL
    Code:
         0: aload_1
         1: invokevirtual #27                 // Method java/lang/String.length:()I
         4: ireturn

  public final int inter$main(java.lang.String);
    flags: (0x0011) ACC_PUBLIC, ACC_FINAL
    Code:
         0: aload_1
         1: ldc           #15                 // String name
         3: invokestatic  #21                 // Method kotlin/jvm/internal/Intrinsics.checkNotNullParameter:(Ljava/lang/Object;Ljava/lang/String;)V
         6: aload_1
         7: invokevirtual #27                 // Method java/lang/String.length:()I
        10: ireturn
    RuntimeInvisibleParameterAnnotations:
      parameter 0:
        0: #13()
          org.jetbrains.annotations.NotNull
```

`private`에는 검사도 `@NotNull`도 없고, `internal`에는 둘 다 있다. `internal`은 JVM에서 public 메서드로 컴파일되므로 Java 쪽에서 부를 수 있고, 그래서 검사가 필요하다. `private`은 바깥에서 도달할 방법이 없으니 검사도 생략된다.

이름이 `inter$main`으로 바뀐 것은 별개 조치다. 접미사 `main`은 모듈 이름이다. [공식 문서](https://kotlinlang.org/docs/java-to-kotlin-interop.html)는 이 변형이 모듈 간 우연한 오버라이드를 막고 같은 시그니처의 오버로드를 허용하기 위한 것이라고 적는다. 호출 자체를 막지는 않는다.

### 파라미터 기본값

Kotlin의 기본값과, 그것을 Java로 흉내 낸 오버로드 체인을 나란히 둔다.

```kotlin
class Greeter {
    fun greet(name: String, greeting: String = "Hello", mark: String = "!"): String =
        "$greeting, $name$mark"
}
```

```java
class GreeterJ {
    String greet(String name) { return greet(name, "Hello"); }
    String greet(String name, String greeting) { return greet(name, greeting, "!"); }
    String greet(String name, String greeting, String mark) { return greeting + ", " + name + mark; }
}
```

`javap -p`로 메서드 목록만 본다.

```
public final class Greeter {
  public Greeter();
  public final java.lang.String greet(java.lang.String, java.lang.String, java.lang.String);
  public static java.lang.String greet$default(Greeter, java.lang.String, java.lang.String, java.lang.String, int, java.lang.Object);
}
```

```
class GreeterJ {
  GreeterJ();
  java.lang.String greet(java.lang.String);
  java.lang.String greet(java.lang.String, java.lang.String);
  java.lang.String greet(java.lang.String, java.lang.String, java.lang.String);
}
```

Java는 오버로드 세 개, Kotlin은 전체 파라미터를 받는 메서드 하나에 `greet$default` 하나다. `$default`는 파라미터를 두 개 더 받는다. `int`는 어느 인자가 생략됐는지 담은 비트마스크다. `Object`는 super 호출을 구분하는 마커로, 일반 호출에서는 항상 `null`이 들어간다.

`greet$default` 본문이 마스크를 어떻게 쓰는지 `javap -c`로 본다.

```
  public static java.lang.String greet$default(Greeter, java.lang.String, java.lang.String, java.lang.String, int, java.lang.Object);
    Code:
         0: iload         4
         2: iconst_2
         3: iand
         4: ifeq          10
         7: ldc           #41                 // String Hello
         9: astore_2
        10: iload         4
        12: iconst_4
        13: iand
        14: ifeq          20
        17: ldc           #43                 // String !
        19: astore_3
        20: aload_0
        21: aload_1
        22: aload_2
        23: aload_3
        24: invokevirtual #45                 // Method greet:(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
        27: areturn
```

파라미터 순서대로 비트가 하나씩 대응한다. 두 번째 파라미터가 비트 `2`, 세 번째가 비트 `4`다. 해당 비트가 서 있으면 기본값 상수를 그 자리에 넣고, 다 채운 뒤 원래 메서드를 부른다. 기본값 개수가 늘어도 메서드는 여전히 둘이다.

앞의 `Greeter.greet`는 `final`이라 마지막 `Object` 파라미터를 읽는 코드가 아예 없다. 이 파라미터의 쓰임은 함수를 `open`으로 바꿔야 드러난다. 기본값이 하나뿐인 짧은 예로 본다.

```kotlin
open class OpenGreeter {
    open fun greet(name: String, mark: String = "!"): String = "$name$mark"
}
```

```
  public static java.lang.String greet$default(OpenGreeter, java.lang.String, java.lang.String, int, java.lang.Object);
    Code:
         0: aload         4
         2: ifnull        15
         5: new           #39                 // class java/lang/UnsupportedOperationException
         8: dup
         9: ldc           #41                 // String Super calls with default arguments not supported in this target, function: greet
        11: invokespecial #44                 // Method java/lang/UnsupportedOperationException."<init>":(Ljava/lang/String;)V
        14: athrow
        15: iload_3
    // 생략
```

이 자리가 `null`이 아니면 super 호출로 보고 예외를 던진다. 마스크를 읽는 코드는 그 검사를 통과한 뒤에 온다. 가드는 `open`일 때만 생성되므로, 앞의 `Greeter` 쪽 인용에 이 부분이 없는 것은 잘라낸 탓이 아니다.

그럼 이 자리에 non-null을 넣는 호출자는 누구인가. 없다. 하위 클래스에서 기본값을 생략한 super 호출은 컴파일러가 먼저 막는다.

```kotlin
open class Base {
    open fun greet(name: String, mark: String = "!"): String = "$name$mark"
}

class Child : Base() {
    override fun greet(name: String, mark: String): String = super.greet(name)
}
```

```
SuperCall.kt:6:68: error: super-calls with default arguments are prohibited. Specify all arguments of 'super.greet' explicitly.
    override fun greet(name: String, mark: String): String = super.greet(name)
                                                                   ^^^^^
```

바이트코드의 가드는 그 뒤에 남은 방어선이다.

### data class

Java 16에서 정식화된 `record`와 붙인다. 생성 목적이 가장 가깝다.

```kotlin
data class Point(val x: Int, val y: Int)
```

```java
record PointJ(int x, int y) {}
```

```
public final class Point {
  private final int x;
  private final int y;
  public Point(int, int);
  public final int getX();
  public final int getY();
  public final int component1();
  public final int component2();
  public final Point copy(int, int);
  public static Point copy$default(Point, int, int, int, java.lang.Object);
  public java.lang.String toString();
  public int hashCode();
  public boolean equals(java.lang.Object);
}
```

```
final class PointJ extends java.lang.Record {
  private final int x;
  private final int y;
  PointJ(int, int);
  public final java.lang.String toString();
  public final int hashCode();
  public final boolean equals(java.lang.Object);
  public int x();
  public int y();
}
```

세 가지가 다르다. `record`는 `java.lang.Record`를 상속하지만 `data class`는 `Object` 말고는 상속하지 않는다. `data class`에는 구조 분해용 `component1`/`component2`와, 일부 필드만 바꿔 새 인스턴스를 만드는 `copy`가 있다. `copy`도 기본값을 쓰므로 `copy$default`가 따라온다. `record`에는 둘 다 없다. 접근자 이름도 `getX`와 `x`로 다르다.

`equals`/`hashCode`/`toString`을 만드는 방식은 더 크게 갈린다. Kotlin은 코드를 전개한다.

```
  public int hashCode();
    Code:
         0: aload_0
         1: getfield      #13                 // Field x:I
         4: invokestatic  #52                 // Method java/lang/Integer.hashCode:(I)I
         7: istore_1
         8: iload_1
         9: bipush        31
        11: imul
        12: aload_0
        13: getfield      #16                 // Field y:I
        16: invokestatic  #52                 // Method java/lang/Integer.hashCode:(I)I
        19: iadd
        20: istore_1
    // 생략
```

`record`는 [`invokedynamic`](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-6.html#jvms-6.5.invokedynamic) 한 줄이다.

```
  public final int hashCode();
    Code:
         0: aload_0
         1: invokedynamic #20,  0             // InvokeDynamic #0:hashCode:(LPointJ;)I
         6: ireturn
```

`BootstrapMethods` 속성이 가리키는 상수 풀 항목을 보면 `java.lang.runtime.ObjectMethods.bootstrap`이 필드 목록 `x;y`와 각 필드를 읽는 메서드 핸들을 받는다.

```
  #39 = String             #40            // x;y
  #40 = Utf8               x;y
  #41 = MethodHandle       1:#7           // REF_getField PointJ.x:I
  #42 = MethodHandle       1:#13          // REF_getField PointJ.y:I
  #43 = MethodHandle       6:#44          // REF_invokeStatic java/lang/runtime/ObjectMethods.bootstrap:(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/TypeDescriptor;Ljava/lang/Class;Ljava/lang/String;[Ljava/lang/invoke/MethodHandle;)Ljava/lang/Object;
```

`record`는 비교 로직을 클래스 파일에 굽지 않고 런타임 첫 호출에 만든다. Kotlin은 컴파일 시점에 굽는다. 클래스 파일 크기가 그만큼 갈린다. 앞의 두 클래스를 재면 `Point.class`가 2182바이트, `PointJ.class`가 1146바이트다. 대신 `record`는 첫 호출에서 메서드 핸들을 엮는 비용을 문다.

결과까지 같지는 않다. 양쪽을 만들어 찍어 본다.

```
kotlin toString  : Point(x=1, y=2)
record toString  : PointJ[x=1, y=2]
kotlin hashCode  : 33
record hashCode  : 33
kotlin equals    : true
record equals    : true
```

`equals`는 같은 판정을 내지만 `toString` 포맷이 다르다. `hashCode`가 맞아떨어진 것은 우연이 아니다. 앞의 바이트코드에서 본 Kotlin 전개는 `h(x)*31 + h(y)`이고, [`ObjectMethods`의 `hashCombiner`](https://github.com/openjdk/jdk17u/blob/master/src/java.base/share/classes/java/lang/runtime/ObjectMethods.java)도 0에서 시작해 필드마다 `result*31 + h(필드)`를 누적한다. 같은 다항식이라 필드를 셋으로 늘려도 값이 같았다.

```kotlin
data class Triple3(val a: Int, val b: Int, val c: String)
```

```java
record Triple3J(int a, int b, String c) {}
```

둘 다 `(1, 2, "z")`로 만들어 찍는다.

```
kotlin 3field : 1145
record 3field : 1145
```

다만 [`Record.hashCode()`](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/lang/Record.html#hashCode()) 문서는 구현 알고리즘을 명세하지 않고 바뀔 수 있다고 적는다. 두 타입의 해시가 계속 같으리라 기대할 근거는 아니다.

### object와 companion object

```kotlin
object Registry {
    fun size(): Int = 0
}

class Service {
    companion object {
        fun create(): Service = Service()
    }
}
```

```java
final class RegistryJ {
    static final RegistryJ INSTANCE = new RegistryJ();
    private RegistryJ() {}
    int size() { return 0; }
}
```

```
public final class Registry {
  public static final Registry INSTANCE;
  private Registry();
  public final int size();
  static {};
}
```

```
final class RegistryJ {
  static final RegistryJ INSTANCE;
  private RegistryJ();
  int size();
  static {};
}
```

`static {}`는 정적 초기화 블록이다. 인스턴스는 여기서 만들어져 `INSTANCE`에 담긴다. 클래스 초기화는 JVM이 락으로 보호하므로 한 번만 일어난다.

두 목록의 차이는 가시성과 `final` 표시뿐이다. Kotlin은 클래스와 멤버를 기본 public으로 두고 `object`의 메서드를 `final`로 만들지만, Java 쪽 예시는 접근 제어자를 안 붙여 package-private이다. 정적 필드 하나, private 생성자, `static {}`이라는 싱글턴의 뼈대는 같다.

`companion object`는 다르다. 바깥 클래스에 메서드가 남지 않는다.

```
public final class Service {
  public static final Service$Companion Companion;
  public Service();
  static {};
}

public final class Service$Companion {
  private Service$Companion();
  public final Service create();
  public Service$Companion(kotlin.jvm.internal.DefaultConstructorMarker);
}
```

`create`는 `Service`가 아니라 별도 클래스 `Service$Companion`의 인스턴스 메서드다. 바깥 클래스는 그 인스턴스를 `Companion` 정적 필드로 들고 있을 뿐이다. `DefaultConstructorMarker`를 받는 생성자는 private 생성자를 바깥에서 부르려고 컴파일러가 만든 것이다.

## 경계 조건

지금까지 본 모양은 Kotlin에서 부를 때는 문제가 되지 않는다. Java에서 부를 때 드러난다.

### non-null 파라미터에 null이 들어간다

Kotlin 컴파일러는 Java 코드의 null 여부를 알 수 없다. 검사는 런타임으로 미뤄진다.

```java
public class CallFromJava {
    public static void main(String[] args) {
        String nothing = null;
        System.out.println(new Nullability().accept(nothing));
    }
}
```

컴파일은 통과하고 실행에서 걸린다.

```
Exception in thread "main" java.lang.NullPointerException: Parameter specified as non-null is null: method Nullability.accept, parameter name
	at Nullability.accept(Nullability.kt)
	at CallFromJava.main(CallFromJava.java:4)
```

`Intrinsics.checkNotNullParameter`가 만든 메시지다. 메서드 안쪽 어디가 아니라 진입부에서 멈추므로 잘못된 값을 넘긴 호출부가 스택 트레이스 바로 아래에 남는다.

### 기본값은 Java에서 통하지 않는다

실제 메서드는 파라미터 세 개짜리 하나뿐이다.

```java
public class CallGreet {
    public static void main(String[] args) {
        System.out.println(new Greeter().greet("Kotlin"));
    }
}
```

```
CallGreet.java:3: error: method greet in class Greeter cannot be applied to given types;
        System.out.println(new Greeter().greet("Kotlin"));
                                        ^
  required: String,String,String
  found:    String
  reason: actual and formal argument lists differ in length
```

`greet$default`를 대신 부를 수도 없다. 이 메서드는 `public static`이지만 [플래그](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-4.html#jvms-4.6)에 `ACC_SYNTHETIC`이 함께 서 있다.

```
    flags: (0x1009) ACC_PUBLIC, ACC_STATIC, ACC_SYNTHETIC
```

`javac`는 이 플래그가 붙은 멤버를 소스에서 참조할 수 있는 심볼로 보지 않는다. 마스크를 직접 계산해 넘겨 봐도 이렇게 끝난다.

```
CallDefault.java:3: error: cannot find symbol
        System.out.println(Greeter.greet$default(new Greeter(), "Kotlin", null, null, 6, null));
                                  ^
  symbol:   method greet$default(Greeter,String,<null>,<null>,int,<null>)
  location: class Greeter
```

### companion 메서드는 정적 메서드가 아니다

```java
public class CallCompanion {
    public static void main(String[] args) {
        System.out.println(Service.create());
    }
}
```

```
CallCompanion.java:3: error: cannot find symbol
        System.out.println(Service.create());
                                  ^
  symbol:   method create()
  location: class Service
```

`Service.Companion.create()`로 필드를 한 번 거치면 호출된다.

## 대안과 트레이드오프

Kotlin은 `@JvmOverloads`와 `@JvmStatic`으로 모양을 Java 쪽에 맞춰 준다. 대신 클래스 파일에 메서드가 는다.

`@JvmOverloads`를 붙이면 오버로드가 실제로 생성된다.

```
public final class GreeterOverloads {
  public GreeterOverloads();
  public final java.lang.String greet(java.lang.String, java.lang.String, java.lang.String);
  public static java.lang.String greet$default(GreeterOverloads, java.lang.String, java.lang.String, java.lang.String, int, java.lang.Object);
  public final java.lang.String greet(java.lang.String, java.lang.String);
  public final java.lang.String greet(java.lang.String);
}
```

`$default`는 그대로 있고 오버로드가 더해진다. Kotlin 호출부는 여전히 `$default`를 쓰고, 새로 생긴 둘은 Java 전용이다.

`@JvmStatic`을 붙이면 바깥 클래스에 정적 메서드가 생긴다.

```
public final class ServiceStatic {
  public static final ServiceStatic$Companion Companion;
  public ServiceStatic();
  public static final ServiceStatic create();
  static {};
}
```

`Companion` 필드와 중첩 클래스는 없어지지 않는다. 정적 메서드가 하나 늘고 그 안에서 companion 인스턴스로 위임한다.

null 검사 쪽은 애노테이션이 아니라 컴파일러 플래그로 끈다. `kotlinc -X`가 출력하는 고급 옵션 목록에 이렇게 적혀 있다.

```
  -Xno-param-assertions      Don't generate not-null assertions on parameters of methods accessible from Java.
```

설명문의 "methods accessible from Java"가 앞에서 `private`에만 검사가 없던 이유다. 이 검사는 Java 호출부의 실수를 진입부에서 잡는다. Java와 섞어 쓰는 코드에서는 끄지 않는 편이 낫다.

## 언제 쓰고 언제 안 쓰나

`@JvmOverloads`와 `@JvmStatic`은 Java 호출부가 실제로 있을 때만 붙인다. Kotlin만 쓰는 모듈에서는 쓰이지 않는 메서드만 클래스 파일에 남는다.

기본값 파라미터가 공개 API에 있고 Java 쪽에서 부를 예정이면 `@JvmOverloads`가 답이다. 다만 오버로드는 파라미터 뒤쪽부터 하나씩 떼어 낸 조합만 생긴다. 중간 파라미터만 생략하는 호출은 Java에서 여전히 불가능하다.

## 참고

- [Kotlin 문서 — Calling Kotlin from Java](https://kotlinlang.org/docs/java-to-kotlin-interop.html)
- [Kotlin 문서 — Null safety](https://kotlinlang.org/docs/null-safety.html)
- [Kotlin 문서 — Data classes](https://kotlinlang.org/docs/data-classes.html)
- [Kotlin 문서 — Object declarations](https://kotlinlang.org/docs/object-declarations.html)
- [JEP 395: Records](https://openjdk.org/jeps/395)
- [ObjectMethods.bootstrap — Java SE 17 API](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/lang/runtime/ObjectMethods.html)
