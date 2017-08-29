#include <zmq.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include "./util.h"
#include "./config.h"

int main() {
	signal(SIGINT, SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	signal(SIGCHLD, noop_hdlr);

	//zmq_setallopts(-1, 5000);
	return 0;
}