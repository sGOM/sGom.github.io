---
title: 계층 구조를 숫자 구간으로 저장하는 Nested Set
description: 트리를 깊이 우선으로 순회해 매긴 left/right 번호로 계층을 표현하는 Nested Set의 동작 방식과 실무 활용 예시를 정리한다
pubDate: 2026-08-14
category: "데이터베이스"
tags: ["기본개념", "Database", "계층구조"]
---

## 전제

[Adjacency List](/posts/adjacency-list/)의 재귀 조회 문제를 우회하는 방식 중 하나다. [계층 구조를 저장하는 Closure Table](/posts/closure-table/)에서 비교 대상으로만 짧게 언급했었다. 같은 계열의 [Path Enumeration](/posts/path-enumeration/)과 함께 보면 차이가 뚜렷하다.

## 왜 필요한가

인접 리스트(parent_id만 저장)는 조상·자손 조회에 재귀가 필요하다. Nested Set은 각 노드에 숫자 두 개(`left`, `right`)를 매겨, 자손이 항상 조상의 `[left, right]` 구간 **안**에 완전히 들어오게 만든다. 조회가 범위 비교 하나로 끝난다는 게 가장 큰 강점이다.

## 용어 정리

이 번호를 매기는 절차를 **MPTT(Modified Preorder Tree Traversal)**라 부른다. 전위 순회(preorder traversal) 중 노드에 번호를 한 번이 아니라 두 번(들어갈 때, 나갈 때) 매긴다고 해서 "Modified"가 붙었다. → [Nested set model — Wikipedia](https://en.wikipedia.org/wiki/Nested_set_model)

## 핵심 정리

| | 내용 |
|---|---|
| 저장 컬럼 | `left`, `right` (정수) |
| 자손 조회 | `left`가 자신의 `[left, right]` 구간 안 |
| 조상 조회 | `left`/`right`가 자신을 감싸는 행 |
| 삽입·이동 비용 | 삽입 지점 뒤 모든 노드의 `left`/`right` 재계산 |
| 인덱스 활용 | 범위 비교(`BETWEEN`)라 인덱스를 잘 탄다 |

## 항목별 설명

조직도를 예로 든다.

```
대표이사
├─ 개발팀장
│  └─ 백엔드 개발자
└─ 영업팀장
```

`left`/`right`는 트리를 깊이 우선으로 순회하며 매긴 번호다. 노드에 처음 들어갈 때 카운터를 하나 올려 `left`에 적고, 그 노드의 자식을 모두 처리한 뒤 빠져나올 때 카운터를 다시 올려 `right`에 적는다. 여는 괄호와 닫는 괄호를 순서대로 매긴다고 생각하면 된다.

1. 대표이사에 들어간다 → `left = 1`
2. 개발팀장에 들어간다 → `left = 2`
3. 백엔드 개발자에 들어간다 → `left = 3`
4. 백엔드 개발자에서 나온다 → `right = 4`
5. 개발팀장에서 나온다 → `right = 5`
6. 영업팀장에 들어간다 → `left = 6`
7. 영업팀장에서 나온다 → `right = 7`
8. 대표이사에서 나온다 → `right = 8`

| id | name | left | right |
|---|---|---|---|
| 1 | 대표이사 | 1 | 8 |
| 2 | 개발팀장 | 2 | 5 |
| 3 | 백엔드 개발자 | 3 | 4 |
| 4 | 영업팀장 | 6 | 7 |

개발팀장(2, 5)의 구간 안에 백엔드 개발자(3, 4)가 완전히 들어가 있다. 표만 보고도 누가 누구 아래인지 알 수 있다.

## 예시

```sql
-- 개발팀장(2)의 모든 하위 조직
SELECT * FROM org
WHERE left BETWEEN 2 AND 5 AND id != 2;
-- 결과: 백엔드 개발자 (left=3, right=4)

-- 백엔드 개발자(3)의 결재 라인(모든 상위 조직)
SELECT * FROM org
WHERE left <= 3 AND right >= 4;
-- 결과: 대표이사(1,8), 개발팀장(2,5)
```

삽입 비용이 왜 큰지는 실제로 한 명을 끼워 넣어보면 드러난다. 개발팀장 밑에 "프론트엔드 개발자"를 추가한다.

```sql
-- 개발팀장의 (옛) right 값인 5를 기준으로, 그 이후 번호를 전부 2칸씩 민다
UPDATE org SET right = right + 2 WHERE right >= 5;
UPDATE org SET left  = left  + 2 WHERE left  >= 5;

-- 비어난 자리(5, 6)에 새 노드를 끼운다
INSERT INTO org (name, left, right) VALUES ('프론트엔드 개발자', 5, 6);
```

결과는 이렇게 바뀐다.

| id | name | left | right |
|---|---|---|---|
| 1 | 대표이사 | 1 | 10 |
| 2 | 개발팀장 | 2 | 7 |
| 3 | 백엔드 개발자 | 3 | 4 |
| 5 | 프론트엔드 개발자 | 5 | 6 |
| 4 | 영업팀장 | 8 | 9 |

새 노드 하나 넣었을 뿐인데 대표이사, 개발팀장, 영업팀장의 번호가 전부 바뀌었다. 트리가 크고 삽입 지점이 앞쪽일수록 갱신되는 행이 늘어난다.

## 혼동하기 쉬운 것

**두 `UPDATE`의 조건을 바꿔 쓰면 트리가 깨진다.** `right` 컬럼은 부모의 옛 `right` 이상인 모든 행을 밀고, `left` 컬럼도 같은 기준값 이상인 행을 민다. 두 조건은 같은 값을 쓰지만 서로 다른 컬럼을 대상으로 한다는 점이 헷갈리기 쉽다.

**`left`/`right`는 실제로 의미 있는 값이 아니라 순서일 뿐이다.** 두 값 사이의 차이나 크기 자체에는 의미가 없고, "어떤 구간이 어떤 구간을 포함하는가"만 의미가 있다.

## 언제 어떤 것을 쓰나

조회가 압도적으로 많고 구조 변경은 드문 트리에 적합하다. 조직도의 결재 라인 확인처럼 "이 사람 위에 누가 있는가"를 수시로 조회하지만 조직 개편은 가끔 있는 경우, 쇼핑몰 카테고리 트리처럼 상품 노출·필터링으로 조회는 끊임없이 일어나지만 카테고리 개편은 드문 경우가 여기 해당한다.

반대로 노드가 자주 추가·삭제·이동된다면 맞지 않는다. 실시간 채팅 스레드처럼 삽입이 잦은 구조라면 [Path Enumeration](/posts/path-enumeration/)이나 [Closure Table](/posts/closure-table/) 쪽이 갱신 비용이 작다.

## 더 깊이

- [계층 구조를 부모 참조로 저장하는 Adjacency List](/posts/adjacency-list/)
- [계층 구조를 저장하는 Closure Table](/posts/closure-table/)
- [계층 구조를 문자열로 저장하는 Path Enumeration](/posts/path-enumeration/)

## 참고

- Bill Karwin, *SQL Antipatterns* — "Naive Trees" 장
- [Nested set model — Wikipedia](https://en.wikipedia.org/wiki/Nested_set_model)
