#include "CTerminalCore.h"

#include <pthread.h>
#include <wchar.h>
#include <xlocale.h>

static locale_t utf8_locale;
static pthread_once_t utf8_locale_once = PTHREAD_ONCE_INIT;

static void create_utf8_locale(void) {
    utf8_locale = newlocale(LC_CTYPE_MASK, "UTF-8", NULL);
}

int character_width(uint32_t scalar) {
    pthread_once(&utf8_locale_once, create_utf8_locale);
    return wcwidth_l((wchar_t)scalar, utf8_locale);
}
