# GitHub 프로필 README 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub 프로필 README에 블로그와 최신 글 5개를 노출하고, 블로그 배포 시 그 목록이 자동으로 갱신되게 한다.

**Architecture:** RSS 파싱과 문자열 치환을 `src/lib/profile-readme.ts`의 순수 함수 3종으로 두고 Vitest로 검증한다. `scripts/update-profile-readme.ts`는 fetch와 파일 IO만 담당하는 얇은 껍데기다. 배포 워크플로에 `update-profile` job을 이어 붙여, 프로필 repo를 PAT로 체크아웃한 뒤 README의 마커 구간만 치환하고 push한다.

**Tech Stack:** TypeScript, Node 22 내장 fetch, Vitest, tsx, GitHub Actions

**설계 문서:** `docs/superpowers/specs/2026-08-09-profile-readme-design.md`

## Global Constraints

- 블로그 repo: `sGOM/sGom.github.io` / 프로필 repo: `sGOM/sGom` / 사이트: `https://sgom.github.io`
- 마커 문자열은 정확히 `<!-- BLOG-POST-LIST:START -->`, `<!-- BLOG-POST-LIST:END -->`
- 최신 글 노출 개수는 5개
- 이메일: `pooh6195@naver.com`
- 순수 함수는 `src/lib/`에 두고 `astro:content`를 import 하지 않는다
- 테스트는 `src/**/*.test.ts`만 수집된다 (`vitest.config.ts`)
- RSS 파싱에 외부 라이브러리를 추가하지 않는다
- `astro.config.mjs`의 `site`는 `https://sgom.github.io` (변경 금지)
- 작업 브랜치: `feat/profile-readme` (main에 직접 커밋하지 않는다)
- 커밋 메시지는 한국어, `feat:` / `chore:` / `docs:` 접두사를 쓴다

---

### Task 0: 작업 브랜치 생성

**Files:** 없음

- [ ] **Step 1: 브랜치를 만든다**

```bash
git checkout -b feat/profile-readme
```

- [ ] **Step 2: 스펙 문서를 커밋한다**

스펙 문서는 이미 작성되어 있다. 브랜치의 첫 커밋으로 올린다.

```bash
git add docs/superpowers/specs/2026-08-09-profile-readme-design.md docs/superpowers/plans/2026-08-09-profile-readme.md
git commit -m "docs: 프로필 README 설계와 구현 계획 추가"
```

---

### Task 1: 프로필 README 초안 작성

마커 형식을 여기서 확정한다. 이후 태스크의 렌더 결과가 이 마커 사이에 들어간다.

**Files:**
- Create: `C:\Users\pooh6\AppData\Local\Temp\claude\C--Users-pooh6-workspace-blog\ebb88a26-7f67-4955-8340-7813131e357f\scratchpad\profile-README.md`

**Interfaces:**
- Consumes: 없음
- Produces: 마커 문자열 `<!-- BLOG-POST-LIST:START -->` / `<!-- BLOG-POST-LIST:END -->` — Task 3의 `replaceMarkedSection`이 이 문자열을 찾는다

- [ ] **Step 1: README 초안 파일을 만든다**

scratchpad 디렉터리에 `profile-README.md`로 아래 내용을 그대로 쓴다.

```markdown
<div align="center">

# Heo SeokJin

[![Blog](https://img.shields.io/badge/Blog-222222.svg?&style=for-the-badge&logo=githubpages&logoColor=white)](https://sgom.github.io)
[![Email](https://img.shields.io/badge/pooh6195@naver.com-03C75A.svg?&style=for-the-badge&logo=naver&logoColor=white)](mailto:pooh6195@naver.com)

</div>

<div align="center">

## 📚 STACK

![Kotlin](https://img.shields.io/badge/Kotlin-7F52FF.svg?&style=for-the-badge&logo=Kotlin&logoColor=white)
![Java](https://img.shields.io/badge/Java-007396.svg?&style=for-the-badge&logo=Java&logoColor=white)
![Spring Boot](https://img.shields.io/badge/springboot-6DB33F.svg?&style=for-the-badge&logo=springboot&logoColor=white)

![Mybatis](https://img.shields.io/badge/Mybatis-005571.svg?&style=for-the-badge&logo=JPA&logoColor=white)
![Spring Data JPA](https://img.shields.io/badge/Spring%20Data%20JPA-6DB33F.svg?&style=for-the-badge&logo=Spring&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-4169E1.svg?&style=for-the-badge&logo=PostgreSQL&logoColor=white)
![MySQL](https://img.shields.io/badge/mysql-4479A1.svg?&style=for-the-badge&logo=mysql&logoColor=white)

![Git](https://img.shields.io/badge/git-F05032.svg?&style=for-the-badge&logo=git&logoColor=white)

</div>

## ✍️ 최신 글

<!-- BLOG-POST-LIST:START -->
- [트랜잭션과 ACID](https://sgom.github.io/posts/transaction-and-acid/) · 2026-08-05
<!-- BLOG-POST-LIST:END -->

<div align="right">

[**→ 글 전체 보기**](https://sgom.github.io)

</div>

## 📊 GitHub

<div align="center">

![Stats](https://github-readme-stats.vercel.app/api?username=sGOM&show_icons=true&hide_border=true&theme=github_dark&hide_title=true&include_all_commits=true)
![Top Langs](https://github-readme-stats.vercel.app/api/top-langs/?username=sGOM&layout=compact&hide_border=true&theme=github_dark&langs_count=6)

</div>
```

