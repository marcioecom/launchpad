# Launchpad

Self-hosting deploy stack pessoal. Provisiona VPS Hetzner com Docker, Traefik e fluxo de deploy padronizado.

## Status

- [x] Phase 1: Foundation (VPS, Traefik, 1 projeto piloto manual)
- [x] Phase 2: Deploy automatizado via webhook + GH Actions
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

Ordem sugerida para chegar do zero a 1 projeto deployado com deploy automatizado:

1. [Provisionar VPS](docs/runbooks/01-provisionar-vps.md) - cria VPS, instala docker/tailscale/firewall
2. [Subir Traefik](docs/runbooks/02-subir-traefik.md) - DNS, Origin Cert, reverse proxy no ar
3. [Adicionar projeto](docs/runbooks/03-adicionar-projeto.md) - onboarding manual de uma app
4. [Subir webhook](docs/runbooks/04-subir-webhook.md) - serviço que recebe POSTs do GH Actions e dispara deploy (uma vez por VPS)
5. [Automatizar deploy](docs/runbooks/05-automatizar-deploy.md) - adicionar deploy automático a um projeto (por projeto)

Operacionais:

- [Deploy manual de update](docs/runbooks/deploy-manual-piloto.md) - quando Actions estiver indisponível

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
