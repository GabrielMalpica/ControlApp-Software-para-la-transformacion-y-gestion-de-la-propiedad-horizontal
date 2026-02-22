#!/usr/bin/env bash
set -euo pipefail

# Prefer explicit DATABASE_URL. If it's not present, map common Railway/Postgres vars.
if [ -z "${DATABASE_URL:-}" ]; then
  for candidate in DATABASE_PRIVATE_URL DATABASE_PUBLIC_URL POSTGRES_URL POSTGRES_PRISMA_URL; do
    value="${!candidate:-}"
    if [ -n "$value" ]; then
      export DATABASE_URL="$value"
      echo "[startup] DATABASE_URL was not set. Using $candidate as fallback."
      break
    fi
  done
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "[startup] ERROR: DATABASE_URL is not configured."
  echo "[startup] Configure DATABASE_URL in Railway Variables, or link your Postgres service and expose one of:"
  echo "[startup] DATABASE_URL, DATABASE_PRIVATE_URL, DATABASE_PUBLIC_URL, POSTGRES_URL, POSTGRES_PRISMA_URL"
  exit 1
fi

echo "[startup] Running Prisma migrations..."
npx prisma migrate deploy

echo "[startup] Seeding initial managers..."
node ./scripts/seed-initial-gerentes.js

echo "[startup] Starting API..."
node dist/index.js
