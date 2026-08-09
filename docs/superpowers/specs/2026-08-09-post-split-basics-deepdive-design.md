# 기존 글을 기본개념과 파고들기로 분할

작성일: 2026-08-09

선행 작업: [좌측 목록을 2-depth 그룹 트리로](2026-08-09-group-tree-nav-design.md)

## 배경

기존 글 3편은 모두 `concept.md` 템플릿으로 쓰였다. 한 편 안에 기본 정의를 정리한 부분과
내부 동작을 파고든 부분이 함께 있다.

| 슬러그 | 「핵심 개념」이 담은 것 | 「동작 원리」 이후가 담은 것 |
|---|---|---|
| `transaction-isolation-levels` | 격리 수준 4단계 표, 이상 현상 3종 정의 | 표준과 InnoDB·PostgreSQL 구현의 차이 |
| `transactional-propagation` | 전파 속성 7종 표 | rollback-only 표시, 물리 트랜잭션 공유 |
| `transactional-self-invocation` | Spring AOP 프록시 기반 동작 | 자기 호출·`private`·`final`이 깨지는 이유와 해결책 |

그룹 축이 생기면 한 편이 두 그룹에 걸친다. 글을 성격대로 나눈다.

## 분할

3편을 6편으로 나눈다. 1:1 대응이다.

| 기본개념 (신규) | 파고들기 (기존 슬러그 유지) |
|---|---|
| 트랜잭션 격리 수준과 이상 현상<br>`isolation-levels-and-anomalies` · 데이터베이스 | 격리 수준은 DBMS마다 다르게 동작한다<br>`transaction-isolation-levels` · 데이터베이스 |
| @Transactional 전파 속성<br>`transactional-propagation-options` · Spring | 예외를 잡았는데 왜 롤백될까<br>`transactional-propagation` · Spring |
| Spring AOP 프록시<br>`spring-aop-proxy` · Spring | 같은 클래스 안에서 부른 @Transactional은 왜 동작하지 않을까<br>`transactional-self-invocation` · Spring |

**기존 슬러그는 파고들기가 가져간다.** 세 편의 제목과 주제가 모두 심화 쪽이라 URL이 그대로
맞고, 이미 발행된 주소도 깨지지 않는다. 기본개념 3편이 새 슬러그를 받는다.

카테고리와 그룹 외 태그는 원본을 따른다. 기본개념 글은 원본의 「핵심 개념」이 다루는 범위에
맞춰 태그를 줄인다. 예를 들어 `spring-aop-proxy`에는 `트랜잭션` 태그를 넣지 않는다.

### 「Spring AOP 프록시」는 보강이 필요하다

원본의 「핵심 개념」은 한 문단이다. 그대로 떼면 기본개념 글로 성립하지 않는다.
JDK 동적 프록시와 CGLIB의 차이를 표로 더한다. 인터페이스 유무에 따른 선택, 상속 기반이라
`private`·`final`을 다루지 못한다는 제약, Kotlin에서 `kotlin-spring` 플러그인이 필요한 이유까지가
기본개념 범위다. 여섯 편 중 새로 쓰는 분량이 있는 유일한 글이다.

## 상호 링크

frontmatter 필드를 새로 만들지 않는다. 본문 링크로 한다. 템플릿에 링크 섹션이 고정돼 있으면
빠뜨릴 일이 없고, 스키마와 컴포넌트를 건드리지 않아도 된다.

- 기본개념 글 → 끝의 「더 깊이」 섹션에서 대응 파고들기 글로
- 파고들기 글 → 앞의 「전제」 섹션에서 대응 기본개념 글로

경로는 `/posts/<슬러그>/` 형식의 루트 상대 경로를 쓴다.

## 템플릿 분리

`templates/concept.md`를 없애고 두 개로 나눈다. `templates/troubleshooting.md`는 오답노트용으로
그대로 둔다.

```
templates/basics.md           기본개념
  왜 필요한가 → 핵심 개념(표) → 예시 → 더 깊이 (파고들기 링크)

templates/deep-dive.md        파고들기
  전제 (기본개념 링크) → 왜 필요한가 → 동작 원리 → 직접 확인
  → 언제 쓰고 언제 안 쓰나 → 참고

templates/troubleshooting.md  오답노트 (변경 없음)
```

각 템플릿 frontmatter의 `tags` 첫 항목에 해당 그룹 태그를 미리 적어 둔다.

`CLAUDE.md` 1절의 템플릿 고르기 항목을 세 갈래로 고쳐 쓴다.

- 기본이 되는 개념을 표와 짧은 설명으로 정리 → `templates/basics.md`
- 기본개념으로 간단히 설명하기 어렵거나 더 깊이 다룸 → `templates/deep-dive.md`
- 실제로 겪은 문제 상황의 파악과 해결 과정 → `templates/troubleshooting.md`

## 절차

`CLAUDE.md` 6절을 따른다. 여섯 편 모두 검수 대상이다.

1. 템플릿 3종을 정리하고 `CLAUDE.md`를 고친다. 여기까지는 글이 아니므로 바로 커밋한다.
2. 여섯 편을 `src/content/posts/_drafts/<슬러그>/index.md`에 `draft: true`로 쓴다.
   기존 3편은 원본을 그대로 두고 초안 쪽에서 작업한다.
3. `npm run dev`를 띄우고 검수를 요청한다. **여기서 멈춘다.**
4. 승인되면 기본개념 3편은 발행 위치로 옮기고, 파고들기 3편은 기존 파일을 덮어쓴다.
   `draft: true`를 지우고 `npm run dev` · `npm test` · `npm run build`를 돌린 뒤 커밋한다.

원본에서 옮겨 온 코드와 실행 결과는 원본과 대조해 확인한 뒤 검수를 요청한다.

`updatedDate`는 기존 3편에만 넣는다. 내용이 줄어드는 개정이다. `pubDate`는 원본 값을 유지한다.

## 검증

- `npm run build`가 통과한다. 여섯 편 모두 그룹 태그가 정확히 하나다.
- 좌측 트리가 `기본개념 3 / 파고들기 3 / 오답노트 0`으로 나온다.
- 여섯 편의 상호 링크가 양방향으로 연결되고 404가 없다.
- 파고들기 3편의 기존 URL이 그대로 열린다.

## 범위 밖

- 오답노트 글 작성. 해당하는 글이 아직 없다
- 원본 3편의 코드 예제 재작성. 옮기기만 한다
- 리다이렉트 설정. 기존 URL이 유지되므로 필요 없다
