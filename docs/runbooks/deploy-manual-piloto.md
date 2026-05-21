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

docker buildx build \
  --platform linux/amd64 \
  --push \
  -t ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:$TAG \
  -t ghcr.io/<GITHUB_USER>/<GITHUB_REPO>:latest \
  .
```

Em Mac com Apple Silicon, `--platform linux/amd64` é obrigatório porque o build default seria ARM64 e a VPS é x86_64.

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
