FROM node:24-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global pnpm@10 --omit=dev \
    && npm cache clean --force

ENV NODE_ENV=production \
    DSH_HOME=/dsh \
    DSH_WORKSPACE=/workspace \
    DSH_TELEMETRY_DISABLED=1

WORKDIR /workspace

ARG DSH_VERSION=0.1.2-rc.1
ARG DSH_AUTH_GATE_VERSION=0.12.0
RUN npm install --global @deepseek-ai/dsh@${DSH_VERSION} --omit=dev \
    && dsh plugin --profile web add dsh-auth-gate@${DSH_AUTH_GATE_VERSION} \
    && mkdir -p /opt/dsh-web \
    && cp -a /dsh /opt/dsh-web/home-seed \
    && npm cache clean --force

COPY dsh/cordis.patch.yml /opt/dsh-web/cordis.patch.yml
COPY scripts/entrypoint.sh /opt/dsh-web/entrypoint.sh
RUN chmod +x /opt/dsh-web/entrypoint.sh \
    && cp /opt/dsh-web/cordis.patch.yml /dsh/cordis.patch.yml \
    && cp /opt/dsh-web/cordis.patch.yml /opt/dsh-web/home-seed/cordis.patch.yml \
    && mkdir -p /dsh /workspace

EXPOSE 3080
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fsS http://127.0.0.1:3080/ >/dev/null || exit 1

ENTRYPOINT ["/opt/dsh-web/entrypoint.sh"]
CMD ["--port", "3080"]