- [ ] **Step 2: 마커 사이 내용이 워크플로에 의해 덮어써지는지 확인한다**

마커 사이의 한 줄은 자리표시용 예시다. Task 3의 `replaceMarkedSection`이 이 구간을 통째로 갈아끼운다. 마커 자체는 남는다.

- [ ] **Step 3: 사용자에게 초안을 보여주고 확인받는다**

파일 경로를 알리고, 배지 색·통계 카드 테마·섹션 순서에 대해 의견을 받는다. **여기서 멈춘다.** 사용자가 수정을 요청하면 반영한다.

- [ ] **Step 4: 커밋 없음**

scratchpad 파일은 blog repo 밖이므로 커밋하지 않는다.

---

### Task 2: RSS 파싱 함수

**Files:**
- Create: `src/lib/profile-readme.ts`
- Test: `src/lib/profile-readme.test.ts`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `export type RssItem = { title: string; link: string; pubDate: Date }`
  - `export function parseRssItems(xml: string, limit: number): RssItem[]`

`@astrojs/rss`가 만드는 RSS는 각 항목이 아래 형태다. `title`은 CDATA로 감싸이고 `link`와 `pubDate`는 평문이다.

```xml
<item><title><![CDATA[트랜잭션과 ACID]]></title><link>https://sgom.github.io/posts/transaction-and-acid/</link><guid isPermaLink="true">https://sgom.github.io/posts/transaction-and-acid/</guid><description><![CDATA[설명]]></description><pubDate>Wed, 05 Aug 2026 00:00:00 GMT</pubDate></item>
```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`src/lib/profile-readme.test.ts`를 만든다.

```ts
import { describe, it, expect } from 'vitest';
import { parseRssItems } from './profile-readme';

function item(title: string, slug: string, pubDate: string): string {
  return (
    `<item><title>${title}</title>` +
    `<link>https://sgom.github.io/posts/${slug}/</link>` +
    `<guid isPermaLink="true">https://sgom.github.io/posts/${slug}/</guid>` +
    `<description><![CDATA[설명]]></description>` +
    `<pubDate>${pubDate}</pubDate></item>`
  );
}

function feed(items: string[]): string {
  return (
    `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>` +
    `<title><![CDATA[sGOM]]></title><link>https://sgom.github.io/</link>` +
    items.join('') +
    `</channel></rss>`
  );
}

