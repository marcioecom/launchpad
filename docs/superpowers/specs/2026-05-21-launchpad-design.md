# Launchpad - Self-Hosting Deploy Stack Design

**Data:** 2026-05-21
**Autor:** Márcio Júnior
**Status:** Draft - pendente review

## Contexto

Após o outage prolongado do Railway, surgiu a necessidade de migrar os projetos pessoais para uma stack self-hosted que combine simplicidade operacional com aprendizado de devops/infra.

Atualmente existem 6 projetos no Railway (TCE Scraper, Altis, NightMint, Permit, Speeko, Clearfy), a maioria com a forma "GitHub repo + Postgres + opcional Redis". Todos usam Cloudflare como DNS/CDN.

Launchpad é o repositório template e a documentação operacional dessa stack. O nome reflete a função: lançar projetos novos rapidamente a partir de uma base padronizada.

## Goals

- Reproduzir a experiência "git push e tá no ar" do Railway em uma VPS própria
- Onboarding de projeto novo: copy/paste do template + alguns ajustes, em até ~15 minutos
- VPS reprovisionável do zero seguindo scripts/guia (sem cliques em UI esquecidos)
- Aprender devops "de verdade": reverse proxy, SSL automático, containers, CI/CD, backup, observability
- Custo total mensal abaixo de US$15

## Non-goals

- Alta disponibilidade (multi-AZ, failover automático)
- Auto-scaling horizontal
- UI de gerenciamento (Coolify, Dokploy) - decisão consciente de ir "raw" para aprender
- Substituir produção de cliente pagante; isso é para projetos pessoais
- Suportar deploy de monorepos complexos com N serviços (cada projeto = 1 app + dependências locais)

## Arquitetura

```
                    Internet
                       |
                       v
                  Cloudflare
                  (DNS, WAF, DDoS, SSL termination opcional)
                       |
                       | TLS (Origin Cert da Cloudflare)
                       v
            +------------------------+
            |   Hetzner VPS (CX32)   |
            |                        |
            |   ufw firewall:        |
            |   - 80/443 só CF IPs   |
            |   - SSH só Tailscale   |
            |                        |
            |   Tailscale daemon     |
            |                        |
            |   +--------------+     |
            |   |   Traefik    |<----+--- TLS 443
            |   | (web network)|     |
            |   +------+-------+     |
            |          |             |
            |   roteia por Host      |
            |          |             |
            |   +------+-----+-----+-----+ ...
            |   |          |       |     |
            |   v          v       v     v
            |  altis    nightmint  ...  webhook
            |  + pg     + pg            (deploy svc)
            |   |          |             |
            |   internal   internal      internal
            |   (net)      (net)         (docker socket)
            +------------------------+
                       |
                       | pg_dump nightly (encrypted, age)
                       v
                Cloudflare R2 (backups)
```

### Componentes

**VPS:** Hetzner Cloud, instância `CX32` (4 vCPU compartilhados, 8GB RAM, 80GB SSD NVMe, ~EUR 6.50/mês). Região Helsinki ou Falkenstein. Ubuntu 24.04 LTS.

**Cloudflare:**
- DNS para `seudominio.com` e subdomínios (`<projeto>.seudominio.com`, `deploy.seudominio.com`)
- Proxy ativo (laranja) em todos os hosts: ganha WAF, rate limit, bloqueio de bot, DDoS protection
- SSL mode: "Full (strict)" usando Origin Certificate da Cloudflare instalado na VPS via Traefik
- R2 bucket para armazenar backups

**Traefik (v3):** Reverse proxy único na VPS. Configuração principal estática em arquivo, rotas dinâmicas via labels Docker. SSL termination usando Cloudflare Origin Certificate (cert gratuito da CF que dura 15 anos, válido apenas quando atrás do proxy CF). Cloudflare na frente faz SSL voltado pro cliente. Modo SSL na CF: "Full (strict)". Sem Let's Encrypt nessa arquitetura para evitar renovação automática + dependência externa adicional.

**Tailscale:** Acesso SSH à VPS exclusivamente via tailnet. Porta 22 fechada na internet pública. Permite SSH de qualquer máquina autorizada (laptop, celular) sem expor superfície de ataque.

**Deploy service (adnanh/webhook):** Container rodando na VPS, exposto em `deploy.seudominio.com`. Recebe POST do GitHub Actions, valida HMAC, executa script de deploy do projeto correspondente. Tem acesso ao Docker socket (`/var/run/docker.sock`) para orquestrar containers.

**Por projeto:** Cada projeto vive em `/srv/apps/<projeto>/` com:
- `docker-compose.yml` (app + postgres + redis opcional)
- `.env` (segredos, não versionado)
- `data/` (volumes persistentes: postgres data, uploads, etc.)
- Conexão à network `web` (compartilhada com Traefik) e `internal` (própria do projeto)

