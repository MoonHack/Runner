#include <zmq.h>
#include <signal.h>
#include <string.h>
#include "./util.h"
#include "./config.h"

static int usage() {
	printf("./router (-bc|-bb BACKEND) (-fc|-fb FRONTEND)...\n");
	return 1;	
}

static int init(int argc, char **argv, void *frontend, void *backend) {
	if (argc < 2 || argc % 2 != 1) {
		return usage();
	}

	signal(SIGINT, SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	signal(SIGCHLD, noop_hdlr);

	zmq_setallopts(frontend, -1, 5000);

	zmq_setallopts(backend, 10000, 60000);

	int i; char *mode, *path; void *sck;
	for (i = 1; i < argc; i += 2) {
		mode = argv[i];
		path = argv[i + 1];
		if (mode[0] != '-' || strlen(mode) != 3) {
			return usage();	
		}
		switch(mode[1]) {
			case 'f':
				sck = frontend;
				break;
			case 'b':
				sck = backend;
				break;
			default:
				return usage();
		}
		switch(mode[2]) {
			case 'c':
				zmq_connect(sck, path);
				break;
			case 'b':
				zmq_bind(sck, path);
				break;
			default:
				return usage();
		}
	}

	return 0;
}

int main(int argc, char **argv) {
	void* ctx = zmq_init(ZMQ_THREADS);
	void* frontend = zmq_socket(ctx, ZMQ_XREP);
	void* backend = zmq_socket(ctx, ZMQ_XREQ);

	int res = init(argc, argv, frontend, backend);
	if (res) {
		return res;
	}

	zmq_device(ZMQ_QUEUE, frontend, backend);
	return 1;
}
