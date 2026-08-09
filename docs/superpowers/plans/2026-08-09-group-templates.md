# 그룹 3종 템플릿과 선택 섹션 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 그룹(기본개념/파고들기/오답노트)마다 템플릿을 하나씩 두고, 각 템플릿 안의 섹션을 필수와 선택으로 나눠 글의 성격에 맞게 고를 수 있게 한다.

**Architecture:** 코드 변경이 없다. `templates/` 아래 마크다운 파일 3개와 문서 2개(`CLAUDE.md`, `README.md`)만 다룬다. 각 섹션 heading 아래에 안내문 한 줄을 두고 `필수 —` 또는 `선택 —`으로 시작한다. 글을 쓸 때 그 줄을 내용으로 갈아치우므로 표시가 파일에 남지 않는다.

**Tech Stack:** Markdown. 검증은 `npm test`(회귀 확인)와 `grep` 기반 구조 확인.

설계 문서: `docs/superpowers/specs/2026-08-09-group-templates-design.md`

## Global Constraints

- 안내문 줄은 반드시 `필수 — ` 또는 `선택 — `으로 시작한다. `—`는 em dash(U+2014)이며 하이픈이나 en dash로 대체하지 않는다.
- 섹션마다 안내문 줄은 정확히 하나다. 예외는 두 곳뿐이다. `deep-dive.md`의 `## 직접 확인`과 `troubleshooting.md`의 `## 가설과 검증`은 안내문 아래에 기존 강조 문구를 덧붙인다.
- 세 템플릿 모두 frontmatter 맨 아래 `tags`에 해당 그룹 태그 하나를 미리 넣는다. `basics.md`는 `["기본개념"]`, `deep-dive.md`는 `["파고들기"]`, `troubleshooting.md`는 `["오답노트"]`.
- frontmatter 필드 순서는 기존 템플릿을 따른다. `title`, `description`, `pubDate`, `category`, `tags`.
- 세 템플릿 모두 frontmatter 아래에 같은 규칙 주석 블록을 둔다. 문구를 파일마다 바꾸지 않는다.
- `templates/` 아래에는 최종적으로 `basics.md`, `deep-dive.md`, `troubleshooting.md` 세 파일만 남는다.
- `src/` 아래 어떤 파일도 건드리지 않는다. 이 작업에 코드 변경은 없다.
- `astro.config.mjs`에 `base`를 넣지 않는다.
- 말투는 평서체(`~다`)를 쓴다. 다만 `CLAUDE.md` 4절의 말투 규칙은 글 본문에만 적용되므로, 템플릿의 안내문은 지시문 형태(`~한다`, `~할 때`)로 써도 된다.

세 템플릿에 공통으로 들어가는 규칙 주석 블록은 다음과 같다. 세 태스크에서 같은 내용을 쓴다.

```markdown
<!--
선택 섹션은 해당 없으면 지운다. 순서는 글에 맞게 바꿔도 된다.
안내문 줄(필수 — / 선택 —)은 내용으로 갈아치운다.
-->
```

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `templates/basics.md` | 기본개념 템플릿. 필수 2 + 선택 9 | 생성 |
| `templates/deep-dive.md` | 파고들기 템플릿. 필수 2 + 선택 10 | 생성 |
| `templates/troubleshooting.md` | 오답노트 템플릿. 필수 6 + 선택 5 | 개편 |
| `templates/concept.md` | `basics.md`와 `deep-dive.md`로 갈라짐 | 삭제 |
| `CLAUDE.md` | 1절 템플릿 고르기를 세 갈래로 | 수정 |
| `README.md` | 템플릿 개수와 목록 | 수정 |

`concept.md` 삭제는 Task 4에 둔다. `CLAUDE.md`와 `README.md`가 그 파일을 링크하고 있어, 먼저 지우면 문서가 깨진 링크를 가리키는 중간 상태가 생긴다.

## 구조 검증 방법

세 템플릿 태스크가 공통으로 쓰는 확인 방법이다. heading 수와 안내문 줄 수가 같아야 한다.

