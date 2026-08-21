#include "t9-input.h"

#include <string.h>

enum {
    PAD_ENTER = 4,
    PAD_LAYER = 8,
    PAD_CANCEL = 12,
    PAD_BACKSPACE = 16,
};

static const char* characters_for(t9_layer_t layer, int pad)
{
    static const char* lower[17] = {
        [1] = "#1", [2] = "0+", [3] = "*",
        [5] = "pqrs7", [6] = "tuv8", [7] = "wxyz9",
        [9] = "ghi4", [10] = "jkl5", [11] = "mno6",
        [13] = " ", [14] = "abc2", [15] = "def3",
    };
    static const char* upper[17] = {
        [1] = "#1", [2] = "0+", [3] = "*",
        [5] = "PQRS7", [6] = "TUV8", [7] = "WXYZ9",
        [9] = "GHI4", [10] = "JKL5", [11] = "MNO6",
        [13] = " ", [14] = "ABC2", [15] = "DEF3",
    };
    static const char* symbols[17] = {
        [1] = "~`", [2] = "0", [3] = "<>|",
        [5] = "$%&^", [6] = "+=", [7] = "#*",
        [9] = ":;/", [10] = "\\\"'", [11] = "()[]{}",
        [13] = " ", [14] = ".,!?", [15] = "@_-",
    };
    if (pad < 1 || pad > 16) return NULL;
    if (layer == T9_LAYER_UPPER) return upper[pad];
    if (layer == T9_LAYER_SYMBOLS) return symbols[pad];
    return lower[pad];
}

static bool commit_pending(t9_input_t* input)
{
    if (!input || input->pending_pad == 0) return false;
    const char* characters = characters_for(input->layer, input->pending_pad);
    if (characters && input->committed_length < T9_TEXT_MAX) {
        input->committed[input->committed_length++] = characters[input->pending_index];
        input->committed[input->committed_length] = '\0';
    }
    input->pending_pad = 0;
    input->pending_index = 0;
    return true;
}

void t9_input_reset(t9_input_t* input)
{
    if (!input) return;
    memset(input, 0, sizeof *input);
    input->layer = T9_LAYER_LOWER;
}

t9_event_t t9_input_press(t9_input_t* input, int pad, int64_t now_ms)
{
    if (!input) return T9_EVENT_NONE;
    if (pad == PAD_ENTER) {
        (void)commit_pending(input);
        return T9_EVENT_SUBMIT;
    }
    if (pad == PAD_CANCEL) {
        t9_input_reset(input);
        return T9_EVENT_CANCEL;
    }
    if (pad == PAD_LAYER) {
        (void)commit_pending(input);
        input->layer = (t9_layer_t)((input->layer + 1) % 3);
        return T9_EVENT_CHANGED;
    }
    if (pad == PAD_BACKSPACE) {
        if (input->pending_pad != 0) {
            input->pending_pad = 0;
            input->pending_index = 0;
        } else if (input->committed_length > 0) {
            input->committed[--input->committed_length] = '\0';
        }
        return T9_EVENT_CHANGED;
    }

    const char* characters = characters_for(input->layer, pad);
    if (!characters || !*characters) return T9_EVENT_NONE;
    if (input->pending_pad == pad && now_ms - input->last_press_ms < T9_COMMIT_TIMEOUT_MS) {
        input->pending_index = (input->pending_index + 1) % strlen(characters);
    } else {
        (void)commit_pending(input);
        if (input->committed_length >= T9_TEXT_MAX) return T9_EVENT_NONE;
        input->pending_pad = pad;
        input->pending_index = 0;
    }
    input->last_press_ms = now_ms;
    return T9_EVENT_CHANGED;
}

t9_event_t t9_input_tick(t9_input_t* input, int64_t now_ms)
{
    if (!input || input->pending_pad == 0) return T9_EVENT_NONE;
    if (now_ms - input->last_press_ms < T9_COMMIT_TIMEOUT_MS) return T9_EVENT_NONE;
    (void)commit_pending(input);
    return T9_EVENT_CHANGED;
}

void t9_input_text(const t9_input_t* input, char* output, size_t output_size)
{
    if (!output || output_size == 0) return;
    output[0] = '\0';
    if (!input) return;
    size_t length = input->committed_length;
    if (length >= output_size) length = output_size - 1;
    memcpy(output, input->committed, length);
    if (input->pending_pad && length + 1 < output_size) {
        const char* characters = characters_for(input->layer, input->pending_pad);
        if (characters) output[length++] = characters[input->pending_index];
    }
    output[length] = '\0';
}

void t9_input_display(const t9_input_t* input, bool revealed,
                      char* output, size_t output_size)
{
    if (!output || output_size == 0) return;
    if (revealed) {
        t9_input_text(input, output, output_size);
        return;
    }
    size_t length = t9_input_length(input);
    if (length >= output_size) length = output_size - 1;
    memset(output, 'X', length);
    output[length] = '\0';
}

size_t t9_input_length(const t9_input_t* input)
{
    if (!input) return 0;
    return input->committed_length + (input->pending_pad != 0 ? 1u : 0u);
}

const char* t9_input_layer_name(const t9_input_t* input)
{
    if (!input || input->layer == T9_LAYER_LOWER) return "LOWER";
    if (input->layer == T9_LAYER_UPPER) return "UPPER";
    return "SYMBOLS";
}
