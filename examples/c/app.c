#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ENTRIES 256

#define MAX_NAME_LEN 64

typedef struct {
    Entry items[MAX_ENTRIES];
    int count;
} Registry;

static int next_id = 1;

enum SortOrder {
    SORT_ASC,
    SORT_DESC,
};

const char *APP_VERSION = "1.0.0";

typedef struct {
    int id;
    char name[MAX_NAME_LEN];
    double value;
} Entry;

void registry_init(Registry *reg) {
    reg->count = 0;
}

int registry_add(Registry *reg, const char *name, double value) {
    if (reg->count >= MAX_ENTRIES) {
        return -1;
    }
    Entry *entry = &reg->items[reg->count];
    entry->id = next_id++;
    strncpy(entry->name, name, MAX_NAME_LEN - 1);
    entry->name[MAX_NAME_LEN - 1] = '\0';
    entry->value = value;
    reg->count++;
    return entry->id;
}

Entry *registry_find(Registry *reg, int id) {
    for (int i = 0; i < reg->count; i++) {
        if (reg->items[i].id == id) {
            return &reg->items[i];
        }
    }
    return NULL;
}

static int compare_asc(const void *a, const void *b) {
    const Entry *ea = (const Entry *)a;
    const Entry *eb = (const Entry *)b;
    if (ea->value < eb->value) return -1;
    if (ea->value > eb->value) return 1;
    return 0;
}

static int compare_desc(const void *a, const void *b) {
    return -compare_asc(a, b);
}

void registry_sort(Registry *reg, enum SortOrder order) {
    if (order == SORT_ASC) {
        qsort(reg->items, reg->count, sizeof(Entry), compare_asc);
    } else {
        qsort(reg->items, reg->count, sizeof(Entry), compare_desc);
    }
}

void registry_print(const Registry *reg) {
    for (int i = 0; i < reg->count; i++) {
        printf("[%d] %s = %.2f\n", reg->items[i].id, reg->items[i].name, reg->items[i].value);
    }
}

double registry_total(const Registry *reg) {
    double sum = 0.0;
    for (int i = 0; i < reg->count; i++) {
        sum += reg->items[i].value;
    }
    return sum;
}

int main(void) {
    Registry reg;
    registry_init(&reg);

    registry_add(&reg, "Alpha", 3.14);
    registry_add(&reg, "Beta", 2.71);
    registry_add(&reg, "Gamma", 1.41);

    registry_sort(&reg, SORT_ASC);
    registry_print(&reg);

    printf("Total: %.2f\n", registry_total(&reg));
    return 0;
}
