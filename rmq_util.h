#include <amqp_tcp_socket.h>
#include <amqp.h>
#include <amqp_framing.h>

#include "./config.h"

#ifndef _MH_RMQ_UTIL_H
#define _MH_RMQ_UTIL_H 1

amqp_bytes_t aqueue;
amqp_socket_t *asocket = NULL;
amqp_connection_state_t aconn;

struct command_request_t {
	uint32_t run_id_len;
	uint32_t caller_len;
	uint32_t script_len;
	uint32_t args_len;
};

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

void _util_init_rmq() {
	int status;

	aqueue = amqp_cstring_bytes("moonhack_command_jobs");

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
	queue_attributes.entries[0].key = amqp_cstring_bytes("x-expires");
	queue_attributes.entries[0].value.kind = AMQP_FIELD_KIND_I32;
	queue_attributes.entries[0].value.value.i32 = 30000;

	amqp_queue_declare(aconn, 1,
		aqueue,
		0,
		0,
		0,
		0,
		queue_attributes);
}

#endif
