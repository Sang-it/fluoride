// Fluoride C++ test file — comprehensive syntax coverage
// Covers: function, constructor/destructor, variable, struct, class, enum,
// enum class, union, namespace, template, concept, using, typedef, #define,
// friend, static_assert, access specifiers, expression

#include <iostream>
#include <string>
#include <vector>
#include <filesystem>

// --- Preprocessor defines ---

#define MAX_SIZE 100

#define DEFAULT_NAME "unknown"

#define SQUARE(x) ((x) * (x))

#define MAX(a, b) ((a) > (b) ? (a) : (b))

// --- Forward declarations ---

void greet(const std::string& name);

void greet(const std::string& name) {
    std::cout << "Hello, " << name << std::endl;
}

int add(int a, int b);

// --- Functions ---

int add(int a, int b) {
    return a + b;
}

int no_args() {
    return 42;
}

int multi_args(int a, int b, int c, int d) {
    return a + b + c + d;
}

// --- Variables ---

int global_counter = 0;

const int MAX_RETRIES = 3;

// --- Structs ---

std::string app_name = "fluoride";

struct Point {
    int y;
    int x;
};

struct Color {
    unsigned char r;
    unsigned char g;
    unsigned char b;
    unsigned char a;
};

struct Config {
    bool debug;
    int timeout;
    std::string host;
    int port;
};

// --- Enums ---

enum Direction {
    DIR_UP,
    DIR_DOWN,
    DIR_LEFT,
    DIR_RIGHT,
};

// --- Scoped enums (enum class) ---

enum class LogLevel {
    Debug,
    Info,
    Warn,
    Error,
};

enum class Status {
    OK,
    Pending,
    Failed,
};

// --- Unions ---

union IntOrFloat {
    int i;
    float f;
};

// --- Class with access specifiers ---

class Animal {
public:
    Animal(const std::string& name) : name_(name) {}

    virtual ~Animal() {}

    virtual void speak() const {
        std::cout << name_ << " makes a sound" << std::endl;
    }

    std::string getName() const {
        return name_;
    }

    int getAge() const {
        return age_;
    }

protected:
    std::string name_;

    int age_ = 0;

private:
    int id_ = 0;
};

// --- Derived class ---

class Dog : public Animal {
public:
    Dog(const std::string& name, const std::string& breed)
        : Animal(name), breed_(breed) {}

    void speak() const override {
        std::cout << name_ << " barks" << std::endl;
    }

    std::string getBreed() const {
        return breed_;
    }

private:
    std::string breed_;
};

// --- Class with friend, static_assert, using ---

class Container {
public:
    Container() = default;

    void add(int value) {
        data_.push_back(value);
    }

    int size() const {
        return static_cast<int>(data_.size());
    }

    friend class Inspector;

    using value_type = int;

private:
    std::vector<int> data_;

    static_assert(sizeof(int) == 4, "int must be 4 bytes");
};

// --- Namespace ---

namespace math {
    int add(int a, int b) {
        return a + b;
    }

    double power(double base, int exp) {
        double result = 1;
        for (int i = 0; i < exp; i++) {
            result *= base;
        }
        return result;
    }

    struct Vector {
        double x;
        double y;
        double z;
    };

    enum class Operation {
        Add,
        Subtract,
        Multiply,
        Divide,
    };
}

// --- Nested namespace ---

namespace utils {
    namespace math {
        int abs(int x) {
            return x < 0 ? -x : x;
        }
    }

    namespace strings {
        std::string trim(const std::string& s) {
            return s;
        }

        std::string to_upper(const std::string& s) {
            std::string result = s;
            for (char& c : result) {
                c = std::toupper(c);
            }
            return result;
        }
    }
}

// --- Namespace alias ---

namespace fs = std::filesystem;

// --- Using alias ---

using MyInt = int;

using StringVec = std::vector<std::string>;

// --- Templates ---

template<typename T>
T max_val(T a, T b) {
    return a > b ? a : b;
}

template<typename T>
class Box {
public:
    Box(T value) : value_(value) {}

    T get() const {
        return value_;
    }

    void set(T new_value) {
        value_ = new_value;
    }

private:
    T value_;
};

// --- Typedef ---

typedef unsigned int uint;

typedef void (*Callback)(int, const char*);

// --- Static assert ---

static_assert(sizeof(int) == 4, "int must be 4 bytes");

// --- Main ---

int main() {
    Animal animal("Buddy");
    animal.speak();

    Dog dog("Rex", "Shepherd");
    dog.speak();

    Container container;
    container.add(42);
    std::cout << "size: " << container.size() << std::endl;

    std::cout << math::add(2, 3) << std::endl;
    std::cout << utils::strings::to_upper("hello") << std::endl;

    Box<int> box(10);
    std::cout << box.get() << std::endl;

    greet("World");

    return 0;
}
