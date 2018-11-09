#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/wait.h>
#include "./config.h"

int worker_count;
pid_t *workers;

static void all_exit() {
	kill(-getpid(), SIGTERM);
}

static pid_t spawn_worker() {
	pid_t worker = fork();
	if (worker == 0) {
		if (chdir("./lua")) {
			_exit(1);
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
		perror("fork_worker");
		return worker;
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
				if (workers[i] < 0) {
					all_exit();
					exit(workers[i]);
					return;
				}
			}
		}
	}
}

int main(int argc, char **argv) {
	if (argc < 2) {
		printf("./simple_master COUNT\n");
		return 1;
	}

	if (argc > 3) {
		int uid = atoi(argv[2]);
		int gid = atoi(argv[3]);
		if (setregid(gid, gid)) {
			perror("setregid");
		}
		if (setreuid(uid, uid)) {
			perror("setreuid");
		}
	} else if (argc > 2) {
		int uidgid = atoi(argv[2]);
		if (setregid(uidgid, uidgid)) {
			perror("setregid");
		}
		if (setreuid(uidgid, uidgid)) {
			perror("setreuid");
		}
	}

	worker_count = atoi(argv[1]);
	workers = malloc(sizeof(pid_t) * worker_count);

	signal(SIGCHLD, sigchld_recvd);
	signal(SIGINT, all_exit);
	signal(SIGHUP, all_exit);

	int i;
	for (i = 0; i < worker_count; ++i) {
		workers[i] = spawn_worker();
		if (workers[i] < 0) {
			all_exit();
			return workers[i];
		}
	}

	printf("Simple master startup done\n");

	while (1) {
		sleep(60);
	}
	all_exit();

	return 0;
}
