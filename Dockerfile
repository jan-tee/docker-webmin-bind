FROM ubuntu:noble-20241118.1 AS add-apt-repositories

# hadolint ignore=DL3008,DL3015
RUN apt-get update \
    && apt-get upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg --no-install-recommends \
    && apt-get install -y curl \
    && apt-key adv --fetch-keys https://download.webmin.com/developers-key.asc \
    && echo "deb https://download.webmin.com/download/newkey/repository stable contrib" >> /etc/apt/sources.list

FROM ubuntu:noble-20241118.1

LABEL maintainer="rickyelopez"

COPY --from=add-apt-repositories /etc/apt/trusted.gpg /etc/apt/trusted.gpg
COPY --from=add-apt-repositories /etc/apt/sources.list /etc/apt/sources.list

ARG BIND_VERSION=1:9.18.30-0ubuntu0.24.04.1
ARG WEBMIN_VERSION=2.202

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN  apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    dnsutils \
    tzdata \
    cron \
    isc-dhcp-server \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3015
RUN rm -rf /etc/apt/apt.conf.d/docker-gzip-indexes \
    && apt-get update \
    && apt-get upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bind9=${BIND_VERSION} \
    bind9-host=${BIND_VERSION} \
    webmin=${WEBMIN_VERSION} \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /sbin/entrypoint.sh

RUN chmod 755 /sbin/entrypoint.sh

RUN mkdir -p /var/log/supervisor

COPY supervisord.conf /etc/supervisor/supervisord.conf

EXPOSE 53/udp 53/tcp 10000/tcp 67/udp 68/udp

ENTRYPOINT ["/sbin/entrypoint.sh"]

CMD ["/usr/sbin/named"]
