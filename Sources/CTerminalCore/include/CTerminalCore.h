#include <spawn.h>

int spawn_in_terminal(
    pid_t *pid,
    int terminal,
    const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attributes,
    char *const arguments[],
    char *const environment[]
);
