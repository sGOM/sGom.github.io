# 기술 블로그

개발하며 겪은 문제와 공부한 개념을 남기는 블로그. Astro로 만들어 GitHub Pages(`sgom.github.io`)에 배포한다.

설계 배경: `docs/superpowers/specs/2026-08-05-blog-design.md`

## 글을 쓸 때

**초안을 바로 발행 위치에 쓰지 않는다.** 원고는 `src/content/posts/_drafts/<슬러그>/index.md`에 먼저 쓴다.
이 디렉터리는 gitignore 대상이라 검수 전 원고가 저장소에 들어가지 않는다.
검수와 승인 절차는 아래 6절에 있다.

### 1. 템플릿 고르기

- **답을 모르는 상태에서 시작해 알아낸 글** → `templates/troubleshooting.md`
- **이미 답을 알고 정리하는 글** → `templates/concept.md`

애매하면 물어본다. 임의로 정하지 않는다.

### 2. 파일 위치

| 단계 | 위치 |
|---|---|
| 초안 (검수 전) | `src/content/posts/_drafts/<슬러그>/index.md` |
| 발행 (승인 후) | `src/content/posts/<슬러그>/index.md` |

이미지는 같은 디렉터리에 두고 `![설명](./이미지.png)`로 참조한다. 승인 시 디렉터리째 옮기므로 상대 경로가 그대로 유지된다.
슬러그는 영문 소문자와 하이픈만 쓴다. 발행 후 URL이 `/posts/<슬러그>/`가 된다.

### 3. frontmatter

| 필드 | 필수 | 비고 |
|---|---|---|
| `title` | O | |
| `description` | O | 목록과 검색 결과에 노출된다 |
| `pubDate` | O | `2026-08-05` 형식 |
| `category` | O | 글 하나에 하나만. 홈 좌측 목록을 만든다 |
| `tags` | O | 최소 1개. 그룹 태그를 정확히 하나 포함해야 한다 |
| `updatedDate` | X | |
| `draft` | X | `true`면 개발 서버에서만 보인다 |

글의 성격은 `tags`에 넣는 **그룹 태그**로 정한다. 홈 좌측 목록의 1-depth가 되며, 셋 중
정확히 하나를 반드시 넣어야 한다. 없거나 둘 이상이면 `npm run build`가 실패한다.

| 그룹 태그 | 담는 글 |
|---|---|
| `기본개념` | 기본이 되는 개념을 표와 짧은 설명·예시로 정리한 글 |
| `파고들기` | 기본개념으로 간단히 설명하기 어렵거나, 더 깊고 자세하게 다룬 글 |
| `오답노트` | 실제로 맞닥뜨린 문제 상황을 파악하고 해결한 과정을 설명한 글 |

카테고리는 큰 분류, 태그는 세부 주제다. 카테고리 목록은 별도 파일 없이 글의 `category` 값에서
계산되므로, 새 이름을 쓰면 그대로 새 카테고리가 생긴다. 오타가 곧 새 카테고리가 되니 기존 값을
먼저 확인한다.

```bash
grep -h "^category:" src/content/posts/*/index.md | sort -u
```

그룹별 글 수는 다음으로 센다.

```bash
grep -h "^tags:" src/content/posts/*/index.md | grep -o "기본개념\|파고들기\|오답노트" | sort | uniq -c
```

### 4. 말투

- **평서체(`~다`)로 고정.** 문단 안에서 `~인데`, `~지만` 정도의 변주는 허용한다.
- **문장을 압축한다.** 설명조의 군살과 만연체를 걷어내고, 같은 정보를 더 적은 글자로 전달한다.
- **감탄사와 과장을 쓰지 않는다.** (`대박`, `무려`, `충격적이게도`)
- **결론을 뒤로 미루지 않는다.** 문단 첫 문장에 요지를 놓는다.
- **추측과 사실을 표기로 구분한다.** (`~로 보인다` vs `~였다`)
- **1인칭은 생략한다.** 평서체에서 "저"는 어울리지 않는다.

이 규칙은 글 본문에만 적용한다. 코드 주석과 UI 문구에는 적용하지 않는다.

### 5. 발행 전 확인

```bash
npm run dev     # 렌더 확인
npm test        # 목록/태그/카테고리 로직
npm run build   # 스키마 검증 + 검색 인덱스
```

### 6. 검수와 승인

**승인 없이 초안을 발행 위치로 옮기지 않는다. 커밋도 하지 않는다.**

1. `src/content/posts/_drafts/<슬러그>/index.md`에 원고를 쓴다. frontmatter에 `draft: true`를 넣는다.
   초안도 스키마 검증 대상이므로 그룹 태그를 처음부터 넣어야 `npm run build`가 통과한다.
2. `npm run dev`를 띄우고 사용자에게 주소를 알린다. 개발 서버는 초안을 렌더하지만 `npm run build`는 제외한다.
3. 사용자가 읽고 판단한다. **여기서 멈춘다.**
4. 승인되면 디렉터리를 옮기고 `draft: true`를 지운 뒤, 위 3개 명령을 돌리고 커밋한다.

```bash
mv src/content/posts/_drafts/<슬러그> src/content/posts/<슬러그>
```

인용한 코드나 실행 결과가 있으면 원본과 대조해 확인한 뒤 검수를 요청한다.
사실 확인은 쓰는 쪽의 몫이다. 사용자에게 확인을 떠넘기지 않는다.

`main`에 push하면 GitHub Actions가 배포한다.

## 코드를 고칠 때

- 목록·태그·카테고리 계산은 `src/lib/posts.ts`에 순수 함수로 둔다. `astro:content`를 import 하지 않는다. 그래야 Vitest로 테스트할 수 있다.
- 로직을 추가하면 `src/lib/posts.test.ts`에 테스트를 먼저 쓴다.
- `astro.config.mjs`에 `base`를 넣지 않는다. 사용자 페이지 repo라 루트에 배포된다.
- 검색 인덱스는 `npm run build`가 만든다. `npm run dev`에서는 검색이 동작하지 않는다. `npm run preview`로 확인한다.
- Pagefind가 인덱싱할 범위는 `PostLayout.astro`의 `data-pagefind-body`가 정한다. 본문 외 요소에는 `data-pagefind-ignore`를 붙인다.

## 현재 범위 밖

댓글(giscus), 조회수, 커스텀 도메인은 넣지 않았다. 필요해지면 그때 추가한다.
