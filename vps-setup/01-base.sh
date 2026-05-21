#!/usr/bin/env bash
# vps-setup/01-base.sh
# Hardening básico: user deploy, ssh keys, timezone, pacotes essenciais.
# Roda como root na primeira conexão à VPS.

set -euo pipefail

DEPLOY_USER="deploy"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: rode como root"
  exit 1
fi

echo "==> Atualizando pacotes"
apt-get update
apt-get upgrade -y

echo "==> Instalando pacotes essenciais"
apt-get install -y \
  curl \
  ca-certificates \
  gnupg \
  ufw \
  fail2ban \
  unattended-upgrades \
  git \
  htop \
  vim \
  jq

echo "==> Configurando timezone UTC"
timedatectl set-timezone UTC

echo "==> Criando user $DEPLOY_USER"
if ! id "$DEPLOY_USER" &>/dev/null; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
  usermod -aG sudo "$DEPLOY_USER"
  echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$DEPLOY_USER"
  chmod 0440 "/etc/sudoers.d/$DEPLOY_USER"
fi

echo "==> Copiando authorized_keys do root para $DEPLOY_USER"
mkdir -p "/home/$DEPLOY_USER/.ssh"
if [[ -f /root/.ssh/authorized_keys ]]; then
  cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
chmod 700 "/home/$DEPLOY_USER/.ssh"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys" 2>/dev/null || true

echo "==> Configurando SSH (root login off, password auth off)"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

echo "==> Habilitando unattended-upgrades"
dpkg-reconfigure -plow unattended-upgrades

systemctl restart ssh

echo "==> Pronto. Da próxima vez logue como: ssh ${DEPLOY_USER}@<vps-ip>"
