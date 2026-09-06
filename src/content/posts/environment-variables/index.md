---
title: 환경 변수는 누가 물려주고 어디에 남는가
description: 셸 변수와 환경 변수의 차이, 자식 프로세스로의 상속 규칙, 리눅스의 시작 파일과 윈도우 레지스트리가 값을 남기는 방식을 정리한다.
pubDate: 2026-08-25
updatedDate: 2026-09-06
category: "운영체제"
tags: ["기본개념", "환경변수", "셸", "프로세스"]
---

## 무엇이 문제인가

`DB_URL=...`을 설정하고 애플리케이션을 띄웠는데 값이 비어 있다. 터미널을 새로 열면 조금 전에 설정한 변수가 사라져 있다. `.bashrc`에 넣었더니 이번에는 SSH 스크립트에서만 안 먹는다. 윈도우에서 `setx`로 넣었더니 이미 열려 있던 터미널에서는 계속 안 보인다.

네 상황 모두 원인이 같다. 환경 변수는 파일이나 레지스트리 같은 공용 저장소가 아니라 **프로세스마다 따로 가지는 메모리**이고, 운영체제가 실행 중인 프로세스에 값을 밀어 넣는 경로는 없다. 부모가 자식 프로세스를 실행할 때 복사해서 넘겨주는 것이 전부다. 리눅스와 윈도우가 갈리는 지점은 그 메모리를 처음 채울 값을 어디에 적어 두느냐다. 리눅스는 셸이 읽는 파일에, 윈도우는 레지스트리에 적는다.

## 용어 정리

