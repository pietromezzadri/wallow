# SPDX-License-Identifier: AGPL-3.0-or-later
ARG BUILD_VERSION

FROM node:24-bookworm-slim AS base

COPY --from=oven/bun:1.4.2 /usr/local/bin/bun /usr/local/bin/bun
RUN ln -sf /usr/local/bin/bun /usr/local/bin/bunx

WORKDIR /usr/src/app

FROM base AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
		build-essential \
		gcc \
		libssl-dev \
		pkg-config \
		openssl \
		libvips-dev \
		python3 && \
	rm -rf /var/lib/apt/lists/*

COPY . .

RUN bun install --frozen-lockfile
RUN bun --filter fluxer_api run build

# bun has no equivalent of `pnpm deploy --prod` (a pruned, self-contained output
# directory for one workspace package), so a second, isolated install pass
# produces a clean production-only node_modules instead: this stage never saw
# the devDependencies installed in `build`, so `--production` has nothing to prune.
FROM base AS prod-deps

RUN apt-get update && apt-get install -y --no-install-recommends \
		build-essential \
		gcc \
		libssl-dev \
		pkg-config \
		openssl \
		libvips-dev \
		python3 && \
	rm -rf /var/lib/apt/lists/*

COPY . .

RUN bun install --frozen-lockfile --production

FROM node:24-bookworm-slim

ARG BUILD_VERSION
ARG SOURCE_SHA
ARG SOURCE_DATE

LABEL org.opencontainers.image.title="fluxer-api"
LABEL org.opencontainers.image.description="Fluxer HTTP API and background workers"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"
LABEL org.opencontainers.image.vendor="Fluxer"
LABEL org.opencontainers.image.url="https://fluxer.app"
LABEL org.opencontainers.image.documentation="https://docs.fluxer.app"
LABEL org.opencontainers.image.source="https://github.com/fluxerapp/fluxer"
LABEL org.opencontainers.image.version="${BUILD_VERSION}"
LABEL org.opencontainers.image.revision="${SOURCE_SHA}"
LABEL org.opencontainers.image.created="${SOURCE_DATE}"
LABEL app.fluxer.build-version="${BUILD_VERSION}"

WORKDIR /usr/src/app

RUN echo 'deb http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/backports.list && \
	apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates \
		ffmpeg \
		libimage-exiftool-perl \
		libwebp7 \
		libwebpmux3 \
		libheif1 \
		libvips42 && \
	apt-get install -y --no-install-recommends -t bookworm-backports \
		libheif-plugin-libde265 \
		libheif-plugin-dav1d && \
	rm -rf /var/lib/apt/lists/*

# NOTE: without pnpm's per-package `deploy --prod` pruning, this ships the whole
# monorepo's production node_modules + source tree rather than just fluxer_api's
# slice of it — a real image-size regression, accepted for a personal fork rather
# than hand-rolling dependency-graph pruning bun has no built-in equivalent for.
COPY --from=prod-deps /usr/src/app ./
COPY --from=build /usr/src/app/fluxer_api/dist ./fluxer_api/dist
COPY --from=build /usr/src/app/tsconfigs ./tsconfigs

RUN rm -rf fluxer_api/pkgs && \
	chown -R 65532:65532 /usr/src/app

WORKDIR /usr/src/app/fluxer_api

ENV HOME=/usr/src/app
ENV NODE_ENV=production
ENV NODE_OPTIONS="--enable-source-maps"
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV BUILD_VERSION=${BUILD_VERSION}

USER 65532:65532

EXPOSE 8080

CMD ["node", "dist/AppEntrypoint.js"]
