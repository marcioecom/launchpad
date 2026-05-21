#!/usr/bin/env bash
# vps-setup/02-firewall.sh
# Configura ufw: 80/443 só Cloudflare, SSH bloqueado publicamente (Tailscale abre depois).
# Roda como deploy via sudo.

set -euo pipefail

CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

echo "==> Resetando ufw"
sudo ufw --force reset

echo "==> Default policies"
sudo ufw default deny incoming
sudo ufw default allow outgoing

echo "==> Permitindo SSH (tailscale entra depois e abre via interface tailscale0)"
# Não abrimos SSH público aqui. Tailscale gerencia.

echo "==> Buscando IPs da Cloudflare"
CF_IPV4=$(curl -fsSL "$CF_IPV4_URL")
CF_IPV6=$(curl -fsSL "$CF_IPV6_URL")

echo "==> Permitindo 80/443 dos IPs da Cloudflare"
while IFS= read -r ip; do
  [[ -z "$ip" ]] && continue
  sudo ufw allow proto tcp from "$ip" to any port 80,443 comment "cloudflare-v4"
done <<< "$CF_IPV4"

while IFS= read -r ip; do
  [[ -z "$ip" ]] && continue
  sudo ufw allow proto tcp from "$ip" to any port 80,443 comment "cloudflare-v6"
done <<< "$CF_IPV6"

echo "==> Habilitando ufw"
sudo ufw --force enable

echo "==> Status atual"
sudo ufw status numbered

echo "==> Pronto. SSH público bloqueado. Rode 03-tailscale.sh AGORA para não perder acesso."
