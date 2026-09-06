---
title: 리팩토링의 경계 — 무엇까지가 리팩토링인가
description: 동작을 바꾸면 리팩토링이 아니다. 기능 변경·버그 수정·최적화·재구조화와 갈라놓고 경계를 정한다
pubDate: 2026-08-19
updatedDate: 2026-09-06
category: "코드 품질"
tags: ["기본개념", "리팩토링", "Kotlin"]
---

## 무엇이 문제인가

"리팩토링했습니다"라고 올라온 PR에 기능 변경이 섞여 있는 일이 잦다. 변수 이름을 바꾸는 김에 조건 하나를 고치고, 메서드를 쪼개는 김에 예외 처리를 추가한 식이다.

섞이면 두 가지가 무너진다. 리뷰어는 구조 변경 100줄 속에서 동작이 바뀐 3줄을 찾아야 한다. 장애가 나서 되돌릴 때는 개선까지 같이 사라진다.

그래서 경계가 필요하다. 리팩토링은 "코드를 개선하는 일" 같은 넓은 말이 아니라 조건이 붙은 작업이다.

## 용어 정리

- **리팩토링(refactoring)**: 마틴 파울러의 [정의](https://refactoring.com/)는 명사와 동사 두 가지다.

  > (noun) a change made to the internal structure of software to make it easier to understand and cheaper to modify without changing its observable behavior
  >
  > (verb) to restructure software by applying a series of refactorings without changing its observable behavior

  핵심은 뒷부분이다. **관측 가능한 동작을 바꾸지 않는다.**

- **관측 가능한 동작(observable behavior)**: 호출하는 쪽에서 볼 수 있는 것. 반환값, 던지는 예외, 외부에 남기는 부수효과(DB 기록, 네트워크 호출)가 여기 든다. 응답시간이나 로그처럼 경계가 애매한 것은 그것에 의존하는 소비자가 있는지로 가른다. 계약에 적힌 응답시간과 다른 시스템이 파싱하는 로그는 관측 동작이고, 사람만 읽는 디버그 로그는 아니다.

- **재구조화(restructuring)**: 구조를 바꾸는 일 전반. 리팩토링은 그중 **동작을 보존하는 작은 단계로만** 진행하는 특정 기법이다. 파울러는 이 구분이 흐려지는 것을 [Refactoring Malapropism](https://martinfowler.com/bliki/RefactoringMalapropism.html)이라 부른다.

- **재작성(rewrite)**: 기존 코드를 버리고 다시 만드는 일. 중간에 시스템이 동작하지 않는 구간이 생긴다.

## 핵심 정리

기준은 하나다. **관측 가능한 동작이 바뀌는가.**

| 활동 | 관측 동작 | 목적 | 끝났음을 확인하는 수단 |
|---|---|---|---|
| 리팩토링 | 그대로 | 구조 개선 | 기존 테스트를 **고치지 않고** 결과가 그대로 |
| 재구조화 | 보장되지 않는다 | 구조 변경 | 방법에 따라 다르다 |
| 기능 추가·변경 | 바뀐다 | 요구사항 반영 | 새로 쓴 테스트가 통과 |
| 버그 수정 | 바뀐다 (틀린 동작 → 맞는 동작) | 결함 제거 | 실패하던 테스트가 통과 |
| 성능 최적화 | 기능은 그대로, 시간·자원은 바뀐다 | 비기능 요구 충족 | 측정값 |
| 재작성 | 보장되지 않는다 | 교체 | 새로 만든 검증 전체 |
| 포매팅 | 그대로 | 가독성 | 컴파일 |

## 항목별 설명

**확인 수단은 통과가 아니라 "결과가 그대로"다.** 실패하던 테스트는 리팩토링 뒤에도 똑같이 실패해야 한다. 버그를 고치기 전에 고칠 자리가 드러나도록 구조부터 정리하는 경우가 그렇다. 이때 테스트가 초록으로 바뀌었다면 리팩토링이 아니라 버그까지 고친 것이다.

**성능 최적화가 가장 헷갈린다.** 기능 동작을 보존하므로 리팩토링과 같아 보이지만 방향이 반대다. 리팩토링은 읽기 쉬운 쪽으로 가고, 최적화는 캐시·배치·루프 펼치기처럼 읽기 어려운 쪽으로 간다. 확인 수단도 테스트가 아니라 측정값이다.

한 커밋에 섞으면 나중에 느려졌을 때 어느 변경 탓인지 가를 수 없다.

**시스템이 깨져 있는 시간이 있으면 리팩토링이 아니라 재구조화다.** 파울러의 [판별 기준](https://martinfowler.com/bliki/RefactoringMalapropism.html)은 이렇다.

> If somebody talks about a system being broken for a couple of days while they are refactoring, you can be pretty sure they are not refactoring. If someone talks about refactoring a document, then that's not refactoring. Both of these are restructuring.

재작성까지 간 것은 아니다. 코드를 버리지 않았으니 결과물은 여전히 같은 코드다. 동작 보존을 확인할 수단 없이 구조를 바꿨을 뿐이고, 파울러가 그 자리에 붙인 이름이 재구조화다.

**이름 변경은 리팩토링이고 포매팅은 아니다.** 둘을 가르는 것은 동작이 아니라 구조다. 둘 다 관측 동작을 보존하지만, 공백과 줄바꿈 정리는 내부 구조를 건드리지 않는다. 반면 이름 변경은 [Rename Variable](https://refactoring.com/catalog/renameVariable.html)로 카탈로그에 오른 정식 리팩토링이다. 파울러의 정의가 말하는 "이해하기 쉽게 만드는 내부 구조 변경"에 이름이 든다.

## 예시

**리팩토링이다.** [Extract Function](https://refactoring.com/catalog/extractFunction.html)을 적용했다.

```kotlin
// before
fun checkout(cart: Cart): Int {
    var total = 0
    for (line in cart.lines) {
        total += line.price * line.qty
    }
    val coupon = cart.coupon
    if (coupon != null && total >= 30_000) {
        total -= total * coupon.rate / 100
    }
    return total
}

// after
fun checkout(cart: Cart): Int {
    val total = subtotal(cart)
    return total - discount(cart, total)
}

private fun subtotal(cart: Cart): Int = cart.lines.sumOf { it.price * it.qty }

private fun discount(cart: Cart, total: Int): Int {
    val coupon = cart.coupon ?: return 0
    if (total < 30_000) return 0
    return total * coupon.rate / 100
}
```

`checkout`의 반환값은 모든 입력에서 같다. 기존 테스트를 한 줄도 고치지 않고 통과시킬 수 있다.

**리팩토링이 아니다.** [Extract Variable](https://refactoring.com/catalog/extractVariable.html)을 적용한 것처럼 보이지만 관측 동작이 바뀐다.

```kotlin
// before — fetchDefaultName()은 최대 한 번, 필요할 때만 호출된다
fun label(user: User?): String {
    if (user == null) return fetchDefaultName()
    return user.profile?.nickname ?: fetchDefaultName()
}

// after — "중복 호출을 변수로 묶었다"
fun label(user: User?): String {
    val default = fetchDefaultName()
    if (user == null) return default
    return user.profile?.nickname ?: default
}
```

`fetchDefaultName()`이 원격 호출이나 DB 조회라면 이제 닉네임이 있는 사용자에게도 매번 호출된다. 반환값만 보는 테스트는 통과하므로 잡히지 않는다. `?:`는 왼쪽이 null일 때만 오른쪽을 계산하는데, 값을 미리 변수로 빼면서 그 조건이 사라졌다.

**이것도 리팩토링이 아니다.** 예외 타입도 관측 가능한 동작이다.

```kotlin
// before
val port = config["port"]!!.toInt()          // 키가 없으면 NullPointerException

// after
val port = config.getValue("port").toInt()   // 키가 없으면 NoSuchElementException
```

`!!`를 없앤 정리로 보이지만, 위쪽 예외를 잡던 호출자가 있으면 깨진다.

## 혼동하기 쉬운 것

| 흔한 말 | 실제 |
|---|---|
| "리팩토링하면서 이 버그도 고쳤다" | 버그 수정이 섞인 것이다. 커밋을 나눈다 |
| "리팩토링이라 테스트는 안 고쳤다" | 맞다. 테스트를 고쳐야 했다면 동작이 바뀐 것이다 |
| "이번 스프린트는 리팩토링만" | 며칠씩 깨져 있다면 재구조화다 |
| "성능 개선 리팩토링" | 최적화다. 확인 수단이 테스트가 아니라 측정값이다 |

두 번째 줄이 실무에서 가장 빠른 판별법이다. 관측 동작이 바뀌었는지를 직접 재는 대신 테스트를 손댔는지만 보면 된다. **기존 테스트를 고쳐야 통과한다면 그건 리팩토링이 아니다.**

## 참고

- [Refactoring — 정의와 카탈로그](https://refactoring.com/)
- [Refactoring Malapropism](https://martinfowler.com/bliki/RefactoringMalapropism.html)
