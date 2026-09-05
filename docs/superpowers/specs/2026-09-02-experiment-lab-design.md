# 실험용 DB 랩

작성일: 2026-09-02

## 배경

글에 실을 코드와 실행 결과를 확인할 때마다 `docker run --rm`으로 DB를 새로 띄우고 버렸다.
`docs/content-verification-2026-08-24.md`의 검증 환경 표가 그 흔적이다. PostgreSQL 16.15를 도커로 세워
플랜을 대조했고, MySQL 실험(`jdbc-driver-value-paths`)은 환경을 세우지 못해 끝내 돌리지 못했다.

문제는 두 가지다. 매번 이미지를 받고 초기화하는 비용, 그리고 실험 환경이 세션과 함께 사라져
독자도 글쓴이도 나중에 같은 결과를 재현할 수 없다는 점.

## 설계

**서버는 재사용하고, 데이터는 재사용하지 않는다.**

`experiments/compose.yml`에 PostgreSQL과 MySQL을 `restart: unless-stopped`로 상시 유지한다.
기동 비용만 아끼고 데이터는 실험마다 버린다. 컨테이너 하나를 계속 쓰면 남은 스키마·통계·autovacuum
상태가 쌓이고, 플래너 상태에 결과가 달린 글(`analyze-and-pg-stats`, `planner-row-estimation`,
`slow-query-after-restart`)은 반년 뒤 같은 스크립트로도 글에 실린 출력이 나오지 않는다.

실험 단위는 `experiments/<슬러그>/setup.sql` 하나다. 자기 DB를 `DROP`/`CREATE` 하는 것으로 시작하고,
스키마·시드·`ANALYZE`를 전부 담는다. 오케스트레이션 스크립트나 실행 래퍼는 두지 않는다.
`docker compose exec -T postgres psql < setup.sql` 한 줄이면 된다.

## 결정과 근거

| 결정 | 근거 |
|---|---|
| 이미지 태그 고정 (`postgres:16.15`, `mysql:8.4.11`) | 글이 인용하는 버전이 곧 이 태그다. `latest`면 인용 버전과 실제 실행 버전이 조용히 어긋난다 |
| 호스트 포트 `5433` / `3307` | 로컬 설치와 충돌하지 않는다. 저장소를 받은 사람이 그대로 띄울 수 있다 |
| 랜덤 고정 (`setseed()` / `RAND(42)`) | 자기완결성의 조건. 스크립트 하나로 같은 숫자가 나와야 재현이다 |
| `setup.sql`만 커밋 | 결과 로그는 낡는다. 결과는 글 본문과 `docs/content-verification-*.md`가 이미 담고 있다 |
| DB만 랩에 | JVM·Kotlin·Python은 로컬 툴체인으로 충분하다. 이미지가 무거워지는 값을 아직 못 한다 |
| profile 없음 | 서비스가 둘뿐이다. `up -d postgres`로 이미 하나만 뜬다 |
| H2 제외 | 서버가 아니라 JDBC로 붙는 임베디드 jar다. 컨테이너로 만들 것이 없다 |

## 검증

`postgres:16.15` 컨테이너에 `setseed(0.42)`로 시드한 1000행 테이블의 합을 두 번 계산해 같은 값
(`508.455527`)이 나오는 것을 확인했다. `SELECT version()`이 `PostgreSQL 16.15`, MySQL이 `8.4.11`로
태그와 일치하는 것도 함께 확인했다.

## 범위 밖

언어 툴체인 컨테이너, 실행 래퍼 스크립트, 결과 로그 체계. 필요해지면 그때 넣는다.
기존 발행 글에 「실험 환경」 절을 소급해 넣지 않는다(`docs/review-status.md`).
