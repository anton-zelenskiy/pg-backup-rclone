FROM postgres:16-alpine

ARG RCLONE_VERSION=1.69.1
ARG SUPERCRONIC_VERSION=0.2.33

RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    gzip \
    tar \
    unzip \
    && curl -fsSL "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
      -o /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic \
    && curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" \
      -o /tmp/rclone.zip \
    && unzip /tmp/rclone.zip -d /tmp \
    && mv "/tmp/rclone-v${RCLONE_VERSION}-linux-amd64/rclone" /usr/local/bin/rclone \
    && chmod +x /usr/local/bin/rclone \
    && rm -rf /tmp/rclone*

COPY scripts/ /scripts/
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh /scripts/backup.sh /scripts/lib/*.sh

# Sidecar only: root so /config/rclone.conf (often chmod 600 on host) is readable
USER root

ENV BACKUP_DIR=/backups
ENV RCLONE_CONFIG=/var/lib/rclone/rclone.conf
ENV SCHEDULE_ENABLED=true
ENV UPLOAD_ENABLED=true

VOLUME ["/backups", "/config"]

ENTRYPOINT ["/docker-entrypoint.sh"]
