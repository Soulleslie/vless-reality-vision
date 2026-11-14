ARG DEBIAN_IMAGE=debian:bookworm-slim
FROM ${DEBIAN_IMAGE}
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash curl ca-certificates jq unzip openssl iproute2 procps python3 dnsutils nginx certbot python3-certbot-dns-cloudflare shellcheck ripgrep util-linux systemd && rm -rf /var/lib/apt/lists/*
WORKDIR /src