| 이름 | 뜻 |
|---|---|
| 셸 변수 | 셸 프로세스 안에서만 유효한 이름과 값. 실행하는 명령에는 넘어가지 않는다 |
| 환경 변수 | 프로세스의 환경 목록에 올라간 변수. 자식 프로세스가 실행될 때 복사된다. 리눅스는 [`environ`](https://man7.org/linux/man-pages/man7/environ.7.html), 윈도우는 [환경 블록](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables)이라 부른다 |
| 영구 설정 | 새로 시작하는 프로세스의 환경 목록을 채울 값을 프로세스 바깥에 적어 두는 것. 리눅스는 셸 시작 파일, 윈도우는 레지스트리다 |

셸마다 이름이 다르다.

| 하는 일 | sh, bash | PowerShell | cmd |
|---|---|---|---|
| 셸 변수 정의 | `VAR=값` | `$VAR = '값'` | 없음 |
| 환경 변수 정의 | `export VAR=값` | `$env:VAR = '값'` | `set VAR=값` |
| 환경 변수 출력 | `env`, `printenv` | `Get-ChildItem Env:` | `set` |
| 셸 변수 출력 | `set` (환경 변수도 함께 나온다) | `Get-Variable` | 해당 없음 |
| 지우기 | `unset VAR` | `Remove-Item Env:VAR` | `set VAR=` |

cmd에는 셸 변수라는 층이 없다. `set`으로 만든 변수는 곧바로 환경 블록에 들어가므로 `export`에 해당하는 명령도 없다.

## 핵심 정리

리눅스와 유닉스 계열 셸이다.

| 설정 방법 | 적용 범위 | 수명 | 자식 프로세스 상속 |
|---|---|---|---|
| `VAR=값` | 현재 셸 | 셸 종료까지 | 안 됨 |
| `export VAR=값` | 현재 셸 | 셸 종료까지 | 됨 |
| `VAR=값 명령` | 그 명령 하나 | 명령 종료까지 | 됨 |
| `~/.bashrc`의 `export VAR=값` | 로그인이 아닌 대화형 셸마다 | 파일을 고칠 때까지 | 됨 |
| `~/.profile`의 `export VAR=값` | 로그인할 때 시작하는 셸 | 파일을 고칠 때까지 | 됨 |
| `env -i VAR=값 명령` | 그 명령 하나, 나머지 환경은 비운 채로 | 명령 종료까지 | 됨 |

윈도우다.

| 설정 방법 | 적용 범위 | 수명 | 자식 프로세스 상속 |
|---|---|---|---|
| `$VAR = '값'` | 현재 PowerShell 세션 | 세션 종료까지 | 안 됨 |
| `$env:VAR = '값'` | 현재 PowerShell 세션 | 세션 종료까지 | 됨 |
| `set VAR=값` | 현재 cmd 세션 | 세션 종료까지 | 됨 |
| `setx VAR 값` | 레지스트리를 다시 읽은 프로세스와 그 자식. 이미 열려 있던 창은 제외 | 레지스트리에서 지울 때까지 | 됨 |
| `setx VAR 값 /m` | 모든 사용자의 이후 프로세스. 관리자 권한이 필요하다 | 레지스트리에서 지울 때까지 | 됨 |
| `[Environment]::SetEnvironmentVariable('VAR', '값', 'User')` | `setx`와 같다 | 레지스트리에서 지울 때까지 | 됨 |
| 시스템 속성 창의 환경 변수 편집 | `setx`와 같다 | 레지스트리에서 지울 때까지 | 됨 |

`Dockerfile`의 `ENV`는 양쪽이 같다. 같은 스테이지의 이후 명령과 그 이미지로 만든 컨테이너에 적용되고, 값은 이미지에 기록된다.

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

PowerShell에도 같은 경계가 있다. `$A`는 셸 변수, `$env:A`는 환경 변수다. 아래 윈도우 출력은 모두 Windows 11(빌드 26200)의 Windows PowerShell 5.1과 cmd에서 확인했다.

```powershell
PS> $A = 'x'
PS> powershell -NoProfile -Command 'Write-Output "[$env:A]"'
[]
PS> $env:A = 'x'
PS> powershell -NoProfile -Command 'Write-Output "[$env:A]"'
[x]
```

다만 PowerShell에는 셸 변수를 환경으로 올리는 명령이 없다. `$VAR`와 `$env:VAR`는 별개 이름 공간이라, 옮기려면 `$env:A = $A`처럼 다시 대입한다. cmd에는 경계 자체가 없어 `set`으로 만든 변수가 곧바로 자식에게 넘어간다.

### 상속은 복사다

자식이 물려받은 값을 바꿔도 부모에게 돌아가지 않는다.

```sh
$ export B=parent
$ sh -c 'export B=child; echo inner=$B'
inner=child
$ echo outer=$B
outer=parent
```

셸이 새 프로그램을 실행할 때 환경 목록을 `execve`의 `envp`로 넘기고, 자식은 그 복사본을 받는다. 그 뒤로 둘은 남남이다. 스크립트에서 `export`한 값을 호출한 셸에 남기려면 실행 대신 [`source`](https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html)로 현재 셸에서 읽어야 한다. PowerShell에서는 `. .\script.ps1`이 같은 역할이다.

윈도우도 복사본을 넘긴다.

```powershell
PS> $env:B = 'parent'
PS> cmd /v:on /c "set B=child& echo inner=!B!"
inner=child
PS> "outer=$env:B"
outer=parent
```

윈도우 셸은 새 프로그램을 실행할 때 [`CreateProcess`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)로 환경 블록을 넘기고, 자식은 그 복사본을 받는다. 이름만 다르고 복사라는 점은 같다. 예시의 `/v:on`은 `!B!` 지연 확장을 켜는 옵션이다. 켜지 않고 `%B%`로 쓰면 대입 전 값이 나오는데, 이유는 아래 「혼동하기 쉬운 것」에 적었다.

### 한 명령에만 붙이기

명령 앞에 `이름=값`을 붙이면 그 명령의 환경에만 들어간다.

```sh
$ C=once printenv C
once
$ echo after=[$C]
after=[]
```

특수 빌트인이 아닌 명령이라면 셸에 흔적이 남지 않는다. 외부 명령과 일반 빌트인이 여기 해당한다. [POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_09_01)는 특수 빌트인(`:`, `export`, `eval` 등) 앞의 대입이 현재 실행 환경에 남는다고 정하고, 셸 함수의 경우는 미규정으로 둔다. [POSIX 모드](https://www.gnu.org/software/bash/manual/html_node/Bash-POSIX-Mode.html)의 bash와 dash에서 `C=once :`를 실행하면 `C`가 셸에 남고, 기본 모드 bash에서는 남지 않는다.

윈도우 셸에는 이 형태가 없다. cmd에서는 `cmd /c "set C=once& 명령"`처럼 자식 셸을 하나 띄워 그 안에서 대입하고, PowerShell에서는 대입과 실행과 정리를 세 줄로 나눠 쓴다.

### 영구 설정은 프로세스 바깥에 있다

`setx`는 값을 레지스트리에 적을 뿐, 실행 중인 프로세스는 건드리지 않는다.

```powershell
PS> setx BLOG_DEMO 1
SUCCESS: Specified value was saved.
PS> "현재=[$env:BLOG_DEMO]"
현재=[]
PS> powershell -NoProfile -Command 'Write-Output "자식=[$env:BLOG_DEMO]"'
자식=[]
PS> [Environment]::GetEnvironmentVariable('BLOG_DEMO', 'User')
1
```

현재 세션의 환경 블록에 없으니 그 세션이 띄운 자식에도 없다. 사용자 범위는 `HKEY_CURRENT_USER\Environment`, 시스템 범위는 `HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment` 키에 적힌다. 값을 바꾼 쪽은 [`WM_SETTINGCHANGE`](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange) 메시지를 `lParam`에 `"Environment"`를 담아 브로드캐스트하고, 이 메시지를 처리하는 프로그램은 자기 환경을 다시 읽는다. 탐색기가 그중 하나라서 알림 뒤 탐색기에서 실행한 프로그램은 새 값을 받고, 이미 열려 있던 터미널은 받지 못한다. 위 예시로 만든 값은 `reg delete "HKCU\Environment" /v BLOG_DEMO /f`로 지운다.

리눅스의 `~/.profile`도 같은 자리다. 파일을 고쳐도 이미 열린 셸은 다시 읽지 않는다. 적어 두는 곳이 파일이냐 레지스트리냐가 다를 뿐, 값이 저절로 들어오는 시점은 양쪽 다 프로세스가 시작할 때뿐이다. 실행 중에 바깥을 다시 읽는 것은 그 프로그램이 직접 해야 하는 일이다.

## 혼동하기 쉬운 것

**빈 값과 없는 값은 리눅스에서 다르다.** `VAR=`는 길이 0인 문자열을 가진 변수가 존재하는 상태이고, `unset VAR`는 목록에서 사라진 상태다.

```sh
$ export D=
$ printenv D; echo "exit=$?"

exit=0
$ unset D
$ printenv D; echo "exit=$?"
exit=1
```

빈 줄 하나가 `D`의 값이다. 애플리케이션이 [`System.getenv("D")`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/System.html#getenv(java.lang.String))로 읽으면 앞은 `""`, 뒤는 `null`이다. 기본값 대체 로직이 `null` 검사만 하면 빈 문자열이 그대로 흘러 들어간다.

윈도우 셸은 빈 문자열 대입을 삭제로 처리해 왔다. cmd의 `set D=`도, Windows PowerShell 5.1의 `$env:D = ''`도 변수를 지운다.

```powershell
PS> $env:D = ''
PS> Test-Path Env:D
False
PS> cmd /c "set D=& if defined D (echo defined) else (echo not defined)"
not defined
```

[PowerShell 7.5](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables)부터는 빈 문자열을 가진 변수를 만들 수 있고, 지우려면 `$null`을 대입한다. 같은 스크립트가 5.1과 7.5에서 다르게 동작한다.

**`.bashrc`와 `.profile`은 읽히는 시점이 다르다.** [Bash 매뉴얼](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html) 기준으로 로그인 셸은 `~/.bash_profile`, `~/.bash_login`, `~/.profile`을 이 순서로 찾아 처음 발견한 하나만 읽는다. `~/.bash_profile`이 있으면 `~/.profile`은 영영 읽히지 않는다. 로그인이 아닌 대화형 셸은 `~/.bashrc`를 읽는다.

터미널에서는 되는데 cron에서만 `command not found`가 나는 이유가 대체로 여기다. cron이 실행하는 셸은 대화형도 로그인도 아니라 시작 파일을 거치지 않는다. crontab에 `SHELL=/bin/bash`를 써도 마찬가지고, `BASH_ENV=/경로`를 지정했을 때 그 파일만 읽는다. `ssh host 'command'`는 사정이 다르다. bash는 표준 입력이 네트워크 연결에 붙어 있으면 비대화형이어도 `~/.bashrc`를 읽는다. 다만 데비안 계열의 기본 `~/.bashrc`는 맨 앞에서 비대화형이면 `return`하므로, 파일은 읽히되 그 아래 설정까지 가지 못한다. 원인이 다를 뿐 값이 안 보이는 결과는 cron과 같다.

**이름의 대소문자 구분은 플랫폼마다 다르다.** 리눅스에서 `Path`와 `PATH`는 다른 변수다. 윈도우는 구분하지 않는다.

```powershell
PS> $env:CASE_TEST = 'x'
PS> $env:case_test
x
```

윈도우에서만 돌려 본 코드는 `Path`라고 적혀 있어도 문제가 드러나지 않고, 같은 코드를 리눅스 컨테이너에 올릴 때 처음 깨진다. 관례상 환경 변수는 대문자로 쓴다.

**cmd의 `%VAR%`는 줄을 읽을 때 확장된다.** 한 줄을 실행하기 전에 그 줄의 `%VAR%`를 먼저 값으로 바꾸므로, 같은 줄에서 대입한 값은 반영되지 않는다.

```powershell
PS> $env:B = 'parent'
PS> cmd /c "set B=child& echo inner=%B%"
inner=parent
```

`/v:on`이나 `setlocal EnableDelayedExpansion`으로 지연 확장을 켜고 `!VAR!`로 쓰면 확장 시점이 실행 시점으로 밀린다.

**`PATH` 구분자가 다르다.** 리눅스는 `:`, 윈도우는 `;`다. 경로를 이어 붙이는 스크립트를 양쪽에서 돌린다면 이 문자를 하드코딩하지 않는다. 덧붙여 `setx`는 값을 [1024자에서 자른다](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/setx). 길어진 `PATH`를 이 명령으로 다시 쓰면 잘린 채로 저장된다. `[Environment]::SetEnvironmentVariable`에는 이 제한이 없어 `PATH`를 건드릴 때는 이쪽이 안전하다.

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

이 파일은 `execve` 시점에 받은 환경의 스냅샷이다. 출력되는 변수는 환경마다 다르고, 시작한 뒤에 추가한 변수는 여기 나타나지 않는다.

```sh
$ export AFTER_START=1
$ tr '\0' '\n' < /proc/$$/environ | grep -c AFTER_START
0
$ printenv AFTER_START
1
```

셸이 새로 실행하는 자식인 `printenv`에는 값이 전달되지만, 셸 자신의 `environ` 파일에는 없다. 실행 중인 프로세스의 설정을 파일로 확인할 때 이 차이를 모르면 값이 반영되지 않았다고 오해하기 쉽다.

윈도우에는 이에 대응하는 내장 수단이 없다. `Get-ChildItem Env:`도 `[Environment]::GetEnvironmentVariables()`도 자기 프로세스만 읽는다. 다른 프로세스의 환경 블록을 보려면 그 프로세스의 메모리를 읽는 외부 도구가 필요하다.

## 참고

- [environ(7)](https://man7.org/linux/man-pages/man7/environ.7.html)
- [proc_pid_environ(5)](https://man7.org/linux/man-pages/man5/proc_pid_environ.5.html)
- [POSIX: Environment Variables](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html)
- [Bash Reference Manual: Bash Startup Files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
- [Win32: Environment Variables](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables)
- [PowerShell: about_Environment_Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables)
- [Windows Commands: setx](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/setx)
