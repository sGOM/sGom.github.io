---
title: 계층 구조를 부모 참조로 저장하는 Adjacency List
description: 각 행이 자신의 parent_id만 저장하는 가장 기본적인 계층 구조 저장 방식과, 재귀 조회가 필요한 이유·비용을 정리한다
pubDate: 2026-08-14
category: "데이터베이스"
tags: ["기본개념", "Database", "계층구조"]
---

## 전제

[Closure Table](/posts/closure-table/), [Path Enumeration](/posts/path-enumeration/), [Nested Set](/posts/nested-set/)은 모두 이 글에서 다루는 Adjacency List의 재귀 조회 문제를 우회하려고 나온 변형이다. Adjacency List가 왜, 얼마나 비싼지를 먼저 짚어야 나머지 세 방식이 "무엇의 대안인지"가 분명해진다.

## 왜 필요한가

계층 구조를 저장하는 가장 단순한 방법은 각 행에 자신의 부모 id(`parent_id`) 하나만 두는 것이다. 스키마가 가장 단순하고 삽입·삭제·이동도 자기 자신 행 하나만 고치면 끝난다. 문제는 조회다. 직계 자식은 `WHERE parent_id = ?` 한 줄로 끝나지만, "이 노드 아래 모든 자손"이나 "이 노드의 모든 조상"을 구하려면 부모를 따라 반복해서 올라가거나 내려가야 한다. 이게 재귀 조회가 필요한 이유다.

## 용어 정리

**Adjacency List(인접 리스트)**는 원래 그래프 이론에서 각 노드가 자신과 연결된 노드 목록을 갖는 표현 방식을 가리키는 이름이다. → [Adjacency list — Wikipedia](https://en.wikipedia.org/wiki/Adjacency_list) 계층 구조에서는 이 아이디어를 뒤집어, 각 행이 자식 목록 대신 부모 하나만 참조하는 형태로 쓴다.

**재귀 CTE(Recursive Common Table Expression)**는 `WITH RECURSIVE`로 시작하는, 자기 자신을 참조하는 쿼리다. SQL:1999 표준에 정의됐다. → [PostgreSQL — Recursive Queries](https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-RECURSIVE)

## 핵심 정리

| | 내용 |
|---|---|
| 저장 컬럼 | `parent_id` 하나 |
| 직계 자식 조회 | `WHERE parent_id = ?` — 단순, 인덱스 탐 |
| 자손 전체 조회 | 재귀 필요 (`WITH RECURSIVE` 또는 애플리케이션 순회) |
| 삽입·이동 비용 | 자기 자신 행의 `parent_id`만 수정 — 네 방식 중 가장 저렴 |
| 저장 공간 | 컬럼 하나뿐이라 네 방식 중 가장 작음 |

## 항목별 설명

조직도를 예로 든다.

```
대표이사
├─ 개발팀장
│  └─ 백엔드 개발자
└─ 영업팀장
```

| id | name | parent_id |
|---|---|---|
| 1 | 대표이사 | `NULL` |
| 2 | 개발팀장 | 1 |
| 3 | 백엔드 개발자 | 2 |
| 4 | 영업팀장 | 1 |

대표이사의 직속 부하만 구하는 건 쉽다.

```sql
SELECT * FROM org WHERE parent_id = 1;
-- 결과: 개발팀장, 영업팀장
```

하지만 "대표이사 아래 전체 조직도"를 구하려면 개발팀장 아래의 백엔드 개발자까지 찾아야 한다. `parent_id`만으로는 몇 단계를 내려가야 할지 모르는 채로 반복 조회할 수밖에 없다.

## 예시

재귀 CTE로 전체 자손을 한 번에 구한다.

```sql
WITH RECURSIVE subordinates AS (
  -- 시작점: 대표이사
  SELECT id, name, parent_id
  FROM org
  WHERE id = 1

  UNION ALL

  -- 이미 찾은 노드의 자식을 계속 이어붙인다
  SELECT o.id, o.name, o.parent_id
  FROM org o
  JOIN subordinates s ON o.parent_id = s.id
)
SELECT * FROM subordinates;
-- 결과: 대표이사, 개발팀장, 영업팀장, 백엔드 개발자
```

조상 조회는 조인 방향만 뒤집으면 된다.

```sql
WITH RECURSIVE managers AS (
  -- 시작점: 백엔드 개발자
  SELECT id, name, parent_id
  FROM org
  WHERE id = 3

  UNION ALL

  SELECT o.id, o.name, o.parent_id
  FROM org o
  JOIN managers m ON o.id = m.parent_id
)
SELECT * FROM managers;
-- 결과: 백엔드 개발자, 개발팀장, 대표이사
```

## 혼동하기 쉬운 것

**순환 참조가 있으면 무한 루프에 빠진다.** `parent_id`가 실수로 자기 자신이나 자손을 가리키게 되면(A→B→A), 재귀 CTE는 종료 조건이 없는 한 계속 돈다. `UNION`(중복 제거)을 쓰거나 방문한 id를 배열에 쌓아 순환을 감지하는 안전장치가 필요하다.

**`UNION ALL`과 `UNION`은 결과가 다르다.** 트리라면(사이클이 없다면) 같은 노드를 두 번 방문할 일이 없어 `UNION ALL`로 충분하고 더 빠르다. 그래프처럼 사이클이 있을 수 있는 구조라면 `UNION`으로 중복 방문을 걸러야 무한 루프를 막는다.

## 구현체별 차이

재귀 CTE가 SQL 표준이라도 모든 DBMS·버전에서 되는 건 아니다.

| DBMS | 지원 시점 | 비고 |
|---|---|---|
| PostgreSQL | 8.4 (2009) | `WITH RECURSIVE` |
| SQLite | 3.8.3 (2014) | `WITH RECURSIVE` |
| MySQL | 8.0 (2018) | 그 이전 버전은 미지원, 프로시저나 애플리케이션 순회로 우회해야 했다 |
| Oracle | 11g R2 (2009) 부터 표준 문법 지원 | 그 전부터 `CONNECT BY PRIOR`라는 자체 문법을 오래 써왔다 |

## 언제 어떤 것을 쓰나

구조가 자주 바뀌고(삽입·삭제·이동이 잦음) 트리가 얕거나 조상·자손 조회가 상대적으로 드물면 Adjacency List가 가장 단순하고 저렴하다. 재귀 CTE를 지원하는 DBMS라면 별도 테이블이나 컬럼 없이도 조회를 해결할 수 있다.

반대로 조회가 압도적으로 많거나 트리가 깊어 재귀 비용이 부담되면 [Closure Table](/posts/closure-table/), [Path Enumeration](/posts/path-enumeration/), [Nested Set](/posts/nested-set/) 중 조회·삽입 패턴에 맞는 방식으로 옮기는 걸 고려한다. 실무에서는 Adjacency List로 시작했다가, 재귀 조회가 실제로 병목이 되는 시점에 다른 방식을 얹는 경우가 많다.

## 더 깊이

- [계층 구조를 저장하는 Closure Table](/posts/closure-table/)
- [계층 구조를 문자열로 저장하는 Path Enumeration](/posts/path-enumeration/)
- [계층 구조를 숫자 구간으로 저장하는 Nested Set](/posts/nested-set/)

## 참고

- Bill Karwin, *SQL Antipatterns* — "Naive Trees" 장
- [PostgreSQL — Recursive Queries](https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-RECURSIVE)
- [Adjacency list — Wikipedia](https://en.wikipedia.org/wiki/Adjacency_list)
