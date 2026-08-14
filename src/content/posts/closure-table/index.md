---
title: 계층 구조를 저장하는 Closure Table
description: 부모-자식 컬럼만으로는 재귀 조회가 필요한 계층 구조를, 조상-자손 관계를 미리 계산해 저장하는 Closure Table로 다루는 방법을 정리한다
pubDate: 2026-08-14
category: "데이터베이스"
tags: ["기본개념", "Database", "계층구조"]
---

## 전제

[Adjacency List](/posts/adjacency-list/)로 저장한 계층 구조가 왜 재귀 조회를 필요로 하는지는 그 글에서 다룬다. 이 글은 그 문제를 우회하는 방식 중 하나를 다룬다.

## 왜 필요한가

[Adjacency List](/posts/adjacency-list/)는 조상·자손 조회에 재귀가 필요하다는 게 문제였다. Closure Table은 이 재귀 조회를 단순 `SELECT` 하나로 바꾸기 위해, 모든 조상-자손 관계를 미리 계산해 별도 테이블에 저장해두는 패턴이다.

## 용어 정리

- **전이적 폐쇄(Transitive Closure)**: A→B, B→C가 성립하면 A→C도 성립한다고 볼 때, 이렇게 유도되는 모든 관계쌍의 집합.
- **Closure Table**: 전이적 폐쇄를 실체화(materialize)해 저장하는 테이블. 이름도 여기서 왔다.

## 핵심 정리

Closure Table은 컬럼 세 개로 조상-자손 관계를 표현한다.

| 컬럼 | 의미 |
|---|---|
| `ancestor_id` | 조상 노드 ID |
| `descendant_id` | 자손 노드 ID |
| `depth` | 두 노드 사이 거리. 0이면 자기 자신 |

규칙은 두 가지다.

- 모든 노드는 자기 자신에 대해 `depth = 0`인 행을 갖는다.
- 직계 부모-자식 관계뿐 아니라 조상-자손 관계 전부를 한 행씩 저장한다. 조상이 N개인 노드는 자기 자신을 포함해 N+1개 행을 갖는다.

## 예시

다음 트리를 저장한다고 하자.

```
1 (루트)
└─ 2
   └─ 3
      └─ 4
```

Closure Table에는 이렇게 쌓인다.

| ancestor_id | descendant_id | depth |
|---|---|---|
| 1 | 1 | 0 |
| 1 | 2 | 1 |
| 1 | 3 | 2 |
| 1 | 4 | 3 |
| 2 | 2 | 0 |
| 2 | 3 | 1 |
| 2 | 4 | 2 |
| 3 | 3 | 0 |
| 3 | 4 | 1 |
| 4 | 4 | 0 |

조회는 재귀 없이 조건만 바꾸면 된다.

```sql
-- 노드 3의 모든 자손
SELECT descendant_id FROM closure
WHERE ancestor_id = 3 AND depth > 0;

-- 노드 3의 모든 조상
SELECT ancestor_id FROM closure
WHERE descendant_id = 3 AND depth > 0;

-- 노드 3의 직계 자식만
SELECT descendant_id FROM closure
WHERE ancestor_id = 3 AND depth = 1;
```

노드를 삽입할 때는 새로 추가할 노드의 자기 자신 행과, 부모가 가진 모든 조상 관계에 depth를 1씩 더해 함께 넣는다. 노드 5를 노드 3의 자식으로 추가하는 경우다.

```sql
INSERT INTO closure (ancestor_id, descendant_id, depth)
SELECT ancestor_id, 5, depth + 1
FROM closure
WHERE descendant_id = 3
UNION ALL
SELECT 5, 5, 0;
```

## 혼동하기 쉬운 것

**자기 자신 행(depth = 0)을 빼먹기 쉽다.** 조상-자손 관계만 생각하면 자기 참조 행이 필요 없어 보이지만, 이 행이 없으면 "노드 3을 포함한 자신과 자손 전체"처럼 자기 자신을 결과에 포함해야 하는 조회에서 `depth >= 0` 조건이 자기 자신을 걸러내지 못한다. 노드를 삽입할 때 자기 자신 행(`SELECT 5, 5, 0`)을 함께 넣는 이유가 여기 있다.

**`ancestor_id`와 `descendant_id` 조건을 반대로 걸기 쉽다.** 자손을 구할 때는 `ancestor_id`를 고정하고 `descendant_id`를 조회하는데, 조상을 구할 때는 반대로 `descendant_id`를 고정하고 `ancestor_id`를 조회해야 한다. 컬럼 이름이 비슷해서 조회 방향을 반대로 쓰는 실수가 나오기 쉽다.

## 언제 어떤 것을 쓰나

조상·자손 조회가 잦고 삽입·삭제는 상대적으로 적은 경우에 맞는다. [Nested Set](/posts/nested-set/)과 비교하면 삽입 비용이 삽입 노드의 조상 수에만 비례해 싸지만, 저장 공간은 트리가 한쪽으로 치우칠수록(편향 트리) 늘어나 최악의 경우 O(n²)에 가까워진다. [Path Enumeration](/posts/path-enumeration/)과 비교하면 정수 컬럼끼리 조인하므로 조상·자손 조회 모두 인덱스를 온전히 활용한다는 장점이 있다.

노드 수가 아주 많고(수백만 단위) 트리도 깊다면 저장 공간이 부담될 수 있는데, 이때는 재귀 CTE를 지원하는 DBMS라면 [Adjacency List](/posts/adjacency-list/) + `WITH RECURSIVE`도 대안이다. 서브트리를 통째로 다른 부모 밑으로 옮기는 이동이 잦다면 Nested Set은 피하고 Closure Table이나 Adjacency List를 쓴다.

## 더 깊이

- [계층 구조를 부모 참조로 저장하는 Adjacency List](/posts/adjacency-list/)
- [계층 구조를 문자열로 저장하는 Path Enumeration](/posts/path-enumeration/)
- [계층 구조를 숫자 구간으로 저장하는 Nested Set](/posts/nested-set/)

## 참고

- Bill Karwin, *SQL Antipatterns* — Closure Table을 처음 정리한 책
