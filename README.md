# Launchpad

Self-hosting deploy stack pessoal. Provisiona VPS Hetzner com Docker, Traefik e fluxo de deploy padronizado.

Arquitetura completa: ver [spec](docs/superpowers/specs/2026-05-21-launchpad-design.md).

## Quick start

1. Provisione uma VPS Hetzner (CX32 Ubuntu 24.04 recomendado)
2. Rode os scripts em `vps-setup/` em ordem
3. Suba a stack do Traefik (`infra/traefik/`)
4. Adicione projetos seguindo o template em `templates/app/`

Veja `docs/runbooks/provisionar-vps.md` para o passo a passo detalhado.
