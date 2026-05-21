# Runbook: Subir Traefik pela primeira vez

Configura o reverse proxy na VPS com SSL via Cloudflare Origin Certificate. Faz isso uma única vez por VPS.

Tempo estimado: 15-20 minutos.

## Pré-requisitos

- VPS provisionada (ver [provisionar-vps.md](provisionar-vps.md))
- Acesso SSH via Tailscale: `ssh deploy@launchpad-prod`
- Conta na Cloudflare com `marcio.run` (ou seu domínio) configurado
- Launchpad clonado em `/srv/launchpad` na VPS

## 1. DNS na Cloudflare

No painel: `marcio.run` -> DNS -> Records.

Crie ou atualize (proxy ATIVO, ícone laranja) apontando para o IP público da VPS:

| Type | Name    | Content       | Proxy    |
|------|---------|---------------|----------|
| A    | deploy  | `<VPS_IP>`    | Proxied  |
| A    | traefik | `<VPS_IP>`    | Proxied  |

Os subdomínios de projetos (ex: `lupa`) serão criados quando você fizer onboarding de cada projeto (ver [adicionar-projeto.md](adicionar-projeto.md)).

Em SSL/TLS -> Overview, confirme modo **Full (strict)**.

## 2. Gerar Origin Certificate

Cloudflare -> SSL/TLS -> Origin Server -> Create Certificate.

- Private key type: **RSA (2048)**
- Hostnames: `*.marcio.run, marcio.run`
- Validity: **15 years**

Clique Create. **Atenção:** a janela com a private key abre só uma vez. Se fechar sem copiar, gere um novo.

No laptop, salve em arquivos temporários:

```bash
mkdir -p ~/launchpad-certs
chmod 700 ~/launchpad-certs
# Cole o "Origin Certificate" em:
nano ~/launchpad-certs/origin.pem
# Cole a "Private Key" em:
nano ~/launchpad-certs/origin.key
```

## 3. Transferir cert para a VPS

```bash
# do laptop
scp ~/launchpad-certs/origin.pem ~/launchpad-certs/origin.key \
  deploy@launchpad-prod:/tmp/
```

## 4. Instalar cert na VPS

```bash
ssh deploy@launchpad-prod
sudo mv /tmp/origin.pem /srv/launchpad/infra/traefik/certs/
sudo mv /tmp/origin.key /srv/launchpad/infra/traefik/certs/
sudo chown deploy:deploy /srv/launchpad/infra/traefik/certs/origin.*
chmod 644 /srv/launchpad/infra/traefik/certs/origin.pem
chmod 600 /srv/launchpad/infra/traefik/certs/origin.key
ls -la /srv/launchpad/infra/traefik/certs/
```

Expected: `origin.pem` (644) e `origin.key` (600).

## 5. Criar network compartilhada

```bash
docker network create web
```

Expected: imprime ID da network. Se já existe, mensagem "network with name web already exists" - tudo certo.

## 6. Subir Traefik

```bash
cd /srv/launchpad/infra/traefik
docker compose up -d
docker compose logs --tail=30
```

Expected nos logs:
- `Starting provider *docker.Provider`
- `Configuration loaded from file`
- Sem erros relacionados a TLS cert ou socket Docker

Se houver erro tipo `unable to load certificate`: confira permissões (Step 4) e que os arquivos estão no path certo.

Se houver erro tipo `client version 1.24 is too old. Minimum supported API version is Y`: você está em uma versão antiga do Traefik (<3.6). Docker 27+ removeu suporte a clientes que falam API <=1.39, e versões antigas do Traefik faziam fallback para 1.24. A stack atual usa `traefik:v3.7` que tem auto-negociação de API funcionando. Se ainda aparecer, garanta que está rodando a versão atualizada: `cd /srv/launchpad && git pull && cd infra/traefik && docker compose pull && docker compose up -d`.

## 7. Apagar cópias locais do cert

```bash
# no laptop
shred -u ~/launchpad-certs/origin.pem ~/launchpad-certs/origin.key
rmdir ~/launchpad-certs
```

Únicas cópias agora: VPS + painel da Cloudflare (que retém só metadados, não a chave privada).

## 8. Validar

Use um subdomínio que já tem DNS apontando pra VPS (foi criado no Step 1). Por exemplo:

```bash
# do laptop (substitua pelo seu domínio)
curl -I https://traefik.marcio.run
```

Expected: **HTTP/2 404** com `server: cloudflare`. O 404 é esperado porque ainda não tem app respondendo nesse subdomínio. O importante é que:
- Cloudflare resolveu DNS
- Cloudflare conectou na VPS via HTTPS
- Origin Cert foi aceito pela Cloudflare
- Traefik respondeu

Se vier `Bad Gateway` (502): Traefik não está rodando. Verifique `docker ps` na VPS.

Se vier erro de SSL: confira que CF está em "Full (strict)" e que o cert foi instalado com permissões corretas.

Se vier "could not resolve host": DNS ainda propagando. Aguarde 1-2 minutos e tente de novo.

Pronto. Próximo passo: [adicionar um projeto](adicionar-projeto.md).
