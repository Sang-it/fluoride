// Fluoride C test file — comprehensive syntax coverage
// Covers: function, forward declaration, variable, struct, enum, union,
// typedef, #define, expression

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// --- Preprocessor defines ---

#define DEFAULT_NAME "unknown"

#define MAX_SIZE 100

#define MAX(a, b) ((a) > (b) ? (a) : (b))

#define SQUARE(x) ((x) * (x))

#define CLAMP(val, lo, hi) ((val) < (lo) ? (lo) : ((val) > (hi) ? (hi) : (val)))

// --- Forward declarations ---

void greet(const char *name);

int add(int a, int b);

void process(void);

// --- Functions ---

void greet(const char *name) {
    printf("Hello, %s\n", name);
}

int add(int a, int b) {
    return a + b;
}

int no_args(void) {
    return 42;
}

int multi_args(int a, int b, int c, int d) {
    return a + b + c + d;
}

void process(void) {
    printf("processing...\n");
}

// Pointer return type
int *create_array(int size) {
    return (int *)malloc(size * sizeof(int));
}

// --- Variables ---

int global_counter = 0;

const char *app_name = "fluoride";

static int internal_state = 0;

// --- Structs ---

struct Point {
    int x;
    int y;
};

struct Color {
    unsigned char r;
    unsigned char g;
    unsigned char b;
    unsigned char a;
};

struct Config {
    int debug;
    int timeout;
    char host[256];
    int port;
};

// --- Enums ---

enum Direction {
    DIR_UP,
    DIR_DOWN,
    DIR_LEFT,
    DIR_RIGHT,
};

enum LogLevel {
    LOG_DEBUG = 0,
    LOG_INFO = 1,
    LOG_WARN = 2,
    LOG_ERROR = 3,
};

// --- Unions ---

union IntOrFloat {
    int i;
    float f;
};

union Data {
    int integer;
    float decimal;
    char text[32];
};

// --- Typedefs ---

typedef unsigned int uint;

typedef struct {
    float x;
    float y;
} Vec2;

typedef enum {
    STATUS_OK,
    STATUS_ERROR,
    STATUS_PENDING,
} Status;

typedef void (*Callback)(int, const char *);

// --- Main ---

int main(int argc, char *argv[]) {
    struct Point p = {1, 2};
    printf("Point: (%d, %d)\n", p.x, p.y);

    greet("World");
    printf("add: %d\n", add(2, 3));
    printf("no_args: %d\n", no_args());
    printf("SQUARE(5): %d\n", SQUARE(5));
    printf("MAX(3, 7): %d\n", MAX(3, 7));

    global_counter++;

    return 0;
}