```bash
f=templates/basics.md
echo "headings: $(grep -c '^## ' "$f")"
echo "guidance: $(grep -cE '^(필수|선택) — ' "$f")"
```

두 값이 다르면 안내문이 빠졌거나 중복된 섹션이 있다. 어느 섹션인지 찾으려면 다음을 쓴다.

```bash
grep -A2 '^## ' templates/basics.md | grep -E '^(## |필수 — |선택 — )'
```

heading과 안내문이 번갈아 나와야 한다. heading 두 개가 연달아 나오면 그 사이 섹션에 안내문이 없다.

---

## Task 1: templates/basics.md — 기본개념

**Files:**
- Create: `templates/basics.md`

**Interfaces:**
- Consumes: 없음
- Produces: `templates/basics.md`. Task 4의 `CLAUDE.md`·`README.md`가 이 경로를 링크한다.

섹션 순서는 `왜 필요한가` → `용어 정리` → `핵심 정리` → `항목별 설명` → `예시` → `혼동하기 쉬운 것` → `구현체별 차이` → `직접 확인` → `언제 어떤 것을 쓰나` → `더 깊이` → `참고`다. 필수 두 개(`핵심 정리`, `예시`)가 선택 섹션 사이에 놓인다.

기본개념은 표와 짧은 설명·예시로 정리하는 글이므로 재현과 실행 결과를 요구하지 않는다. `직접 확인`이 선택인 이유다.

- [ ] **Step 1: 파일을 만든다**

`templates/basics.md`를 아래 내용 그대로 만든다.

```markdown
---
title:
description:
pubDate:
category:
tags: ["기본개념"]
---

<!--
선택 섹션은 해당 없으면 지운다. 순서는 글에 맞게 바꿔도 된다.
안내문 줄(필수 — / 선택 —)은 내용으로 갈아치운다.
-->

## 왜 필요한가

선택 — 이 개념을 모르면 어떤 문제를 겪는지. 정의부터 시작하지 않는다.

## 용어 정리

선택 — 이름이 비슷해 헷갈리는 용어를 먼저 갈라놓을 때.

## 핵심 정리

필수 — 표로 한눈에 보이게. 항목, 동작, 차이를 열로 세운다.

## 항목별 설명

선택 — 표 한 줄로 부족해 항목마다 2~3문장이 필요할 때.

## 예시

필수 — 짧은 코드나 상태 변화. 표만 있는 글은 공식 문서 요약과 구별되지 않는다.

## 혼동하기 쉬운 것

선택 — 실무에서 자주 뒤바뀌는 짝이 있을 때.

## 구현체별 차이

선택 — 표준과 실제 제품이 다를 때. DBMS, 브라우저, 런타임.

## 직접 확인

선택 — 짧게 재현해 보일 때. 분량이 커지면 파고들기로 분리한다.

## 언제 어떤 것을 쓰나

선택 — 선택 기준이 있을 때.

## 더 깊이

선택 — 대응 파고들기 글이 있을 때 링크. `/posts/<슬러그>/` 형식.

## 참고

선택 — 출처 링크.
```

- [ ] **Step 2: 구조를 확인한다**

Run:
```bash
f=templates/basics.md
echo "headings: $(grep -c '^## ' "$f")"
echo "guidance: $(grep -cE '^(필수|선택) — ' "$f")"
echo "필수: $(grep -c '^필수 — ' "$f")"
echo "선택: $(grep -c '^선택 — ' "$f")"
```

Expected:
```
headings: 11
guidance: 11
필수: 2
선택: 9
```

숫자가 다르면 섹션이 빠졌거나 안내문 접두사를 잘못 붙인 것이다.

- [ ] **Step 3: 그룹 태그를 확인한다**

Run: `grep '^tags:' templates/basics.md`
Expected: `tags: ["기본개념"]`

- [ ] **Step 4: 커밋**

```bash
git add templates/basics.md
git commit -m "feat: 기본개념 템플릿 추가"
```

---

## Task 2: templates/deep-dive.md — 파고들기

