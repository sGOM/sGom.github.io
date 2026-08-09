# 좌측 목록 2-depth 그룹 트리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈 좌측 목록을 평면 카테고리 목록에서 그룹(기본개념/파고들기/오답노트) 아래에 카테고리가 붙는 2-depth 트리로 바꾼다.

**Architecture:** 그룹은 `tags` 배열에 들어가는 예약 태그로 판정한다. frontmatter 필드를 새로 만들지 않고, Zod 스키마의 `.refine()`으로 글마다 그룹 태그가 정확히 하나인지 빌드 시점에 검증한다. 트리 계산은 `src/lib/posts.ts`의 순수 함수에 두어 Vitest로 테스트하고, Astro 컴포넌트는 계산된 트리를 받아 그리기만 한다.

**Tech Stack:** Astro 5 (Content Layer, `glob` loader), TypeScript, Zod (`astro/zod`), Vitest

설계 문서: `docs/superpowers/specs/2026-08-09-group-tree-nav-design.md`

## Global Constraints

- 그룹은 `기본개념`, `파고들기`, `오답노트` 셋으로 고정한다. 이름에 공백을 넣지 않는다.
- 트리에 표시되는 그룹 순서는 건수와 무관하게 항상 `기본개념` → `파고들기` → `오답노트`다.
- 하위 카테고리 정렬 규칙은 기존 `collectCategories`와 같다. 건수 내림차순, 동률이면 이름 오름차순(`localeCompare(_, 'ko')`).
- 글이 0개인 그룹도 트리에 `(0)`으로 표시하고 링크를 건다.
- 그룹 태그는 `/tags/` 목록과 글 하단 배지에서 걸러내지 않는다. 태그 관련 코드는 건드리지 않는다.
- `src/lib/posts.ts`는 `astro:content`를 import 하지 않는다. 순수 모듈로 유지한다.
- `astro.config.mjs`에 `base`를 넣지 않는다.
- 기존 `/categories/<카테고리>/` 라우트는 제거하지 않는다.

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `src/lib/posts.ts` | 그룹 상수, 그룹 판정, 트리 계산. 순수 함수만 | 수정 |
| `src/lib/posts.test.ts` | 위 함수들의 테스트 | 수정 |
| `src/content.config.ts` | 그룹 태그 개수 검증 | 수정 |
| `src/components/CategoryList.astro` | 2-depth 트리 렌더와 현재 위치 강조 | 수정 |
| `src/layouts/ListLayout.astro` | 트리를 CategoryList로 전달 | 수정 |
| `src/pages/index.astro` | 전체보기 | 수정 |
| `src/pages/categories/[category].astro` | 카테고리 단독 페이지 (트리에서 링크하지 않음) | 수정 |
| `src/pages/groups/[group].astro` | 그룹 페이지 | 생성 |
| `src/pages/categories/[category]/[group].astro` | 그룹 × 카테고리 페이지 | 생성 |
| `src/content/posts/*/index.md` | 기존 3편에 그룹 태그 추가 | 수정 |
| `CLAUDE.md` | 그룹 태그 작성 규칙 | 수정 |

---

## Task 1: 그룹 상수와 트리 계산 순수 함수

`GROUPS`, `groupOf`, `buildGroupTree`를 추가한다. 이후 모든 태스크가 이 세 가지에 의존한다.

**Files:**
- Modify: `src/lib/posts.ts`
- Test: `src/lib/posts.test.ts`

