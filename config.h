#define ZMQ_SOCKET "ipc:///tmp/moonhack-master-to-workers"
#define ZMQ_THREADS 4
#define WORKER_COUNT 64

#define TASK_HARD_TIMEOUT 7
#define TASK_MEMORY_LIMIT (8 * 1024 * 1024)