**Files:**
- Create: `templates/deep-dive.md`

**Interfaces:**
- Consumes: 없음
- Produces: `templates/deep-dive.md`. Task 4의 `CLAUDE.md`·`README.md`가 이 경로를 링크한다.

섹션 순서는 `전제` → `왜 필요한가` → `겉으로 보이는 것` → `구조` → `동작 원리` → `코드로 따라가기` → `직접 확인` → `경계 조건` → `대안과 트레이드오프` → `언제 쓰고 언제 안 쓰나` → `성능` → `참고`다. 필수 두 개(`동작 원리`, `직접 확인`)가 중간에 놓인다.

`직접 확인`의 강조 문구는 기존 `templates/concept.md`에서 그대로 옮겨온 것이다. 이 템플릿의 규율이므로 문구를 바꾸지 않는다.

- [ ] **Step 1: 파일을 만든다**

`templates/deep-dive.md`를 아래 내용 그대로 만든다.

```markdown
---
title:
description:
pubDate:
category:
tags: ["파고들기"]
---

<!--
선택 섹션은 해당 없으면 지운다. 순서는 글에 맞게 바꿔도 된다.
안내문 줄(필수 — / 선택 —)은 내용으로 갈아치운다.
-->

## 전제

선택 — 대응 기본개념 글이 있을 때 링크. 이 글이 어디서 출발하는지. `/posts/<슬러그>/` 형식.

## 왜 필요한가

선택 — 이 깊이가 왜 필요한지.

## 겉으로 보이는 것

선택 — 표면 동작과 실제가 다를 때. 먼저 표면을 적고 뒤집는다.

## 구조

선택 — 클래스·컴포넌트 관계. 그림이나 순서도.

## 동작 원리

필수 — 내부적으로 어떻게 돌아가는지.

## 코드로 따라가기

선택 — 실제 구현 코드를 인용해 짚을 때.

## 직접 확인

필수 — 코드로 재현하고 실행 결과를 넣는다.

**이 섹션이 비면 발행하지 않는다.**
공식 문서를 요약한 글은 이미 많지만 직접 재현해 확인한 글은 적다.

## 경계 조건

선택 — 언제 깨지는가.

## 대안과 트레이드오프

선택 — 다른 선택지가 있을 때.

## 언제 쓰고 언제 안 쓰나

선택 — 실무 판단 기준.

## 성능

선택 — 측정값이 있을 때만. 없으면 쓰지 않는다.

## 참고

선택 — 출처 링크.
```

- [ ] **Step 2: 구조를 확인한다**

Run:
```bash
f=templates/deep-dive.md
echo "headings: $(grep -c '^## ' "$f")"
echo "guidance: $(grep -cE '^(필수|선택) — ' "$f")"
echo "필수: $(grep -c '^필수 — ' "$f")"
echo "선택: $(grep -c '^선택 — ' "$f")"
```

Expected:
```
headings: 12
guidance: 12
필수: 2
선택: 10
```

- [ ] **Step 3: 규율 문구와 그룹 태그를 확인한다**

Run:
```bash
grep '^tags:' templates/deep-dive.md
grep -n '이 섹션이 비면 발행하지 않는다' templates/deep-dive.md
```

Expected: `tags: ["파고들기"]`가 나오고, 강조 문구가 `## 직접 확인` 아래에 한 번 나온다.

- [ ] **Step 4: 커밋**

```bash
git add templates/deep-dive.md
git commit -m "feat: 파고들기 템플릿 추가"
```

---

## Task 3: templates/troubleshooting.md 개편

**Files:**
- Modify: `templates/troubleshooting.md`

**Interfaces:**
- Consumes: 없음
- Produces: 개편된 `templates/troubleshooting.md`. 경로는 그대로이므로 Task 4가 링크를 바꿀 필요는 없다.

기존 여섯 섹션(`상황`, `증상`, `가설과 검증`, `원인`, `해결`, `배운 것`)을 **전부 필수로 유지**한다. 이 태스크가 하는 일은 두 가지다. 안내문을 `필수 — ` 접두사 형식으로 통일하고, 선택 섹션 다섯 개를 끼워 넣는다.

