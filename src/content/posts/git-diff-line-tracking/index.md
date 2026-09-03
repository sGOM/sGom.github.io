---
title: git은 변경된 줄을 저장하지 않는다 — 스냅샷에서 hunk가 나오기까지
description: 커밋이 담는 것은 파일 전체 스냅샷이고 변경된 줄은 git diff가 읽는 시점에 계산한다. blob 객체, Myers 알고리즘, 컨텍스트 병합, packfile 델타가 각각 어느 층에서 일하는지 실행 결과로 확인한다
pubDate: 2026-09-03
category: "개발도구"
tags: ["파고들기", "Git", "diff", "객체 모델"]
---

## 전제

[git merge 종류 — fast-forward, 머지 커밋, 스쿼시](/posts/git-merge-types/)에서 커밋이 그래프의 노드로 어떻게 이어지는지 다뤘다. 그 글은 커밋들 사이의 관계를 봤다.

여기서는 커밋 하나 안에 무엇이 들어 있는지, `git diff`가 그 내용으로 "변경된 줄"을 어떻게 만들어 내는지를 본다.

## 왜 필요한가

같은 두 파일을 비교하는데 옵션에 따라 변경된 줄 수가 달라진다. 두 줄짜리 파일에서 둘째 줄의 들여쓰기만 바꾼 경우다. `--no-index`를 쓰므로 저장소가 없어도 된다.

```console
$ printf 'line1\nline2\n' > b_old
$ printf 'line1\n  line2\n' > b_new
$ git diff --no-index --numstat b_old b_new
1	1	b_old => b_new
$ git diff --no-index -w --numstat b_old b_new
$ git diff --no-index -w --numstat b_old b_new | wc -c
0
```

한 번은 1줄이 바뀌었다고 하고, 한 번은 파일 이름조차 내놓지 않는다. 어느 쪽이 저장된 값인가. 둘 다 아니다. 저장된 값 자체가 없다.

`git log -p`가 커밋마다 `+`와 `-`를 붙여 보여주니 커밋이 변경 줄 목록을 갖고 있다고 오해하기 쉽다. 그 화면은 매번 계산된 결과다. git이 무엇을 재료로 어디서 계산하는지 보면 diff 옵션이 결과를 바꾸는 이유도, 이름 변경 탐지가 실패하는 이유도 같이 나온다.

## 겉으로 보이는 것

`git show`는 커밋 하나를 인자로 받아 변경된 줄을 출력한다. `git commit`은 `3 files changed, 12 insertions(+), 4 deletions(-)`를 찍는다. `git log --stat`과 GitHub의 커밋 페이지도 같은 형태다.

커밋을 열면 diff가 나오니 저장 구조도 그럴 것 같다. 커밋 객체를 직접 열면 다르다.

## 구조

git이 저장하는 객체는 네 종류이고 이 글에 나오는 것은 셋이다.

| 객체 | 담는 것 |
|---|---|
| blob | 파일 내용 전체. 파일 이름은 담지 않는다 |
| tree | 디렉터리 하나의 목록. 이름, 모드, 가리키는 blob이나 tree의 해시 |
| commit | tree 하나의 해시, 부모 커밋 해시, 작성자와 커밋터, 메시지 |

셋이 이렇게 이어진다.

```
commit
  └─ tree ef36c0e
       └─ blob 33c99cd   a.txt
```

커밋에서 출발해 따라가면 그 시점에 추적 중이던 파일 전체가 나온다. 이전 커밋과의 차이는 이 경로 어디에도 없다.

## 동작 원리

**커밋 객체에 diff가 없다.** 커밋이 담는 것은 tree 해시, 부모 해시, 작성자와 커밋터, 커밋 메시지다.

한 줄을 고치면 그 파일의 blob이 통째로 새로 만들어진다. 10줄 파일에서 다섯째 줄만 바꿔도 새 blob은 10줄 전체를 담는다. 바뀐 줄만 담은 객체는 생기지 않는다.

git은 blob 해시를 내용에서 계산한다. 정확히는 `blob <크기>\0` 헤더를 앞에 붙인 바이트열의 해시다. 경로가 달라도 내용이 같으면 blob 하나를 공유한다. git이 식별하는 단위는 파일이나 줄이 아니라 내용이다.

