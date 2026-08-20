---
title: git worktree로 브랜치를 디렉터리째 나눠 쓰기
description: 저장소 하나에서 여러 브랜치를 각각의 디렉터리에 동시에 체크아웃하는 git worktree의 명령과 동작을 정리하고, 에이전트를 여러 개 돌릴 때의 쓸모까지 짚는다
pubDate: 2026-08-20
category: "GIT"
tags: ["기본개념", "Git", "브랜치", "워크트리"]
---

## 왜 필요한가

작업 중에 다른 브랜치를 봐야 할 일은 자주 생긴다. 리뷰 요청이 오거나, 운영 장애로 hotfix를 내야 하거나, 이전 버전에서 동작을 확인해야 할 때다. `git switch`로 브랜치를 갈아타면 작업 디렉터리 하나를 그대로 덮어쓰기 때문에 대가가 따른다.

- 커밋하지 않은 변경을 `stash`에 밀어 넣었다가 되돌려야 한다. 되돌리는 걸 잊으면 그대로 묻힌다.
- `node_modules`, `build`, `target`, IDE 인덱스처럼 추적하지 않는 산출물이 브랜치에 맞지 않게 남는다. 의존성이 다른 브랜치를 오갔다면 재설치와 재빌드가 뒤따른다.
- 실행 중인 개발 서버나 디버거를 내려야 한다.

`git worktree`는 저장소 하나에 작업 디렉터리를 여러 개 붙여, 브랜치마다 별도 디렉터리를 갖게 한다. 브랜치를 갈아타는 대신 디렉터리를 옮겨 다니면 되므로 `stash`도 서버 재시작도 필요 없어진다. 재설치·재빌드는 브랜치를 오갈 때마다 되풀이되지 않고 워크트리를 만들 때 한 번씩만 치르는 비용으로 바뀐다. 이 비용은 뒤에서 다시 다룬다.

## 용어 정리

| 용어 | 뜻 |
|---|---|
| 워킹 트리(working tree) | 체크아웃된 파일이 놓인 디렉터리. 저장소가 기록한 특정 커밋의 상태를 파일로 펼쳐 놓은 것 |
| 메인 워크트리(main worktree) | `git init`이나 `git clone`으로 처음 만들어진 워킹 트리. 실제 `.git` 디렉터리를 갖는다 |
| 링크드 워크트리(linked worktree) | `git worktree add`로 나중에 붙인 워킹 트리. `.git`이 디렉터리가 아니라 메인 쪽을 가리키는 파일이다 |

링크드 워크트리의 `.git`은 한 줄짜리 텍스트 파일이다.

```
gitdir: C:/tmp/wtdemo/demo/.git/worktrees/wt-feature
```

