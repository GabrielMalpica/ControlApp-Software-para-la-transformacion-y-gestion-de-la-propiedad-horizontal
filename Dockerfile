FROM node:22-bookworm-slim AS node_runtime

FROM postgres:18.4-bookworm

COPY --from=node_runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node_runtime /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
WORKDIR /app/contorlapp_backend

COPY contorlapp_backend/package.json contorlapp_backend/package-lock.json ./
COPY contorlapp_backend/prisma ./prisma
RUN npm ci --include=dev

COPY contorlapp_backend/tsconfig.json ./
COPY contorlapp_backend/src ./src
COPY contorlapp_backend/scripts ./scripts
RUN npm run build && npm prune --omit=dev

WORKDIR /app
COPY package.json ./

EXPOSE 3000
CMD ["npm", "start"]
