#include <zmq.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "./util.h"

// Dummy script to manually trigger a script run like: ./run user user.script '{}'

void *ctx;
void *zsocket;

int _main(int argc, char **argv) {
	char *run_id = "1337";
	char *caller = argv[1];
	char *script = argv[2];
	char *args = argv[3];

	struct sockaddr_in myaddr;
	int s;

	struct timeval timeout;
	timeout.tv_sec = 10;
	timeout.tv_usec = 0;

	myaddr.sin_family = AF_INET;
	myaddr.sin_port = 0;
	inet_aton("127.0.0.1", &myaddr.sin_addr);
	s = socket(PF_INET, SOCK_STREAM, 0);
	if (!s) {
		perror("socket");
		return 1;
	}
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));
	setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (char*)&timeout, sizeof(timeout));
	if (bind(s, (struct sockaddr*)&myaddr, sizeof(myaddr)) < 0) {
		perror("bind");
		return 1;
	}

	socklen_t len_inet = sizeof(myaddr);
	if (getsockname(s, (struct sockaddr *)&myaddr, &len_inet) < 0) {
		perror("getsockname");
		return 1;
	}

	if (listen(s, 5) < 0) {
		perror("listen");
		return 1;
	}

	zmq_send(zsocket, &myaddr.sin_addr, sizeof(myaddr.sin_addr), ZMQ_SNDMORE);
	zmq_send(zsocket, &myaddr.sin_port, sizeof(myaddr.sin_port), ZMQ_SNDMORE);
	zmq_send(zsocket, run_id, strlen(run_id), ZMQ_SNDMORE);
	zmq_send(zsocket, caller, strlen(caller), ZMQ_SNDMORE);
	zmq_send(zsocket, script, strlen(script), ZMQ_SNDMORE);
	zmq_send(zsocket, args, strlen(args), 0);

	int sc = accept(s, NULL, NULL);
	setsockopt(sc, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));
	setsockopt(sc, SOL_SOCKET, SO_SNDTIMEO, (char*)&timeout, sizeof(timeout));
	close(s);

	char buffer[65537];
	int buf_len = zmq_recv(zsocket, &buffer, 65536, 0);
	buffer[buf_len] = 0;
	printf("RESULT: %s", buffer);

	FILE *sockfd = fdopen(sc, "r");
	while(!feof(sockfd) && fgets(buffer, 65536, sockfd)) {
		printf("%s", buffer);
	}

	fclose(sockfd);
	close(sc);

	return 0;
}

int main(int argc, char **argv) {
	ctx = zmq_init(1);
	zsocket = zmq_socket(ctx, ZMQ_REQ);
	zmq_connect(zsocket, "tcp://127.0.0.1:5556");
	zmq_setallopts(zsocket, 60000, 60000);
	while (1) {
		if (_main(argc, argv)) {
			return 1;
		}
	}
	return 0;
}
