# Runbook: Adicionar um projeto novo

Onboarding de uma aplicação na stack: build da imagem, registro de DNS, configuração na VPS e primeiro deploy.

Tempo estimado: 15-25 minutos (depende de quanto o projeto já tem pronto).

## Pré-requisitos

- VPS provisionada e com Traefik no ar ([subir-traefik.md](02-subir-traefik.md))
- Acesso ao repo do projeto no GitHub
- Postgres é a única dependência (Redis ou outros vêm depois)

## Variáveis usadas neste runbook

Substitua nos comandos:

- `<PROJETO>`: nome do projeto, kebab-case. Ex: `lupa`
- `<SUBDOMINIO>`: subdomínio que vai responder. Ex: `lupa` (vira `lupa.marcio.run`)
- `<DOMINIO>`: seu domínio. Ex: `marcio.run`
- `<GH_USER>`: seu username no GitHub. Ex: `marcioecom`
- `<GH_REPO>`: nome do repo do projeto. Ex: `lupa`
- `<APP_PORT>`: porta interna que a app escuta. Ex: `3000`

## 1. Preparar o projeto

No repo do projeto (laptop):

### 1a. Adicionar Dockerfile

Se já tem Dockerfile, revise. Senão, copie o template e adapte:

```bash
# do laptop, no repo do projeto
cp /caminho/para/launchpad/templates/app/Dockerfile.example ./Dockerfile
```

Ajustes que normalmente são necessários:
- Versão do Node (`ARG NODE_VERSION=22`)
- Comando de build (se a app precisar de compilação)
- Comando de start (`pnpm start`, `node dist/index.js`, etc)
- Porta exposta (`EXPOSE 3000`)

### 1b. Adicionar .dockerignore

```
node_modules
.git
.env
.env.*
!.env.example
dist
coverage
.vscode
.DS_Store
tests
```

### 1c. Testar build local

```bash
docker build -t <PROJETO>-test .
docker run --rm -e DATABASE_URL=postgres://fake -p 3000:3000 <PROJETO>-test
```

App deve iniciar (vai dar erro de DB connection, normal). `Ctrl+C` para parar.

### 1d. Commit e push

```bash
git add Dockerfile .dockerignore
git commit -m "feat: add production Dockerfile"
git push
```

## 2. Push da imagem inicial para GHCR

Para a primeira imagem precisamos fazer push manualmente. A automação via GH Actions vem na Phase 2.

### 2a. Criar PAT no GitHub

Em https://github.com/settings/tokens/new:
- Token classic
- Scope: `write:packages`
- Anote o token (vai aparecer só uma vez)

### 2b. Login e push

```bash
echo "<PAT>" | docker login ghcr.io -u <GH_USER> --password-stdin

docker buildx build \
  --platform linux/amd64 \
  --push \
  -t ghcr.io/<GH_USER>/<GH_REPO>:latest \
  .
```

**Por que `--platform linux/amd64`:** Macs com Apple Silicon (M1/M2/M3/M4) buildam ARM64 por default. A VPS é x86_64. Sem essa flag, o `docker pull` na VPS falha com "no matching manifest for linux/amd64". Em runners do GitHub Actions (Phase 2) isso some porque eles já rodam linux/amd64 nativo.

Se quiser uma imagem multi-arch (para usar localmente em ARM e na VPS em AMD), troque a flag por `--platform linux/amd64,linux/arm64`. Demora ~2x mais por build.

Confirme em https://github.com/<GH_USER>?tab=packages.

## 3. DNS na Cloudflare

Em `<DOMINIO>` -> DNS -> Records:

- **Type:** A
- **Name:** `<SUBDOMINIO>`
- **Content:** `<VPS_IP>`
- **Proxy:** Proxied (laranja)

Se já existia um A record (ex: estava apontando pro Railway), apenas atualize o Content para o novo IP.

Verifique:

```bash
dig +short <SUBDOMINIO>.<DOMINIO>
```

Expected: IPs da Cloudflare (104.x ou 172.67.x), não o IP da VPS (porque está proxied).

## 4. Login da VPS no GHCR

Se ainda não fez na VPS para outro projeto, crie um PAT separado **somente read** e logue:

### 4a. PAT read-only

Em https://github.com/settings/tokens/new:
- Token classic
- Scope: `read:packages` (só leitura)
- Nome sugerido: `vps-launchpad-prod-readonly`

### 4b. Login na VPS

```bash
ssh deploy@launchpad-prod
echo "<PAT_RO>" | docker login ghcr.io -u <GH_USER> --password-stdin
```

Esse login persiste em `~/.docker/config.json`. Vale para todos os pulls subsequentes.

