---
title: PostgreSQL numeric과 double precision
description: 같은 소수를 담는 두 타입이 저장 방식부터 갈린다. 오차, 반올림, 비교, 속도에서 무엇이 달라지는지 PostgreSQL 16에서 확인한다
pubDate: 2026-08-24
category: "데이터베이스"
tags: ["기본개념", "Database", "PostgreSQL"]
---

## 무엇이 문제인가

금액 컬럼을 `double precision`으로 잡으면 합계가 어긋난다. 1부터 300만까지에 각각 `1.0000001`을 곱해 더하면 정확한 값은 `4500001950000.15`인데, `double precision`으로 계산하면 `4500001950000.536`이 나온다. 0.386 차이다. 같은 계산을 `numeric`으로 하면 `4500001950000.15`가 그대로 나온다.

두 타입 모두 소수를 담지만 담는 방식이 다르다. 어느 쪽을 골랐는지가 오차뿐 아니라 반올림 방향, 비교 결과, 연산 속도까지 바꾼다.

## 핵심 정리

| 항목 | `numeric` | `double precision` |
|---|---|---|
| 저장 방식 | 10진수를 그대로 저장 | [IEEE 754](https://ko.wikipedia.org/wiki/IEEE_754) 2진 부동소수점 |
| 크기 | 가변. 10진 4자리마다 2바이트 + 3~8바이트 오버헤드 | 8바이트 고정 |
| 범위 | 소수점 앞 131072자리, 뒤 16383자리 | 약 1E-307 ~ 1E+308 |
| 정밀도 | 선언한 자릿수까지 정확 | 최소 15자리 |
| `0.1` 같은 10진 소수 | 오차 없음 | 오차 있음 |
| 연산 | 소프트웨어로 계산. 느리다 | CPU 부동소수점 명령 |
| `round()` 동작 | 0에서 먼 쪽으로 (`2.5` → `3`) | 가까운 짝수로 (`2.5` → `2`, 대부분의 장비에서) |
| 자릿수 초과 | `numeric(p,s)`는 정수부 초과면 에러, 소수부는 반올림 | 조용히 반올림 |
| 집계 순서 | 결과 동일 | 더하는 순서에 따라 달라짐 |

## 항목별 설명

### 0.1을 담는 방식이 다르다

`double precision`은 값을 `부호 × 가수 × 2^지수` 꼴로 저장한다. 밑이 2이므로 분모가 2의 거듭제곱인 분수만 정확히 표현된다. `0.5`(1/2)나 `0.25`(1/4)는 정확하지만 `0.1`(1/10)은 그렇지 않다. 10진수로 1/3을 `0.333...`으로밖에 못 쓰는 것과 같은 사정이다. 저장하는 순간 가장 가까운 2진 소수로 반올림되고, 그 미세한 차이가 연산을 거치며 드러난다.

`numeric`은 10진 숫자를 4자리씩 묶어 그대로 저장한다. `0.1`은 `0.1`로 들어가고 나온다. 대신 CPU가 직접 계산하지 못해 PostgreSQL이 소프트웨어로 자릿수를 하나씩 처리한다. 공식 문서도 [`numeric` 연산이 "정수 타입이나 부동소수점 타입에 비해 매우 느리다(very slow compared to the integer types, or to the floating-point types)"](https://www.postgresql.org/docs/16/datatype-numeric.html#DATATYPE-NUMERIC-DECIMAL)고 적는다.

### 정밀도 15자리의 의미

`double precision`의 "최소 15자리"는 소수점 아래 15자리가 아니라 유효숫자 15자리다. 정수 부분이 길어지면 그 정수도 정확히 담기지 못한다.

`float8`은 `double precision`의 별칭이다.

```sql
select 9007199254740993::float8, 9007199254740993::numeric;
--         float8         |     numeric
-- -----------------------+------------------
--  9.007199254740992e+15 | 9007199254740993
```

`9007199254740993`은 2^53 + 1이다. 가수가 53비트라 이 값부터는 홀수를 표현할 수 없고, 가장 가까운 표현 가능한 값으로 반올림된다. 홀수는 위아래 두 짝수 사이에 정확히 놓이므로 가수가 짝수인 쪽으로 붙는다. `9007199254740993`은 아래로 `...992`가 되고 `9007199254740995`는 위로 `...996`이 된다.

## 예시

PostgreSQL 16.14에서 실행한 결과다.

```sql
select 0.1::float8 + 0.2::float8       as f8_sum,
       0.1::numeric + 0.2::numeric     as num_sum,
       0.1::float8 + 0.2::float8 = 0.3::float8     as f8_eq,
       0.1::numeric + 0.2::numeric = 0.3::numeric  as num_eq;

--        f8_sum        | num_sum | f8_eq | num_eq
-- ---------------------+---------+-------+--------
--  0.30000000000000004 |     0.3 | f     | t
```

`0.1`과 `0.2`가 각각 가장 가까운 2진 소수로 반올림된 뒤 더해지므로 결과가 `0.3`에서 벗어난다. 공식 문서는 이 때문에 [부동소수점 값을 같은지 비교하는 것이 "기대대로 동작하지 않을 수 있다(might not always work as expected)"](https://www.postgresql.org/docs/16/datatype-numeric.html#DATATYPE-FLOAT)고 경고한다.

같은 값을 더해도 순서가 다르면 결과가 갈린다.

```sql
select sum(v)::text from (select unnest(array[1e16, 1, 1, 1, 1])::float8 as v) t;
--  1e+16

select sum(v)::text from (select unnest(array[1, 1, 1, 1, 1e16])::float8 as v) t;
--  1.0000000000000004e+16

select sum(v)::text from (select unnest(array[1e16, 1, 1, 1, 1])::numeric as v) t;
--  10000000000000004
```

`1e16`에 `1`을 더하면 결과를 담을 유효숫자가 모자라 `1`이 통째로 버려진다. 작은 값끼리 먼저 더해 `4`를 만든 뒤 `1e16`에 더하면 살아남는다. `numeric`은 순서를 바꿔도 같은 값을 낸다.

앞서 「무엇이 문제인가」에 적은 300만 건 합계도 같은 원인이다. 한 번에 0.386이 벌어지는 게 아니라, 매 덧셈마다 버려진 끝자리가 쌓인 결과다.

```sql
select sum(i::float8   * 1.0000001::float8)   from generate_series(1, 3000000) i;
--  4500001950000.536

select sum(i::numeric  * 1.0000001::numeric)  from generate_series(1, 3000000) i;
--  4500001950000.1500000
```

정확한 값은 `4500001500000 × 1.0000001`, 즉 `4500001950000.15`다. `numeric` 쪽 출력의 꼬리 `0`은 곱한 상수의 소수부 자릿수를 따라간 것이라 값은 같다.

## 혼동하기 쉬운 것

### `0.1`이라고 쓰면 `numeric`이다

PostgreSQL에서 소수점이 붙은 상수는 `double precision`이 아니라 `numeric`이다. 공식 문서에 [소수점이나 지수를 포함하는 상수는 항상 처음에 `numeric` 타입으로 간주된다(Constants that contain decimal points and/or exponents are always initially presumed to be type `numeric`)](https://www.postgresql.org/docs/16/sql-syntax-lexical.html#SQL-SYNTAX-CONSTANTS-NUMERIC)고 적혀 있다.

```sql
select pg_typeof(0.1), pg_typeof(1e10), pg_typeof(0.1::float8);
--  pg_typeof | pg_typeof |    pg_typeof
-- -----------+-----------+------------------
--  numeric   | numeric   | double precision
```

그런데 `float8` 값과 이 상수를 비교하면 `numeric` 쪽이 `float8`로 바뀐다. `float8 = numeric` 연산자가 없어 캐스팅으로 해결되는데, 연산자 해석에는 암묵(implicit) 캐스트만 쓰이기 때문이다. `numeric` → `float8`은 암묵 캐스트(`i`)지만 `float8` → `numeric`은 대입(assignment) 캐스트(`a`)라 여기 쓰이지 않는다.

```sql
select castsource::regtype, casttarget::regtype, castcontext
from pg_cast
where castsource in ('numeric'::regtype, 'float8'::regtype)
  and casttarget in ('numeric'::regtype, 'float8'::regtype);
--     castsource    |    casttarget    | castcontext
-- ------------------+------------------+-------------
--  double precision | numeric          | a
--  numeric          | double precision | i

select 0.1::float8 = 0.1000000000000000055511151231257827::numeric;
--  t
```

`numeric` 쪽 상수가 `float8`로 반올림된 뒤 비교되므로, 이 긴 10진 상수가 `0.1::float8`과 같다고 나온다. 정확한 비교를 원하면 양쪽을 `numeric`으로 맞춰야 한다.

### `round()`가 반올림하는 방향이 다르다

```sql
select round(1.5::numeric), round(2.5::numeric), round(1.5::float8), round(2.5::float8);
--  round | round | round | round
-- -------+-------+-------+-------
--      2 |     3 |     2 |     2
```

`numeric`은 `2.5`를 `3`으로 올리고 `double precision`은 `2`로 내린다. 공식 문서는 [`numeric`이 중간값을 0에서 먼 쪽으로 반올림하는 반면, (대부분의 장비에서) `real`과 `double precision`은 가장 가까운 짝수로 반올림한다(the `numeric` type rounds ties away from zero, while (on most machines) the `real` and `double precision` types round ties to the nearest even number)](https://www.postgresql.org/docs/16/datatype-numeric.html#DATATYPE-NUMERIC-DECIMAL)고 설명한다. 금액을 `float8`로 계산하다 `numeric`으로 옮기면 이 지점에서 1원씩 어긋난다.

### `NaN = NaN`이 참이다

IEEE 754에서 `NaN`은 자기 자신과도 같지 않지만 PostgreSQL은 다르다. [정렬과 트리 기반 인덱스에 쓸 수 있도록 `NaN`끼리는 같다고 보고, `NaN`이 아닌 모든 값보다 크다고 취급한다(PostgreSQL treats `NaN` values as equal, and greater than all non-`NaN` values)](https://www.postgresql.org/docs/16/datatype-numeric.html#DATATYPE-FLOAT). `numeric`과 `double precision` 모두 같다.

```sql
select 'NaN'::float8 = 'NaN'::float8, 'NaN'::numeric = 'NaN'::numeric;
--  ?column? | ?column?
-- ----------+----------
--  t        | t
```

## 언제 어떤 것을 쓰나

10진수로 적힌 값이 그대로 보존돼야 하면 `numeric`이다. 금액, 수량, 세율, 사용자가 입력한 소수가 여기 해당한다. `numeric(p,s)`로 자릿수를 선언하면 정수부 자릿수를 넘는 값이 에러로 걸러지는 것도 이득이다.

```sql
select 1234.5::numeric(5,2);
-- ERROR:  numeric field overflow
-- DETAIL:  A field with precision 5, scale 2 must round to an absolute value less than 10^3.
```

걸러지는 건 정수부 초과뿐이다. 소수부는 선언한 자리까지 조용히 반올림된다. `1.239::numeric(5,2)`는 에러 없이 `1.24`가 된다.

측정값처럼 애초에 오차를 안고 들어오는 값, 좌표나 통계처럼 마지막 자리가 의미 없는 값은 `double precision`이 맞다. 8바이트 고정이라 저장 공간을 예측하기 쉽고 연산도 빠르다. 앞의 300만 건 쿼리를 그대로 재서 `double precision`이 458~571ms, `numeric`이 911~943ms였다. 다른 컨테이너가 함께 도는 개발용 장비에서 워밍업 없이 두 번씩 잰 값이라 절대치보다 배율의 경향만 볼 값이다.

경계에 있는 값은 실제로 무엇을 하는 컬럼인지로 가른다. 같은 소수점 둘째 자리라도 결제 금액이면 `numeric`이고 센서가 읽은 온도면 `double precision`이다.

## 참고

- [PostgreSQL 16 문서 — Numeric Types](https://www.postgresql.org/docs/16/datatype-numeric.html)
- [PostgreSQL 16 문서 — Numeric Constants](https://www.postgresql.org/docs/16/sql-syntax-lexical.html#SQL-SYNTAX-CONSTANTS-NUMERIC)
- [IEEE 754](https://ko.wikipedia.org/wiki/IEEE_754)
