# syntax=docker/dockerfile:1.7

# ----- build -----
FROM node:20-alpine AS build
WORKDIR /app

# Use a single RUN command to reduce layers and cleanup immediately
RUN apk add --no-cache python3 make g++ && \
    npm config set cache /tmp/.npm && \
    cp package*.json ./ && \
    npm ci && \
    rm -rf /tmp/.npm

COPY . ./

# Generate and build in one step with cleanup
RUN npm run prisma:generate && \
    npm run build && \
    npm cache clean --force && \
    rm -rf /root/.cache /tmp/* /var/tmp/*

# ----- runtime -----
FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

COPY package*.json ./
RUN npm ci --omit=dev && \
    npm cache clean --force && \
    rm -rf /root/.cache /tmp/* /var/tmp/*

COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
COPY DB/prisma/schema.prisma ./DB/prisma/schema.prisma

EXPOSE 80
CMD ["node", "dist/index.js"]
