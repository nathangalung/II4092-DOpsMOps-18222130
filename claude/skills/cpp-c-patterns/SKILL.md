---
name: C/C++ Patterns & Best Practices
description: Use when writing or reviewing C/C++ code or its build setup — modern C++, memory safety, CMake+Ninja, sanitizers, testing
globs: ["**/*.cpp", "**/*.c", "**/*.h", "**/*.hpp", "**/CMakeLists.txt", "**/*.cmake", "**/Makefile", "**/conanfile.*", "**/vcpkg.json"]
---

# C/C++ Patterns & Best Practices

## Performance Build Setup

### Build System: CMake + Ninja
```cmake
cmake_minimum_required(VERSION 3.25)
project(myproject LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)  # For clangd LSP

# Compiler cache
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
endif()

# Fast linker
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=mold")
```
Build: `cmake -B build -G Ninja && cmake --build build -j$(nproc)`

### Package Management
- **vcpkg**: Microsoft, CMake integration, manifest mode (vcpkg.json)
- **Conan 2**: Python-based, flexible, good for custom builds
- Prefer vcpkg for CMake-heavy projects, Conan for complex dependency graphs

## Modern C++ Principles (C++17/20/23)

### RAII (Resource Acquisition Is Initialization)
"Every resource has an owner. The owner's destructor releases the resource."
- `std::unique_ptr<T>` for exclusive ownership (zero overhead)
- `std::shared_ptr<T>` for shared ownership (reference counting)
- `std::lock_guard` / `std::scoped_lock` for mutex locking
- Never `new`/`delete` directly — always use smart pointers or containers

### Rule of Zero / Five
- **Rule of Zero**: if a class manages no resources directly, don't write destructor/copy/move
- **Rule of Five**: if you write any of {destructor, copy constructor, copy assignment, move constructor, move assignment}, write ALL five
- Prefer Rule of Zero by using smart pointers and standard containers

### Value Semantics
- Prefer passing by value or const reference over raw pointers
- `std::string_view` for read-only string parameters (no allocation)
- `std::span<T>` for read-only array/vector views
- `std::optional<T>` instead of nullptr/sentinel values
- `std::variant<T...>` instead of unions (type-safe)
- `std::expected<T, E>` (C++23) for error handling without exceptions

### Move Semantics
- `std::move()` transfers ownership (leaves source in valid-but-unspecified state)
- Return by value: compiler applies RVO (Return Value Optimization) — don't `std::move` return values
- Pass `std::unique_ptr` by value to transfer ownership into a function
- Use `noexcept` on move operations (enables optimizations in containers)

## Safety Practices

### Sanitizers (Compile-Time Safety)
```cmake
# Debug build with sanitizers
target_compile_options(myapp PRIVATE
    $<$<CONFIG:Debug>:-fsanitize=address,undefined -fno-omit-frame-pointer>
)
target_link_options(myapp PRIVATE
    $<$<CONFIG:Debug>:-fsanitize=address,undefined>
)
```
- **ASan**: buffer overflow, use-after-free, memory leaks (2x slowdown)
- **UBSan**: undefined behavior — signed overflow, null deref, alignment
- **TSan**: data races in multithreaded code (5-15x slowdown, use separately)
- **MSan**: uninitialized memory reads (3x slowdown)
- Run ALL sanitizers in CI — they catch bugs that no test logic finds

### Static Analysis
- **clang-tidy**: 300+ checks, auto-fix, integrate with CMake
- **cppcheck**: fast, complements clang-tidy
- Config: `.clang-tidy` file with enabled check categories

## Concurrency Patterns

### std::jthread (C++20)
- Automatically joins on destruction (RAII for threads)
- Built-in stop_token for cooperative cancellation
- Prefer over `std::thread` in all cases

### Lock-Free Patterns
- `std::atomic<T>` for simple shared counters/flags
- `std::atomic_ref<T>` (C++20) for atomic access to non-atomic variables
- Lock-free queues: use proven libraries (boost::lockfree, folly::MPMCQueue)
- Rule: if you think you need lock-free code, you probably don't. Measure first

## Testing
- **Google Test (gtest)**: industry standard, rich matchers, death tests
- **Google Benchmark**: microbenchmarking framework
- **Catch2**: header-only alternative, simpler setup
- **doctest**: fastest compile times, header-only
- Test with sanitizers enabled in CI

## Common Pitfalls
- Undefined behavior is NEVER acceptable — "it works on my machine" means nothing
- Integer overflow in signed types is UB — use unsigned or check bounds
- Dangling references: never return reference to local variable
- `std::vector<bool>` is NOT a vector — use `std::vector<char>` or `std::bitset`
- `const` everything: parameters, member functions, variables — immutability by default