**Backups:** Cron job na VPS executa `pg_dump` de cada banco, criptografa com `age`, faz upload para Cloudflare R2. Chave `age` pública na VPS, privada offline (e em gerenciador de senhas).

## Fluxo de deploy

```
Developer                 GitHub                   VPS
    |                        |                      |
    | git push origin main   |                      |
    |----------------------->|                      |
    |                        | Actions:             |
    |                        |  1. checkout         |
    |                        |  2. login GHCR       |
    |                        |  3. build + push     |
    |                        |     image:${sha}     |
    |                        |     image:latest     |
    |                        |  4. POST deploy svc  |
    |                        |     (HMAC signed)    |
    |                        |--------------------->|
    |                        |                      | webhook valida HMAC
    |                        |                      | executa deploy-<proj>.sh:
    |                        |                      |   docker compose pull
    |                        |                      |   docker compose run migrate
    |                        |                      |   docker compose up -d app
    |                        |                      |   docker image prune
    |                        |<---------------------|
    |                        | exit 0 -> HTTP 200   |
    |                        | exit != 0 -> 500     |
    |                        |                      |
    |                        | environment status:  |
    |                        |  success | failure   |
    |                        |                      |
    |                        | GitHub Deployments   |
    |                        | UI mostra status     |
```

Tempo total esperado: ~30s build + ~10s deploy = ~40s do push ao container novo rodando.

### Auth do webhook

GitHub Actions calcula HMAC-SHA256 do payload usando segredo compartilhado, envia em header `X-Hub-Signature-256`. Webhook na VPS valida assinatura antes de executar qualquer comando. Segredo é único por projeto (`<PROJETO>_DEPLOY_SECRET`).

### GitHub Deployments

Usar a key `environment:` no job do workflow ativa automaticamente a UI nativa do GitHub Deployments. Não precisa de action de terceiros nem GitHub App:

```yaml
jobs:
  deploy:
    environment:
      name: production
      url: https://<projeto>.seudominio.com
```

GitHub cria deployment ao iniciar job, marca success/failure ao terminar, e o link aparece como "View deployment" na aba Deployments.

## Estrutura do launchpad repo

```
launchpad/
├── README.md                       # overview, quickstart
├── docs/
│   ├── superpowers/specs/         # specs como este
│   ├── runbooks/                  # operacional
│   │   ├── adicionar-projeto.md
│   │   ├── restaurar-backup.md
│   │   ├── recriar-vps.md
│   │   └── rotacionar-secrets.md
│   └── decisions/                 # ADRs futuros
├── vps-setup/
│   ├── README.md                   # passo a passo de provisioning
│   ├── 01-base.sh                  # user, ssh keys, timezone, pacotes básicos
│   ├── 02-firewall.sh              # ufw, regras CF IPs
│   ├── 03-tailscale.sh             # instala tailscale, configura ssh
│   ├── 04-docker.sh                # docker engine + compose
│   ├── 05-traefik.sh               # sobe stack do traefik
│   ├── 06-webhook.sh               # sobe stack do webhook deploy svc
│   └── 07-backup.sh                # cron pg_dump + r2 upload
├── infra/
│   ├── traefik/
│   │   ├── docker-compose.yml
│   │   ├── traefik.yml             # config estática
│   │   └── dynamic/                # config dinâmica (middlewares, etc)
│   ├── webhook/
│   │   ├── docker-compose.yml
│   │   ├── hooks.yaml              # config dos endpoints
│   │   └── scripts/                # scripts de deploy por projeto (gerados)
│   └── backup/
│       ├── backup.sh               # pg_dump + age + rclone
│       └── rclone.conf.template
├── templates/
│   ├── app/                        # template de novo projeto
│   │   ├── docker-compose.yml      # app + postgres + (opcional) redis
│   │   ├── .env.example
│   │   ├── Dockerfile.example
│   │   └── .github/workflows/
│   │       └── deploy.yml
│   └── hook.yaml.template          # bloco a colar em hooks.yaml
└── scripts/
    └── add-project.sh              # automatiza onboarding (futuro)
```

## Onboarding de projeto novo

Fluxo manual inicial (automatizável depois):

1. **No repo do projeto:**
   - Copiar `templates/app/docker-compose.yml` para a raiz, ajustar nome do serviço, image, port, volume
   - Copiar `templates/app/.github/workflows/deploy.yml`, ajustar nome do projeto e URL
   - Criar `Dockerfile` se ainda não existe
   - Adicionar secret `DEPLOY_SECRET` no GitHub repo settings

2. **No launchpad (commit + push):**
   - Adicionar bloco em `infra/webhook/hooks.yaml`
   - Criar script `infra/webhook/scripts/deploy-<projeto>.sh`

