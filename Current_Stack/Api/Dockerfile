# syntax=docker/dockerfile:1.7

# ----- build -----
FROM node:20 AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . ./

# Generate Prisma client
RUN npm run prisma:generate

RUN npm run build

# ----- runtime -----
FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

COPY package*.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
COPY DB/prisma/schema.prisma ./DB/prisma/schema.prisma

EXPOSE 80
CMD ["node", "dist/index.js"]
