#include <zmq.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>
#include "./config.h"

pid_t workers[WORKER_COUNT];
char *backend_socket;

void all_exit() {
	kill(-getpid(), SIGTERM);
}

pid_t spawn_worker() {
	pid_t worker = fork();
	if (worker == 0) {
		if (chdir("./lua") && chdir("../lua")) {
			return 1;
		}
		signal(SIGINT, SIG_IGN);
		signal(SIGHUP, SIG_IGN);
		execl("../bin/worker", "worker", ZMQ_SOCKET_SIMPLE_MASTER, NULL);
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

int main(int argc, char **argv) {
	if (argc < 2) {
		printf("./simple_master FRONTEND\n");
		return 1;
	}

	backend_socket = argv[1];

	signal(SIGCHLD, sigchld_recvd);
	signal(SIGINT, all_exit);
	signal(SIGHUP, all_exit);

	pid_t router = fork();
	if (router == 0) {
		signal(SIGINT, SIG_IGN);
		signal(SIGHUP, SIG_IGN);
		execl("./bin/router", "router", ZMQ_ROUTER_THREADS_SIMPLE_MASTER, "-bb", ZMQ_SOCKET_SIMPLE_MASTER, "-fb", argv[1], NULL);
		_exit(1);
	} else if(router < 0) {
		all_exit();
		return 1;
	}

	int i;
	for (i = 0; i < WORKER_COUNT; ++i) {
		workers[i] = spawn_worker();
	}

	printf("Simple master startup done\n");

	int stat;
	waitpid(router, &stat, 0);
	all_exit();

	return 0;
}
