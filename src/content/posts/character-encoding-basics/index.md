---
title: "문자 인코딩: 코드 포인트, UTF-8, 서로게이트 쌍"
description: "같은 문자열의 길이가 도구마다 3, 4, 8로 갈리는 이유를 코드 포인트, UTF-8, UTF-16의 서로게이트 쌍으로 설명한다."
pubDate: 2026-09-11
category: "컴퓨터공학"
tags: ["기본개념", "유니코드", "UTF-8"]
---

## 왜 헷갈리는가

`a한😀`의 길이를 물으면 도구마다 답이 다르다. Python `len()`은 3, Java `length()`는 4, UTF-8로 인코딩한 바이트 수는 8이다. 셋 다 맞는 값이고 세는 단위가 다를 뿐이다. Python은 코드 포인트를, Java는 UTF-16 코드 단위를, 바이트 수는 UTF-8 코드 단위를 센다. 이 세 단위를 갈라놓으면 길이가 왜 갈리는지, 문자열을 자를 때 무엇이 깨지는지가 보인다.

## 용어 정리

- **코드 포인트(code point)**: 유니코드가 문자마다 붙인 번호. `U+D55C`처럼 16진수로 적는다. [유니코드 용어집](https://www.unicode.org/glossary/#code_point)이 정한 범위는 0부터 `0x10FFFF`까지다.
- **인코딩 형식(encoding form)**: 코드 포인트를 저장할 비트열로 바꾸는 규칙. UTF-8, UTF-16, UTF-32가 있다.
- **코드 단위(code unit)**: 인코딩 형식이 다루는 최소 비트 묶음([용어집](https://www.unicode.org/glossary/#code_unit)). UTF-8은 8비트, UTF-16은 16비트, UTF-32는 32비트다. 코드 포인트 하나가 코드 단위 몇 개가 되는지가 형식마다 다르다.
- **BMP와 보충 문자**: `U+0000`부터 `U+FFFF`까지가 [BMP](https://www.unicode.org/glossary/#basic_multilingual_plane)(Basic Multilingual Plane)이고, 그 위의 문자가 [보충 문자](https://www.unicode.org/glossary/#supplementary_character)(supplementary character)다. `한`(U+D55C)은 BMP에, `😀`(U+1F600)는 보충 문자에 속한다.
- **서로게이트 쌍(surrogate pair)**: UTF-16이 보충 문자 하나를 16비트 코드 단위 두 개로 나눠 적은 것. 앞 단위는 `U+D800`\~`U+DBFF`(high surrogate), 뒤 단위는 `U+DC00`\~`U+DFFF`(low surrogate) 범위에서 온다.

## 핵심 정리

| | UTF-8 | UTF-16 | UTF-32 |
|---|---|---|---|
| 코드 단위 | 8비트 | 16비트 | 32비트 |
| 코드 포인트 하나에 드는 코드 단위 | 1~4개 | 1개 또는 2개 | 1개 |
| `a` (U+0061) | `61` (1바이트) | `00 61` (2바이트) | 4바이트 |
| `한` (U+D55C) | `ED 95 9C` (3바이트) | `D5 5C` (2바이트) | 4바이트 |
| `😀` (U+1F600) | `F0 9F 98 80` (4바이트) | `D8 3D DE 00` (4바이트, 서로게이트 쌍) | 4바이트 |
| ASCII와의 관계 | U+007F까지는 ASCII와 바이트가 같다 | 다르다 | 다르다 |

UTF-8과 UTF-16의 바이트는 아래 「예시」의 실행 결과에서 옮겼다. JSON은 닫힌 환경 밖에서 주고받을 때 UTF-8을 쓰도록 정해져 있다([RFC 8259 8.1절](https://www.rfc-editor.org/rfc/rfc8259#section-8.1)). 반면 Java의 `String`은 [문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/lang/String.html)가 밝히듯 UTF-16 형식의 문자열이고, JavaScript 문자열도 UTF-16 코드 단위로 길이를 센다. Java 프로그램이 JSON을 내보내면 그 사이에서 UTF-16이 UTF-8로 바뀐다.

UTF-8이 코드 포인트를 몇 바이트로 적는지는 범위로 정해진다. [RFC 3629 3절](https://www.rfc-editor.org/rfc/rfc3629#section-3)의 표다.

| 코드 포인트 범위 | 바이트 수 | 비트 패턴 |
|---|---|---|
| U+0000 ~ U+007F | 1 | `0xxxxxxx` |
| U+0080 ~ U+07FF | 2 | `110xxxxx 10xxxxxx` |
| U+0800 ~ U+FFFF | 3 | `1110xxxx 10xxxxxx 10xxxxxx` |
| U+10000 ~ U+10FFFF | 4 | `11110xxx 10xxxxxx 10xxxxxx 10xxxxxx` |

## 항목별 설명

**UTF-8은 첫 바이트가 길이를 알린다.** 첫 바이트 앞쪽에 연달아 선 1의 개수가 바이트 수이고, 뒤따르는 바이트는 모두 `10`으로 시작한다. `한`(U+D55C)은 U+0800\~U+FFFF 구간이라 3바이트 패턴 `1110xxxx 10xxxxxx 10xxxxxx`를 쓴다. 이 패턴의 `x`는 바이트마다 4, 6, 6개, 합쳐 16개다. 그래서 `D55C`를 2진수 16비트(`1101010101011100`)로 바꿔 앞에서부터 4, 6, 6비트씩 잘라 각 바이트의 `x` 자리에 넣는다.

| | 첫 바이트 | 둘째 바이트 | 셋째 바이트 |
|---|---|---|---|
| 패턴 | `1110xxxx` | `10xxxxxx` | `10xxxxxx` |
| `D55C`를 4·6·6비트로 자름 | `1101` | `010101` | `011100` |
| `x` 자리에 넣은 결과 | `11101101` | `10010101` | `10011100` |
| 16진수 | `ED` | `95` | `9C` |

이 구조에서 두 가지 성질이 나온다.

- **ASCII 바이트와 겹치지 않는다.** 여러 바이트짜리 문자의 바이트는 `한`의 `ED 95 9C`처럼 모두 `0x80` 이상이다. 따라서 개행 `0x0A` 같은 ASCII 바이트를 바이트 단위로 찾아도 다른 문자의 일부에 잘못 걸리지 않는다.
- **중간에서 읽어도 문자 경계를 찾는다.** 첫 바이트는 `0`이나 `11`로 시작하고, 뒤따르는 바이트는 위 표의 `95 9C`(`10 010101`, `10 011100`)처럼 `10`으로 시작해 둘이 겹치지 않는다. 따라서 `10`으로 시작하는 바이트를 건너뛰면 다음 문자의 첫 바이트가 나온다.

**UTF-16은 BMP 밖의 문자를 두 단위로 쪼갠다.** [RFC 2781 2.1절](https://www.rfc-editor.org/rfc/rfc2781#section-2.1)의 절차는 코드 포인트에서 `0x10000`을 빼 20비트로 만들고, 위 10비트를 `0xD800`에, 아래 10비트를 `0xDC00`에 더하는 것이다. `😀`(U+1F600)이면 `0x1F600 - 0x10000 = 0xF600`이다.

```text
0xF600 (20비트) = 0000111101 | 1000000000
high           = 0xD800 + 0x03D = 0xD83D
low            = 0xDC00 + 0x200 = 0xDE00
```

[JSON 기본개념](/posts/json-basics/)에서 `😀`를 `\uD83D\uDE00`으로 적은 것이 이 두 값이다.

코드 포인트의 상한이 `0x10FFFF`인 이유도 여기서 나온다. 서로게이트 쌍이 담는 20비트는 `0x100000`개이고, BMP의 `0x10000`개를 더하면 `0x110000`개다. 0부터 세면 마지막 번호가 `0x10FFFF`다. UTF-8의 4바이트 패턴에는 `x`가 21개라 `0x1FFFFF`까지 담을 자리가 있지만, RFC 3629는 UTF-8도 이 범위로 묶었다.

> In UTF-8, characters from the U+0000..U+10FFFF range (the UTF-16 accessible range) are encoded using sequences of 1 to 4 octets.

**서로게이트 범위의 번호는 문자가 아니다.** `U+D800`\~`U+DFFF`는 UTF-16이 쌍을 만들 때만 쓰는 번호이고, 이 범위에는 문자가 배정되지 않는다. 그래서 쌍을 이루는 두 단위가 문자 두 개로 읽힐 일이 없다. UTF-16 디코더는 코드 단위 하나만 보고 역할을 가린다.

- `D800`\~`DBFF`: high surrogate. 다음 단위가 low면 둘을 묶어 문자 하나로 읽는다.
- `DC00`\~`DFFF`: low surrogate. 앞 단위와 짝을 이루는 뒤쪽이다.
- 그 밖의 값: `한`(`D55C`)처럼 서로게이트 범위 밖의 값은 코드 단위 하나가 곧 문자 하나다.

RFC 3629는 서로게이트 범위의 번호를 UTF-8로 인코딩하는 것을 금지한다.

> The definition of UTF-8 prohibits encoding character numbers between U+D800 and U+DFFF, which are reserved for use with the UTF-16 encoding form (as surrogate pairs) and do not directly represent characters.

그래서 쌍의 한쪽만 남은 UTF-16 문자열은 UTF-8로 옮길 수 없다.

high와 low의 범위가 겹치지 않으므로, 문자열 중간에서 읽기 시작해 low가 먼저 나와도 쌍의 뒤쪽임을 안다. 앞서 UTF-8에서 첫 바이트와 뒤따르는 바이트를 가른 것과 같은 원리다.

## 예시

`Encoding.java`는 `a한😀`의 코드 포인트마다 UTF-8 바이트와 UTF-16 바이트를 찍는다. UTF-16은 바이트 순서를 빅엔디언으로 고정한 `UTF_16BE`로 인코딩했다.

```java
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class Encoding {
    public static void main(String[] args) {
        String s = "a한😀";
        HexFormat hex = HexFormat.ofDelimiter(" ");

        System.out.println("code point  UTF-8        UTF-16BE     char");
        s.codePoints().forEach(cp -> {
            String c = Character.toString(cp);
            System.out.printf("%-11s %-12s %-12s %s%n", String.format("U+%04X", cp),
                    hex.formatHex(c.getBytes(StandardCharsets.UTF_8)),
                    hex.formatHex(c.getBytes(StandardCharsets.UTF_16BE)), c);
        });

        System.out.println();
        System.out.println("length()          " + s.length());
        System.out.println("codePointCount()  " + s.codePointCount(0, s.length()));
        System.out.println("UTF-8 바이트      " + s.getBytes(StandardCharsets.UTF_8).length);
        System.out.println("UTF-16BE 바이트   " + s.getBytes(StandardCharsets.UTF_16BE).length);
    }
}
```

```
$ java -Dstdout.encoding=UTF-8 Encoding.java
code point  UTF-8        UTF-16BE     char
U+0061      61           00 61        a
U+D55C      ed 95 9c     d5 5c        한
U+1F600     f0 9f 98 80  d8 3d de 00  😀

length()          4
codePointCount()  3
UTF-8 바이트      8
UTF-16BE 바이트   8
```

`length()`가 4인 것은 Java 26 [`String` 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/lang/String.html#length())가 적은 대로 코드 단위를 세기 때문이다.

> Returns the length of this string. The length is equal to the number of Unicode code units in the string.

`😀` 하나가 `d8 3d`와 `de 00` 두 단위를 차지해 3이 아니라 4가 됐다. 코드 포인트는 `codePointCount()`가 센다. UTF-8과 UTF-16의 바이트 수가 둘 다 8인 것은 우연이다. `a`에서 UTF-8이 1바이트 적고 `한`에서 1바이트 많아 상쇄됐다.

`Surrogate.java`는 서로게이트 쌍을 손으로 계산해 `Character`가 주는 값과 맞춰 보고, 같은 문자열을 코드 단위 기준과 코드 포인트 기준으로 각각 자른다.

```java
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class Surrogate {
    public static void main(String[] args) {
        int cp = 0x1F600;                        // 😀
        int v = cp - 0x10000;                    // 20비트로 줄인다
        int high = 0xD800 + (v >> 10);           // 위 10비트
        int low = 0xDC00 + (v & 0x3FF);          // 아래 10비트
        System.out.printf("직접 계산    %X %X%n", high, low);
        System.out.printf("Character   %X %X%n",
                (int) Character.highSurrogate(cp), (int) Character.lowSurrogate(cp));
        System.out.printf("되돌리기     U+%X%n", Character.toCodePoint((char) high, (char) low));

        String s = "a한😀";
        String cut = s.substring(0, 3);          // 😀의 앞쪽 절반에서 자른다
        HexFormat hex = HexFormat.ofDelimiter(" ");
        System.out.println();
        System.out.println("cut.length()    " + cut.length());
        System.out.printf("마지막 char     %X (high surrogate: %b)%n",
                (int) cut.charAt(2), Character.isHighSurrogate(cut.charAt(2)));
        System.out.println("UTF-8로 인코딩  " + hex.formatHex(cut.getBytes(StandardCharsets.UTF_8)));

        String safe = s.substring(0, s.offsetByCodePoints(0, 3));   // 코드 포인트 세 개
        System.out.println();
        System.out.println("safe.length()   " + safe.length());
        System.out.println("UTF-8로 인코딩  " + hex.formatHex(safe.getBytes(StandardCharsets.UTF_8)));
    }
}
```

```
$ java -Dstdout.encoding=UTF-8 Surrogate.java
직접 계산    D83D DE00
Character   D83D DE00
되돌리기     U+1F600

cut.length()    3
마지막 char     D83D (high surrogate: true)
UTF-8로 인코딩  61 ed 95 9c 3f

safe.length()   4
UTF-8로 인코딩  61 ed 95 9c f0 9f 98 80
```

첫 세 줄은 앞의 계산과 같다. 문제는 그 아래다. `substring(0, 3)`은 코드 단위 세 개를 자르므로 `😀`의 high surrogate `D83D`만 남긴다. 이 문자열을 UTF-8로 인코딩하면 마지막 바이트가 `3f`, 곧 `?`다. [`getBytes(Charset)`](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/lang/String.html#getBytes(java.nio.charset.Charset))는 인코딩할 수 없는 입력을 예외 없이 대체 바이트로 바꾼다.

> This method always replaces malformed-input and unmappable-character sequences with this charset's default replacement byte array.

"앞에서 N자까지 자르기"를 `length()`와 `substring()`으로 짜면, 이모지가 경계에 걸리는 순간 이렇게 `?`가 저장되고 예외도 경고도 나지 않는다. `offsetByCodePoints()`로 코드 포인트 N개째의 인덱스를 구해 자르면 마지막 두 줄처럼 `😀`가 온전히 남는다.

## 혼동하기 쉬운 것

**MySQL의 `utf8`은 UTF-8 전체가 아니다.** MySQL에서 `utf8`은 `utf8mb3`의 별칭이고, [MySQL 8.4 문서](https://dev.mysql.com/doc/refman/8.4/en/charset-unicode-utf8mb3.html)에 따르면 `utf8mb3`는 문자 하나를 최대 3바이트로 저장하며 BMP 문자만 지원한다. 4바이트짜리 보충 문자는 들어가지 않는다. RFC 3629의 UTF-8 전체에 해당하는 것은 `utf8mb4`다.

```sql
-- 실행: docker compose -f experiments/compose.yml exec -T mysql mysql -uroot -plab --default-character-set=utf8mb4 --table --force --unbuffered < experiments/character-encoding-basics/setup-mysql.sql
DROP DATABASE IF EXISTS character_encoding_basics;
CREATE DATABASE character_encoding_basics CHARACTER SET utf8mb4;
USE character_encoding_basics;

SELECT VERSION();
SELECT CHAR_LENGTH('a한😀') AS char_length, LENGTH('a한😀') AS length;

CREATE TABLE t3 (v VARCHAR(3) CHARACTER SET utf8);
SHOW WARNINGS\G
CREATE TABLE t4 (v VARCHAR(3) CHARACTER SET utf8mb4);
INSERT INTO t3 VALUES ('a한'), ('a한😀');
INSERT INTO t4 VALUES ('a한'), ('a한😀');
SELECT 't3' AS tbl, HEX(v), CHAR_LENGTH(v), LENGTH(v) FROM t3
UNION ALL
SELECT 't4', HEX(v), CHAR_LENGTH(v), LENGTH(v) FROM t4;
```

```bash
docker compose -f experiments/compose.yml exec -T mysql mysql -uroot -plab --default-character-set=utf8mb4 --table --force --unbuffered < experiments/character-encoding-basics/setup-mysql.sql
```

`--force`는 오류가 난 문장을 건너뛰고 다음 문장을 계속 실행하게 한다.

```
mysql: [Warning] Using a password on the command line interface can be insecure.
+-----------+
| VERSION() |
+-----------+
| 8.4.11    |
+-----------+
+-------------+--------+
| char_length | length |
+-------------+--------+
|           3 |      8 |
+-------------+--------+
*************************** 1. row ***************************
  Level: Warning
   Code: 3719
Message: 'utf8' is currently an alias for the character set UTF8MB3, but will be an alias for UTF8MB4 in a future release. Please consider using UTF8MB4 in order to be unambiguous.
ERROR 1366 (HY000) at line 12: Incorrect string value: '\xF0\x9F\x98\x80' for column 'v' at row 2
+-----+------------------+----------------+-----------+
| tbl | HEX(v)           | CHAR_LENGTH(v) | LENGTH(v) |
+-----+------------------+----------------+-----------+
| t4  | 61ED959C         |              2 |         4 |
| t4  | 61ED959CF09F9880 |              3 |         8 |
+-----+------------------+----------------+-----------+
```

첫 줄은 명령줄에 비밀번호를 적어서 나오는 클라이언트 경고라 실험과 무관하다. `SHOW WARNINGS`의 경고가 별칭 관계를 직접 밝힌다. `ERROR 1366`의 `\xF0\x9F\x98\x80`은 `😀`의 UTF-8 바이트 그대로이고, 3바이트 문자셋 컬럼이 이 4바이트를 거부했다. 두 행을 한 문장으로 넣었는데 결과에 `t3` 행이 하나도 없다. 둘째 행에서 실패하자 첫째 행까지 되돌려졌다. MySQL 8.4의 기본 SQL 모드에는 `STRICT_TRANS_TABLES`가 들어 있고, 기본 엔진인 InnoDB는 트랜잭션 테이블이라 [strict 모드 규칙](https://dev.mysql.com/doc/refman/8.4/en/sql-mode.html)대로 문장 전체가 취소된다.

> For transactional tables, an error occurs for invalid or missing values in a data-change statement when either STRICT_ALL_TABLES or STRICT_TRANS_TABLES is enabled. The statement is aborted and rolled back.

`utf8mb4`인 `t4`에는 둘 다 들어갔다.

`VARCHAR(3)` 컬럼에 8바이트가 들어간 것은 [MySQL의 `VARCHAR(M)`](https://dev.mysql.com/doc/refman/8.4/en/char.html)이 바이트가 아니라 문자 수를 세기 때문이다.

> The CHAR and VARCHAR types are declared with a length that indicates the maximum number of characters you want to store.

**코드 포인트 하나가 화면의 한 글자는 아니다.** `한`은 `U+D55C` 하나로도, 초성·중성·종성 자모 셋(`U+1112 U+1161 U+11AB`)으로도 적을 수 있다. 앞이 NFC, 뒤가 NFD 형식이다. [UAX #15](https://www.unicode.org/reports/tr15/#Canon_Compat_Equivalence)는 한글 음절과 자모 조합을 정준 등가(canonical equivalence)의 예로 들지만, `equals()`는 코드 단위를 비교한다.

```java
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;

public class Normalize {
    public static void main(String[] args) {
        String nfc = "한";
        String nfd = Normalizer.normalize(nfc, Normalizer.Form.NFD);

        for (String s : new String[] { nfc, nfd }) {
            StringBuilder cps = new StringBuilder();
            s.codePoints().forEach(cp -> cps.append(String.format("U+%X ", cp)));
            System.out.printf("%-22s length=%d  UTF-8 %d바이트%n", cps,
                    s.length(), s.getBytes(StandardCharsets.UTF_8).length);
        }
        System.out.println("equals               " + nfc.equals(nfd));
        System.out.println("NFC로 맞춘 뒤 equals  " + nfc.equals(Normalizer.normalize(nfd, Normalizer.Form.NFC)));
    }
}
```

```
$ java -Dstdout.encoding=UTF-8 Normalize.java
U+D55C                 length=1  UTF-8 3바이트
U+1112 U+1161 U+11AB   length=3  UTF-8 9바이트
equals               false
NFC로 맞춘 뒤 equals  true
```

NFD 쪽은 코드 포인트가 셋이라 `length()`가 3이고 UTF-8로 9바이트다. 같은 글자인데 `equals()`는 거짓이다. 출처가 다른 문자열을 비교하거나 키로 쓸 때는 한 형식으로 정규화한 뒤에 비교한다.

사람이 한 글자로 보는 단위에 가장 가까운 것은 [확장 자소 클러스터](https://www.unicode.org/glossary/#extended_grapheme_cluster)(extended grapheme cluster)이고, 경계는 [UAX #29](https://www.unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries)가 정한다. UAX #29도 이것을 근사로 부른다.

> In implementations, the notion of user-perceived characters corresponds to the concept of grapheme clusters. They are a best-effort approximation that can be determined programmatically and unambiguously.

## 구현체별 차이

같은 `a한😀`를 세는 함수들이다.

| 환경 | 호출 | 결과 | 세는 단위 |
|---|---|---|---|
| Java 26.0.1 | `s.length()` | 4 | UTF-16 코드 단위 |
| Java 26.0.1 | `s.codePointCount(0, s.length())` | 3 | 코드 포인트 |
| Node.js 24.15.0 | `s.length` | 4 | UTF-16 코드 단위 |
| Node.js 24.15.0 | `[...s].length` | 3 | 코드 포인트 |
| Python 3.14.4 | `len(s)` | 3 | 코드 포인트 |
| MySQL 8.4.11 | `CHAR_LENGTH()` / `LENGTH()` | 3 / 8 | 문자 / 바이트 |
| PostgreSQL 16.15 | `length()` / `octet_length()` | 3 / 8 | 문자 / 바이트 |

Java와 MySQL은 위 실행 결과다. Python과 Node.js는 셸에서 한 줄씩 돌렸다. 셸의 문자 인코딩을 타지 않게 문자를 이스케이프로 적었다.

```bash
python -c "s = 'a\uD55C\U0001F600'; print(len(s), len(s.encode('utf-8')))"
node -e "const s = 'a\uD55C\u{1F600}'; console.log(s.length, [...s].length)"
```

```
3 8
4 3
```

Python 줄의 둘째 값 8은 UTF-8 바이트 수다. JavaScript의 `length`는 [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/length)이 적은 대로 UTF-16 코드 단위를 세고, 전개 문법 `[...s]`가 쓰는 [문자열 이터레이터](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/Symbol.iterator)는 코드 포인트 단위로 돈다. Python은 [`str`을 코드 포인트의 나열로 정의한다](https://docs.python.org/3.14/library/stdtypes.html#text-sequence-type-str).

PostgreSQL은 상시 랩에서 이 파일을 돌렸다.

```sql
-- 실행: docker compose -f experiments/compose.yml exec -T postgres psql -U postgres -q < experiments/character-encoding-basics/setup.sql
SET client_min_messages = warning;
DROP DATABASE IF EXISTS "character-encoding-basics";
CREATE DATABASE "character-encoding-basics" ENCODING 'UTF8' TEMPLATE template0;
\c character-encoding-basics

SHOW server_version;
SELECT length('a한😀') AS length, octet_length('a한😀') AS octet_length;
```

```bash
docker compose -f experiments/compose.yml exec -T postgres psql -U postgres -q < experiments/character-encoding-basics/setup.sql
```

```
         server_version          
---------------------------------
 16.15 (Debian 16.15-1.pgdg13+2)
(1 row)

 length | octet_length 
--------+--------------
      3 |            8
(1 row)
```

[PostgreSQL 16 문서](https://www.postgresql.org/docs/16/functions-string.html)는 `length()`를 문자 수로, `octet_length()`를 바이트 수로 정의한다.

길이 제한을 검사하는 코드가 Java나 JavaScript에 있고 제한을 거는 컬럼이 DB에 있으면, 보충 문자 하나마다 두 쪽이 센 값이 1씩 어긋난다. 어느 쪽 단위로 검사할지 먼저 정한다.

## 참고

- [RFC 3629 — UTF-8, a transformation format of ISO 10646](https://www.rfc-editor.org/rfc/rfc3629)
- [RFC 2781 — UTF-16, an encoding of ISO 10646](https://www.rfc-editor.org/rfc/rfc2781)
- [Unicode Glossary](https://www.unicode.org/glossary/)
- [UAX #15 — Unicode Normalization Forms](https://www.unicode.org/reports/tr15/)
- [Java 26 `Character` — Unicode Character Representations](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/lang/Character.html#unicode)
- [MySQL 8.4 — The utf8mb3 Character Set](https://dev.mysql.com/doc/refman/8.4/en/charset-unicode-utf8mb3.html)
