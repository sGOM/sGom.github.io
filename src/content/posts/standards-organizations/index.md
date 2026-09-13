---
title: 표준화 기구 14곳 — 누가 무엇을 정하는가
description: 코딩하며 마주치는 표준을 내는 기관과 그 표준이 기대는 곳 14군데를 정리하고, 회원 자격과 합의 방식의 차이가 판본 방식과 공개 여부로 어떻게 드러나는지 본다
pubDate: 2026-09-13
category: "컴퓨터공학"
tags: ["기본개념", "표준", "명세"]
---

## 왜 헷갈리는가

같은 층위로 보이는 이름들이 실제로는 다른 종류다. JSON을 정의한 문서는 [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)와 [ECMA-404](https://ecma-international.org/publications-and-standards/standards/ecma-404/) 둘이고 둘 다 유효하다. HTML은 W3C가 내다가 지금은 WHATWG가 낸다. 부동소수점은 IEEE가 정했는데 ISO/IEC 60559라는 번호로도 팔린다.

기관마다 회원 자격과 합의 방식이 다르고, 그 차이가 두 가지로 드러난다. 명세가 판본으로 끊기는지 계속 고쳐지는지, 그리고 돈을 내야 읽을 수 있는지다. 아래 14곳에는 IANA처럼 표준을 만들지는 않지만 표준이 기대는 곳도 함께 넣었다. 기관의 승인 없이 굳은 사실상 표준은 다루지 않는다.

## 용어 정리

- **표준(standard)**: 합의 절차를 거쳐 문서로 굳힌 규격.
- **사실상 표준(de facto standard)**: 기관의 승인 없이 널리 쓰여 기준이 된 것. Semantic Versioning, Markdown이 여기 든다.
- **Living Standard**: 판본을 끊지 않고 계속 고치는 명세. WHATWG가 쓰는 방식이다.
- **등록부(registry)**: 표준이 값 목록을 직접 담지 않고 위임한 목록. `application/json` 같은 이름이 어디에 있는지는 명세가 아니라 등록부가 답한다.
- **국가 표준기관(NSB)**: 한 나라를 대표해 ISO에 참여하는 기관. 한국은 국가기술표준원(KATS)이다.

## 핵심 정리

| 기관 | 성격 | 대표 산출물 |
|---|---|---|
| **ISO**<br>국제표준화기구 | 나라마다 표준기관(NSB) 한 곳이 회원으로 참여하는 민간 연합체. 국가 단위 투표로 정한다 | [ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html) 날짜와 시간을 문자열로 적는 규칙<br>[ISO 3166](https://www.iso.org/iso-3166-country-codes.html) 국가와 행정구역에 붙이는 코드 |
| **IEC**<br>국제전기기술위원회 | 전기·전자 분야를 맡는다. 1906년 설립으로 ISO(1947년)보다 앞선다 | IEC 80000-13 KiB, MiB 같은 [2진 접두어](https://www.iec.ch/prefixes-binary-multiples). 1999년 IEC 60027-2 Amendment 2에서 도입돼 이리로 옮겨왔다<br>[IEC 61508](https://webstore.iec.ch/en/publication/5515) 전자 제어 시스템이 고장 나도 사람이 다치지 않게 하는 요구사항 |
| **ISO/IEC JTC 1** | 두 기관의 영역이 겹치는 IT를 맡기려 만든 [합동 기술위원회](https://www.iso.org/committee/45020.html). IT 분야에서 `ISO/IEC`가 붙은 표준은 대개 여기 소관이다 | [ISO/IEC 9899](https://www.iso.org/standard/82075.html) C 언어의 문법과 표준 라이브러리<br>[ISO/IEC 9075-1](https://www.iso.org/standard/76583.html) SQL의 틀을 정의하는 1부 |
| **IETF**<br>국제 인터넷 표준화 기구 | 회원 자격이 없고 개인이 메일링 리스트로 참여한다. 상위 등급으로 올리려면 독립 구현들이 실제로 맞물려 돌아야 한다 | [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) HTTP 메서드·상태 코드·헤더의 의미<br>[RFC 8446](https://www.rfc-editor.org/rfc/rfc8446) TLS 1.3 핸드셰이크와 암호 협상 |
| **IANA** | 표준이 아니라 표준이 참조하는 값의 목록을 관리한다. ICANN 산하에서 운영한다 | [미디어 타입 등록부](https://www.iana.org/assignments/media-types/media-types.xhtml) `application/json` 같은 타입 이름의 원본<br>[tz database](https://www.iana.org/time-zones) `Asia/Seoul`의 UTC 오프셋 변경 이력 |
| **W3C**<br>월드 와이드 웹 컨소시엄 | 회원사가 회비를 내고 참여한다. 초안에서 권고안(Recommendation)까지 단계를 밟는다 | [WCAG 2.2](https://www.w3.org/TR/WCAG22/) 웹 콘텐츠 접근성 판정 기준<br>[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/) 그 시점에 안정된 것으로 본 CSS 모듈 목록 |
| **WHATWG** | 브라우저 벤더가 운영하고 변경은 GitHub에서 이뤄진다. 판본을 끊지 않는 Living Standard 방식이다 | [HTML Standard](https://html.spec.whatwg.org/multipage/) 요소, 파싱 규칙, 브라우저가 노출하는 API<br>[URL Standard](https://url.spec.whatwg.org/) 브라우저가 실제로 URL을 해석하는 절차 |
| **IEEE SA** | 전기전자기술자협회의 표준 부문. 하드웨어와 저수준 규격이 많다 | [IEEE 754](https://standards.ieee.org/standard/754-2019.html) 부동소수점의 비트 배치와 연산 결과<br>[IEEE 802.11](https://standards.ieee.org/ieee/802.11/11852/) 무선 LAN의 매체 접근 제어와 물리 계층 |
| **Ecma International** | 유럽에서 출발한 민간 표준기관. 승인 주기가 짧다 | [ECMA-262](https://ecma-international.org/publications-and-standards/standards/ecma-262/) JavaScript 언어<br>[ECMA-404](https://ecma-international.org/publications-and-standards/standards/ecma-404/) JSON의 문법 |
| **Unicode Consortium** | 문자 처리를 전담한다. ISO/IEC 10646과 코드포인트를 맞춰 간다 | [Unicode Standard](https://www.unicode.org/versions/latest/) 문자 집합, 인코딩, 정규화, 문자소 경계<br>[CLDR](https://cldr.unicode.org/) 언어권별 날짜·숫자·정렬 서식 데이터 |
| **The Open Group** | UNIX 상표를 가진 컨소시엄. IEEE와 POSIX를 공동 발행한다 | [POSIX.1-2024](https://pubs.opengroup.org/onlinepubs/9799919799/) 셸, 유틸리티, 시스템 호출이 지켜야 할 동작 |
| **NIST** | 미국 상무부 산하 기관. 미국 연방 기준이지만 바깥에서도 인용된다 | [FIPS 197](https://csrc.nist.gov/pubs/fips/197/final) AES 블록 암호<br>[SP 800-63B](https://csrc.nist.gov/pubs/sp/800/63/b/4/final) 비밀번호와 다중 인증 수단의 요구사항 |
| **OASIS** | 기업이 회원인 컨소시엄. XML 계열과 메시징 프로토콜을 다룬다 | [SAML 2.0](https://docs.oasis-open.org/security/saml/v2.0/saml-core-2.0-os.pdf) SSO에서 신원 정보를 주고받는 형식<br>[MQTT 5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) 저사양 기기용 발행·구독 프로토콜 |
| **OpenID Foundation** | OpenID 인증을 표준화하려고 2007년에 세운 비영리 재단 | [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html) OAuth 2.0 위에 신원 계층을 올려 ID 토큰을 발급하고 검증하는 절차 |

## 항목별 설명

### ISO, IEC, JTC 1이 갈라진 이유

ISO와 IEC는 담당 분야가 다르다. IEC가 1906년에 전기 분야를 먼저 맡았고, ISO가 1947년에 나머지를 맡았다. 컴퓨터는 어느 쪽으로도 볼 수 있어 경계에 걸린다. 두 기관이 각자 IT 표준을 내면 충돌하므로 1987년에 합동 기술위원회 JTC 1을 만들어 IT를 통째로 옮겼다.

그래서 C 언어 표준의 정식 이름은 ISO 9899가 아니라 ISO/IEC 9899다. 반대로 날짜 표기(ISO 8601)나 국가 코드(ISO 3166)에는 IEC가 붙지 않는다. IT 표준이 아니라 각각 TC 154와 TC 46이라는 다른 기술위원회 소관이기 때문이다. 다만 접두사만으로 위원회가 확정되지는 않는다. 시험·교정기관의 능력 요구사항을 정한 ISO/IEC 17025처럼 JTC 1 밖에서 두 기관이 함께 내는 표준도 있다.

### IETF의 합의가 다른 점

IETF에는 회원이 없다. 가입 절차도 회비도 없고 메일링 리스트에 글을 쓰면 참여자다. 표결도 하지 않는다. 반대 의견이 남아 있어도 기술적 근거가 해소됐다고 의장이 판단하면 진행하는 [rough consensus](https://www.rfc-editor.org/rfc/rfc7282) 방식이다.

대신 구현으로 검증한다. RFC를 Internet Standard 등급으로 올리려면 서로 독립적으로 만든 구현들이 실제로 맞물려 동작한 경험이 있어야 한다. 문서가 먼저 완성되고 구현이 따라오는 순서가 아니다.

### IANA는 표준을 만들지 않는다

IANA는 명세가 비워둔 자리를 채운다. HTTP의 `Content-Type`에 무엇을 쓸 수 있는지 RFC 9110은 나열하지 않는다. 목록이 계속 늘어나므로 명세에 박아두면 새 타입이 생길 때마다 문서를 고쳐야 한다. 그래서 명세는 IANA 등록부를 가리키고, 새 타입은 문서 개정 없이 등록부에만 추가된다.

포트 번호, HTTP 상태 코드, 문자 인코딩 이름도 같은 구조다. 시간대 데이터베이스는 성격이 조금 다른데, 각국 정부가 서머타임과 오프셋을 바꿀 때마다 갱신되는 데이터라 명세로 굳힐 수가 없다.

## 예시

요청 하나에 여러 기관의 문서가 동시에 걸린다.

```
https://api.example.com/users?name=%EA%B9%80
```

이 주소로 `curl -i` 요청을 보냈다고 가정하고, 설명에 필요한 조각만 남긴 화면이다. 실제 서버에서 받은 응답이 아니다. HTTP/2 자체에는 상태 줄이 없고 헤더와 본문을 빈 줄로 가르지도 않는다. `:status` 의사 헤더와 HEADERS·DATA 프레임을 curl이 읽을 수 있는 형태로 되돌린 것이다.

```
HTTP/2 200
content-type: application/json
date: Sun, 13 Sep 2026 04:12:33 GMT

{"id":1,"name":"김","createdAt":"2026-09-13T04:12:33Z"}
```

| 조각 | 정한 문서 | 기관 |
|---|---|---|
| `https://`와 `?name=`의 문법 | RFC 3986, URL Standard | IETF, WHATWG |
| `김`을 `ea b9 80` 세 바이트로 보는 것 | Unicode Standard | Unicode Consortium |
| 그 바이트를 `%EA%B9%80`으로 적는 것 | RFC 3986 | IETF |
| `https://`가 부르는 TLS 핸드셰이크(1.3인 경우) | RFC 8446 | IETF |
| `HTTP/2 200` 줄이 되돌린 `:status`와 프레임 분할 | RFC 9113 | IETF |
| `200`의 의미와 헤더 문법 | RFC 9110 | IETF |
| `application/json`이라는 이름 | 미디어 타입 등록부 | IANA |
| `Sun, 13 Sep 2026 04:12:33 GMT` 형식 | RFC 9110 | IETF |
| 본문 `{ }` `"` `,` 의 문법 | RFC 8259, ECMA-404 | IETF, Ecma |
| `2026-09-13T04:12:33Z` 형식 | ISO 8601, RFC 3339 | ISO, IETF |

`date` 헤더와 본문의 `createdAt`은 같은 시각인데 형식이 다르다. HTTP 헤더의 날짜는 RFC 9110이 규정한 고정 형식이라 요일과 영문 월 이름이 들어가고, 본문의 날짜는 애플리케이션이 고른 ISO 8601 표기다. HTTP는 초기 이메일 헤더 형식을 물려받았고 그 자리를 바꾸면 기존 구현이 깨지므로 그대로 남았다.

표에 RFC 3339를 함께 적은 것은 ISO 8601 중 인터넷에서 쓸 부분만 좁혀 고정한 프로파일이어서다.

조각 열 개에 여섯 기관이 걸렸다. 한 기관이 웹 전체를 정하지 않는다는 것이 이 표의 요지다.

## 혼동하기 쉬운 것

**W3C는 이제 HTML을 정하지 않는다.** 2019년 W3C와 WHATWG가 합의해 HTML과 DOM은 WHATWG의 Living Standard 하나로 일원화됐다. `w3.org/TR`에 남아 있는 HTML 5.x 문서는 그 이전 판본이라 검색으로 먼저 걸려도 현행이 아니다. CSS와 접근성은 여전히 W3C 소관이므로 웹 표준을 통째로 한 기관에 귀속시킬 수 없다.

**판본을 끊는 곳과 끊지 않는 곳이 갈린다.** W3C 권고안은 날짜로 판이 끊기고 ISO 표준은 `:2025`처럼 연도가 번호에 붙는다. WHATWG 명세는 어느 쪽도 아니라 오늘 읽은 문장이 다음 달에 바뀌어 있을 수 있다. 그래서 Living Standard를 인용할 때는 조회한 날짜를 함께 적어야 한다.

**하나의 표준에 이름이 둘 붙는다.** IEEE 754는 [ISO/IEC 60559](https://www.iso.org/standard/80985.html)로도 발행되고, WCAG 2.2는 ISO/IEC 40500:2025다([W3C 공지](https://www.w3.org/WAI/news/2025-10-21/wcag22-iso), [ISO 카탈로그](https://www.iso.org/standard/91029.html)). 다른 기관이 만든 표준을 ISO가 내용 변경 없이 받아 승인하는 절차가 있어서다. 그러나 ISO 번호가 판을 따라오지는 않는다. WCAG 2.1은 2018년에 권고안이 됐지만 대응 ISO 번호가 발행된 적은 없고, ISO/IEC 40500은 2012년부터 2025년까지 줄곧 WCAG 2.0을 가리켰다. 어느 번호로 인용하든 판까지 함께 적어야 하는 이유다.

**JSON을 정의한 문서가 둘인 것은 담는 범위가 달라서다.** ECMA-404는 문법만 정한다. RFC 8259는 같은 문법에 상호운용 지침을 더해, 객체에 같은 이름이 두 번 나올 때와 배정밀도로 표현되지 않는 수를 만날 때 무엇이 갈리는지를 적는다. 파서마다 결과가 달라지는 자리가 대개 후자다.

**RFC 번호가 붙었다고 표준은 아니다.** RFC는 IETF를 포함한 여러 스트림이 함께 쓰는 일련번호이고, 그중 표준화 트랙에 있는 것은 일부다. 나머지는 정보 제공(Informational), 실험(Experimental), 현행 모범 사례(BCP), 폐기(Historic)로 분류되고 만우절 농담 문서도 번호를 받는다. 인용하기 전에 문서 첫머리의 Category를 본다.

**읽을 수 있는지가 기관마다 다르다.** IETF, W3C, WHATWG, Unicode, The Open Group, Ecma, IANA, NIST, OASIS, OpenID Foundation의 문서는 전문이 무료로 공개된다. 유료인 곳은 ISO, IEC, IEEE 셋이고, JTC 1의 산출물도 ISO/IEC 이름으로 나오므로 유료다. 위 표에서 ISO·IEC 카탈로그로 가는 링크가 본문 대신 가격과 초록만 보여주는 이유다. IEEE에는 예외가 있어 802 계열은 발행 6개월 뒤 GET Program으로 무료 공개된다. 유료인 쪽은 원문 대신 위원회 작업 초안을 인용하는 관행이 생겼는데, C23이면 N3220이 그 자리를 대신한다.

## 더 깊이

이 글의 표에 나온 표준을 하나씩 파고든 글이다.

- [JSON — 정의와 널리 쓰이게 된 과정](/posts/json-basics/) · [같은 JSON, 다른 값 — 명세가 파서에 남긴 자리](/posts/json-parser-differences/)
- [double의 52비트, bias 1023, 17자리는 어디서 나오는가](/posts/ieee754-double-numbers/)
- [POSIX가 정의한 줄과 파일 끝 개행](/posts/posix-line-and-trailing-newline/)
- [OAuth2 기본개념 — 네 역할과 토큰 발급 흐름](/posts/oauth2-basics/)

## 참고

- [IETF](https://www.ietf.org/) / [RFC Editor](https://www.rfc-editor.org/)
- [W3C 표준 목록](https://www.w3.org/TR/) / [WHATWG 명세 목록](https://spec.whatwg.org/)
- [ISO/IEC JTC 1 위원회 페이지](https://www.iso.org/committee/45020.html)
- [IANA 프로토콜 등록부](https://www.iana.org/protocols)
