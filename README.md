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
