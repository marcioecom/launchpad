#!/usr/bin/env bash
# vps-setup/03-tailscale.sh
# Instala tailscale e configura SSH via tailnet.
# Roda como deploy via sudo.
#
# Após rodar, abra a URL impressa para autenticar, depois:
#   sudo tailscale set --ssh
# E a partir de outra máquina no tailnet:
#   ssh deploy@<TAILSCALE_HOSTNAME>

set -euo pipefail

TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-launchpad-prod}"

if ! command -v tailscale &>/dev/null; then
  echo "==> Instalando tailscale"
  curl -fsSL https://tailscale.com/install.sh | sudo sh
fi

echo "==> Iniciando tailscale up com SSH habilitado, hostname=${TAILSCALE_HOSTNAME}"
sudo tailscale up \
  --ssh \
  --hostname="$TAILSCALE_HOSTNAME" \
  --accept-routes

echo "==> Status:"
sudo tailscale status

echo "==> Tailnet IP:"
sudo tailscale ip -4

echo
echo "==> Pronto. Agora você pode SSH via:"
echo "    ssh deploy@${TAILSCALE_HOSTNAME}"
echo
echo "Quando confirmar que funciona, encerre a sessão SSH atual."
