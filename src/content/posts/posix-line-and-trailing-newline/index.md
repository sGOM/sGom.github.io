---
title: "POSIX가 정의한 줄과 파일 끝 개행"
description: "GitHub diff에 뜨는 No newline at end of file 경고를, POSIX의 line과 incomplete line 정의로 설명한다."
pubDate: 2026-08-31
category: "컴퓨터공학"
tags: ["기본개념", "POSIX", "Git"]
---

## 무엇이 문제인가

파일 끝에 개행을 넣지 않고 커밋한 뒤 개행 하나만 추가하고 `git diff`를 보면 이렇게 나온다. GitHub의 diff 화면도 같은 표기를 보여준다.

```diff
@@ -1,3 +1,3 @@
 a
 b
-c
\ No newline at end of file
+c
```

`c`는 글자 하나 바뀌지 않았는데 삭제와 추가로 함께 잡혔다. 그 개행이 있어야 `c`가 비로소 한 줄이 되기 때문이다.

## 핵심 정리

| 용어 | POSIX 정의 | 요약 |
|---|---|---|
| [line](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap03.html#tag_03_185) (3.185) | A sequence of zero or more non-\<newline\> characters plus a terminating \<newline\> character. | 개행 문자로 끝나야 한 줄이다 |
| [incomplete line](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap03.html#tag_03_172) (3.172) | A sequence of one or more non-\<newline\> characters at the end of the file. | 파일 끝에 개행 없이 남은 문자열. 줄이 아니다 |
| [empty line](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap03.html#tag_03_120) (3.120) | A line consisting of only a \<newline\>. | 개행 하나뿐인 줄 |
| [newline character](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap03.html#tag_03_224) (3.224) | A character that in the output stream indicates that printing should start at the beginning of the next line. (이하 생략) | C의 `'\n'`, 바이트로는 `0x0A` |
| [text file](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap03.html#tag_03_387) (3.387) | A file that contains characters organized into zero or more lines. (이하 생략) | 0줄 이상의 줄로 이루어진 파일 |

정의를 한 문장으로 줄이면, 개행은 줄과 줄 사이의 구분자가 아니라 줄의 종결자다.

## 항목별 설명

구분자로 보는 관점에서는 `a\nb\nc`가 세 줄이다. 개행 두 개가 세 덩어리를 가른다. 그러나 POSIX는 그렇게 세지 않는다. 종결자가 붙은 `a`와 `b`만 줄이고, 남은 `c`는 incomplete line이다.

incomplete line은 줄이 되지 못한 나머지에 붙은 이름이다. 그래서 `c`를 줄로 만들려면 `c`를 지우고 `c\n`을 새로 넣어야 한다. 위 diff가 삭제 한 줄과 추가 한 줄로 나온 이유다.

## 예시

개행이 있는 파일과 없는 파일은 바이트 하나만 다르다.

```console
$ printf 'a\nb\nc\n' > good.txt
$ printf 'a\nb\nc'   > bad.txt
$ od -c good.txt
0000000   a  \n   b  \n   c  \n
0000006
$ od -c bad.txt
0000000   a  \n   b  \n   c
0000005
```

그런데 `wc -l`은 `bad.txt`를 2줄로 센다. 개행 문자를 세기 때문이다.

```console
$ wc -l good.txt bad.txt
 3 good.txt
 2 bad.txt
 5 total
```

`bad.txt`에도 `c`는 분명히 있지만 `wc`는 줄로 세지 않는다. POSIX가 [wc](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/wc.html)의 `-l`을 각 입력 파일의 개행 문자 수로 규정하고 있어서, 이 결과는 규격대로 동작한 것이다.

git도 같은 기준으로 파일을 읽는다. 개행 없는 파일에 줄을 하나 덧붙이면, 새 줄과 함께 기존 마지막 줄까지 바뀐 것으로 잡힌다.

```diff
@@ -1,3 +1,4 @@
 a
 b
-c
\ No newline at end of file
+c
+d
```

같은 파일에 개행이 이미 있었다면 diff는 한 줄이다.

```diff
@@ -1,3 +1,4 @@
 a
 b
 c
+d
```

## 혼동하기 쉬운 것

**`\ No newline at end of file`은 POSIX 규격이 아니라 GNU 관례다.** [POSIX의 diff 규격](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/diff.html)에 이 문구는 없다. 불완전한 줄 뒤에 `\`로 시작하는 줄을 붙여 표시하는 [GNU diffutils의 관례](https://www.gnu.org/software/diffutils/manual/html_node/Incomplete-Lines.html)를 git이 따르고, GitHub도 그대로 보여준다. 파일에 들어 있는 내용이 아니라 diff 출력에만 붙는 표시다.

**C 표준은 소스 파일과 텍스트 스트림에 서로 다른 규칙을 둔다.** [C11 5.1.1.2](https://port70.net/~nsz/c/c11/n1570.html#5.1.1.2)는 소스 파일에 개행을 요구한다.

> A source file that is not empty shall end in a new-line character, which shall not be immediately preceded by a backslash character before any such splicing takes place.

실행 중에 읽고 쓰는 텍스트 스트림을 다루는 [7.21.2](https://port70.net/~nsz/c/c11/n1570.html#7.21.2)는 같은 것을 구현에 맡긴다.

> Whether the last line requires a terminating new-line character is implementation-defined.

그래서 개행 없이 끝나는 `.c` 파일은 규격 위반이지만 컴파일러는 대체로 받아준다. 이 `shall`은 제약(constraint) 밖에 있어 위반의 결과가 미정의 동작이고, 미정의 동작에는 진단 의무가 없기 때문이다.

**빈 파일과 개행 하나뿐인 파일은 다르다.** 빈 파일은 문자가 없으니 줄도 0개다. 개행 하나뿐인 파일은 non-\<newline\> 문자 0개에 종결자가 붙은 형태라 empty line 하나, 즉 1줄이다. `wc`의 두 결과가 갈리는 지점이다.

```console
$ : > empty.txt
$ printf '\n' > onenl.txt
$ wc -c empty.txt onenl.txt
0 empty.txt
1 onenl.txt
1 total
$ wc -l empty.txt onenl.txt
0 empty.txt
1 onenl.txt
1 total
```

## 직접 확인

경고를 무시하면 파일을 이어 붙이거나 줄 단위로 읽는 쪽이 깨진다.

`cat`은 개행을 넣어주지 않는다. 앞 파일의 마지막 글자와 뒤 파일의 첫 글자가 한 줄로 붙는다.

```console
$ printf 'a\nb\nc' > p1.txt
$ printf 'x\ny\n'  > p2.txt
$ cat p1.txt p2.txt
a
b
cx
y
```

셸의 `while read`는 마지막 줄을 조용히 버린다. `read`는 개행을 만나야 성공을 반환하는데, `c`를 읽은 시점에는 개행 대신 EOF를 만나 실패로 끝나고 루프 본문이 실행되지 않는다.

```console
$ while read -r line; do echo "읽음: $line"; done < p1.txt
읽음: a
읽음: b
```

`read`는 실패해도 읽은 내용을 변수에 남겨두므로, 조건을 하나 덧붙이면 마지막 줄까지 처리한다.

```console
$ while read -r line || [ -n "$line" ]; do echo "읽음: $line"; done < p1.txt
읽음: a
읽음: b
읽음: c
```

세는 도구마다 답이 갈리기도 한다. GNU grep은 incomplete line도 한 줄로 세서 `wc -l`과 결과가 어긋난다.

```console
$ grep -c '' p1.txt
3
$ wc -l p1.txt
2 p1.txt
```

확인 환경은 Git for Windows의 bash 5.2.26, git 2.45.1, GNU diffutils 3.10, GNU coreutils의 `wc`와 `od`다.

## 참고

- [POSIX.1-2024 Base Definitions, Chapter 3](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap03.html)
- [GNU diffutils manual — Incomplete Lines](https://www.gnu.org/software/diffutils/manual/html_node/Incomplete-Lines.html)
- [C11 draft N1570, 5.1.1.2 Translation phases](https://port70.net/~nsz/c/c11/n1570.html#5.1.1.2) / [7.21.2 Streams](https://port70.net/~nsz/c/c11/n1570.html#7.21.2)
