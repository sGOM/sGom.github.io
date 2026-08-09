# GitHub 프로필 README 설계

작성일: 2026-08-09

## 목적

GitHub 프로필 README(`sGOM/sGom`)에 블로그를 노출한다. 프로필을 연 사람이 블로그의 존재와
최근에 무엇을 쓰고 있는지를 스크롤 없이 파악하게 만드는 것이 목표다.

최신 글 목록은 손으로 관리하지 않는다. 글을 쓸 때마다 두 곳을 고쳐야 하면 결국 한쪽이 낡는다.
블로그를 배포하면 프로필도 따라 갱신되도록 자동화한다.

## 산출물

| 산출물 | 위치 | 관리 주체 |
|---|---|---|
| 프로필 README 초안 | scratchpad `profile-README.md` | 사용자가 `sGOM/sGom`에 붙여넣는다 |
| 순수 함수 3종 + 테스트 | `src/lib/profile-readme.ts`, `.test.ts` | blog repo |
| 갱신 스크립트 | `scripts/update-profile-readme.ts` | blog repo |
| 갱신 job | `.github/workflows/deploy.yml` | blog repo |

프로필 repo는 로컬에 클론하지 않는다. README는 초안 파일로 전달하고, 이후 갱신은 워크플로가
원격에서 직접 수행한다.

## README 구조

```
<div align="center">
  <h1>Heo SeokJin</h1>
  [Blog 배지] [Email 배지]
</div>

## 📚 STACK
(기존 배지 3줄 유지)

## ✍️ 최신 글
<!-- BLOG-POST-LIST:START -->
- [제목](https://sgom.github.io/posts/<슬러그>/) · 2026-08-09
  ... 최대 5개
<!-- BLOG-POST-LIST:END -->
→ 글 전체 보기

## 📊 GitHub
[stats 카드] [top langs 카드]
```

### 결정 사항

- **자기소개 문구를 넣지 않는다.** 이름 헤더와 배지만 둔다. 문구는 낡기 쉽고 관리 대상이 늘어난다.
- **배지 스타일은 `for-the-badge`로 통일한다.** 기존 STACK 배지와 시각적으로 어긋나지 않게 한다.
  - Blog → `https://sgom.github.io`
  - Email → `pooh6195@naver.com`
- **기존 STACK 배지는 그대로 유지한다.** 손댈 이유가 없다.
- **통계 카드는 `github-readme-stats` 2장**(stats, top-langs)만 쓴다. 테마는 고정값으로 둔다.
  외부 서비스이므로 가동률에 의존하는 것을 감수한다. 실패해도 이미지 하나가 깨질 뿐이다.

## 자동 갱신

### 흐름

기존 배포 워크플로에 job 하나를 잇는다.

```
build → deploy → update-profile
```

`update-profile`이 하는 일은 다음과 같다.

1. `https://sgom.github.io/rss.xml`을 fetch한다. `deploy` 이후이므로 최신 상태다.
2. 최신 5개의 `title`, `link`, `pubDate`를 뽑는다.
3. `actions/checkout`으로 `sGOM/sGom`을 `PROFILE_TOKEN`으로 체크아웃한다.
4. README의 `BLOG-POST-LIST` 마커 사이를 치환한다.
5. 변경이 있을 때만 커밋하고 push한다.

### 대안 검토

| 안 | 내용 | 판단 |
|---|---|---|
| A | 프로필 repo에 cron 워크플로 | 즉시성이 없다. 글을 써도 최대 하루 뒤에 반영된다 |
| B | 외부 액션(`blog-post-workflow`) | 출력 형식 통제가 제한적이고 제3자 액션을 신뢰해야 한다 |
| C | 블로그 배포 시 push | **채택.** 배포 즉시 반영되고 출력 형식을 완전히 통제한다 |

C의 비용은 cross-repo push용 PAT 발급과 관리다. 갱신 지연이 없다는 이점이 이를 상회한다고 봤다.

### 필요한 준비물

