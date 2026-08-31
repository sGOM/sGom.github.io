---
title: "OAuth2 기본개념 — 네 역할과 토큰 발급 흐름"
description: "OAuth2의 네 역할과 그랜트 타입, 인가 코드 흐름을 실제 HTTP 요청으로 정리한다."
pubDate: 2026-08-25
category: "보안"
tags: ["기본개념", "OAuth2", "인증"]
---

## 왜 필요한가

사진 인화 서비스에 구글 포토의 사진을 넘기려면 예전에는 구글 아이디와 비밀번호를 그 서비스에 입력해야 했다. 이 방식은 네 군데서 깨진다.

- 인화 서비스가 비밀번호를 평문으로 보관하거나 로그에 남긴다.
- 사진만 읽으면 되는데 메일과 결제 정보까지 열린다.
- 권한을 회수하려면 비밀번호를 바꿔야 하고, 그러면 다른 서비스도 전부 끊긴다.
- 2단계 인증을 켠 계정은 비밀번호만으로는 연동되지 않는다.

OAuth2는 비밀번호 대신 **범위와 기간이 정해진 토큰**을 넘긴다. 인화 서비스는 `photos.read` 권한이 붙은 토큰 문자열 하나를 받고, 사용자는 구글 설정에서 그 앱의 접근 권한만 끊는다.

## 용어 정리

| 용어 | 뜻 | OAuth2와의 관계 |
|---|---|---|
| 인증(Authentication) | 누구인지 확인하는 일 | OAuth2의 범위가 아니다 |
| 인가(Authorization) | 무엇을 해도 되는지 정하는 일 | OAuth2가 다루는 것 |
| 액세스 토큰 | 보호된 자원에 접근할 때 제시하는 자격증명 | 짧게 살고 자주 재발급된다 |
| 리프레시 토큰 | 액세스 토큰을 다시 받을 때 쓰는 자격증명 | 인가 서버에만 보낸다 |

