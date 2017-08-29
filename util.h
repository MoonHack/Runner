void zmq_setallopts(void* socket, int rcvtimeo, int sndtimeo) {
	int val = 0;
	zmq_setsockopt(socket, ZMQ_LINGER, &val, sizeof(int));
	zmq_setsockopt(socket, ZMQ_RCVTIMEO, &rcvtimeo, sizeof(int));
	zmq_setsockopt(socket, ZMQ_SNDTIMEO, &sndtimeo, sizeof(int));
}

void noop_hdlr() {

}