#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define T9_TEXT_MAX 64
#define T9_COMMIT_TIMEOUT_MS 800

typedef enum {
    T9_LAYER_LOWER,
    T9_LAYER_UPPER,
    T9_LAYER_SYMBOLS,
} t9_layer_t;

typedef enum {
    T9_EVENT_NONE,
    T9_EVENT_CHANGED,
    T9_EVENT_SUBMIT,
    T9_EVENT_CANCEL,
} t9_event_t;

typedef struct {
    char committed[T9_TEXT_MAX + 1];
    size_t committed_length;
    int pending_pad;
    size_t pending_index;
    int64_t last_press_ms;
    t9_layer_t layer;
} t9_input_t;

void t9_input_reset(t9_input_t* input);
t9_event_t t9_input_press(t9_input_t* input, int pad, int64_t now_ms);
t9_event_t t9_input_tick(t9_input_t* input, int64_t now_ms);
void t9_input_text(const t9_input_t* input, char* output, size_t output_size);
void t9_input_display(const t9_input_t* input, bool revealed,
                      char* output, size_t output_size);
size_t t9_input_length(const t9_input_t* input);
const char* t9_input_layer_name(const t9_input_t* input);

