# syntax=docker/dockerfile:1
#
# dsh web — DeepSeek Harness Web UI (container image)
# Runs `dsh --profile web` behind a Debian-slim Node 24 runtime.

FROM node:24-slim AS base

# --- system deps ------------------------------------------------------------
# git+python3 are useful for agent tooling / potential native builds inside the
# container; curl is handy for healthchecks. Keep the layer lean.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       git \
       python3 \
       make \
       g++ \
    && rm -rf /var/lib/apt/lists/*

# --- runtime layout ---------------------------------------------------------
ENV NODE_ENV=production
# All dsh user data / config / credentials / sessions live under DSH_HOME.
# Persist it with a volume for durable session history.
ENV DSH_HOME=/dsh
# Workspace root the agent operates in (what the model sees as {{cwd}}).
ENV DSH_WORKSPACE=/workspace
WORKDIR /workspace

# --- install dsh ------------------------------------------------------------
# Pin the exact version; @deepseek-ai/dsh is the single launcher that pulls in
# the web profile, frontend dist, LLM adapters, and tooling.
ARG DSH_VERSION=0.1.2-rc.1
RUN npm install --global @deepseek-ai/dsh@${DSH_VERSION} --omit=dev \
    && npm cache clean --force

# --- deploy-time config (home-level cordis patch) ----------------------------
# The web profile binds loopback by default and hard-rejects `--host 0.0.0.0`
# for safety. A deployment reaches all interfaces by overriding the `webserver`
# row in the home-level patch layer (applied after the bundle patches).
# See ./dsh/cordis.patch.yml.
COPY dsh/cordis.patch.yml /dsh/cordis.patch.yml

# The web UI reaches browsers over the LAN/container network.
EXPOSE 3080

# `--no-open` keeps the container from trying to open a browser.
# Telemetry is disabled in the image by default (override via compose env).
ENV DSH_TELEMETRY_DISABLED=1
ENTRYPOINT ["dsh", "--profile", "web", "--no-open"]

# Bind host/port come from the patch; `--port` can still be overridden.
CMD ["--port", "3080"]
