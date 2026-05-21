# Launchpad - Phase 1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provisionar uma VPS Hetzner com Tailscale, Docker e Traefik, e migrar 1 projeto piloto do Railway, sem webhook ainda (deploy manual nesta fase).

**Architecture:** Repositório launchpad contém scripts de provisioning idempotentes e configs de infra. VPS Ubuntu 24.04 com firewall ufw, SSH apenas via Tailscale, Docker Engine, Traefik v3 como reverse proxy com Cloudflare Origin Certificate, e um projeto piloto rodando atrás de subdomínio na Cloudflare proxy.

**Tech Stack:** Bash, Docker Engine 27+, Docker Compose v2, Traefik v3, Tailscale, ufw, Hetzner Cloud, Cloudflare DNS+proxy, GitHub Container Registry.

---

## Variáveis necessárias

Antes de começar, defina estes valores (substitua nos comandos quando aparecer `<NOME>`):

| Variável | Significado | Exemplo |
|---|---|---|
| `<DOMAIN>` | Domínio raiz na Cloudflare | `marcioecom.dev` |
| `<PILOT_PROJECT>` | Nome do projeto piloto (kebab-case) | `permit` |
| `<PILOT_SUBDOMAIN>` | Subdomínio do piloto | `permit` (vira `permit.marcioecom.dev`) |
| `<GITHUB_USER>` | Username do GitHub | `marciojunior` |
| `<GITHUB_REPO>` | Repo do projeto piloto | `permit` |
| `<TAILSCALE_HOSTNAME>` | Hostname desejado no tailnet | `launchpad-prod` |
| `<VPS_IP>` | IP público da VPS (preenche após Task 11) | `188.245.x.x` |

---

## Estrutura de arquivos do launchpad

```
launchpad/
├── README.md
├── .gitignore
├── docs/
│   ├── superpowers/
│   │   ├── specs/2026-05-21-launchpad-design.md
│   │   └── plans/2026-05-21-phase-1-foundation.md (este arquivo)
│   └── runbooks/
│       ├── provisionar-vps.md
│       └── deploy-manual-piloto.md
├── vps-setup/
│   ├── README.md
│   ├── 01-base.sh
│   ├── 02-firewall.sh
│   ├── 03-tailscale.sh
│   └── 04-docker.sh
├── infra/
│   └── traefik/
│       ├── docker-compose.yml
│       ├── traefik.yml
│       └── certs/
│           └── .gitkeep
└── templates/
    └── app/
        ├── Dockerfile.example
        ├── docker-compose.yml
        └── .env.example
```

---

## Task 1: Inicializar repo launchpad

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/.gitignore`
- Create: `/Users/marciojunior/code/marcioecom/launchpad/README.md`

- [ ] **Step 1: Criar .gitignore**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/.gitignore <<'EOF'
# Secrets
.env
.env.*
!.env.example

# Cloudflare Origin Cert (privada não vai pro git)
infra/traefik/certs/*.pem
infra/traefik/certs/*.key
!infra/traefik/certs/.gitkeep

# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
*.swp
EOF
```

- [ ] **Step 2: Criar README inicial**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/README.md <<'EOF'
# Launchpad

Self-hosting deploy stack pessoal. Provisiona VPS Hetzner com Docker, Traefik e fluxo de deploy padronizado.

Arquitetura completa: ver [spec](docs/superpowers/specs/2026-05-21-launchpad-design.md).

## Quick start

1. Provisione uma VPS Hetzner (CX32 Ubuntu 24.04 recomendado)
2. Rode os scripts em `vps-setup/` em ordem
3. Suba a stack do Traefik (`infra/traefik/`)
4. Adicione projetos seguindo o template em `templates/app/`

Veja `docs/runbooks/provisionar-vps.md` para o passo a passo detalhado.
EOF
```

- [ ] **Step 3: Inicializar git**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git init
git add .gitignore README.md
git commit -m "chore: initial repo skeleton"
```

Expected: 2 files committed, "Initialized empty Git repository" mensagem.

---

## Task 2: Adicionar spec e plan ao repo

**Files:**
- Modify: `/Users/marciojunior/code/marcioecom/launchpad/docs/superpowers/specs/2026-05-21-launchpad-design.md` (já existe)
- Modify: `/Users/marciojunior/code/marcioecom/launchpad/docs/superpowers/plans/2026-05-21-phase-1-foundation.md` (este)

- [ ] **Step 1: Commit spec + plan**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add docs/
git commit -m "docs: add design spec and phase 1 plan"
```

Expected: commit registra os dois arquivos de documentação.

---

## Task 3: Script de hardening base

Configura o user `deploy`, hardening SSH e instala pacotes essenciais. Roda como root na primeira conexão à VPS.

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/vps-setup/01-base.sh`

