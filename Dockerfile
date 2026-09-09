FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    DSH_HOME=/root/.dsh \
    DSH_TELEMETRY_DISABLED=1

# General-purpose base tools + Node 24 (official tarball).
ARG NODE_VERSION=24.11.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      dnsutils \
      git \
      gzip \
      iproute2 \
      iputils-ping \
      jq \
      less \
      netcat-openbsd \
      openssh-client \
      procps \
      python3 \
      tar \
      unzip \
      vim-tiny \
      wget \
      xz-utils \
    && ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
         amd64) NODE_ARCH=x64 ;; \
         arm64) NODE_ARCH=arm64 ;; \
         *) echo "unsupported arch: $ARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
         | tar -xJ -C /usr/local --strip-components=1 \
    && node -v && npm -v \
    && rm -rf /var/lib/apt/lists/*

# AWS SDK for the Node S3 sync daemon (s3-sync.mjs). KS3 works with these
# @aws-sdk/client-s3 client params; rclone's generic S3 driver does not.
ARG AWS_SDK_S3_VERSION=3.1107.0
RUN mkdir -p /opt/dsh-web \
    && npm install --prefix /opt/dsh-web @aws-sdk/client-s3@${AWS_SDK_S3_VERSION} --omit=dev \
    && rm -rf /opt/dsh-web/node_modules/.cache

WORKDIR /root

ARG DSH_VERSION=0.1.2-rc.1
RUN npm install --global @deepseek-ai/dsh@${DSH_VERSION} --omit=dev \
    && npm cache clean --force

COPY dsh/cordis.patch.yml /opt/dsh-web/cordis.patch.yml
COPY scripts/entrypoint.sh scripts/sync-provider.sh scripts/sync-workspace.sh scripts/s3-sync.mjs /opt/dsh-web/
RUN chmod +x /opt/dsh-web/entrypoint.sh /opt/dsh-web/sync-provider.sh /opt/dsh-web/sync-workspace.sh \
    && mkdir -p /root/.dsh /root \
    && cp /opt/dsh-web/cordis.patch.yml /root/.dsh/cordis.patch.yml

EXPOSE 3080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3080/ >/dev/null || exit 1

ENTRYPOINT ["/opt/dsh-web/entrypoint.sh"]
CMD ["--port", "3080"]
