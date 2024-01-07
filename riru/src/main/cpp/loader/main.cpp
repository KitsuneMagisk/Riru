#include <string>
#include <stdlib.h>
#include <signal.h>

int trace_init_main(int argc, char *argv[]);
bool trace_zygote(int pid, const char *lib_path);

int main(int argc, char *argv[]) {
    if (argc == 4  && strcmp(argv[1], "--inject-on-entry") == 0) {
        int pid = atoi(argv[2]);
        if (!trace_zygote(pid, argv[3])) {
            kill(pid, SIGKILL);
            return 1;
        }
        return 0;
    }
    return trace_init_main(argc, argv);
}