fine-grained PAT를 발급해 blog repo의 Actions secret `PROFILE_TOKEN`으로 등록한다.

- Repository access: `sGOM/sGom`만 선택
- Permissions: Contents → Read and write

이 발급은 사용자가 직접 해야 한다. 구현 시 절차를 안내한다.

## 코드 구조

`src/lib/`의 기존 규칙을 따른다. 로직은 순수 함수로 두고 IO는 스크립트가 담당한다.

### `src/lib/profile-readme.ts`

| 함수 | 입력 | 출력 |
|---|---|---|
| `parseRssItems(xml, limit)` | RSS 문자열 | `{ title, link, pubDate }[]` |
| `renderPostList(items)` | 아이템 배열 | 마크다운 목록 문자열 |
| `replaceMarkedSection(readme, block)` | README 전문, 삽입할 블록 | 치환된 README 전문 |

RSS 파싱에 외부 라이브러리를 넣지 않는다. 입력이 `@astrojs/rss`가 생성하는 형식으로 고정되어
있으므로 정규식으로 충분하다. 임의의 XML을 다룰 일이 생기면 그때 바꾼다.

`@astrojs/rss`는 `title`을 CDATA로 감싼다. 파싱은 CDATA와 평문을 모두 처리하고, HTML 엔티티
(`&amp;` 등)를 디코드한다. 제목에 마크다운 링크 문법을 깨는 문자(`[`, `]`)가 있으면 이스케이프한다.

### `src/lib/profile-readme.test.ts`

테스트를 먼저 쓴다. 다루는 경계는 다음과 같다.

- CDATA로 감싼 제목과 평문 제목
- HTML 엔티티가 들어간 제목
- 글이 `limit`보다 적을 때
- 아이템이 0개일 때 (빈 목록 대신 안내 문구를 낸다)
- README에 마커가 없을 때 (예외를 던진다)
- 마커 사이에 기존 내용이 있을 때와 비어 있을 때

### `scripts/update-profile-readme.ts`

fetch, 파일 읽기/쓰기만 한다. Node 22 내장 `fetch`를 쓴다.

`src/lib/`의 순수 함수는 `.ts`로 두므로 스크립트도 `.ts`로 통일하고, 실행은 `tsx`로 한다.
`tsx`를 devDependency에 추가하고 워크플로에서 `npx tsx scripts/update-profile-readme.ts`로
호출한다. Node의 실험적 타입 스트리핑 플래그에 의존하지 않고, 순수 함수를 `.js`로 내리지도
않는다. 의존성 하나를 더 받는 대신 기존 파일 규칙과 Vitest 테스트를 그대로 유지한다.

인자는 갱신할 README 경로 하나를 받는다. 워크플로가 체크아웃한 프로필 repo의 경로를 넘긴다.

### 워크플로 job

`update-profile`은 checkout을 두 번 한다.

| 대상 | 경로 | 토큰 |
|---|---|---|
| `sGOM/sGom.github.io` | `blog` | 기본 `GITHUB_TOKEN` |
| `sGOM/sGom` | `profile` | `PROFILE_TOKEN` |

blog 쪽에서 `npm ci` 후 스크립트를 실행하고, 대상으로 `profile/README.md`를 넘긴다.
커밋 작성자는 `github-actions[bot]`으로 둔다.

## 실패 처리

| 상황 | 동작 |
|---|---|
| RSS fetch 실패 | job 실패. 조용히 넘어가면 갱신이 멈춘 것을 모른다 |
| README에 마커 없음 | job 실패 |
| 글이 0개 | 안내 문구를 넣고 정상 종료 |
| 내용 변동 없음 | 커밋을 만들지 않는다 |

이 job이 실패해도 블로그 배포는 이미 끝난 뒤이므로 사이트에는 영향이 없다.

## 범위 밖

- 프로필 repo를 로컬에 클론해 관리하는 것
- 방문자 수 카운터, 트로피, 스네이크 애니메이션 등 추가 위젯
- 다크/라이트 테마에 따라 통계 카드 이미지를 전환하는 처리
