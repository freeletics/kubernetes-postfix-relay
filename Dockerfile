FROM alpine:3.13.5

# Install supervisor, postfix
# Install postfix first to get the first account (101)
# Install opendkim second to get the second account (102)
RUN apk add --no-cache postfix && \
    apk add --no-cache opendkim && \
    apk add --no-cache --upgrade cyrus-sasl cyrus-sasl-static \
        cyrus-sasl-digestmd5 cyrus-sasl-crammd5 \
        cyrus-sasl-login cyrus-sasl-ntlm && \
    apk add --no-cache --upgrade ca-certificates tzdata supervisor \
        rsyslog musl musl-utils bash opendkim-utils libcurl jsoncpp \
        lmdb && \
    (rm "/tmp/"* 2>/dev/null || true) && \
    (rm -rf /var/cache/apk/* 2>/dev/null || true)

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
