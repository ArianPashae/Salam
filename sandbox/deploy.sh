#!/usr/bin/env bash
set -euo pipefail

api_container="${1:?usage: deploy.sh API_CONTAINER API_ENV_FILE}"
env_file="${2:?usage: deploy.sh API_CONTAINER API_ENV_FILE}"
root="$(cd "$(dirname "$0")/.." && pwd)"
manager="salam-sandbox-manager"

network="$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' "$api_container" | awk '{print $1}')"
[ -n "$network" ] || { echo "cannot find the network of $api_container" >&2; exit 1; }

docker build -t salam-sandbox "$root/sandbox/image"
docker build -t salam-sandbox-manager -f "$root/sandbox/Dockerfile" "$root"

secret="$(grep -E '^AI_SANDBOX_SECRET=' "$env_file" | head -n 1 | cut -d= -f2- || true)"
if [ -z "$secret" ]; then
    secret="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf 'AI_SANDBOX_SECRET=%s\n' "$secret" >> "$env_file"
fi
if ! grep -qE '^AI_SANDBOX_URL=' "$env_file"; then
    printf 'AI_SANDBOX_URL=http://%s:8090\n' "$manager" >> "$env_file"
fi

docker rm -f "$manager" > /dev/null 2>&1 || true
docker run -d --name "$manager" --restart unless-stopped --network "$network" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e SANDBOX_SECRET="$secret" -e SANDBOX_NETWORK=salam-sandbox \
    --memory 256m --pids-limit 256 salam-sandbox-manager

echo "sandbox manager is up on network $network; restart $api_container to read $env_file"
