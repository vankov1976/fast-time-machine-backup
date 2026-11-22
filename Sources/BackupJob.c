#include <libgen.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static volatile sig_atomic_t stop_requested = 0;

static void on_stop(int sig) {
    (void)sig;
    stop_requested = 1;
}

static int run_backup(const char *script) {
    char *args[] = {"/bin/bash", (char *)script, NULL};
    posix_spawnattr_t attr;
    pid_t child = 0;
    int status = 0;

    if (posix_spawnattr_init(&attr) != 0) {
        return 1;
    }
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);
    if (posix_spawn(&child, "/bin/bash", NULL, &attr, args, environ) != 0) {
        posix_spawnattr_destroy(&attr);
        return 1;
    }
    posix_spawnattr_destroy(&attr);

    for (;;) {
        pid_t got = waitpid(child, &status, WNOHANG);
        if (got == child) {
            if (WIFEXITED(status)) {
                return WEXITSTATUS(status);
            }
            return 1;
        }
        if (got < 0) {
            return 1;
        }
        if (stop_requested) {
            kill(-child, SIGTERM);
            waitpid(child, &status, 0);
            return 0;
        }
        sleep(1);
    }
}

static void pause_for(int seconds) {
    while (seconds > 0 && !stop_requested) {
        seconds = sleep((unsigned)seconds);
    }
}

int main(int argc, char **argv) {
    char executable[4096];
    uint32_t size = sizeof(executable);
    char directory[4096];
    char target[8192];
    int once = 0;
    int backup_first = 0;
    int interval = 3600;
    int i;

    if (_NSGetExecutablePath(executable, &size) != 0) {
        return 1;
    }
    snprintf(directory, sizeof(directory), "%s", dirname(executable));

    if (geteuid() != 0) {
        snprintf(target, sizeof(target), "%s/BackupMenu", directory);
        execv(target, argv);
        perror("BackupMenu");
        return 1;
    }

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "once") == 0) {
            once = 1;
        } else if (strcmp(argv[i], "backup") == 0) {
            backup_first = 1;
        } else {
            int n = atoi(argv[i]);
            if (n >= 60) {
                interval = n;
            }
        }
    }

    snprintf(target, sizeof(target), "%s/../Resources/backup.sh", directory);
    signal(SIGTERM, on_stop);
    signal(SIGINT, on_stop);

    if (once) {
        return run_backup(target);
    }

    if (backup_first && !stop_requested) {
        run_backup(target);
    }
    while (!stop_requested) {
        pause_for(interval);
        if (stop_requested) {
            break;
        }
        run_backup(target);
    }
    return 0;
}
