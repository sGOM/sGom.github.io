---
title: 소켓 버퍼 — write가 리턴했다고 상대가 받은 것은 아니다
description: 송신 버퍼와 수신 버퍼가 각각 무엇을 붙들고, 수신 측이 읽지 않으면 송신이 어디서 막히는지 측정한다
pubDate: 2026-08-25
category: "네트워크"
tags: ["파고들기", "네트워크", "Java", "버퍼"]
---

## 전제

버퍼가 요청 횟수를 줄이는 원리는 [자바 I/O 버퍼](/posts/io-buffer-basics/)에서 다뤘다. 소켓의 버퍼는 목적이 하나 더 있다. 보내는 쪽과 받는 쪽의 속도를 맞추는 일이다.

## 왜 필요한가

`socket.getOutputStream().write(data)`가 리턴하면 무엇이 끝난 것인가. 상대 애플리케이션이 데이터를 받은 것도 아니고, 상대 호스트에 도착한 것도 아니다. 커널의 송신 버퍼에 복사된 것뿐이다.

이 구분이 필요한 이유는 실패 시점 때문이다. 연결이 끊겨도 이미 리턴한 `write`는 성공으로 남는다. 데이터가 송신 버퍼에서 사라져도 애플리케이션은 모른다. `write`가 성공했으니 전달됐다고 가정한 코드는 여기서 데이터를 잃는다.

## 구조

한쪽이 보낸 데이터는 네 구간을 지난다.

```
송신 앱  --write-->  송신 버퍼  --네트워크-->  수신 버퍼  --read-->  수신 앱
        (커널 복사)   (SO_SNDBUF)              (SO_RCVBUF)
```

`write`는 첫 화살표까지만 책임진다. 나머지는 커널의 TCP 스택이 상대의 사정을 봐 가며 진행한다.

## 동작 원리

수신 버퍼는 저장 공간이면서 동시에 상대에게 보내는 신호다. TCP는 수신 버퍼의 빈 공간을 윈도우 크기로 상대에게 알리고, 송신 측은 아직 확인받지 못한 데이터가 그 크기를 넘지 않도록 보낸다. 흐름 제어다.

[`ServerSocket.setReceiveBufferSize` 문서](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/net/ServerSocket.html)가 이 두 역할을 한 문장으로 적는다.

> The value of `SO_RCVBUF` is used both to set the size of the internal socket receive buffer, and to set the size of the TCP receive window that is advertised to the remote peer.

수신 앱이 `read`를 부르지 않으면 수신 버퍼가 차고, 광고 윈도우가 0이 된다. 송신 측은 더 보낼 수 없어 송신 버퍼에 쌓기 시작하고, 송신 버퍼마저 차면 그때서야 `write`가 블록된다. **버퍼 두 개가 다 차기 전까지 송신 앱은 상대가 멈춰 있다는 사실을 알 수 없다.**

## 직접 확인

수신 측이 `accept`만 하고 한 바이트도 읽지 않는 서버를 세운 뒤, 클라이언트에서 1KB씩 계속 보내며 어디서 멈추는지 쟀다. 1초 동안 누적 전송량이 변하지 않으면 블록된 것으로 판정했다.

```java
static final int CHUNK = 1024;

// 수신 버퍼는 bind 전에 걸어야 윈도우 스케일 협상에 반영된다
ServerSocket server = new ServerSocket();
server.setReceiveBufferSize(rcvBuf);
server.bind(new InetSocketAddress("127.0.0.1", 0));

Socket client = new Socket();
client.setSendBufferSize(sndBuf);
client.connect(server.getLocalSocketAddress());

// 서버는 accept만 하고 read를 부르지 않는다
Thread sender = new Thread(() -> {
    byte[] chunk = new byte[CHUNK];
    try {
        OutputStream out = client.getOutputStream();
        while (true) { out.write(chunk); sent.addAndGet(CHUNK); }
    } catch (IOException ignored) {}
});
```

JDK 26, Windows 11, 루프백 연결이다.

```
snd=65536  rcv=65536   blocked at  195584 B   (snd + 2*rcv = 196608)
snd=8192   rcv=8192    blocked at   24576 B   (snd + 2*rcv = 24576)
snd=65536  rcv=65536   blocked at  196608 B   (snd + 2*rcv = 196608)
snd=8192   rcv=65536   blocked at  139264 B   (snd + 2*rcv = 139264)
snd=65536  rcv=8192    blocked at   81920 B   (snd + 2*rcv = 81920)
```

