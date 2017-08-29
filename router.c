#include <zmq.h>
#include <signal.h>
#include "./util.h"
#include "./config.h"

int main() {
	signal(SIGINT, SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	signal(SIGCHLD, noop_hdlr);

	void* ctx = zmq_init(ZMQ_THREADS);
	void* frontend = zmq_socket(ctx, ZMQ_XREP);
	zmq_bind(frontend, "tcp://*:5556");
	zmq_setallopts(frontend, -1, 5000);

	void* backend = zmq_socket(ctx, ZMQ_XREQ);
	zmq_setallopts(backend, 10000, 60000);

	zmq_device(ZMQ_QUEUE, frontend, backend);
	return 1;
}
