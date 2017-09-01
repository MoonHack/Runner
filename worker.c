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

#define BASE_LEN 256
#define BUFFER_LEN 65536
#define ARGS_LEN BUFFER_LEN

#define EXIT_OK 0
#define EXIT_HARD_TIMEOUT 5
#define EXIT_SOFT_TIMEOUT 6
#define EXIT_FORCED 7

FILE *urandom_fh;
pid_t worker_pid;
lua_State *L;
int lua_main;
int lua_prot_depth = 0;
int lua_exit_on_prot_leave = 0;
int lua_alarm_delayed = 0;
#define cgroup_mem_limit "/var/root/cg_mem/memory.limit_in_bytes"
#define cgroup_memsw_limit "/var/root/cg_mem/memory.memsw.limit_in_bytes"
#define cgroup_mem_tasks "/var/root/cg_mem/tasks"

#define COPYIN(VAR) \
	memcpy(VAR, envelope.message.body.bytes + pos, command-> VAR ## _len + 1); \
	pos += command-> VAR ## _len + 1;

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

size_t read_random(void *buffer, size_t len) {
	if (!urandom_fh) {
		return 0;
	}
	size_t res = fread(buffer, len, 1, urandom_fh);
	return res;
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

	// run_id, caller, script, args, enterProt, leaveProt
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
	int err;

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

int main(int argc, char **argv) {
	if (argc < 2) {
		printf("Usage: ./worker BACKEND\n");
		return 1;
	}

	int uid = getuid();
	int gid = getgid();

	if (secure_me(uid, gid)) {
		return 1;
	}

	urandom_fh = fopen("/dev/urandom", "rb");

	lua_init();

	signal(SIGCHLD, noop_hdlr);

	_util_init_rmq();
	//amqp_queue_bind(aconn, 1, aqueue, aexchange, amqp_empty_bytes, amqp_empty_table);
	//die_on_amqp_error(amqp_get_rpc_reply(aconn), "Binding queue");
	amqp_basic_consume(aconn, 1, aqueue, amqp_empty_bytes, 0, 1, 0, amqp_empty_table);
	die_on_amqp_error(amqp_get_rpc_reply(aconn), "Consuming");

	struct sockaddr_in saddr;
	saddr.sin_family = AF_INET;

	struct timeval timeout;
	timeout.tv_sec = 10;
	timeout.tv_usec = 0;

	char caller[BASE_LEN + 1], script[BASE_LEN + 1], run_id[BASE_LEN + 1], args[ARGS_LEN + 1];
	int caller_len, script_len, run_id_len, args_len;

	int stdout_pipe[2];

	int exitstatus;
	FILE *stdout_fd;
	char buffer[BUFFER_LEN + 1];

	amqp_rpc_reply_t res;
	amqp_envelope_t envelope;
	struct command_request_t *command;

	while (1) {
		amqp_envelope_t envelope;
		amqp_maybe_release_buffers(aconn);
		res = amqp_consume_message(aconn, &envelope, NULL, 0);
		if (AMQP_RESPONSE_NORMAL != res.reply_type) {
			return 1;
		}

		//envelope.message.body.bytes, envelope.message.body.len

		command = envelope.message.body.bytes;
		if (command->run_id_len > BASE_LEN ||
			command->caller_len > BASE_LEN ||
			command->script_len > BASE_LEN ||
			command->args_len > ARGS_LEN) {
			amqp_destroy_envelope(&envelope);
			continue;
		}

		int pos = sizeof(struct command_request_t);
		COPYIN(run_id);
		COPYIN(caller);
		COPYIN(script);
		COPYIN(args);

		saddr.sin_addr = command->sin_addr;
		saddr.sin_port = command->sin_port;

		caller[command->caller_len] = 0;
		script[command->script_len] = 0;
		run_id[command->run_id_len] = 0;
		args[command->args_len] = 0;

		amqp_destroy_envelope(&envelope);
		
		pid_t subworker_master = fork();
		if (subworker_master > 0) {
			waitpid(subworker_master, &exitstatus, 0);
			continue;
		} else if (subworker_master < 0) {
			exit(1);
		}

		// This all runs INSIDE THE FORK
		if (unshare(CLONE_NEWPID | CLONE_FILES)) {
			perror("CLONE_NEWPID_FILES");
			exit(1);
		}

		int sockfd = socket(PF_INET, SOCK_STREAM, 0);
		setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));
		setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (char*)&timeout, sizeof(timeout));
		if (connect(sockfd, (struct sockaddr *)&saddr, sizeof(saddr)) < 0) {
			//zmq_send(zsocket, "NOCONNECT\n", 10, 0);
			perror("connect");
			exit(1);
		}

		if(pipe(stdout_pipe)) {
			perror("stdout_pipe");
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
			signal(SIGTERM, SIG_IGN);
			signal(SIGINT, SIG_IGN);
			signal(SIGHUP, SIG_IGN);
			alarm(TASK_HARD_TIMEOUT);

			add_task_to_cgroup(getpid());

			urandom_fh = fopen("/dev/urandom", "rb");

			if (secure_me_sub(uid, gid)) {
				exit(1);
			}
			
			lua_rawgeti(L, LUA_REGISTRYINDEX, lua_main);
			lua_pushstring(L, run_id);
			lua_pushstring(L, caller);
			lua_pushstring(L, script);
			lua_pushstring(L, args);
			lua_call(L, 4, 0);
			exit(0);
		} else if(subworker < 0) {
			exit(1);
		}

		close(stdout_pipe[1]);

		worker_pid = subworker;
		signal(SIGALRM, sigalrm_killchild_rcvd);
		alarm(30);

		stdout_fd = fdopen(stdout_pipe[0], "r");
		while(!feof(stdout_fd)) {
			if (!fgets(buffer, BUFFER_LEN, stdout_fd)) {
				break;
			}
			if (write(sockfd, buffer, strlen(buffer)) < 0) {
				break;
			}
		}

		fclose(stdout_fd);

		waitpid(subworker, &exitstatus, 0);

		if (WIFSIGNALED(exitstatus)) {
			switch(WTERMSIG(exitstatus)) {
				case 9: // SIGKILL, really only happens when OOM
					if (write(sockfd, "\1\nMEMORY_LIMIT\n", 15) < 0) {
						perror("write");
					}
					break;
				default:
					if (write(sockfd, "\1\nINTERNAL\n", 11) < 0) {
						perror("write");
					}
					printf("KILLED %d\n", WTERMSIG(exitstatus));
					break;
			}
		} else if(WIFEXITED(exitstatus)) {
			switch(WEXITSTATUS(exitstatus)) {
				case EXIT_SOFT_TIMEOUT:
					if (write(sockfd, "\1\nSOFT_TIMEOUT\n", 15) < 0) {
						perror("write");
					}
					break;
				case EXIT_HARD_TIMEOUT:
					if (write(sockfd, "\1\nHARD_TIMEOUT\n", 15) < 0) {
						perror("write");
					}
					break;
				//case EXIT_FORCED:
				//	if (write(sockfd, "\1\nHARD_KILLED\n", 14) < 0) {
				//		perror("write");
				//	}					
				//	break;
				case EXIT_OK:
					if (write(sockfd, "\1\nOK\n", 5) < 0) {
						perror("write");
					}
					break;					
				default:
					if (write(sockfd, "\1\nINTERNAL\n", 11) < 0) {
						perror("write");
					}
					printf("EXITED %d\n", WEXITSTATUS(exitstatus));
					break;
			}
		}

		close(sockfd);
		exit(0);
	}

	return 0;
}