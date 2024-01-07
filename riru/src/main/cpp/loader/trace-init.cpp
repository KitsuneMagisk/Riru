#include <vector>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <pthread.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <string>
#include <set>
#include "logging.h"

using namespace std;

#define WPTEVENT(x)(x >> 16)

#define WEVENT(__status)(((__status) >> 16) & 0xff)

#define STOPPED_WITH(sig, event) WIFSTOPPED(status) && (status >> 8 == ((sig) | (event << 8)))

std::string get_program(int pid) {
    std::string path = "/proc/";
    path += std::to_string(pid);
    path += "/exe";
    constexpr
    const auto SIZE = 256;
    char buf[SIZE + 1];
    auto sz = readlink(path.c_str(), buf, SIZE);
    if (sz == -1) {
        return "";
    }
    buf[sz] = 0;
    return buf;
}

int fork_dont_care() {
    auto pid = fork();
    if (pid < 0) {
        PLOGE("fork 1");
    } else if (pid == 0) {
        pid = fork();
        if (pid < 0) {
            PLOGE("fork 2");
        } else if (pid > 0) {
            exit(0);
        }
    } else {
        int status;
        waitpid(pid, &status, __WALL);
    }
    return pid;
}

int trace_init_main(int argc, char *argv[]) {
    int status;
    std::set < pid_t > process;

    const char *tmp = (argc >= 2)? argv[1] : "/debug_ramdisk";

    if (ptrace(PTRACE_SEIZE, 1, 0, PTRACE_O_TRACEFORK) == -1) {
        LOGD("cannot trace init\n");
        return -1;
    }
    LOGD("start tracing init\n");

    for (int pid;;) {
        while ((pid = waitpid(-1, & status, __WALL | __WNOTHREAD)) != 0) {
            if (pid == 1) {
                if (STOPPED_WITH(SIGTRAP, PTRACE_EVENT_FORK)) {
                    long child_pid;
                    ptrace(PTRACE_GETEVENTMSG, pid, 0, & child_pid);
                    LOGD("init forked %ld\n", child_pid);
                }
                if (WIFSTOPPED(status)) {
                    ptrace(PTRACE_CONT, pid, 0, (WPTEVENT(status) == 0)? WSTOPSIG(status) : 0);
                }
                continue;
            }
            auto state = process.find(pid);
            if (state == process.end()) {
                LOGD("new process %d attached\n", pid);
                process.emplace(pid);
                ptrace(PTRACE_SETOPTIONS, pid, 0, PTRACE_O_TRACEEXEC);
                ptrace(PTRACE_CONT, pid, 0, 0);
                continue;
            } else {
                if (STOPPED_WITH(SIGTRAP, PTRACE_EVENT_EXEC)) {
                    auto program = get_program(pid);
                    LOGD("proc_monitor: pid=[%d] [%s]\n", pid, program.c_str());
                    string tracer = string(tmp);
                    string rirulib = string(tmp);
                    do {
                        if (program == "/system/bin/app_process64") {
                            tracer += "/riru/riruloader64";
                            rirulib += "/riru/riru64";
                        } else if (program == "/system/bin/app_process32") {
                            tracer += "/riru/riruloader32";
                            rirulib += "/riru/riru32";
                        }
                        if (tracer != tmp) {
                            kill(pid, SIGSTOP);
                            ptrace(PTRACE_CONT, pid, 0, 0);
                            waitpid(pid, & status, __WALL);
                            if (STOPPED_WITH(SIGSTOP, 0)) {
                                ptrace(PTRACE_DETACH, pid, 0, SIGSTOP);
                                status = 0;
                                auto p = fork_dont_care();
                                if (p == 0) {
                                    LOGI("riru: inject zygote PID=[%d] [%s]\n", pid, program.c_str());
                                    execl(tracer.data(), "", "--inject-on-entry",
                                        std::to_string(pid).c_str(), rirulib.data(), nullptr);
                                    PLOGE("failed to exec");
                                    kill(pid, SIGKILL);
                                    exit(1);
                                } else if (p == -1) {
                                    PLOGE("failed to fork");
                                    kill(pid, SIGKILL);
                                }
                            }
                        }
                    } while (false);
                } else {
                    LOGD("process %d received unknown status\n", pid);
                }
                process.erase(state);
                if (WIFSTOPPED(status)) {
                    LOGD("detach process %d\n", pid);
                    ptrace(PTRACE_DETACH, pid, 0, 0);
                }
            }
        }
    }
    return 0;
}
