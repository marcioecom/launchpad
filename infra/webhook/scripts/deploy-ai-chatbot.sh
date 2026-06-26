#!/bin/sh
# Deploy script para o projeto ai-chatbot.
# Executado pelo webhook quando recebe um POST signed em /hooks/ai-chatbot.
# Argumento: image_tag (sha do commit, ou "latest")

set -e

IMAGE_TAG="${1:-latest}"
echo "==> Deploy ai-chatbot @ tag=${IMAGE_TAG}"

cd /srv/apps/ai-chatbot

echo "==> Pull da imagem nova"
IMAGE_TAG="${IMAGE_TAG}" docker compose pull app

echo "==> Recreate do container app"
IMAGE_TAG="${IMAGE_TAG}" docker compose up -d --no-deps app

echo "==> Limpeza de imagens órfãs"
docker image prune -f

echo "==> Deploy completo"