## 5. Criar diretório do projeto na VPS

```bash
ssh deploy@launchpad-prod
sudo mkdir -p /srv/apps/<PROJETO>/data/postgres
sudo chown -R deploy:deploy /srv/apps/<PROJETO>
cd /srv/apps/<PROJETO>
```

## 6. Copiar template do compose e ajustar

```bash
cp /srv/launchpad/templates/app/docker-compose.yml ./docker-compose.yml

sed -i \
  -e 's/APP_NAME/<PROJETO>/g' \
  -e 's/SUBDOMAIN/<SUBDOMINIO>/g' \
  -e 's/DOMAIN/<DOMINIO>/g' \
  -e 's/GITHUB_USER/<GH_USER>/g' \
  -e 's/GITHUB_REPO/<GH_REPO>/g' \
  -e 's/APP_PORT/<APP_PORT>/g' \
  docker-compose.yml
```

Verifique:

```bash
cat docker-compose.yml
docker compose config > /dev/null && echo "OK"
```

Expected: nenhum placeholder literal sobrou (`APP_NAME`, `SUBDOMAIN`, etc), e `compose config` retorna "OK".

## 7. Criar `.env`

```bash
cp /srv/launchpad/templates/app/.env.example .env
chmod 600 .env
```

Edite (`vim .env` ou `nano .env`):

- `POSTGRES_PASSWORD`: gere com `openssl rand -hex 24` (use `-hex`, NÃO `-base64`: base64 gera `/`, `+`, `=` que quebram URL parsing no DATABASE_URL)
- `DATABASE_URL`: ajuste com a senha nova. Formato: `postgres://<user>:<senha>@postgres:5432/<db>`
- Outras env vars específicas da app (API keys, JWT secrets, URLs externas, etc)

**Gotcha do postgres:** o container só lê `POSTGRES_PASSWORD` na primeira inicialização do volume. Se você já subiu o postgres antes com outra senha e editar agora, precisa resetar:

```bash
docker compose down
rm -rf data/postgres
# depois sobe de novo no Step 8
```

**CRÍTICO:** copie o conteúdo do `.env` pro 1Password antes de prosseguir. Se a VPS for perdida, é a única coisa não reproduzível pelo código.

## 8. Primeiro deploy

```bash
cd /srv/apps/<PROJETO>

# Pull da imagem
docker compose pull

# Sobe postgres primeiro
docker compose up -d postgres
sleep 10
docker compose logs postgres | tail -10
# Espere "database system is ready to accept connections"

# Migrations (se a app tiver)
# Adapte o comando conforme o framework da app:
#   - Drizzle: docker compose run --rm app pnpm db:push
#   - Prisma: docker compose run --rm app pnpm prisma migrate deploy
#   - TypeORM: docker compose run --rm app pnpm typeorm migration:run

# Sobe a app
docker compose up -d app
docker compose logs -f app
# Ctrl+C nos logs quando ver que subiu (container continua rodando)
```

## 9. Validar

### Status dos containers

```bash
docker compose ps
```

Expected: ambos `Up X seconds` (postgres com `(healthy)`).

### Roteamento interno

```bash
docker exec traefik wget -q -O- --no-check-certificate https://<SUBDOMINIO>.<DOMINIO>/ | head
```

### Acesso externo

```bash
# do laptop
curl -I https://<SUBDOMINIO>.<DOMINIO>
```

Expected: `HTTP/2 200` (ou 301/302 se a app redireciona).

### Browser

Abra https://<SUBDOMINIO>.<DOMINIO>. Cadeado verde, app responde, funcionalidade básica funciona, dados persistem em reload.

## 10. Troubleshooting

**`Bad Gateway` (502):**
- App container subiu? `docker compose ps`
- App está escutando em `0.0.0.0`, não `127.0.0.1`? Logs vão dizer
- Porta no compose label bate com a porta real da app?

**`Not Found` (404) do Traefik:**
- Subdomínio na regra do Traefik bate com o que você acessou? `docker exec traefik traefik show config | grep -A2 routers`
- Cloudflare proxy ativo (laranja, não cinza)?

**App levanta mas DB connection falha:**
- DATABASE_URL aponta para `postgres:5432` (não `localhost`)?
- Postgres está `(healthy)`?
- Credenciais batem entre `POSTGRES_*` e `DATABASE_URL`?

**Pull do GHCR dá `denied`:**
- PAT na VPS tem escopo `read:packages`?
- Package no GitHub é privada e o PAT é do owner certo?
- Tente: `docker logout ghcr.io && docker login ghcr.io -u <GH_USER>`
