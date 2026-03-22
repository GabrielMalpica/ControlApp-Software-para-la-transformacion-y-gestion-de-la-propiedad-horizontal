#!/usr/bin/env bash
set -euo pipefail

export TZ="${TZ:-America/Bogota}"

# Prefer explicit DATABASE_URL, but if it points to Railway internal host and a public URL
# exists, switch to the public URL to avoid unreachable private networking setups.
if [ -n "${DATABASE_URL:-}" ]; then
  if [[ "$DATABASE_URL" == *"postgres.railway.internal"* ]] && [ -n "${DATABASE_PUBLIC_URL:-}" ]; then
    export DATABASE_URL="$DATABASE_PUBLIC_URL"
    echo "[startup] DATABASE_URL pointed to postgres.railway.internal. Using DATABASE_PUBLIC_URL instead."
  fi
else
  for candidate in DATABASE_PUBLIC_URL POSTGRES_URL POSTGRES_PRISMA_URL DATABASE_PRIVATE_URL; do
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

echo "[startup] Building TypeScript..."
npm run build

echo "[startup] Seeding initial managers..."
node ./scripts/seed-initial-gerentes.js

echo "[startup] Starting API..."
node dist/index.js
