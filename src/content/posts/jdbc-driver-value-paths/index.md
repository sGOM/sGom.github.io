---
title: "PreparedStatement의 ?는 어디서 값과 만나는가"
description: Connector/J가 MySQL로 실제로 보내는 문장을 general_log로 잡아, 두 경로가 각각 무엇으로 인젝션을 막는지 확인한다
pubDate: 2026-08-22
updatedDate: 2026-08-24
category: "데이터베이스"
tags: ["파고들기", "Database", "JDBC", "MySQL"]
---

## 전제

[MyBatis의 #{}와 ${} — 바인딩과 문자열 치환](/posts/mybatis-parameter-binding/)에서 `#{}`는 `?`를 만들고 값은 따로 넘긴다는 데까지 봤다. 이 글은 그 `?`를 넘겨받은 JDBC 드라이버가 무엇을 하는지 확인한다.

## 왜 필요한가

`#{}`가 안전한 이유를 "값이 SQL 문장과 분리되어 전달되기 때문"이라고 설명하는 글이 많다. 그런데 MySQL Connector/J는 기본 설정에서 서버 사이드 prepare를 쓰지 않는다. `useServerPrepStmts`의 기본값이 `false`다. ([Connector/J — Prepared Statements 설정](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-prepared-statements.html))

값을 문장에 직접 채워 넣은 SQL 한 벌을 보낸다는 뜻이다.

값과 문장이 합쳐진 채로 서버에 도착하는데 왜 인젝션이 안 되나. 무엇이 그걸 막고 있고, 그 무엇은 언제 깨지나. 문서에는 답이 없다. 드라이버가 실제로 보낸 문장을 봐야 한다.

## 구조

드라이버가 `?`를 처리하는 경로는 둘이다. `useServerPrepStmts`가 어느 쪽을 탈지 정한다.

```text
클라이언트 조립 (useServerPrepStmts=false, 기본값)

  드라이버 ──[ SELECT ... WHERE name = '값' ]──▶ 서버
             값이 이미 박힌 문장 한 벌. 서버는 이걸 파싱한다.


서버 사이드 prepare (useServerPrepStmts=true)

  드라이버 ──[ COM_STMT_PREPARE: SELECT ... WHERE name = ? ]──▶ 서버
                                                                파싱해 두고 핸들을 준다
  드라이버 ──[ COM_STMT_EXECUTE: 핸들 + 값(바이너리) ]────────▶ 서버
                                                                이미 파싱된 문장에 값만 꽂는다
```

같은 `?` 하나를 두고 막는 방식이 다르다.

| | 클라이언트 조립 | 서버 사이드 prepare |
|---|---|---|
| 서버가 파싱하는 것 | 값이 박힌 문장 | `?`만 있는 문장 |
| 값이 도착하는 시점 | 파싱 전 | 파싱이 끝난 뒤 |
| 인젝션을 막는 것 | 드라이버의 리터럴 조립 | 파싱과 값 전달의 순서 |
| 서버 왕복 | 1회 | 첫 실행 2회. `cachePrepStmts=true`로 핸들을 캐시해야 이후 1회 |

## 동작 원리

**드라이버는 접속하는 순간 서버 상태를 읽어 둔다.** 값을 리터럴로 만들려면 서버가 문자열 리터럴을 어떻게 해석하는지 알아야 한다. 

Connector/J는 커넥션을 열면서 세션 변수를 한 번에 읽는 질의를 보내고, 그 목록에 문자셋 변수들과 `@@sql_mode`가 들어 있다. `sql_mode`를 바꾸면 그 뒤에 열린 커넥션이 만드는 리터럴의 형태도 바뀐다.

**클라이언트 조립은 값을 리터럴로 만들어 문장에 넣는다.** 읽어 둔 상태에 따라 만드는 형태가 갈린다.

| 서버 `sql_mode` | 값에 이스케이프 대상 문자가 | 드라이버가 만드는 리터럴 |
|---|---|---|
| 기본 | 없다 | `'홍길동'` |
| 기본 | 있다 | 걸린 문자만 바꿔 넣는다. `'`는 `''`로, `\`는 `\\`로 |
| [`NO_BACKSLASH_ESCAPES`](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html) | 없다 | `'홍길동'` |
| `NO_BACKSLASH_ESCAPES` | 있다 | 값 전체를 [16진수 리터럴](https://dev.mysql.com/doc/refman/8.0/en/hexadecimal-literals.html) `x'...'`로 바꾼다 |

이스케이프 대상은 일곱 문자다. `\0`(NUL), `\n`, `\r`, `\`, `'`, `"`, `\032`(Ctrl+Z). 하나라도 들어 있으면 값이 오른쪽 칸의 처리를 받는다.

`"`는 트리거만 하고 기본 모드에서는 바뀌지 않는다. `a"b`가 기본 모드에서는 `'a"b'`로 그대로 나가고 `NO_BACKSLASH_ESCAPES`에서는 통째로 16진수가 되는 이유다.

어느 쪽이든 값은 리터럴 안에 갇힌다.

**서버 사이드 prepare는 문장과 값을 다른 메시지로 보낸다.** [`COM_STMT_PREPARE`](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_prepare.html)로 `?`가 든 문장을 먼저 보내면 서버가 파싱해 두고 핸들을 돌려준다.

값은 [`COM_STMT_EXECUTE`](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_execute.html)가 바이너리 형식으로 따로 실어 보낸다. 값이 도착했을 때 문장은 이미 파싱이 끝나 있으므로, 값이 문법이 될 기회 자체가 없다.

## 코드로 따라가기

`sql_mode`가 리터럴 형태를 가르는 이 동작은 MySQL 문서에도 Connector/J 문서에도 찾지 못했다. 소스에는 있다. 문자열 바인딩은 [`StringValueEncoder.getBytes()`](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/protocol-impl/java/com/mysql/cj/protocol/a/StringValueEncoder.java#L94)가 처리한다.

```java
if (this.serverSession.isNoBackslashEscapesSet()) {
    // Scan for any nasty chars
    if (!isEscapeNeededForString(x, stringLength)) {
        return StringUtils.getBytesWrapped(x, '\'', '\'', this.charEncoding.getValue());
    }
    return escapeBytesIfNeeded(StringUtils.getBytes(x, this.charEncoding.getValue()));
}

if (isEscapeNeededForString(x, stringLength)) {
    String escString = StringUtils
            .escapeString(new StringBuilder((int) (x.length() * 1.1)), x, this.serverSession.useAnsiQuotedIdentifiers(), this.charsetEncoder)
            .toString();
    return StringUtils.getBytes(escString, this.charEncoding.getValue());
}

return StringUtils.getBytesWrapped(x, '\'', '\'', this.charEncoding.getValue());
```

네 갈래가 「동작 원리」 표의 네 칸이다. 걸릴 문자가 없으면 어느 모드든 따옴표로 감싸고 끝낸다. 있으면 `NO_BACKSLASH_ESCAPES`일 때 [`escapeBytesIfNeeded()`](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/protocol-impl/java/com/mysql/cj/protocol/a/AbstractValueEncoder.java#L214)로, 아닐 때 `StringUtils.escapeString()`으로 간다.

```java
if (this.serverSession.isNoBackslashEscapesSet()
        || this.serverSession.getCharsetSettings().isMultibyteCharset(this.charEncoding.getValue())) {

    // Send as hex
    ByteArrayOutputStream bOut = new ByteArrayOutputStream(x.length * 2 + 3);
    bOut.write('x');
    bOut.write('\'');

    StringUtils.hexEscapeBlock(x, x.length, (lowBits, highBits) -> {
        bOut.write(lowBits);
        bOut.write(highBits);
    });
    bOut.write('\'');
    return bOut.toByteArray();
}
```

주석이 그대로 말한다. 값을 문자 단위로 고치지 않고 바이트를 통째로 16진수로 찍는다. 뒤쪽 조건(멀티바이트 문자셋)은 이 글의 경로와 무관하다. 문자열 바인딩에서 이 메서드는 위 분기를 거쳐 오므로 `NO_BACKSLASH_ESCAPES`일 때만 불린다.

무엇이 "걸릴 문자"인지는 [`isEscapeNeededForString()`](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/protocol-impl/java/com/mysql/cj/protocol/a/StringValueEncoder.java#L386)이 정한다.

```java
switch (c) {
    case 0: /* Must be escaped for 'mysql' */
    case '\n': /* Must be escaped for logs */
    case '\r':
    case '\\':
    case '\'':
    case '"': /* Better safe than sorry */
    case '\032': /* This gives problems on Win32 */
        return true; // no need to scan more
}
```

기본 모드에서 값을 손보는 [`StringUtils.escapeString()`](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/core-api/java/com/mysql/cj/util/StringUtils.java#L1745)은 이 일곱 문자를 그대로 받는다. `'`는 `''`로 겹쳐 쓰고, `\`는 `\\`로, `\032`는 `\Z`로 바꾼다. `"`는 `ANSI_QUOTES`가 켜져 있을 때만 `\"`가 되고, 꺼져 있으면 손대지 않는다.

여기에 `¥`(U+00A5)와 `₩`(U+20A9) case가 둘 더 있다. 이 두 글자를 백슬래시 바이트로 인코딩하는 문자셋에서만 앞에 `\`를 붙인다.

## 직접 확인

MySQL 8.0.46(도커 `mysql:8.0`), Connector/J 9.1.0, JDK 26.0.1로 확인했다. `' OR 1=1 #`을 값으로 넣어 네 경로를 돌린 결과가 이렇다. 문자열을 닫고 항상 참인 조건을 붙인 뒤, 남는 따옴표를 `#`로 주석 처리하는 페이로드다.

| 경로 | 서버가 받은 문장 | 행 수 |
|---|---|---|
| 문자열 이어붙이기 | `... name = '' OR 1=1 #'` | **3 (뚫림)** |
| 바인딩 · 클라이언트 조립(기본) | `... name = ''' OR 1=1 #'` | 0 |
| 바인딩 · `useServerPrepStmts=true` | `Prepare: ... name = ?` | 0 |
| 바인딩 · `sql_mode=NO_BACKSLASH_ESCAPES` | `... name = x'27204f...'` | 0 |

`useServerPrepStmts=true` 행에는 `Execute` 줄이 하나 더 붙는데, 그 줄을 어떻게 읽어야 하는지는 「`useServerPrepStmts=true`로 켜면」에서 따로 다룬다.

위 문장들은 `general_log`에서 그대로 뽑았다. 켜 두면 서버가 받은 문장이 남는다.

```bash
docker run -d --name mybatis-lab -e MYSQL_ROOT_PASSWORD=labpw -e MYSQL_DATABASE=lab \
  -p 13306:3306 mysql:8.0 --character-set-server=utf8mb4

curl -sSLO https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/9.1.0/mysql-connector-j-9.1.0.jar

# 서버가 TCP를 열 때까지 기다린다. -h127.0.0.1을 빼면 초기화 중인
# 임시 서버가 소켓으로 응답해 먼저 통과해 버린다.
until docker exec mybatis-lab mysqladmin -h127.0.0.1 -uroot -plabpw --silent ping; do sleep 1; done
```

```bash
docker exec -i mybatis-lab mysql -uroot -plabpw lab <<'SQL'
CREATE TABLE users (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(50));
INSERT INTO users(name) VALUES ('홍길동'),('김철수'),('이영희');
SET GLOBAL log_output='TABLE';
SQL
```

「실험 코드」의 두 파일을 방금 받은 jar와 같은 디렉터리에 `Probe.java`, `Connect.java`로 저장한다. 단일 파일 소스 실행이라 컴파일 없이 돌아간다. 실험은 `Probe`가 맡고, 접속할 때 오가는 질의만 `Connect`로 따로 잡는다.

```text
java -cp mysql-connector-j-9.1.0.jar Probe.java <접속 옵션> <보낼 값> [concat]
```

첫 인자는 JDBC URL 뒤에 붙일 접속 옵션, 둘째는 보낼 값이다. 셋째 자리에 `concat`을 주면 `?`에 바인딩하는 대신 값을 문자열로 이어 붙인다. `${}`를 흉내 내는 자리다.

출력은 보낸 값, 돌려받은 행 수, 서버가 받은 문장이다. 실험과 무관한 줄은 걸러 냈다. 드라이버가 접속하며 보내는 질의(`/*`로 시작한다), 로그를 켜고 끄는 `SET` 문, 로그 테이블을 읽는 질의다.

### `' OR 1=1 #`이 실제로 공격이 되는가

`${}`처럼 값을 문자열로 그대로 이어 붙였을 때다.

```text
$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" "' OR 1=1 #" concat
보낸 값      : [' OR 1=1 #]
돌려받은 행 수: 3
Query    | SELECT id, name FROM users WHERE name = '' OR 1=1 #'
```

3행 전부가 나왔다. 조건이 항상 참이 됐고, 뒤에 남은 따옴표는 `#` 뒤로 밀려 주석이 됐다.

### 옵션을 아무것도 주지 않으면

기본값이 어느 경로인지부터 확인한다. 접속 옵션 자리를 비웠다.

```text
$ java -cp mysql-connector-j-9.1.0.jar Probe.java "" "홍길동"
보낸 값      : [홍길동]
돌려받은 행 수: 1
Query    | SELECT id, name FROM users WHERE name = '홍길동'
```

`Prepare`/`Execute`가 아니라 `Query` 한 줄이다. 값이 이미 박혀서 왔다. 기본값이 클라이언트 조립이라는 문서의 서술이 그대로 확인된다.

### 공격 문자열을 `?`에 바인딩하면

```text
$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" "' OR 1=1 #"
보낸 값      : [' OR 1=1 #]
돌려받은 행 수: 0
Query    | SELECT id, name FROM users WHERE name = ''' OR 1=1 #'
```

여기서도 값이 박힌 채로 도착했다. 그런데 따옴표가 `''`로 겹쳐 있어서 문자열이 거기서 닫히지 않는다. 리터럴 전체가 `' OR 1=1 #`라는 하나의 값이고, 그런 이름을 가진 행이 없어 0행이 나온다.

### `useServerPrepStmts=true`로 켜면

```text
$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=true" "' OR 1=1 #"
보낸 값      : [' OR 1=1 #]
돌려받은 행 수: 0
Prepare  | SELECT id, name FROM users WHERE name = ?
Execute  | SELECT id, name FROM users WHERE name = '\' OR 1=1 #'
```

`Prepare`에 값이 없다. 서버는 `?`만 있는 문장을 파싱했다. 관측된 사실은 여기까지다.

`Execute` 줄에 값이 보이는 것은 드라이버가 그 텍스트를 보냈다는 뜻이 아니다. 두 가지가 그렇게 읽히는 것을 막는다.

첫째, 같은 입력인데 클라이언트 조립에서는 `''`로, 여기서는 `\'`로 찍혔다. 한 드라이버가 만든 문자열이라면 같은 규칙을 따랐을 것이다. 둘째, 프로토콜 문서상 이 경로의 값은 `COM_STMT_EXECUTE`의 바이너리 파라미터로 간다. 

그렇다면 `Execute` 줄의 텍스트는 서버가 바인딩된 값을 되살려 찍은 것으로 보인다. 패킷을 직접 뜬 것은 아니므로 여기까지가 추론이다.

### 백슬래시가 든 값 (기본 모드)

백슬래시가 든 값은 다음 절의 기준선이 된다.

```text
$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" "a\b"
보낸 값      : [a\b]
돌려받은 행 수: 0
Query    | SELECT id, name FROM users WHERE name = 'a\\b'
```

`\`가 `\\`로 늘어났다. 서버가 백슬래시를 이스케이프 문자로 읽어 주므로 이 리터럴은 `a\b`라는 값 하나다.

### `NO_BACKSLASH_ESCAPES`를 켜면

이 모드에서는 백슬래시가 평범한 문자가 된다. 방금의 `'a\\b'`는 백슬래시 두 개짜리 문자열이 된다. 기본 모드처럼 이스케이프했다면 값이 바뀌었을 것이다.

```text
$ docker exec mybatis-lab mysql -uroot -plabpw \
    -e "SET GLOBAL sql_mode=CONCAT(@@GLOBAL.sql_mode, ',NO_BACKSLASH_ESCAPES')"

$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" "a\b"
보낸 값      : [a\b]
돌려받은 행 수: 0
Query    | SELECT id, name FROM users WHERE name = x'615c62'

$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" "' OR 1=1 #"
보낸 값      : [' OR 1=1 #]
돌려받은 행 수: 0
Query    | SELECT id, name FROM users WHERE name = x'27204f5220313d312023'

$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" "홍길동"
보낸 값      : [홍길동]
돌려받은 행 수: 1
Query    | SELECT id, name FROM users WHERE name = '홍길동'
```

`\\`를 쓰는 대신 값을 통째로 16진수 리터럴로 바꿨다. `61 5c 62`가 `a\b`다. 두 번째 값도 마찬가지로 `27`이 `'`, `20`이 공백, `4f 52`가 `OR`다. 이스케이프 대상 문자가 없는 `홍길동`은 「옵션을 아무것도 주지 않으면」의 출력과 똑같이 평범한 리터럴로 갔다.

갈림길은 두 번째 값이 보여 준다. 따옴표만 든 값은 `''` 겹쳐쓰기로 처리할 수 있고 그 방식은 이 모드에서도 유효한데, 드라이버는 그 수단을 두고도 16진수로 갔다. **일곱 문자 중 하나만 걸려도 값 전체가 16진수로 나간다.** 여기서 실제로 돌려 본 것은 `'`와 `\` 둘이고, 나머지 다섯은 「코드로 따라가기」의 분기로 확인했다.

이 모드에서 드라이버는 이스케이프 방식을 바꾸는 게 아니라 이스케이프 자체를 포기한다. 16진수 리터럴에는 따옴표도 백슬래시도 없으니, 모드와 무관하게 값이 문법이 될 수 없다.

16진수로 바꿔도 비교는 그대로다. 위 세 출력은 16진수로 간 값이 모두 0행이라 매칭이 되는 경우가 없다. 대소문자만 다른 행을 하나 넣고 확인했다.

```text
$ docker exec mybatis-lab mysql -uroot -plabpw lab \
    -e "INSERT INTO users(name) VALUES (CONVERT(x'412242' USING utf8mb4))"

$ java -cp mysql-connector-j-9.1.0.jar Probe.java "&useServerPrepStmts=false" 'a"b'
보낸 값      : [a"b]
돌려받은 행 수: 1
Query    | SELECT id, name FROM users WHERE name = x'612262'
```

넣은 값은 `A"B`고 물어본 값은 `a"b`다. 16진수 리터럴은 [기본적으로 이진 문자열](https://dev.mysql.com/doc/refman/8.0/en/hexadecimal-literals.html)인데("By default, a hexadecimal literal is a binary string") 대소문자를 무시하고 잡혔다. 컬럼의 `utf8mb4_0900_ai_ci`가 비교에 적용됐다는 뜻이다. 리터럴(4)보다 컬럼(2)의 [coercibility](https://dev.mysql.com/doc/refman/8.0/en/charset-collation-coercibility.html) 값이 낮고, MySQL은 낮은 쪽의 콜레이션을 쓴다.

멀티바이트도 같다. `홍"길동`은 `x'ed998d22eab8b8eb8f99'`로 나가 같은 이름의 행을 찾았다.

확인이 끝나면 되돌린다. 다음 실행은 기본 모드를 전제한다. `DEFAULT`는 서버의 컴파일 기본값이지 방금 `CONCAT`하기 전의 값이 아니다. `sql_mode`를 따로 설정해 둔 서버라면 그 값을 미리 받아 두고 되돌려야 한다.

```text
$ docker exec mybatis-lab mysql -uroot -plabpw -e "SET GLOBAL sql_mode=DEFAULT"
```

### 접속할 때 보내는 질의

`Probe`가 `/*`로 시작하는 줄을 걸러 내므로 위 출력에는 안 나온다. 로그를 비우고 `Connect`로 접속만 한 뒤, 첫 줄을 그대로 보면 이렇다.

```text
$ docker exec mybatis-lab mysql -uroot -plabpw -e \
    "SET GLOBAL general_log=OFF; TRUNCATE mysql.general_log; SET GLOBAL general_log=ON;"

$ java -cp mysql-connector-j-9.1.0.jar Connect.java

$ docker exec mybatis-lab mysql -uroot -plabpw -N -B \
    -e "SELECT CONVERT(argument USING utf8mb4) FROM mysql.general_log
        WHERE command_type='Query' ORDER BY event_time LIMIT 1"

/* mysql-connector-j-9.1.0 (Revision: cf2917ea...) */SELECT  @@session.auto_increment_increment
AS auto_increment_increment, @@character_set_client AS character_set_client, ...
@@performance_schema AS performance_schema, @@sql_mode AS sql_mode, @@system_time_zone
AS system_time_zone, ... @@wait_timeout AS wait_timeout
```

원문은 한 줄이다. 여기서는 리비전 해시와 가운데 변수 목록을 `...`로 줄이고 폭에 맞춰 접었다.

세션 변수를 한 번에 훑는 질의라 `@@wait_timeout`이나 `@@performance_schema`처럼 이스케이프와 무관한 것도 함께 들어 있다. 이 중 `@@sql_mode`는 실제로 리터럴 형태를 갈랐다. 문자셋 변수들도 값을 바이트로 옮길 때 쓰일 것으로 보인다. 16진수로 간 두 값이 전부 ASCII라 이번 출력에서는 드러나지 않았다.

드라이버가 이 응답을 보고 형태를 정하는지, 아니면 [OK 패킷의 `status_flags`](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_ok_packet.html)를 보는지까지는 이 실험으로 가르지 못한다. 접속하자마자 물어본다는 것, 그리고 `sql_mode`를 바꾸면 리터럴 형태가 바뀐다는 것까지가 확인된 사실이다.

### 실험 코드

두 파일 전문이다. 로그를 비우고 켜는 일, 질의 실행, 결과 출력이 모두 `Probe` 안에 있다.

```java
import java.sql.*;

// 사용법: java -cp mysql-connector-j-9.1.0.jar Probe.java <접속 옵션> <보낼 값> [concat]
public class Probe {
    static final String BASE = "jdbc:mysql://127.0.0.1:13306/lab?user=root&password=labpw";

    public static void main(String[] args) throws Exception {
        String params = args[0], value = args[1];
        boolean concat = args.length > 2;

        exec("SET GLOBAL general_log=OFF", "TRUNCATE mysql.general_log", "SET GLOBAL general_log=ON");

        int rows = 0;
        try (Connection c = DriverManager.getConnection(BASE + params)) {
            if (concat) {                                    // ${} 흉내: 직접 이어 붙인다
                String sql = "SELECT id, name FROM users WHERE name = '" + value + "'";
                try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(sql)) {
                    while (rs.next()) rows++;
                }
            } else {                                         // #{}가 만드는 것: ?에 바인딩한다
                try (PreparedStatement ps = c.prepareStatement("SELECT id, name FROM users WHERE name = ?")) {
                    ps.setString(1, value);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) rows++;
                    }
                }
            }
        }
        exec("SET GLOBAL general_log=OFF");

        System.out.println("보낸 값      : [" + value + "]");
        System.out.println("돌려받은 행 수: " + rows);
        try (Connection c = DriverManager.getConnection(BASE); Statement s = c.createStatement();
             ResultSet rs = s.executeQuery(
                 "SELECT command_type, CONVERT(argument USING utf8mb4) FROM mysql.general_log"
               + " WHERE command_type IN ('Query','Prepare','Execute') ORDER BY event_time")) {
            while (rs.next()) {
                String q = rs.getString(2).replace("\n", " ").trim();
                if (q.startsWith("/*") || q.contains("general_log") || q.startsWith("SET ")) continue;
                System.out.printf("%-8s | %s%n", rs.getString(1), q);
            }
        }
    }

    static void exec(String... sqls) throws SQLException {
        try (Connection c = DriverManager.getConnection(BASE); Statement s = c.createStatement()) {
            for (String sql : sqls) s.execute(sql);
        }
    }
}
```

`Connect`는 접속만 하고 끊는다. 핸드셰이크 질의를 잡을 때 쓴다.

```java
import java.sql.*;

public class Connect {
    public static void main(String[] a) throws Exception {
        DriverManager.getConnection("jdbc:mysql://127.0.0.1:13306/lab?user=root&password=labpw").close();
    }
}
```

## 경계 조건

**뚫린 것은 문자열을 직접 이어 붙인 경우 하나뿐이다.** `?`에 바인딩한 셋은 `useServerPrepStmts`를 켜도 `sql_mode`를 바꿔도 0행이었다. `${}`가 위험한 이유가 여기 있다. 드라이버가 개입할 기회 자체가 없다.

**클라이언트 조립의 안전은 드라이버 구현에 기댄다.** 값이 파서를 통과한다는 사실은 그대로다. 통과해도 문법이 되지 않는 것은 드라이버가 리터럴 경계를 지켜 줬기 때문이다.

위 실험은 Connector/J 9.1.0이 그 일을 해낸다는 것을 보여 줄 뿐, 모든 드라이버가 그렇다는 보장은 아니다. 반대로 서버 사이드 prepare는 그 판단을 서버의 파싱 순서에 맡기므로 구현 품질에 덜 기댄다.

**서버 사이드 prepare를 켜도 항상 그 경로를 타지는 않는다.** Connector/J는 서버가 준비하지 못하는 문장을 만나면 [`emulateUnsupportedPstmts`](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-prepared-statements.html)(기본 `true`)에 따라 클라이언트 조립으로 조용히 내려간다. 이건 문서에 있는 동작이고 이번 실험에서 재현하지는 않았다.

**`general_log`는 실험용이다.** 켜 두면 바인딩된 값까지 평문으로 남는다. 확인이 끝나면 끈다. `sql_mode`는 켰던 절에서 되돌렸다.

```sql
SET GLOBAL general_log=OFF;
```

## 언제 쓰고 언제 안 쓰나

`useServerPrepStmts`를 켤지는 인젝션 방어와 무관하다. 두 경로 모두 막았다. 판단 기준은 같은 문장을 반복 실행해 파싱 비용을 아낄 수 있느냐다. MySQL에서 이 설정으로 얻는 것이 파싱 비용 절감이지 실행계획 재사용이 아니라는 점은 [기본개념 글](/posts/mybatis-parameter-binding/#구현체별-차이)에서 다뤘다.

이 옵션만 켜면 절감이 일어나지 않는다. 핸들을 캐시하는 것은 [`cachePrepStmts`](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-performance-extensions.html)이고 기본값이 `false`라, 이걸 같이 켜지 않으면 `prepareStatement()`마다 다시 prepare해서 왕복이 계속 2회다.

파싱을 한 번 더 하지 않으려다 왕복을 한 번 더 하는 셈이 된다.

## 참고

- [MySQL — The General Query Log](https://dev.mysql.com/doc/refman/8.0/en/query-log.html)
- [MySQL — Server SQL Modes](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html)
- [MySQL — Hexadecimal Literals](https://dev.mysql.com/doc/refman/8.0/en/hexadecimal-literals.html)
- [MySQL — Protocol COM_STMT_PREPARE](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_prepare.html)
- [MySQL — Protocol COM_STMT_EXECUTE](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_execute.html)
- [Connector/J 9.1.0 소스 — StringValueEncoder.java](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/protocol-impl/java/com/mysql/cj/protocol/a/StringValueEncoder.java)
- [Connector/J 9.1.0 소스 — AbstractValueEncoder.java](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/protocol-impl/java/com/mysql/cj/protocol/a/AbstractValueEncoder.java)
- [Connector/J 9.1.0 소스 — StringUtils.java](https://github.com/mysql/mysql-connector-j/blob/9.1.0/src/main/core-api/java/com/mysql/cj/util/StringUtils.java)
- [MySQL Connector/J — Performance Extensions 설정](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-performance-extensions.html)
- [MySQL Connector/J — Prepared Statements 설정](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-prepared-statements.html)
