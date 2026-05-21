# VPS Setup

Scripts idempotentes para provisionar uma VPS Ubuntu 24.04 do zero.

## Ordem

1. **`01-base.sh`** - como root, na primeira conexão. Cria user `deploy`, hardening SSH, instala pacotes base.
2. **`03-tailscale.sh`** - como deploy. Instala Tailscale e habilita SSH via tailnet. **Rode ANTES do firewall** para não perder acesso.
3. **`02-firewall.sh`** - como deploy. Configura ufw para aceitar 80/443 só da Cloudflare, bloqueia SSH público.
4. **`04-docker.sh`** - como deploy. Instala Docker Engine e plugin compose.

## Por que essa ordem?

Os scripts 02 e 03 estão "fora de ordem" intencionalmente. Você precisa do Tailscale ATIVO antes de bloquear SSH público, senão se trancar pra fora da VPS.

## Variáveis de ambiente

`03-tailscale.sh` aceita `TAILSCALE_HOSTNAME` (default `launchpad-prod`).

```bash
TAILSCALE_HOSTNAME=meu-server bash 03-tailscale.sh
```

## Idempotência

Todos os scripts são seguros para re-executar. Eles checam estado existente antes de modificar.
