---
title: 양방향 매핑 엔티티를 그대로 반환하면 어디서 터지는가
description: 순환 참조, 지연 로딩 프록시, N+1을 Spring Boot 4에서 재현하고 대응책을 견줬다
pubDate: 2026-08-25
category: "Spring"
tags: ["파고들기", "JPA", "Hibernate", "Jackson", "직렬화"]
---

## 무엇이 문제인가

`@OneToMany`와 `@ManyToOne`을 양쪽에 걸어 두면 객체 그래프에 순환이 생긴다. `Team`이 `members`를 갖고, 각 `Member`가 다시 `team`을 갖는다. 이 상태로 컨트롤러가 엔티티를 그대로 반환하면 순환 참조, 지연 로딩 프록시, N+1이 차례로 문제가 된다. 앞의 둘은 응답을 만드는 경로에서 드러나고, N+1은 그 경로가 예외로 끊기기 때문에 트랜잭션 안에서 따로 재야 보인다.

셋은 증상이 서로 달라서 하나를 막아도 나머지가 남는다. 순환 참조를 `@JsonIgnore`로 끊었더니 이번엔 `LazyInitializationException`이 나고, 그것까지 막았더니 응답에서 필요한 필드가 사라진다. 각각이 어디서 발생하고 어떤 대응이 무엇까지 막는지 재현해서 확인했다.

측정 환경은 Spring Boot 4.0.1, Hibernate 7.2.0.Final, Jackson 3.0.3, Kotlin 2.2.21, H2 인메모리다. `spring.jpa.open-in-view`는 `false`다.

## 핵심 개념

**연관관계의 주인**은 외래 키를 관리하는 쪽이다. 아래에서는 `team_id` 컬럼을 가진 `Member`가 주인이고, `Team.members`는 `mappedBy`로 걸린 반대편이다. 반대편 컬렉션은 DB에 아무 열도 만들지 않지만, 객체 그래프 위에는 실재하는 참조로 남는다. 순환은 여기서 생긴다.

