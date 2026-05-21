# Runbook: Subir o webhook deploy service

Sobe o serviço `adnanh/webhook` na VPS, exposto em `https://deploy.marcio.run`. Recebe POSTs assinados do GitHub Actions e executa scripts de deploy. Faz isso uma única vez por VPS.

Tempo: 10-15 minutos.

## Pré-requisitos

- Traefik rodando (ver [subir-traefik.md](02-subir-traefik.md))
- DNS de `deploy.marcio.run` apontando para o IP da VPS, proxy ativo
- SSH na VPS via Tailscale: `ssh deploy@launchpad-prod`

## 1. Atualizar o launchpad na VPS

```bash
ssh deploy@launchpad-prod
cd /srv/launchpad
git pull
```

A pasta `infra/webhook/` agora existe com Dockerfile, compose, template de hooks e scripts.

## 2. Configurar o `.env` do webhook

```bash
cd /srv/launchpad/infra/webhook
cp .env.example .env
chmod 600 .env
```

Gere o secret HMAC para o lupa:

```bash
openssl rand -hex 32
# ex: a8f3...d9e2
```

Edite `.env`:

```bash
vim .env
# substitua o valor de LUPA_DEPLOY_SECRET pelo openssl gerou
```

**Salve esse valor no 1Password agora.** Você vai precisar dele no GitHub Secrets do repo do lupa (Step 6 do [automatizar-deploy.md](05-automatizar-deploy.md)).

## 3. Build da imagem do webhook

A primeira vez exige build (estende a imagem do docker CLI e adiciona o binário do webhook):

```bash
docker compose build
```

Expected: build completa, image `launchpad/webhook:latest` criada.

## 4. Subir a stack

```bash
docker compose up -d
docker compose logs --tail=30
```

Expected nos logs:
- `serving hooks from /etc/webhook/hooks.yaml.tmpl`
- `starting up on port 9000`
- (com `-verbose`) lista dos hooks carregados, incluindo `hello` e `lupa`

## 5. Validar healthcheck

Do laptop:

```bash
curl https://deploy.marcio.run/hooks/hello
```

Expected: retorna `ok` (200). O hook `hello` não tem auth, serve só pra validar que o roteamento Cloudflare -> Traefik -> webhook chegou na porta certa.

## 6. Validar com HMAC (sem rodar deploy ainda)

Vamos enviar um POST assinado para `/hooks/lupa` para confirmar que a assinatura está sendo verificada:

```bash
# Pegue o secret do .env (sem expor no histórico):
SECRET=$(ssh deploy@launchpad-prod 'grep LUPA_DEPLOY_SECRET /srv/launchpad/infra/webhook/.env | cut -d= -f2')
PAYLOAD='{"image_tag":"latest"}'
SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print "sha256="$NF}')

curl -i -X POST https://deploy.marcio.run/hooks/lupa \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: $SIG" \
  -d "$PAYLOAD"
```

Expected: HTTP 200 com body "deploy triggered", e o script `deploy-lupa.sh` roda na VPS (pull + migrate + up). O lupa fica deployado com `:latest`. Confira:

```bash
ssh deploy@launchpad-prod 'docker logs webhook --tail 20'
```

Se a assinatura estiver errada, o webhook responde 400/403 com mensagem de "hook rule was not satisfied".

## 7. Troubleshooting

**`404 not found` na URL `/hooks/hello`:**
- Traefik roteando? `docker logs traefik | grep deploy`
- DNS de `deploy.marcio.run` propagado? `dig +short deploy.marcio.run`

**Webhook não consegue executar `docker`:**
- Socket montado? `docker exec webhook ls -la /var/run/docker.sock`
- Volumes corretos? `docker compose config`

**Webhook não encontra o script `deploy-lupa.sh`:**
- Permissão de exec? `ls -la /srv/launchpad/infra/webhook/scripts/`
- Script vem do volume mount?

**HMAC sempre invalida mesmo com secret certo:**
- Caracteres especiais no secret: gere com `openssl rand -hex 32` (zero special chars)
- Newline acidental no `.env`: arquivo não pode ter `\r\n` (use `dos2unix` se editou no Windows)

**Actions recebe 403 mas curl manual do laptop funciona:**

Cloudflare está bloqueando o request do GitHub Actions com challenge de bot (Bot Fight Mode). Sintomas no `curl -v`:
- `HTTP/1.1 403 Forbidden`
- `Cf-Mitigated: challenge`
- Body é HTML com `<title>Just a moment...</title>`

Webhook nunca recebe o request. Fix: adicione uma Custom Rule no WAF da Cloudflare exemptando o subdomínio `deploy.marcio.run`:

1. Cloudflare → `marcio.run` → Security → WAF → Custom rules → Create rule
2. Field: Hostname / equals / `deploy.marcio.run`
3. Action: Skip
4. Marque: Super Bot Fight Mode, Browser Integrity Check, All managed rules, Zone Lockdown
5. Deploy

Alternativa rápida (menos cirúrgica): desligar Bot Fight Mode globalmente em Security → Bots.

**`docker compose pull` falha com `unauthorized` ou `error from registry: unauthorized`:**
- A imagem no GHCR é privada e o container do webhook não tem credenciais do registry
- O compose monta `/home/deploy/.docker/config.json:/root/.docker/config.json:ro` para reusar o login do user `deploy` no host
- Garanta que você fez `docker login ghcr.io` como `deploy` (não como root) na VPS quando seguiu o [03-adicionar-projeto.md](03-adicionar-projeto.md)
- Verifique: `cat /home/deploy/.docker/config.json` (deve ter `auths` com `ghcr.io`)
- Se mudou o login no host depois de subir o webhook, recrie o container: `cd /srv/launchpad/infra/webhook && docker compose up -d`

Pronto. Próximo passo: [automatizar-deploy.md](05-automatizar-deploy.md) para o lupa (Steps 1-5 antes do GitHub Actions).