두 토큰 모두 RFC 6749가 "클라이언트에게 대개 불투명하다(usually opaque to the client)"고 적어 두었다([§1.4](https://www.rfc-editor.org/rfc/rfc6749#section-1.4), [§1.5](https://www.rfc-editor.org/rfc/rfc6749#section-1.5)). 클라이언트는 토큰을 받아 그대로 전달할 뿐, 내용을 해석할 대상으로 보지 않는다.

## 핵심 정리

### 네 역할

| 역할 | 정의 | 예 |
|---|---|---|
| Resource Owner | 보호된 자원에 대한 접근을 허락할 수 있는 주체 | 사진의 주인인 사용자 |
| Client | 자원 소유자를 대신해 자원을 요청하는 애플리케이션 | 사진 인화 서비스 |
| Authorization Server | 자원 소유자를 인증하고 인가를 받아 토큰을 발급하는 서버 | `accounts.google.com` |
| Resource Server | 액세스 토큰을 받아 보호된 자원을 내주는 서버 | 구글 포토 API |

인가 서버와 자원 서버는 같은 회사가 운영해도 별개 역할이다. 토큰을 만드는 쪽과 검증해서 쓰는 쪽이 분리되어 있다.

### 그랜트 타입

토큰을 받아 내는 절차를 그랜트(grant)라고 한다.

| 그랜트 | `grant_type` | 쓰는 곳 | 상태 |
|---|---|---|---|
| Authorization Code | `authorization_code` | 사용자가 개입하는 거의 모든 경우 | 기본값 |
| Client Credentials | `client_credentials` | 사용자 없이 서버끼리 부르는 배치, 내부 API | 유효 |
| Device Authorization | `urn:ietf:params:oauth:grant-type:device_code` | 브라우저나 키보드가 없는 TV, CLI | 유효 |
| Refresh Token | `refresh_token` | 만료된 액세스 토큰 재발급 | 유효 |
| Implicit | (`response_type=token`) | 과거 SPA | 사용하지 않는다 |
| Resource Owner Password | `password` | 과거 자사 앱 로그인 | 금지 |

아래 두 줄은 2025년 1월 [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html)(OAuth 2.0 보안 모범 사례)이 정리했다. Implicit은 "클라이언트가 사용해서는 안 된다(SHOULD NOT)". 비밀번호 그랜트는 더 세다. "사용되어서는 안 된다(MUST NOT). 이 그랜트 타입은 자원 소유자의 자격증명을 클라이언트에게 안전하지 않게 노출한다."

## 항목별 설명

Authorization Code 그랜트는 토큰을 두 단계로 나눠 준다. 브라우저 리다이렉트로는 **코드**만 넘기고, 그 코드를 서버 대 서버 통신으로 토큰과 바꾼다.

1. 클라이언트가 사용자의 브라우저를 인가 서버의 `/authorize`로 보낸다. 요청 URL에 `client_id`, `redirect_uri`, `scope`, `state`가 들어간다.
2. 인가 서버가 사용자를 로그인시키고 동의 화면을 띄운다. 이 화면에서 비밀번호를 받는 쪽은 인가 서버지 클라이언트가 아니다.
3. 사용자가 동의하면 인가 서버가 `redirect_uri`로 브라우저를 되돌려 보내며 `code`를 붙인다.
4. 클라이언트가 `/token`을 직접 호출해 `code`를 보낸다. 시크릿을 보관할 수 있는 기밀 클라이언트는 `client_secret`을, SPA나 모바일 앱 같은 공개 클라이언트는 `code_verifier`를 함께 싣는다.
5. 인가 서버가 액세스 토큰과 리프레시 토큰을 JSON으로 응답한다.
6. 클라이언트가 자원 서버에 `Authorization: Bearer <액세스 토큰>` 헤더를 붙여 요청한다.

3단계의 `code`는 브라우저 주소창과 접속 기록에 남는다. 그래서 코드는 한 번만 쓸 수 있고 수명이 짧다. 더 이상 권장하지 않는 Implicit 그랜트는 이 자리에 토큰 자체를 프래그먼트(`#`)로 실어 보냈다. 프래그먼트는 서버 로그에 남지 않지만, 토큰은 코드와 달리 교환 단계 없이 그대로 쓰인다. 유출을 알아채고 폐기하기 전에 이미 사용된다.

`state`는 1단계에서 클라이언트가 만들어 보내고 3단계에서 돌아온 값을 대조한다. 값이 다르면 이 응답은 자신이 시작한 요청의 결과가 아니므로 버린다. 복귀할 페이지 주소처럼 요청을 시작한 시점의 정보를 실어 나르는 데도 쓴다. 이때 내용의 무결성이 중요하다면 변조와 뒤바꿔치기를 막아야 한다(MUST).

PKCE는 4단계를 지킨다. 1단계에서 무작위 값(`code_verifier`)의 해시를 미리 보내 두고, 4단계에서 원본 값을 함께 제출한다. 3단계에서 코드를 가로챈 공격자는 원본 값을 모르므로 토큰으로 바꾸지 못한다. 공개 클라이언트에는 필수다.

## 예시

RFC 6749에 실린 예시다. 값은 원문 그대로다.

1단계, 인가 요청([§4.1.1](https://www.rfc-editor.org/rfc/rfc6749#section-4.1.1)).

```http
GET /authorize?response_type=code&client_id=s6BhdRkqt3&state=xyz
    &redirect_uri=https%3A%2F%2Fclient%2Eexample%2Ecom%2Fcb HTTP/1.1
Host: server.example.com
```

3단계, 코드를 붙인 리다이렉트([§4.1.2](https://www.rfc-editor.org/rfc/rfc6749#section-4.1.2)).

```http
HTTP/1.1 302 Found
Location: https://client.example.com/cb?code=SplxlOBeZQQYbYS6WxSbIA
          &state=xyz
```

4단계, 코드를 토큰으로 바꾸는 요청([§4.1.3](https://www.rfc-editor.org/rfc/rfc6749#section-4.1.3)). `Authorization: Basic`에 `client_id:client_secret`이 실려 있다.

```http
POST /token HTTP/1.1
Host: server.example.com
Authorization: Basic czZCaGRSa3F0MzpnWDFmQmF0M2JW
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&code=SplxlOBeZQQYbYS6WxSbIA
&redirect_uri=https%3A%2F%2Fclient%2Eexample%2Ecom%2Fcb
```

5단계, 토큰 응답([§4.1.4](https://www.rfc-editor.org/rfc/rfc6749#section-4.1.4)).

```json
{
  "access_token":"2YotnFZFEjr1zCsicMWpAA",
  "token_type":"example",
  "expires_in":3600,
  "refresh_token":"tGzv3JOkF0XG5Qx2TlKWIA",
  "example_parameter":"example_value"
}
```

`token_type`이 `example`인 것은 RFC가 토큰 타입을 별도 문서로 분리해 두고 예시에서 자리만 표시했기 때문이다. 실제 서버는 대부분 `Bearer`를 내려준다.

6단계, 자원 요청([RFC 6750 §2.1](https://www.rfc-editor.org/rfc/rfc6750#section-2.1)).

```http
GET /resource HTTP/1.1
Host: server.example.com
Authorization: Bearer mF_9.B5f-4.1JqM
```

토큰이 만료됐거나 잘못됐으면 자원 서버는 401과 함께 이유를 헤더에 담는다([RFC 6750 §3](https://www.rfc-editor.org/rfc/rfc6750#section-3)).

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="example",
                  error="invalid_token",
                  error_description="The access token expired"
```

## 혼동하기 쉬운 것

**OAuth2만으로는 로그인이 되지 않는다.** 액세스 토큰은 "이 토큰 소지자는 이 범위의 자원에 접근해도 된다"만 말한다. 토큰을 받았다는 사실이 사용자가 방금 로그인했다는 증거는 아니다. 다른 앱에서 유출된 토큰을 붙여 넣어도 자원 서버는 통과시킨다.

이 구멍을 메우려고 OAuth2 위에 얹은 규격이 OpenID Connect다. 여기서는 액세스 토큰과 별도로, 누가 언제 어느 클라이언트를 대상으로 인증했는지를 담은 `id_token`을 발급한다.

**액세스 토큰의 내용은 클라이언트가 읽을 대상이 아니다.** 많은 인가 서버가 JWT를 액세스 토큰으로 발급하다 보니 클라이언트가 이를 디코딩해 사용자 정보를 꺼내 쓰는 코드가 흔하다. 토큰 형식은 인가 서버와 자원 서버 사이의 약속이라, 서버가 형식을 불투명한 문자열로 바꾸는 순간 그 코드는 깨진다. 사용자 정보는 OIDC의 `id_token`이나 `/userinfo`에서 얻는다.

**PKCE를 쓰면 `state`는 CSRF 방어에서 빠질 수 있다.** 두 방어는 겹친다. 공격자가 자기 인가 코드를 피해자 세션에 밀어 넣어도, 피해자 브라우저가 들고 있는 `code_verifier`와 맞지 않아 교환 단계에서 실패한다. RFC 9700도 "인가 서버가 PKCE를 지원한다는 것을 확인한 클라이언트는 PKCE가 제공하는 CSRF 방어에 의존해도 된다(MAY)"고 적었다([§2.1.3](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.3)). 다만 확인이 전제다. 같은 문서 §4.7.1은 인가 서버가 PKCE를 지원하지 않으면 `state`나 `nonce`를 CSRF 방어에 써야 한다(MUST)고 요구한다.

**`redirect_uri`는 부분 일치로 검증하지 않는다.** RFC 9700은 인가 서버가 "정확한 문자열 일치(exact string matching)"를 써야 한다(MUST)고 요구한다. 예외는 네이티브 앱의 `localhost` 리다이렉트에서 포트 번호뿐이다. 접두사 일치를 허용하면 등록된 도메인 아래 열린 리다이렉트 한 곳으로 코드가 새어 나간다.

## 언제 어떤 것을 쓰나

| 상황 | 그랜트 |
|---|---|
| 웹 서버 앱, SPA, 모바일 앱 등 사용자가 개입하는 경우 | Authorization Code + PKCE |
| 사용자 없이 서비스 계정으로 도는 배치나 내부 API 호출 | Client Credentials |
| 입력 장치가 빈약한 TV, 콘솔, CLI | Device Authorization |

사실상 첫 줄 하나로 끝난다. 공개 클라이언트에게 Implicit을 권하던 과거 기준은 PKCE가 대신하면서 없어졌다. 공개와 기밀의 구분 자체는 남아 있고, 클라이언트 인증 방식과 PKCE 요구 강도가 여기서 갈린다.

## 참고

- [RFC 6749 — The OAuth 2.0 Authorization Framework](https://www.rfc-editor.org/rfc/rfc6749)
- [RFC 6750 — Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750)
- [RFC 7636 — Proof Key for Code Exchange (PKCE)](https://www.rfc-editor.org/rfc/rfc7636)
- [RFC 8628 — OAuth 2.0 Device Authorization Grant](https://www.rfc-editor.org/rfc/rfc8628)
- [RFC 9700 — Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
