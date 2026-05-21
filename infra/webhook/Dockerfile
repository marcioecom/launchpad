# Custom image: webhook + docker CLI + docker compose plugin.
# adnanh/webhook não vem com docker, então estendemos a imagem base do Docker CLI
# e adicionamos o binário do webhook.

FROM docker:28-cli

ARG WEBHOOK_VERSION=2.8.2

RUN apk add --no-cache \
      docker-cli-compose \
      curl \
      bash \
      tini && \
    curl -fsSL "https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-amd64.tar.gz" \
      -o /tmp/webhook.tar.gz && \
    tar -xzf /tmp/webhook.tar.gz -C /tmp && \
    mv "/tmp/webhook-linux-amd64/webhook" /usr/local/bin/webhook && \
    chmod +x /usr/local/bin/webhook && \
    rm -rf /tmp/webhook*

EXPOSE 9000

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/webhook"]
CMD ["-hooks", "/etc/webhook/hooks.yaml.tmpl", "-template", "-verbose"]
