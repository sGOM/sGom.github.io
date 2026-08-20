---
title: MyBatis의 #{}와 ${} — 바인딩과 문자열 치환
description: 두 표기가 각각 어떤 SQL을 만드는지, 왜 하나는 안전하고 하나는 위험한지 정리한다
pubDate: 2026-08-20
category: "데이터베이스"
tags: ["기본개념", "Database", "MyBatis"]
---

## 왜 필요한가

`#{}`와 `${}`는 매퍼 XML에서 똑같이 값을 끼워 넣는 것처럼 보인다. 그런데 `${}`로 검색어를 받으면 SQL 인젝션이 뚫리고, `#{}`로 정렬 컬럼을 받으면 정렬이 의도대로 되지 않는다.

둘은 값을 끼우는 시점과 방식이 다르다. 그 차이를 알면 어느 자리에 무엇을 쓸지 외우지 않아도 된다.

## 용어 정리

- **PreparedStatement**: SQL 문장과 값을 분리해 다루는 JDBC 인터페이스. 값이 들어갈 자리는 `?`로 표시한다. ([javadoc](https://docs.oracle.com/en/java/javase/21/docs/api/java.sql/java/sql/PreparedStatement.html))
- **바인딩(binding)**: `?` 자리에 값을 전달하는 것. 값은 SQL 문장과 분리된 경로로 드라이버에 넘어간다.
- **문자열 치환(string substitution)**: SQL 문장을 만들기 전에 그 자리에 문자열을 그대로 이어 붙이는 것. 붙은 문자열은 SQL 문장의 일부가 된다.
- **[TypeHandler](https://mybatis.org/mybatis-3/configuration.html#typeHandlers)**: 자바 타입과 JDBC 타입 사이를 변환하는 MyBatis 구성 요소. `#{}` 값은 이 경로를 거쳐 `PreparedStatement`에 설정된다.

## 핵심 정리

| | `#{}` | `${}` |
|---|---|---|
| 하는 일 | `?`를 만들고 값을 바인딩한다 | 문자열을 그대로 이어 붙인다 |
| 값이 반영되는 단계 | JDBC 드라이버 | MyBatis가 SQL 문장을 만드는 중 |
| 값의 신분 | 데이터 | SQL 문장의 일부 |
| 값을 문법에서 떼어놓는 주체 | 드라이버와 DB | 없다. 직접 해야 한다 |
| SQL 인젝션 | 안전하다 | 뚫린다 |
| 따옴표·이스케이프 | 알아서 처리된다 | 직접 붙여야 한다 |
| 넣을 수 있는 것 | 값만 | 값, 테이블명, 컬럼명, 키워드 |
| 문장 재사용 | 가능. SQL 문자열이 값과 무관하게 고정된다 | 불가. 값마다 SQL 문자열이 달라진다 |

**`#{}`를 기본으로 쓰고, `#{}`로 불가능한 자리에만 `${}`를 쓴다.** MyBatis 공식 문서도 `#{}`가 "safer, faster and almost always preferred"라고 못 박는다. ([sqlmap-xml — String Substitution](https://mybatis.org/mybatis-3/sqlmap-xml.html#String_Substitution))

## 항목별 설명

**`#{}`가 안전한 것은 값이 SQL 문법으로 해석되지 않기 때문이다.** 그 보장은 애플리케이션 코드가 아니라 JDBC 드라이버와 DB가 나눠 진다. 드라이버가 택하는 경로는 둘이고, 어느 쪽이든 결과는 같다. 서버 사이드 prepare면 `?`가 박힌 문장을 DB가 먼저 파싱해 두고 값은 나중에 따로 받는다. 클라이언트에서 조립하면 드라이버가 값을 이스케이프해 완성된 SQL을 보낸다. `' OR 1=1 --`을 넣어도 어느 경로에서든 그런 내용의 문자열로만 남는다. 자바 값을 JDBC 타입으로 옮기는 일은 그 앞단에서 TypeHandler가 맡는다.

**`${}`는 그 보호 밖에 있다.** MyBatis가 SQL 문장을 조립하는 단계에서 이어 붙이므로, 드라이버가 문장을 받았을 때는 이미 문법의 일부다. 값이었는지 구분할 방법이 없다.

**`${}`가 필요한 이유는 `?`를 아무 데나 쓸 수 없기 때문이다.** `?`는 값이 오는 자리에만 놓을 수 있다. 테이블명, 컬럼명, `ASC`/`DESC` 같은 키워드는 파싱 시점에 확정돼야 하므로 바인딩 대상이 아니다. 이 자리를 동적으로 바꾸려면 SQL 문장 자체를 다르게 만드는 수밖에 없고, 그게 `${}`다.

**`${}`는 화이트리스트로만 쓴다.** 미리 정해 둔 허용 목록에 있는 값인지 확인하고, 없으면 기본값으로 떨어뜨린다. 반대로 위험한 문자와 패턴을 걸러내는 블랙리스트 방식은 우회 방법이 계속 나온다.

## 예시

같은 파라미터를 두 표기로 받았을 때 만들어지는 SQL이다.

```xml
<select id="findByName" resultType="User">
  SELECT * FROM users WHERE name = #{name}
</select>
```

```sql
SELECT * FROM users WHERE name = ?
```

값 `홍길동`은 `?` 자리로 넘어간다. 따옴표는 붙이지 않는다.

```xml
<select id="findByName" resultType="User">
  SELECT * FROM users WHERE name = '${name}'
</select>
```

```sql
SELECT * FROM users WHERE name = '홍길동'
```

문자열이므로 따옴표를 직접 써야 한다. 그리고 이 따옴표가 뚫린다. `name`으로 `' OR '1'='1`이 들어오면 이렇게 된다.

```sql
SELECT * FROM users WHERE name = '' OR '1'='1'
```

조건이 항상 참이 되어 전체 행이 나온다. `#{}` 쪽은 같은 입력이 와도 `name`이 `' OR '1'='1`인 행을 찾을 뿐이다.

정렬 컬럼처럼 `#{}`가 통하지 않는 자리는 이렇게 쓴다.

```xml
<select id="findAll" resultType="User">
  SELECT * FROM users ORDER BY ${orderBy} ${direction}
</select>
```

```java
// 허용 목록에 없으면 기본값으로 떨어뜨린다.
// Set.of(...).contains(null)은 NPE를 던지므로 null을 먼저 거른다.
private static final Set<String> SORTABLE = Set.of("name", "created_at");

String orderBy = input != null && SORTABLE.contains(input) ? input : "created_at";
String direction = "desc".equalsIgnoreCase(dir) ? "DESC" : "ASC";
```

## 혼동하기 쉬운 것

**`#{}`에 따옴표를 붙이면 안 된다.** MyBatis는 따옴표 안팎을 가리지 않고 `#{name}`을 `?`로 바꾸므로 `'#{name}'`은 `'?'`가 된다. 문자열 리터럴 안의 `?`는 드라이버가 파라미터 자리로 보지 않는다. 넘길 값은 있는데 받을 자리가 없어 실패한다.

**`ORDER BY #{orderBy}`는 컬럼을 가리키지 못한다.** `ORDER BY ?`가 만들어지고 컬럼명이 아니라 문자열 값이 바인딩된다. 이때 에러를 내는지는 DBMS마다 다른데, 넘어가더라도 모든 행이 같은 값을 정렬 기준으로 갖는 셈이라 의도한 순서가 나오지 않는다. 어느 쪽이든 `${}`로 바꿔야 한다.

**`LIKE '%${keyword}%'`는 `${}`를 쓸 이유가 없다.** 와일드카드는 값의 일부이므로 자바 쪽에서 붙여 `#{}`로 넘기면 된다. 매퍼 안에서 처리하려면 [`<bind>`](https://mybatis.org/mybatis-3/dynamic-sql.html#bind)를 쓴다. `value` 안의 이름은 파라미터 이름으로 해석되므로 `@Param`이 필요하다.

```java
List<User> search(@Param("keyword") String keyword);
```

```xml
<select id="search" resultType="User">
  <bind name="pattern" value="'%' + keyword + '%'" />
  SELECT * FROM users WHERE name LIKE #{pattern}
</select>
```

**`IN (#{ids})`로 리스트를 넘길 수 없다.** `?` 하나에는 값 하나만 바인딩된다. [`<foreach>`](https://mybatis.org/mybatis-3/dynamic-sql.html#foreach)를 쓰면 원소 개수만큼 `?`가 만들어진다. `collection`에 쓸 이름도 `@Param`으로 붙여야 한다.

```java
List<User> findByIds(@Param("ids") List<Long> ids);
```

```xml
<select id="findByIds" resultType="User">
  SELECT * FROM users WHERE id IN
  <foreach item="id" collection="ids" open="(" separator="," close=")">
    #{id}
  </foreach>
</select>
```

## 구현체별 차이

`#{}`가 만든 `?`를 드라이버가 어떻게 처리하는지는 제품과 설정에 따라 다르다. 인젝션 안전성은 어느 쪽이든 유지되지만, 문장을 재사용하는지와 재사용해서 무엇을 아끼는지가 여기서 갈린다.

| 드라이버 | 기본 동작 |
|---|---|
| MySQL Connector/J | `useServerPrepStmts`가 `false`다. 서버 사이드 prepare를 쓰지 않고 드라이버가 클라이언트에서 값을 채운 SQL을 보낸다 |
| PostgreSQL JDBC | Extended Protocol을 쓴다. 같은 문장이 `prepareThreshold`(기본 5)회 실행되면 named statement로 전환하고, 그때부터 계획 재사용 여지가 생긴다 |

**MySQL에서 `useServerPrepStmts=true`로 얻는 것은 파싱 비용 절감이지 실행계획 재사용이 아니다.** MySQL 매뉴얼이 드는 prepared statement의 이점은 파싱 오버헤드 절감과 인젝션 방어 둘뿐이다. ([Connector/J 설정](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-prepared-statements.html), [MySQL — SQL Prepared Statements](https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html), [PostgreSQL JDBC](https://jdbc.postgresql.org/documentation/server-prepare/))

## 언제 어떤 것을 쓰나

| 넣을 것 | 표기 |
|---|---|
| WHERE 조건값, INSERT/UPDATE 값 | `#{}` |
| LIKE 패턴 | `#{}` (와일드카드는 값에 포함) |
| IN 목록 | `<foreach>` + `#{}` |
| LIMIT/OFFSET | `#{}` (값이다) |
| 테이블명, 컬럼명 | `${}` + 화이트리스트 |
| ORDER BY 컬럼, ASC/DESC | `${}` + 화이트리스트 |

## 참고

- [MyBatis — String Substitution](https://mybatis.org/mybatis-3/sqlmap-xml.html#String_Substitution)
- [MyBatis FAQ — What is the difference between #{...} and ${...}?](https://github.com/mybatis/mybatis-3/wiki/FAQ)
- [MyBatis — Dynamic SQL](https://mybatis.org/mybatis-3/dynamic-sql.html)
- [java.sql.PreparedStatement javadoc](https://docs.oracle.com/en/java/javase/21/docs/api/java.sql/java/sql/PreparedStatement.html)
- [MySQL Connector/J — Prepared Statements 설정](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-prepared-statements.html)
- [MySQL — SQL Prepared Statements](https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html)
- [PostgreSQL JDBC — Server Prepared Statements](https://jdbc.postgresql.org/documentation/server-prepare/)
