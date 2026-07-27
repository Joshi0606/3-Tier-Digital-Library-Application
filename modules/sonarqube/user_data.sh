#!/bin/bash
set -e
exec > >(tee /var/log/sonarqube-userdata.log) 2>&1

echo "=== SonarQube bootstrap started at $(date) ==="

# ── OS tuning — required by Elasticsearch inside SonarQube ───────────────────
# Without this, Elasticsearch refuses to start with:
# "max virtual memory areas vm.max_map_count is too low"
sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" >> /etc/sysctl.conf

# ── Install Docker (Amazon Linux 2023 uses dnf) ───────────────────────────────
dnf update -y
dnf install -y docker

usermod -aG docker ec2-user
systemctl enable docker
systemctl start docker

# ── Docker Compose v2 plugin ──────────────────────────────────────────────────
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ── SonarQube docker-compose (H2 embedded DB — learning/dev only) ─────────────
mkdir -p /opt/sonarqube
cd /opt/sonarqube

cat > docker-compose.yml <<EOF
version: '3.8'
services:
  sonarqube:
    image: sonarqube:${sonarqube_version}-community
    container_name: sonarqube
    restart: unless-stopped
    ports:
      - "9000:9000"
    environment:
      # Disables bootstrap checks so Elasticsearch starts on t3.small
      SONAR_ES_BOOTSTRAP_CHECKS_DISABLE: "true"
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs

volumes:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
EOF

docker compose up -d

# ── Wait for SonarQube to be ready (up to 10 minutes) ────────────────────────
echo "Waiting for SonarQube to be ready..."
for i in $$(seq 1 60); do
  STATUS=$$(curl -s http://localhost:9000/api/system/status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)
  echo "  Attempt $$i/60 — status: $${STATUS:-no response}"
  if [ "$${STATUS}" = "UP" ]; then
    echo "SonarQube is UP!"
    break
  fi
  sleep 10
done

echo "=== SonarQube bootstrap finished at $(date) ==="
