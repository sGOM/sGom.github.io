// 확장 함수는 무엇으로 컴파일되고, 어떤 규칙으로 고르는가.
//
// 실행:
//   kotlinc experiments/extension-function-dispatch/Ext.kt -d out
//   javap -p -c out/ExtKt.class          (바이트코드)
//   java -Dstdout.encoding=UTF-8 -cp "out;<kotlin-stdlib.jar>" ExtKt

open class Base
class Derived : Base()

// 1. 수신자 타입만 다른 확장 함수 둘.
fun Base.name() = "Base의 확장"
fun Derived.name() = "Derived의 확장"

// 2. 멤버 함수와 이름이 겹치는 확장 함수.
class Greeter {
    fun hello() = "멤버 함수"
}
fun Greeter.hello() = "확장 함수"

// 3. 상속 관계에서 멤버를 오버라이드하려는 확장 함수.
open class Animal {
    open fun speak() = "Animal.speak"
}
class Dog : Animal() {
    override fun speak() = "Dog.speak"
}
fun Animal.speakExt() = "Animal의 확장"
fun Dog.speakExt() = "Dog의 확장"

// 4. 널 가능 수신자.
fun String?.orEmptyLabel() = this ?: "(널)"

// 5. 확장 프로퍼티.
val Base.label: String get() = "Base의 확장 프로퍼티"

// 6. 제네릭 안에서 확장 함수를 부르면 무엇이 불리는가.
fun <T : Base> callInGeneric(x: T) = x.name()

fun main() {
    println("Kotlin ${KotlinVersion.CURRENT}, Java ${System.getProperty("java.version")}")

    println()
    println("=== 1. 정적 디스패치: 선언 타입이 고른다 ===")
    val d = Derived()
    val asBase: Base = d
    println("  Derived 타입 변수: ${d.name()}")
    println("  Base 타입 변수:    ${asBase.name()}   (담긴 값은 Derived)")

    println()
    println("=== 2. 멤버 함수가 확장 함수를 이긴다 ===")
    println("  Greeter().hello() = ${Greeter().hello()}")

    println()
    println("=== 3. 멤버는 동적, 확장은 정적 ===")
    val dog: Animal = Dog()
    println("  멤버 speak():     ${dog.speak()}      (담긴 값 기준)")
    println("  확장 speakExt():  ${dog.speakExt()}   (선언 타입 기준)")

    println()
    println("=== 4. 널 가능 수신자 ===")
    val s: String? = null
    println("  null.orEmptyLabel() = ${s.orEmptyLabel()}")

    println()
    println("=== 5. 제네릭 안에서는 상한이 기준이다 ===")
    println("  callInGeneric(Derived()) = ${callInGeneric(Derived())}")
    println("  직접 부르면            = ${Derived().name()}")

    println()
    println("=== 6. 확장 프로퍼티 ===")
    println("  asBase.label = ${asBase.label}")
}
