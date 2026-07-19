# ============================================================
# frontend/Dockerfile
# Builds the React (Vite) frontend and serves it with Nginx.
#
# Stage 1 — Node builds the static bundle (dist/)
# Stage 2 — Nginx serves dist/ and proxies /auth, /books, /borrow
#
# The VITE_API_BASE build arg controls where the React app
# sends API calls. For docker-compose it is empty string ""
# because Nginx proxies the calls locally. For production
# it should also be "" (Nginx on EKS proxies to ALB).
# ============================================================

# ── Stage 1: Build ───────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files first — layer is cached until they change
COPY package.json ./

# npm install generates the lockfile inside the container.
# Once you commit a package-lock.json, switch this to:
#   COPY package.json package-lock.json ./
#   RUN npm ci --silent
RUN npm install --silent

# Copy all source files
COPY . .

# Build the production bundle → output goes to /app/dist
RUN npm run build

# ── Stage 2: Serve ───────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

# Upgrade all packages to patch known vulnerabilities (CVE-2026-31789)
RUN apk upgrade --no-cache

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built React app from Stage 1
COPY --from=builder /app/dist /usr/share/nginx/html

# Correct ownership for nginx process
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chmod -R 755 /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
