# syntax=docker/dockerfile:1.7

# ----- build -----
FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . ./
RUN npm run prisma:generate
RUN npm run build

# ----- runtime -----
FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=80

COPY package*.json ./
RUN npm ci --omit=dev
RUN npm run prisma:generate

COPY --from=build /app/dist ./dist

EXPOSE 80
CMD ["node", "dist/index.js"]
