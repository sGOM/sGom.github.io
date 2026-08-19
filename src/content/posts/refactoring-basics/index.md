---
title: 리팩토링의 경계 — 무엇까지가 리팩토링인가
description: 동작을 바꾸면 리팩토링이 아니다. 인접한 작업들과 갈라놓고, 좋은 리팩토링의 판단 기준을 정리한다
pubDate: 2026-08-19
category: "리팩토링"
tags: ["기본개념", "리팩토링", "Kotlin"]
---

## 왜 필요한가

"리팩토링했습니다"라고 올라온 PR에 기능 변경이 섞여 있는 일이 잦다. 변수 이름을 바꾸는 김에 조건 하나를 고치고, 메서드를 쪼개는 김에 예외 처리를 추가한 식이다.

섞이면 두 가지가 무너진다. 리뷰어는 구조 변경 100줄 속에서 동작이 바뀐 3줄을 찾아야 한다. 장애가 나서 되돌릴 때는 개선까지 같이 사라진다.

그래서 경계가 필요하다. 리팩토링은 "코드를 개선하는 일" 같은 넓은 말이 아니라 조건이 붙은 작업이다.

## 용어 정리

- **리팩토링(refactoring)**: 마틴 파울러의 [정의](https://refactoring.com/)는 명사와 동사 두 가지다.

  > (noun) a change made to the internal structure of software to make it easier to understand and cheaper to modify without changing its observable behavior
  >
  > (verb) to restructure software by applying a series of refactorings without changing its observable behavior

  핵심은 뒷부분이다. **관측 가능한 동작을 바꾸지 않는다.**

- **관측 가능한 동작(observable behavior)**: 호출하는 쪽에서 볼 수 있는 것. 반환값, 던지는 예외, 외부에 남기는 부수효과(DB 기록, 네트워크 호출)가 여기 든다. 응답시간이나 내부 로그처럼 경계가 애매한 것도 있다.

- **재구조화(restructuring)**: 구조를 바꾸는 일 전반. 리팩토링은 그중 **동작을 보존하는 작은 단계로만** 진행하는 특정 기법이다. 파울러는 이 구분이 흐려지는 것을 [Refactoring Malapropism](https://martinfowler.com/bliki/RefactoringMalapropism.html)이라 부른다.

- **재작성(rewrite)**: 기존 코드를 버리고 다시 만드는 일. 중간에 시스템이 동작하지 않는 구간이 생긴다.

## 핵심 정리

기준은 하나다. **관측 가능한 동작이 바뀌는가.**

| 활동 | 관측 동작 | 목적 | 끝났음을 확인하는 수단 |
|---|---|---|---|
| 리팩토링 | 그대로 | 구조 개선 | 기존 테스트가 **고치지 않고** 그대로 통과 |
| 기능 추가·변경 | 바뀐다 | 요구사항 반영 | 새로 쓴 테스트가 통과 |
| 버그 수정 | 바뀐다 (틀린 동작 → 맞는 동작) | 결함 제거 | 실패하던 테스트가 통과 |
| 성능 최적화 | 기능은 그대로, 시간·자원은 바뀐다 | 비기능 요구 충족 | 측정값 |
| 재작성 | 보장되지 않는다 | 교체 | 새로 만든 검증 전체 |
| 포매팅 | 그대로 | 가독성 | 컴파일 |

## 항목별 설명

**성능 최적화가 가장 헷갈린다.** 기능 동작을 보존하므로 리팩토링과 같아 보이지만 방향이 반대다. 리팩토링은 읽기 쉬운 쪽으로 가고, 최적화는 캐시·배치·루프 펼치기처럼 읽기 어려운 쪽으로 간다. 확인 수단도 테스트가 아니라 측정값이다. 한 커밋에 섞으면 나중에 느려졌을 때 어느 변경 탓인지 가를 수 없다.

**버그 수정은 리팩토링이 아니지만 순서를 나눌 수 있다.** 실패하는 테스트를 먼저 만들고, 고칠 자리가 드러나도록 리팩토링하고(이 시점에도 테스트는 여전히 실패한다), 그다음 고친다. 커밋이 둘로 나뉘고 각각이 검증된다.

**시스템이 깨져 있는 시간이 있으면 재작성이다.** 파울러의 판별 기준은 이렇다.

> If somebody talks about a system being broken for a couple of days while they are refactoring, you can be pretty sure they are not refactoring.

**포매팅과 이름 변경은 다르다.** 공백과 줄바꿈 정리는 동작도 구조도 바꾸지 않는다. 반면 이름 변경은 [Rename Variable](https://refactoring.com/catalog/renameVariable.html)로 카탈로그에 올라 있는 정식 리팩토링이다.

## 예시

동작을 보존한 쪽이다. [Extract Function](https://refactoring.com/catalog/extractFunction.html)을 적용했다.

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

다음은 겉보기에 같은 종류의 정리인데 동작이 바뀌는 쪽이다.

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

예외 타입도 관측 가능한 동작이다.

```kotlin
val port = config["port"]!!.toInt()          // 키가 없으면 NullPointerException
val port = config.getValue("port").toInt()   // 키가 없으면 NoSuchElementException
```

`!!`를 없앤 정리로 보이지만, 위쪽 예외를 잡던 호출자가 있으면 깨진다.

## 혼동하기 쉬운 것

| 흔한 말 | 실제 |
|---|---|
| "리팩토링하면서 이 버그도 고쳤다" | 버그 수정이 섞인 것이다. 커밋을 나눈다 |
| "리팩토링이라 테스트는 안 고쳤다" | 맞다. 테스트를 고쳐야 했다면 동작이 바뀐 것이다 |
| "이번 스프린트는 리팩토링만" | 며칠씩 깨져 있다면 재작성이다 |
| "성능 개선 리팩토링" | 최적화다. 확인 수단이 테스트가 아니라 측정값이다 |

두 번째가 실무에서 가장 유용한 판별법이다. **기존 테스트를 고쳐야 통과한다면 그건 리팩토링이 아니다.**

## 언제 어떤 것을 쓰나

동작만 보존하면 좋은 리팩토링인 것은 아니다. 대부분의 구조 개선은 무언가를 내주고 무언가를 얻는다.

| 하려는 것 | 얻는 것 | 잃는 것 | 판단 기준 |
|---|---|---|---|
| 테스트 없는 코드 정리 | 구조 개선 | 동작 보존을 확인할 수단 | 특성화 테스트를 먼저 붙인다. 못 붙이면 손대지 않는다 |
| 중복 세 곳을 하나로 (DRY) | 고칠 지점이 하나로 | 세 곳이 서로 다른 방향으로 변할 때의 결합 | 우연히 같은 코드인지, 같은 이유로 함께 바뀌는 코드인지 본다 |
| 인터페이스 추출 | 교체 가능성 | 구현이 하나뿐이면 간접 계층만 늘어난다 | 두 번째 구현이 실제로 있을 때 |
| 캐시·배치 도입 | 응답시간 | 가독성, 무효화 검증 비용 | 측정값이 있을 때만. 리팩토링과 다른 커밋으로 |
| 기능 변경과 한 커밋에 | 왕복 한 번 | 리뷰에서 진짜 변경이 묻히고, 롤백하면 개선도 사라진다 | 나눈다 |

판단 기준은 결국 하나로 모인다. **지금 하려는 변경을 더 싸게 만드는가.** 나중에 필요할 것 같아서 미리 만드는 추상은 이 질문에 답하지 못한다.

전면적으로 잡는 대신 손대는 김에 조금씩 고치는 방식을 파울러는 [Opportunistic Refactoring](https://martinfowler.com/bliki/OpportunisticRefactoring.html)이라 부른다. 캠프장 규칙 — 발견했을 때보다 나은 상태로 두고 나온다 — 이 그 방식이다. 대신 파고들어 원래 작업을 놓치지 않는 선을 지켜야 한다.

## 참고

- [Refactoring — 정의와 카탈로그](https://refactoring.com/)
- [Refactoring Malapropism](https://martinfowler.com/bliki/RefactoringMalapropism.html)
- [Opportunistic Refactoring](https://martinfowler.com/bliki/OpportunisticRefactoring.html)
