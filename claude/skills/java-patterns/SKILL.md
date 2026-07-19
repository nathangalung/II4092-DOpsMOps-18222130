---
name: Java Patterns & Best Practices
description: Use when writing or reviewing Java or Gradle builds — modern LTS features, records, sealed classes, virtual threads, GraalVM, testing
globs: ["**/*.java", "**/build.gradle*", "**/pom.xml", "**/settings.gradle*", "**/*.properties", "**/application.yml"]
---

# Java Patterns & Best Practices

## Performance Setup

### Runtime: Latest LTS JDK (21+) with ZGC
```bash
# SDKMAN for version management
sdk install java 21.0.5-graal  # GraalVM for native image
sdk use java 21.0.5-graal
```
JVM flags: `-XX:+UseZGC -XX:+ZGenerational` (sub-millisecond pauses)

### Build: Gradle with Build Cache
```kotlin
// settings.gradle.kts
buildCache { local { isEnabled = true } }
```
- Always `./gradlew` (wrapper), never system gradle
- Parallel: `org.gradle.parallel=true` in gradle.properties
- Daemon: enabled by default (warm JVM for subsequent builds)
- Build scan: `--scan` for performance analysis

### Native Image (GraalVM)
- 10-50ms startup vs 2-5 seconds JVM
- Lower memory footprint
- AOT compilation: `native-image -jar app.jar`
- Frameworks: Quarkus (best native support), Spring Boot 3 (GraalVM native)

## Modern Java (17-23) Features

### Records (Java 16+)
```java
// Immutable data carrier — replaces Lombok @Value
public record User(UUID id, String name, String email) {}
// Auto-generates: constructor, getters, equals, hashCode, toString
```

### Sealed Classes (Java 17+)
```java
// Exhaustive type hierarchies — compiler enforces all subtypes handled
public sealed interface Shape permits Circle, Rectangle, Triangle {}
public record Circle(double radius) implements Shape {}
```

### Pattern Matching (Java 21+)
```java
// Switch expressions with pattern matching
return switch (shape) {
    case Circle c -> Math.PI * c.radius() * c.radius();
    case Rectangle r -> r.width() * r.height();
    case Triangle t -> 0.5 * t.base() * t.height();
};
```

### Virtual Threads (Java 21+ — Project Loom)
```java
// Lightweight threads — millions concurrent, no thread pool tuning
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    executor.submit(() -> handleRequest(request));
}
```
- Replace thread pools for I/O-bound work
- Don't use for CPU-bound (use platform threads)
- Don't use synchronized blocks (use ReentrantLock) — virtual threads can't unmount from carrier during synchronized

### Structured Concurrency (Java 21+ Preview)
```java
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    var user = scope.fork(() -> fetchUser(id));
    var orders = scope.fork(() -> fetchOrders(id));
    scope.join().throwIfFailed();
    return new UserWithOrders(user.get(), orders.get());
}
```

## Design Principles

### Effective Java (Joshua Bloch) — Key Items
1. **Static factory methods over constructors**: `User.of(name, email)` — descriptive, cached, polymorphic
2. **Builder pattern for many constructor params**: when >4 parameters
3. **Prefer composition over inheritance**: delegate, don't extend
4. **Design for immutability**: records, unmodifiable collections, `final` fields
5. **Return Optional instead of null**: `Optional<User>` — no NPE, explicit absence
6. **Prefer interfaces to abstract classes**: default methods enable multiple inheritance of behavior
7. **Minimize mutability**: `final` by default, immutable collections (`List.of()`)

### Stream API Best Practices
- Prefer method references over lambdas when clear: `User::getName`
- Don't chain > 5 operations — extract to named method
- `toList()` (Java 16+) instead of `Collectors.toList()`
- Parallel streams: ONLY for CPU-bound work on large collections (>10K elements)

### Dependency Injection
- Constructor injection only (not field injection) — immutable, testable
- `@RequiredArgsConstructor` (Lombok) or explicit constructor
- Interface-based dependencies for testability

## Testing Patterns

### JUnit 5
```java
@Test
@DisplayName("should calculate area for circle")
void shouldCalculateCircleArea() {
    var circle = new Circle(5.0);
    assertThat(circle.area()).isCloseTo(78.54, within(0.01));
}
```

### Testing Stack
- **JUnit 5**: test framework (parametric tests, nested tests, extensions)
- **AssertJ**: fluent assertions (better than Hamcrest)
- **Mockito**: mocking (verify interactions, stub returns)
- **Testcontainers**: real databases/services in Docker
- **ArchUnit**: architecture tests (enforce layer dependencies, naming)

### Table-Driven Tests (Parameterized)
```java
@ParameterizedTest
@CsvSource({"1, 1", "2, 4", "3, 9"})
void shouldSquare(int input, int expected) {
    assertThat(square(input)).isEqualTo(expected);
}
```

## Common Anti-Patterns to Avoid
- **God class**: class with 1000+ lines doing everything — split by responsibility
- **Primitive obsession**: using String for email, int for money — use value objects/records
- **Null returns**: return `Optional<T>` or empty collection instead
- **Checked exceptions for control flow**: use unchecked exceptions for programmer errors
- **Mutable static state**: global mutable state is the root of concurrency bugs
- **String concatenation in loops**: use `StringBuilder` or `String.join()`
