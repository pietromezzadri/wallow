#!/usr/bin/env bash
# Generates real random values for every key in 02-secrets-template.yaml.example and
# applies them directly to the cluster as the wallow-secrets Secret. Never
# writes a real secret value to a file on disk -- everything lives in shell
# variables for the lifetime of this process only, and is piped straight into
# `kubectl apply`.
#
# Idempotent / safe to re-run: --dry-run=client -o yaml | kubectl apply -f -
# recreates the same Secret object, so re-running this mints and applies a
# FRESH set of secrets every time. That's fine for a first install; it is
# NOT fine once the stack has real data, because a new POSTGRES_PASSWORD (or
# ERLANG_COOKIE, or any of the others) no longer matches what's already
# stored/negotiated in the running volumes -- see the big warning in
# fluxer_docs/src/installer/install.sh about exactly this. Re-run only before
# the stack has ever started, or delete+recreate the underlying volumes too.
#
# Generation recipes match fluxer_docs/src/installer/install.sh's
# fluxer_write_env / fluxer_generate_vapid exactly:
#   hex      -> openssl rand -hex 32
#   base64   -> openssl rand -base64 32
#   vapid    -> a real P-256 (prime256v1) EC keypair: the public key is
#               base64url of the 65-byte uncompressed point, the private key
#               is base64url of the 32-byte scalar. A plain random value does
#               NOT work here -- web push requires an actual EC keypair.
set -euo pipefail

NAMESPACE="wallow"
SECRET_NAME="wallow-secrets"

command -v openssl >/dev/null 2>&1 || { echo "openssl is required." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required." >&2; exit 1; }

rand_hex() { openssl rand -hex 32; }
rand_base64() { openssl rand -base64 32; }

# base64url with padding stripped, same helper install.sh uses.
base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Generates a P-256 keypair and prints "<public> <private>" (base64url, space
# separated) on success. Retries up to 8 times: on rare occasions the DER
# encoding of the private scalar comes out short (a leading zero byte gets
# trimmed), which this detects via the fixed SEC1 header prefix and discards.
generate_vapid() {
	local scratch header priv pub attempt=1
	scratch="$(mktemp -d)"
	trap 'rm -rf "$scratch"' RETURN
	while [ "$attempt" -le 8 ]; do
		openssl ecparam -name prime256v1 -genkey -noout -out "$scratch/vapid.pem" 2>/dev/null
		openssl ec -in "$scratch/vapid.pem" -outform DER -out "$scratch/vapid.der" 2>/dev/null
		openssl ec -in "$scratch/vapid.pem" -pubout -outform DER -out "$scratch/vapid.pub.der" 2>/dev/null
		header=$(od -An -tx1 -N7 <"$scratch/vapid.der" | tr -d ' \n')
		if [ "$header" = "30770201010420" ]; then
			priv=$(tail -c +8 "$scratch/vapid.der" | head -c 32 | base64url)
			pub=$(tail -c 65 "$scratch/vapid.pub.der" | base64url)
			if [ "${#priv}" -eq 43 ] && [ "${#pub}" -eq 87 ]; then
				printf '%s %s\n' "$pub" "$priv"
				return 0
			fi
		fi
		attempt=$((attempt + 1))
	done
	echo "Failed to generate a valid VAPID keypair after 8 attempts." >&2
	return 1
}

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

echo "Generating secrets for namespace ${NAMESPACE}..."

POSTGRES_PASSWORD="$(rand_hex)"
MEILI_MASTER_KEY="$(rand_hex)"
FLUXER_S3_ACCESS_KEY="fluxer"
FLUXER_S3_SECRET_KEY="$(rand_hex)"
FLUXER_SUDO_MODE_SECRET="$(rand_hex)"
FLUXER_CONNECTION_INITIATION_SECRET="$(rand_hex)"
FLUXER_GATEWAY_RPC_AUTH_TOKEN="$(rand_hex)"
FLUXER_MEDIA_PROXY_SECRET_KEY="$(rand_hex)"
FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64="$(rand_base64)"
FLUXER_ADMIN_SECRET_KEY_BASE="$(rand_hex)"
FLUXER_ADMIN_OAUTH_CLIENT_SECRET="$(rand_hex)"
FLUXER_ERLANG_COOKIE="$(rand_hex)"
LIVEKIT_API_KEY="fluxer"
LIVEKIT_API_SECRET="$(rand_hex)"

read -r FLUXER_VAPID_PUBLIC_KEY FLUXER_VAPID_PRIVATE_KEY < <(generate_vapid)

# Derived: LiveKit's own LIVEKIT_KEYS env var format, "<key>: <secret>".
LIVEKIT_KEYS="${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}"

kubectl create secret generic "$SECRET_NAME" \
	-n "$NAMESPACE" \
	--from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
	--from-literal=MEILI_MASTER_KEY="$MEILI_MASTER_KEY" \
	--from-literal=FLUXER_S3_ACCESS_KEY="$FLUXER_S3_ACCESS_KEY" \
	--from-literal=FLUXER_S3_SECRET_KEY="$FLUXER_S3_SECRET_KEY" \
	--from-literal=FLUXER_SUDO_MODE_SECRET="$FLUXER_SUDO_MODE_SECRET" \
	--from-literal=FLUXER_CONNECTION_INITIATION_SECRET="$FLUXER_CONNECTION_INITIATION_SECRET" \
	--from-literal=FLUXER_GATEWAY_RPC_AUTH_TOKEN="$FLUXER_GATEWAY_RPC_AUTH_TOKEN" \
	--from-literal=FLUXER_MEDIA_PROXY_SECRET_KEY="$FLUXER_MEDIA_PROXY_SECRET_KEY" \
	--from-literal=FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64="$FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64" \
	--from-literal=FLUXER_ADMIN_SECRET_KEY_BASE="$FLUXER_ADMIN_SECRET_KEY_BASE" \
	--from-literal=FLUXER_ADMIN_OAUTH_CLIENT_SECRET="$FLUXER_ADMIN_OAUTH_CLIENT_SECRET" \
	--from-literal=FLUXER_ERLANG_COOKIE="$FLUXER_ERLANG_COOKIE" \
	--from-literal=LIVEKIT_API_KEY="$LIVEKIT_API_KEY" \
	--from-literal=LIVEKIT_API_SECRET="$LIVEKIT_API_SECRET" \
	--from-literal=FLUXER_VAPID_PUBLIC_KEY="$FLUXER_VAPID_PUBLIC_KEY" \
	--from-literal=FLUXER_VAPID_PRIVATE_KEY="$FLUXER_VAPID_PRIVATE_KEY" \
	--from-literal=LIVEKIT_KEYS="$LIVEKIT_KEYS" \
	--dry-run=client -o yaml | kubectl apply -f -

echo "wallow-secrets applied to namespace ${NAMESPACE}."
