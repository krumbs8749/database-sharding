FROM ubuntu:22.04 as base-image

# Install systemd
RUN apt-get update && apt-get install -y systemd systemd-sysv dbus bash-completion

# Mask a few services that we do not need
RUN systemctl mask dev-hugepages.mount sys-fs-fuse-connections.mount \
    sys-kernel-config.mount sys-kernel-debug.mount && \
    systemctl disable systemd-update-utmp.service && \
    systemctl disable systemd-tmpfiles-setup.service

# Define environment variable
ENV container docker

# Copy the systemd unit file and entry script
COPY ./docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

RUN echo '\n\
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then\n\
  . /etc/bash_completion\n\
fi' >> /root/.bashrc

# Define the entry point script
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command
CMD ["/lib/systemd/systemd"]

# Run systemd init as the main process
STOPSIGNAL SIGRTMIN+3

# Inform Docker that the container wants to run in an init system
LABEL "exec.systemd"="true"

FROM base-image as topology-image

RUN apt install -y zookeeper
COPY ./docker/topology/zookeeper.service /etc/systemd/system/
COPY ./docker/topology/env /var/lib/zookeeper/
RUN echo 1 > /etc/zookeeper/conf/myid
RUN systemctl enable zookeeper


FROM base-image as vtctl-image

RUN apt install -y netcat

RUN adduser --disabled-password --gecos "" vitess
RUN mkdir /var/log/vitess && chown vitess:vitess /var/log/vitess
RUN touch /home/vitess/vtconfig.yaml

COPY --from=binaries-image /vt/vitess/bin/vtctldclient /usr/local/bin/
COPY --from=binaries-image /vt/vitess/bin/vtctld /usr/local/bin/

COPY ./docker/vtctl/add_cellinfo.sh /home/vitess/
COPY ./docker/vtctl/create_keyspace.sh /home/vitess/
COPY ./docker/vtctl/set_durability_policy.sh /home/vitess/

COPY ./docker/vtctl/vtctld.service /etc/systemd/system/
COPY ./docker/vtctl/init-keyspace.service /etc/systemd/system/

RUN systemctl enable vtctld
RUN systemctl enable init-keyspace