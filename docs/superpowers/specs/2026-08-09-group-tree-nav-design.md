# 좌측 목록을 2-depth 그룹 트리로

작성일: 2026-08-09

## 배경

홈 좌측 목록은 지금 평면이다. `전체보기` 아래에 카테고리(`Spring`, `데이터베이스`)가 나란히 놓인다.
카테고리는 기술 영역을 나누지만 글의 성격은 나누지 못한다. 기초를 정리한 글과 내부 동작을 파고든
글과 문제 해결 기록이 같은 목록에 섞인다.

글의 성격을 상위 축으로 두고 카테고리를 그 아래에 두는 2-depth 구조로 바꾼다.

## 그룹

상위 축을 그룹이라 부른다. 세 개로 고정한다.

| 그룹 | 담는 글 |
|---|---|
| `기본개념` | 기본이 되는 개념을 표와 짧은 설명·예시로 정리한 글 |
| `파고들기` | 기본개념으로 간단히 설명하기 어렵거나, 기본개념을 더 깊고 자세하게 다룬 글 |
| `오답노트` | 실제로 맞닥뜨린 문제 상황을 파악하고 해결한 과정과 방식을 설명한 글 |

세 그룹 모두 하위에 카테고리를 갖는다. 대칭이다.

이름에 공백을 넣지 않는다. 그룹은 태그로 표현하고 태그는 URL에 그대로 들어가므로,
공백이 있으면 `/tags/기본%20개념/`이 된다.

## 결정 사항

### 그룹은 예약 태그로 판정한다

frontmatter에 필드를 새로 만들지 않는다. `tags` 배열에 그룹 이름과 같은 태그가 들어 있으면
그 글은 그 그룹에 속한다.

```yaml
---
title: "같은 클래스 안에서 부른 @Transactional은 왜 동작하지 않을까"
category: "Spring"
tags: ["파고들기", "Spring", "트랜잭션", "AOP"]
---
```

### 그룹 태그도 일반 태그처럼 노출한다

글 하단 태그 배지와 `/tags/` 목록에서 그룹 태그를 걸러내지 않는다. 태그 관련 코드는
건드리지 않는다.

### 그룹 태그가 없거나 둘 이상이면 빌드를 실패시킨다

`npm run build`가 어느 파일인지 알려주며 멈춘다. 새 글을 쓸 때 빠뜨리는 사고를 막는다.

### 글이 0개인 그룹도 트리에 표시한다

`파고들기` 외 두 그룹은 초기에 글이 0개다. 숨기면 트리가 비어 보이므로 `(0)`으로 표시하고
링크도 건다. 그룹 목록 페이지는 "아직 글이 없습니다"를 보여준다 (`ListLayout`의 기존 동작).

## 데이터 모델

`src/lib/posts.ts`에 그룹 상수를 둔다. 배열 순서가 곧 트리에 표시되는 순서다.

```ts
export const GROUPS = ['기본개념', '파고들기', '오답노트'] as const;
```

`src/content.config.ts`의 스키마에 `.refine()`을 걸어 검증한다.

```ts
schema: z.object({ /* 기존과 동일 */ }).refine(
  (d) => d.tags.filter((t) => (GROUPS as readonly string[]).includes(t)).length === 1,
  { message: `tags에 그룹 태그(${GROUPS.join(', ')}) 중 정확히 하나가 있어야 한다` }
);
```

`content.config.ts`가 `src/lib/posts.ts`를 import 한다. `posts.ts`는 `astro:content`를 import
하지 않는 순수 모듈이므로 방향이 한쪽뿐이고 순환하지 않는다.

## 트리 계산

`src/lib/posts.ts`에 순수 함수 두 개를 추가한다. `astro:content`를 쓰지 않으므로 Vitest로
테스트된다.

```ts
export type GroupNode = {
  group: string;
  count: number;
  categories: { category: string; count: number }[];
};

/** tags에서 그룹 태그를 찾는다. 없으면 undefined */
export function groupOf(post: PostLike): string | undefined;

/** GROUPS 순서로 고정된 2-depth 트리를 만든다 */
export function buildGroupTree<T extends PostLike>(posts: T[]): GroupNode[];
```

- 그룹 순서는 건수와 무관하게 `GROUPS` 순서를 따른다.
- 하위 카테고리 정렬은 기존 `collectCategories`와 같은 규칙이다. 건수 내림차순, 동률이면
  이름 오름차순(`localeCompare(_, 'ko')`).
- 그룹 태그가 없는 글은 트리에서 제외한다. 스키마가 막으므로 실제로는 도달하지 않지만,
  순수 함수가 잘못된 입력에 대해 예측 가능하게 동작하도록 정의해 둔다.

기존 `collectCategories`는 그대로 둔다. `/categories/<카테고리>/` 페이지가 계속 쓴다.

## 라우트

| 항목 | URL | 파일 |
|---|---|---|
| 전체보기 | `/` | `pages/index.astro` (기존) |
| 그룹 | `/groups/<그룹>/` | `pages/groups/[group].astro` (신규) |
| 그룹 > 카테고리 | `/categories/<카테고리>/<그룹>/` | `pages/categories/[category]/[group].astro` (신규) |
| 카테고리 (트리에서 링크 안 함) | `/categories/<카테고리>/` | `pages/categories/[category].astro` (기존, 유지) |

