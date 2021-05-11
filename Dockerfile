FROM ubuntu:20.04

# Install supervisor, postfix
# Install postfix first to get the first account (101)
# Install opendkim second to get the second account (102)
RUN apt update && \
    apt install -y postfix \
        netcat \
        libsasl2-modules \
        ca-certificates \
        tzdata \
        supervisor \
        rsyslog \
        bash \
        opendkim-tools \
        curl \
        postfix-lmdb

# Set up configuration
COPY configs/*      /etc/
COPY scripts/*.sh   /

RUN chmod +x /*.sh

# Set up volumes
VOLUME [ "/var/spool/postfix", "/etc/postfix", "/etc/opendkim/keys" ]

# Run supervisord
USER    root
WORKDIR /tmp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD printf "EHLO healthcheck\n" | nc 127.0.0.1 587 | grep -qE "^220.*ESMTP Postfix"

EXPOSE 587
CMD [ "/bin/sh", "-c", "/docker-entrypoint.sh" ]
