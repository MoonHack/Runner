#include <amqp.h>

#ifndef _MH_RMQ_UTIL_H
#define _MH_RMQ_UTIL_H 1

amqp_bytes_t aqueue;
amqp_socket_t *asocket;
amqp_connection_state_t aconn;
amqp_bytes_t aexchange_notify;

#pragma pack(push, 1)
struct command_request_t {
	uint32_t run_id_len;
	uint32_t caller_len;
	uint32_t script_len;
	uint32_t args_len;
};
#pragma pack(pop)

void die_on_amqp_error(amqp_rpc_reply_t x, char const *context);
void _util_init_rmq();

#endif
