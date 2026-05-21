#!/usr/bin/env bash
# vps-setup/04-docker.sh
# Instala Docker Engine + compose plugin. Repositório oficial Docker.
# Roda como deploy via sudo.

set -euo pipefail

DEPLOY_USER="deploy"

if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  echo "==> Docker já instalado, pulando"
  docker --version
  docker compose version
  exit 0
fi

echo "==> Removendo versões antigas (se houver)"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" 2>/dev/null || true
done

echo "==> Adicionando repositório oficial Docker"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

echo "==> Instalando docker-ce + plugins"
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

echo "==> Adicionando $DEPLOY_USER ao grupo docker"
sudo usermod -aG docker "$DEPLOY_USER"

echo "==> Habilitando docker no boot"
sudo systemctl enable --now docker

echo "==> Verificando"
sudo docker --version
sudo docker compose version

echo "==> Pronto. Faça logout/login para ativar o grupo docker no shell atual."