- [ ] **Step 1: Escrever o script**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/vps-setup/01-base.sh <<'EOF'
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
EOF
chmod +x /Users/marciojunior/code/marcioecom/launchpad/vps-setup/01-base.sh
```

- [ ] **Step 2: Validar com shellcheck (se instalado)**

```bash
which shellcheck && shellcheck /Users/marciojunior/code/marcioecom/launchpad/vps-setup/01-base.sh || echo "shellcheck not installed, skipping"
```

Expected: zero issues, ou skip se shellcheck não está instalado. Se há warnings, corrigir antes de prosseguir.

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add vps-setup/01-base.sh
git commit -m "feat(vps-setup): add base hardening script"
```

---

## Task 4: Script de firewall

Configura ufw para aceitar 80/443 apenas dos IPs da Cloudflare, e bloquear SSH público (será aberto só via Tailscale na Task 5).

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/vps-setup/02-firewall.sh`

- [ ] **Step 1: Escrever o script**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/vps-setup/02-firewall.sh <<'EOF'
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
EOF
chmod +x /Users/marciojunior/code/marcioecom/launchpad/vps-setup/02-firewall.sh
```

- [ ] **Step 2: Validar**

```bash
which shellcheck && shellcheck /Users/marciojunior/code/marcioecom/launchpad/vps-setup/02-firewall.sh || echo "skip"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add vps-setup/02-firewall.sh
git commit -m "feat(vps-setup): add ufw firewall script with cloudflare allowlist"
```

---

## Task 5: Script de instalação do Tailscale

Instala Tailscale, ativa SSH via Tailscale (tailscale ssh), e configura para iniciar no boot.

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/vps-setup/03-tailscale.sh`

- [ ] **Step 1: Escrever o script**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/vps-setup/03-tailscale.sh <<'EOF'
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
EOF
chmod +x /Users/marciojunior/code/marcioecom/launchpad/vps-setup/03-tailscale.sh
```

- [ ] **Step 2: Validar**

```bash
which shellcheck && shellcheck /Users/marciojunior/code/marcioecom/launchpad/vps-setup/03-tailscale.sh || echo "skip"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add vps-setup/03-tailscale.sh
git commit -m "feat(vps-setup): add tailscale install script"
```

---

## Task 6: Script de instalação do Docker

Instala Docker Engine + plugin compose, adiciona user `deploy` ao grupo docker.

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/vps-setup/04-docker.sh`

- [ ] **Step 1: Escrever o script**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/vps-setup/04-docker.sh <<'EOF'
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
EOF
chmod +x /Users/marciojunior/code/marcioecom/launchpad/vps-setup/04-docker.sh
```

- [ ] **Step 2: Validar**

```bash
which shellcheck && shellcheck /Users/marciojunior/code/marcioecom/launchpad/vps-setup/04-docker.sh || echo "skip"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add vps-setup/04-docker.sh
git commit -m "feat(vps-setup): add docker install script"
```

---

## Task 7: README do vps-setup

Documenta a ordem de execução dos scripts.

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/vps-setup/README.md`

- [ ] **Step 1: Escrever o README**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/vps-setup/README.md <<'EOF'
# VPS Setup

Scripts idempotentes para provisionar uma VPS Ubuntu 24.04 do zero.

## Ordem

1. **`01-base.sh`** - como root, na primeira conexão. Cria user `deploy`, hardening SSH, instala pacotes base.
2. **`03-tailscale.sh`** - como deploy. Instala Tailscale e habilita SSH via tailnet. **Rode ANTES do firewall** para não perder acesso.
3. **`02-firewall.sh`** - como deploy. Configura ufw para aceitar 80/443 só da Cloudflare, bloqueia SSH público.
4. **`04-docker.sh`** - como deploy. Instala Docker Engine e plugin compose.

## Por que essa ordem?

Os scripts 02 e 03 estão "fora de ordem" intencionalmente. Você precisa do Tailscale ATIVO antes de bloquear SSH público, senão se trancar pra fora da VPS.

## Variáveis de ambiente

`03-tailscale.sh` aceita `TAILSCALE_HOSTNAME` (default `launchpad-prod`).

```bash
TAILSCALE_HOSTNAME=meu-server bash 03-tailscale.sh
```

## Idempotência

Todos os scripts são seguros para re-executar. Eles checam estado existente antes de modificar.
EOF
```

