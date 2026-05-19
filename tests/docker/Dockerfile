FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    diffutils \
    openssh-client \
    openssh-server \
    procps \
    sudo \
  && rm -rf /var/lib/apt/lists/*

COPY . /src

RUN chmod +x \
    /src/bin/agentictl \
    /src/bin/agentictl-act \
    /src/bin/agentictl-nodes \
    /src/bin/agentictl-readonly \
    /src/install/install-node.sh \
    /src/packaging/build-tarball.sh \
    /src/tests/run.sh \
    /src/tests/docker/scripts/*.sh \
    /src/tests/docker/bin/systemctl \
  && install -m 0755 /src/tests/docker/bin/systemctl /usr/local/sbin/systemctl \
  && install -m 0755 /src/tests/docker/bin/systemctl /usr/bin/systemctl \
  && mkdir -p /run/sshd

WORKDIR /src
