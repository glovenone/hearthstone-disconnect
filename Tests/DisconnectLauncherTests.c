#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static int captured_exec(const char *path, char *const argv[]);
#define execv captured_exec
#define main launcher_main
#include "../DisconnectLauncher.c"
#undef main
#undef execv
static int captured_exec(const char *path, char *const argv[]) {
    assert(strcmp(path, REAL_EXECUTABLE) == 0);
    assert(strcmp(argv[0], REAL_EXECUTABLE) == 0);
    assert(strcmp(argv[1], "-launch") == 0);
    assert(getenv("DOORSTOP_INITIALIZED") == NULL);
    assert(getenv("DOORSTOP_PROCESS_PATH") == NULL);
    assert(getenv("DOORSTOP_MONO_LIB_PATH") == NULL);
    assert(strcmp(getenv("DOORSTOP_ENABLED"), "1") == 0);
    assert(strcmp(getenv("DOORSTOP_TARGET_ASSEMBLY"), PRELOADER) == 0);
    assert(strcmp(getenv("DYLD_INSERT_LIBRARIES"), DOORSTOP) == 0);
    errno = ENOENT;
    return -1;
}
int main(void) {
    setenv("DOORSTOP_INITIALIZED", "TRUE", 1);
    setenv("DOORSTOP_PROCESS_PATH", "old-process", 1);
    setenv("DOORSTOP_MONO_LIB_PATH", "old-mono", 1);
    char *args[] = {"launcher", "-launch", NULL};
    assert(launcher_main(2, args) == 1);
    puts("PASS: inherited loader state cleared; game arguments preserved (no game launched)");
    return 0;
}