`가설과 검증`의 강조 문구는 오답노트의 존재 이유이므로 문구를 바꾸지 않는다. 기존 파일에 있던 `> 가설 1: ○○일 것이다` 예시 인용도 유지한다.

섹션 순서는 `상황` → `환경` → `증상` → `재현 절차` → `가설과 검증` → `막다른 길` → `원인` → `해결` → `남은 문제` → `배운 것` → `참고`다.

- [ ] **Step 1: 파일을 통째로 바꾼다**

`templates/troubleshooting.md`를 아래 내용으로 바꾼다. `tags: ["오답노트"]`는 이미 파일에 있으므로 값이 그대로 유지된다.

```markdown
---
title:
description:
pubDate:
category:
tags: ["오답노트"]
---

<!--
선택 섹션은 해당 없으면 지운다. 순서는 글에 맞게 바꿔도 된다.
안내문 줄(필수 — / 선택 —)은 내용으로 갈아치운다.
-->

## 상황

필수 — 어떤 시스템에서, 무엇을 하다가 마주쳤는지. 3~4문장.

## 환경

선택 — 버전이 원인일 때. 라이브러리, 런타임, DB 버전.

## 증상

필수 — 관측된 사실만 적는다. 로그, 지표, 에러 메시지. 추측은 여기 쓰지 않는다.

## 재현 절차

선택 — 최소 재현 코드나 단계가 있을 때.

## 가설과 검증

필수 — 무엇을 근거로 세웠고, 어떻게 확인했고, 결과가 무엇이었는지.

> 가설 1: ○○일 것이다

**틀린 가설도 남긴다. 이 섹션이 이 템플릿의 존재 이유다.**
정답만 적힌 글은 검색 결과와 구별되지 않는다.

## 막다른 길

선택 — 조사했지만 원인이 아니었던 경로. 가설로 정리하기 애매한 것.

## 원인

필수 — 왜 그런 일이 일어났는지. 코드나 설정 수준의 근거와 함께.

## 해결

필수 — 바꾼 것과, 바꾼 뒤 지표가 어떻게 변했는지.

## 남은 문제

선택 — 해결했지만 찜찜하게 남은 것.

## 배운 것

필수 — 다음에 비슷한 상황에서 무엇을 먼저 볼 것인가. 2~3줄.

## 참고

선택 — 출처 링크.
```

- [ ] **Step 2: 구조를 확인한다**

Run:
```bash
f=templates/troubleshooting.md
echo "headings: $(grep -c '^## ' "$f")"
echo "guidance: $(grep -cE '^(필수|선택) — ' "$f")"
echo "필수: $(grep -c '^필수 — ' "$f")"
echo "선택: $(grep -c '^선택 — ' "$f")"
```

Expected:
```
headings: 11
guidance: 11
필수: 6
선택: 5
```

- [ ] **Step 3: 규율 문구와 그룹 태그를 확인한다**

Run:
```bash
grep '^tags:' templates/troubleshooting.md
grep -n '틀린 가설도 남긴다' templates/troubleshooting.md
```

Expected: `tags: ["오답노트"]`가 나오고, 강조 문구가 `## 가설과 검증` 아래에 한 번 나온다.

- [ ] **Step 4: 커밋**

```bash
git add templates/troubleshooting.md
git commit -m "feat: 오답노트 템플릿에 선택 섹션 추가"
```

---

## Task 4: concept.md 삭제와 문서 갱신

**Files:**
- Delete: `templates/concept.md`
- Modify: `CLAUDE.md` (1절 템플릿 고르기)
- Modify: `README.md` (45행 디렉터리 주석, 69–72행 템플릿 목록)

**Interfaces:**
- Consumes: Task 1의 `templates/basics.md`, Task 2의 `templates/deep-dive.md`
- Produces: 없음. 마지막 태스크다

