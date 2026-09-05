# 실험 랩

글에 실을 코드와 실행 결과를 재현하는 DB 환경. 서버는 상시 유지하고, 실험마다 자기 DB를 만들고 지운다.

## 왜 DB를 매번 새로 만드나

컨테이너 하나를 계속 쓰면 실험이 남긴 스키마·통계·autovacuum 상태가 쌓인다. 플래너 상태에 결과가 달린 글
(`analyze-and-pg-stats`, `planner-row-estimation`, `slow-query-after-restart`)은 그 잔여 상태 때문에 반년 뒤 같은
스크립트를 돌려도 글에 실린 출력이 나오지 않는다. 서버 기동 비용만 아끼고 데이터는 매번 버린다.

## 쓰는 법

```bash
# 서버 기동 (한 번만. restart: unless-stopped 라 재부팅 후에도 살아 있다)
docker compose -f experiments/compose.yml up -d postgres

# 실험 실행
docker compose -f experiments/compose.yml exec -T postgres psql -U postgres < experiments/<슬러그>/setup.sql

# MySQL
docker compose -f experiments/compose.yml up -d mysql
docker compose -f experiments/compose.yml exec -T mysql mysql -uroot -plab < experiments/<슬러그>/setup.sql
```

호스트 포트는 기본값을 비켜 쓴다. PostgreSQL `5433`, MySQL `3307`. 로컬에 같은 DB가 설치돼 있어도 충돌하지 않는다.

## setup.sql 규칙

**스크립트 하나만 돌려서 결과가 재현돼야 한다.** 이 저장소를 받은 사람이 같은 명령으로 같은 숫자를 봐야 한다.

1. `DROP DATABASE IF EXISTS <슬러그>;` / `CREATE DATABASE <슬러그>;` 로 시작한다. 슬러그는 글 디렉터리 이름과 맞춘다.
2. 스키마·시드 데이터·`ANALYZE`까지 스크립트 안에 전부 넣는다. 남아 있는 상태에 기대지 않는다.
3. 랜덤이 필요하면 고정한다. PostgreSQL은 `SELECT setseed(0.42);`, MySQL은 `RAND(42)`.
4. 버전에 결과가 달리면 스크립트 첫머리에 `SELECT version();`을 넣어 출력에 남긴다.

`compose.yml`의 이미지 태그는 고정돼 있다. `docs/content-verification-2026-08-24.md`가 인용하는 버전이 곧 이 태그다.
태그를 올리면 글에 실린 버전 표기와 어긋나므로, 올릴 때는 영향받는 글을 같이 확인한다.

## 저장소에 넣는 것

실험 스크립트(`experiments/<슬러그>/setup.sql`)만 커밋한다. 실행 결과 로그는 넣지 않는다. 결과는 글 본문이나
`docs/content-verification-*.md`에 쓴다.
