#!/bin/sh
# Deploy script para o projeto lupa.
# Executado pelo webhook quando recebe um POST signed em /hooks/lupa.
# Argumento: image_tag (sha do commit, ou "latest")

set -e

IMAGE_TAG="${1:-latest}"
echo "==> Deploy lupa @ tag=${IMAGE_TAG}"

cd /srv/apps/lupa

echo "==> Pull da imagem nova"
IMAGE_TAG="${IMAGE_TAG}" docker compose pull app

echo "==> Migrations"
IMAGE_TAG="${IMAGE_TAG}" docker compose run --rm app pnpm db:push

echo "==> Recreate do container app (postgres mantém estado)"
IMAGE_TAG="${IMAGE_TAG}" docker compose up -d --no-deps app

echo "==> Limpeza de imagens órfãs"
docker image prune -f

echo "==> Deploy completo"
