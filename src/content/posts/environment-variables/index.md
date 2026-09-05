---
title: 환경 변수는 누가 물려주고 어디에 남는가
description: 셸 변수와 환경 변수의 차이, export가 하는 일, 자식 프로세스로의 상속 규칙을 정리한다.
pubDate: 2026-08-25
category: "운영체제"
tags: ["기본개념", "환경변수", "셸", "프로세스"]
---

## 무엇이 문제인가

`export DB_URL=...`을 실행하고 애플리케이션을 띄웠는데 값이 비어 있다. 터미널을 새로 열면 조금 전에 설정한 변수가 사라져 있다. `.bashrc`에 넣었더니 이번에는 SSH 스크립트에서만 안 먹는다.

세 상황 모두 원인이 같다. 환경 변수는 파일이나 전역 저장소가 아니라 **프로세스마다 따로 가지는 메모리**이고, 부모가 자식 프로세스를 실행할 때 복사해서 넘겨주는 것 말고는 전달 경로가 없다.

## 용어 정리

| 이름 | 뜻 |
|---|---|
| 셸 변수 | 셸 프로세스 안에서만 유효한 이름과 값. 실행하는 명령에는 넘어가지 않는다 |
| 환경 변수 | 프로세스의 환경 목록([`environ`](https://man7.org/linux/man-pages/man7/environ.7.html))에 올라간 변수. 자식 프로세스가 실행될 때 복사된다 |
| `export` | 셸 변수를 환경 목록에 올리는 명령. 값을 바꾸는 게 아니라 넘겨줄 대상으로 표시한다 |
| `env`, `printenv` | 환경 변수만 출력한다 |
| `set` | 셸 변수까지 함께 출력한다. 그래서 목록이 훨씬 길다 |

## 핵심 정리

| 설정 방법 | 적용 범위 | 수명 | 자식 프로세스 상속 |
|---|---|---|---|
| `VAR=값` | 현재 셸 | 셸 종료까지 | 안 됨 |
| `export VAR=값` | 현재 셸 | 셸 종료까지 | 됨 |
| `VAR=값 명령` | 그 명령 하나 | 명령 종료까지 | 됨 |
| `~/.bashrc`의 `export VAR=값` | 로그인이 아닌 대화형 셸마다 | 파일을 고칠 때까지 | 됨 |
| `~/.profile`의 `export VAR=값` | 로그인할 때 시작하는 셸 | 파일을 고칠 때까지 | 됨 |
| `Dockerfile`의 `ENV` | 같은 스테이지의 이후 명령과 그 이미지로 만든 컨테이너 | 이미지에 기록된다 | 됨 |
| `env -i VAR=값 명령` | 그 명령 하나, 나머지 환경은 비운 채로 | 명령 종료까지 | 됨 |

## 예시

### export가 경계를 만든다

`export` 없이 정의한 변수는 같은 셸 안에서만 보인다.

```sh
$ A=x
$ sh -c 'echo [$A]'
[]
$ export A
$ sh -c 'echo [$A]'
[x]
```

`export A`는 값을 다시 대입하지 않는다. 이미 있던 셸 변수 `A`를 환경 목록으로 옮길 뿐이다.

### 상속은 복사다

자식이 물려받은 값을 바꿔도 부모에게 돌아가지 않는다.

```sh
$ export B=parent
$ sh -c 'export B=child; echo inner=$B'
inner=child
$ echo outer=$B
outer=parent
```

셸이 새 프로그램을 실행할 때 환경 목록을 `execve`의 `envp`로 넘기고, 자식은 그 복사본을 받는다. 그 뒤로 둘은 남남이다. 스크립트에서 `export`한 값을 호출한 셸에 남기려면 실행 대신 [`source`](https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html)로 현재 셸에서 읽어야 한다.

### 한 명령에만 붙이기

명령 앞에 `이름=값`을 붙이면 그 명령의 환경에만 들어간다.

```sh
$ C=once printenv C
once
$ echo after=[$C]
after=[]
```

특수 빌트인이 아닌 명령이라면 셸에 흔적이 남지 않는다. 외부 명령과 일반 빌트인이 여기 해당한다. [POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_09_01)는 특수 빌트인(`:`, `export`, `eval` 등) 앞의 대입이 현재 실행 환경에 남는다고 정하고, 셸 함수의 경우는 미규정으로 둔다. [POSIX 모드](https://www.gnu.org/software/bash/manual/html_node/Bash-POSIX-Mode.html)의 bash와 dash에서 `C=once :`를 실행하면 `C`가 셸에 남고, 기본 모드 bash에서는 남지 않는다.

## 혼동하기 쉬운 것

**빈 값과 없는 값은 다르다.** `VAR=`는 길이 0인 문자열을 가진 변수가 존재하는 상태이고, `unset VAR`는 목록에서 사라진 상태다.

```sh
$ export D=
$ printenv D; echo "exit=$?"

exit=0
$ unset D
$ printenv D; echo "exit=$?"
exit=1
```

빈 줄 하나가 `D`의 값이다. 애플리케이션이 [`System.getenv("D")`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/System.html#getenv(java.lang.String))로 읽으면 앞은 `""`, 뒤는 `null`이다. 기본값 대체 로직이 `null` 검사만 하면 빈 문자열이 그대로 흘러 들어간다.

**`.bashrc`와 `.profile`은 읽히는 시점이 다르다.** [Bash 매뉴얼](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html) 기준으로 로그인 셸은 `~/.bash_profile`, `~/.bash_login`, `~/.profile`을 이 순서로 찾아 처음 발견한 하나만 읽는다. `~/.bash_profile`이 있으면 `~/.profile`은 영영 읽히지 않는다. 로그인이 아닌 대화형 셸은 `~/.bashrc`를 읽는다.

터미널에서는 되는데 cron에서만 `command not found`가 나는 이유가 대체로 여기다. cron이 실행하는 셸은 대화형도 로그인도 아니라 시작 파일을 거치지 않는다. crontab에 `SHELL=/bin/bash`를 써도 마찬가지고, `BASH_ENV=/경로`를 지정했을 때 그 파일만 읽는다. `ssh host 'command'`는 사정이 다르다. bash는 표준 입력이 네트워크 연결에 붙어 있으면 비대화형이어도 `~/.bashrc`를 읽는다. 다만 데비안 계열의 기본 `~/.bashrc`는 맨 앞에서 비대화형이면 `return`하므로, 파일은 읽히되 그 아래 설정까지 가지 못한다. 원인이 다를 뿐 값이 안 보이는 결과는 cron과 같다.

**이름은 대소문자를 구분한다.** `Path`와 `PATH`는 다른 변수다. 관례상 환경 변수는 대문자로 쓴다.

## 직접 확인

리눅스에서는 `/proc/<PID>/environ`으로 실행 중인 프로세스의 환경을 볼 수 있다. 값이 널 문자로 구분되어 있어 `tr`로 바꿔 읽는다.

```sh
$ sleep 60 &
[1] 9323
$ tr '\0' '\n' < /proc/9323/environ | head -3
USER=root
SHLVL=1
HOME=/root
```

출력되는 변수는 환경마다 다르다. 이 파일은 `execve` 시점에 받은 환경의 스냅샷이다. 시작한 뒤에 추가한 변수는 여기 나타나지 않는다.

```sh
$ export AFTER_START=1
$ tr '\0' '\n' < /proc/$$/environ | grep -c AFTER_START
0
$ printenv AFTER_START
1
```

셸이 새로 실행하는 자식인 `printenv`에는 값이 전달되지만, 셸 자신의 `environ` 파일에는 없다. 실행 중인 프로세스의 설정을 파일로 확인할 때 이 차이를 모르면 값이 반영되지 않았다고 오해하기 쉽다.

## 참고

- [environ(7)](https://man7.org/linux/man-pages/man7/environ.7.html)
- [proc_pid_environ(5)](https://man7.org/linux/man-pages/man5/proc_pid_environ.5.html)
- [POSIX: Environment Variables](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html)
- [Bash Reference Manual: Bash Startup Files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
