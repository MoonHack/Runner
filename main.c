#include <zmq.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>
#include "./config.h"

pid_t workers[WORKER_COUNT];

void all_exit() {
	kill(-getpid(), SIGTERM);
}

pid_t spawn_worker() {
	pid_t worker = fork();
	if (worker == 0) {
		execl("../worker", "worker", NULL);
		_exit(1);
	} else if (worker > 0) {
		return worker;
	} else {
		all_exit();
		return 1;
	}
}

void sigchld_recvd() {
	int status;
	pid_t pid = waitpid(-1, &status, WNOHANG | WUNTRACED | WCONTINUED);
	if (WIFCONTINUED(status) || WIFSTOPPED(status)) {
		return;
	}
	if (WIFSIGNALED(status) || WIFEXITED(status)) {
		int i;
		for (i = 0; i < WORKER_COUNT; i++) {
			if (workers[i] == pid) {
				workers[i] = spawn_worker();
				break;
			}
		}
	}
}

int main() {
	if (chdir("lua")) {
		return 1;
	}

	signal(SIGCHLD, sigchld_recvd);
	signal(SIGINT, all_exit);
	signal(SIGHUP, all_exit);

	pid_t router = fork();
	if (router == 0) {
		execl("../router", "router", NULL);
		_exit(1);
	} else if(router < 0) {
		all_exit();
		return 1;
	}

	int i;
	for (i = 0; i < WORKER_COUNT; ++i) {
		workers[i] = spawn_worker();
	}

	int stat;
	waitpid(router, &stat, 0);
	all_exit();

	return 0;
}
