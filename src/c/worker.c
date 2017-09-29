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

#include "./rmq_util.h"
#include "./config.h"

#define BUFFER_LEN 65536

#define RUN_ID_LEN 36
#define REPLY_QUEUE_LEN (25 + RUN_ID_LEN)

#define EXIT_OK 0
#define EXIT_HARD_TIMEOUT 5
#define EXIT_SOFT_TIMEOUT 6
#define EXIT_KILLSWITCH 7
#define EXIT_ERROR 4

FILE *pipe_fh;
pid_t worker_pid;
lua_State *L;
int lua_main;
int lua_prot_depth = 0;
int lua_exit_on_prot_leave = 0;
amqp_basic_properties_t props;

#define cgroup_mem_limit "/var/root/cg_mem/memory.limit_in_bytes"
#define cgroup_memsw_limit "/var/root/cg_mem/memory.memsw.limit_in_bytes"
#define cgroup_mem_tasks "/var/root/cg_mem/tasks"

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

void notify_user(const char *name, const char *data) {
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

static void set_memory_limit(const char *memlimit) {
	FILE *fd;

	fd = fopen(cgroup_mem_limit, "w");
	fputs(memlimit, fd);
	fclose(fd);

	fd = fopen(cgroup_memsw_limit, "w");
	fputs(memlimit, fd);
	fclose(fd);
}

static void add_task_to_cgroup(pid_t pid) {
	FILE *fd = fopen(cgroup_mem_tasks, "w");
	fprintf(fd, "%d\n", pid);
	fclose(fd);
}

void lua_enterprot() {
	if (++lua_prot_depth == 1) {
		set_memory_limit(TASK_MEMORY_LIMIT_HIGH);
	}
}

void lua_leaveprot() {
	--lua_prot_depth;
	if (lua_prot_depth < 0) {
		exit(3);
	} else if (lua_prot_depth == 0) {
		if (lua_exit_on_prot_leave) {
			exit(lua_exit_on_prot_leave);
		}
		set_memory_limit(TASK_MEMORY_LIMIT);
	}
}

static void lua_init() {
	L = luaL_newstate();
	luaL_openlibs(L);
	if(luaL_dofile(L, "main.luac")) {
		printf("Error loading Lua: %s\n", lua_tostring(L, -1));
		exit(1);
	}

	// caller, script, args
	lua_main = luaL_ref(L, LUA_REGISTRYINDEX);
}

static int cgroup_init() {
	char cgroup_mem_root[256];
	sprintf(cgroup_mem_root, "/sys/fs/cgroup/memory/%s/moonhack_cg_%d/", getenv("USER"), getpid());

	mkdir(cgroup_mem_root, 0700);
	if (mkdir("/var/root/cg_mem", 0700)) {
		perror("mkdir_cg_mem");
		return 1;
	}

	if (mount(cgroup_mem_root, "/var/root/cg_mem", "bind", MS_BIND, "")) {
		perror("mount_cg_mem");
		return 1;
	}

	set_memory_limit(TASK_MEMORY_LIMIT);
	return 0;
}

static int secure_me(int uid, int gid) {
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

	if (symlink(".", "/var/root/root")) {
		perror("symlink_var_root_root");
		return 1;
	}

	if (symlink(".", "/var/root/var")) {
		perror("symlink_var_root_var");
		return 1;
	}

	if (mkdir("/var/root/dev", 0755)) {
		perror("mkdir_dev");
		return 1;
	}

	if (cgroup_init()) {
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
	char arepqueue_bytes[REPLY_QUEUE_LEN] = "moonhack_command_results_00000000-0000-0000-0000-000000000000";
	amqp_bytes_t arepqueue;
	arepqueue.bytes = arepqueue_bytes;
	arepqueue.len = REPLY_QUEUE_LEN;

	amqp_bytes_t message_bytes;
	props._flags = AMQP_BASIC_DELIVERY_MODE_FLAG;
	props.delivery_mode = 2;

	int first_loop = 1;
	uint64_t pos;

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

		pid_t subworker_master = fork();
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

		pid_t subworker = fork();
		if (subworker == 0) {
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

			add_task_to_cgroup(getpid());

			if (secure_me_sub(uid, gid)) {
				exit(1);
			}

			lua_rawgeti(L, LUA_REGISTRYINDEX, lua_main);

			lua_pushlstring(L, caller, caller_len);
			lua_pushlstring(L, script, script_len);
			lua_pushlstring(L, args, args_len);

			free(caller);
			free(script);
			free(args);

			lua_call(L, 3, 0);

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
