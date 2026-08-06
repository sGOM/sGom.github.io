# 기술 블로그

개발하며 겪은 문제와 공부한 개념을 남기는 블로그. Astro로 만들어 GitHub Pages(`sgom.github.io`)에 배포한다.

설계 배경: `docs/superpowers/specs/2026-08-05-blog-design.md`

## 글을 쓸 때

### 1. 템플릿 고르기

- **답을 모르는 상태에서 시작해 알아낸 글** → `templates/troubleshooting.md`
- **이미 답을 알고 정리하는 글** → `templates/concept.md`

애매하면 물어본다. 임의로 정하지 않는다.

### 2. 파일 위치

`src/content/posts/<영문-슬러그>/index.md`

이미지는 같은 디렉터리에 두고 `![설명](./이미지.png)`로 참조한다.
슬러그는 영문 소문자와 하이픈만 쓴다. URL이 `/posts/<슬러그>/`가 된다.

### 3. frontmatter

| 필드 | 필수 | 비고 |
|---|---|---|
| `title` | O | |
| `description` | O | 목록과 검색 결과에 노출된다 |
| `pubDate` | O | `2026-08-05` 형식 |
| `tags` | O | 최소 1개 |
| `updatedDate` | X | |
| `draft` | X | `true`면 개발 서버에서만 보인다 |
| `series` | X | `seriesOrder`와 반드시 함께 |
| `seriesOrder` | X | `series`와 반드시 함께. 1부터 |

`series`만 쓰고 `seriesOrder`를 빠뜨리면 빌드가 실패한다.

### 4. 말투

- **정중체(`~습니다`)로 고정.** 문단 안에서 `~죠`, `~고요` 정도의 변주는 허용한다.
- **감탄사와 과장을 쓰지 않는다.** (`대박`, `무려`, `충격적이게도`)
- **결론을 뒤로 미루지 않는다.** 문단 첫 문장에 요지를 놓는다.
- **추측과 사실을 표기로 구분한다.** (`~로 보입니다` vs `~였습니다`)
- **1인칭은 생략을 우선한다.** 필요할 때만 "저"를 쓴다.

이 규칙은 글 본문에만 적용한다. 코드 주석과 UI 문구에는 적용하지 않는다.

### 5. 발행 전 확인

```bash
npm run dev     # 렌더 확인
npm test        # 목록/태그/시리즈 로직
npm run build   # 스키마 검증 + 검색 인덱스
```

`main`에 push하면 GitHub Actions가 배포한다.

## 코드를 고칠 때

- 목록·태그·시리즈 계산은 `src/lib/posts.ts`에 순수 함수로 둔다. `astro:content`를 import 하지 않는다. 그래야 Vitest로 테스트할 수 있다.
- 로직을 추가하면 `src/lib/posts.test.ts`에 테스트를 먼저 쓴다.
- `astro.config.mjs`에 `base`를 넣지 않는다. 사용자 페이지 repo라 루트에 배포된다.
- 검색 인덱스는 `npm run build`가 만든다. `npm run dev`에서는 검색이 동작하지 않는다. `npm run preview`로 확인한다.
- Pagefind가 인덱싱할 범위는 `PostLayout.astro`의 `data-pagefind-body`가 정한다. 본문 외 요소에는 `data-pagefind-ignore`를 붙인다.

## 현재 범위 밖

댓글(giscus), 조회수, 커스텀 도메인은 넣지 않았다. 필요해지면 그때 추가한다.
