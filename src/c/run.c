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
#include <uuid/uuid.h>
#include "./rmq_util.h"

// Dummy script to manually trigger a script run like: ./run user user.script '{}'

#define COPYIN(VAR) \
	memcpy(message + pos, VAR, command. VAR ## _len); \
	pos += command. VAR ## _len;

int _main(int argc, char **argv) {
	uuid_t uuid;
	uuid_generate_random(uuid);
	amqp_bytes_t consumer_tag = amqp_cstring_bytes("run_consumer");
	char run_id[64];
	uuid_unparse(uuid, run_id);
	char *caller = argv[1];
	char *script = argv[2];
	char *args = argv[3];
	char queue_name[65536];
	amqp_bytes_t arepqueue;
	sprintf(queue_name, "moonhack_command_results_%s", run_id);
	arepqueue.bytes = queue_name;
	arepqueue.len = strlen(queue_name);

	printf("Q: %s\n", queue_name);

	amqp_table_t queue_attributes;
	queue_attributes.num_entries = 1;
	queue_attributes.entries = malloc(sizeof(amqp_table_entry_t) * queue_attributes.num_entries);
	queue_attributes.entries[0].key = amqp_cstring_bytes("x-expires");
	queue_attributes.entries[0].value.kind = AMQP_FIELD_KIND_I32;
	queue_attributes.entries[0].value.value.i32 = 60000;
	//queue_attributes.entries[1].key = amqp_cstring_bytes("x-message-ttl");
	//queue_attributes.entries[1].value.kind = AMQP_FIELD_KIND_I32;
	//queue_attributes.entries[1].value.value.i32 = 60000;

	struct command_request_t command;
	command.run_id_len = strlen(run_id);
	command.caller_len = strlen(caller);
	command.script_len = strlen(script);
	command.args_len = strlen(args);

	int pos = sizeof(command);
	int msg_len = pos + command.run_id_len + command.caller_len + command.script_len + command.args_len;
	char *message = malloc(msg_len);
	memcpy(message, &command, sizeof(struct command_request_t));
	COPYIN(run_id);
	COPYIN(caller);
	COPYIN(script);
	COPYIN(args);

	struct timeval timeout;
	timeout.tv_usec = 0;
	timeout.tv_sec = 30;

	amqp_bytes_t message_bytes;
	message_bytes.len = msg_len;
	message_bytes.bytes = message;

	amqp_basic_properties_t props;
	props._flags = AMQP_BASIC_DELIVERY_MODE_FLAG;
	props.delivery_mode = 1;

	amqp_queue_declare(aconn, 1,
		arepqueue,
		0,
		0,
		0,
		1,
		queue_attributes);

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

	char buffer[65536];
	amqp_basic_consume(aconn, 1, arepqueue, consumer_tag, 0, 1, 0, amqp_empty_table);
	die_on_amqp_error(amqp_get_rpc_reply(aconn), "Consuming");
	amqp_rpc_reply_t res;
	while (1) {
		amqp_envelope_t envelope;
		amqp_maybe_release_buffers(aconn);
		res = amqp_consume_message(aconn, &envelope, &timeout, 0);
		if (AMQP_RESPONSE_NORMAL != res.reply_type) {
			break;
		}
		memcpy(buffer, envelope.message.body.bytes, envelope.message.body.len);
		buffer[envelope.message.body.len] = 0;
		printf("%s", buffer);
		if (buffer[0] == '\1') {
			break;
		}
	}
	amqp_basic_cancel(aconn, 1, consumer_tag);

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
