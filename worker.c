#include <zmq.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "./util.h"
#include "./config.h"

#define BASE_LEN 256
#define BUFFER_LEN 65536
#define ARGS_LEN BUFFER_LEN

#define EXIT_OK 0
#define EXIT_TIMEOUT 5

#define ZMQ_NEEDMORE zmq_getsockopt(zsocket, ZMQ_RCVMORE, &_zmq_rcvmore, &_zmq_rcvmore_size); \
	if (!_zmq_rcvmore) { \
		zmq_send(zsocket, "BAD_INPUT\n", 10, 0); \
		continue; \
	}

lua_State *L;
int lua_main;
int lua_prot_depth = 0;
char *cgroup_mem_root;
char *cgroup_mem_limit;
char *cgroup_memsw_limit;
char *cgroup_mem_tasks;

void sigalrm_recvd() {
	exit(EXIT_TIMEOUT);
}

static void set_memory_limit(const char *memlimit) {
	FILE *fd;
	
	fd = fopen(cgroup_mem_limit, "w");
	fputs(memlimit, fd);
	fclose(fd);

	fd = fopen(cgroup_memsw_limit, "w");
	fputs(memlimit, fd);
	fclose(fd);
}

static void add_task_to_cgroup() {
	FILE *fd = fopen(cgroup_mem_tasks, "w");
	fprintf(fd, "%d\n", getpid());
	fclose(fd);
}

static int lua_enterprot(lua_State *L) {
	if (++lua_prot_depth == 1) {
		set_memory_limit(TASK_MEMORY_LIMIT_HIGH);
		signal(SIGTERM, SIG_IGN);
	}
	return 0;
}

static int lua_leaveprot(lua_State *L) {
	--lua_prot_depth;
	if (lua_prot_depth < 0) {
		exit(3);
	} else if (lua_prot_depth == 0) {
		set_memory_limit(TASK_MEMORY_LIMIT);
		signal(SIGTERM, SIG_DFL);
	}
	return 0;
}

static void lua_init() {
	L = luaL_newstate();
	luaL_openlibs(L);
	if(luaL_dofile(L, "main.lua")) {
		exit(1);
	}

	// run_id, caller, script, args, enterProt, leaveProt
	lua_main = luaL_ref(L, LUA_REGISTRYINDEX);
}

static void cgroup_init() {
	cgroup_mem_root = malloc(256);
	cgroup_mem_limit = malloc(256);
	cgroup_memsw_limit = malloc(256);
	cgroup_mem_tasks = malloc(256);
	sprintf(cgroup_mem_root, "/sys/fs/cgroup/memory/%s/moonhack_cg_%d/", getenv("USER"), getpid());
	sprintf(cgroup_mem_limit, "%s%s", cgroup_mem_root, "memory.limit_in_bytes");
	sprintf(cgroup_memsw_limit, "%s%s", cgroup_mem_root, "memory.memsw.limit_in_bytes");
	sprintf(cgroup_mem_tasks, "%s%s", cgroup_mem_root, "tasks");
	mkdir(cgroup_mem_root, 0700);
	set_memory_limit(TASK_MEMORY_LIMIT);
}

