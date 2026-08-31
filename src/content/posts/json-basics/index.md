---
title: JSON — 정의와 널리 쓰이게 된 과정
description: JSON의 값 일곱 가지와 문법을 정리하고, XML이 쓰이던 자리를 넘겨받은 과정을 표준 문서의 연표로 따라간다
pubDate: 2026-08-31
category: "웹"
tags: ["기본개념", "JSON", "직렬화"]
---

## 왜 필요한가

프로그램끼리 데이터를 주고받으려면 메모리 안의 값을 텍스트로 바꿔야 한다. 보내는 쪽과 받는 쪽이 다른 언어로 쓰였으면 포인터도 클래스도 건널 수 없고, 남는 것은 바이트 열뿐이다. 이 바이트 열의 문법을 정한 것이 데이터 교환 포맷이다.

JSON은 그 문법을 값 일곱 가지와 구두점 몇 개로 끝낸다. [ECMA-404](https://ecma-international.org/publications-and-standards/standards/ecma-404/)의 표현으로는 "a syntax of braces, brackets, colons, and commas"다. 스키마도, 네임스페이스도, 속성과 자식 요소의 구분도 없다. 이 좁은 범위가 JSON이 판단을 미룬 자리이자 널리 쓰이게 된 이유다.

## 용어 정리

- **JSON 텍스트(JSON text)**: 직렬화된 값 하나. [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)는 "A JSON text is a serialized value"라고 정의한다. 객체나 배열이 아니어도 되고 `42` 하나도 유효한 JSON 텍스트다.
- **값(value)**: 객체, 배열, 숫자, 문자열, `true`, `false`, `null` 중 하나.
- **멤버(member)**: 객체 안의 이름-값 쌍. 이름은 반드시 문자열이다.
- **직렬화(serialization)**: 메모리의 값을 텍스트로 바꾸는 일. 반대는 역직렬화(deserialization)다.

## 핵심 정리

| 값 | 표기 | 규칙 |
|---|---|---|
| 객체(object) | `{"name": "kim", "age": 30}` | 이름-값 쌍의 모음. 이름은 큰따옴표 문자열이어야 한다 |
| 배열(array) | `[1, 2, 3]` | 값의 나열. 원소 타입이 같을 필요는 없다 |
| 문자열(string) | `"hello"` | 큰따옴표만. 홑따옴표는 문법 위반이다 |
| 숫자(number) | `-1.5e3` | 십진 표기 하나. 정수와 실수를 구분하지 않는다 |
| `true` | `true` | 소문자 고정. 대문자 `True`는 문법 위반이다 |
| `false` | `false` | 소문자 고정 |
| `null` | `null` | 값 없음 |

JSON에 없는 것은 주석, 후행 쉼표, 홑따옴표, 따옴표 없는 키, `NaN`과 `Infinity`, 날짜 타입이다.

## 항목별 설명

**숫자에는 타입이 없다.** JSON의 숫자는 십진수 표기 그 자체이고, 그것이 정수인지 부동소수점인지는 정하지 않는다. ECMA-404는 이유를 이렇게 밝힌다. "JSON is agnostic about the semantics of numbers. (...) JSON instead offers only the representation of numbers that humans use: a sequence of digits." 언어마다 다른 수 타입을 통일하는 대신, 숫자를 어떻게 해석할지를 받는 쪽에 넘긴 것이다. 이 결정이 파서마다 다른 결과를 만든다.

**문자열은 유니코드 코드 포인트의 나열이다.** 인코딩은 UTF-8을 쓰고(RFC 8259 8.1절), `\u0041`처럼 네 자리 16진수로 이스케이프할 수도 있다. BMP 밖의 문자를 이스케이프할 때는 `\uD83D\uDE00`처럼 서로게이트 쌍, 즉 `\u` 이스케이프 두 개로 적는다.

**날짜 타입이 없다.** 그래서 대부분 `"2026-08-31T09:00:00Z"` 같은 ISO 8601 문자열로 싣고, 파싱 후 각 언어의 날짜 타입으로 바꾼다. 타임스탬프 정수를 쓰기도 하는데 초 단위인지 밀리초 단위인지는 JSON이 알려주지 않는다.

**주석이 없다.** 설정 파일에서 가장 자주 불편해지는 지점이다. 주석을 허용한 JSON5나 JSONC는 JSON이 아니라 별개 포맷이고, 표준 문법만 받는 파서는 이들을 거부한다.

## 예시

`user.json`은 다음과 같다.

```json
{
  "id": 7,
  "name": "김철수",
  "active": true,
  "scores": [90, 85.5, null],
  "profile": { "city": "서울", "joinedAt": "2026-08-31" }
}
```

파싱하면 각 언어의 기본 타입으로 바로 대응된다.

```
>>> import json
>>> json.loads(open("user.json", encoding="utf-8").read())
{'id': 7, 'name': '김철수', 'active': True, 'scores': [90, 85.5, None], 'profile': {'city': '서울', 'joinedAt': '2026-08-31'}}
```

```
> JSON.parse(fs.readFileSync("user.json", "utf-8"))
{
  id: 7,
  name: '김철수',
  active: true,
  scores: [ 90, 85.5, null ],
  profile: { city: '서울', joinedAt: '2026-08-31' }
}
```

객체는 dict, 배열은 list, `true`는 `True`, `null`은 `None`이 된다. JSON의 값 종류가 대부분 언어에 이미 있는 타입이라 매핑 규칙을 따로 선언할 필요가 없다.

## 널리 쓰이게 된 과정

표준 문서만 놓고 보면 연표는 이렇다.

| 시점 | 일 |
|---|---|
| 2001년 4월 | Douglas Crockford와 Chip Morningstar가 첫 JSON 메시지를 주고받는다. 같은 해 json.org가 열린다 |
| 2005년 12월 | Yahoo!가 일부 웹 서비스를 JSON으로 제공하기 시작한다 |
| 2006년 7월 | [RFC 4627](https://datatracker.ietf.org/doc/rfc4627/)이 `application/json` 미디어 타입을 등록한다. 표준이 아닌 Informational 문서다 |
| 2009년 | ECMAScript 5판에 `JSON.parse`와 `JSON.stringify`가 들어간다 |
| 2013년 10월 | Ecma International이 ECMA-404 1판을 낸다 |
| 2014년 3월 | RFC 7159가 RFC 4627을 대체한다 |
| 2017년 11월 | ISO/IEC 21778이 나온다 |
| 2017년 12월 | RFC 8259가 STD 90이 되고, ECMA-404 2판이 나온다 |

**브라우저가 이미 파서를 갖고 있었다.** JSON 텍스트는 JavaScript의 객체 리터럴 표기에서 나왔다. 그래서 초기에는 응답 문자열을 `eval('(' + text + ')')`처럼 괄호로 감싸 넣는 것만으로 객체가 됐고, 서버가 XML을 보내면 필요했던 DOM 순회 코드가 사라졌다. 괄호가 필요한 이유는 `{`로 시작하는 텍스트가 문(statement) 자리에서 객체가 아니라 블록으로 읽히기 때문이다. `eval`은 받은 문자열을 코드로 실행하므로 위험한데, 이 문제는 2009년 ES5가 `JSON.parse`를 표준에 넣으면서 정리됐다.

**언어 타입으로 옮기는 층이 필요 없다.** XML은 요소, 속성, 텍스트 노드, 네임스페이스로 이루어진 트리이고, 이것을 객체로 바꾸려면 무엇을 필드로 볼지 정하는 규칙이 따로 있어야 한다. JSON은 객체와 배열이 그대로 대응되므로 그 층이 없다. 위 예시에서 dict가 바로 나온 것이 그 결과다.

XML을 밀어낸 결정적 사건 하나를 짚기는 어렵다. 서버가 페이지 전체 대신 데이터 조각만 돌려주는 방식이 2005년 Ajax라는 이름을 얻으며 퍼졌고, 그 데이터의 포맷이 XML에서 JSON으로 옮겨간 것으로 보인다.

## 혼동하기 쉬운 것

**"JSON은 JavaScript의 부분집합이다"는 2019년부터, 그것도 표현식 자리에서만 맞는 말이다.** JSON 문자열 안에는 U+2028(LINE SEPARATOR)과 U+2029(PARAGRAPH SEPARATOR)를 이스케이프 없이 넣을 수 있지만, ES2018까지의 JavaScript 문자열 리터럴에는 넣을 수 없었다. 유효한 JSON인데 JavaScript 표현식 자리에 그대로 넣으면 문법 오류가 나는 텍스트가 존재했다는 뜻이다. [JSON superset 제안](https://github.com/tc39/proposal-json-superset)이 ES2019에 반영되면서 이 차이는 사라졌다. 표현식 자리라는 단서는 그대로 남는다. 앞서 본 대로 `{`로 시작하는 JSON은 문 자리에서 블록으로 읽힌다.

**JSON과 JSON을 닮은 포맷은 다르다.** JSON5와 JSONC는 주석과 후행 쉼표를 허용하고, 그 확장을 실제로 쓴 문서는 JSON 파서가 거부한다. JSONL/NDJSON은 성격이 다르다. 각 줄은 그 자체로 유효한 JSON이고, 파서가 거부하는 것은 여러 줄을 한 번에 넣었을 때다.

**중복된 키는 문법 위반이 아니다.** 두 표준 모두 이름이 겹친 객체를 유효한 JSON으로 두고, 그때 어떤 값을 남길지는 정하지 않는다. 파서별로 갈리는 결과는 아래 파고들기 글에서 확인한다.

## 더 깊이

같은 JSON 텍스트를 넣어도 파서마다 다른 값이 나오는 지점은 [같은 JSON, 다른 값 — 명세가 파서에 남긴 자리](/posts/json-parser-differences/)에서 다룬다.

## 참고

- [RFC 8259 — The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
- [ECMA-404 — The JSON Data Interchange Syntax](https://ecma-international.org/publications-and-standards/standards/ecma-404/)
- [json.org](https://www.json.org/json-ko.html)
- [Wikipedia — JSON](https://en.wikipedia.org/wiki/JSON)
