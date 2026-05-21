# Runbook: Atualizar env var de um projeto

Atualizar, adicionar ou remover variáveis de ambiente de uma app rodando.

Tempo: 1-2 minutos.

## Passos

```bash
ssh deploy@launchpad-prod
cd /srv/apps/<PROJETO>

# 1. Editar o .env
vim .env
# (adicione, remova ou altere as linhas necessárias)

# 2. Recriar o container da app com os env vars novos
docker compose up -d app

# 3. Validar
docker compose logs --tail=30 app
docker compose exec app printenv | grep <NOME_VAR>  # confirma a var nova
```

Pronto.

## Gotchas

### `docker compose restart` NÃO funciona

```bash
docker compose restart app   # NÃO pega .env novo
```

`restart` reusa o mesmo container, e env vars são carregadas só na criação do container. Tem que ser `up -d` (que detecta a config mudou e recria).

### Env vars do Postgres (POSTGRES_DB, USER, PASSWORD)

Se você mudar `POSTGRES_PASSWORD` (ou `POSTGRES_USER`, `POSTGRES_DB`), **isso não atualiza o banco existente**. Postgres lê essas vars só na primeira inicialização do volume. Para trocar credenciais de fato:

**Opção A: alterar dentro do banco (preserva dados)**
```bash
docker compose exec postgres psql -U <user_atual> -d <db>
# dentro do psql:
ALTER USER <user> WITH PASSWORD '<nova_senha>';
\q

# Atualize o .env
vim .env
# (POSTGRES_PASSWORD e DATABASE_URL)

# Recreate só a app (postgres continua rodando)
docker compose up -d app
```

**Opção B: reset do volume (apaga dados, dev/inicial só)**
```bash
docker compose down
sudo rm -rf data/postgres
# edita .env com a senha nova
docker compose up -d
docker compose run --rm app pnpm db:push   # ou seu comando de migrate
docker compose up -d app
```

### Variáveis que a app cacheou em memória

Algumas apps fazem cache de env vars em runtime (ex: connection pools criados no startup). Recreate do container já resolve, mas tenha em mente: se a app cacheia em memory tipo "primeira request inicializa o cliente", você pode precisar de um deploy completo (não só env).

### Backup no 1Password

Toda vez que mudar segredos (API keys, senhas), **atualize o item no 1Password antes de fechar a sessão**. Se a VPS for perdida, é a única coisa não-reproduzível.

## Validação pós-update

Que olhar:

- `docker compose ps`: app deve estar `Up` com timestamp recente
- `docker compose logs --tail=50 app`: sem erros relacionados à var (e.g., "missing env", "invalid token")
- Smoke test via browser ou `curl` no endpoint que usa a var
