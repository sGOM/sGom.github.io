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
본문을 고쳤으면 frontmatter의 `updatedDate`를 오늘 날짜로 맞춘다.

## 2. 검수 완료 표시

`docs/review-status.md`에서 그 슬러그를 가리키는 줄의 `- [ ]`를 `- [V]`로 바꾼다. 이미 `[V]`면 그대로 두고 알린다.

## 3. 글과 표시만 커밋

```bash
npm test && npm run build   # 실패하면 커밋하지 말고 보고한다
git add src/content/posts/<슬러그> docs/review-status.md
git status --short          # 스테이징된 것이 위 둘뿐인지 확인
git commit
```

**`git add -A`, `git add .`, `git commit -a`를 쓰지 않는다.** 세션에서 함께 고친 `docs/`, `.claude/`, `experiments/` 변경은 이 커밋에 넣지 않는다.

메시지는 `posts: <슬러그> ...` 형식으로 이번에 고친 내용을 적고 마지막에 `검수 완료 처리.` 한 줄을 넣는다.

## 4. 푸시

```bash
git log origin/main..HEAD --oneline   # 스킬이 만들지 않은 커밋이 섞였으면 사용자에게 먼저 알린다
git push
```