describe('parseRssItems', () => {
  it('CDATA로 감싼 제목을 벗겨낸다', () => {
    const xml = feed([
      item('<![CDATA[트랜잭션과 ACID]]>', 'transaction-and-acid', 'Wed, 05 Aug 2026 00:00:00 GMT'),
    ]);

    const result = parseRssItems(xml, 5);

    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('트랜잭션과 ACID');
    expect(result[0].link).toBe('https://sgom.github.io/posts/transaction-and-acid/');
    expect(result[0].pubDate.toISOString().slice(0, 10)).toBe('2026-08-05');
  });

  it('CDATA 없는 평문 제목도 읽는다', () => {
    const xml = feed([item('평문 제목', 'plain', 'Wed, 05 Aug 2026 00:00:00 GMT')]);

    expect(parseRssItems(xml, 5)[0].title).toBe('평문 제목');
  });

  it('HTML 엔티티를 디코드한다', () => {
    const xml = feed([
      item('<![CDATA[A &amp; B &lt;태그&gt; &quot;인용&quot; &#39;작은따옴표&#39;]]>', 'ent', 'Wed, 05 Aug 2026 00:00:00 GMT'),
    ]);

    expect(parseRssItems(xml, 5)[0].title).toBe(`A & B <태그> "인용" '작은따옴표'`);
  });

  it('limit만큼만 반환한다', () => {
    const xml = feed([
      item('1', 'a', 'Wed, 05 Aug 2026 00:00:00 GMT'),
      item('2', 'b', 'Tue, 04 Aug 2026 00:00:00 GMT'),
      item('3', 'c', 'Mon, 03 Aug 2026 00:00:00 GMT'),
    ]);

    expect(parseRssItems(xml, 2).map((i) => i.title)).toEqual(['1', '2']);
  });

  it('글이 limit보다 적으면 있는 만큼 반환한다', () => {
    const xml = feed([item('1', 'a', 'Wed, 05 Aug 2026 00:00:00 GMT')]);

    expect(parseRssItems(xml, 5)).toHaveLength(1);
  });

  it('item이 없으면 빈 배열을 반환한다', () => {
    expect(parseRssItems(feed([]), 5)).toEqual([]);
  });

  it('필수 필드가 빠진 item은 건너뛴다', () => {
    const broken = `<item><title><![CDATA[제목만]]></title></item>`;
    const xml = feed([broken, item('정상', 'ok', 'Wed, 05 Aug 2026 00:00:00 GMT')]);

    expect(parseRssItems(xml, 5).map((i) => i.title)).toEqual(['정상']);
  });
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `Failed to resolve import "./profile-readme"`

- [ ] **Step 3: 최소 구현을 쓴다**

`src/lib/profile-readme.ts`를 만든다.

```ts
export type RssItem = {
  title: string;
  link: string;
  pubDate: Date;
};

function decodeEntities(text: string): string {
  return text
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0*39;|&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function extractTag(block: string, tag: string): string {
  const matched = new RegExp(
    `<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`
  ).exec(block);
  if (!matched) return '';

  const raw = matched[1].trim();
  const cdata = /^<!\[CDATA\[([\s\S]*?)\]\]>$/.exec(raw);
  return decodeEntities((cdata ? cdata[1] : raw).trim());
}

export function parseRssItems(xml: string, limit: number): RssItem[] {
  const items: RssItem[] = [];
  const itemPattern = /<item>([\s\S]*?)<\/item>/g;

  let matched: RegExpExecArray | null;
  while ((matched = itemPattern.exec(xml)) !== null) {
    if (items.length >= limit) break;

    const block = matched[1];
    const title = extractTag(block, 'title');
    const link = extractTag(block, 'link');
    const pubDate = extractTag(block, 'pubDate');
    if (!title || !link || !pubDate) continue;

    const parsed = new Date(pubDate);
    if (Number.isNaN(parsed.valueOf())) continue;

    items.push({ title, link, pubDate: parsed });
  }

  return items;
}
```

`&amp;`를 마지막에 치환하는 것이 중요하다. 먼저 치환하면 `&amp;lt;`가 `<`로 잘못 풀린다.

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — `parseRssItems` 7개 통과, 기존 `posts.test.ts`도 통과

- [ ] **Step 5: 커밋한다**

```bash
git add src/lib/profile-readme.ts src/lib/profile-readme.test.ts
git commit -m "feat: RSS 항목 파싱 함수 추가"
```

---

### Task 3: 목록 렌더와 마커 치환 함수

**Files:**
- Modify: `src/lib/profile-readme.ts`
- Test: `src/lib/profile-readme.test.ts`

**Interfaces:**
- Consumes: `RssItem` (Task 2)
- Produces:
  - `export function renderPostList(items: RssItem[]): string`
  - `export function replaceMarkedSection(readme: string, block: string): string`
  - `export const LIST_START = '<!-- BLOG-POST-LIST:START -->'`
  - `export const LIST_END = '<!-- BLOG-POST-LIST:END -->'`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`src/lib/profile-readme.test.ts` 하단에 아래를 덧붙인다. 최상단 import 문을 아래로 교체한다 — `RssItem`은 타입이므로 `type` 키워드가 붙는다.

```ts
import {
  parseRssItems,
  renderPostList,
  replaceMarkedSection,
  LIST_START,
  LIST_END,
  type RssItem,
} from './profile-readme';
```

```ts
describe('renderPostList', () => {
  const item = (title: string, slug: string, date: string): RssItem => ({
    title,
    link: `https://sgom.github.io/posts/${slug}/`,
    pubDate: new Date(date),
  });

  it('제목·링크·날짜를 마크다운 목록으로 만든다', () => {
    const result = renderPostList([
      item('트랜잭션과 ACID', 'transaction-and-acid', '2026-08-05T00:00:00Z'),
      item('격리 수준', 'isolation-levels', '2026-08-04T00:00:00Z'),
    ]);

    expect(result).toBe(
      '- [트랜잭션과 ACID](https://sgom.github.io/posts/transaction-and-acid/) · 2026-08-05\n' +
        '- [격리 수준](https://sgom.github.io/posts/isolation-levels/) · 2026-08-04'
    );
  });

  it('제목의 대괄호를 이스케이프해 링크 문법을 지킨다', () => {
    const result = renderPostList([item('MySQL [8.0] 이야기', 'mysql', '2026-08-05T00:00:00Z')]);

    expect(result).toContain('[MySQL \\[8.0\\] 이야기]');
  });

  it('글이 없으면 안내 문구를 낸다', () => {
    expect(renderPostList([])).toBe('_아직 발행한 글이 없다._');
  });

  it('시간대와 무관하게 UTC 기준 날짜를 쓴다', () => {
    const result = renderPostList([item('글', 'a', '2026-08-05T00:00:00Z')]);

    expect(result).toContain('· 2026-08-05');
  });
});

