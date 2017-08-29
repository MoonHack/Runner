#include <zmq.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include "./util.h"
#include "./config.h"

static int usage() {
	printf("./router THREADS (-bc|-bb BACKEND) (-fc|-fb FRONTEND)...\n");
	return 1;	
}

int main(int argc, char **argv) {
	if (argc < 3 || argc % 2 == 1) {
		return usage();
	}

	void* ctx = zmq_init(atoi(argv[1]));
	void* frontend = zmq_socket(ctx, ZMQ_XREP);
	void* backend = zmq_socket(ctx, ZMQ_XREQ);

	zmq_setallopts(frontend, -1, 5000);

	zmq_setallopts(backend, 10000, 60000);

	int i; char *mode, *path; void *sck;
	for (i = 2; i < argc; i += 2) {
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

	zmq_device(ZMQ_QUEUE, frontend, backend);
	return 1;
}