첫 줄은 크기를 지정하지 않은 기본값이고, 이 환경에서는 양쪽 다 65536바이트였다. 네 줄은 계산값과 정확히 일치하고 첫 줄만 1024바이트 적다. 누적량은 `write`가 리턴한 뒤에 더하므로 마지막 한 청크만큼 적게 잡힐 수 있다.

읽어낼 것은 두 가지다. 첫째, 상대가 전혀 읽지 않아도 송신 측은 수십에서 수백 KB를 성공적으로 써넣는다. 둘째, 그 양은 두 버퍼가 함께 정한다. 송신 버퍼만 키운 다섯째 줄에서는 막히는 지점이 늘린 만큼만 늘고, 수신 버퍼만 키운 넷째 줄에서는 그 두 배가 는다.

수신 버퍼에 계수 2가 붙은 것은 Windows TCP 스택이 버퍼 공간을 회계하는 방식으로 보인다. 리눅스는 [`setsockopt`으로 받은 값을 두 배로 잡아](https://man7.org/linux/man-pages/man7/socket.7.html) 부가 정보 공간을 확보하므로 배수가 다르게 나온다. 배수 자체는 플랫폼을 따라가고, 어느 환경에서나 남는 것은 어느 한쪽만 키워도 그쪽 몫만큼만 늘어난다는 관계다.

## 경계 조건

수신 버퍼 크기는 연결 전에 정해야 64KB를 넘길 수 있다. 윈도우 크기 필드는 16비트라 그대로는 65535가 최대이고, 그 이상은 [RFC 7323](https://datatracker.ietf.org/doc/html/rfc7323)의 윈도우 스케일 옵션으로 표현한다. 이 옵션은 연결을 맺는 핸드셰이크에서만 협상된다.

같은 문서가 이 순서를 어겼을 때 무슨 일이 벌어지는지 적는다.

> Failure to do this will not cause an error, and the buffer size may be set to the requested value but the TCP receive window in sockets accepted from this ServerSocket will be no larger than 64K bytes.

오류가 나지 않는다는 점이 문제다. `getReceiveBufferSize()`는 요청한 값을 그대로 돌려주는데 실제 광고 윈도우는 64KB에 묶여 있다. 위 실험에서 `ServerSocket`을 인자 없는 생성자로 만들고 `setReceiveBufferSize` 뒤에 `bind`를 부른 것은 이 때문이다.

요청한 크기가 그대로 적용된다는 보장도 없다. 실제로 적용된 값은 `accept()`가 돌려준 `Socket`의 `getReceiveBufferSize()`로 읽어야 한다. `ServerSocket`에 건 값은 그 소켓들에 제안하는 기본값일 뿐이다.

## 언제 쓰고 언제 안 쓰나

기본값을 바꿀 이유는 대개 대역폭과 지연이 둘 다 큰 경로다. 한 번에 날려 놓을 수 있는 양은 대역폭 곱하기 왕복 지연이고, 이 값을 [대역폭 지연 곱](https://en.wikipedia.org/wiki/Bandwidth-delay_product)이라 한다. 수신 버퍼가 그보다 작으면 송신 측은 ACK를 기다리느라 회선을 놀린다. 1Gbps 회선에 왕복 지연 100ms면 12.5MB가 필요한데, 기본값 64KB로는 약 5Mbps에 그쳐 회선의 0.5%만 쓴다.

반대로 버퍼를 키우면 대기 중인 데이터가 늘어나 지연이 커진다. 요청 하나가 오가는 대화형 프로토콜에서는 이득이 없고, 연결 수만큼 메모리를 더 잡는다.

리눅스는 [`tcp_rmem`과 `tcp_wmem`](https://man7.org/linux/man-pages/man7/tcp.7.html) 범위 안에서 크기를 자동으로 조절한다. `setReceiveBufferSize`로 값을 명시하면 이 자동 조절이 꺼진다. 측정해서 근거가 나오기 전에는 건드리지 않는 편이 낫다.

## 참고

- [`ServerSocket` (Java SE 26 API)](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/net/ServerSocket.html)
- [RFC 9293: Transmission Control Protocol (TCP)](https://datatracker.ietf.org/doc/html/rfc9293)
- [RFC 7323: TCP Extensions for High Performance](https://datatracker.ietf.org/doc/html/rfc7323)
