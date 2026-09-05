---
title: 같은 JSON, 다른 값 — 명세가 파서에 남긴 자리
description: 표준이 문법만 정하고 의미를 정하지 않은 지점을 짚고, 같은 JSON 텍스트를 Python과 Node.js에 넣어 결과가 갈리는 것을 확인한다
pubDate: 2026-08-31
category: "웹"
tags: ["파고들기", "JSON", "직렬화"]
---

## 전제

JSON의 값 종류와 문법은 [JSON — 정의와 널리 쓰이게 된 과정](/posts/json-basics/)에서 다뤘다. 이 글은 그 문법을 통과한 텍스트가 파서에 따라 다른 값이 되는 지점을 본다.

## 풀리지 않는 질문

`{"a": 1, "a": 2}`는 유효한 JSON이다. 파싱 결과가 무엇인지는 표준을 아무리 읽어도 나오지 않는다. `12345678901234567890`도 유효한 JSON이고, Python은 이 값을 그대로 돌려주지만 Node.js는 `12345678901234567000`을 돌려준다. 둘 다 표준을 어긴 것이 아니다.

표준이 정하지 않은 자리와 표준을 어긴 자리는 다르다. 이 글은 앞의 것을 주로 보되, 뒤의 것도 하나 나온다.

이런 자리가 생긴 이유는 JSON 표준이 문법만 정의하기 때문이다. 어떤 텍스트가 JSON인지는 정하되, 그 텍스트를 어떤 값으로 만들지는 정하지 않는다.

## 핵심 개념

JSON에는 표준 문서가 둘 있고, 둘은 범위가 다르다.