- [ ] **Step 2: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add vps-setup/README.md
git commit -m "docs(vps-setup): add execution order README"
```

---

## Task 8: Runbook de provisioning

Passo a passo manual de provisioning, escrito para ser seguido pela primeira vez.

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/docs/runbooks/provisionar-vps.md`

- [ ] **Step 1: Criar diretório e escrever runbook**

```bash
mkdir -p /Users/marciojunior/code/marcioecom/launchpad/docs/runbooks
cat > /Users/marciojunior/code/marcioecom/launchpad/docs/runbooks/provisionar-vps.md <<'EOF'
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
EOF
```

- [ ] **Step 2: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add docs/runbooks/provisionar-vps.md
git commit -m "docs(runbooks): add vps provisioning runbook"
```

---

## Task 9: Config estática do Traefik

Define entrypoints, providers, e referência ao Origin Cert.

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/infra/traefik/traefik.yml`
- Create: `/Users/marciojunior/code/marcioecom/launchpad/infra/traefik/certs/.gitkeep`

- [ ] **Step 1: Criar config estática**

```bash
mkdir -p /Users/marciojunior/code/marcioecom/launchpad/infra/traefik/certs
touch /Users/marciojunior/code/marcioecom/launchpad/infra/traefik/certs/.gitkeep

cat > /Users/marciojunior/code/marcioecom/launchpad/infra/traefik/traefik.yml <<'EOF'
# Config estática do Traefik v3.
# Rotas são definidas via labels Docker em cada container.

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: web
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

log:
  level: INFO

accessLog: {}
EOF
```

- [ ] **Step 2: Criar config dinâmica com TLS cert**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/infra/traefik/dynamic.yml <<'EOF'
# Config dinâmica: certificados TLS e middlewares globais.

tls:
  certificates:
    - certFile: /etc/traefik/certs/origin.pem
      keyFile: /etc/traefik/certs/origin.key
  options:
    default:
      minVersion: VersionTLS12

http:
  middlewares:
    # Force https (já feito no entryPoint, este é fallback)
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
EOF
```

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add infra/traefik/
git commit -m "feat(traefik): add static and dynamic config"
```

---

## Task 10: Docker compose do Traefik

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/infra/traefik/docker-compose.yml`

- [ ] **Step 1: Criar o compose**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/infra/traefik/docker-compose.yml <<'EOF'
services:
  traefik:
    image: traefik:v3.2
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic.yml:/etc/traefik/dynamic.yml:ro
      - ./certs:/etc/traefik/certs:ro
    networks:
      - web
    labels:
      - traefik.enable=true
      # Dashboard só acessível via Tailscale (porta interna)
      - traefik.http.routers.dashboard.rule=Host(`traefik.localhost`)
      - traefik.http.routers.dashboard.service=api@internal
      - traefik.http.routers.dashboard.entrypoints=websecure
      - traefik.http.routers.dashboard.tls=true

networks:
  web:
    name: web
    external: true
EOF
```

- [ ] **Step 2: Validar compose syntax (localmente)**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad/infra/traefik
docker compose config > /dev/null && echo "OK"
```

Expected: prints "OK". Se der erro de YAML, corrigir.

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add infra/traefik/docker-compose.yml
git commit -m "feat(traefik): add compose stack"
```

---

## Task 11: CHECKPOINT - Provisionar VPS no Hetzner

Este é um checkpoint manual. O usuário precisa criar a VPS de fato.

- [ ] **Step 1: Seguir runbook de provisioning**

Abra `docs/runbooks/provisionar-vps.md` e execute todos os passos 1 a 9.

Ao final você deve ter:

1. VPS rodando, IP anotado (substituir `<VPS_IP>`)
2. SSH público bloqueado, SSH via Tailscale funcionando
3. Docker instalado, `docker compose version` retorna v2.x
4. Tailscale hostname `launchpad-prod` ativo no tailnet

- [ ] **Step 2: Anotar o IP da VPS**

Edite mentalmente (ou em um arquivo local) o valor de `<VPS_IP>` para uso nas próximas tasks.

---

## Task 12: Configurar DNS na Cloudflare

Criar registros DNS para os subdomínios necessários.

- [ ] **Step 1: Criar registros A**

No painel da Cloudflare, em DNS -> Records, adicionar:

| Type | Name | Content | Proxy | TTL |
|---|---|---|---|---|
| A | `<PILOT_SUBDOMAIN>` | `<VPS_IP>` | Proxied (laranja) | Auto |
| A | `deploy` | `<VPS_IP>` | Proxied | Auto |
| A | `traefik` | `<VPS_IP>` | Proxied | Auto |

(O subdomínio `traefik` é opcional para acessar dashboard, pode ser desabilitado depois)

