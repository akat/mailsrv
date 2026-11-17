# mailsrv-tools: εργαλεία λειτουργίας για τον Stalwart (ΟΧΙ ο ίδιος ο mail server).
# Τρέχει on-demand με `docker run --rm`. Δεν μένει μόνιμα ενεργό.
FROM alpine:3.20

RUN apk add --no-cache bash bind-tools curl netcat-openbsd iproute2 coreutils docker-cli

COPY scripts/preflight.sh scripts/check-dns.sh scripts/backup.sh /opt/mailsrv/scripts/
COPY tools/entrypoint.sh /usr/local/bin/mailsrv
RUN chmod 0755 /opt/mailsrv/scripts/*.sh /usr/local/bin/mailsrv

LABEL org.opencontainers.image.title="mailsrv-tools" \
      org.opencontainers.image.description="Preflight, DNS check and backup tools for the Stalwart mail stack"

ENTRYPOINT ["/usr/local/bin/mailsrv"]
CMD ["help"]
