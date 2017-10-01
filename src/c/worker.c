#define _GNU_SOURCE

#include <amqp_tcp_socket.h>
#include <amqp.h>
#include <amqp_framing.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sched.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/time.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <luajit.h>

#include "./rmq_util.h"
#include "./config.h"

#define BUFFER_LEN 65536

#define RUN_ID_LEN 36

#define EXIT_OK 0
#define EXIT_HARD_TIMEOUT 5
#define EXIT_SOFT_TIMEOUT 6
#define EXIT_KILLSWITCH 7
#define EXIT_ERROR 4
#define EXIT_MEMLIMIT 3

size_t current_memlimit;
size_t current_memlimit_hard;

FILE *pipe_fh;
pid_t worker_pid;
lua_State *L;
int lua_main;
int lua_prot_depth = 0;
int lua_exit_on_prot_leave = 0;
amqp_basic_properties_t props;

char cgroup_mem_limit[256];
char cgroup_memsw_limit[256];
char cgroup_mem_tasks[256];
//#define cgroup_mem_limit "/var/root/cg_mem/memory.limit_in_bytes"
//#define cgroup_memsw_limit "/var/root/cg_mem/memory.memsw.limit_in_bytes"
//#define cgroup_mem_tasks "/var/root/cg_mem/tasks"

#define WRITE_AMQP(_str, _len) \
	message_bytes.bytes = _str; \
	message_bytes.len = _len; \
	if (amqp_basic_publish(aconn, \
			1, \
			amqp_empty_bytes, \
			arepqueue, \
			0, \
			0, \
			&props, \
			message_bytes \
		)) { \
		exit(1); \
	}