- [ ] **Step 2: Verificar resolução**

```bash
dig +short <PILOT_SUBDOMAIN>.<DOMAIN>
```

Expected: retorna IPs da Cloudflare (não o IP da VPS, porque está proxied). Algo como `104.21.x.x` ou `172.67.x.x`.

- [ ] **Step 3: Configurar SSL mode**

Cloudflare -> SSL/TLS -> Overview -> selecionar **Full (strict)**.

---

## Task 13: Gerar Origin Certificate na Cloudflare

Apenas gera o certificado e salva localmente. A instalação na VPS acontece em Task 15, depois do clone.

- [ ] **Step 1: Criar certificado**

Cloudflare -> SSL/TLS -> Origin Server -> Create Certificate.

Configurações:
- Private key type: RSA (2048)
- Hostnames: `*.<DOMAIN>, <DOMAIN>`
- Validity: 15 years

Clique Create.

- [ ] **Step 2: Salvar arquivos localmente (temporariamente)**

Copie do painel da Cloudflare:
- "Origin Certificate" -> salva como `~/launchpad-certs/origin.pem` no laptop
- "Private key" -> salva como `~/launchpad-certs/origin.key` no laptop

```bash
mkdir -p ~/launchpad-certs
chmod 700 ~/launchpad-certs
# cole os conteúdos nos arquivos correspondentes
```

A janela com a private key na Cloudflare só aparece UMA VEZ. Se fechar sem copiar, gere um novo certificado.

---

## Task 14: Clonar launchpad na VPS

- [ ] **Step 1: SSH na VPS e preparar /srv**

```bash
ssh deploy@launchpad-prod
sudo mkdir -p /srv
sudo chown deploy:deploy /srv
cd /srv
```

- [ ] **Step 2: Clonar o repo (ou rsync se ainda não publicou)**

Se o launchpad já está no GitHub (Task 28 antecipada):

```bash
git clone https://github.com/<GITHUB_USER>/launchpad.git
```

Se ainda não publicou, use rsync do laptop:

```bash
# rode no laptop
rsync -av --exclude='.git' \
  /Users/marciojunior/code/marcioecom/launchpad/ \
  deploy@launchpad-prod:/srv/launchpad/
```

- [ ] **Step 3: Verificar estrutura**

```bash
ls -la /srv/launchpad/infra/traefik/
# expected: docker-compose.yml, traefik.yml, dynamic.yml, certs/
```

A pasta `certs/` existe (com `.gitkeep`) mas está vazia. Será populada na próxima task.

---

## Task 15: Instalar Origin Cert na VPS

- [ ] **Step 1: Transferir cert do laptop para a VPS via Tailscale SCP**

```bash
# do laptop
scp ~/launchpad-certs/origin.pem ~/launchpad-certs/origin.key \
  deploy@launchpad-prod:/tmp/
```

Expected: dois arquivos transferidos.

- [ ] **Step 2: Mover para o diretório do Traefik com permissões corretas**

```bash
ssh deploy@launchpad-prod
sudo mv /tmp/origin.pem /srv/launchpad/infra/traefik/certs/
sudo mv /tmp/origin.key /srv/launchpad/infra/traefik/certs/
sudo chown deploy:deploy /srv/launchpad/infra/traefik/certs/origin.*
chmod 644 /srv/launchpad/infra/traefik/certs/origin.pem
chmod 600 /srv/launchpad/infra/traefik/certs/origin.key
ls -la /srv/launchpad/infra/traefik/certs/
```

Expected: `origin.pem` com 644 e `origin.key` com 600, ambos owner deploy.

- [ ] **Step 3: Apagar cópias locais do laptop**

```bash
# no laptop
shred -u ~/launchpad-certs/origin.pem ~/launchpad-certs/origin.key
rmdir ~/launchpad-certs
```

Expected: arquivos sumiram. Únicas cópias agora: VPS + painel CF (que tem só metadados, não a private key).

---

## Task 16: Criar network `web` e subir Traefik

- [ ] **Step 1: Criar network compartilhada**

Na VPS:

```bash
docker network create web
```

Expected: print do ID da network. Se já existe, "network with name web already exists" - tudo bem.

- [ ] **Step 2: Subir Traefik**

```bash
cd /srv/launchpad/infra/traefik
docker compose up -d
```

Expected: `[+] Running 1/1 ✔ Container traefik Started`

- [ ] **Step 3: Verificar logs**

```bash
docker compose logs --tail=30
```

Expected: ver "Starting provider *docker.Provider", "Configuration loaded from file". Sem erros sobre TLS cert ou socket.

