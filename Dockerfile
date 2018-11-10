FROM doridian/alpine-builder AS builder
RUN echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories
RUN echo "@edge http://dl-cdn.alpinelinux.org/alpine/edge/main/" >> /etc/apk/repositories

RUN apk add --no-cache rabbitmq-c-dev luarocks5.1 lua5.1-dev lua-uuid mongo-c-driver-dev@testing libbson@testing mongo-c-driver@testing libcrypto1.1@edge libssl1.1@edge

RUN mkdir -p /root/Runner/build/
COPY CMakeLists.txt dockercompile.sh /root/Runner/
COPY LuaJIT /root/Runner/LuaJIT/
COPY src /root/Runner/src/

RUN /root/Runner/dockercompile.sh

FROM alpine
RUN echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories
RUN echo "@edge http://dl-cdn.alpinelinux.org/alpine/edge/main/" >> /etc/apk/repositories

RUN apk add --no-cache rabbitmq-c lua-uuid mongo-c-driver@testing libbson@testing shadow libcrypto1.1@edge libssl1.1@edge

RUN useradd runner
RUN mkdir -p /opt/runnertmp /opt/runnertmp_rw /opt/cgroup

COPY dockerrun.sh /opt/Runner/
COPY --from=builder /root/Runner/build/worker /root/Runner/build/run /root/Runner/build/simple_master /opt/Runner/
COPY --from=builder /root/Runner/build/lua /opt/Runner/lua
COPY --from=builder /usr/local/lib/lua /usr/local/lib/lua/
COPY --from=builder /usr/local/share/lua /usr/local/share/lua/

WORKDIR /opt/Runner
ENV RUNNER_COUNT=1
ENTRYPOINT ["/opt/Runner/dockerrun.sh"]

