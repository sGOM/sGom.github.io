---
title: "암호화 알고리즘 기본개념 — 대칭키, 공개키, 해시"
description: "대칭키·공개키·해시·MAC이 각각 무엇을 보장하는지 가르고, AES-GCM과 RSA-OAEP, Argon2id를 언제 쓰는지 정리한다."
pubDate: 2026-09-03
draft: true
category: "보안"
tags: ["기본개념", "암호화", "해시"]
---

## 왜 필요한가

회원 테이블의 비밀번호 컬럼을 AES로 암호화해 두면 안전할 것 같다. 실제로는 그렇지 않다. 복호화할 수 있다는 말은 복호화 키가 어딘가에 있다는 말이다. 키를 애플리케이션 서버에 두면 서버가 함께 뚫렸을 때 암호화가 무의미해지고, 키 관리라는 문제가 통째로 새로 생긴다.

비밀번호는 애초에 되돌릴 필요가 없다. 로그인할 때 필요한 것은 원문이 아니라 "입력한 값이 그때 그 값과 같은가"뿐이다. 되돌릴 필요가 없는 값에 되돌릴 수 있는 도구를 쓴 것이 문제다.

알고리즘 이름을 외우는 것보다 **무엇을 보장하려는지 먼저 정하는 것**이 순서다. 기밀성, 무결성, 인증, 부인 방지는 서로 다른 목표이고 도구도 다르다.

## 용어 정리

| 용어 | 되돌릴 수 있나 | 키가 필요한가 | 목적 |
|---|---|---|---|
| 인코딩(Base64, URL 인코딩) | 예 | 아니오 | 표현 형식 변환 |
| 암호화(AES, RSA) | 예 (키가 있으면) | 예 | 기밀성 |
| 해시(SHA-256) | 아니오 | 아니오 | 변조 탐지용 지문 |
| MAC(HMAC) | 아니오 | 예 (공유 비밀) | 무결성 + 발신자 인증 |
| 전자서명(RSA-PSS, Ed25519) | 아니오 | 예 (개인키/공개키) | 무결성 + 인증 + 부인 방지 |

Base64는 암호화가 아니다. [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648)이 정의한 것은 바이너리를 ASCII로 옮기는 표현 방식이고, 키가 없으니 누구나 되돌린다.

MAC과 전자서명의 차이는 키의 대칭성에서 온다. HMAC은 검증하는 쪽도 같은 비밀키를 가지므로, 검증자가 위조도 할 수 있다. 전자서명은 검증에 공개키만 쓰므로 서명자만 서명을 만들 수 있고, 이 비대칭이 부인 방지를 만든다.

## 핵심 정리

| 쓰임 | 키 구조 | 대표 알고리즘 | 보장하는 것 | 주 용도 |
|---|---|---|---|---|
| 대칭키 | 양쪽이 같은 키 | AES, ChaCha20 | 기밀성 | 실제 데이터 본문 |
| 대칭키(AEAD) | 양쪽이 같은 키 | AES-GCM, ChaCha20-Poly1305 | 기밀성 + 무결성 | TLS 레코드, 저장 데이터 |
| 공개키 암호 | 공개키/개인키 | RSA-OAEP | 기밀성 | 대칭키 전달 |
| 키 교환 | 공개키/개인키 | ECDH, X25519 | 공유 비밀 합의 | TLS 핸드셰이크 |
| 전자서명 | 공개키/개인키 | RSA-PSS, ECDSA, Ed25519 | 무결성, 인증, 부인 방지 | 인증서, JWT |
| 해시 | 없음 | SHA-256, SHA-3 | 변조 탐지 (해시값이 신뢰된 경로로 왔을 때) | 체크섬, 서명 대상 축약 |
| MAC | 공유 비밀 | HMAC-SHA256 | 무결성 + 발신자 인증 | API 서명, 웹훅 |
| 비밀번호 해시 | 없음(솔트 사용) | Argon2id, bcrypt, PBKDF2 | 저장된 비밀번호 보호 | 회원 인증 |