- [ ] **Step 4: Verificar containers rodando**

```bash
docker ps
```

Expected: traefik up, status "Up X seconds". Portas 80, 443 publicadas.

- [ ] **Step 5: Curl de fora (laptop)**

```bash
curl -I https://<PILOT_SUBDOMAIN>.<DOMAIN>
```

Expected: HTTP/2 404 (404 do Traefik porque ainda não tem nada respondendo no subdomínio). O importante é que retornou status code via HTTPS - significa que: DNS resolveu, Cloudflare proxied, Cloudflare conectou na VPS, TLS handshake completou com Origin Cert, Traefik respondeu.

Se der `Bad Gateway` ou similar, há problema na chain. Debug:
- Cloudflare SSL mode é "Full (strict)"?
- VPS firewall aceita CF IPs? `sudo ufw status` na VPS
- Traefik está rodando? `docker ps`
- Cert montado? `docker exec traefik ls /etc/traefik/certs/`

---

## Task 17: Template de Dockerfile para projeto app

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/templates/app/Dockerfile.example`

- [ ] **Step 1: Criar Dockerfile multi-stage exemplo (Node/pnpm)**

```bash
mkdir -p /Users/marciojunior/code/marcioecom/launchpad/templates/app
cat > /Users/marciojunior/code/marcioecom/launchpad/templates/app/Dockerfile.example <<'EOF'
# Dockerfile exemplo para app Node.js com pnpm.
# Copie para a raiz do seu projeto como `Dockerfile` e ajuste:
# - versão do Node
# - comando de build (pnpm build, pnpm tsc, etc)
# - comando de start
# - porta exposta

ARG NODE_VERSION=22

# --- builder ---
FROM node:${NODE_VERSION}-alpine AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

# --- runtime ---
FROM node:${NODE_VERSION}-alpine AS runtime

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

COPY --from=builder /app/dist ./dist
# Se você gera arquivos em outros lugares (e.g. drizzle migrations), copie aqui também
# COPY --from=builder /app/drizzle ./drizzle

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

USER node

CMD ["node", "dist/index.js"]
EOF
```

- [ ] **Step 2: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add templates/app/Dockerfile.example
git commit -m "feat(templates): add example Node Dockerfile"
```

---

## Task 18: Template de docker-compose para projeto

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/templates/app/docker-compose.yml`

- [ ] **Step 1: Criar compose template**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/templates/app/docker-compose.yml <<'EOF'
# Template de docker-compose para projeto app.
# Substitua todas ocorrências de:
#   APP_NAME -> nome do projeto (kebab-case, ex: permit)
#   SUBDOMAIN -> subdomínio (ex: permit)
#   DOMAIN -> seu domínio raiz (ex: marcioecom.dev)
#   GITHUB_USER -> seu username github
#   GITHUB_REPO -> nome do repo no github
#   APP_PORT -> porta interna que a app expõe (default 3000)

services:
  app:
    image: ghcr.io/GITHUB_USER/GITHUB_REPO:${IMAGE_TAG:-latest}
    container_name: APP_NAME-app
    restart: unless-stopped
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - web
      - internal
    labels:
      - traefik.enable=true
      - traefik.docker.network=web
      - traefik.http.routers.APP_NAME.rule=Host(`SUBDOMAIN.DOMAIN`)
      - traefik.http.routers.APP_NAME.entrypoints=websecure
      - traefik.http.routers.APP_NAME.tls=true
      - traefik.http.services.APP_NAME.loadbalancer.server.port=APP_PORT

  postgres:
    image: postgres:16-alpine
    container_name: APP_NAME-postgres
    restart: unless-stopped
    env_file: .env
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - internal

networks:
  web:
    external: true
  internal:
    driver: bridge
EOF
```

- [ ] **Step 2: Criar .env.example**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/templates/app/.env.example <<'EOF'
# Substitua todos valores antes de usar.

# Postgres
POSTGRES_DB=APP_NAME
POSTGRES_USER=APP_NAME
POSTGRES_PASSWORD=trocar-por-senha-forte

# DATABASE_URL para a app (apontando para o container postgres na rede internal)
DATABASE_URL=postgres://APP_NAME:trocar-por-senha-forte@postgres:5432/APP_NAME

# App-specific
NODE_ENV=production
PORT=3000
# Adicione segredos da app aqui (API keys, JWT_SECRET, etc)
EOF
```

- [ ] **Step 3: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add templates/app/docker-compose.yml templates/app/.env.example
git commit -m "feat(templates): add app compose and env templates"
```

---

## Task 19: Adaptar projeto piloto - Dockerfile