| 문서 | 범위 | 성격 |
|---|---|---|
| [ECMA-404](https://ecma-international.org/publications-and-standards/standards/ecma-404/) 2판 (2017) | 문법만 | 무엇이 유효한 JSON 텍스트인지 |
| [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) (2017, STD 90) | 문법 + 상호운용성 권고 | 미디어 타입 등록과 SHOULD 수준의 권고 |

ECMA-404는 1절에서 범위를 못박는다. "The goal of this specification is only to define the syntax of valid JSON texts. Its intent is not to provide any semantics or interpretation of text conforming to that syntax." 값의 의미를 정하는 것은 처리기(processor)나 JSON을 쓰는 개별 명세의 몫이라는 뜻이다.

RFC 8259는 여기에 상호운용성 권고를 얹지만, 권고는 MUST가 아니라 SHOULD다. 따르지 않아도 표준 위반이 아니다.

## 동작 원리

문법을 통과한 뒤에도 결과가 갈리는 자리가 넷이다. 앞의 셋은 파서가 스스로 정하는 것이고, 마지막 하나는 JSON과 JavaScript의 문법 차이에서 온다.

**중복된 이름.** ECMA-404는 "The JSON syntax does not impose any restrictions on the strings used as names, does not require that name strings be unique, and does not assign any significance to the ordering of name/value pairs"라고 쓴다. 이름이 겹쳐도 문법 위반이 아니다. RFC 8259는 "The names within an object SHOULD be unique"라고 한 단계 더 나가지만, 겹쳤을 때의 결과는 정하지 않고 실제 구현을 열거만 한다. "Many implementations report the last name/value pair only. Other implementations report an error or fail to parse the object, and some implementations report all of the name/value pairs, including duplicates."

**숫자의 정밀도.** JSON 문법의 숫자는 자릿수 제한이 없다. 어떤 수 타입에 담을지는 파서가 정한다. RFC 8259 6절은 표준을 바꾸는 대신 권고를 남겼다. "Since software that implements IEEE 754 binary64 (double precision) numbers [IEEE754] is generally available and widely used, good interoperability can be achieved by implementations that expect no more precision or range than these provide (...)" 배정밀도 부동소수점에 들어가는 범위를 벗어나지 말라는 말이지, 벗어난 텍스트가 무효라는 말이 아니다.

**문법 밖의 수.** RFC 8259는 "Numeric values that cannot be represented in the grammar below (such as Infinity and NaN) are not permitted"라고 못박는다. 여기서 입력과 출력의 취급이 갈린다. 9절 Parsers는 "A JSON parser MUST accept all texts that conform to the JSON grammar. A JSON parser MAY accept non-JSON forms or extensions"라고 해서, 문법 밖의 텍스트를 받아주는 것까지는 허용한다. 반면 10절 Generators는 "A JSON generator produces JSON text. The resulting text MUST strictly conform to the JSON grammar", 이 두 문장이 전부다. `NaN`을 받아들이는 파서는 표준 안에 있고, `NaN`을 출력하는 직렬화기는 표준 밖에 있다.

**JavaScript 문자열 리터럴과의 어긋남.** JSON 문자열 안에는 U+2028(LINE SEPARATOR)과 U+2029(PARAGRAPH SEPARATOR)를 이스케이프 없이 넣을 수 있다. ES2018까지의 JavaScript 문자열 리터럴에는 넣을 수 없었다. [tc39/proposal-json-superset](https://github.com/tc39/proposal-json-superset)은 이 상태를 "JSON strings can contain unescaped U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR characters while ECMAScript strings cannot"이라고 요약한다. 이 제안이 ES2019에 들어가면서 이 차이는 사라졌다. 다만 상위집합이 성립하는 자리는 표현식과 문자열 리터럴이다. `{`로 시작하는 JSON 텍스트는 문(statement) 자리에서 객체가 아니라 블록으로 읽혀 지금도 문법 오류다.

## 직접 확인

Python 3.14.4와 Node.js v24.15.0에 같은 텍스트를 넣는다.

```python
# probe.py
import json, sys

print("python", sys.version.split()[0])
print("중복 키   :", json.loads('{"a": 1, "a": 2}'))
print("큰 정수   :", json.loads("12345678901234567890"))
print("타입      :", type(json.loads("12345678901234567890")).__name__)
print("과학 표기 :", json.loads("1E400"))
print("소수      :", json.loads("0.1") + json.loads("0.2"))
print("최상위 값 :", json.loads("42"), json.loads('"hello"'), json.loads("null"))
print("NaN 출력  :", json.dumps(float("nan")), json.dumps(float("inf")))
print("NaN 입력  :", json.loads("NaN"))
```

```javascript
// probe.js
console.log("node", process.version);
console.log("중복 키   :", JSON.parse('{"a": 1, "a": 2}'));
console.log("큰 정수   :", JSON.parse("12345678901234567890"));
console.log("과학 표기 :", JSON.parse("1E400"));
console.log("소수      :", JSON.parse("0.1") + JSON.parse("0.2"));
console.log("최상위 값 :", JSON.parse("42"), JSON.parse('"hello"'), JSON.parse("null"));
console.log("NaN 출력  :", JSON.stringify(NaN), JSON.stringify(Infinity));
try {
  JSON.parse("NaN");
} catch (e) {
  console.log("NaN 입력  :", e.constructor.name + ":", e.message);
}
```

실행 결과다.

```
$ python probe.py
python 3.14.4
중복 키   : {'a': 2}
큰 정수   : 12345678901234567890
타입      : int
과학 표기 : inf
소수      : 0.30000000000000004
최상위 값 : 42 hello None
NaN 출력  : NaN Infinity
NaN 입력  : nan

$ node probe.js
node v24.15.0
중복 키   : { a: 2 }
큰 정수   : 12345678901234567000
과학 표기 : Infinity
소수      : 0.30000000000000004
최상위 값 : 42 hello null
NaN 출력  : null null
NaN 입력  : SyntaxError: "NaN" is not valid JSON
```

갈리는 지점을 정리하면 이렇다.

| 입력 | Python 3.14.4 | Node.js v24.15.0 |
|---|---|---|
| `{"a": 1, "a": 2}` | 뒤의 값 (`2`) | 뒤의 값 (`2`) |
| `12345678901234567890` | 임의 정밀도 정수 그대로 | 배정밀도로 반올림된 `12345678901234567000` |
| `1E400` | `inf` | `Infinity` |
| `NaN` 직렬화 | `NaN` (10절 위반) | `null` |
| `NaN` 파싱 | 값 `nan`으로 받아들임 | `SyntaxError` |

두 파서 모두 중복 키에서 마지막 값을 남기지만, 이것은 표준이 시킨 결과가 아니라 두 구현이 같은 선택을 한 결과다. 큰 정수에서 갈리는 이유는 Python의 정수에 자릿수 제한이 없고 JavaScript의 `number`가 IEEE 754 배정밀도이기 때문이다. `1E400`은 배정밀도 범위를 넘어 양쪽 모두 무한대가 되는데, 둘 다 오류를 내지 않는다.

`NaN`은 표에서 유일하게 표준 위반이 걸리는 행이다. Python이 기본값으로 내보내는 `NaN`은 10절이 요구하는 문법에 맞지 않고, 그렇게 만든 텍스트를 Node.js는 거부한다. `json.dumps(float("nan"), allow_nan=False)`로 막으면 `ValueError: Out of range float values are not JSON compliant: nan`이 난다. 다른 쪽 방향인 `json.loads("NaN")`은 9절의 MAY가 허용하는 확장이다.

U+2028은 파싱과 재출력을 모두 통과한다.

```javascript
const sep = String.fromCodePoint(0x2028);
const text = '{"msg": "a' + sep + 'b"}';   // 이스케이프하지 않은 U+2028
const parsed = JSON.parse(text);
console.log("코드 포인트:", [...parsed.msg].map(c => c.codePointAt(0).toString(16)).join(" "));
console.log("재출력에 raw U+2028 그대로:", JSON.stringify(parsed).includes(sep));
```

```
코드 포인트: 61 2028 62
재출력에 raw U+2028 그대로: true
```

`JSON.stringify`는 U+2028을 이스케이프하지 않는다. 이 출력을 그대로 JavaScript 표현식 자리에 끼워 넣으면 ES2018까지의 엔진에서는 문법 오류가 났다. 서버가 만든 JSON을 HTML의 `<script>` 안에 인라인으로 심는 코드가 이 경로를 밟는다.

## 경계 조건

**64비트 정수 ID.** 서버가 64비트 정수 ID를 숫자로 내보내면 JavaScript 쪽에서 배정밀도로 반올림되어 다른 ID가 된다. JavaScript의 `number`가 오차 없이 담는 정수 상한은 `Number.MAX_SAFE_INTEGER`, 즉 2^53 - 1이고 64비트 ID는 이를 넘는다. 위 실험의 `12345678901234567890`이 자릿수가 비슷한 예다. Twitter가 2010년 트윗 ID를 64비트 [Snowflake](https://blog.x.com/engineering/en_us/a/2010/announcing-snowflake) ID로 바꾸면서 이 문제가 드러났고, 그 뒤 API 응답에 문자열 필드 `id_str`이 `id`와 함께 실렸다. 현재 [X API v2](https://docs.x.com/x-api/fundamentals/data-dictionary)는 `id`를 문자열로 낸다.

**금액과 소수.** `0.1 + 0.2`가 `0.30000000000000004`이 되는 것은 JSON이 아니라 배정밀도 부동소수점의 성질이다. JSON 텍스트에는 `0.1`이 정확히 적혀 있으므로, 금액은 문자열이나 최소 단위 정수로 싣고 파싱 후 십진 타입으로 바꾸는 편이 안전하다.

**중복 키.** 검증기와 처리기가 다른 값을 골라 쓰면 검증을 통과한 요청이 다른 뜻으로 실행될 수 있다. 두 단계가 같은 파서를 쓰는지, 아니면 입력 단계에서 중복 키를 거부하는지를 확인해야 한다.

## 대안과 트레이드오프

| 방법 | 얻는 것 | 잃는 것 |
|---|---|---|
| 큰 수와 금액을 문자열로 싣기 | 파서 정밀도와 무관해진다 | 받는 쪽에서 변환 코드가 필요하다 |
| [JSON Schema](https://json-schema.org/)로 입력 검증 | 타입과 범위를 명시할 수 있다 | 중복 키처럼 파싱 단계에서 이미 결정된 것은 막지 못한다 |
| 파서 옵션으로 타입 지정 (`json.loads(text, parse_float=Decimal)`) | 소수 정밀도를 지킨다 | 언어마다 옵션이 달라 받는 쪽마다 따로 설정해야 한다 |
| 이진 포맷(Protocol Buffers 등)으로 교체 | 타입이 스키마에 못박힌다 | 사람이 읽을 수 없고 스키마 배포가 필요하다 |

## 참고

- [RFC 8259 — The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
- [ECMA-404 — The JSON Data Interchange Syntax](https://ecma-international.org/publications-and-standards/standards/ecma-404/)
- [tc39/proposal-json-superset](https://github.com/tc39/proposal-json-superset)
- [Python `json` — Infinite and NaN Number Values](https://docs.python.org/3/library/json.html#infinite-and-nan-number-values)
