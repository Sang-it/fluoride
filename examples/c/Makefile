CC = gcc
CFLAGS = -Wall -Wextra -std=c11
TARGET = app

all: $(TARGET)

$(TARGET): app.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