**영속성 컨텍스트의 경계**는 트랜잭션의 경계다. `open-in-view`가 `false`면 가장 바깥 `@Transactional` 메서드가 반환하는 순간 영속성 컨텍스트가 닫힌다. 서비스가 돌려준 엔티티는 그 시점부터 [준영속(detached)](https://docs.hibernate.org/orm/7.2/userguide/html_single/Hibernate_User_Guide.html#pc-detach) 상태다.

```kotlin
@Entity
@Table(name = "team")
class Team(
    @Column(nullable = false)
    var name: String,
) {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long? = null

    @OneToMany(mappedBy = "team", cascade = [CascadeType.ALL])
    val members: MutableList<Member> = mutableListOf()

    fun addMember(member: Member) {
        members += member
        member.team = this
    }
}

@Entity
@Table(name = "member")
class Member(
    @Column(nullable = false)
    var name: String,
) {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long? = null

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "team_id")
    var team: Team? = null
}
```

## 동작 원리

### 순환을 끊을 조건이 직렬화기에 없다

Jackson은 객체 그래프를 깊이 우선으로 따라가며 getter를 호출한다. `Team`을 쓰다가 `members`를 만나면 각 `Member`를 쓰고, 거기서 `team`을 만나면 다시 `Team`을 쓴다. 방문한 객체를 기억하지 않으므로 이 왕복에는 끝이 없다.

멈추는 지점은 Jackson이 스스로 건 한도다. jackson-core는 [`StreamWriteConstraints`](https://javadoc.io/doc/tools.jackson.core/jackson-core/3.0.3/tools.jackson.core/tools/jackson/core/StreamWriteConstraints.html)로 출력 문서의 최대 중첩 깊이를 제한하고, jackson-core 3의 기본값은 500이다. 깊이가 501이 되는 순간 `StreamConstraintsException`이 난다.

### 프록시는 세션을 잃어도 참조로 남는다

`@ManyToOne(fetch = FetchType.LAZY)`는 `Team`을 조회하지 않는다는 뜻이지, `team` 필드를 비워 둔다는 뜻이 아니다. Hibernate는 `Team`을 상속한 프록시 인스턴스를 만들어 넣는다. 프록시는 실제 값이 필요해지는 첫 접근에서 자기를 만든 세션으로 SELECT를 보낸다.

트랜잭션이 끝나면 그 세션이 닫힌다. 프록시는 그대로 남지만 조회할 통로가 없다. 이 상태에서 `team.name`을 읽으면 `LazyInitializationException`이 난다. 직렬화기가 그 getter를 대신 호출해도 결과는 같고, 예외를 Jackson의 `DatabindException`이 감쌀 뿐이다.

### 컬렉션 접근이 SELECT를 부른다

`Team.members`도 기본이 지연 로딩이다. 팀 목록을 조회한 뒤 각 팀의 `members`를 건드리면 팀 하나당 SELECT가 한 번씩 더 나간다. 목록 1회에 팀 수만큼이 붙는다.

## 직접 확인

전체 코드는 [spring-transactional-test](https://github.com/sGOM/spring-transactional-test)의 `BidirectionalEntityReturnTest`에 있다. 서비스는 트랜잭션 안에서 조회만 하고 엔티티를 그대로 돌려준다.

```kotlin
@Service
class BidirectionalEntityService(
    private val teamRepository: TeamRepository,
    private val memberRepository: MemberRepository,
) {
    @Transactional(readOnly = true)
    fun findTeamWithMembers(id: Long): Team = teamRepository.findWithMembers(id)!!

    @Transactional(readOnly = true)
    fun findMember(id: Long): Member = memberRepository.findById(id).orElseThrow()

    @Transactional(readOnly = true)
    fun findMemberAsDto(id: Long): MemberDto =
        memberRepository.findById(id).orElseThrow().let { MemberDto(it.id!!, it.name, it.team!!.name) }
}
```

### 순환 참조

`join fetch`로 컬렉션까지 채운 `Team`을 직렬화한다.

```kotlin
val exception = shouldThrow<StreamConstraintsException> {
    objectMapper.writeValueAsString(service.findTeamWithMembers(teamId))
}

exception.message!! shouldContain "Document nesting depth (501) exceeds the maximum allowed (500"
exception.message!! shouldContain "Team[\"members\"]"
```

예외 메시지는 왕복한 경로를 그대로 적어 준다. 아래는 실제 출력의 앞부분이다. 줄바꿈을 넣고 반복 구간을 줄였다. 마지막 줄은 생략 표시이고, 전체 메시지는 25,139자다.

```
Document nesting depth (501) exceeds the maximum allowed
(500, from `StreamWriteConstraints.getMaxNestingDepth()`)
(through reference chain:
 org.example.transactiontest.entity.Team["members"]
 ->org.hibernate.collection.spi.PersistentBag[0]
 ->org.example.transactiontest.entity.Member["team"]
 ->org.example.transactiontest.entity.Team["members"]
 ->org.hibernate.collection.spi.PersistentBag[0]
 ->org.example.transactiontest.entity.Member["team"]
 -> ... (같은 왕복이 끝까지 반복)
```

`StackOverflowError`가 아니라 깊이 제한에 먼저 걸렸다. 어느 쪽으로 끝나든 응답은 만들어지지 않는다.

### 지연 로딩 프록시

`team`을 건드리지 않은 채 `Member`만 받아 온다.

```kotlin
val member = service.findMember(memberId)

(member.team is HibernateProxy).shouldBeTrue()
Hibernate.isInitialized(member.team).shouldBeFalse()

val exception = shouldThrow<LazyInitializationException> { member.team!!.name }
exception.message!! shouldContain "Could not initialize proxy"
exception.message!! shouldContain "no session"
```

`member.team!!::class.java.name`을 찍으면 `org.example.transactiontest.entity.Team$HibernateProxy`가 나온다. 예외 메시지는 `Could not initialize proxy [Team#1] - no session`이다.

같은 `Member`를 직렬화하면 예외 타입만 바뀐다.

```kotlin
val exception = shouldThrow<DatabindException> {
    objectMapper.writeValueAsString(service.findMember(memberId))
}

(exception.cause is LazyInitializationException).shouldBeTrue()
```

예외가 서비스가 아니라 직렬화기 안에서 발생한다는 점이 다르다. 스택 트레이스의 위쪽은 Jackson이고, 원인만 Hibernate 것이다.

### N+1

응답을 만드는 경로에서는 프록시 예외가 먼저 나므로 N+1까지 가지 못한다. 그래서 트랜잭션 안에서 따로 쟀다. 팀 3개를 넣고 목록을 조회한 뒤 각 팀의 `members`를 건드린다. 쿼리 수는 Hibernate 통계로 센다.

```kotlin
statistics.clear()
val touched = txExecutor.newTransaction(readOnly = true) {
    teamRepository.findAll().sumOf { it.members.size }
}

touched shouldBe 5
statistics.prepareStatementCount shouldBe 4
```

목록 1회에 팀마다 1회씩 3회가 붙어 4회다. 팀이 100개면 101회가 된다.

## 대안과 트레이드오프

세 가지를 같은 테스트 안에서 견줬다. `@JsonIgnore`는 엔티티를 고치는 대신 [MixIn](https://github.com/FasterXML/jackson-docs/wiki/JacksonMixInAnnotations)으로 주입했다. 애노테이션을 클래스에 직접 붙인 것과 효과는 같다.

Jackson 3의 `ObjectMapper`는 불변이라 MixIn을 나중에 끼워 넣지 못한다. 매퍼를 다시 세워야 한다.

```kotlin
private fun mapperIgnoring(target: Class<*>, mixIn: Class<*>): ObjectMapper =
    (objectMapper as JsonMapper).rebuild().addMixIn(target, mixIn).build()
```

### `Team.members`에 붙이는 경우

```kotlin
val mapper = mapperIgnoring(Team::class.java, IgnoreMembers::class.java)

val json = mapper.writeValueAsString(service.findTeamWithMembers(teamId))
json shouldContain "\"name\":\"백엔드\""
json shouldNotContain "members"

shouldThrow<DatabindException> { mapper.writeValueAsString(service.findMember(memberId)) }
```

순환은 끊긴다. 하지만 `Member`를 직렬화하는 경로는 `team` 프록시를 그대로 지나가므로 `DatabindException`이 그대로 난다. 첫 번째 문제만 막았다.

### `Member.team`에 붙이는 경우

```kotlin
val mapper = mapperIgnoring(Member::class.java, IgnoreTeam::class.java)

mapper.writeValueAsString(service.findTeamWithMembers(teamId)) shouldContain "\"name\":\"헌\""

val memberJson = mapper.writeValueAsString(service.findMember(memberId))
memberJson shouldNotContain "team"
```

순환도 프록시 접근도 없어진다. 대가는 `Member`를 싣는 **모든** 응답에서 팀 정보가 사라진다는 것이다. 회원 상세 화면에 팀 이름을 넣어야 하는 순간 막힌다. 애노테이션이 클래스에 붙어 있으므로 엔티티만 보고는 특정 API에서 되돌릴 수 없다. 매퍼를 따로 세워 MixIn을 걸거나 `@JsonView`를 쓰는 길은 남지만, 그 시점이면 응답 모양을 엔티티 밖에서 관리하기 시작한 셈이다.

`@JsonManagedReference`/`@JsonBackReference`도 직렬화에서 한쪽을 끊는 점은 같고, 역직렬화 때 관계를 복원한다는 차이가 있다. 이 글에서는 재현하지 않았다.

### DTO로 옮기는 경우

```kotlin
val json = objectMapper.writeValueAsString(service.findMemberAsDto(memberId))

json shouldBe """{"id":$memberId,"name":"헌","teamName":"백엔드"}"""
```

변환이 트랜잭션 안에서 일어나므로 프록시는 그 자리에서 초기화되고, DTO에는 순환도 프록시도 남지 않는다. 응답 모양이 엔티티와 분리되므로 API마다 다른 필드 조합을 만들 수 있다.

비용은 클래스와 변환 코드가 는다는 것이고, 프록시를 그 자리에서 초기화하므로 SELECT도 한 번 더 나간다. 그리고 변환을 트랜잭션 밖에서 하면 아무것도 해결되지 않는다. 옮기는 위치가 DTO를 쓰는 것 자체보다 중요하다.

| 대응 | 순환 참조 | 프록시 접근 | 응답 모양 |
|---|---|---|---|
| `Team.members`에 `@JsonIgnore` | 막음 | 그대로 | 컬렉션이 모든 응답에서 빠짐 |
| `Member.team`에 `@JsonIgnore` | 막음 | 막음 | 팀 정보가 모든 응답에서 빠짐 |
| 트랜잭션 안에서 DTO 변환 | 막음 | 막음 | API마다 지정 |

## 경계 조건

**Kotlin 엔티티가 `final`이면 지연 로딩이 조용히 무효가 된다.** Hibernate는 엔티티 클래스를 상속해 프록시를 만드는데, Kotlin 클래스는 기본이 `final`이라 상속할 수 없다. allopen을 걸기 전에 같은 코드를 돌리면 `member.team`이 프록시가 아닌 `Team` 실인스턴스였고 `Hibernate.isInitialized`가 `true`였다. `@ManyToOne(fetch = FetchType.LAZY)`가 즉시 로딩으로 동작한 것이다. 예외는 나지 않는다.

```kotlin
allOpen {
    annotation("jakarta.persistence.Entity")
    annotation("jakarta.persistence.MappedSuperclass")
    annotation("jakarta.persistence.Embeddable")
}
```

이 설정을 넣은 뒤에야 `Team$HibernateProxy`가 나오고 위의 `LazyInitializationException`이 재현된다.

**`open-in-view`를 켜면 증상이 바뀌는 것으로 보인다.** 영속성 컨텍스트가 요청 끝까지 열려 있으므로 프록시가 직렬화 시점에도 초기화되고, `Member` 단독 경로에서는 `LazyInitializationException` 대신 추가 SELECT가 나갈 것으로 보인다. 예외가 없어진 만큼 문제는 눈에 덜 띈다. 다만 순환 참조 쪽은 달라지지 않는다. `Team`을 반환하는 경로는 OSIV와 무관하게 `StreamConstraintsException`으로 끝난다. 이 글에서 측정한 값은 모두 `open-in-view: false` 기준이고, 켠 상태는 재현하지 않았다.

**예외 타입은 Jackson 버전에 묶인다.** 위 메시지는 Jackson 3.0.3에서 관측한 것이다. 중첩 깊이 제한이 없거나 상한이 더 큰 버전에서는 스택이 먼저 넘칠 수 있다.

## 참고

- [Hibernate ORM 7.2 User Guide, Fetching](https://docs.hibernate.org/orm/7.2/userguide/html_single/Hibernate_User_Guide.html#fetching)
- [Jackson `StreamWriteConstraints`](https://javadoc.io/doc/tools.jackson.core/jackson-core/3.0.3/tools.jackson.core/tools/jackson/core/StreamWriteConstraints.html)
- [Kotlin all-open compiler plugin](https://kotlinlang.org/docs/all-open-plugin.html)
- [Spring Boot `spring.jpa.open-in-view`](https://docs.spring.io/spring-boot/appendix/application-properties/index.html#application-properties.data.spring.jpa.open-in-view)