#define COPYIN(VAR) \
	VAR = malloc(VAR ## _len); \
	memcpy(VAR, envelope.message.body.bytes + pos, VAR ## _len); \
	pos += VAR ## _len;

static void noop_hdlr() {

}

static int pcall_interrhdl(lua_State *L) {
	luaJIT_set_memory_limits(L, 0, 0);
	const char *errStr = lua_tostring(L, -1);
	if (strcmp(errStr, "not enough memory") == 0) {
		exit(EXIT_MEMLIMIT);
		return 0;
	}
	luaL_traceback(L, L, errStr, 1);
	printf("Internal Lua error: %s\n", lua_tostring(L, -1));
	exit(1);
	return 0;
}

static void sigalrm_recvd() {
	if (lua_prot_depth > 0 && lua_exit_on_prot_leave == 0) {
		lua_exit_on_prot_leave = EXIT_HARD_TIMEOUT;
		alarm(20);
		return;
	}
	exit(EXIT_HARD_TIMEOUT);
}

static void sigalrm_killchild_rcvd() {
	kill(worker_pid, SIGKILL);
}

void lua_notify_user(const char *name, const char *data) {
	if (amqp_basic_publish(aconn,
			1,
			aexchange_notify,
			amqp_cstring_bytes(name),
			0,
			0,
			&props,
			amqp_cstring_bytes(data)
		)) {
		exit(EXIT_ERROR);
	}
}

void lua_writeln(const char *str) {
	if (fwrite(str, strlen(str), 1, pipe_fh)) {
		fflush(pipe_fh);
	}
}

size_t lua_get_memory_limit() {
	return current_memlimit;
}

size_t lua_get_memory_usage() {
	return luaJIT_get_memory_usage(L);
}

static void add_task_to_cgroup(pid_t pid) {
	FILE *fd = fopen(cgroup_mem_tasks, "w");
	if (!fd) {
		perror("fopen_cgroup_mem_tasks");
		exit(1);
	}
	fprintf(fd, "%d\n", pid);
	fclose(fd);
}

void lua_enterprot() {
	if (++lua_prot_depth == 1) {
		luaJIT_set_memory_limits(L, current_memlimit, 0);
	}
}

void lua_leaveprot() {
	--lua_prot_depth;
	if (lua_prot_depth < 0) {
		exit(EXIT_ERROR);
	} else if (lua_prot_depth == 0) {
		if (lua_exit_on_prot_leave) {
			exit(lua_exit_on_prot_leave);
		} else {
			luaJIT_set_memory_limits(L, current_memlimit, current_memlimit_hard);
		}
	}
}

static void lua_init() {
	L = luaL_newstate();
	luaL_openlibs(L);
	lua_pushcfunction(L, pcall_interrhdl);
	if(luaL_loadfile(L, "main.luac")) {
		printf("Error loading Lua: %s\n", lua_tostring(L, -1));
		exit(1);
	}

	if (lua_pcall(L, 0, 1, -2)) {
		exit(1);
	}

	// caller, script, args
	lua_main = luaL_ref(L, LUA_REGISTRYINDEX);

	// By not popping it from the stack here, we can use it in the main function's runner
	//lua_pop(L, lua_gettop(L));

	lua_gc(L, LUA_GCCOLLECT, 0);
	lua_gc(L, LUA_GCCOLLECT, 0);

	lua_atpanic(L, pcall_interrhdl);
	luaJIT_set_memory_limits(L, current_memlimit, current_memlimit_hard);
}

static int cgroup_init() {
	char cgroup_mem_root[200];
	sprintf(cgroup_mem_root, "/sys/fs/cgroup/memory/%s/moonhack_cg_%d/", getenv("USER"), getpid());
	sprintf(cgroup_mem_limit, "%smemory.limit_in_bytes", cgroup_mem_root);
	sprintf(cgroup_memsw_limit, "%smemory.memsw.limit_in_bytes", cgroup_mem_root);
	sprintf(cgroup_mem_tasks, "%stasks", cgroup_mem_root);

	mkdir(cgroup_mem_root, 0700);

	FILE *fd;

	fd = fopen(cgroup_mem_limit, "w");
	if (!fd) {
		perror("fopen_cgroup_mem_limit");
		exit(1);
	}
	fputs(TASK_MEMORY_LIMIT_HIGH, fd);
	fclose(fd);

	fd = fopen(cgroup_memsw_limit, "w");
	if (!fd) {
		perror("fopen_cgroup_memsw_limit");
		exit(1);
	}
	fputs(TASK_MEMORY_LIMIT_HIGH, fd);
	fclose(fd);
	return 0;
}

static int secure_me(int uid, int gid) {
	if (cgroup_init()) {
		return 1;
	}

	if (unshare(CLONE_NEWUSER)) {
		perror("CLONE_NEWUSER");
		return 1;
	}

	int fd = open("/proc/self/uid_map", O_WRONLY);
	if(fd < 0) {
		perror("uid_map_open");
		return 1;
	}
	if(dprintf(fd, "%d %d 1\n", uid, uid) < 0) {
		perror("uid_map_dprintf");
		return 1;
	}
	close(fd);

	fd = open("/proc/self/setgroups", O_WRONLY);
	if(fd < 0) {
		perror("setgroups_open");
		return 1;
	}
	if (dprintf(fd, "deny\n") < 0) {
		perror("setgroups_dprintf");
		return 1;
	}
	close(fd);

	fd = open("/proc/self/gid_map", O_WRONLY);
	if(fd < 0) {
		perror("gid_map_open");
		return 1;
	}
	if (dprintf(fd, "%d %d 1\n", gid, gid) < 0) {
		perror("gid_map_dprintf");
		return 1;
	}
	close(fd);

	if (unshare(CLONE_NEWNS)) {
		perror("CLONE_NEWNS");
		return 1;
	}

	if (mount("none", "/var", "tmpfs", MS_NOSUID | MS_NOEXEC | MS_NOATIME, "")) {
		perror("mount_var");
		return 1;
	}

	if (mkdir("/var/root", 0755)) {
		perror("mkdir_root");
		return 1;
	}

	if (mount("none", "/var", "tmpfs", MS_RDONLY | MS_REMOUNT | MS_NOSUID | MS_NOEXEC | MS_NOATIME, "")) {
		perror("remount_ro_var");
		return 1;
	}

	return 0;
}

static int secure_me_sub(int uid, int gid) {
	if (chroot("/var/root")) {
		perror("chroot");
		return 1;
	}

	if (chdir("/")) {
		perror("chdir_root");
		return 1;
	}

	if (setresuid(uid, uid, uid)) {
		perror("setresuid");
		return 1;
	}

	if (setresgid(gid, gid, gid)) {
		perror("setresgid");
		return 1;
	}

	return 0;
}

int main() {
	int uid = getuid();
	int gid = getgid();

	current_memlimit = TASK_MEMORY_LIMIT;
	current_memlimit_hard = current_memlimit + (1 * 1024 * 1024);

	if (secure_me(uid, gid)) {
		return 1;
	}

	lua_init();

	signal(SIGCHLD, noop_hdlr);

	_util_init_rmq();

	amqp_basic_consume(aconn, 1, aqueue, amqp_empty_bytes, 0, 0, 0, amqp_empty_table);
	die_on_amqp_error(amqp_get_rpc_reply(aconn), "Consuming");

	char *caller, *script, *args;
	int caller_len, script_len, args_len;

	int stdout_pipe[2];

	int exitstatus;
	FILE *stdout_fd;
	char buffer[BUFFER_LEN];

	struct command_request_t *command;

	// The 61 here suppresses the nullbyte, which is unnecessary
	char arepqueue_bytes[] = "moonhack_command_results_00000000-0000-0000-0000-000000000000";
	amqp_bytes_t arepqueue;
	arepqueue.bytes = arepqueue_bytes;
	arepqueue.len = sizeof(arepqueue_bytes) - 1;

	amqp_bytes_t message_bytes;
	props._flags = AMQP_BASIC_DELIVERY_MODE_FLAG;
	props.delivery_mode = 2;

	int first_loop = 1;
	uint64_t pos;

	pid_t subworker, subworker_master;

	amqp_envelope_t envelope;

	while (1) {
		if (!first_loop) { // Means second loop iteration
			amqp_basic_ack(aconn, 1, envelope.delivery_tag, 0);
		}
		amqp_maybe_release_buffers(aconn);
		die_on_amqp_error(amqp_consume_message(aconn, &envelope, NULL, 0), "Consume");

		first_loop = 0;

		if (envelope.redelivered) {
			printf("REDELIVERED\n");
			amqp_destroy_envelope(&envelope);
			continue;
		}

		if (envelope.message.body.len < sizeof(struct command_request_t)) {
			printf("TOOSHORT\n");
			amqp_destroy_envelope(&envelope);
			continue;
		}

		command = envelope.message.body.bytes;
		if (command->run_id_len != RUN_ID_LEN) {
			printf("WRONGLENRUNID\n");
			amqp_destroy_envelope(&envelope);
			continue;
		}

		caller_len = command->caller_len;
		script_len = command->script_len;
		args_len = command->args_len;

		pos = sizeof(struct command_request_t);
		memcpy(arepqueue.bytes + 25, envelope.message.body.bytes + pos, RUN_ID_LEN);
		pos += RUN_ID_LEN;

		if (pos + caller_len + script_len + args_len != envelope.message.body.len) {
			WRITE_AMQP("\1WRONGLEN\n", 10);
			amqp_destroy_envelope(&envelope);
			continue;
		}

		COPYIN(caller);
		COPYIN(script);
		COPYIN(args);

		amqp_destroy_envelope(&envelope);

		subworker_master = fork();
		if (subworker_master > 0) {
			free(caller);
			free(script);
			free(args);
			waitpid(subworker_master, &exitstatus, 0);
			continue;
		} else if (subworker_master < 0) {
			exit(1);
		}

		// This all runs INSIDE THE FORK
		if (unshare(CLONE_NEWPID)) {
			perror("CLONE_NEWPID");
			exit(1);
		}

		if(pipe(stdout_pipe)) {
			perror("stdout_pipe");
			exit(1);
		}

		subworker = fork();
		if (subworker == 0) {
			add_task_to_cgroup(getpid());

			close(stdout_pipe[0]);
			pipe_fh = fdopen(stdout_pipe[1], "w");

			if (unshare(CLONE_FILES)) {
				perror("CLONE_FILES");
				exit(1);
			}

			lua_prot_depth = 0;

			signal(SIGALRM, sigalrm_recvd);
			signal(SIGTERM, SIG_IGN);
			signal(SIGINT, SIG_IGN);
			signal(SIGHUP, SIG_IGN);
			alarm(TASK_HARD_TIMEOUT);

			if (secure_me_sub(uid, gid)) {
				exit(1);
			}

			 // By not popping it from the stack in lua_init, we don't need to push it here
			//lua_pushcfunction(L, pcall_interrhdl);

			lua_rawgeti(L, LUA_REGISTRYINDEX, lua_main);

			lua_pushlstring(L, caller, caller_len);
			lua_pushlstring(L, script, script_len);
			lua_pushlstring(L, args, args_len);

			free(caller);
			free(script);
			free(args);

			if (lua_pcall(L, 3, 0, -5)) {
				exit(1);
			}
			exit(0);
		} else if(subworker < 0) {
			exit(1);
		}

		free(caller);
		free(script);
		free(args);

		close(stdout_pipe[1]);

		worker_pid = subworker;
		signal(SIGALRM, sigalrm_killchild_rcvd);
		alarm(30);

		stdout_fd = fdopen(stdout_pipe[0], "r");
		while(!feof(stdout_fd)) {
			if (!fgets(buffer, BUFFER_LEN, stdout_fd)) {
				break;
			}
			WRITE_AMQP(buffer, strlen(buffer));
		}

		fclose(stdout_fd);

		waitpid(subworker, &exitstatus, 0);

		if (WIFSIGNALED(exitstatus)) {
			switch(WTERMSIG(exitstatus)) {
				case 9: // SIGKILL, really only happens when OOM
					WRITE_AMQP("\1MEMORY_LIMIT\n", 14);
					break;
				default:
					WRITE_AMQP("\1INTERNAL\n", 10);
					break;
			}
		} else if(WIFEXITED(exitstatus)) {
			switch(WEXITSTATUS(exitstatus)) {
				case EXIT_SOFT_TIMEOUT:
					WRITE_AMQP("\1SOFT_TIMEOUT\n", 14);
					break;
				case EXIT_HARD_TIMEOUT:
					WRITE_AMQP("\1HARD_TIMEOUT\n", 14);
					break;
				case EXIT_KILLSWITCH:
					printf("Killswitch engaged!!!\n");
					WRITE_AMQP("\1INTERNAL\n", 10);
					break;
				case EXIT_OK:
					WRITE_AMQP("\1OK\n", 4);
					break;
				case EXIT_MEMLIMIT:
					WRITE_AMQP("\1MEMORY_LIMIT\n", 14);
					break;
				default:
					WRITE_AMQP("\1INTERNAL\n", 10);
					printf("EXITED %d\n", WEXITSTATUS(exitstatus));
					break;
			}
		}

		exit(0);
	}

	return 0;
}
