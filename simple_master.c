#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/wait.h>
#include "./config.h"

int worker_count;
pid_t *workers;
char *backend_socket;

static void all_exit() {
	kill(-getpid(), SIGTERM);
}

static pid_t spawn_worker() {
	pid_t worker = fork();
	if (worker == 0) {
		if (chdir("./lua")) {
			return 1;
		}
		signal(SIGINT, SIG_IGN);
		signal(SIGHUP, SIG_IGN);
		execl("../worker", "worker", NULL);
		perror("execl_worker");
		_exit(1);
	} else if (worker > 0) {
		return worker;
	} else {
		all_exit();
		return 1;
	}
}

static void sigchld_recvd() {
	int status;
	pid_t pid = waitpid(-1, &status, WNOHANG | WUNTRACED | WCONTINUED);
	if (WIFCONTINUED(status) || WIFSTOPPED(status)) {
		return;
	}
	if (WIFSIGNALED(status) || WIFEXITED(status)) {
		int i;
		for (i = 0; i < worker_count; i++) {
			if (workers[i] == pid) {
				workers[i] = spawn_worker();
				break;
			}
		}
	}
}

int main(int argc, char **argv) {
	if (argc < 2) {
		printf("./simple_master COUNT\n");
		return 1;
	}

	worker_count = atoi(argv[1]);
	workers = malloc(sizeof(pid_t) * worker_count);

	backend_socket = argv[1];

	signal(SIGCHLD, sigchld_recvd);
	signal(SIGINT, all_exit);
	signal(SIGHUP, all_exit);

	int i;
	for (i = 0; i < worker_count; ++i) {
		workers[i] = spawn_worker();
	}

	printf("Simple master startup done\n");

	while (1) {
		sleep(60);
	}
	all_exit();

	return 0;
}