그래서 `git diff A B`는 저장된 무언가를 읽는 명령이 아니다. A와 B가 가리키는 blob을 각각 꺼내 그 자리에서 비교한다. 비교는 git에 내장된 xdiff가 맡고 기본 알고리즘은 Myers다. git 소스의 [xdiff/xdiffi.c](https://github.com/git/git/blob/v2.43.0/xdiff/xdiffi.c#L37)에 `See "An O(ND) Difference Algorithm and its Variations", by Eugene Myers`라는 주석이 남아 있다.

Myers 알고리즘은 두 줄 목록을 놓고 삽입과 삭제 횟수의 합이 최소가 되는 편집 스크립트를 목표로 삼는다. 다만 git의 구현은 최소를 보장하지 않는다. 같은 파일에 "We might encounter expensive edge cases using this algorithm, so a little bit of heuristic is needed to cut the search and to return a suboptimal point"라는 주석이 있다. 탐색 비용이 커지면 중간에 끊고 최적이 아닌 결과를 낸다. 최소를 강제하려면 `--diff-algorithm=minimal`을 쓴다. [git-config 문서](https://git-scm.com/docs/git-config)가 `myers`를 "The basic greedy diff algorithm", `minimal`을 "Spend extra time to make sure the smallest possible diff is produced"로 나눠 적는 이유다.

줄이 같은지만 보므로 한 글자를 고쳐도 그 줄은 삭제 한 줄과 삽입 한 줄이 된다. 반대로 `-w`는 줄을 비교하기 전에 공백을 정규화한다. 공백만 바뀐 줄은 같은 줄로 취급되어 편집 스크립트 단계에서 이미 차이가 사라진다.

편집 스크립트가 비면 그 파일은 통계 목록에서 지워진다. [`diff.c`](https://github.com/git/git/blob/v2.43.0/diff.c#L3845)의 `builtin_diffstat()`이 항목을 먼저 등록해 두고, 수정된 파일의 추가 줄과 삭제 줄이 모두 0이면서 모드가 그대로면 도로 빼낸다. 주석이 이유를 밝힌다. "Omit diffstats of modified files where nothing changed. Even if may_differ, this might be the case due to ignoring whitespace changes, etc."

그래서 변경 줄이 0으로 보고되는 것이 아니라 파일 이름조차 출력되지 않는다. 「왜 필요한가」의 `--numstat`이 빈 화면을 낸 이유가 이것이다. 같은 주석이 예외도 적어 둔다. 추가, 삭제, 이름 변경, 모드 변경은 이 처리에서 빠지므로 0줄이어도 목록에 남는다. 여기서 이름 변경은 탐지가 붙인 상태를 뜻한다. `--no-index`로 이름이 다른 두 파일을 넘긴 경우는 상태가 수정이라 위 조건에 걸린다. 「왜 필요한가」의 출력에 보이는 `=>`는 통계에 이름을 합쳐 적는 표기일 뿐이다. git 테스트 스위트의 [`whitespace-only changes not reported (diffstat)`](https://github.com/git/git/blob/master/t/t4015-diff-whitespace.sh)가 `--stat -b`로 같은 동작을 고정해 두었다.

편집 스크립트가 나오면 앞뒤로 바뀌지 않은 줄을 컨텍스트로 붙인다. 기본값은 3줄이고 `-U`로 바꾼다. 컨텍스트 범위가 겹치는 변경들은 하나의 hunk로 합쳐진다. `@@ -1,4 +1,4 @@`의 네 숫자는 원본 시작 줄과 줄 수, 새 파일 시작 줄과 줄 수다.

편집 횟수가 같은 후보가 여럿일 때가 있다. 반복되는 블록 사이에 삽입이 일어나면 경계를 어디로 잡아도 삽입 줄 수가 같다. git은 이때 들여쓰기를 보고 읽기 좋은 쪽으로 hunk 경계를 민다. 이 보정이 indent heuristic이고 [2.14부터 기본으로 켜져 있다](https://github.com/git/git/blob/master/Documentation/RelNotes/2.14.0.adoc). 릴리스 노트는 "The "indent" heuristics is now the default in "diff""로, [git-config 문서](https://git-scm.com/docs/git-config)는 `diff.indentHeuristic`을 "Set this option to `false` to disable the default heuristics that shift diff hunk boundaries to make patches easier to read"로 적는다.

저장 계층에는 별개의 압축이 있다. `git gc`가 느슨한 객체를 packfile로 모으면서 비슷한 객체를 델타로 저장한다. 이 델타는 바이트 단위 명령이고 줄과 무관하다. [gitformat-pack](https://git-scm.com/docs/gitformat-pack)은 명령이 둘이라고 정의한다. "one for copying a byte range from the source object and one for inserting new data embedded in the instruction itself". 델타의 기반 객체는 타입과 경로 이름 해시와 크기로 정렬한 뒤 [슬라이딩 윈도우](https://github.com/git/git/blob/master/Documentation/technical/pack-heuristics.adoc) 안에서 고르므로 부모 커밋의 같은 경로가 아닐 수도 있다.

## 직접 확인

Ubuntu 24.04, bash 5.2, GNU sed 4.9, git 2.43.0에서 실행했다. `sed -i`와 `printf '\x00'`은 이 조합에 맞춘 것이라 BSD 계열에서는 다르게 동작한다.

저장소를 셋 쓰므로 디렉터리를 나눠 만든다. (1)은 객체 구조와 diff 계산, (2)는 packfile 델타, (3)은 이름 변경 탐지다. (3)은 「경계 조건」에서 쓰고, 「경계 조건」의 나머지 두 예제는 (1)로 돌아가 이어간다. 블록마다 `cd`를 적어 두었다. `--no-index` 예제는 저장소가 필요 없다.

### (1) 객체 구조

빈 저장소에 10줄 파일을 커밋하고 다섯째 줄만 고쳐 다시 커밋한다.

```console
$ mkdir /tmp/g1 && cd /tmp/g1
$ git init -q . && git config user.email a@b.c && git config user.name t
$ printf 'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n' > a.txt
$ git add a.txt && git commit -qm first
$ sed -i 's/^line5$/LINE5 changed/' a.txt
$ git add a.txt && git commit -qm second
```

커밋 객체를 연다.

```console
$ git cat-file -p HEAD
tree ef36c0e343f8ff41b09d763d6ce22f8d61b4c34b
parent d6f6af4633de05ea7bfd5665a02a07f796fee95a
author t <a@b.c> 1788396198 +0000
committer t <a@b.c> 1788396198 +0000

second
```

`line5`도 `LINE5 changed`도 없다. tree 해시와 부모 해시만 있다.

tree를 따라가면 blob이 나온다.

```console
$ git ls-tree HEAD~1
100644 blob 4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c	a.txt
$ git ls-tree HEAD
100644 blob 33c99cd9e75d56c83e31d3b2850fa7eece55ac20	a.txt
```

두 blob의 크기를 잰다.

```console
$ git cat-file -s 4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c
61
$ git cat-file -s 33c99cd9e75d56c83e31d3b2850fa7eece55ac20
69
```

61바이트와 69바이트다. 바뀐 줄 하나의 크기가 아니라 파일 전체의 크기다. 새 blob을 꺼내면 10줄이 전부 들어 있다.

```console
$ git cat-file -p 33c99cd9e75d56c83e31d3b2850fa7eece55ac20
line1
line2
line3
line4
LINE5 changed
line6
line7
line8
line9
line10
```

내용이 같으면 경로가 달라도 blob 하나를 공유한다.

```console
$ printf 'same content\n' > x.txt
$ mkdir sub && printf 'same content\n' > sub/y.txt
$ git hash-object x.txt
01e6138faef088714355b81759a88101ce07a1a3
$ git hash-object sub/y.txt
01e6138faef088714355b81759a88101ce07a1a3
```

diff가 계산이라는 것은 커밋을 거치지 않고도 확인된다. 위에서 얻은 blob 해시 두 개를 그대로 넘기면 된다.

```console
$ git diff 4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c 33c99cd9e75d56c83e31d3b2850fa7eece55ac20
diff --git a/4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c b/33c99cd9e75d56c83e31d3b2850fa7eece55ac20
index 4083766..33c99cd 100644
--- a/4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c
+++ b/33c99cd9e75d56c83e31d3b2850fa7eece55ac20
@@ -2,7 +2,7 @@ line1
 line2
 line3
 line4
-line5
+LINE5 changed
 line6
 line7
 line8
```

두 blob 사이에는 커밋 관계도 파일 이름도 없다. 그런데도 변경된 줄이 나온다.

### 컨텍스트가 hunk를 가른다

13줄 파일의 첫 줄과 마지막 줄을 고쳐 컨텍스트 줄 수만 바꾼다.

```console
$ printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\n' > ctx_old
$ printf 'A\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nM\n' > ctx_new
$ git diff --no-index -U0 ctx_old ctx_new
diff --git a/ctx_old b/ctx_new
index 988f966..9ecff16 100644
--- a/ctx_old
+++ b/ctx_new
@@ -1 +1 @@
-a
+A
@@ -13 +13 @@ l
-m
+M
$ git diff --no-index -U6 ctx_old ctx_new
diff --git a/ctx_old b/ctx_new
index 988f966..9ecff16 100644
--- a/ctx_old
+++ b/ctx_new
@@ -1,13 +1,13 @@
-a
+A
 b
 c
 d
 e
 f
 g
 h
 i
 j
 k
 l
-m
+M
```

`-U0`에서는 hunk가 둘이고 `-U6`에서는 컨텍스트가 겹쳐 하나로 합쳐진다. 변경된 줄은 그대로인데 표현이 달라진다.

### hunk 경계는 보정이 정한다

같은 블록이 반복되는 입력을 만든다.

```console
$ printf 'function f() {\n  if (a) {\n    b();\n  }\n}\n' > A_old
$ printf 'function f() {\n  if (a) {\n    c();\n  }\n  if (a) {\n    b();\n  }\n}\n' > A_new
$ git diff --no-index --indent-heuristic A_old A_new
diff --git a/A_old b/A_new
index 824bba5..6213498 100644
--- a/A_old
+++ b/A_new
@@ -1,4 +1,7 @@
 function f() {
+  if (a) {
+    c();
+  }
   if (a) {
     b();
   }
$ git diff --no-index --no-indent-heuristic A_old A_new
diff --git a/A_old b/A_new
index 824bba5..6213498 100644
--- a/A_old
+++ b/A_new
@@ -1,5 +1,8 @@
 function f() {
   if (a) {
+    c();
+  }
+  if (a) {
     b();
   }
 }
```

보정을 끄면 블록이 중간에서 잘린다. 삽입 3줄이라는 결과는 같고 어느 3줄로 볼지가 달라진다.

같은 입력에 알고리즘만 네 가지로 바꿔 출력 해시를 견준다.

```console
$ for alg in myers minimal patience histogram; do
>   git diff --no-index --no-indent-heuristic --diff-algorithm=$alg A_old A_new | md5sum
> done
0851da2baf825da58dca096659d11dcb  -
0851da2baf825da58dca096659d11dcb  -
0851da2baf825da58dca096659d11dcb  -
0851da2baf825da58dca096659d11dcb  -
```

해시가 넷 다 같다. 블록 이동, 반복 블록 사이 삽입, 120줄짜리 반복 입력을 포함해 아홉 가지 경우를 만들었지만 네 알고리즘의 출력이 갈리는 경우는 만들지 못했다.

여기까지의 실험에서 출력을 바꾼 것은 indent heuristic(hunk 경계), `-U`(hunk 병합), `-w`(파일 제외) 셋이고, 각각 다른 입력에서 확인했다. indent heuristic은 바로 위 A_old/A_new에서, `-U`는 ctx_old/ctx_new에서, `-w`는 「왜 필요한가」의 b_old/b_new에서다.

### (2) packfile 델타

새 저장소에서 2000줄 파일을 만들어 커밋하고 한 줄만 고쳐 다시 커밋한다.

```console
$ mkdir /tmp/g2 && cd /tmp/g2
$ git init -q . && git config user.email a@b.c && git config user.name t
$ python3 -c "open('big.txt','w').write(''.join('line %d: the quick brown fox jumps over the lazy dog\n' % i for i in range(2000)))"
$ git add big.txt && git commit -qm v1
$ python3 -c "
> ls=open('big.txt').read().splitlines(True)
> ls[999]='line 999: CHANGED\n'
> open('big.txt','w').writelines(ls)"
$ git add big.txt && git commit -qm v2
```

두 버전의 blob 해시를 확인한다.

```console
$ git rev-parse HEAD~1:big.txt HEAD:big.txt
a42dbb65f23b4753f31a5b15afd9036418ad2ba1
3097881bb42175701cac4552a4fe0f4d6ed1db50
```

바뀐 줄이 54바이트에서 18바이트가 되면서 파일 전체도 36바이트 줄었다.

```console
$ git cat-file -s a42dbb65f23b4753f31a5b15afd9036418ad2ba1
108890
$ git cat-file -s 3097881bb42175701cac4552a4fe0f4d6ed1db50
108854
```

`git gc`를 돌리고 packfile 안을 본다. blob 두 줄만 추린 것이다.

```console
$ git gc -q
$ git verify-pack -v .git/objects/pack/*.idx | grep blob
a42dbb65f23b4753f31a5b15afd9036418ad2ba1 blob   108890 5203 236
3097881bb42175701cac4552a4fe0f4d6ed1db50 blob   22 35 5439 1 a42dbb65f23b4753f31a5b15afd9036418ad2ba1
```

[git-verify-pack](https://git-scm.com/docs/git-verify-pack) 문서는 행 형식을 둘로 나눠 정의한다. 델타가 아닌 객체는 `object-name type size size-in-packfile offset-in-packfile` 다섯 열이고, 델타 객체는 뒤에 `depth base-object-name`이 붙어 일곱 열이다. 두 번째 행에만 그 두 열이 있다. 델타 깊이 1, 기반 객체는 첫 번째 blob이다.

커밋 객체에만 시각이 들어가므로 재실행하면 커밋 해시가 달라진다. tree와 blob은 내용만으로 정해지므로 해시는 위 값 그대로 재현된다. 오프셋 열은 실행에 따라 위 값과 다르게 나오기도 했다.

문서는 열 이름만 정의한다. 관측상 델타 행의 size는 복원된 내용의 크기가 아니다. 이 행은 22를 보고하는데 `git cat-file -s`는 gc 이후에도 108854를 보고한다.

```console
$ git cat-file -s 3097881bb42175701cac4552a4fe0f4d6ed1db50
108854
$ git cat-file -p 3097881bb42175701cac4552a4fe0f4d6ed1db50 | wc -l
2000
$ git cat-file -p 3097881bb42175701cac4552a4fe0f4d6ed1db50 | sed -n '1000p'
line 999: CHANGED
```

108KB 파일의 두 번째 버전이 packfile 안에서 35바이트를 차지한다. 이 절약은 바이트 단위 델타의 결과이고, `git diff`가 보여주는 줄 단위 변경과는 다른 층에서 일어난다.

## 경계 조건

**같은 입력에서도 옵션이 diff 출력을 바꾼다.** `--word-diff`를 붙이면 줄 단위 `+`와 `-` 대신 줄 안에서 바뀐 구간이 표시된다. (1)의 blob 두 개를 그대로 쓰므로 그 저장소로 돌아간다.

```console
$ cd /tmp/g1
$ git diff --word-diff 4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c 33c99cd9e75d56c83e31d3b2850fa7eece55ac20
diff --git a/4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c b/33c99cd9e75d56c83e31d3b2850fa7eece55ac20
index 4083766..33c99cd 100644
--- a/4083766a98b7d3e5e8e276f0f09c27ba1efe4d5c
+++ b/33c99cd9e75d56c83e31d3b2850fa7eece55ac20
@@ -2,7 +2,7 @@ line1
line2
line3
line4
[-line5-]{+LINE5 changed+}
line6
line7
line8
```

### (3) 이름 변경 탐지

이름 변경은 저장된 정보가 아니다. tree는 이름과 모드와 blob 해시를 담을 뿐, 이전 이름이 무엇이었는지는 기록하지 않는다. `git diff`가 삭제된 경로와 추가된 경로를 맞춰 추정한다.

내용이 그대로면 blob 해시가 같으므로 정확히 맞춰진다. 세 번째 저장소에 (1)과 같은 10줄 파일을 한 번 커밋해 두고 시작한다.

```console
$ mkdir /tmp/g3 && cd /tmp/g3
$ git init -q . && git config user.email a@b.c && git config user.name t
$ printf 'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n' > a.txt
$ git add a.txt && git commit -qm first
$ git mv a.txt renamed.txt && git commit -qm rename
$ git diff --stat HEAD~1 HEAD
 a.txt => renamed.txt | 0
 1 file changed, 0 insertions(+), 0 deletions(-)
$ git diff --stat --no-renames HEAD~1 HEAD
 a.txt       | 10 ----------
 renamed.txt | 10 ++++++++++
 2 files changed, 10 insertions(+), 10 deletions(-)
```

내용이 함께 바뀌면 유사도로 추정한다. 10줄 중 한 줄을 고치면서 이름을 바꾼 경우다.

```console
$ git mv renamed.txt moved.txt
$ sed -i 's/^line10$/TAIL/' moved.txt
$ git add -A && git commit -qm rename-and-edit
$ git diff --stat HEAD~1 HEAD
 renamed.txt => moved.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

추정이므로 임계값을 넘기면 실패한다. 같은 두 커밋에 유사도 기준을 95%로 올리면 이름 변경이 사라지고 삭제와 추가로 보인다.

```console
$ git diff --stat -M95% HEAD~1 HEAD
 moved.txt   | 10 ++++++++++
 renamed.txt | 10 ----------
 2 files changed, 10 insertions(+), 10 deletions(-)
```

같은 두 커밋인데 한쪽은 1줄 변경, 다른 쪽은 20줄 변경이다. 이름 변경 여부는 저장된 정보가 아니라 비교 시점의 유사도 계산과 임계값이 정한다.

### 그 밖의 경계

바이너리 파일에는 줄이 없다. 내용에 NUL 바이트가 있으면 git은 바이너리로 판단하고 변경 줄 대신 한 줄만 출력한다. (1)의 저장소로 다시 돌아가 확인한 것이다.

```console
$ cd /tmp/g1
$ printf 'abc\x00def\n' > bin.dat && git add bin.dat && git commit -qm addbin
$ printf 'abc\x00XYZ\n' > bin.dat
$ git diff -- bin.dat
diff --git a/bin.dat b/bin.dat
index ca85725..6bfc9f0 100644
Binary files a/bin.dat and b/bin.dat differ
```

델타 체인은 diff 출력과 무관하다. 기반 객체는 정렬 순서와 윈도우 크기가 정하고 `git gc` 시점과 옵션에 따라 달라지므로, 델타 기반이 부모 커밋의 같은 파일이라는 보장은 없다.

## 언제 쓰고 언제 안 쓰나

| 상황 | 설정 |
|---|---|
| 기본 리뷰 | 손대지 않는다. `myers`와 indent heuristic이 기본값이다 |
| hunk 경계가 블록 중간에서 잘릴 때 | `git config diff.indentHeuristic`을 확인한다. 값이 비어 있으면 켜진 상태다 |
| 포매터를 돌린 커밋 | `-w`로 공백만 바뀐 줄을 제외한다 |
| 리뷰 컨텍스트가 부족할 때 | `-U10` 정도로 늘린다 |
| 이름 변경 탐지가 의심스러울 때 | `--no-renames`로 끄거나 `-M`으로 임계값을 조절해 견준다 |

`--diff-algorithm`은 마지막에 시도한다. 위 재현에서 이 규모의 입력으로는 `myers`, `minimal`, `patience`, `histogram`의 출력이 갈리지 않았다. 크게 재배치된 큰 파일에서는 `histogram`이 다른 결과를 낼 것으로 보이지만 이 글에서는 재현하지 못했다.

## 참고

- [git-diff 문서](https://git-scm.com/docs/git-diff)
- [git-config 문서의 `diff.algorithm`과 `diff.indentHeuristic`](https://git-scm.com/docs/git-config)
- [gitformat-pack — packfile 델타 인코딩](https://git-scm.com/docs/gitformat-pack)
- [git-verify-pack 출력 형식](https://git-scm.com/docs/git-verify-pack)
- [git 소스의 xdiff/xdiffi.c](https://github.com/git/git/blob/v2.43.0/xdiff/xdiffi.c)
- [git 2.14 릴리스 노트 — indent heuristic 기본 적용](https://github.com/git/git/blob/master/Documentation/RelNotes/2.14.0.adoc)