3. **Na VPS (via Tailscale SSH):**
   - `mkdir -p /srv/apps/<projeto>`
   - Copiar/criar `.env` com segredos reais
   - Pull do launchpad atualizado: `cd /srv/launchpad && git pull`
   - Restart do webhook: `cd /srv/infra/webhook && docker compose up -d`

4. **DNS:**
   - Adicionar registro A `<projeto>.seudominio.com` -> IP da VPS na Cloudflare (proxy ativo)

5. **Trigger primeiro deploy:**
   - Push para main no projeto. Verifica logs em GitHub Actions e na tab Deployments.

Em ~5 commits e um SSH curto, o projeto está no ar.

## Provisioning da VPS

Sequência reprodutível, executável de cima para baixo:

1. Criar VPS Hetzner CX32, Ubuntu 24.04, SSH key configurada
2. SSH inicial via IP público (única vez): `ssh root@<ip>`
3. Executar `01-base.sh`: cria user `deploy`, configura SSH keys, hardening básico (PermitRootLogin no, PasswordAuthentication no)
4. Executar `02-firewall.sh`: ufw default deny, allow 80/443 from Cloudflare IPs, allow 22 from `100.64.0.0/10` (Tailscale CGNAT range)
5. Executar `03-tailscale.sh`: `curl -fsSL https://tailscale.com/install.sh | sh`, `tailscale up --ssh`
6. A partir daqui, SSH só via Tailscale: `ssh deploy@<vps-tailscale-name>`
7. Executar `04-docker.sh`: instala Docker engine + plugin compose
8. Clonar launchpad em `/srv/launchpad`
9. Executar `05-traefik.sh`: instala Origin Cert da Cloudflare, sobe Traefik
10. Executar `06-webhook.sh`: gera secrets HMAC, sobe webhook service
11. Executar `07-backup.sh`: configura rclone com R2 creds, instala cron

VPS pronta para receber projetos.

## Estratégia de backup

### O quê

- Dump de cada banco Postgres (todas instâncias dos projetos)
- Frequência: diária às 03:00 UTC (baixo tráfego)
- Retenção: 7 dias dentro do bucket (lifecycle rule no R2)

### Como

```bash
# /srv/launchpad/infra/backup/backup.sh (simplificado)
for proj in /srv/apps/*/; do
  name=$(basename "$proj")
  ts=$(date -u +%Y%m%d-%H%M%S)
  docker compose -f "$proj/docker-compose.yml" exec -T postgres \
    pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
    | age -r "$AGE_RECIPIENT" \
    | rclone rcat "r2:launchpad-backups/$name/$ts.sql.age"
done
```

### Restore

Documentado em `docs/runbooks/restaurar-backup.md`:

```bash
rclone cat r2:launchpad-backups/<proj>/<ts>.sql.age \
  | age -d -i ~/.age/key.txt \
  | docker compose exec -T postgres psql -U <user> <db>
```

### Chave age

- Chave privada (`age-keygen` output) salva offline: 1Password + USB drive + papel
- Chave pública (recipient) na VPS em `/srv/launchpad/.age-recipients`
- Rotação anual, documentada como runbook

### O que NÃO está coberto

- Snapshot da VPS inteira (volumes, configs, /etc/) - futura iteração, pode usar snapshot Hetzner manual
- PITR (point-in-time recovery) - perda máxima é 24h, aceitável para projetos pessoais
- Restore automatizado / testes de restore - aceitar fazer manualmente uma vez por trimestre

## Modelo de segurança

### Superfície de ataque exposta

- **Cloudflare edge:** absorve a maior parte. WAF, rate limit, bot fight mode
- **VPS:** apenas 80/443 públicos, e só aceita conexões de IPs da Cloudflare (lista oficial atualizada manualmente trimestralmente, ou via script no `02-firewall.sh`)
- **SSH:** zero exposição pública. Único caminho é Tailscale.

### Segredos

- `.env` por projeto, em `/srv/apps/<projeto>/.env`, modo `600`, dono `deploy:deploy`
- Backup do `.env` manual: copiar conteúdo para 1Password ao criar/atualizar
- Não versionados em git
- Migração futura para SOPS+age planejada se gestão manual virar dor

### Webhook deploy

- HMAC-SHA256 obrigatório, segredo único por projeto
- Container do webhook tem `/var/run/docker.sock` montado: efetivamente root na VPS. Cuidar do segredo HMAC com o mesmo rigor de uma SSH key
- Logs do webhook em `journalctl` (via Docker logging driver) - todo deploy fica auditado

### Docker

- Containers não rodam como root quando possível (`USER` no Dockerfile)
- Networks: `internal` por projeto (só app + dependências), `web` (só Traefik + app)
- Postgres nunca exposto em network `web`

## Custos estimados (USD/mês)

