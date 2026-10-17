#include "CTerminalCore.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

int spawn_in_terminal(
    pid_t *pid,
    int terminal,
    const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attributes,
    char *const arguments[],
    char *const environment[]
) {
    int status_pipe[2];
    if (pipe(status_pipe) != 0) {
        return errno;
    }
    fcntl(status_pipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(status_pipe[1], F_SETFD, FD_CLOEXEC);

    sigset_t all_signals;
    sigset_t previous_signals;
    sigfillset(&all_signals);
    pthread_sigmask(SIG_SETMASK, &all_signals, &previous_signals);
    pid_t child = fork();
    if (child == 0) {
        int error = 0;
        if (setsid() == -1 || ioctl(terminal, TIOCSCTTY, 0) == -1 || fcntl(terminal, F_SETFD, 0) == -1) {
            error = errno;
        } else {
            error = posix_spawn(NULL, path, file_actions, attributes, arguments, environment);
        }
        write(status_pipe[1], &error, sizeof(error));
        _exit(127);
    }
    int fork_error = errno;
    pthread_sigmask(SIG_SETMASK, &previous_signals, NULL);
    close(status_pipe[1]);
    if (child == -1) {
        close(status_pipe[0]);
        return fork_error;
    }

    int error = 0;
    ssize_t count;
    do {
        count = read(status_pipe[0], &error, sizeof(error));
    } while (count == -1 && errno == EINTR);
    close(status_pipe[0]);
    if (count == sizeof(error)) {
        while (waitpid(child, NULL, 0) == -1 && errno == EINTR) {
        }
        return error;
    }
    *pid = child;
    return 0;
}
