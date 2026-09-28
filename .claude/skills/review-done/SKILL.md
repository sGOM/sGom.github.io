---
name: review-done
description: Use when the user says a post's review is finished — "검수 완료", "이 글 확인했다", "검수 끝났으니 반영해줘".
---

# 검수 완료 처리

스킬 호출 자체가 사용자의 체크다. 체크 여부를 대신 판단하지 않는다.

## 1. 대상 글 정하기

이번 세션에서 검수한 글. 확실하지 않으면 작업 트리에서 찾는다.

```bash
git status --porcelain -- src/content/posts | sed 's|.*src/content/posts/||;s|/.*||' | sort -u
```

슬러그가 없거나 둘 이상이면 **사용자에게 묻는다.** 짐작하지 않는다. 여러 글이면 글마다 커밋을 따로 만든다.
발행된 글의 본문을 고쳤으면 frontmatter의 `updatedDate`를 오늘 날짜로 맞춘다.
초안(`_drafts/<슬러그>/`)은 `git status`에 나오지 않는다. gitignore 대상이라서다. 이번 세션의 글이 초안이면 그 슬러그를 쓴다.

## 1-1. 초안이면 발행한다

`_drafts/`는 gitignore 대상이라 초안인 채로는 커밋·푸시할 글이 없다. **초안에 대한 이 스킬 호출은 발행 승인이다.**

1. 글 안의 `/posts/<슬러그>/` 링크가 모두 발행된 글을 가리키는지 확인한다. 아직 초안인 글을 가리키면 멈추고 사용자에게 묻는다. 먼저 올리면 404다.
2. 슬러그가 글 전체를 대표하는지 본다. 발행하면 URL이 고정된다. 바꿀 이유가 보이면 옮기기 전에 사용자에게 묻는다.
3. 옮기고 `draft: true` 줄을 지운다.

```bash
mv src/content/posts/_drafts/<슬러그> src/content/posts/<슬러그>
```

4. `docs/review-status.md`에서 그 줄의 경로를 `_drafts/<슬러그>/`에서 `<슬러그>/`로 고치고 줄 끝 `(초안)`을 지운다. 새 줄을 붙이지 않는다.

## 2. 검수 완료 표시

`docs/review-status.md`에서 그 슬러그를 가리키는 줄의 `- [ ]`를 `- [V]`로 바꾼다. 이미 `[V]`면 그대로 두고 알린다.
이번 세션에서 본문을 고쳤으면 그 줄 끝의 `· 교차검증 합의`도 지운다.

## 3. 글과 표시만 커밋

```bash
npm test && npm run build   # 실패하면 커밋하지 말고 보고한다
git add src/content/posts/<슬러그> docs/review-status.md
git status --short          # 스테이징된 것이 위 둘뿐인지 확인
git commit
```

`docs/review-status.md`에 이 글과 무관한 미커밋 변경이 있으면 파일째 `git add` 하지 않는다.
`HEAD` 판에 이 글의 줄만 바꾼 사본을 만들어 그것만 스테이징한다. 작업 트리의 다른 변경은 그대로 남긴다.

```bash
git show HEAD:docs/review-status.md > <scratchpad>/rs.md   # 이 글의 줄만 고친다
git update-index --cacheinfo 100644,$(git hash-object -w --no-filters <scratchpad>/rs.md),docs/review-status.md
git diff --cached docs/review-status.md                    # 한 줄만 바뀌었는지 확인
```

**`git add -A`, `git add .`, `git commit -a`를 쓰지 않는다.** 세션에서 함께 고친 `docs/`, `.claude/`, `experiments/` 변경은 이 커밋에 넣지 않는다.

메시지는 `posts: <슬러그> ...` 형식으로 이번에 고친 내용을 적고 마지막에 `검수 완료 처리.` 한 줄을 넣는다.

## 4. 푸시

```bash
git log origin/main..HEAD --oneline   # 스킬이 만들지 않은 커밋이 섞였으면 사용자에게 먼저 알린다
git push
```
