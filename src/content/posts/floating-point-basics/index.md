---
title: "부동소수점 — 0.1 + 0.2가 0.3이 아닌 이유"
description: "double이 십진 소수를 어떻게 저장하는지, 왜 오차가 생기는지, 비교와 금액 계산에서 무엇을 조심해야 하는지 정리한다."
pubDate: 2026-08-24
category: "컴퓨터공학"
tags: ["기본개념", "부동소수점", "IEEE754", "Java"]
---

## 왜 필요한가

Java에서 `0.1 + 0.2`는 `0.3`이 아니다.

```java
System.out.println(0.1 + 0.2);        // 0.30000000000000004
System.out.println(0.1 + 0.2 == 0.3); // false
```

JVM 버그가 아니다. `double`은 [IEEE 754](https://ko.wikipedia.org/wiki/IEEE_754) 규격을 따르고, 규격대로 계산한 결과가 저것이다. 십진 소수 `0.1`을 이진수로 정확히 적을 수 없기 때문에 생긴다.

## 핵심 정리

`double`과 `float`는 실수를 부호, 지수, 가수 세 조각으로 쪼개 저장한다. 정규수의 값은 `(-1)^부호 × 1.가수 × 2^(지수 - bias)`다.

| 항목 | `float` (32비트) | `double` (64비트) |
|---|---|---|
| 부호 | 1비트 | 1비트 |
| 지수 | 8비트 | 11비트 |
| 가수(저장) | 23비트 | 52비트 |
| 가수(유효) | 24비트 | 53비트 |
| 지수 bias | 127 | 1023 |
| 왕복 보장 십진 자릿수 | 6자리 | 15자리 |
| 값을 특정하는 데 필요한 자릿수 | 9자리 | 17자리 |
| 연속 정수를 정확히 세는 한계 | 2^24 = 16,777,216 | 2^53 = 9,007,199,254,740,992 |

가수가 24비트, 53비트인데 저장은 하나 적은 이유는 맨 앞 `1`을 적지 않기 때문이다. 정규화하면 항상 `1.xxx` 꼴이므로 그 `1`은 저장하지 않고, 규격이 항상 있는 것으로 정한다.

지수 필드가 전부 0이거나 전부 1이면 이 공식이 적용되지 않는다. 전부 0이면 앞자리를 `0.`으로 읽는 [비정규수](https://en.wikipedia.org/wiki/Subnormal_number)이고, 전부 1이면 `Infinity`나 `NaN`이다.

"왕복 보장"과 "값을 특정"은 다른 값이다. 유효숫자 15자리짜리 십진수는 `double`로 넣었다 빼도 그대로 돌아온다. 반대로 임의의 `double` 하나를 다른 `double`과 구별되게 십진수로 적으려면 17자리가 필요하다.

### 이진 분수로 못 적는 수

십진법에서 `1/3`을 `0.333...`으로 끝없이 적어야 하는 것과 같은 문제다. 이진법에서는 분모가 2의 거듭제곱인 분수만 유한하게 끝난다. `0.1`은 `1/10`이고 10에 5가 섞여 있어 끝나지 않는다.

```
0.1(십진) = 0.0001100110011001100... (이진, 1100 반복)
```

유효 53비트에서 반올림한 값이 저장된다. `0.2`도, `0.3`도 마찬가지다. 셋 다 조금씩 어긋난 값이라 더한 결과가 맞아떨어지지 않는다.

## 예시

### 저장된 값을 그대로 꺼내기

`new BigDecimal(double)`은 `double`이 실제로 담고 있는 값을 반올림 없이 십진수로 옮긴다.

```java
System.out.println(new BigDecimal(0.1));
// 0.1000000000000000055511151231257827021181583404541015625

System.out.println(new BigDecimal(0.3));
// 0.299999999999999988897769753748434595763683319091796875

System.out.println(new BigDecimal(0.1 + 0.2));
// 0.3000000000000000444089209850062616169452667236328125
```

`0.1 + 0.2`와 `0.3`은 저장된 값 자체가 다르다. `println(0.1)`이 `0.1`로 보이는 것은 `Double.toString`이 원래 값으로 되돌아가는 짧은 십진 표기를 고르기 때문이다. 최단 표기 보장은 [JDK 19](https://bugs.openjdk.org/browse/JDK-4511638)부터고, 그 전 규격은 다른 값과 구별될 만큼의 자릿수였다. 화면에 보이는 것과 메모리에 있는 것이 다르다.

같은 `BigDecimal`이라도 생성 방법에 따라 결과가 갈린다.

```java
new BigDecimal(0.1)         // 0.1000000000000000055511151231257827021181583404541015625
BigDecimal.valueOf(0.1)     // 0.1
new BigDecimal("0.1")       // 0.1
```

`new BigDecimal(0.1)`은 이미 오차가 낀 `double`을 받아 그 오차까지 옮긴다. `valueOf`는 위의 `Double.toString`을 거치고, 문자열 생성자는 십진수를 그대로 읽는다. [javadoc이 문자열 생성자를 권한다](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/math/BigDecimal.html#%3Cinit%3E(double)).

### 비트 배치

```java
static String bits(double d) {
    String s = Long.toBinaryString(Double.doubleToLongBits(d));
    s = "0".repeat(64 - s.length()) + s;
    return s.charAt(0) + " " + s.substring(1, 12) + " " + s.substring(12);
}
```

```
bits(1.0)  0 01111111111 0000000000000000000000000000000000000000000000000000
bits(-1.0) 1 01111111111 0000000000000000000000000000000000000000000000000000
bits(0.5)  0 01111111110 0000000000000000000000000000000000000000000000000000
bits(0.1)  0 01111111011 1001100110011001100110011001100110011001100110011010
```

`1.0`의 지수 필드는 `01111111111` = 1023이다. 1023 - 1023 = 0이므로 `1.0 × 2^0`이다. `0.5`는 1022 - 1023 = -1, `0.1`은 1019 - 1023 = -4다. 가수 `1001100110011...`은 `1001`이 반복되다가 끝에서 `1010`으로 올림됐다. 이 올림이 오차의 정체다.

`0.5`와 `1.0`의 가수는 전부 0이다. 2의 거듭제곱이라 오차가 없다.

### 2의 거듭제곱은 정확하다

```java
System.out.println(0.5 + 0.25 == 0.75); // true
System.out.println(0.1 + 0.2 == 0.3);   // false
```

`0.5`, `0.25`, `0.75`는 각각 `2^-1`, `2^-2`, `2^-1 + 2^-2`다. 이진수로 유한하게 끝나므로 저장에도 덧셈에도 오차가 없다. 부동소수점이 늘 틀리는 것이 아니라, 이진 분수로 떨어지지 않는 값에서만 틀린다.

### 곱셈은 되는데 덧셈은 안 되는 경우

```java
System.out.println(0.1 * 10 == 1.0);  // true

double sum = 0.0;
for (int i = 0; i < 10; i++) sum += 0.1;
System.out.println(sum);              // 0.9999999999999999
System.out.println(sum == 1.0);       // false
```

`0.1 * 10`은 연산이 한 번이다. 오차가 낀 `0.1`에 10을 곱한 참값은 `1.0000000000000000555...`이고, `1.0`과 그다음 `double` 사이 간격 `2.22e-16`의 절반에도 못 미치므로 `1.0`으로 떨어진다. 열 번 더하는 쪽은 매 연산마다 반올림이 일어나고 그 오차가 쌓인다.

매번 어긋나지는 않는다. 같은 루프의 네 번째 덧셈은 정확히 `0.4`로 돌아온다. 반복이 길어질수록 누적 오차가 커지는 경향이다.

```java
double s = 0.0;
for (int i = 0; i < 1000; i++) s += 0.1;
System.out.println(s); // 99.9999999999986
```

### 반올림이 예상과 어긋나는 지점

```java
System.out.println(new BigDecimal(1.005));
// 1.00499999999999989341858963598497211933135986328125
System.out.println(1.005 * 100);                    // 100.49999999999999
System.out.println(Math.round(1.005 * 100) / 100.0); // 1.0
```

`1.005`를 소수 둘째 자리로 반올림하면 `1.01`을 기대하지만 `1.0`이 나온다. 저장된 값이 `1.005`보다 작아서다. 금액을 `double`로 다루면 이 차이가 청구서에 그대로 나온다.

## 혼동하기 쉬운 것

### `Double.MIN_VALUE`는 음수가 아니다

```java
System.out.println(Double.MIN_VALUE);      // 4.9E-324
System.out.println(Double.MIN_VALUE > 0);  // true
System.out.println(-Double.MAX_VALUE);     // -1.7976931348623157E308
```

`Integer.MIN_VALUE`가 가장 작은 `int`인 것과 달리, `Double.MIN_VALUE`는 **0보다 큰 가장 작은 값**이다. 표현할 수 있는 가장 작은 `double`은 `-Double.MAX_VALUE`다. [javadoc](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Double.html#MIN_VALUE)에도 "smallest positive nonzero value"로 적혀 있다.

### `==`, `equals`, `compare`가 서로 다르게 답한다

`NaN`과 `-0.0`에서 셋의 결과가 갈린다.

| 비교 | `==` | `Double.equals` | `Double.compare` |
|---|---|---|---|
| `NaN`, `NaN` | `false` | `true` | `0` (같음) |
| `0.0`, `-0.0` | `true` | `false` | `1` (`0.0`이 큼) |

```java
System.out.println(Double.NaN == Double.NaN);                            // false
System.out.println(Double.valueOf(Double.NaN).equals(Double.NaN));       // true
System.out.println(0.0 == -0.0);                                         // true
System.out.println(Double.valueOf(0.0).equals(Double.valueOf(-0.0)));    // false
System.out.println(Double.compare(Double.NaN, Double.NaN));              // 0
System.out.println(Double.compare(0.0, -0.0));                           // 1
```

`HashSet`과 `HashMap`은 `equals`를, `TreeMap`과 정렬은 `compare`를 쓴다. `NaN`을 `HashSet`에 두 번 넣으면 하나만 남지만, `==`로 짠 중복 검사에서는 걸러지지 않는다. `0.0`과 `-0.0`은 반대로 `==`에서 같고 `HashSet`에서 다르다.

### 정수라고 안전하지 않다

`double`의 유효 가수는 53비트다. 2^53을 넘으면 연속된 정수를 다 담지 못한다.

```java
System.out.println(1e16 + 1 == 1e16); // true
System.out.println(Math.ulp(1e16));   // 2.0
```

`1e16` 근처에서 이웃한 `double` 사이의 간격은 2다. 1을 더해도 자기 자신으로 반올림된다. `long`의 상한(약 9.22 × 10^18)보다 훨씬 이른 지점에서 정확성이 깨진다. ID나 금액을 `double`에 담으면 안 되는 이유다.

## 언제 어떤 것을 쓰나

| 용도 | 타입 | 이유 |
|---|---|---|
| 금액, 세금, 회계 | `BigDecimal` (문자열 생성자) 또는 최소 단위 `long` | 십진 소수를 오차 없이 다뤄야 한다 |
| 좌표, 물리량, 통계 | `double` | 원래 측정값에 오차가 있고 속도가 중요하다 |
| 메모리를 아껴야 하는 대량 수치 | `float` | 유효 자릿수 6자리로 충분할 때만 |

원화처럼 소수점이 없는 통화는 `long`에 원 단위로 담는 편이 `BigDecimal`보다 가볍다. 소수점이 있는 통화나 세율 계산이 끼면 `BigDecimal`을 쓴다.

## 비교할 때

`==` 대신 오차 허용 범위를 두고 비교한다. 이때 `1e-9` 같은 고정값을 쓰면 큰 수에서 무너진다.

```java
double x = 1e17;
double y = Math.nextUp(Math.nextUp(Math.nextUp(1e17))); // 세 칸 옆 double

System.out.println(y - x);                        // 48.0
System.out.println(Math.abs(x - y) < 1e-9);       // false
System.out.println(Math.ulp(x));                  // 16.0
System.out.println(Math.abs(x - y) <= Math.ulp(x) * 4); // true
```

`1e17` 근처에서는 이웃한 `double` 사이 간격이 이미 16이다. 표현할 수 있는 값이 세 칸밖에 차이 나지 않는데도 고정 오차 `1e-9`는 "다르다"고 답한다. 곱한 `4`는 몇 번의 연산을 거쳤는지에 맞춰 잡는 값이다. 연산 한 번마다 최대 0.5 ulp가 붙으므로, 허용할 연산 횟수를 넘겨준다고 보면 된다. 허용 범위는 비교 대상의 크기에 맞춰 잡아야 하고, [`Math.ulp`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Math.html#ulp(double))가 그 크기에서의 최소 간격을 알려준다.

## 참고

- [IEEE 754 - 위키백과](https://ko.wikipedia.org/wiki/IEEE_754)
- [Double (Java SE API)](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Double.html)
- [BigDecimal (Java SE API)](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/math/BigDecimal.html)
- [What Every Computer Scientist Should Know About Floating-Point Arithmetic](https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html)