`concept.md` 삭제와 문서 갱신을 한 태스크로 묶는 이유는 `CLAUDE.md`와 `README.md`가 그 파일을 링크하고 있기 때문이다. 먼저 지우면 문서가 없는 파일을 가리키는 중간 상태가 생긴다.

- [ ] **Step 1: `concept.md`가 아직 참조되는 곳을 확인한다**

Run: `grep -rn "concept.md" --include="*.md" . | grep -v "^./docs/superpowers/"`
Expected: `CLAUDE.md`와 `README.md` 두 곳이 나온다. `docs/superpowers/` 아래 스펙 문서는 과거 설계 기록이므로 고치지 않는다.

세 번째 파일이 나오면 그 파일도 함께 고쳐야 한다. Step 5에서 다시 확인한다.

- [ ] **Step 2: `templates/concept.md`를 지운다**

```bash
git rm templates/concept.md
```

- [ ] **Step 3: `CLAUDE.md` 1절을 고친다**

변경 전:
```markdown
### 1. 템플릿 고르기

- **답을 모르는 상태에서 시작해 알아낸 글** → `templates/troubleshooting.md`
- **이미 답을 알고 정리하는 글** → `templates/concept.md`

애매하면 물어본다. 임의로 정하지 않는다.
```

변경 후:
```markdown
### 1. 템플릿 고르기

- **기본이 되는 개념을 표와 짧은 설명으로 정리하는 글** → `templates/basics.md`
- **기본개념으로 간단히 설명하기 어렵거나 더 깊이 다루는 글** → `templates/deep-dive.md`
- **실제로 겪은 문제 상황의 파악과 해결 과정** → `templates/troubleshooting.md`

애매하면 물어본다. 임의로 정하지 않는다.

세 템플릿 모두 섹션이 필수와 선택으로 나뉘어 있다. 선택 섹션은 해당 없으면 지운다.
```

세 갈래의 표현이 3절 그룹 태그 표의 "담는 글" 열과 같은 구분을 가리켜야 한다. 3절은 고치지 않는다.

- [ ] **Step 4: `README.md`를 고친다**

45행의 디렉터리 주석을 바꾼다.

변경 전:
```
templates/                            # 글 템플릿 2종
```

변경 후:
```
templates/                            # 글 템플릿 3종
```

`#` 위치가 다른 줄들과 세로로 맞아 있으므로 정렬을 유지한다.

69–72행의 템플릿 목록을 바꾼다.

변경 전:
```markdown
템플릿은 두 가지다.

- [`templates/troubleshooting.md`](templates/troubleshooting.md) — 답을 모르는 상태에서 시작해 알아낸 글
- [`templates/concept.md`](templates/concept.md) — 이미 답을 알고 정리하는 글
```

변경 후:
```markdown
템플릿은 세 가지다. 각 템플릿의 섹션은 필수와 선택으로 나뉘어 있고, 선택 섹션은 해당 없으면 지운다.

- [`templates/basics.md`](templates/basics.md) — 기본이 되는 개념을 표와 짧은 설명으로 정리하는 글
- [`templates/deep-dive.md`](templates/deep-dive.md) — 기본개념으로 간단히 설명하기 어렵거나 더 깊이 다루는 글
- [`templates/troubleshooting.md`](templates/troubleshooting.md) — 실제로 겪은 문제 상황의 파악과 해결 과정
```

- [ ] **Step 5: 참조가 남지 않았는지 확인한다**

Run: `grep -rn "concept.md" --include="*.md" . | grep -v "^./docs/superpowers/"`
Expected: 아무것도 나오지 않는다.

Run: `ls templates/`
Expected: `basics.md`, `deep-dive.md`, `troubleshooting.md` 세 개만 나온다.

- [ ] **Step 6: 회귀가 없는지 확인한다**

Run: `npm test`
Expected: PASS, 22/22. 이 작업은 코드를 건드리지 않으므로 숫자가 그대로여야 한다.

Run: `npm run build`
Expected: PASS. `templates/`는 `src/content/posts/` 밖이라 스키마 검증 대상이 아니지만, 빌드가 깨지지 않음을 확인한다.