Estas tasks (19-24) acontecem no repo do projeto piloto (`<PILOT_PROJECT>`), não no launchpad.

- [ ] **Step 1: Ir para o repo do piloto**

```bash
cd /Users/marciojunior/code/newcode/<PILOT_PROJECT>
# ou onde quer que esteja o repo do piloto
```

- [ ] **Step 2: Verificar se já tem Dockerfile**

```bash
ls -la Dockerfile
```

Se já tem: revisar se segue padrão multi-stage, USER non-root, EXPOSE adequado.
Se não tem: copiar do template.

- [ ] **Step 3: Copiar template e ajustar**

```bash
cp /Users/marciojunior/code/marcioecom/launchpad/templates/app/Dockerfile.example ./Dockerfile
```

Edite o Dockerfile e ajuste:
- `NODE_VERSION` para a versão usada no projeto
- Comando de build (pode ser `pnpm tsc`, `pnpm build`, etc)
- Path do output (`dist`, `build`, etc)
- Comando de start (`node dist/index.js`, `node dist/main.js`, etc)
- `PORT` que a app realmente expõe

- [ ] **Step 4: Testar build local**

```bash
docker build -t pilot-test .
```

Expected: build completa sem erros. Pode demorar alguns minutos na primeira vez.

- [ ] **Step 5: Testar que o container sobe**

```bash
docker run --rm -e DATABASE_URL=postgres://fake -p 3000:3000 pilot-test
```

Expected: container inicia. Se der erro de DB connection, tudo bem - é esperado.
Ctrl+C para parar.

- [ ] **Step 6: Commit no repo do piloto**

```bash
git add Dockerfile
git commit -m "feat: add production Dockerfile"
```

---

## Task 20: Build e push da imagem para GHCR

- [ ] **Step 1: Login no GHCR**

Criar Personal Access Token (classic) com escopo `write:packages` em https://github.com/settings/tokens/new

```bash
echo "<GHCR_TOKEN>" | docker login ghcr.io -u <GITHUB_USER> --password-stdin
```

Expected: "Login Succeeded"

- [ ] **Step 2: Build com tag GHCR**

```bash
cd /Users/marciojunior/code/newcode/<PILOT_PROJECT>
docker build -t ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:latest .
```

- [ ] **Step 3: Push**

```bash
docker push ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:latest
```

Expected: layers uploaded. Demora a primeira vez (~30s-5min dependendo do tamanho).

- [ ] **Step 4: Verificar no GitHub**

Acesse `https://github.com/<GITHUB_USER>?tab=packages`. A package `<GITHUB_REPO>` deve aparecer.

Por default packages do GHCR são privadas. Para a VPS conseguir pull:
- Option A: Tornar a package pública (Settings da package -> Change visibility)
- Option B: Login do GHCR na VPS (próxima task)

Recomendado neste piloto: **Option B** (login na VPS), para já validar o fluxo que vamos usar com webhook depois.

---

## Task 21: Login do GHCR na VPS

- [ ] **Step 1: Criar PAT específico para a VPS**

Crie outro PAT em https://github.com/settings/tokens/new com escopo apenas `read:packages`. Chame de `vps-launchpad-prod-readonly`.

- [ ] **Step 2: Login docker na VPS**

```bash
ssh deploy@launchpad-prod
echo "<PAT_RO>" | docker login ghcr.io -u <GITHUB_USER> --password-stdin
```

Expected: "Login Succeeded"

O token fica salvo em `~/.docker/config.json`. Persiste entre reboots.

- [ ] **Step 3: Testar pull**

```bash
docker pull ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:latest
```

Expected: layers downloaded. Se "denied", PAT está sem escopo ou pacote não existe.

---

## Task 22: Criar diretório do piloto na VPS

- [ ] **Step 1: Criar estrutura**

```bash
ssh deploy@launchpad-prod
sudo mkdir -p /srv/apps/<PILOT_PROJECT>/data/postgres
sudo chown -R deploy:deploy /srv/apps/<PILOT_PROJECT>
cd /srv/apps/<PILOT_PROJECT>
```

- [ ] **Step 2: Copiar template de compose**

```bash
cp /srv/launchpad/templates/app/docker-compose.yml ./docker-compose.yml
```

- [ ] **Step 3: Substituir placeholders**

Use sed para substituir, ajustando os valores:

```bash
# substitua os valores reais nas variáveis
APP_NAME="<PILOT_PROJECT>"
SUBDOMAIN="<PILOT_SUBDOMAIN>"
DOMAIN="<DOMAIN>"
GITHUB_USER="<GITHUB_USER>"
GITHUB_REPO="<GITHUB_REPO>"
APP_PORT="3000"

sed -i \
  -e "s/APP_NAME/$APP_NAME/g" \
  -e "s/SUBDOMAIN/$SUBDOMAIN/g" \
  -e "s/DOMAIN/$DOMAIN/g" \
  -e "s/GITHUB_USER/$GITHUB_USER/g" \
  -e "s/GITHUB_REPO/$GITHUB_REPO/g" \
  -e "s/APP_PORT/$APP_PORT/g" \
  docker-compose.yml
```

- [ ] **Step 4: Verificar substituições**

```bash
cat docker-compose.yml
```

Expected: nenhum `APP_NAME`, `SUBDOMAIN`, etc literal aparece. Todos foram substituídos.

```bash
docker compose config > /dev/null && echo "OK"
```

Expected: "OK". Se erro, há problema de YAML/syntax.

---

## Task 23: Criar .env do piloto

- [ ] **Step 1: Copiar template**

```bash
cd /srv/apps/<PILOT_PROJECT>
cp /srv/launchpad/templates/app/.env.example .env
chmod 600 .env
```

- [ ] **Step 2: Editar com valores reais**

```bash
vim .env
```

Substitua:
- `POSTGRES_PASSWORD` por uma senha forte (use `openssl rand -base64 24` para gerar)
- `DATABASE_URL` com a mesma senha
- Adicione qualquer outra env var que o piloto precisa (copiar do Railway antes de desligar)

**CRÍTICO:** Salve o conteúdo do `.env` no 1Password antes de seguir. Se você perder a VPS, isto é a única coisa que não tem como recriar do código.

---

## Task 24: Deploy manual do piloto

- [ ] **Step 1: Pull da imagem**

```bash
cd /srv/apps/<PILOT_PROJECT>
docker compose pull
```

Expected: `[+] Pulling X/X ... done`. Postgres e a app baixadas.

- [ ] **Step 2: Subir postgres primeiro**

```bash
docker compose up -d postgres
sleep 10
docker compose logs postgres | tail -20
```

Expected: "database system is ready to accept connections"

- [ ] **Step 3: Rodar migrations (se houver)**

Se o projeto tem migrations (Drizzle, Prisma, TypeORM):

```bash
docker compose run --rm app pnpm migrate
# ou pnpm db:migrate, depende do projeto
```

Expected: migrations rodam. Se "no migrations to apply" também ok.

- [ ] **Step 4: Subir a app**

```bash
docker compose up -d app
docker compose logs -f app
```

Expected: app inicia, logs mostram "listening on port 3000" ou similar.
Ctrl+C para sair dos logs (sem parar o container).

- [ ] **Step 5: Verificar status**

```bash
docker compose ps
```

Expected: ambos containers `Up X seconds (healthy)` ou `Up X seconds`.

---

## Task 25: Validação end-to-end

- [ ] **Step 1: Teste local na VPS (network interna)**

```bash
ssh deploy@launchpad-prod
docker exec traefik wget -q -O- --no-check-certificate https://<PILOT_SUBDOMAIN>.<DOMAIN>/ | head
```

Expected: HTML da app (ou JSON, dependendo do que a app retorna em `/`).

- [ ] **Step 2: Teste externo (do laptop)**

```bash
curl -I https://<PILOT_SUBDOMAIN>.<DOMAIN>
```

Expected: `HTTP/2 200` (ou 301/302 se a app redireciona). Sem erros TLS.

- [ ] **Step 3: Teste em browser**

Abrir https://<PILOT_SUBDOMAIN>.<DOMAIN> no browser. Deve carregar a app normalmente, com cadeado de SSL válido.

- [ ] **Step 4: Verificar via Cloudflare**

Cloudflare -> Analytics -> Traffic. Deve mostrar requests recentes ao subdomínio. SSL handshakes 100% success.

- [ ] **Step 5: Smoke test funcional**

Faça uma operação básica na app que toca o DB (criar usuário, criar registro, fazer login, etc). Verifique que persiste em refresh.

---

## Task 26: Documentar runbook de deploy manual

**Files:**
- Create: `/Users/marciojunior/code/marcioecom/launchpad/docs/runbooks/deploy-manual-piloto.md`

- [ ] **Step 1: Escrever runbook**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/docs/runbooks/deploy-manual-piloto.md <<'EOF'
# Runbook: Deploy manual de update (Phase 1)

Enquanto a Phase 2 (webhook) não está pronta, deploys de novas versões são manuais.

## Quando usar

- Após push de mudanças no projeto piloto
- Apenas durante a Phase 1; Phase 2 automatiza isto

