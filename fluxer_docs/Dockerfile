# SPDX-License-Identifier: AGPL-3.0-or-later
ARG BUILD_VERSION

FROM node:24-bookworm-slim AS base

COPY --from=oven/bun:1.4.2 /usr/local/bin/bun /usr/local/bin/bun

WORKDIR /usr/src/app

FROM base AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
		build-essential \
		gcc \
		libvips-dev \
		pkg-config \
		python3 && \
	rm -rf /var/lib/apt/lists/*

COPY . .

RUN bun install --frozen-lockfile
RUN bun --filter fluxer_docs run build

# bun has no equivalent of `pnpm deploy --prod`; see fluxer_api/Dockerfile for why
# this is a second, isolated install pass rather than pruning in place.
FROM base AS prod-deps

RUN apt-get update && apt-get install -y --no-install-recommends \
		build-essential \
		gcc \
		libvips-dev \
		pkg-config \
		python3 && \
	rm -rf /var/lib/apt/lists/*

COPY . .

RUN bun install --frozen-lockfile --production

FROM node:24-bookworm-slim

ARG BUILD_VERSION=""
ARG SOURCE_SHA=""
ARG SOURCE_DATE=""

WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates \
		libvips42 && \
	rm -rf /var/lib/apt/lists/*

COPY --from=oven/bun:1.4.2 /usr/local/bin/bun /usr/local/bin/bun

LABEL maintainer="Fluxer"
LABEL org.opencontainers.image.title="fluxer-docs"
LABEL org.opencontainers.image.description="Fluxer API and protocol reference"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"
LABEL org.opencontainers.image.vendor="Fluxer"
LABEL org.opencontainers.image.url="https://fluxer.app"
LABEL org.opencontainers.image.documentation="https://docs.fluxer.app"
LABEL org.opencontainers.image.source="https://github.com/fluxerapp/fluxer"
LABEL org.opencontainers.image.version="${BUILD_VERSION}"
LABEL org.opencontainers.image.revision="${SOURCE_SHA}"
LABEL org.opencontainers.image.created="${SOURCE_DATE}"
LABEL app.fluxer.build-version="${BUILD_VERSION}"

# See fluxer_api/Dockerfile: no pnpm-deploy equivalent, so this ships the whole
# monorepo's production node_modules + source tree, not just fluxer_docs's slice.
COPY --from=prod-deps /usr/src/app ./
COPY --from=build /usr/src/app/fluxer_docs/dist ./fluxer_docs/dist

RUN chown -R 65532:65532 /usr/src/app

WORKDIR /usr/src/app/fluxer_docs

ENV HOME=/usr/src/app
ENV NODE_ENV=production
ENV NODE_OPTIONS="--enable-source-maps"
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV BUILD_VERSION=${BUILD_VERSION}

USER 65532:65532

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
	CMD ["bunx", "tsx", "scripts/Healthcheck.ts"]

CMD ["bunx", "tsx", "scripts/StartServer.ts"]
