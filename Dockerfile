FROM node:24-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    DSH_HOME=/dsh \
    DSH_WORKSPACE=/workspace \
    DSH_TELEMETRY_DISABLED=1

WORKDIR /workspace

ARG DSH_VERSION=0.1.2-rc.1
RUN npm install --global @deepseek-ai/dsh@${DSH_VERSION} --omit=dev \
    && npm cache clean --force

COPY dsh/cordis.patch.yml /dsh/cordis.patch.yml

RUN mkdir -p /dsh /workspace && chown -R node:node /dsh /workspace
USER node

EXPOSE 3080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3080/ >/dev/null || exit 1

ENTRYPOINT ["dsh", "--profile", "web", "--no-open"]
CMD ["--port", "3080"]