| Item                       | Custo         |
|----------------------------|---------------|
| Hetzner CX32               | ~7.20         |
| Cloudflare DNS + proxy     | 0             |
| Cloudflare R2 (<10GB)      | 0 (free tier) |
| GHCR (<500MB privado/repo) | 0 (free tier) |
| Tailscale (free tier)      | 0             |
| Domínio (já possuído)      | -             |
| **Total**                  | **~7.20**     |

Comparado ao Railway, economia significativa quando os projetos rodam de verdade (Railway cobrava por uso de cada serviço; uma VPS fixa é fixed cost).

## Critérios de sucesso

O design é considerado bem sucedido quando:

1. VPS pode ser recriada do zero em <30 minutos seguindo apenas os scripts em `vps-setup/` (assumindo que `.env` de cada projeto está backupeado no 1Password)
2. Um projeto novo pode ser adicionado em <15 minutos (excluindo o tempo de escrever a app em si)
3. `git push` na main de qualquer projeto resulta em deploy em produção em <2 minutos sem ação humana
4. GitHub mostra status do deploy na tab Deployments igual o Railway fazia
5. Restore de qualquer banco em <10 minutos seguindo o runbook
6. Acesso SSH à VPS impossível de fora do tailnet, validado por scan externo
7. Custo total mensal real abaixo de US$10

## Roadmap incremental

Cada fase entrega valor independente:

**Fase 1 - Foundation (1 VPS, 1 projeto)**
- Provisionar VPS, ufw, tailscale, docker
- Subir Traefik
- Migrar 1 projeto (escolher o mais simples, provavelmente Permit ou TCE Scraper) como piloto manual sem webhook ainda

**Fase 2 - Deploy automatizado**
- Subir adnanh/webhook
- Construir workflow GH Actions do projeto piloto
- Validar fluxo completo: push -> Actions -> webhook -> deploy

**Fase 3 - Backup**
- Configurar R2 bucket, rclone, age
- Cron + script de backup
- Fazer um restore de teste

**Fase 4 - Migração dos demais projetos**
- Iterar nos 5 projetos restantes, refinando o template a cada onboarding

**Fase 5 - Operacional**
- Uptime Kuma para monitoring básico
- Runbooks completos
- Script `add-project.sh` que automatiza o onboarding

**Fase 6 (futuro, opcional)**
- Observability: Grafana + Prometheus + Loki
- SOPS para secrets
- Staging environment
- Snapshot semanal da VPS

## Decisões registradas

| Decisão                                    | Por quê                                              |
|--------------------------------------------|------------------------------------------------------|
| Traefik em vez de nginx/Caddy              | Service discovery via labels: combina com fluxo "copy template"; conceitos transferíveis pra K8s |
| 1 VPS para tudo                            | Custo, simplicidade. Splitar quando algum projeto crescer |
| Postgres por projeto (não compartilhado)   | Isolamento de dados, backups independentes, blast radius pequeno |
| Webhook em vez de SSH push do Actions      | Sem expor SSH, deploy controlado pela VPS, padrão webhook é familiar |
| GHCR em vez de Docker Hub                  | Grátis para repos privados, integrado com GH Actions |
| `.env` simples agora, SOPS depois          | YAGNI: começa simples, migra quando dor justificar    |
| pg_dump diário em vez de WAL archiving     | Suficiente para projetos pessoais, restore trivial    |
| Cloudflare R2 em vez de S3/B2              | Zero egress, free tier generoso                       |
| Hetzner em vez de outras VPS               | Custo/performance excelente, experiência prévia       |

## Riscos e mitigações

| Risco                                     | Mitigação                                              |
|-------------------------------------------|--------------------------------------------------------|
| VPS cai por hardware ou networking        | Cloudflare custom error page; redeploy em nova VPS via scripts (<30min RTO) |
| Webhook secret vaza                       | Rotacionar segredo (mudar em GH secret + hooks.yaml + restart webhook) |
| Backup nunca testado                      | Restore de teste obrigatório por trimestre como parte do runbook |
| Cloudflare API/conta indisponível         | Fallback: desativar proxy CF em registro DNS aponta direto pro IP (perde proteções mas projetos voltam) |
| Esquecer de adicionar `.env` em prod      | Healthcheck do container falha -> Traefik não roteia -> erro visível |
| Build container infla a imagem >GHCR free | Multi-stage Dockerfile no template; alerta se passar 400MB |

## Out of scope explícito

- Kubernetes
- Multi-region
- Auto-scaling
- CI runners self-hosted (continuar usando GitHub-hosted)
- Dashboard custom (Uptime Kuma já cobre o essencial)
- Email transacional (continuar usando serviço externo)
- Object storage de aplicação (continuar usando R2 ou similar diretamente das apps)

## Próximos passos

Após aprovação deste spec, próximo passo é gerar o **plano de implementação** detalhado (via skill `writing-plans`), que vai quebrar a Fase 1 em tarefas executáveis com checkpoints.
