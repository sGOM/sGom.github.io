---
title: "POSIX — 표준이 정한 것과 구현이 덧붙인 것"
description: "POSIX가 어떤 문서이고 네 권으로 무엇을 규정하는지, 그 범위 밖에서 같은 셸 스크립트가 왜 시스템마다 갈리는지 정리한다."
pubDate: 2026-09-07
category: "운영체제"
tags: ["기본개념", "POSIX", "셸"]
---

## 왜 헷갈리는가

`[[ ]]`로 조건을 쓴 셸 스크립트가 어떤 시스템에서는 `[[: not found`로 죽는다. 두 시스템 모두 POSIX를 따르는데도 그렇다.

POSIX는 유닉스 계열 운영체제가 프로그램에 내놓아야 할 기능을 정한 표준 문서다. 기능이란 파일 열기 같은 C 함수, 셸 문법, `sed`·`awk` 같은 명령어를 말한다. 표준이 정한 것은 모든 시스템이 갖춰야 할 최소한이고, 그 위에 무엇을 더 얹을지는 각 시스템이 정한다. 얹은 부분은 다른 시스템에도 있다는 보장이 없다. `[[ ]]`도 `sed -i`도 그렇게 얹힌 것이다.

## 용어 정리

| 용어 | 뜻 |
|---|---|
| [UNIX](https://en.wikipedia.org/wiki/Unix) | 1969년 AT&T 벨 연구소가 만든 운영체제. 버클리 대학의 BSD, AT&T가 직접 낸 상용판 System V, 그 라이선스를 받은 IBM의 AIX와 HP의 HP-UX로 갈라졌고, 이들과 리눅스처럼 동작을 본떠 새로 만든 시스템을 묶어 유닉스 계열이라 부른다. 지금 UNIX라는 이름은 The Open Group의 상표라서, 인증을 통과한 제품만 UNIX를 자칭할 수 있다 |
| [POSIX](https://ko.wikipedia.org/wiki/POSIX) | Portable Operating System Interface(이식 가능한 운영체제 인터페이스)의 약자. 1980년대 유닉스가 회사마다 갈라져 같은 프로그램도 시스템마다 고쳐야 했다. 여러 유닉스의 동작을 정리하고 서로 갈리는 곳은 하나로 정해 규칙으로 묶은 것이 1988년에 나온 첫 판이다 |
| 이식성 (portability) | 한 시스템에서 쓴 코드를 다른 시스템으로 옮겨도 고치지 않고 돌아가는 성질. POSIX가 노리는 목표다 |
| 구현 (implementation) | 표준을 보고 실제로 만든 운영체제나 프로그램. 리눅스, macOS, bash, GNU sed가 모두 구현이다. 표준은 규칙을 적은 글일 뿐이고, 실행되는 것은 구현이다 |
| 확장 (extension) | 구현이 표준에 없는 기능을 스스로 더한 것. bash의 `[[ ]]`, GNU sed의 `-i`가 그 예다 |
| XSI | X/Open System Interfaces. X/Open은 The Open Group의 전신인 업계 단체다. 표준 본문 안에 선택 사항으로 표시해 둔 기능 묶음이다. 일반 구현은 빼도 되고, 갖춘 구현은 XSI 적합(XSI conformant)이라 부른다. 프로세스끼리 메시지를 주고받는 [`msgget`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/msgget.html) 같은 함수가 여기 속한다 |

UNIX가 먼저 여러 갈래로 갈라졌고, POSIX는 그 뒤에 나왔다. 아래 계보는 단순화했다.

```text
1969  UNIX (AT&T Bell Labs)
        |
        +-- BSD (UC Berkeley) -----------+
        +-- System V (AT&T) -------------+   서로 조금씩 달라 프로그램을 옮기려면 고쳐야 했다
              +-- AIX (IBM) -------------+
              +-- HP-UX (HP) ------------+
                                         |
                                         v
1988                                   POSIX   여러 유닉스의 동작을 정리하고, 갈리는 곳은 하나로 정했다
```

POSIX에 얽힌 이름도 여럿이다. 표준을 만드는 기관 세 곳이 한 본문을 함께 쓰고, 각자 자기 기관의 번호 체계로 발행하기 때문이다. IEEE, The Open Group, ISO/IEC 판은 제목이 달라도 본문이 같다.

| 이름 | 무엇인가 |
|---|---|
| [IEEE Std 1003.1-2024](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap01.html) | 전기·전자·컴퓨터 분야 표준을 만드는 전문가 단체 [IEEE](https://ko.wikipedia.org/wiki/IEEE)가 붙인 문서 번호. 1003.1이 POSIX 문서의 번호이고 2024는 발행 연도다. 줄여서 POSIX.1-2024라고 쓴다 |
| [The Open Group Base Specifications Issue 8](https://pubs.opengroup.org/onlinepubs/9799919799/) | UNIX 상표를 가진 업계 컨소시엄 [The Open Group](https://en.wikipedia.org/wiki/The_Open_Group)이 붙인 이름. Issue는 판을 뜻해 Issue 8은 8판이다. 이 판본이 웹에 무료로 공개돼 있어 이 글의 표준 링크는 모두 여기를 가리킨다 |
| ISO/IEC/IEEE 9945:2026 | 국제 표준을 발행하는 [ISO](https://ko.wikipedia.org/wiki/국제_표준화_기구)와 [IEC](https://ko.wikipedia.org/wiki/국제전기기술위원회)가 같은 본문에 붙인 국제 표준 번호. 2024년 본문의 국제 표준판은 [2026년 3월에 나왔다](https://www.opengroup.org/austin/) |
| [Austin Group](https://www.opengroup.org/austin/) | 위 세 기관이 함께 꾸린 작업반. 본문 개정을 여기서 한 번에 하므로 세 기관의 판이 같은 내용이 된다 |
| [Single UNIX Specification Version 5](https://www.opengroup.org/membership/forums/platform/unix) | 제품에 UNIX라는 이름을 붙이려면 통과해야 하는 The Open Group의 인증 규격. POSIX 본문을 핵심으로 삼고 다른 규격을 더 묶었다. POSIX를 따르는 것과 UNIX 인증을 받는 것이 왜 다른지는 「혼동하기 쉬운 것」에 적었다 |

## 핵심 정리

Issue 8 본문은 네 권(volume)으로 나뉜다. 앞의 세 권은 규범(normative)이라 구현이 반드시 지켜야 하고, 마지막 권은 참고(informative)라 지킬 의무가 없다.

| 권 | 이름 | 담는 것 |
|---|---|---|
| [XBD](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/contents.html) | Base Definitions | 나머지 세 권이 공통으로 쓰는 정의. '줄'이나 '파일 이름' 같은 용어의 뜻, C 헤더 파일(`<unistd.h>` 등) 목록, 정규 표현식 문법 |
| [XSH](https://pubs.opengroup.org/onlinepubs/9799919799/functions/contents.html) | System Interfaces | 프로그램이 운영체제에 일을 시킬 때 부르는 C 함수. 파일을 여는 `open`, 프로세스를 복제하는 `fork`의 인자와 동작, 실패했을 때 남기는 오류 번호(`errno`) |
| [XCU](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/contents.html) | Shell and Utilities | 터미널에서 쓰는 셸 문법과 명령어(유틸리티). `sh`, `sed`, `awk`가 받아야 할 옵션과 그 동작 |
| XRAT | Rationale | 각 규칙을 왜 그렇게 정했는지 적은 해설. 구현이 따를 의무는 없다 |

네 권이 겨냥하는 것은 [1장 Scope](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap01.html)에 한 문장으로 있다.

> POSIX.1-2024 defines a standard operating system interface and environment, including a command interpreter (or "shell"), and common utility programs to support applications portability at the source code level.

마지막 구절이 범위를 긋는다. 소스 코드 수준의 이식성이므로 같은 소스를 각 시스템에서 다시 컴파일해야 한다. 리눅스에서 빌드한 바이너리가 macOS에서 도는 것은 POSIX가 약속한 적 없는 일이다.

## 항목별 설명

### XBD의 용어 정의는 도구의 동작으로 나타난다

XBD 3장은 용어를 모아둔 사전처럼 보이지만, 그 정의가 유틸리티의 동작을 결정한다. `line`을 개행 문자로 끝나는 문자열로 정의했기 때문에 마지막 개행이 없는 `a\nb\nc`를 `wc -l`이 3이 아니라 2로 센다. 그 정의와 `git diff`의 `No newline at end of file` 표기는 [POSIX가 정의한 줄과 파일 끝 개행](/posts/posix-line-and-trailing-newline/)에 따로 적었다.

### XCU가 정한 옵션은 최소 집합이다

Issue 8이 [`sed`](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/sed.html)에 정한 옵션은 `-E`, `-e`, `-f`, `-n` 넷이다. 결과를 화면에 내지 않고 원본 파일을 직접 고쳐 쓰는 `-i`는 없다. 리눅스 배포판의 기본인 GNU sed와 FreeBSD·macOS의 기본인 BSD sed가 각자 붙인 확장인데, 표준이 문법을 맞춰준 적이 없어 사용법이 갈렸다. 아래 환경의 GNU sed 4.9는 `sed -i 's/a/b/' t.txt`를 그대로 받지만, [BSD sed의 `-i`](https://man.freebsd.org/cgi/man.cgi?query=sed&sektion=1)는 백업 파일 이름에 붙일 접미사를 인자로 요구한다. 백업이 필요 없으면 빈 문자열을 넘겨 `sed -i '' 's/a/b/' t.txt`로 써야 한다.

표준을 근거로 이식성을 말하려면 어느 판인지까지 밝혀야 한다. `-E`는 Issue 8에서 들어왔고, 직전 판인 [Issue 7 2018 edition의 `sed`](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sed.html)에는 `-n`, `-e`, `-f` 셋뿐이다.

## 예시

아래 출력은 Windows 11의 Git for Windows 2.45.1 환경에서 얻었다. 유닉스 호환 계층인 MSYS2 런타임 3.4.10, GNU bash 5.2.26, dash 0.5.12, GNU sed 4.9가 들어 있다.

셸의 확장은 같은 명령을 다른 셸에 줘보면 드러난다. 비교 대상인 dash는 [데비안](https://wiki.debian.org/Shell)과 [우분투](https://wiki.ubuntu.com/DashAsBinSh)가 `/bin/sh`로 쓰는 셸로, POSIX가 정한 문법 밖의 기능을 거의 넣지 않았다.

```console
$ bash -c '[[ a == a* ]] && echo match'
match
$ dash -c '[[ a == a* ]] && echo match'
dash: 1: [[: not found
```

`[[ ]]`는 POSIX 셸 문법에 없다. bash가 붙인 확장이라 dash는 `[[`를 명령 이름으로 읽고 찾지 못한다.

`echo`도 갈린다. [XCU의 `echo`](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/echo.html)는 옵션 자체를 금지했다.

> Implementations shall not support any options.

그러면서 첫 인자가 `-e`·`-n` 같은 꼴이거나 인자에 백슬래시가 들어 있으면 결과를 implementation-defined, 즉 구현이 정하고 문서에 밝히도록 남겼다. XSI를 따르는 구현은 그 첫 인자를 출력할 문자열로 취급하고, `\t` 같은 백슬래시 이스케이프를 해석해야 한다.

```console
$ bash -c 'echo -e "a\tb"'
a	b
$ dash -c 'echo -e "a\tb"'
-e a	b
```

bash는 `-e`를 옵션으로 처리했고, dash는 문자열로 출력한 뒤 `\t`를 탭으로 해석했다. XSI 동작은 dash 쪽이다. 같은 페이지의 사용 안내 절(APPLICATION USAGE)은 이 자리에서 `printf`를 쓰라고 적어뒀다.

> New applications are encouraged to use *printf* instead of *echo*.

구현이 어느 판에 맞췄다고 주장하는지는 `getconf`가 답한다. 시스템 설정값을 조회하는 POSIX 명령어다.

```console
$ getconf _POSIX_VERSION
200809
$ getconf _XOPEN_VERSION
700
```

표준의 최신 판이 곧 손에 있는 시스템의 동작은 아니다. [2장 Conformance](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap02.html)는 POSIX.1-2024를 따르는 구현이 `_POSIX_VERSION`을 `202405`로, XSI까지 따르면 `_XOPEN_VERSION`을 `800`으로 두라고 요구한다. 위에서 나온 `200809`와 `700`은 그 앞 판인 POSIX.1-2008과 XSI Issue 7이다. 2024년에 나온 판을 근거로 코드를 쓰기 전에 대상 시스템이 몇을 답하는지 먼저 확인해야 한다.

## 혼동하기 쉬운 것

**POSIX를 따른다는 말과 UNIX 인증을 받았다는 말은 다르다.** 인증은 The Open Group이 상표로 운영하고, 통과한 제품만 등록부에 오른다. 2026년 9월 기준 [UNIX 03 등록부](https://www.opengroup.org/openbrand/register/xy.htm)에는 Apple macOS 26.0 Tahoe, IBM AIX, HPE HP-UX 11i V3가 있다. 인증은 규격 판마다 따로 있고, UNIX 03은 Single UNIX Specification Version 3을 기준으로 한 인증이다. 리눅스 커널과 주요 배포판은 표준을 대체로 따르지만 이 목록에 없다. 등록은 제품 버전 단위라 시간이 지나면 목록이 바뀐다.

유닉스 계열, POSIX 준수, UNIX 인증은 묶는 기준이 다르다. 유닉스 계열은 운영체제 자체가 UNIX에서 갈라졌거나 UNIX를 본떠 만들어졌는지, POSIX는 규칙을 지키는지, UNIX 인증은 시험을 통과했는지로 나눈다. 기준이 달라 셋은 대부분 겹치기만 하고, 확실한 포함 관계는 하나뿐이다. 인증 규격(SUS)이 POSIX 본문을 포함하므로 인증 제품은 POSIX도 따른다.

```text
+---------------------------------+
| Unix-like                       |
| V7 Unix, 4.2BSD                 |
|           +---------------------+-----------------------+
|           | Linux, FreeBSD      |                       |
|           |   +-----------------+---------------+       |
|           |   | UNIX certified  |               |       |
|           |   |                 |               |       |
|           |   |  macOS, AIX,    |   z/OS        |       |
|           |   |  HP-UX          |               |       |
|           |   |                 |               |       |
|           |   +-----------------+---------------+       |
+-----------+---------------------+                       |
            | Windows NT 3.1-4.0                          |
            |                              follows POSIX  |
            +---------------------------------------------+
```

인증 영역은 The Open Group 등록부 기준이다. macOS·AIX·HP-UX는 UNIX 03, z/OS는 [UNIX 95](https://www.opengroup.org/openbrand/register/xu.htm) 등록부에 올라 있다. UNIX 95는 [Single UNIX Specification Version 1](https://en.wikipedia.org/wiki/Single_UNIX_Specification)(1994)을 기준으로 한 인증이다. V7 Unix(1979)와 4.2BSD(1983)는 POSIX(1988)보다 먼저 나와 따를 표준이 없었다. Linux와 FreeBSD는 인증 없이 대체로 따르는 쪽이다. z/OS는 MVS 계보의 IBM 메인프레임 OS라 유닉스 계열이 아니지만, 구성요소인 z/OS UNIX System Services로 UNIX 인터페이스를 제공해 UNIX 95 인증을 받았다. Windows NT 3.1~4.0은 POSIX.1의 C 함수 부분만 구현한 [POSIX 하위 시스템](https://en.wikipedia.org/wiki/Microsoft_POSIX_subsystem)을 함께 실었다. 기본 설치에는 셸이 없었고, 명령어는 `pax` 하나뿐이었다.

**`/bin/sh`가 bash를 가리켜도 POSIX 셸이 되지는 않는다.** bash는 `sh`라는 이름으로 불리면 [시작 파일(셸이 켜질 때 읽는 `~/.profile` 같은 설정 파일) 처리를 옛 `sh`에 맞추고 POSIX 모드로 들어간다](https://www.gnu.org/software/bash/manual/bash.html#Bash-Startup-Files). [POSIX 모드](https://www.gnu.org/software/bash/manual/bash.html#Bash-POSIX-Mode)는 bash 고유 동작 가운데 표준과 충돌하는 것을 표준 쪽으로 맞추는 모드인데, `[[ ]]` 같은 확장 문법은 끄지 않는다. 아래 환경의 `sh`는 bash다.

```console
$ sh -c '[[ a == a* ]] && echo match'
match
$ bash --posix -c '[[ a == a* ]] && echo match'
match
```

`/bin/sh`에서 통과했다는 이유로 이식 가능하다고 판단하면 dash를 `sh`로 쓰는 시스템에서 깨진다.

## 구현체별 차이

| 구현 | 표준과의 관계 | 실무에서 걸리는 것 |
|---|---|---|
| 리눅스 (glibc, GNU coreutils) | 대체로 따르지만 UNIX 인증 등록부에는 없다 | GNU 확장이 기본값이라 표준 밖 옵션을 쓰기 쉽다 |
| macOS | UNIX 03 인증. 등록부에 올라 있다 | 유틸리티가 BSD 계열이라 GNU 옵션이 없다 |
| 윈도우 | 현재 윈도우는 네이티브로 POSIX 인터페이스를 제공하지 않는다 | 리눅스 커널을 돌리는 WSL, 윈도우 위에서 POSIX 함수를 흉내 내는 MSYS2·Cygwin 같은 별도 계층을 거친다 |

이식성이 필요한 스크립트라면 `#!/bin/sh`로 선언하고 dash처럼 확장이 적은 셸로 한 번 돌려보는 편이 빠르다. bash에서만 확인하면 확장을 썼는지 알 방법이 없다.

## 더 깊이

- [POSIX가 정의한 줄과 파일 끝 개행](/posts/posix-line-and-trailing-newline/)

## 참고

- [The Open Group Base Specifications Issue 8](https://pubs.opengroup.org/onlinepubs/9799919799/)
- [XBD 2. Conformance](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap02.html)
- [XCU sed](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/sed.html), [XCU echo](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/echo.html)
- [The Open Group UNIX 03 등록부](https://www.opengroup.org/openbrand/register/xy.htm), [UNIX 95 등록부](https://www.opengroup.org/openbrand/register/xu.htm)
- [The Austin Group](https://www.opengroup.org/austin/)
- [Bash Reference Manual — Bash POSIX Mode](https://www.gnu.org/software/bash/manual/bash.html#Bash-POSIX-Mode)
- [FreeBSD sed(1)](https://man.freebsd.org/cgi/man.cgi?query=sed&sektion=1)
