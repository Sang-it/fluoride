// Fluoride C header test file — comprehensive syntax coverage
// Covers: #define, forward declaration, struct, enum, union, typedef,
// typedef struct/enum/union, function pointer typedef, variable, field,
// enumerator

#ifndef APP_H
#define APP_H

#include <stddef.h>
#include <stdint.h>

#ifndef APP_B
#define APP_B
#define MAX_BUFFER_SIZE 4096

#define API_VERSION 3
#endif

#define MAX_BUFFER_SIZE 4096

#define API_VERSION 3

#define DEFAULT_TIMEOUT 5000

// --- Preprocessor defines (function macros) ---

#define MIN(a, b) ((a) < (b) ? (a) : (b))

#define MAX(a, b) ((a) > (b) ? (a) : (b))

#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

#define CLAMP(val, lo, hi) (MIN(MAX(val, lo), hi))

// --- Forward declarations (structs) ---

struct Node;

struct Connection;

// --- Function forward declarations ---

void init(void);

int compute(int a, int b);

int *get_buffer(size_t n);

double average(const double *data, size_t count);

void cleanup(void);

// --- Variable declarations ---

extern int global_count;

extern const char *VERSION;

extern volatile int interrupt_flag;

// --- Struct definitions (with fields) ---

struct Vector3 {
  float x;
  float y;
  float z;
};

struct Rect {
  int left;
  int top;
  int width;
  int height;
};

// Linked list node
struct Node {
  int value;
  struct Node *next;
  struct Node *prev;
};

// --- Enum definitions (with enumerators) ---

enum Color {
  COLOR_RED,
  COLOR_GREEN,
  COLOR_BLUE,
  COLOR_ALPHA,
};

enum LogLevel {
  LOG_TRACE = 0,
  LOG_DEBUG = 1,
  LOG_INFO = 2,
  LOG_WARN = 3,
  LOG_ERROR = 4,
  LOG_FATAL = 5,
};

// --- Union definitions (with fields) ---

union Value {
  int32_t i;
  float f;
  char s[16];
};

union Register {
  uint32_t full;
  uint16_t half[2];
  uint8_t bytes[4];
};

// --- Typedefs (simple) ---

typedef unsigned long ulong;

typedef int ErrorCode;

// --- Typedef struct (with body) ---

typedef struct {
  double real;
  double imag;
} Complex;

typedef struct {
  const char *key;
  const char *value;
} KeyValue;

// --- Typedef enum (with body) ---

typedef enum {
  PRIORITY_LOW,
  PRIORITY_NORMAL,
  PRIORITY_HIGH,
  PRIORITY_CRITICAL,
} Priority;

typedef enum {
  STATE_IDLE,
  STATE_RUNNING,
  STATE_PAUSED,
  STATE_STOPPED,
} State;

// --- Typedef union (with body) ---

typedef union {
  int64_t as_int;
  double as_float;
  void *as_ptr;
} Token;

// --- Typedef function pointers ---

typedef void (*EventHandler)(int event, void *data);

typedef int (*Comparator)(const void *a, const void *b);

typedef void (*Callback)(void);

#endif /* APP_H */