`/categories/<카테고리>/`를 남기는 이유는 두 가지다. 글 하단 카테고리 배지가 이 URL을 가리키고
있고, 이미 발행된 주소를 깨뜨릴 이유가 없다.

`pages/categories/[category].astro`와 `pages/categories/[category]/[group].astro`는 경로 깊이가
달라 충돌하지 않는다.

`getStaticPaths` 생성 범위:

- `groups/[group]`: `GROUPS` 전체를 돈다. 글이 0개인 그룹도 페이지를 만든다.
- `categories/[category]/[group]`: 글이 1편 이상 있는 (카테고리, 그룹) 조합만 만든다.
  빈 조합까지 만들면 카테고리 수 × 3개의 빈 페이지가 생긴다.

## 컴포넌트

### CategoryList.astro

`<ul>` 중첩 구조로 바꾼다. props가 바뀐다.

```ts
interface Props {
  groups: GroupNode[];
  total: number;
  /** 현재 위치. 홈(전체보기)이면 넘기지 않는다 */
  current?: { group?: string; category?: string };
}
```

`is-current` 판정 규칙은 다음과 같다.

| 페이지 | 넘기는 `current` | 강조되는 항목 |
|---|---|---|
| `/` | 없음 | 전체보기 |
| `/groups/<그룹>/` | `{ group }` | 해당 그룹 |
| `/categories/<카테고리>/<그룹>/` | `{ group, category }` | 해당 하위 카테고리만 |
| `/categories/<카테고리>/` | `{ category }` | 없음 |

부모까지 함께 강조하지 않는다. 하위 카테고리를 보고 있을 때 그룹은 강조하지 않는다.

`/categories/<카테고리>/`는 트리에 대응하는 항목이 없으므로 아무것도 강조되지 않는다.
`current`를 넘기지 않으면 전체보기가 강조되므로, 이 페이지는 `{ category }`를 넘겨 전체보기가
잘못 강조되는 것을 막는다.

접기·펼치기는 넣지 않는다. 그룹 3개에 카테고리 몇 개뿐이라 항상 펼쳐도 짧다.

### ListLayout.astro

`categories: { category, count }[]` prop을 `groups: GroupNode[]`로, `current?: string`을
`current?: { group?, category? }`로 바꿔 그대로 넘긴다. 레이아웃 구조와 스타일은 그대로 둔다.

호출부는 `pages/index.astro`와 `pages/categories/[category].astro` 둘뿐이고, 여기에 신규
라우트 두 개가 더해진다.

### 좁은 화면 (max-width: 899px)

지금은 전체 항목을 가로로 흘린다. 2-depth는 그렇게 못 하므로 그룹마다 한 줄을 차지하고,
그 줄 안에서 하위 카테고리가 가로로 흐르는 형태로 바꾼다.

```
전체보기 (3)
기본개념 (0)
파고들기 (3)   Spring (2)  데이터베이스 (1)
오답노트 (0)
```

## 테스트

`src/lib/posts.test.ts`에 먼저 쓴다.

`groupOf`
- 그룹 태그가 하나면 그 값을 반환한다
- 그룹 태그가 없으면 `undefined`를 반환한다

`buildGroupTree`
- 빈 배열을 넣으면 그룹 3개가 모두 `count: 0`, `categories: []`로 나온다
- 그룹 순서가 건수와 무관하게 `GROUPS` 순서를 따른다
- 하위 카테고리가 건수 내림차순으로 정렬된다
- 건수가 같으면 카테고리 이름 오름차순(한국어)으로 정렬된다
- 그룹 태그가 없는 글은 결과에서 빠지고 상위 `count`에도 잡히지 않는다

## 마이그레이션

기존 글 3편의 `tags`에 `파고들기`를 추가한다. 세 편 모두 `concept.md` 템플릿으로 쓰였고
(왜 필요한가 → 핵심 개념 → 동작 원리 → 직접 확인), 제목과 주제가 표준·기본 정의를 넘어선
내용이다.

| 슬러그 | 추가 후 tags |
|---|---|
| `transaction-isolation-levels` | `["파고들기", "Database", "트랜잭션", "테스트"]` |
| `transactional-propagation` | `["파고들기", "Spring", "트랜잭션", "테스트"]` |
| `transactional-self-invocation` | `["파고들기", "Spring", "트랜잭션", "AOP"]` |

이 작업 직후 트리는 `기본개념 0 / 파고들기 3 / 오답노트 0`이다. 이 불균형은 후속 작업인
[글 분할](2026-08-09-post-split-basics-deepdive-design.md)에서 해소된다.

## 문서

`CLAUDE.md`의 frontmatter 표에 그룹 태그 규칙을 적는다. `tags`의 비고에 "그룹 태그
(기본개념/파고들기/오답노트) 중 정확히 하나를 반드시 포함한다"를 넣고, 카테고리 확인용
`grep` 옆에 그룹별 글 수를 세는 방법을 덧붙인다.

## 범위 밖

- 트리 접기·펼치기
- frontmatter `group` 필드
- 그룹 태그를 `/tags/` 목록에서 숨기기
- `/categories/<카테고리>/` 제거
- 그룹별 RSS
