# Runbook: Provisionar VPS do zero

Tempo estimado: 20-30 minutos.

## Pré-requisitos

- Conta na Hetzner Cloud com método de pagamento
- Conta no Tailscale (free tier basta)
- Domínio configurado na Cloudflare
- Chave SSH pública sua já no Hetzner Cloud (Settings -> Security -> SSH Keys)
- O launchpad repo clonado localmente

## 1. Criar VPS na Hetzner

1. Acesse https://console.hetzner.cloud
2. Project -> Add Server
3. Configurações:
   - **Location:** Falkenstein (FSN1) ou Helsinki (HEL1)
   - **Image:** Ubuntu 24.04
   - **Type:** Shared vCPU -> CX32 (4 vCPU, 8GB RAM, 80GB SSD)
   - **Networking:** IPv4 + IPv6
   - **SSH keys:** selecione sua chave
   - **Name:** `launchpad-prod`
4. Create & Buy now
5. Aguarde ~30s, anote o **IP público**

## 2. Primeiro SSH (como root)

```bash
ssh root@<VPS_IP>
```

Aceite o fingerprint.

## 3. Clonar launchpad na VPS

```bash
cd /tmp
git clone https://github.com/<GITHUB_USER>/launchpad.git
cd launchpad
```

(Ou copie os scripts via `scp` se ainda não publicou o repo.)

## 4. Hardening base (como root)

```bash
bash vps-setup/01-base.sh
```

Verifica:
- User `deploy` criado: `id deploy`
- SSH root desabilitado: grep PermitRootLogin /etc/ssh/sshd_config

Saia do SSH (`exit`).

## 5. Reconectar como deploy

```bash
ssh deploy@<VPS_IP>
```

Mova o repo para o home do deploy:

```bash
sudo mv /tmp/launchpad ~/launchpad
sudo chown -R deploy:deploy ~/launchpad
cd ~/launchpad
```

## 6. Tailscale (CRÍTICO: antes do firewall)

```bash
TAILSCALE_HOSTNAME=launchpad-prod bash vps-setup/03-tailscale.sh
```

- Abra a URL que aparecer no output
- Autentique no Tailscale
- Confirme que aparece em https://login.tailscale.com/admin/machines

**Em outro terminal local**, teste SSH via Tailscale:

```bash
ssh deploy@launchpad-prod
```

Se funcionou, prossiga. Se não, NÃO feche a sessão SSH atual via IP público.

## 7. Firewall

Na sessão SSH (qualquer uma, IP ou Tailscale):

```bash
bash vps-setup/02-firewall.sh
sudo ufw status numbered
```

Confirme que as regras da Cloudflare apareceram. SSH público está agora bloqueado.

## 8. Docker

```bash
bash vps-setup/04-docker.sh
```

Faça logout/login para ativar o grupo docker:

```bash
exit
ssh deploy@launchpad-prod
docker compose version  # deve printar v2.x
```

## 9. Validações finais

```bash
# Tailscale ativo
sudo tailscale status

# Firewall ativo
sudo ufw status

# Docker ok
docker ps
docker compose version

# Testar de fora: SSH público deve falhar
# (rode no seu laptop, NÃO na VPS)
nc -zv -w 5 <VPS_IP> 22
# expected: timeout / no route to host (porta filtrada)
```

A VPS está pronta para receber a stack do Traefik.
