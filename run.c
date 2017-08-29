#include <zmq.h>
#include <unistd.h>
#include <string.h>
#include "./util.h"

// Dummy script to manually trigger a script run like: ./run user user.script '{}'

int main(int argc, char **argv) {
	void* ctx = zmq_init(1);
	void* socket = zmq_socket(ctx, ZMQ_REQ);
	zmq_connect(socket, "tcp://127.0.0.1:5556");
	zmq_setallopts(socket, 60000, 60000);
	char *run_id = "1337";
	char *caller = argv[1];
	char *script = argv[2];
	char *args = argv[3];

	zmq_send(socket, run_id, strlen(run_id), ZMQ_SNDMORE);
	zmq_send(socket, caller, strlen(caller), ZMQ_SNDMORE);
	zmq_send(socket, script, strlen(script), ZMQ_SNDMORE);
	zmq_send(socket, args, strlen(args), 0);

	int _zmq_rcvmore = 0;
	size_t _zmq_rcvmore_size = sizeof(int);

	char buf[65537];
	int buf_len;
	do {
		buf_len = zmq_recv(socket, buf, 65536, 0);
		buf[buf_len] = 0;
		if (write(1, buf, buf_len) < 0) {
			return 1;
		}
		zmq_getsockopt(socket, ZMQ_RCVMORE, &_zmq_rcvmore, &_zmq_rcvmore_size);
	} while(_zmq_rcvmore);

	return 0;
}