가리키는 곳에는 메인 저장소를 이어주는 `commondir`·`gitdir`와, 그 워크트리 전용 `HEAD`, `index`, `logs`, `refs`가 들어 있다. 즉 체크아웃 상태와 스테이징 영역이 워크트리별로 갈라지고, 커밋·브랜치·태그를 담은 객체 데이터베이스는 메인 저장소 하나를 공유한다. 무엇이 갈라지고 무엇이 공유되는지는 [공식 문서 REFS 절](https://git-scm.com/docs/git-worktree#_refs)에 정리돼 있고, 아래 「혼동하기 쉬운 것」에서 자주 걸리는 항목만 추렸다.

## 핵심 정리

| 명령 | 하는 일 | 주의 |
|---|---|---|
| `git worktree add <경로> <브랜치>` | 그 브랜치를 새 디렉터리에 체크아웃 | 다른 워크트리가 이미 체크아웃한 브랜치면 실패 |
| `git worktree add -b <새브랜치> <경로>` | 새 브랜치를 만들면서 체크아웃 | 분기 기준은 현재 HEAD |
| `git worktree add <경로>` | 디렉터리 이름과 같은 이름의 브랜치를 쓴다 | 없으면 새로 만들고 있으면 체크아웃. 다른 워크트리가 쓰고 있으면 실패 |
| `git worktree list` | 워크트리 목록과 각각의 HEAD·브랜치 | `locked`, `prunable` 상태도 함께 표시 |
| `git worktree remove <경로>` | 디렉터리와 등록 정보를 함께 삭제 | 수정·미추적 파일이 있으면 `--force` 필요 |
| `git worktree prune` | 디렉터리가 사라진 워크트리의 등록 정보 정리 | `rm -rf`로 지웠을 때 필요 |
| `git worktree move <경로> <새경로>` | 워크트리 디렉터리를 옮긴다 | 메인 워크트리는 옮길 수 없다 |
| `git worktree lock <경로>` | `prune`·`move`·`remove`를 모두 막는다 | 해제는 `unlock`, 강제는 `-f`를 두 번 |

## 항목별 설명

**`add`의 세 형태는 브랜치를 어떻게 정하느냐만 다르다.** 브랜치 이름을 주면 그 브랜치를, `-b`를 주면 새로 만든 브랜치를 체크아웃한다. 아무것도 주지 않으면 디렉터리 이름을 브랜치 이름으로 삼는데, [공식 문서](https://git-scm.com/docs/git-worktree)는 이 경우를 이렇게 설명한다.

> If `<branch>` doesn't exist, a new branch based on HEAD is automatically created as if `-b <branch>` was given. If `<branch>` does exist, it will be checked out in the new worktree, if it's not checked out anywhere else, otherwise the command will refuse to create the worktree (unless `--force` is used).

없으면 만들고, 있으면 그대로 체크아웃한다. 실패하는 조건은 "브랜치가 이미 있을 때"가 아니라 "그 브랜치가 다른 워크트리에 이미 체크아웃돼 있을 때"다. 출력이 `new branch`인지 `checking out`인지로 어느 쪽이었는지 알 수 있다.

**`remove`와 `prune`은 역할이 다르다.** `remove`는 디렉터리와 등록 정보를 한 번에 지우는 정상 경로다. 파일 탐색기나 `rm -rf`로 디렉터리만 먼저 지워버리면 등록 정보가 남아 `list`에 `prunable`로 뜨는데, 이때 `prune`이 그 찌꺼기를 걷어낸다.

**`lock`은 그 워크트리를 건드리는 명령을 통째로 막는다.** USB나 네트워크 드라이브에 만든 워크트리는 매체가 빠지면 경로가 사라진 것처럼 보여 `prune` 대상이 된다. 잠가두면 자동 정리에서 빠지고, `move`와 `remove`도 거부된다. 풀려면 `git worktree unlock <경로>`를 쓰거나 `-f`를 두 번 준다.

## 예시

git 2.45.1 기준이다. 출력 문구는 버전에 따라 달라질 수 있다.

커밋 하나와 브랜치 `feature-x`가 있는 저장소 `demo`에서 시작한다. `feature-x`를 형제 디렉터리에 체크아웃한다.

```console
$ git worktree add ../wt-feature feature-x
Preparing worktree (checking out 'feature-x')
HEAD is now at 9319276 init

$ git worktree list
C:/tmp/wtdemo/demo        9319276 [main]
C:/tmp/wtdemo/wt-feature  9319276 [feature-x]
```

원래 디렉터리는 `main`을 그대로 유지한 채 `../wt-feature`에서 `feature-x` 작업을 한다. 링크드 워크트리에서 커밋하면 메인 저장소에서 즉시 보인다. 객체 데이터베이스가 하나이기 때문에 `push`나 `fetch` 없이 공유된다.

```console
$ cd ../wt-feature
$ echo "linked" > f.txt
$ git add f.txt
$ git commit -m "from linked"
[feature-x 5175d59] from linked
 1 file changed, 1 insertion(+)
 create mode 100644 f.txt

$ cd ../demo
$ git log --oneline -1 feature-x
5175d59 from linked
```

정리는 `remove`로 한다. 남은 변경이 있으면 막아준다.

```console
$ echo scratch > ../wt-feature/tmp.txt
$ git worktree remove ../wt-feature
fatal: '../wt-feature' contains modified or untracked files, use --force to delete it
```

## 혼동하기 쉬운 것

**같은 브랜치를 두 워크트리에 동시에 체크아웃할 수 없다.** 워킹 트리가 둘인데 브랜치 참조가 하나면 어느 쪽 커밋을 따라야 할지 정할 수 없어서다.

```console
$ git worktree add ../wt-dup feature-x
Preparing worktree (checking out 'feature-x')
fatal: 'feature-x' is already used by worktree at 'C:/tmp/wtdemo/wt-feature'
```

`--force`로 뚫을 수는 있지만, 두 워킹 트리가 같은 브랜치 참조를 함께 움직이게 되므로 권하지 않는다. 같은 커밋의 파일만 필요하다면 `--detach`로 브랜치 없이 붙이는 편이 낫다.

**`clone`과는 공유 범위가 다르다.** 별도 디렉터리가 생긴다는 점은 같지만, `clone`은 저장소를 하나 더 만들어 커밋을 주고받으려면 `push`/`fetch`가 필요하다. 워크트리는 저장소를 공유해 커밋이 곧바로 보이고, 브랜치와 태그도 한 벌만 관리된다.

**공유되는 것과 안 되는 것을 구분해야 한다.**

| 대상 | 워크트리 간 |
|---|---|
| 커밋·브랜치·태그·리모트 | 공유 |
| `stash` | 공유 ([`refs/stash`는 저장소 공통](https://git-scm.com/docs/git-worktree#_refs)) |
| `HEAD`·인덱스(스테이징) | 워크트리별 |
| `refs/bisect`, `refs/worktree`, `refs/rewritten` | 워크트리별 |
| 추적하지 않는 파일 (`node_modules`, `.env`, 빌드 산출물) | 워크트리별 |

특히 `stash`가 공유된다는 점이 걸린다. 한 워크트리에서 `git stash`한 내용이 다른 워크트리의 `git stash list`에도 그대로 보인다. 워크트리를 나눠 쓰는 목적이 작업 격리라면 `stash`보다 임시 커밋이 안전하다.

`node_modules`나 `.env`가 공유되지 않는다는 점도 알아둬야 한다. 새 워크트리는 추적 대상 파일만 체크아웃하므로 의존성 설치와 로컬 설정 복사가 매번 필요하다.

## AI 시대에 더 필요한 이유

코딩 에이전트를 여러 개 돌리기 시작하면 워크트리의 쓸모가 달라진다. 사람이 쓸 때는 브랜치를 갈아타는 번거로움을 더는 도구였지만, 에이전트를 붙일 때는 동시에 진행되는 작업들을 격리하는 수단이 된다.

여러 프로세스가 한 작업 디렉터리를 동시에 쓰면 편집이 겹치고, 테스트가 다른 쪽의 중간 상태를 읽는다. 디렉터리가 하나면 체크아웃된 파일도 하나이므로 브랜치를 나눠도 이 문제는 남는다. 작업마다 디렉터리를 하나씩 주면 파일 충돌이 사라지고, 커밋은 저장소 하나에 모여 `push`/`fetch` 없이 그대로 비교하고 머지할 수 있다.

작업 결과를 통째로 버리기 쉬워지는 점도 크다. 맡긴 시도가 마음에 들지 않으면 `git worktree remove --force`로 디렉터리째 지우면 된다. 되돌릴 파일을 골라내거나 리셋 범위를 고민할 필요가 없다. 다만 `remove`는 디렉터리와 등록 정보만 지운다. 브랜치와 그 위의 커밋은 남으므로 완전히 버리려면 `git branch -D`까지 해야 한다.

Claude Code는 이 방식을 명령으로 감쌌다. [공식 문서의 "Run parallel sessions with worktrees"](https://code.claude.com/docs/en/common-workflows#run-parallel-sessions-with-worktrees)는 워크트리를 "각자의 브랜치를 가진 별도 체크아웃(a separate checkout on its own branch)"으로 소개하고, 터미널마다 다른 이름을 주어 실행하라고 안내한다.

```bash
claude --worktree feature-auth
```

앞서 정리한 "공유되지 않는 것"은 여기서 비용으로 돌아온다. 워크트리마다 의존성을 따로 설치해야 하고, `.env` 같은 로컬 설정도 복사해야 한다. 설정 파일 쪽은 Claude Code가 만드는 워크트리에 한해 [`.worktreeinclude`](https://code.claude.com/docs/en/worktrees#copy-gitignored-files-into-worktrees)로 자동 복사할 수 있다. `.gitignore` 문법으로 경로를 적으면 되고, gitignore 대상이면서 그 패턴에 맞는 파일만 복사된다. `git worktree add`로 직접 만든 워크트리에는 적용되지 않는다. 의존성 설치는 여전히 남으므로 워크트리 생성과 설치를 묶은 스크립트를 만들어두는 편이 낫다.

## 참고

- [git-worktree 공식 문서](https://git-scm.com/docs/git-worktree)
- [Git Glossary — working tree](https://git-scm.com/docs/gitglossary#def_working_tree)
- [Claude Code — Run parallel sessions with worktrees](https://code.claude.com/docs/en/common-workflows#run-parallel-sessions-with-worktrees)
- [Claude Code — Worktrees](https://code.claude.com/docs/en/worktrees)