**Interfaces:**
- Consumes: `PostLike`, `collectCategories` (같은 파일에 이미 있음)
- Produces:
  - `GROUPS: readonly ['기본개념', '파고들기', '오답노트']`
  - `type GroupNode = { group: string; count: number; categories: { category: string; count: number }[] }`
  - `groupOf(post: PostLike): string | undefined`
  - `buildGroupTree<T extends PostLike>(posts: T[]): GroupNode[]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`src/lib/posts.test.ts`의 import 문에 `GROUPS`, `groupOf`, `buildGroupTree`를 추가한다.

```ts
import {
  sortByDate,
  filterDrafts,
  collectTags,
  collectCategories,
  GROUPS,
  groupOf,
  buildGroupTree,
  type PostLike,
} from './posts';
```

파일 맨 끝에 다음 두 `describe` 블록을 붙인다. 기존 `post()` 헬퍼를 그대로 쓴다.

```ts
describe('groupOf', () => {
  it('tags에 있는 그룹 태그를 반환한다', () => {
    expect(groupOf(post('a', { tags: ['파고들기', 'Spring'] }))).toBe('파고들기');
  });

  it('그룹 태그의 위치와 무관하게 찾아낸다', () => {
    expect(groupOf(post('a', { tags: ['Spring', '트랜잭션', '오답노트'] }))).toBe(
      '오답노트'
    );
  });

  it('그룹 태그가 없으면 undefined를 반환한다', () => {
    expect(groupOf(post('a', { tags: ['Spring'] }))).toBeUndefined();
  });
});

