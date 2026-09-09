FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    DSH_HOME=/dsh \
    DSH_WORKSPACE=/workspace \
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
      s3fs \
      tar \
      unzip \
      util-linux \
      vim-tiny \
      wget \
      xz-utils \
    && if [ -f /etc/fuse.conf ]; then \
         sed -i 's/^#[[:space:]]*user_allow_other/user_allow_other/' /etc/fuse.conf; \
         grep -q '^user_allow_other' /etc/fuse.conf || echo user_allow_other >> /etc/fuse.conf; \
       fi \
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

WORKDIR /workspace

ARG DSH_VERSION=0.1.2-rc.1
RUN npm install --global @deepseek-ai/dsh@${DSH_VERSION} --omit=dev \
    && npm cache clean --force

COPY dsh/cordis.patch.yml /opt/dsh-web/cordis.patch.yml
COPY scripts/entrypoint.sh scripts/sync-provider.sh scripts/mount-workspace.sh /opt/dsh-web/
RUN chmod +x /opt/dsh-web/entrypoint.sh /opt/dsh-web/sync-provider.sh /opt/dsh-web/mount-workspace.sh \
    && mkdir -p /dsh /workspace \
    && cp /opt/dsh-web/cordis.patch.yml /dsh/cordis.patch.yml

EXPOSE 3080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3080/ >/dev/null || exit 1

ENTRYPOINT ["/opt/dsh-web/entrypoint.sh"]
CMD ["--port", "3080"]
