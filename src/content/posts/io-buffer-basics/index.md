---
title: 자바 I/O 버퍼 — write 호출 100만 번을 123번으로
description: 버퍼가 무엇을 줄이는지, 버퍼 크기를 어떻게 정하는지 실측으로 확인한다
pubDate: 2026-08-25
category: "Java"
tags: ["기본개념", "Java", "IO", "버퍼"]
---

## 왜 필요한가

1바이트씩 100만 번 쓰는 코드는 4초가 걸린다. 같은 코드를 `BufferedOutputStream`으로 감싸면 18ms로 끝난다. 파일에 들어간 바이트 수는 100만으로 같다.

차이는 커널에 요청을 몇 번 보냈는지에 있다. 파일에 쓰려면 프로세스가 [시스템 호출](https://ko.wikipedia.org/wiki/%EC%8B%9C%EC%8A%A4%ED%85%9C_%ED%98%B8%EC%B6%9C)로 커널에 넘겨야 한다. 사용자 모드에서 커널 모드로 전환하고, 인자를 검증하고, 다시 돌아온다. 이 왕복 비용은 1바이트를 넘기든 8KB를 넘기든 거의 같다. 100만 번 나눠 보내면 왕복도 100만 번이다.

버퍼는 쓰기를 메모리에 모아뒀다가 일정량이 차면 한 번에 넘긴다. 왕복 횟수가 줄어들면 시간이 줄어든다.

## 핵심 정리

| 용어 | 무엇인가 |
|---|---|
| 버퍼 | 속도나 처리 단위가 다른 두 쪽 사이에 둔 임시 메모리 공간 |
| `flush` | 버퍼에 모인 것을 하위 대상으로 내보내고 버퍼를 비운다 |
| `close` | `flush` 후 자원을 반납한다. 닫지 않으면 버퍼에 남은 데이터가 사라진다 |
| 버퍼 크기 | 몇 바이트를 모았다가 내보낼지. `BufferedOutputStream`은 지정하지 않으면 8192바이트다(명세가 아니라 JDK 구현값) |
| 자동 flush | `System.out`처럼 개행마다 내보내도록 설정된 경우. 버퍼가 차기 전에도 나간다 |

## 예시

`BufferedOutputStream`은 `OutputStream`을 감싸는 [데코레이터](https://ko.wikipedia.org/wiki/%EB%8D%B0%EC%BD%94%EB%A0%88%EC%9D%B4%ED%84%B0_%ED%8C%A8%ED%84%B4)다. 감싸는 순서가 곧 데이터가 지나는 순서다.

```java
// 감싸지 않음: write 한 번이 곧 커널 요청 한 번
OutputStream raw = Files.newOutputStream(path);
raw.write('a');

// 감쌈: 8192바이트가 찰 때까지 메모리에 쌓는다
OutputStream buffered = new BufferedOutputStream(Files.newOutputStream(path));
buffered.write('a');   // 아직 파일에 없다
buffered.close();      // 여기서 나간다
```

버퍼에 쌓인 데이터는 내보내기 전까지 파일에 없다.

```java
BufferedWriter w = new BufferedWriter(new FileWriter(path.toFile()));
w.write("hello");
System.out.println("after write : " + Files.size(path) + " B");
w.flush();
System.out.println("after flush : " + Files.size(path) + " B");
w.close();
```

```
after write : 0 B
after flush : 5 B
```

`try-with-resources`를 쓰거나 `close`를 부르지 않으면 마지막 버퍼 내용이 유실된다. 버퍼가 만드는 가장 흔한 버그다.

## 직접 확인

버퍼 크기별로 하위 스트림에 실제 도달한 호출 횟수를 셌다. `FilterOutputStream`으로 감싸면 통과하는 호출을 가로챌 수 있다. `Files.newOutputStream`이 돌려주는 스트림에는 자체 버퍼가 없으므로, 여기서 센 호출은 시스템 호출과 1:1로 대응한다.

```java
static class Counting extends FilterOutputStream {
    long calls = 0;
    Counting(OutputStream out) { super(out); }
    @Override public void write(int b) throws IOException { calls++; out.write(b); }
    @Override public void write(byte[] b, int off, int len) throws IOException { calls++; out.write(b, off, len); }
}

static long[] run(Path p, int size) throws IOException {
    Counting c = new Counting(Files.newOutputStream(p));
    OutputStream out = size == 0 ? c : new BufferedOutputStream(c, size);
    long t = System.nanoTime();
    for (int i = 0; i < 1_000_000; i++) out.write('a');
    out.close();
    return new long[]{ (System.nanoTime() - t) / 1_000_000, c.calls };
}

run(p, 0); run(p, 8192);                                  // 예열
for (int s : new int[]{0, 1, 64, 512, 8192, 65536}) {     // 0은 버퍼 없음
    long[] r = run(p, s);
    System.out.printf("%-12s %10d %14d%n", s + " B", r[0], r[1]);
}
```

JDK 26, Windows 11, 1바이트씩 100만 번 쓴 결과다. 앞선 회차를 예열용으로 한 번 버렸다.

```
buffer         time(ms)    write calls
none               4019        1000000
1 B                4060        1000000
64 B                 82          15625
512 B                26           1954
8192 B               18            123
65536 B              17             16
size = 1000000
```

호출 횟수가 줄면 시간도 줄지만 같은 배율은 아니다. 8192바이트 버퍼는 호출을 8130배 줄이고 시간을 223배 줄였다. 시간이 호출만큼 줄지 않은 것은 버퍼에 복사하는 비용과 반복문 자체의 비용이 남기 때문이다.

크기 1인 버퍼는 버퍼가 없는 것과 같다. 1바이트가 찰 때마다 곧바로 내보내므로 호출 횟수가 100만으로 같다. **버퍼를 씌웠다는 사실이 아니라 버퍼가 얼마나 모으는지가 비용을 정한다.**

기본값이 8192인 것은 크기를 지정하지 않고 같은 실험을 돌려 역산했다.

```
default BufferedOutputStream -> write calls = 123
1000000 / 8192 = 122 remainder 576
```

122번이 가득 찬 버퍼를 내보내고, 마지막 576바이트를 `close`가 내보내 123번이다.

## 혼동하기 쉬운 것

버퍼와 캐시는 둘 다 메모리에 데이터를 들고 있지만 목적이 다르다.

| | 버퍼 | 캐시 |
|---|---|---|
| 목적 | 속도나 단위가 다른 두 쪽을 맞춘다 | 다시 쓰일 데이터를 가까이 둔다 |
| 데이터의 운명 | 내보내면 비운다 | 내보낸 뒤에도 남긴다 |
| 성능 이득의 근원 | 요청 횟수 감소 | 재요청 회피 |
| 비어 있을 때 | 정상 상태다 | 히트율이 0인 상태다 |

같은 메모리 영역이 둘 다인 경우도 있다. [리눅스의 페이지 캐시](https://www.kernel.org/doc/html/latest/admin-guide/mm/concepts.html)는 쓰기를 모아 뒀다가 나중에 기록하므로 버퍼처럼 동작하지만, 기록한 뒤에도 내용을 남겨 두므로 캐시이기도 하다.

## 언제 어떤 것을 쓰나

측정값에서 512바이트와 8192바이트의 차이는 8ms인데, 8192바이트와 65536바이트의 차이는 1ms로 측정 오차 수준까지 줄어든다. 버퍼를 여덟 배 키워도 더 나올 것이 남아 있지 않다는 뜻이다. 기본값을 바꾸려면 근거가 따로 있어야 한다.

키울 만한 경우는 한 번에 넘기는 단위가 이미 큰 쪽이다. 네트워크로 큰 파일을 흘려보내거나, 스토리지가 요청 하나를 처리하는 고정 비용이 클 때다. 반대로 줄일 이유는 지연이다. 버퍼가 클수록 데이터가 상대에게 도달하기까지 오래 붙들려 있는다. 로그처럼 즉시 보여야 하는 출력에 큰 버퍼를 씌우면 화면에 아무것도 안 나오다가 뭉텅이로 나온다.

## 참고

- [`BufferedOutputStream` (Java SE 26 API)](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/BufferedOutputStream.html)
- [`FilterOutputStream` (Java SE 26 API)](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/io/FilterOutputStream.html)
