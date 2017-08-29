#include <zmq.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "./util.h"
#include "./config.h"

#define BASE_LEN 256
#define BUFFER_LEN 65536
#define ARGS_LEN BUFFER_LEN

#define EXIT_MEMLIMIT 9
#define EXIT_OK 0
#define EXIT_TIMEOUT 5

#define ZMQ_NEEDMORE zmq_getsockopt(socket, ZMQ_RCVMORE, &_zmq_rcvmore, &_zmq_rcvmore_size); \
	if (!_zmq_rcvmore) { \
		zmq_send(socket, "BAD_INPUT\n", 10, 0); \
		continue; \
	}

lua_State *L;
int lua_main;
int lua_prot_depth = 0;

void sigalrm_recvd() {
	exit(EXIT_TIMEOUT);
}

static int lua_enterprot(lua_State *L) {
	if (++lua_prot_depth == 1) {
		// Increase mem limit
		signal(SIGTERM, SIG_IGN);
	}
}

static int lua_leaveprot(lua_State *L) {
	--lua_prot_depth;
	if (lua_prot_depth < 0) {
		exit(3);
	} else if (lua_prot_depth == 0) {
		// Reset mem limit
		signal(SIGTERM, SIG_DFL);
	}
}

static void lua_init() {
	L = luaL_newstate();
	luaL_openlibs(L);
	luaL_dofile(L, "main.lua");

	// run_id, caller, script, args, enterProt, leaveProt
	lua_main = luaL_ref(L, LUA_REGISTRYINDEX);
}

int main() {
	int _zmq_rcvmore = 0;
	size_t _zmq_rcvmore_size = sizeof(int);

	signal(SIGINT, SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	signal(SIGCHLD, noop_hdlr);

	lua_init();

	void* ctx = zmq_init(1);
	void* socket = zmq_socket(ctx, ZMQ_REP);
	zmq_setallopts(socket, -1, 5000);
	zmq_connect(socket, ZMQ_SOCKET);

	char caller[BASE_LEN + 1], script[BASE_LEN + 1], run_id[BASE_LEN + 1], args[ARGS_LEN + 1];
	int caller_len, script_len, run_id_len, args_len;

	int stdout_pipe[2];
	int stderr_pipe[2];

	int stat, exit_code;
	FILE *stdout_fd, *stderr_fd;
	char buffer[BUFFER_LEN + 1];

	while (1) {
		run_id_len = zmq_recv(socket, &run_id, BASE_LEN, 0);
		ZMQ_NEEDMORE;
		caller_len = zmq_recv(socket, &caller, BASE_LEN, 0);
		ZMQ_NEEDMORE;
		script_len = zmq_recv(socket, &script, BASE_LEN, 0);
		ZMQ_NEEDMORE;
		args_len = zmq_recv(socket, &args, ARGS_LEN, 0);
		caller[caller_len] = 0;
		script[script_len] = 0;
		run_id[run_id_len] = 0;
		args[args_len] = 0;
		
		if(pipe(stdout_pipe)) {
			exit(1);
		}
		if(pipe(stderr_pipe)) {
			exit(1);
		}

		pid_t subworker = fork();
		if (subworker == 0) {
			close(stdout_pipe[0]);
			close(stderr_pipe[0]);
			dup2(stdout_pipe[1], 1);
			close(stdout_pipe[1]);
			dup2(stderr_pipe[1], 2);
			close(stderr_pipe[1]);

			signal(SIGALRM, sigalrm_recvd);
			alarm(TASK_HARD_TIMEOUT);
			
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
		close(stderr_pipe[1]);

		waitpid(subworker, &stat, 0);
		exit_code = WEXITSTATUS(stat);

		stdout_fd = fdopen(stdout_pipe[0], "r");
		stderr_fd = fdopen(stdout_pipe[0], "r");

		switch(exit_code) {
			case EXIT_TIMEOUT:
				zmq_send(socket, "HARD_TIMEOUT\n", 13, ZMQ_SNDMORE);
				break;
			case EXIT_MEMLIMIT:
				zmq_send(socket, "MEMORY_LIMIT\n", 13, ZMQ_SNDMORE);
				break;
			case EXIT_OK:
				zmq_send(socket, "OK\n", 3, ZMQ_SNDMORE);
				break;
			default:
				zmq_send(socket, "INTERNAL\n", 9, ZMQ_SNDMORE);
				break;
		}

		while(!feof(stdout_fd) && fgets(buffer, BUFFER_LEN, stdout_fd)) {
			zmq_send(socket, buffer, strlen(buffer), ZMQ_SNDMORE);
		}
		zmq_send(socket, "STOP\n", 5, 0);

		fclose(stdout_fd);
		fclose(stderr_fd);
	}

	return 0;
}