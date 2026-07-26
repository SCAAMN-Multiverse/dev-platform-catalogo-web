# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Angular — imagen multietapa. Contrato: PLATFORM.md §6.
#
# Etapa `dev`  -> ejecuta el DEV SERVER dentro del pod (ng serve). Es lo que
#                 hace posible el hot reload: si el contenedor sirviera el
#                 build de producción con nginx, sincronizar un fichero no
#                 tendría ningún efecto y el inner loop no existiría.
# Etapa `prod` -> build estático servido por nginx. Es lo que va a pre y pro.
#
# PIN DE VERSIONES — razón y condición de salida en PLATFORM.md §12.
# ---------------------------------------------------------------------------

# node:24.18.0-alpine — Node 24 "Krypton" es la línea LTS activa (2026-06-23) y
# está dentro del rango que exige Angular 22 (^22.22.3 || ^24.15.0 || >=26).
# CONDICIÓN DE SALIDA: subir cuando Node 26 pase a LTS, o al subir Angular a un
# major cuyo `engines` deje fuera a 24.
FROM node:24.18.0-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# `npm ci` (no `npm install`): instala EXACTAMENTE el lockfile. `npm install`
# puede reescribirlo y hace que dos builds del mismo commit difieran.
RUN npm ci

# --- dev: dev server con hot reload -----------------------------------------
FROM deps AS dev
WORKDIR /app
COPY . .
ENV NODE_ENV=development
# 8080 = puerto del dev server (targetPort del Service; el Service expone 80).
EXPOSE 8080
# host 0.0.0.0 y allowedHosts están en angular.json (architect.serve.options).
# NO se pasan aquí para que `ng serve` local y `ng serve` en el pod se
# comporten igual: una sola fuente de verdad.
CMD ["npm", "run", "start"]

# --- build: artefacto estático ----------------------------------------------
FROM deps AS build
WORKDIR /app
COPY . .
RUN npm run build

# --- prod: nginx sirviendo el estático --------------------------------------
# nginx:1.30.4-alpine — rama `stable` de nginx a fecha de escritura.
# CONDICIÓN DE SALIDA: subir con cada nueva `stable` (1.32.x), o antes si sale
# un aviso de seguridad para 1.30.
FROM nginx:1.30.4-alpine AS prod
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/catalogo-web/browser /usr/share/nginx/html
# 8080 y no 80: nginx corre sin privilegios; el Service sigue exponiendo 80.
EXPOSE 8080
