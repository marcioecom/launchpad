# Runbook: Automatizar deploy via GitHub Actions

Adiciona o fluxo `git push -> Actions -> webhook -> deploy` em um projeto. Faz isso uma vez por projeto.

Tempo: 10-15 minutos por projeto.

## Pré-requisitos

- Webhook service rodando ([subir-webhook.md](04-subir-webhook.md))
- Projeto já onboarded e rodando manualmente ([adicionar-projeto.md](03-adicionar-projeto.md))
- Acesso ao repo do projeto no GitHub (sua org/conta)

## Variáveis

Substitua nos comandos:

- `<PROJETO>`: kebab-case, ex: `lupa`
- `<DOMINIO>`: domínio completo, ex: `lupa.marcio.run`
- `<PROJETO_UPPER>`: maiúsculo, ex: `LUPA` (usado em `LUPA_DEPLOY_SECRET`)

## 1. Gerar secret HMAC (se ainda não tem)

Se você está automatizando o **lupa pela primeira vez**, o secret já foi gerado em [subir-webhook.md](04-subir-webhook.md) Step 2 - pule pro Step 2 aqui.

Para projetos novos, na VPS:

```bash
ssh deploy@launchpad-prod
SECRET=$(openssl rand -hex 32)
echo "$SECRET"
# Salve esse valor no 1Password (vai usar no GitHub Secrets também)
```

Adicione ao `.env` do webhook:

```bash
echo "<PROJETO_UPPER>_DEPLOY_SECRET=$SECRET" | sudo tee -a /srv/launchpad/infra/webhook/.env
```

## 2. Adicionar entrada no `hooks.yaml.tmpl`

No laptop, edite `infra/webhook/hooks.yaml.tmpl`:

```yaml
- id: <PROJETO>
  execute-command: /scripts/deploy-<PROJETO>.sh
  command-working-directory: /srv/apps/<PROJETO>
  pass-arguments-to-command:
    - source: payload
      name: image_tag
  response-message: "deploy triggered"
  trigger-rule:
    match:
      type: payload-hmac-sha256
      secret: "{{ getenv `<PROJETO_UPPER>_DEPLOY_SECRET` | js }}"
      parameter:
        source: header
        name: X-Hub-Signature-256
```

## 3. Criar o script de deploy

Copie o template:

```bash
cp templates/app/deploy-script.sh.example infra/webhook/scripts/deploy-<PROJETO>.sh
chmod +x infra/webhook/scripts/deploy-<PROJETO>.sh
```

Edite e substitua:
- `PROJETO` pelo nome real (3 ocorrências: echo, cd, log)
- `MIGRATE_CMD` pelo comando de migration apropriado (ou remova o bloco se não tiver)

Comandos comuns:
- Drizzle: `pnpm db:push`
- Prisma: `pnpm prisma migrate deploy`
- TypeORM: `pnpm typeorm migration:run`

Commit:

```bash
cd /Users/marciojunior/code/marcioecom/launchpad
git add infra/webhook/hooks.yaml.tmpl infra/webhook/scripts/deploy-<PROJETO>.sh
git commit -m "feat(webhook): add deploy hook for <PROJETO>"
git push
```

## 4. Aplicar mudanças no webhook na VPS

```bash
ssh deploy@launchpad-prod
cd /srv/launchpad
git pull

cd infra/webhook
docker compose up -d  # recria container, pega .env e config novos
docker compose logs --tail=30
```

Expected nos logs: `serving X hooks` (X = quantos hooks no template).

## 5. Adicionar GitHub Action workflow no projeto

No repo do projeto:

```bash
cd /Users/marciojunior/code/newcode/<PROJETO>
mkdir -p .github/workflows
cp /Users/marciojunior/code/marcioecom/launchpad/templates/app/github-workflow-deploy.yml.example \
   .github/workflows/deploy.yml
```

Edite `.github/workflows/deploy.yml` e substitua:
- `PROJETO` pelo nome (2 ocorrências: DEPLOY_URL e environment vars)
- `DOMINIO` pelo domínio completo (1 ocorrência: environment URL)

## 6. Configurar GitHub Secret

No GitHub: `https://github.com/<seu_user>/<repo>/settings/secrets/actions`

- New repository secret
- Name: `DEPLOY_SECRET`
- Value: o `openssl rand -hex 32` gerado no Step 1 (ou já no Step 2 do subir-webhook se for lupa)

Pode confirmar no 1Password se o valor está consistente.

## 7. Push e validar

Commit e push o workflow:

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add automated deploy workflow"
git push
```

Acompanhe em `https://github.com/<seu_user>/<repo>/actions`:

1. Job começa em ~5s
2. Build da imagem (~30s-2min)
3. Push pro GHCR
4. POST para `https://deploy.marcio.run/hooks/<PROJETO>`
5. Webhook responde 200, script roda na VPS
6. Aba **Deployments** do repo mostra deployment com status "active"

Em `https://<DOMINIO>` a versão nova já deve estar no ar.

## 8. Validações pós-setup

```bash
# Smoke test
curl -I https://<DOMINIO>
# expected: 200

# Logs do webhook
ssh deploy@launchpad-prod 'docker logs webhook --tail 30'
# expected: ver a entrada do hook execute

# Aba Deployments do GitHub
# repo -> environments -> production -> ver lista de deployments
```

## 9. Troubleshooting

**Action rodou mas webhook retornou 400/403:**
- Secret no GitHub bate com o do `.env` do webhook?
- Newline acidental? Recopie tudo certinho do 1Password
- Logs do webhook: `docker logs webhook --tail 50`

**Action rodou, webhook 200, mas app não atualizou:**
- Imagem foi pulhada? `docker images | grep <PROJETO>`
- Script falhou no meio? `docker logs webhook --tail 50`
- Migration travou? Veja logs do `docker compose run` no log do webhook

**Push pro GHCR falha na Action:**
- O job tem `permissions: packages: write`?
- Login step antes do build?

**`environment: production` não aparece na aba Deployments:**
- Job rodou com sucesso até o fim?
- Workflow tem `permissions: deployments: write`?
- O bloco `environment:` está corretamente indentado no job?