describe('replaceMarkedSection', () => {
  const readme = (inner: string) =>
    `# 제목\n\n## 최신 글\n\n${LIST_START}\n${inner}\n${LIST_END}\n\n## 그 다음\n`;

  it('마커 사이를 새 블록으로 갈아끼운다', () => {
    const result = replaceMarkedSection(readme('- 예전 글'), '- 새 글');

    expect(result).toBe(readme('- 새 글'));
  });

  it('마커 밖의 내용은 건드리지 않는다', () => {
    const result = replaceMarkedSection(readme('- 예전 글'), '- 새 글');

    expect(result).toContain('# 제목');
    expect(result).toContain('## 그 다음');
  });

  it('마커 사이가 비어 있어도 삽입한다', () => {
    const source = `${LIST_START}\n${LIST_END}`;

    expect(replaceMarkedSection(source, '- 새 글')).toBe(
      `${LIST_START}\n- 새 글\n${LIST_END}`
    );
  });

  it('시작 마커가 없으면 예외를 던진다', () => {
    expect(() => replaceMarkedSection(`# 제목\n${LIST_END}`, '- 글')).toThrow(
      /마커/
    );
  });

  it('끝 마커가 없으면 예외를 던진다', () => {
    expect(() => replaceMarkedSection(`# 제목\n${LIST_START}`, '- 글')).toThrow(
      /마커/
    );
  });

  it('마커 순서가 뒤집혀 있으면 예외를 던진다', () => {
    expect(() =>
      replaceMarkedSection(`${LIST_END}\n${LIST_START}`, '- 글')
    ).toThrow(/마커/);
  });
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `npm test`
Expected: FAIL — `renderPostList is not a function` 또는 import 해결 실패

- [ ] **Step 3: 최소 구현을 쓴다**

`src/lib/profile-readme.ts`에 아래를 덧붙인다.

```ts
export const LIST_START = '<!-- BLOG-POST-LIST:START -->';
export const LIST_END = '<!-- BLOG-POST-LIST:END -->';

const EMPTY_MESSAGE = '_아직 발행한 글이 없다._';

function escapeLinkText(title: string): string {
  return title.replace(/([[\]])/g, '\\$1');
}

function formatDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function renderPostList(items: RssItem[]): string {
  if (items.length === 0) return EMPTY_MESSAGE;

  return items
    .map(
      (item) =>
        `- [${escapeLinkText(item.title)}](${item.link}) · ${formatDate(item.pubDate)}`
    )
    .join('\n');
}

export function replaceMarkedSection(readme: string, block: string): string {
  const start = readme.indexOf(LIST_START);
  const end = readme.indexOf(LIST_END);
  if (start === -1 || end === -1 || end < start) {
    throw new Error(
      `README에서 ${LIST_START} / ${LIST_END} 마커를 찾지 못했다`
    );
  }

  return (
    readme.slice(0, start + LIST_START.length) +
    '\n' +
    block +
    '\n' +
    readme.slice(end)
  );
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `npm test`
Expected: PASS — 전체 통과

- [ ] **Step 5: 커밋한다**

```bash
git add src/lib/profile-readme.ts src/lib/profile-readme.test.ts
git commit -m "feat: 최신 글 목록 렌더와 마커 치환 함수 추가"
```

---

### Task 4: 갱신 스크립트

**Files:**
- Create: `scripts/update-profile-readme.ts`
- Modify: `package.json` (devDependencies에 `tsx` 추가)

**Interfaces:**
- Consumes: `parseRssItems`, `renderPostList`, `replaceMarkedSection` (Task 2, 3)
- Produces: CLI `npx tsx scripts/update-profile-readme.ts <README 경로>` — Task 5의 워크플로가 호출한다

- [ ] **Step 1: tsx를 설치한다**

```bash
npm install -D tsx
```

- [ ] **Step 2: 스크립트를 쓴다**

`scripts/update-profile-readme.ts`를 만든다.

```ts
import { readFile, writeFile } from 'node:fs/promises';
import {
  parseRssItems,
  renderPostList,
  replaceMarkedSection,
} from '../src/lib/profile-readme.js';

const RSS_URL = 'https://sgom.github.io/rss.xml';
const POST_LIMIT = 5;

const readmePath = process.argv[2];
if (!readmePath) {
  console.error('사용법: tsx scripts/update-profile-readme.ts <README 경로>');
  process.exit(1);
}

const response = await fetch(RSS_URL);
if (!response.ok) {
  throw new Error(`RSS를 가져오지 못했다: ${response.status} ${response.statusText}`);
}

const items = parseRssItems(await response.text(), POST_LIMIT);
const readme = await readFile(readmePath, 'utf8');
const updated = replaceMarkedSection(readme, renderPostList(items));

if (updated === readme) {
  console.log('변경 없음');
  process.exit(0);
}

await writeFile(readmePath, updated);
console.log(`README를 갱신했다 (글 ${items.length}개)`);
```

`../src/lib/profile-readme.js`로 import하는 것이 맞다. TypeScript의 ESM 규약이며 tsx가 `.ts`로 되돌려 해석한다.

- [ ] **Step 3: 로컬에서 실제로 돌려본다**

scratchpad의 README 초안을 대상으로 실행한다. 이 단계는 실제 네트워크를 쓴다.

```bash
cp "C:/Users/pooh6/AppData/Local/Temp/claude/C--Users-pooh6-workspace-blog/ebb88a26-7f67-4955-8340-7813131e357f/scratchpad/profile-README.md" "C:/Users/pooh6/AppData/Local/Temp/claude/C--Users-pooh6-workspace-blog/ebb88a26-7f67-4955-8340-7813131e357f/scratchpad/test-README.md"
npx tsx scripts/update-profile-readme.ts "C:/Users/pooh6/AppData/Local/Temp/claude/C--Users-pooh6-workspace-blog/ebb88a26-7f67-4955-8340-7813131e357f/scratchpad/test-README.md"
```

Expected: `README를 갱신했다 (글 5개)` 출력. `test-README.md`의 마커 사이에 실제 글 5개가 들어가 있고, 제목·링크·날짜가 `https://sgom.github.io/rss.xml`의 내용과 일치한다.

파일을 열어 링크 5개를 눈으로 대조한다. 하나라도 어긋나면 Task 2로 돌아간다.

- [ ] **Step 4: 잘못된 경로를 줬을 때 실패하는지 확인한다**

```bash
npx tsx scripts/update-profile-readme.ts "C:/nonexistent/README.md"
```

Expected: 0이 아닌 종료 코드와 ENOENT 오류. 조용히 성공하면 안 된다.

- [ ] **Step 5: 테스트와 빌드가 여전히 통과하는지 확인한다**

Run: `npm test && npm run build`
Expected: 둘 다 PASS. `scripts/`가 `tsconfig.json`의 `include`(`**/*`)에 들어가므로 타입 오류가 나면 여기서 드러난다.

- [ ] **Step 6: 커밋한다**

```bash
git add scripts/update-profile-readme.ts package.json package-lock.json
git commit -m "feat: 프로필 README 갱신 스크립트 추가"
```

---

### Task 5: 배포 워크플로에 갱신 job 추가

**Files:**
- Modify: `.github/workflows/deploy.yml`

**Interfaces:**
- Consumes: `npx tsx scripts/update-profile-readme.ts <경로>` (Task 4)
- Produces: 없음 (최종 태스크)

- [ ] **Step 1: job을 추가한다**

`.github/workflows/deploy.yml` 끝에 아래를 덧붙인다. 기존 `build`, `deploy` job은 건드리지 않는다.

```yaml
  update-profile:
    needs: deploy
    runs-on: ubuntu-latest
    steps:
      - name: Checkout blog
        uses: actions/checkout@v7
        with:
          path: blog
      - name: Checkout profile
        uses: actions/checkout@v7
        with:
          repository: sGOM/sGom
          path: profile
          token: ${{ secrets.PROFILE_TOKEN }}
      - name: Setup Node
        uses: actions/setup-node@v6
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: blog/package-lock.json
      - name: Install dependencies
        working-directory: blog
        run: npm ci
      - name: Update profile README
        working-directory: blog
        run: npx tsx scripts/update-profile-readme.ts ../profile/README.md
      - name: Commit and push
        working-directory: profile
        run: |
          if git diff --quiet; then
            echo "변경 없음"
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add README.md
          git commit -m "chore: 최신 글 목록 갱신"
          git push
```

최상위 `permissions`는 그대로 둔다. 프로필 repo 쓰기는 `GITHUB_TOKEN`이 아니라 `PROFILE_TOKEN`이 담당한다.

- [ ] **Step 2: YAML이 유효한지 확인한다**

```bash
npx --yes js-yaml .github/workflows/deploy.yml > /dev/null && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: 사용자에게 PAT 발급을 안내한다**

**여기서 멈춘다.** 아래를 사용자에게 그대로 전달하고 완료를 기다린다. 이 secret 없이는 job이 실패한다.

1. https://github.com/settings/personal-access-tokens/new 접속
2. Token name: `blog-to-profile`, Expiration: 원하는 기간
3. Repository access → Only select repositories → `sGOM/sGom` 선택
4. Permissions → Repository permissions → **Contents: Read and write**
5. Generate token 후 값 복사
6. https://github.com/sGOM/sGom.github.io/settings/secrets/actions/new 에서 Name `PROFILE_TOKEN`, Secret에 붙여넣고 저장

- [ ] **Step 4: 사용자에게 README 초안 반영을 안내한다**

Task 1의 `profile-README.md` 내용을 `sGOM/sGom`의 `README.md`에 붙여넣고 커밋하도록 안내한다. 마커 두 줄이 반드시 포함되어야 한다.

- [ ] **Step 5: 커밋한다**

```bash
git add .github/workflows/deploy.yml
git commit -m "feat: 배포 후 프로필 README 갱신 job 추가"
```

- [ ] **Step 6: PR을 올린다**

```bash
git push -u origin feat/profile-readme
gh pr create --title "프로필 README 블로그 노출과 자동 갱신" --body "$(cat <<'EOF'
## 요약

GitHub 프로필 README에 블로그와 최신 글 5개를 노출하고, 블로그 배포 시 목록이 자동 갱신되게 한다.

- `src/lib/profile-readme.ts` — RSS 파싱, 목록 렌더, 마커 치환 순수 함수
- `scripts/update-profile-readme.ts` — fetch와 파일 IO
- `.github/workflows/deploy.yml` — `update-profile` job 추가

## 사전 준비

`PROFILE_TOKEN` secret(fine-grained PAT, `sGOM/sGom` Contents: write)이 등록되어 있어야 한다.

## 테스트

- `npm test` — 파싱/렌더/치환 17개 케이스
- 로컬에서 실제 RSS로 스크립트 실행해 결과 대조

설계 문서: `docs/superpowers/specs/2026-08-09-profile-readme-design.md`
EOF
)"
```

- [ ] **Step 7: merge 후 실제 동작을 확인한다**

merge하면 배포 워크플로가 돌면서 `update-profile`까지 실행된다. Actions 로그에서 job이 성공했는지, `sGOM/sGom`에 `chore: 최신 글 목록 갱신` 커밋이 생겼는지, 프로필 페이지의 최신 글 목록이 실제 블로그와 일치하는지 확인한다.

---

## 검증 요약

| 태스크 | 검증 방법 |
|---|---|
| 1 | 사용자가 README 초안을 읽고 승인 |
| 2 | `npm test` — 파싱 7개 케이스 |
| 3 | `npm test` — 렌더 4개 + 치환 6개 케이스 |
| 4 | 실제 RSS로 스크립트 실행 후 결과 대조, `npm run build` |
| 5 | YAML 파싱, merge 후 Actions 로그와 프로필 repo 커밋 확인 |