describe('buildGroupTree', () => {
  it('글이 없어도 그룹 3개를 모두 만든다', () => {
    expect(buildGroupTree([])).toEqual([
      { group: '기본개념', count: 0, categories: [] },
      { group: '파고들기', count: 0, categories: [] },
      { group: '오답노트', count: 0, categories: [] },
    ]);
  });

  it('그룹 순서는 건수와 무관하게 GROUPS 순서를 따른다', () => {
    const posts = [
      post('a', { tags: ['오답노트'] }),
      post('b', { tags: ['오답노트'] }),
      post('c', { tags: ['기본개념'] }),
    ];
    expect(buildGroupTree(posts).map((g) => g.group)).toEqual([...GROUPS]);
  });

  it('그룹별 글 수를 센다', () => {
    const posts = [
      post('a', { tags: ['기본개념'] }),
      post('b', { tags: ['파고들기'] }),
      post('c', { tags: ['파고들기'] }),
    ];
    expect(buildGroupTree(posts).map((g) => g.count)).toEqual([1, 2, 0]);
  });

  it('하위 카테고리를 건수 내림차순으로 정렬한다', () => {
    const posts = [
      post('a', { tags: ['기본개념'], category: 'Spring' }),
      post('b', { tags: ['기본개념'], category: 'Spring' }),
      post('c', { tags: ['기본개념'], category: '데이터베이스' }),
    ];
    const basics = buildGroupTree(posts)[0];
    expect(basics.count).toBe(3);
    expect(basics.categories).toEqual([
      { category: 'Spring', count: 2 },
      { category: '데이터베이스', count: 1 },
    ]);
  });

  it('건수가 같으면 카테고리 이름 가나다순으로 정렬한다', () => {
    const posts = [
      post('a', { tags: ['파고들기'], category: '서버' }),
      post('b', { tags: ['파고들기'], category: '네트워크' }),
      post('c', { tags: ['파고들기'], category: '데이터베이스' }),
    ];
    expect(buildGroupTree(posts)[1].categories.map((c) => c.category)).toEqual([
      '네트워크',
      '데이터베이스',
      '서버',
    ]);
  });

  it('다른 그룹의 글은 서로 섞이지 않는다', () => {
    const posts = [
      post('a', { tags: ['기본개념'], category: 'Spring' }),
      post('b', { tags: ['오답노트'], category: 'Spring' }),
    ];
    const tree = buildGroupTree(posts);
    expect(tree[0].categories).toEqual([{ category: 'Spring', count: 1 }]);
    expect(tree[2].categories).toEqual([{ category: 'Spring', count: 1 }]);
  });

  it('그룹 태그가 없는 글은 어느 그룹에도 들어가지 않는다', () => {
    const posts = [post('a', { tags: ['Spring'] })];
    expect(buildGroupTree(posts)).toEqual([
      { group: '기본개념', count: 0, categories: [] },
      { group: '파고들기', count: 0, categories: [] },
      { group: '오답노트', count: 0, categories: [] },
    ]);
  });
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL. `GROUPS`, `groupOf`, `buildGroupTree`가 `./posts`에 없어 import 에러 또는 "is not a function"이 난다.

- [ ] **Step 3: 최소 구현을 쓴다**

`src/lib/posts.ts` 맨 끝에 붙인다. `collectCategories`가 위에 정의돼 있어야 하므로 파일 끝이 맞다.

```ts
/** 글의 성격을 나누는 상위 축. 배열 순서가 곧 좌측 트리에 표시되는 순서다 */
export const GROUPS = ['기본개념', '파고들기', '오답노트'] as const;

export type GroupNode = {
  group: string;
  count: number;
  categories: { category: string; count: number }[];
};

/**
 * tags에서 그룹 태그를 찾는다.
 * 스키마가 "정확히 하나"를 보장하므로 실제로는 항상 값이 나온다.
 */
export function groupOf(post: PostLike): string | undefined {
  return post.data.tags.find((t) => (GROUPS as readonly string[]).includes(t));
}

/** GROUPS 순서로 고정된 2-depth 트리를 만든다. 글이 0개인 그룹도 남긴다 */
export function buildGroupTree<T extends PostLike>(posts: T[]): GroupNode[] {
  return GROUPS.map((group) => {
    const inGroup = posts.filter((p) => groupOf(p) === group);
    return {
      group,
      count: inGroup.length,
      categories: collectCategories(inGroup),
    };
  });
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS. 기존 테스트를 포함해 전부 통과한다.

- [ ] **Step 5: 커밋**

```bash
git add src/lib/posts.ts src/lib/posts.test.ts
git commit -m "feat: 그룹 트리 계산 순수 함수 추가"
```

---

## Task 2: 스키마 검증과 기존 글 마이그레이션

그룹 태그 검증을 켜면 기존 3편이 즉시 빌드를 깨뜨린다. 검증과 마이그레이션은 한 커밋이어야 한다.

**Files:**
- Modify: `src/content.config.ts`
- Modify: `src/content/posts/transaction-isolation-levels/index.md` (frontmatter `tags`)
- Modify: `src/content/posts/transactional-propagation/index.md` (frontmatter `tags`)
- Modify: `src/content/posts/transactional-self-invocation/index.md` (frontmatter `tags`)
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Task 1의 `GROUPS`
- Produces: 모든 글이 그룹 태그를 정확히 하나 갖는다는 불변식. Task 3·4가 이에 의존한다.

- [ ] **Step 1: 검증을 켜기 전에 현재 빌드가 통과하는지 확인한다**

Run: `npm run build`
Expected: PASS. 이후 실패가 새로 켠 검증 때문임을 분명히 하기 위한 기준선이다.

- [ ] **Step 2: 스키마에 `.refine()`을 건다**

`src/content.config.ts`를 아래 내용으로 바꾼다. `z.object({...})` 뒤에 `.refine()`이 붙는 것이 유일한 변경이며, import 한 줄이 늘어난다.

```ts
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';
import { GROUPS } from './lib/posts';

const posts = defineCollection({
  loader: glob({
    pattern: '**/index.md',
    base: './src/content/posts',
    // 'transaction-isolation-levels/index.md' -> 'transaction-isolation-levels'
    generateId: ({ entry }) => entry.replace(/\/index\.md$/, ''),
  }),
  schema: z
    .object({
      title: z.string(),
      description: z.string(),
      pubDate: z.coerce.date(),
      category: z.string(),
      tags: z.array(z.string()).nonempty(),
      updatedDate: z.coerce.date().optional(),
      draft: z.boolean().default(false),
    })
    .refine(
      (d) =>
        d.tags.filter((t) => (GROUPS as readonly string[]).includes(t)).length === 1,
      {
        message: `tags에 그룹 태그(${GROUPS.join(', ')}) 중 정확히 하나가 있어야 한다`,
        path: ['tags'],
      }
    ),
});

export const collections = { posts };
```

- [ ] **Step 3: 검증이 기존 글을 잡아내는지 확인한다**

Run: `npm run build`
Expected: FAIL. 세 글 모두 그룹 태그가 없어 스키마 에러가 난다. 에러 메시지에 파일명(또는 엔트리 id)과 `tags에 그룹 태그(...) 중 정확히 하나가 있어야 한다`가 나오는지 확인한다.

이 확인이 이 태스크의 핵심이다. 빌드가 통과해 버리면 `.refine()`이 붙지 않은 것이므로 Step 2로 돌아간다.

- [ ] **Step 4: 기존 3편에 `파고들기` 태그를 추가한다**

각 파일 frontmatter의 `tags` 배열 맨 앞에 `"파고들기"`를 넣는다. 다른 필드는 건드리지 않는다.

`src/content/posts/transaction-isolation-levels/index.md`
```yaml
tags: ["파고들기", "Database", "트랜잭션", "테스트"]
```

`src/content/posts/transactional-propagation/index.md`
```yaml
tags: ["파고들기", "Spring", "트랜잭션", "테스트"]
```

`src/content/posts/transactional-self-invocation/index.md`
```yaml
tags: ["파고들기", "Spring", "트랜잭션", "AOP"]
```

세 파일 모두 원본 항목의 순서와 값을 그대로 유지한 채 맨 앞에 `"파고들기"`만 넣는다.

- [ ] **Step 5: 빌드가 다시 통과하는지 확인한다**

Run: `npm run build`
Expected: PASS.

- [ ] **Step 6: `CLAUDE.md`에 그룹 태그 규칙을 적는다**

3절 frontmatter 표의 `tags` 행을 바꾼다.

변경 전:
```markdown
| `tags` | O | 최소 1개 |
```

변경 후:
```markdown
| `tags` | O | 최소 1개. 그룹 태그를 정확히 하나 포함해야 한다 |
```

3절의 카테고리 설명 문단 바로 앞에 다음 문단과 표를 넣는다.

```markdown
글의 성격은 `tags`에 넣는 **그룹 태그**로 정한다. 홈 좌측 목록의 1-depth가 되며, 셋 중
정확히 하나를 반드시 넣어야 한다. 없거나 둘 이상이면 `npm run build`가 실패한다.

| 그룹 태그 | 담는 글 |
|---|---|
| `기본개념` | 기본이 되는 개념을 표와 짧은 설명·예시로 정리한 글 |
| `파고들기` | 기본개념으로 간단히 설명하기 어렵거나, 더 깊고 자세하게 다룬 글 |
| `오답노트` | 실제로 맞닥뜨린 문제 상황을 파악하고 해결한 과정을 설명한 글 |
```

3절 끝의 카테고리 확인용 `grep` 블록 아래에 그룹별 글 수를 세는 명령을 덧붙인다.

```bash
grep -h "^tags:" src/content/posts/*/index.md | grep -o "기본개념\|파고들기\|오답노트" | sort | uniq -c
```

- [ ] **Step 7: 커밋**

```bash
git add src/content.config.ts src/content/posts CLAUDE.md
git commit -m "feat: 그룹 태그 검증 추가 및 기존 글 마이그레이션"
```

---

## Task 3: CategoryList를 2-depth 트리로 전환

props 이름과 모양이 바뀌므로 컴포넌트·레이아웃·기존 호출부 두 곳을 한 번에 고쳐야 빌드가 깨지지 않는다.

**Files:**
- Modify: `src/components/CategoryList.astro`
- Modify: `src/layouts/ListLayout.astro`
- Modify: `src/pages/index.astro`
- Modify: `src/pages/categories/[category].astro`

**Interfaces:**
- Consumes: Task 1의 `GroupNode`, `buildGroupTree`
- Produces:
  - `CategoryList` props: `{ groups: GroupNode[]; total: number; current?: { group?: string; category?: string } }`
  - `ListLayout` props: 기존 `title`, `description`, `heading?`, `posts`에 더해 위와 같은 `groups`, `total`, `current`. `categories` prop은 사라진다. Task 4의 신규 라우트가 이 시그니처를 쓴다.

강조 규칙:

| 페이지 | `current` | 강조 |
|---|---|---|
| `/` | 넘기지 않음 | 전체보기 |
| `/groups/<그룹>/` | `{ group }` | 해당 그룹 |
| `/categories/<카테고리>/<그룹>/` | `{ group, category }` | 해당 하위 카테고리만 |
| `/categories/<카테고리>/` | `{ category }` | 없음 |

부모까지 함께 강조하지 않는다.

- [ ] **Step 1: `CategoryList.astro`를 다시 쓴다**

파일 전체를 아래 내용으로 바꾼다.

```astro
---
import type { GroupNode } from '../lib/posts';

interface Props {
  groups: GroupNode[];
  total: number;
  /** 현재 위치. 홈(전체보기)이면 넘기지 않는다 */
  current?: { group?: string; category?: string };
}

const { groups, total, current } = Astro.props;
---

<aside class="category-list" data-pagefind-ignore aria-label="카테고리">
  <ul class="groups">
    <li>
      <a href="/" class:list={[current === undefined && 'is-current']}>
        전체보기 <span class="count">({total})</span>
      </a>
    </li>
    {groups.map(({ group, count, categories }) => (
      <li>
        <a
          href={`/groups/${encodeURIComponent(group)}/`}
          class:list={[
            current?.group === group &&
              current?.category === undefined &&
              'is-current',
          ]}
        >
          {group} <span class="count">({count})</span>
        </a>
        {categories.length > 0 && (
          <ul class="categories">
            {categories.map(({ category, count }) => (
              <li>
                <a
                  href={`/categories/${encodeURIComponent(category)}/${encodeURIComponent(group)}/`}
                  class:list={[
                    current?.group === group &&
                      current?.category === category &&
                      'is-current',
                  ]}
                >
                  {category} <span class="count">({count})</span>
                </a>
              </li>
            ))}
          </ul>
        )}
      </li>
    ))}
  </ul>
</aside>

<style>
  .category-list {
    position: sticky;
    top: 5.5rem;
    align-self: start;
    max-height: calc(100vh - 7rem);
    overflow-y: auto;
    font-size: 0.9rem;
  }

  ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .groups {
    display: flex;
    flex-direction: column;
    gap: 0.6rem;
  }

  /* 2-depth. 세로선으로 들여쓰기를 드러낸다 */
  .categories {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    margin-top: 0.4rem;
    padding-left: 0.75rem;
    border-left: 1px solid var(--border);
  }

  .categories a {
    font-size: 0.85rem;
  }

  a {
    color: var(--fg-muted);
  }

  a:hover {
    color: var(--fg);
  }

  .is-current {
    color: var(--fg);
    font-weight: 700;
  }

  .count {
    font-size: 0.8rem;
  }

  /* 좁은 화면에서는 본문 위로 접어 올린다.
     2-depth는 가로로 못 펴므로 그룹마다 한 줄을 차지하고
     그 줄 안에서 하위 카테고리가 가로로 흐른다 */
  @media (max-width: 899px) {
    .category-list {
      position: static;
      max-height: none;
      margin-bottom: 2rem;
      padding-bottom: 1.5rem;
      border-bottom: 1px solid var(--border);
    }
    .groups {
      gap: 0.75rem;
    }
    .groups > li {
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      gap: 0.5rem 1rem;
    }
    .categories {
      flex-direction: row;
      flex-wrap: wrap;
      gap: 0.5rem 1rem;
      margin-top: 0;
      padding-left: 0;
      border-left: 0;
    }
  }
</style>
```

- [ ] **Step 2: `ListLayout.astro`의 props를 바꾼다**

`src/layouts/ListLayout.astro`의 frontmatter와 `CategoryList` 호출부만 고친다. `<style>` 블록과 나머지 마크업은 그대로 둔다.

frontmatter를 아래로 바꾼다.

```astro
---
import type { CollectionEntry } from 'astro:content';
import BaseLayout from './BaseLayout.astro';
import CategoryList from '../components/CategoryList.astro';
import PostCard from '../components/PostCard.astro';
import type { GroupNode } from '../lib/posts';

interface Props {
  title: string;
  description: string;
  /** 목록 위에 노출할 제목. 홈에서는 생략한다 */
  heading?: string;
  posts: CollectionEntry<'posts'>[];
  groups: GroupNode[];
  total: number;
  /** 현재 위치. 홈이면 넘기지 않는다 */
  current?: { group?: string; category?: string };
}

const { title, description, heading, posts, groups, total, current } =
  Astro.props;
---
```

`CategoryList` 호출부를 바꾼다.

변경 전:
```astro
      <CategoryList categories={categories} total={total} current={current} />
```

변경 후:
```astro
      <CategoryList groups={groups} total={total} current={current} />
```

- [ ] **Step 3: `index.astro`를 고친다**

`src/pages/index.astro` 전체를 아래로 바꾼다.

```astro
---
import { getCollection } from 'astro:content';
import ListLayout from '../layouts/ListLayout.astro';
import { sortByDate, filterDrafts, buildGroupTree } from '../lib/posts';

const all = await getCollection('posts');
const visible = filterDrafts(all, import.meta.env.DEV);
const posts = sortByDate(visible);
---

<ListLayout
  title="sGOM"
  description="개발하며 겪은 문제와 공부한 개념을 남깁니다"
  posts={posts}
  groups={buildGroupTree(visible)}
  total={visible.length}
/>
```

- [ ] **Step 4: `categories/[category].astro`를 고친다**

`src/pages/categories/[category].astro` 전체를 아래로 바꾼다. `collectCategories`는 경로 생성에만 남고, 트리는 `buildGroupTree`가 만든다.

```astro
---
import { getCollection } from 'astro:content';
import ListLayout from '../../layouts/ListLayout.astro';
import {
  collectCategories,
  buildGroupTree,
  sortByDate,
  filterDrafts,
} from '../../lib/posts';

export async function getStaticPaths() {
  const all = await getCollection('posts');
  const posts = filterDrafts(all, import.meta.env.DEV);
  const groups = buildGroupTree(posts);
  return collectCategories(posts).map(({ category }) => ({
    params: { category },
    props: {
      posts: sortByDate(posts.filter((p) => p.data.category === category)),
      groups,
      total: posts.length,
    },
  }));
}

const { category } = Astro.params;
const { posts, groups, total } = Astro.props;
---

<ListLayout
  title={`${category} | sGOM`}
  description={`${category} 카테고리의 글`}
  heading={category}
  posts={posts}
  groups={groups}
  total={total}
  current={{ category }}
/>
```

- [ ] **Step 5: 순수 함수 테스트가 여전히 통과하는지 확인한다**

Run: `npm test`
Expected: PASS. 이 태스크는 `posts.ts`를 건드리지 않으므로 Task 1의 테스트가 그대로 통과해야 한다.

- [ ] **Step 6: 빌드가 통과하는지 확인한다**

Run: `npm run build`
Expected: PASS. `categories` prop이 남아 있으면 여기서 타입 에러가 난다.

`/groups/파고들기/` 링크는 아직 대상 페이지가 없다. Task 4에서 만든다. Astro는 정적 빌드에서 내부 링크 대상을 검사하지 않으므로 빌드는 통과한다.

- [ ] **Step 7: 개발 서버에서 눈으로 확인한다**

Run: `npm run dev`

확인할 것:
- 홈 좌측에 `전체보기 (3)` 아래로 `기본개념 (0)` / `파고들기 (3)` / `오답노트 (0)`가 나오고, `파고들기` 아래에 `Spring (2)`와 `데이터베이스 (1)`가 들여쓰기된 채 붙는다.
- 홈에서 `전체보기`만 굵게 강조된다.
- 브라우저 폭을 899px 이하로 줄이면 목록이 본문 위로 올라가고, `파고들기 (3)`과 하위 카테고리가 한 줄에 가로로 놓인다.
- `/categories/Spring/`으로 이동하면 좌측에서 아무 항목도 강조되지 않는다. 특히 `전체보기`가 강조되면 안 된다.

- [ ] **Step 8: 커밋**

```bash
git add src/components/CategoryList.astro src/layouts/ListLayout.astro src/pages/index.astro src/pages/categories/[category].astro
git commit -m "feat: 좌측 목록을 2-depth 그룹 트리로 전환"
```

---

## Task 4: 그룹 페이지와 그룹 × 카테고리 페이지

Task 3에서 만든 링크의 대상 페이지를 만든다.

**Files:**
- Create: `src/pages/groups/[group].astro`
- Create: `src/pages/categories/[category]/[group].astro`

**Interfaces:**
- Consumes: Task 1의 `GROUPS`, `groupOf`, `buildGroupTree`. Task 3의 `ListLayout` props 시그니처
- Produces: 없음. 마지막 태스크다

`src/pages/categories/[category].astro`와 `src/pages/categories/[category]/[group].astro`는 경로 깊이가 달라 충돌하지 않는다. 기존 파일을 지우거나 옮기지 않는다.

`getCollection`이 돌려주는 `CollectionEntry<'posts'>`는 `PostLike`의 필드를 모두 갖고 있어 `groupOf`에 그대로 넘길 수 있다. `filterDrafts`, `sortByDate`가 이미 같은 방식으로 쓰이고 있다.

- [ ] **Step 1: 그룹 페이지를 만든다**

`src/pages/groups/[group].astro`를 만든다.

```astro
---
import { getCollection } from 'astro:content';
import ListLayout from '../../layouts/ListLayout.astro';
import {
  GROUPS,
  groupOf,
  buildGroupTree,
  sortByDate,
  filterDrafts,
} from '../../lib/posts';

export async function getStaticPaths() {
  const all = await getCollection('posts');
  const posts = filterDrafts(all, import.meta.env.DEV);
  const groups = buildGroupTree(posts);
  // 글이 0개인 그룹도 트리에서 링크하므로 GROUPS 전체를 돈다
  return GROUPS.map((group) => ({
    params: { group },
    props: {
      posts: sortByDate(posts.filter((p) => groupOf(p) === group)),
      groups,
      total: posts.length,
    },
  }));
}

const { group } = Astro.params;
const { posts, groups, total } = Astro.props;
---

<ListLayout
  title={`${group} | sGOM`}
  description={`${group} 그룹의 글`}
  heading={group}
  posts={posts}
  groups={groups}
  total={total}
  current={{ group }}
/>
```

- [ ] **Step 2: 그룹 × 카테고리 페이지를 만든다**

`src/pages/categories/[category]/[group].astro`를 만든다. 트리의 `categories`에는 글이 1편 이상인 조합만 들어 있으므로, 그대로 펼치면 빈 페이지가 생기지 않는다.

```astro
---
import { getCollection } from 'astro:content';
import ListLayout from '../../../layouts/ListLayout.astro';
import {
  groupOf,
  buildGroupTree,
  sortByDate,
  filterDrafts,
} from '../../../lib/posts';

export async function getStaticPaths() {
  const all = await getCollection('posts');
  const posts = filterDrafts(all, import.meta.env.DEV);
  const groups = buildGroupTree(posts);
  // 글이 1편 이상인 (카테고리, 그룹) 조합만 만든다
  return groups.flatMap(({ group, categories }) =>
    categories.map(({ category }) => ({
      params: { category, group },
      props: {
        posts: sortByDate(
          posts.filter(
            (p) => p.data.category === category && groupOf(p) === group
          )
        ),
        groups,
        total: posts.length,
      },
    }))
  );
}

const { category, group } = Astro.params;
const { posts, groups, total } = Astro.props;
---

<ListLayout
  title={`${group} · ${category} | sGOM`}
  description={`${group} 그룹의 ${category} 카테고리 글`}
  heading={`${group} · ${category}`}
  posts={posts}
  groups={groups}
  total={total}
  current={{ group, category }}
/>
```

- [ ] **Step 3: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS.

- [ ] **Step 4: 빌드가 통과하고 페이지가 생성되는지 확인한다**

Run: `npm run build`
Expected: PASS.

빌드 로그에 다음 5개 경로가 생성됐는지 확인한다. 초안을 제외한 상태(`파고들기` 3편)라면 이렇게 나온다.

```
/groups/기본개념/
/groups/파고들기/
/groups/오답노트/
/categories/Spring/파고들기/
/categories/데이터베이스/파고들기/
```

`/categories/Spring/기본개념/`처럼 글이 없는 조합이 생성됐다면 Step 2의 `flatMap`이 잘못된 것이다.

- [ ] **Step 5: 개발 서버에서 이동을 확인한다**

Run: `npm run dev`

확인할 것:
- 좌측에서 `파고들기`를 누르면 `/groups/파고들기/`로 가고 글 3편이 나오며, 좌측에서 `파고들기`만 강조된다. 하위 `Spring`은 강조되지 않는다.
- 좌측에서 `파고들기` 아래 `Spring`을 누르면 `/categories/Spring/파고들기/`로 가고 글 2편이 나오며, 그 하위 항목만 강조된다. 부모인 `파고들기`는 강조되지 않는다.
- 좌측에서 `기본개념`을 누르면 `/groups/기본개념/`로 가고 "아직 글이 없습니다"가 나온다.
- 글 하단의 태그 배지에 `#파고들기`가 다른 태그와 함께 그대로 보인다.
- `/tags/파고들기/`가 열리고 3편이 나온다.

- [ ] **Step 6: 검색 인덱스에 영향이 없는지 확인한다**

Run: `npm run preview`

`npm run build` 직후여야 한다. `/search`에서 아무 단어나 검색해 결과가 나오는지 확인한다. 좌측 트리에는 `data-pagefind-ignore`가 붙어 있으므로 그룹 이름이 검색 결과 본문으로 잡히면 안 된다.

- [ ] **Step 7: 커밋**

```bash
git add src/pages/groups src/pages/categories
git commit -m "feat: 그룹 및 그룹×카테고리 목록 페이지 추가"
```

---

## Self-Review

**Spec coverage**

| 스펙 항목 | 태스크 |
|---|---|
| `GROUPS` 상수, 순서 고정 | Task 1 |
| `groupOf`, `buildGroupTree` | Task 1 |
| 하위 카테고리 정렬 규칙 | Task 1 (테스트 2건) |
| 그룹 태그 없는 글 제외 | Task 1 |
| 스키마 `.refine()` 검증 | Task 2 |
| 빌드 실패로 누락 차단 | Task 2 Step 3에서 실제로 실패를 확인 |
| 기존 3편 마이그레이션 | Task 2 Step 4 |
| `CLAUDE.md` 문서 | Task 2 Step 6 |
| `CategoryList` 2-depth 렌더 | Task 3 Step 1 |
| 강조 규칙 4종 | Task 3 (표 + Step 7 확인) |
| 접기·펼치기 없음 | Task 3 (구현하지 않음) |
| 좁은 화면 레이아웃 | Task 3 Step 1 미디어 쿼리 + Step 7 확인 |
| `ListLayout` props 변경 | Task 3 Step 2 |
| `/groups/<그룹>/` 라우트 | Task 4 Step 1 |
| `/categories/<카테고리>/<그룹>/` 라우트 | Task 4 Step 2 |
| 글 0개 그룹도 페이지 생성 | Task 4 Step 1 (`GROUPS` 전체 순회) |
| 빈 조합 페이지 생성 안 함 | Task 4 Step 2 + Step 4 확인 |
| `/categories/<카테고리>/` 유지 | Task 3 Step 4 (수정만, 삭제 안 함) |
| 그룹 태그를 `/tags/`에서 숨기지 않음 | 태그 코드를 어느 태스크도 건드리지 않음 + Task 4 Step 5 확인 |

빠진 항목 없음.

**Placeholder scan**

TBD·TODO 없음. 모든 코드 단계에 실제 코드 블록이 있고, 모든 실행 단계에 명령과 기대 결과가 있다.
Task 2 Step 4의 세 파일은 목표 `tags` 배열을 값 그대로 적었다.

`npm run dev` / `npm test` / `npm run build` / `npm run preview` 네 명령이 `package.json`에 모두 정의돼 있음을 확인했다.

**Type consistency**

- `GroupNode`는 Task 1에서 정의하고 Task 3의 `CategoryList`·`ListLayout`이 import 한다. 필드 이름 `group`/`count`/`categories`가 세 곳에서 일치한다.
- `current`는 Task 3의 표, `CategoryList` props, `ListLayout` props, Task 4의 두 페이지에서 모두 `{ group?: string; category?: string }`이다.
- `buildGroupTree`, `groupOf`, `GROUPS` 이름이 Task 1·2·3·4에서 동일하다.
- Task 3에서 `ListLayout`의 `categories` prop을 없애고, 같은 태스크 안에서 호출부 두 곳을 모두 고친다. 누락 없음.
