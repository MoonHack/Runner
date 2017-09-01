#include <amqp_tcp_socket.h>
#include <amqp.h>
#include <amqp_framing.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "./rmq_util.h"

// Dummy script to manually trigger a script run like: ./run user user.script '{}'

#define COPYIN(VAR) \
	memcpy(message + pos, VAR, command. VAR ## _len + 1); \
	pos += command. VAR ## _len + 1;

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

	struct command_request_t command;
	command.run_id_len = strlen(run_id);
	command.caller_len = strlen(caller);
	command.script_len = strlen(script);
	command.args_len = strlen(args);
	command.sin_addr = myaddr.sin_addr;
	command.sin_port = myaddr.sin_port;

	int pos = sizeof(command);
	int msg_len = pos + command.run_id_len + command.caller_len + command.script_len + command.args_len + 4;
	char *message = malloc(msg_len);
	memcpy(message, &command, sizeof(struct command_request_t));
	COPYIN(run_id);
	COPYIN(caller);
	COPYIN(script);
	COPYIN(args);

	amqp_bytes_t message_bytes;
	message_bytes.len = msg_len;
	message_bytes.bytes = message;

	amqp_basic_properties_t props;
	props._flags = AMQP_BASIC_DELIVERY_MODE_FLAG;
	props.delivery_mode = 1;

	printf("Send: %s\n", amqp_error_string2(
							amqp_basic_publish(aconn,
								1,
								amqp_empty_bytes,
								aqueue,
								0,
								0,
								&props,
								message_bytes
							)
						)
		);

	int sc = accept(s, NULL, NULL);
	setsockopt(sc, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));
	setsockopt(sc, SOL_SOCKET, SO_SNDTIMEO, (char*)&timeout, sizeof(timeout));
	close(s);

	char buffer[65537];

	FILE *sockfd = fdopen(sc, "r");
	while(!feof(sockfd) && fgets(buffer, 65536, sockfd)) {
		printf("%s", buffer);
	}

	fclose(sockfd);
	close(sc);

	return 0;
}

int main(int argc, char **argv) {
	_util_init_rmq();
	int status;

	aconn = amqp_new_connection();

	asocket = amqp_tcp_socket_new(aconn);
	if (!asocket) {
		printf("Cannot create socket\n");
		return 1;
	}

	status = amqp_socket_open(asocket, "127.0.0.1", 5672);
	if (status) {
		printf("Cannot open socket\n");
		return 1;
	}

	die_on_amqp_error(amqp_login(aconn, "/", 0, 131072, 0, AMQP_SASL_METHOD_PLAIN, "guest", "guest"), "Logging in");
	amqp_channel_open(aconn, 1);
	die_on_amqp_error(amqp_get_rpc_reply(aconn), "Opening channel");

	if (strcmp(argv[1], "1") == 0) {
		while (1) {
			if (_main(argc - 1, argv + 1)) {
				return 1;
			}
		}
	} else {
		if (_main(argc, argv)) {
			return 1;
		}		
	}
	return 0;
}
