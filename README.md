# sGOM 기술 블로그

개발하며 겪은 문제와 공부한 개념을 남기는 블로그. Astro로 만든 정적 사이트를 GitHub Pages에 배포한다.

- 사이트: https://sgom.github.io
- 설계 문서: [`docs/superpowers/specs/2026-08-05-blog-design.md`](docs/superpowers/specs/2026-08-05-blog-design.md)
- 글 작성 규칙: [`CLAUDE.md`](CLAUDE.md)

## 기술 스택

| 항목 | 선택 |
|---|---|
| 정적 사이트 생성기 | Astro 7 |
| 콘텐츠 | Markdown + Content Collections (zod 스키마) |
| 검색 | Pagefind (빌드 산출물 인덱싱, 클라이언트 검색) |
| 코드 하이라이트 | Shiki (`github-light` / `github-dark`) |
| 테스트 | Vitest |
| 배포 | GitHub Actions → GitHub Pages |

Node 22.12 이상이 필요하다.

## 실행

```bash
npm install
npm run dev      # 개발 서버 (초안 포함해 렌더)
npm test         # 목록·태그·카테고리 로직 테스트
npm run build    # 프로덕션 빌드 + 검색 인덱스 생성
npm run preview  # 빌드 결과 확인 (검색은 여기서만 동작)
```

검색 인덱스는 `npm run build`가 만든다. 개발 서버에서는 `/search`가 동작하지 않으므로 `npm run preview`로 확인한다.

## 디렉터리 구조

```
src/
├── content/posts/<슬러그>/index.md   # 글. 이미지는 같은 디렉터리에 둔다
├── content.config.ts                 # frontmatter 스키마
├── layouts/                          # BaseLayout, ListLayout, PostLayout
├── components/                       # PostCard, CategoryList, TableOfContents, ThemeToggle
├── lib/posts.ts                      # 정렬·필터·태그·카테고리 집계 (순수 함수)
├── pages/
└── styles/global.css
templates/                            # 글 템플릿 3종
docs/superpowers/                     # 설계 스펙과 구현 계획
```

## 페이지

| 경로 | 내용 |
|---|---|
| `/` | 글 목록, 좌측 그룹-카테고리 2-depth 트리 |
| `/posts/<슬러그>/` | 본문, 우측 목차 |
| `/groups/<그룹>/` | 그룹별 목록 |
| `/categories/<카테고리>/` | 카테고리별 목록 |
| `/categories/<카테고리>/<그룹>/` | 카테고리 안에서 그룹으로 좁힌 목록 |
| `/tags/` `/tags/<태그>/` | 태그 목록과 태그별 목록 |
| `/search` | 검색 |
| `/about` | 소개 |
| `/rss.xml` | RSS |

## 글 쓰기

초안은 `src/content/posts/_drafts/<슬러그>/index.md`에 쓴다. 이 디렉터리는 gitignore 대상이라 검수 전 원고가 저장소에 들어가지 않는다. 승인되면 `src/content/posts/<슬러그>/`로 옮기고 `draft: true`를 지운다.

frontmatter 필수 필드는 `title`, `description`, `pubDate`, `category`, `tags`다. 누락되면 빌드가 실패한다. `tags`에는 `기본개념`, `파고들기`, `오답노트` 중 정확히 하나를 그룹 태그로 포함해야 하며, 없거나 둘 이상이면 빌드가 실패한다. 카테고리 목록은 별도 파일 없이 각 글의 `category` 값에서 계산되므로, 새 이름을 쓰면 그대로 새 카테고리가 생긴다.

템플릿은 세 가지다. 각 템플릿의 섹션은 필수와 선택으로 나뉘어 있고, 선택 섹션은 해당 없으면 지운다.

- [`templates/basics.md`](templates/basics.md) — 기본이 되는 개념을 표와 짧은 설명으로 정리하는 글
- [`templates/deep-dive.md`](templates/deep-dive.md) — 기본개념으로 간단히 설명하기 어렵거나 더 깊이 다루는 글
- [`templates/troubleshooting.md`](templates/troubleshooting.md) — 실제로 겪은 문제 상황의 파악과 해결 과정

말투 규칙, 검수 절차, 코드 수정 시 지켜야 할 제약은 [`CLAUDE.md`](CLAUDE.md)에 있다.

## 배포

`main`에 push하면 [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)이 빌드해 GitHub Pages에 올린다. 사용자 페이지 저장소라 루트에 배포되므로 `astro.config.mjs`에 `base`를 넣지 않는다.
