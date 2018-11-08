#include <amqp_tcp_socket.h>
#include <amqp.h>
#include <amqp_framing.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

#include "./config.h"
#include "./rmq_util.h"

void die_on_amqp_error(amqp_rpc_reply_t x, char const *context) {
	switch (x.reply_type) {
	case AMQP_RESPONSE_NORMAL:
		return;

	case AMQP_RESPONSE_NONE:
		fprintf(stderr, "%s: missing RPC reply type!\n", context);
		break;

	case AMQP_RESPONSE_LIBRARY_EXCEPTION:
		fprintf(stderr, "%s: %s\n", context, amqp_error_string2(x.library_error));
		break;

	case AMQP_RESPONSE_SERVER_EXCEPTION:
		switch (x.reply.id) {
		case AMQP_CONNECTION_CLOSE_METHOD: {
			amqp_connection_close_t *m = (amqp_connection_close_t *) x.reply.decoded;
			fprintf(stderr, "%s: server connection error %uh, message: %.*s\n",
							context,
							m->reply_code,
							(int) m->reply_text.len, (char *) m->reply_text.bytes);
			break;
		}
		case AMQP_CHANNEL_CLOSE_METHOD: {
			amqp_channel_close_t *m = (amqp_channel_close_t *) x.reply.decoded;
			fprintf(stderr, "%s: server channel error %uh, message: %.*s\n",
							context,
							m->reply_code,
							(int) m->reply_text.len, (char *) m->reply_text.bytes);
			break;
		}
		default:
			fprintf(stderr, "%s: unknown server error, method id 0x%08X\n", context, x.reply.id);
			break;
		}
		break;
	}

	exit(1);
}

const char* _getenv_perm(const char *var) {
	const char *res = getenv(var);
	if (!res) {
		fprintf(stderr, "Missing variable: %s\n", var);
		exit(1);
	}
	return strdup(res);
}

void _util_init_rmq() {
	RMQ_HOST = _getenv_perm("RMQ_HOST");
	RMQ_PORT = atoi(getenv("RMQ_PORT"));
	RMQ_USER = _getenv_perm("RMQ_USER");
	RMQ_PASS = _getenv_perm("RMQ_PASS");

	int status;

	aqueue = amqp_cstring_bytes("moonhack_command_jobs");
	aexchange_notify = amqp_cstring_bytes("moonhack_notifications");

	aconn = amqp_new_connection();

	asocket = amqp_tcp_socket_new(aconn);
	if (!asocket) {
		printf("Cannot create socket\n");
		exit(1);
	}

	status = amqp_socket_open(asocket, RMQ_HOST, RMQ_PORT);
	if (status) {
		printf("Cannot open socket\n");
		exit(1);
	}

	die_on_amqp_error(amqp_login(aconn, "/", 0, 131072, 0, AMQP_SASL_METHOD_PLAIN, RMQ_USER, RMQ_PASS), "Logging in");
	amqp_channel_open(aconn, 1);
	die_on_amqp_error(amqp_get_rpc_reply(aconn), "Opening channel");

	amqp_table_t queue_attributes;
	queue_attributes.num_entries = 1;
	queue_attributes.entries = malloc(sizeof(amqp_table_entry_t) * queue_attributes.num_entries);
	queue_attributes.entries[0].key = amqp_cstring_bytes("x-message-ttl");
	queue_attributes.entries[0].value.kind = AMQP_FIELD_KIND_I32;
	queue_attributes.entries[0].value.value.i32 = 30000;

	amqp_queue_declare(aconn, 1,
		aqueue,
		0,
		1,
		0,
		0,
		queue_attributes);

	amqp_exchange_declare(aconn, 1,
		aexchange_notify,
		amqp_cstring_bytes("topic"),
		0,
		1,
		0,
		0,
		amqp_empty_table);
}