- [ ] **Step 7: 커밋**

```bash
git add -A templates CLAUDE.md README.md
git commit -m "docs: concept.md 삭제 및 템플릿 3종으로 문서 갱신"
```

---

## Self-Review

**Spec coverage**

| 스펙 항목 | 태스크 |
|---|---|
| 표기 방식 (`필수 —` / `선택 —` 안내문 줄) | Task 1·2·3 (Global Constraints에 형식 고정) |
| 규칙 주석 블록 | Task 1·2·3 (Global Constraints에 문구 고정) |
| 순서를 바꿔도 된다는 명시 | 규칙 주석 블록에 포함 |
| `basics.md` 필수 2 + 선택 9 | Task 1 Step 1, Step 2에서 개수 검증 |
| `basics.md` 섹션 순서 | Task 1 도입부에 명시, Step 1 코드가 그 순서 |
| 기본개념은 재현을 요구하지 않음 | Task 1 도입부에 근거 기술, `직접 확인`이 선택 |
| `deep-dive.md` 필수 2 + 선택 10 | Task 2 Step 1, Step 2에서 개수 검증 |
| `deep-dive.md` 섹션 순서 | Task 2 도입부에 명시 |
| `직접 확인`의 "비면 발행하지 않는다" 유지 | Task 2 Step 1 코드, Step 3에서 검증 |
| `troubleshooting.md` 여섯 섹션 전부 필수 | Task 3 Step 1, Step 2에서 `필수: 6` 검증 |
| `troubleshooting.md` 선택 5 | Task 3 Step 2에서 `선택: 5` 검증 |
| `가설과 검증`의 "틀린 가설도 남긴다" 유지 | Task 3 Step 1 코드, Step 3에서 검증 |
| 세 템플릿 `tags`에 그룹 태그 | Task 1 Step 3, Task 2 Step 3, Task 3 Step 3 |
| `concept.md` 삭제 | Task 4 Step 2, Step 5에서 검증 |
| `CLAUDE.md` 1절 세 갈래 | Task 4 Step 3 |
| `README.md` "템플릿은 두 가지다" | Task 4 Step 4 |
| `templates/`에 세 파일만 남음 | Task 4 Step 5 |
| `npm test` / `npm run build` 회귀 확인 | Task 4 Step 6 |

빠진 항목 없음.

**Placeholder scan**

TBD·TODO 없음. 세 템플릿의 전체 내용을 값 그대로 적었고, 문서 수정은 변경 전·후를 모두 인용했다. 모든 검증 단계에 명령과 기대 출력이 있다.

Task 4 Step 1의 "세 번째 파일이 나오면 그 파일도 함께 고쳐야 한다"는 플레이스홀더가 아니라, 계획 작성 시점에 확인한 참조 위치(2곳)가 실행 시점에 달라졌을 경우의 지침이다. Step 5가 같은 명령으로 결과를 확인한다.

**Type consistency**

코드 변경이 없어 타입은 없다. 대신 문자열과 경로의 일관성을 확인했다.

- 파일명 `templates/basics.md`, `templates/deep-dive.md`, `templates/troubleshooting.md`가 File Structure 표, Task 1·2·3의 Files 절, Task 4의 `CLAUDE.md`·`README.md` 본문에서 모두 일치한다.
- 그룹 태그 문자열 `기본개념`, `파고들기`, `오답노트`가 Global Constraints와 세 태스크의 frontmatter에서 일치한다.
- 안내문 접두사가 세 태스크 모두 `필수 — ` / `선택 — `(em dash + 공백)으로 동일하다. 검증 `grep -cE '^(필수|선택) — '`도 같은 패턴을 쓴다.
- `CLAUDE.md` 1절의 세 갈래 문구와 `README.md` 템플릿 목록의 세 갈래 문구가 서로 같다. 스펙의 문구와도 같다.
- 섹션 개수가 도입부 설명과 검증 기대값에서 일치한다. `basics.md` 11(2+9), `deep-dive.md` 12(2+10), `troubleshooting.md` 11(6+5).
