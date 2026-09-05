// Kotlin 확장 함수를 Java에서 부르면 어떤 모양이 되는가.
//
// 실행:
//   kotlinc experiments/extension-function-dispatch/Ext.kt -d out
//   javac -cp "out;<kotlin-stdlib.jar>" -d out experiments/extension-function-dispatch/FromJava.java
//   java -cp "out;<kotlin-stdlib.jar>" FromJava
public class FromJava {
    public static void main(String[] args) {
        Derived d = new Derived();
        Base asBase = d;
        System.out.println("  ExtKt.name(Derived) = " + ExtKt.name(d));
        System.out.println("  ExtKt.name(Base)    = " + ExtKt.name(asBase));
        // 멤버에 가려진 확장 함수도 정적 메서드로는 남아 있다.
        System.out.println("  ExtKt.hello(Greeter)= " + ExtKt.hello(new Greeter()));
        System.out.println("  new Greeter().hello()= " + new Greeter().hello());
    }
}
