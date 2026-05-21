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

Ordem sugerida para chegar do zero a 1 projeto deployado:

1. [Provisionar VPS](docs/runbooks/provisionar-vps.md) - cria VPS, instala docker/tailscale/firewall
2. [Subir Traefik](docs/runbooks/subir-traefik.md) - DNS, Origin Cert, reverse proxy no ar
3. [Adicionar projeto](docs/runbooks/adicionar-projeto.md) - onboarding de uma app

Operacionais:

- [Deploy manual de update (Phase 1)](docs/runbooks/deploy-manual-piloto.md)
- [Atualizar env var de um projeto](docs/runbooks/atualizar-env.md)

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
