#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define GAME_ROOT "/Applications/Hearthstone"
#define REAL_EXECUTABLE GAME_ROOT "/Hearthstone.app/Contents/MacOS/Hearthstone.real"
#define DOORSTOP GAME_ROOT "/libdoorstop.dylib"
#define PRELOADER GAME_ROOT "/BepInEx/core/BepInEx.Preloader.dll"
#define CORLIB GAME_ROOT "/BepInEx/unstripped_corlib"

int main(int argc, char **argv) {
    (void)argc;
    if (chdir(GAME_ROOT) != 0) {
        fprintf(stderr, "DisconnectLauncher: chdir: %s\n", strerror(errno));
        return 1;
    }

    setenv("DYLD_INSERT_LIBRARIES", DOORSTOP, 1);
    setenv("DYLD_LIBRARY_PATH", GAME_ROOT, 1);
    setenv("DOORSTOP_ENABLED", "1", 1);
    setenv("DOORSTOP_IGNORE_DISABLED_ENV", "0", 1);
    setenv("DOORSTOP_TARGET_ASSEMBLY", PRELOADER, 1);
    setenv("DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE", CORLIB, 1);
    setenv("DOORSTOP_REDIRECT_OUTPUT_LOG", "1", 1);

    argv[0] = (char *)REAL_EXECUTABLE;
    execv(REAL_EXECUTABLE, argv);
    fprintf(stderr, "DisconnectLauncher: execv: %s\n", strerror(errno));
    return 1;
}