### 쓰지 않는 것

| 알고리즘 | 상태 | 근거 |
|---|---|---|
| DES | 사용하지 않는다 | 키가 56비트다. 1999년 EFF와 distributed.net이 [DES Challenge III](https://www.eff.org/press/releases/rsa-code-breaking-contest-again-won-distributednet-and-electronic-frontier-foundation)에서 22시간 15분 만에 전수 탐색으로 깼다 |
| 3DES | 사용하지 않는다 | [NIST SP 800-131A Rev.2](https://csrc.nist.gov/pubs/sp/800/131/a/r2/final)가 3키 TDEA를 2023년 이후 금지로 분류했다. 2키 TDEA는 2015년에 이미 금지됐다 |
| MD5, SHA-1 | 서명·인증서에 쓰지 않는다 | 충돌을 실제로 만들 수 있다. SHA-1은 2017년 [SHAttered](https://shattered.io/)가 같은 해시를 갖는 PDF 두 개를 공개했다 |
| AES-ECB | 사용하지 않는다 | 같은 평문 블록이 같은 암호문 블록이 된다. 아래 예시에서 확인한다 |
| RSA PKCS#1 v1.5 암호화 | 새로 쓰지 않는다 | 1998년 블라이헨바허(Bleichenbacher) 적응적 선택 암호문 공격 대상이다([RFC 8017 §7.2](https://www.rfc-editor.org/rfc/rfc8017#section-7.2)가 경고한다). 암호화는 OAEP를 쓴다 |

## 항목별 설명

### 대칭키는 알고리즘보다 운용 모드가 문제다

AES는 [FIPS 197](https://csrc.nist.gov/pubs/fips/197/upd1/final)이 정의한 블록 암호다. 한 번에 128비트 블록 하나를 변환하고, 키는 128·192·256비트를 받는다. 128비트보다 긴 데이터를 다루려면 블록을 이어 붙이는 방법이 따로 필요하고, 이것이 운용 모드다.

ECB는 블록마다 독립적으로 같은 변환을 건다. 그래서 평문이 같으면 암호문도 같아지고, 데이터의 반복 구조가 암호문에 그대로 남는다. CBC는 직전 암호문 블록을 다음 평문에 XOR해 이 패턴을 없앤다.

GCM은 여기에 인증 태그를 더한다. 복호화할 때 태그가 맞지 않으면 평문을 내주지 않고 예외를 던진다. 암호화와 무결성 검증을 한 알고리즘이 함께 하는 이 방식을 AEAD라고 부르고, [TLS 1.3](https://www.rfc-editor.org/rfc/rfc8446#section-1.2)은 AEAD가 아닌 암호 스위트를 전부 제거했다.

GCM에는 지켜야 할 조건이 하나 있다. **같은 키로 같은 IV를 두 번 쓰면 안 된다.** [NIST SP 800-38D](https://csrc.nist.gov/pubs/sp/800/38/d/final)는 96비트 IV를 권장하고, 난수 IV를 쓸 경우 한 키당 호출 횟수를 2^32회로 제한한다. IV가 겹치면 두 평문의 XOR이 드러나고 인증 키까지 복원될 수 있다.

### 공개키로는 데이터를 직접 암호화하지 않는다

RSA-2048에 OAEP(SHA-256) 패딩을 쓰면 한 번에 넣을 수 있는 평문은 190바이트다. 모듈러스 256바이트에서 해시 32바이트 두 개와 2바이트를 뺀 값이다. 그리고 느리다. 아래 예시에서 측정한 수치로 1MB를 RSA로 처리하면 4초가 넘고, 같은 데이터를 AES-256-GCM으로 처리하면 12밀리초다.

그래서 실제 프로토콜은 둘을 섞는다. 대칭키를 난수로 만들어 본문을 AES로 암호화하고, 그 대칭키만 공개키로 감싸 보낸다. TLS는 여기서 한 걸음 더 나아가 RSA로 키를 전달하는 대신 ECDHE로 매 세션마다 새 공유 비밀을 합의한다. 서버 개인키가 나중에 유출되어도 과거 세션은 복호화되지 않는다.

키 길이는 알고리즘끼리 직접 비교하지 않는다. [NIST SP 800-57 Part 1 Rev.5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)는 RSA 2048비트를 112비트 보안 강도로, ECC 256비트를 128비트로 본다. RSA로 128비트에 맞추려면 3072비트가 필요하다.

### 비밀번호 해시는 느려야 한다

SHA-256은 빠르게 설계됐다. 아래 예시를 잰 컨테이너의 단일 코어에서 25바이트 입력을 초당 300만 회 남짓 해시했고(`MessageDigest` 인스턴스를 재사용해 200만 회 워밍업 뒤 500만 회 측정), GPU로 병렬화하면 여기서 몇 자릿수가 더 올라간다. 이 속도는 공격자에게도 똑같이 유리하다. 유출된 해시 목록에 후보 비밀번호를 대입하는 공격은 해시 함수가 빠를수록 잘 통한다.

비밀번호 해시는 반대로 설계됐다. 계산 비용을 파라미터로 받아 의도적으로 느리게 만들고, 이 파라미터를 하드웨어 발전에 맞춰 올린다. 다만 무엇을 요구하는지는 셋이 다르다.

| 알고리즘 | 조정 가능한 것 | 메모리 |
|---|---|---|
| PBKDF2 | 반복 횟수 | 고정, 작다 |
| bcrypt | 코스트 팩터(반복 횟수는 2^cost) | 약 4KB 고정 |
| Argon2 | 반복 횟수, 메모리 사용량, 병렬도 | 파라미터로 지정한다 |

시간만 늘리는 방식은 전용 하드웨어에 약하다. ASIC이나 GPU는 연산 유닛을 수천 개 늘려 반복 횟수를 상쇄하지만, 코어마다 수십 MB씩 붙이는 것은 훨씬 비싸다. Argon2가 메모리를 요구하는 이유가 이것이다. [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106)은 두 변종을 섞은 Argon2id를 기본 선택으로 제시한다.

솔트는 사용자마다 다른 난수를 붙여 같은 비밀번호가 같은 해시가 되지 않게 한다. 미리 계산해 둔 표(레인보우 테이블)를 무력화하고, 같은 비밀번호를 쓴 두 계정이 서로 드러나는 것도 막는다. 솔트는 비밀이 아니라서 해시 문자열 안에 그대로 저장된다.

## 예시

### AES-256-GCM

```java
KeyGenerator kg = KeyGenerator.getInstance("AES");
kg.init(256);
SecretKey key = kg.generateKey();

byte[] iv = new byte[12];                       // 96비트, 매번 새로 만든다
new SecureRandom().nextBytes(iv);               // getInstanceStrong()은 환경에 따라 블로킹한다

Cipher enc = Cipher.getInstance("AES/GCM/NoPadding");
enc.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, iv));
byte[] ct = enc.doFinal("주민번호 900101-1234567".getBytes(UTF_8));

System.out.println(ct.length);                  // 43 = 평문 27 + 태그 16
```

암호문은 평문보다 16바이트 길다. 붙어 나온 인증 태그다. 이 태그로 무결성을 검증한다.

```java
byte[] tampered = ct.clone();
tampered[0] ^= 1;                               // 1비트만 뒤집는다

Cipher dec = Cipher.getInstance("AES/GCM/NoPadding");
dec.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, iv));
dec.doFinal(tampered);
// javax.crypto.AEADBadTagException: Tag mismatch
```

CBC였다면 결과가 갈린다. 같은 평문을 `AES/CBC/PKCS5Padding`으로 암호화하면 32바이트가 나오고, 여기서 위치별로 1비트씩 뒤집으면 이렇게 된다. 출력 가능한 ASCII가 아닌 바이트는 `.`으로 찍었다.

```
원본 평문     -> "............ 900101-1234567"
byte[0]  변조 -> "C..TV...@.).5...001-1234567"     예외 없음
byte[31] 변조 -> javax.crypto.BadPaddingException
```

앞 블록을 건드리면 예외가 나지 않는다. 첫 16바이트만 난수로 뭉개지고 **뒤쪽 11바이트는 그대로 살아남는다.** 17번째 바이트 하나가 `9`에서 `0`으로 뒤집힌 것이 전부다(`901...`이 `001...`이 됐다). 애플리케이션은 이 값을 정상 복호화 결과로 받는다. 마지막 블록을 건드렸을 때만 패딩 검사에 걸린다. 이 두 반응의 차이가 패딩 오라클 공격의 출발점이다.

### ECB가 남기는 패턴

같은 16바이트 블록 세 개를 이어 붙여 암호화한다.

```java
byte[] plain = new byte[48];
for (int i = 0; i < 48; i++) plain[i] = (byte) ('A' + (i % 16));  // 같은 블록 3개

Cipher ecb = Cipher.getInstance("AES/ECB/NoPadding");
ecb.init(Cipher.ENCRYPT_MODE, key);
byte[] a = ecb.doFinal(plain);

Cipher cbc = Cipher.getInstance("AES/CBC/NoPadding");
cbc.init(Cipher.ENCRYPT_MODE, key, new IvParameterSpec(iv));   // 16바이트 난수 IV
byte[] b = cbc.doFinal(plain);
```

```
ECB block0 = 313b69c250c4cfbd7838e11c83fafddb
ECB block1 = 313b69c250c4cfbd7838e11c83fafddb   <- 동일
ECB block2 = 313b69c250c4cfbd7838e11c83fafddb   <- 동일

CBC block0 = 3c74371945e9367032a269a63957b5c7
CBC block1 = 4fc8f91fc862923c9a4caddfa6cc0722
CBC block2 = 24998d472ab7ab874a798ae2b7a0f496
```

키를 몰라도 "같은 데이터가 세 번 반복된다"는 사실이 읽힌다. 비트맵 이미지를 ECB로 암호화하면 원본 윤곽이 그대로 보이는 이유가 이것이다.

### RSA의 크기 제한과 속도

```java
// 여기서 ECB는 블록 모드가 아니라 "블록 하나"를 뜻하는 JCA의 관례 표기다
Cipher rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding");
rsa.init(Cipher.ENCRYPT_MODE, publicKey);       // RSA-2048

rsa.doFinal(new byte[190]);                     // ok, 암호문 256바이트
rsa.doFinal(new byte[191]);
// javax.crypto.IllegalBlockSizeException: Data must not be longer than 190 bytes
```

이름과 실제가 갈리는 자리가 하나 있다. `OAEPWithSHA-256AndMGF1Padding`은 MGF1에도 SHA-256이 걸릴 것처럼 읽히지만, SunJCE에서 이 문자열은 **라벨 해시만 SHA-256으로 잡고 MGF1은 SHA-1로 남긴다.** 같은 암호문을 `OAEPParameterSpec`으로 복호화해 보면 드러난다.

```
MGF1=SHA-256 -> javax.crypto.BadPaddingException: Padding error in decryption
MGF1=SHA-1   -> 복호화 성공
```

MGF1까지 SHA-256으로 맞추는 다른 언어·라이브러리와 붙이면 여기서 복호화가 깨진다. 양쪽을 명시하려면 `OAEPParameterSpec`을 직접 넘긴다.

```java
Cipher rsa = Cipher.getInstance("RSA/ECB/OAEPPadding");
rsa.init(Cipher.ENCRYPT_MODE, publicKey, new OAEPParameterSpec(
        "SHA-256", "MGF1", MGF1ParameterSpec.SHA256, PSource.PSpecified.DEFAULT));
```

OpenJDK 21, x86-64 리눅스 컨테이너에서 잰 값이다. AES는 1MB를 한 번에 처리해 재고, RSA는 190바이트 블록 하나를 재서 5,519블록으로 환산했다.

| 연산 | 측정값 | 1MB 환산 |
|---|---|---|
| AES-256-GCM 암호화 | 1MB에 12ms | 12ms |
| RSA-2048 OAEP 암호화(공개키) | 190바이트 1블록에 0.037ms | 약 0.2초 |
| RSA-2048 OAEP 복호화(개인키) | 190바이트 1블록에 0.77ms | 약 4.3초 |

1MB는 190바이트 블록 5,519개다. 복호화 기준으로 AES보다 350배가량 느리다. 공개키 연산이 개인키 연산보다 20배 빠른 것은 공개 지수 e가 65537로 작기 때문이다.

## 혼동하기 쉬운 것

**IV와 솔트는 다른 문제를 푼다.** 둘 다 난수이고 비밀이 아니지만, IV는 같은 평문이 같은 암호문이 되는 것을 막고 솔트는 미리 계산한 해시 표를 막는다. IV는 재사용이 곧 평문 노출이고(GCM), 솔트는 재사용하면 레인보우 테이블 방어가 풀린다.

**해시는 암호화가 아니다.** "비밀번호를 SHA-256으로 암호화했다"는 문장은 틀렸다. 해시는 복호화되지 않는다. 반대로 "AES로 비밀번호를 저장했다"는 문장은 문법은 맞지만 설계가 틀렸다.

**AES-256이 AES-128보다 2배 안전한 것은 아니다.** 키 공간이 2^128배 넓지만 둘 다 전수 탐색이 불가능한 영역이다. 실무에서 깨지는 지점은 모드 선택, IV 관리, 키 보관이다.

**HTTPS를 쓰면 데이터가 암호화된다는 말은 전송 구간에만 해당한다.** TLS는 종료 지점에서 복호화되고, 그 지점은 로드밸런서일 수도 애플리케이션 서버일 수도 있다. 저장 데이터 암호화는 별개 작업이다.

## 언제 어떤 것을 쓰나

| 하려는 일 | 선택 |
|---|---|
| 파일이나 컬럼을 암호화해 저장 | AES-256-GCM. IV는 레코드마다 새로 만들어 암호문과 함께 저장한다 |
| 비밀번호 저장 | Argon2id. 기존 스택에 bcrypt가 있으면 bcrypt도 유효하다 |
| API 요청 위변조 방지 | HMAC-SHA256 |
| 파일 무결성 확인 | SHA-256 |
| 토큰 발급자 검증 | 발급자와 검증자가 다르면 전자서명(ES256, EdDSA), 같으면 HMAC(HS256) |
| 키를 안전하게 전달 | 직접 구현하지 않는다. TLS를 쓴다 |

알고리즘을 고르는 것보다 검증된 구현을 그대로 쓰는 쪽이 실패 확률이 낮다. 위의 MGF1 사례처럼, 사고는 알고리즘이 약해서가 아니라 표준 라이브러리의 기본값을 벗어나는 조합을 직접 맞출 때 난다.

## 더 깊이

- 토큰 기반 인가에서 이 도구들이 어떻게 조합되는지는 [OAuth2 기본개념](/posts/oauth2-basics/)에서 다룬다.

## 참고

- [FIPS 197: Advanced Encryption Standard (AES)](https://csrc.nist.gov/pubs/fips/197/upd1/final)
- [NIST SP 800-38D: Galois/Counter Mode (GCM) and GMAC](https://csrc.nist.gov/pubs/sp/800/38/d/final)
- [NIST SP 800-57 Part 1 Rev. 5: Key Management](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)
- [RFC 8017: PKCS #1 v2.2 (RSA)](https://www.rfc-editor.org/rfc/rfc8017)
- [RFC 8446: TLS 1.3](https://www.rfc-editor.org/rfc/rfc8446)
- [RFC 9106: Argon2](https://www.rfc-editor.org/rfc/rfc9106)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
