// Fluoride C++ header test file — comprehensive syntax coverage
// Covers: class, struct, enum, enum class, union, namespace, template,
// concept, using, typedef, #define, friend, static_assert, access specifiers,
// constructor, destructor, operator overload, forward declaration, variable

#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <type_traits>
#include <vector>

// --- Preprocessor defines ---

#define HPP_VERSION 2

#define MAKE_TAG(a, b) (((a) << 8) | (b))

// --- Forward declarations ---

class Engine;

struct Vertex;

void global_init();

int global_compute(int a, int b, int c);

// --- Variables ---

extern int instance_count;

extern const char *build_tag;

constexpr int MAX_ENTITIES = 1024;

inline int default_port = 8080;

// --- Static assert ---

static_assert(sizeof(int) == 4, "int must be 4 bytes");

static_assert(sizeof(void *) >= 4, "pointer must be at least 4 bytes");

// --- Using aliases ---

using StringList = std::vector<std::string>;

using ByteBuffer = std::vector<uint8_t>;

// --- Typedef ---

typedef unsigned int uint;

typedef void (*SignalHandler)(int);

// --- Enum (unscoped) ---

enum Flags {
  FLAG_NONE = 0,
  FLAG_READ = 1,
  FLAG_WRITE = 2,
  FLAG_EXEC = 4,
};

// --- Enum class (scoped) ---

enum class LogLevel {
  Trace,
  Debug,
  Info,
  Warn,
  Error,
  Fatal,
};

enum class Direction {
  North,
  South,
  East,
  West,
};

// --- Union ---

union Variant {
  int32_t i;
  float f;
  char s[16];
};

// --- Struct (with fields) ---

struct Vertex {
  float x;
  float y;
  float z;
  float u;
  float v;
};

struct Color {
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
};

// --- Class with access specifiers, constructor, destructor, methods, fields
// ---

class Shape {
public:
  Shape();
  Shape(const std::string &name, int sides);
  virtual ~Shape();

  virtual double area() const = 0;
  virtual double perimeter() const = 0;
  std::string name() const;
  int sides() const;

  // Operator overload
  bool operator==(const Shape &other) const;

  // Friend declaration
  friend void print_shape(const Shape &s);

protected:
  std::string name_;
  int sides_;

private:
  int id_;
  static int next_id_;
};

// --- Derived class ---

class Circle : public Shape {
public:
  explicit Circle(double radius);
  ~Circle() override;

  double area() const override;
  double perimeter() const override;
  double radius() const;

private:
  double radius_;
};

// --- Concept ---

template <typename T>
concept Numeric = std::is_arithmetic_v<T>;

template <typename T>
concept Printable = requires(T t) { std::to_string(t); };

// --- Template function ---

template <typename T> T clamp(T val, T lo, T hi);

template <Numeric T> T lerp(T a, T b, double t);

// --- Template class (nestable, with methods and fields) ---

template <typename T> class Container {
public:
  Container();
  explicit Container(size_t capacity);
  ~Container();

  void push(const T &item);
  T pop();
  size_t size() const;
  bool empty() const;
  T &operator[](size_t index);

private:
  T *data_;
  size_t size_;
  size_t capacity_;
};

// --- Namespace (nestable, with children) ---

namespace math {

constexpr double PI = 3.14159265358979;

double radians(double degrees);

double degrees(double radians);

struct Matrix4 {
  float m[16];
};

enum class Axis {
  Y,
  X,
  Z,
};

} // namespace math

// --- Nested namespaces ---

namespace engine {
namespace detail {

struct InternalState {
  int tick;
  float dt;
};

void reset_state(InternalState &s);

} // namespace detail

class World {
public:
  World();
  void update(float dt);
  void render();

private:
  detail::InternalState state_;
};

} // namespace engine

// --- Namespace alias ---

namespace fs = std::filesystem;
