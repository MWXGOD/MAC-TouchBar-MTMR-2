#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;

    char executablePath[PATH_MAX];
    if (realpath(argv[0], executablePath) == NULL) {
        perror("MTMR launcher: realpath");
        return 1;
    }

    char executableDirectory[PATH_MAX];
    strncpy(executableDirectory, executablePath, sizeof(executableDirectory));
    executableDirectory[sizeof(executableDirectory) - 1] = '\0';
    char *directory = dirname(executableDirectory);

    char originalPath[PATH_MAX];
    char localizerPath[PATH_MAX];
    char appContents[PATH_MAX];
    if (snprintf(originalPath, sizeof(originalPath), "%s/MTMR.original", directory) >= (int)sizeof(originalPath) ||
        snprintf(appContents, sizeof(appContents), "%s/..", directory) >= (int)sizeof(appContents) ||
        snprintf(localizerPath, sizeof(localizerPath), "%s/Resources/libmtmr-menu-localizer.dylib", appContents) >= (int)sizeof(localizerPath)) {
        fputs("MTMR launcher: path too long\n", stderr);
        return 1;
    }

    setenv("DYLD_INSERT_LIBRARIES", localizerPath, 1);
    execl(originalPath, originalPath, (char *)NULL);

    fprintf(stderr, "MTMR launcher: unable to start %s: %s\n", originalPath, strerror(errno));
    return 1;
}