int main() {
	int _zmq_rcvmore = 0;
	size_t _zmq_rcvmore_size = sizeof(int);

	signal(SIGINT, SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	signal(SIGCHLD, noop_hdlr);

	cgroup_init();
	lua_init();

	void* ctx = zmq_init(1);
	void* zsocket = zmq_socket(ctx, ZMQ_REP);
	zmq_setallopts(zsocket, -1, 5000);
	zmq_connect(zsocket, ZMQ_SOCKET);

	struct sockaddr_in saddr;
	saddr.sin_family = AF_INET;

	char caller[BASE_LEN + 1], script[BASE_LEN + 1], run_id[BASE_LEN + 1], args[ARGS_LEN + 1];
	int caller_len, script_len, run_id_len, args_len;

	int stdout_pipe[2];

	int exitstatus;
	FILE *stdout_fd;
	char buffer[BUFFER_LEN + 1];

	while (1) {
		zmq_recv(zsocket, &saddr.sin_addr, sizeof(saddr.sin_addr), 0);
		ZMQ_NEEDMORE;
		zmq_recv(zsocket, &saddr.sin_port, sizeof(saddr.sin_port), 0);
		ZMQ_NEEDMORE;
		run_id_len = zmq_recv(zsocket, &run_id, BASE_LEN, 0);
		ZMQ_NEEDMORE;
		caller_len = zmq_recv(zsocket, &caller, BASE_LEN, 0);
		ZMQ_NEEDMORE;
		script_len = zmq_recv(zsocket, &script, BASE_LEN, 0);
		ZMQ_NEEDMORE;
		args_len = zmq_recv(zsocket, &args, ARGS_LEN, 0);

		caller[caller_len] = 0;
		script[script_len] = 0;
		run_id[run_id_len] = 0;
		args[args_len] = 0;

		int sockfd = socket(PF_INET, SOCK_STREAM, 0);
		if (connect(sockfd, (struct sockaddr *)&saddr, sizeof(saddr)) < 0) {
			zmq_send(zsocket, "NOCONNECT\n", 10, 0);
			perror("connect");
			continue;
		}

		zmq_send(zsocket, "STARTED\n", 8, 0);
		
		if(pipe(stdout_pipe)) {
			exit(1);
		}

		pid_t subworker = fork();
		if (subworker == 0) {
			close(sockfd);
			close(stdout_pipe[0]);
			dup2(stdout_pipe[1], 1);
			close(stdout_pipe[1]);

			lua_prot_depth = 0;

			signal(SIGALRM, sigalrm_recvd);
			alarm(TASK_HARD_TIMEOUT);

			add_task_to_cgroup();
			
			lua_rawgeti(L, LUA_REGISTRYINDEX, lua_main);
			lua_pushstring(L, run_id);
			lua_pushstring(L, caller);
			lua_pushstring(L, script);
			lua_pushstring(L, args);
			lua_pushcfunction(L, lua_enterprot);
			lua_pushcfunction(L, lua_leaveprot);
			lua_call(L, 6, 0);
			exit(0);
		} else if(subworker < 0) {
			exit(1);
		}

		close(stdout_pipe[1]);

		stdout_fd = fdopen(stdout_pipe[0], "r");
		while(!feof(stdout_fd) && fgets(buffer, BUFFER_LEN, stdout_fd)) {
			if (write(sockfd, buffer, strlen(buffer)) < 0) {
				break;
			}
			//zmq_send(socket, buffer, strlen(buffer), ZMQ_SNDMORE);
		}

		waitpid(subworker, &exitstatus, 0);

		if (WIFSIGNALED(exitstatus)) {
			switch(WTERMSIG(exitstatus)) {
				case 9: // SIGKILL, really only happens when OOM
					if (write(sockfd, "\0\nMEMORY_LIMIT\n", 15) < 0) {
						perror("write");
					}
					break;
				default:
					if (write(sockfd, "\0\nINTERNAL\n", 11) < 0) {
						perror("write");
					}
					printf("KILLED %d\n", WTERMSIG(exitstatus));
					break;
			}
		} else if(WIFEXITED(exitstatus)) {
			switch(WEXITSTATUS(exitstatus)) {
				case EXIT_TIMEOUT:
					if (write(sockfd, "\0\nHARD_TIMEOUT\n", 15) < 0) {
						perror("write");
					}
					break;
				case EXIT_OK:
					if (write(sockfd, "\0\nOK\n", 5) < 0) {
						perror("write");
					}
					break;					
				default:
					if (write(sockfd, "\0\nINTERNAL\n", 11) < 0) {
						perror("write");
					}
					printf("EXITED %d\n", WEXITSTATUS(exitstatus));
					break;
			}
		}

		fclose(stdout_fd);
		close(sockfd);
	}

	return 0;
}