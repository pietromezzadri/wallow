#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Builds the app-proxy image from source directly into minikube's own Docker
# daemon (no registry push/pull needed -- `eval $(minikube docker-env)`
# redirects `docker` to the cluster's daemon for the rest of this shell).
#
# --build-arg FLUXER_APP_PROXY_TIME_FREEZE_ENABLED=false is NOT optional.
# Without it, fluxer_app_proxy/src/frozen_snapshots.rs serves a hardcoded,
# compiled-in HTML/JS snapshot from the real upstream Fluxer (complete with
# fluxerstatic.com asset URLs your CSP correctly blocks) instead of what this
# build actually produced -- the whole site renders blank. The real
# self-hosted CI workflow (build-app-proxy-self-hosted.yaml) sets this same
# flag for the same reason; a plain `docker build` doesn't inherit it, so it
# has to be passed explicitly every time this image is rebuilt.
set -euo pipefail

cd "$(dirname "$0")/../.."
eval "$(minikube docker-env)"

docker build \
	-f fluxer_app_proxy/Dockerfile \
	-t wallow-app-proxy:local \
	--build-arg FLUXER_APP_PROXY_TIME_FREEZE_ENABLED=false \
	.

echo "Built wallow-app-proxy:local into minikube's Docker daemon."
echo "Restart the running pod to pick it up: kubectl delete pod -n wallow -l app=app-proxy"