## Passos

### 1. Build e push da imagem nova (laptop)

```bash
cd /Users/marciojunior/code/newcode/<projeto>
TAG=$(git rev-parse --short HEAD)

docker build -t ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:$TAG -t ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:latest .
docker push ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:$TAG
docker push ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:latest
```

### 2. Deploy na VPS (via Tailscale SSH)

```bash
ssh deploy@launchpad-prod
cd /srv/apps/<projeto>

docker compose pull app
docker compose run --rm app pnpm migrate  # se houver migrations
docker compose up -d app
docker compose logs --tail=50 app
```

### 3. Verificar

```bash
curl -I https://<subdominio>.<dominio>
# expected: 200 OK
```

### 4. Rollback (se necessário)

```bash
# na VPS
PREV_TAG=<sha-anterior>
IMAGE_TAG=$PREV_TAG docker compose up -d app
```

(Phase 2 vai automatizar tudo isto via GitHub Actions + webhook.)
EOF
```

- [ ] **Step 2: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add docs/runbooks/deploy-manual-piloto.md
git commit -m "docs(runbooks): add manual deploy runbook for phase 1"
```

---

## Task 27: Atualizar README do launchpad

**Files:**
- Modify: `/Users/marciojunior/code/marcioecom/launchpad/README.md`

- [ ] **Step 1: Reescrever README com estado atual**

```bash
cat > /Users/marciojunior/code/marcioecom/launchpad/README.md <<'EOF'
# Launchpad

Self-hosting deploy stack pessoal. Provisiona VPS Hetzner com Docker, Traefik e fluxo de deploy padronizado.

## Status

- [x] Phase 1: Foundation (VPS, Traefik, 1 projeto piloto manual)
- [ ] Phase 2: Deploy automatizado via webhook + GH Actions
- [ ] Phase 3: Backup automatizado
- [ ] Phase 4: Migração dos demais projetos
- [ ] Phase 5: Observability básica (Uptime Kuma) + automação onboarding

## Arquitetura

Ver [spec](docs/superpowers/specs/2026-05-21-launchpad-design.md).

## Estrutura

- `vps-setup/` - scripts idempotentes de provisioning (executar em ordem)
- `infra/traefik/` - stack do reverse proxy
- `templates/app/` - template para novos projetos
- `docs/runbooks/` - procedimentos operacionais

## Runbooks

- [Provisionar VPS do zero](docs/runbooks/provisionar-vps.md)
- [Deploy manual durante Phase 1](docs/runbooks/deploy-manual-piloto.md)

## Operação básica

SSH na VPS (via Tailscale):

```bash
ssh deploy@launchpad-prod
```

Ver projetos rodando:

```bash
docker ps
```

Logs de um projeto:

```bash
cd /srv/apps/<projeto>
docker compose logs -f
```
EOF
```

- [ ] **Step 2: Commit**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add README.md
git commit -m "docs: update README with phase 1 status"
```

---

## Task 28: Publicar launchpad no GitHub

- [ ] **Step 1: Criar repo no GitHub**

Em https://github.com/new:
- Owner: `<GITHUB_USER>`
- Repository name: `launchpad`
- Visibility: Private (recomendado - contém detalhes da sua infra)
- NÃO adicionar README/license/.gitignore (já temos)

- [ ] **Step 2: Adicionar remote e push**

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git remote add origin git@github.com:<GITHUB_USER>/launchpad.git
git branch -M main
git push -u origin main
```

Expected: branch main published.

- [ ] **Step 3: Sincronizar na VPS**

```bash
ssh deploy@launchpad-prod
cd /srv/launchpad

# se inicialmente foi via rsync, trocar para git:
sudo rm -rf /srv/launchpad
cd /srv
git clone git@github.com:<GITHUB_USER>/launchpad.git
# precisará configurar deploy key SSH se for repo privado
```

(Alternativa: continuar usando HTTPS com PAT em vez de SSH.)

---

## Critérios de conclusão da Phase 1

Phase 1 está completa quando:

1. `ssh deploy@launchpad-prod` funciona (apenas via Tailscale)
2. `nc -zv -w 5 <VPS_IP> 22` do laptop dá timeout (SSH público bloqueado)
3. `docker ps` na VPS mostra: traefik + 2 containers do piloto (app + postgres)
4. `curl -I https://<PILOT_SUBDOMAIN>.<DOMAIN>` retorna 200/301 com SSL válido
5. Browser abre a app, navegação básica funciona, dados persistem
6. Launchpad repo no GitHub espelha o estado da VPS

Pronto para Phase 2 (deploy automatizado via webhook).
