#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# ZKTeco ADMS - Ubuntu 22.04 Docker Deployment Script
# Chạy: chmod +x deploy-ubuntu.sh && sudo ./deploy-ubuntu.sh
# ═══════════════════════════════════════════════════════════════

set -e

echo "═══════════════════════════════════════════════════════════"
echo "  ZKTeco ADMS - Docker Deployment for Ubuntu 22.04"
echo "═══════════════════════════════════════════════════════════"

# ──── Step 1: Install Docker ────
install_docker() {
    echo ""
    echo "▶ [1/5] Checking Docker..."
    if command -v docker &> /dev/null; then
        echo "  ✓ Docker already installed: $(docker --version)"
    else
        echo "  Installing Docker..."
        apt-get update -qq
        apt-get install -y ca-certificates curl gnupg lsb-release

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        systemctl start docker
        echo "  ✓ Docker installed: $(docker --version)"
    fi

    if ! docker compose version &> /dev/null; then
        echo "  ✗ Docker Compose plugin not found!"
        exit 1
    fi
    echo "  ✓ Docker Compose: $(docker compose version --short)"
}

# ──── Step 2: Setup project directory ────
setup_project() {
    echo ""
    echo "▶ [2/6] Setting up project directory..."
    
    PROJECT_DIR="/opt/zkteco"
    if [ ! -d "$PROJECT_DIR" ]; then
        mkdir -p "$PROJECT_DIR"
        echo "  Created $PROJECT_DIR"
    fi
    echo "  ✓ Project directory ready: $PROJECT_DIR"
}

# ──── Step 2.5: Login ghcr.io ────
login_ghcr() {
    echo ""
    echo "▶ [3/6] Logging into GitHub Container Registry..."
    
    cd "$PROJECT_DIR"
    
    if [ -z "$GHCR_TOKEN" ]; then
        read -sp "  Enter GitHub PAT (write:packages): " GHCR_TOKEN
        echo ""
    fi
    
    echo "$GHCR_TOKEN" | docker login ghcr.io -u Thuylienphat-coder --password-stdin
    echo "  ✓ Logged into ghcr.io"
}

# ──── Step 3: Configure .env ────
configure_env() {
    echo ""
    echo "▶ [4/6] Configuring environment..."
    
    cd "$PROJECT_DIR"
    
    if [ ! -f ".env" ]; then
        echo "  Creating .env from template..."
        
        # Auto-detect server IP
        SERVER_IP=$(hostname -I | awk '{print $1}')
        
        cat > .env << EOF
# ═══════════════════════════════════════════════════════════════
# ZKTeco ADMS - Production Environment
# Generated on $(date)
# ═══════════════════════════════════════════════════════════════

SERVER_HOST=${SERVER_IP}
API_BASE_URL=http://${SERVER_IP}:7070
API_PORT=7070
FLUTTER_PORT=3000

POSTGRES_DB=ZKTecoADMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
POSTGRES_PORT=5432

JWT_ACCESS_SECRET=$(openssl rand -base64 32)
JWT_REFRESH_SECRET=$(openssl rand -base64 32)
JWT_ISSUER=http://${SERVER_IP}
JWT_AUDIENCE=http://${SERVER_IP}
JWT_ACCESS_EXPIRATION=1500
JWT_REFRESH_EXPIRATION=120

DEFAULT_EMPLOYEE_PASSWORD=Ti100600@
REDIS_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
EOF
        echo "  ✓ .env created with auto-generated passwords"
        echo "  ⚠ Review and edit if needed: nano $PROJECT_DIR/.env"
    else
        echo "  ✓ .env already exists"
    fi
}

# ──── Step 4: Pull & Start ────
build_and_start() {
    echo ""
    echo "▶ [5/6] Pulling images and starting services..."
    
    cd "$PROJECT_DIR"
    
    # Stop existing containers
    docker compose -f docker-compose.prod.yml down 2>/dev/null || true
    
    # Pull latest images
    echo "  Pulling images from ghcr.io..."
    docker compose -f docker-compose.prod.yml pull
    
    # Start services
    echo "  Starting services..."
    docker compose -f docker-compose.prod.yml up -d
    
    echo "  ✓ Services started"
}

# ──── Step 5: Setup Firewall ────
setup_firewall() {
    echo ""
    echo "▶ [6/6] Configuring firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp   comment "SSH" 2>/dev/null || true
        ufw allow 7070/tcp comment "ZKTeco API" 2>/dev/null || true
        ufw allow 3000/tcp comment "ZKTeco Flutter" 2>/dev/null || true
        
        if ! ufw status | grep -q "Status: active"; then
            echo "y" | ufw enable
        fi
        echo "  ✓ Firewall configured (ports 22, 7070, 3000 open)"
    else
        echo "  ⚠ ufw not installed, skipping firewall setup"
    fi
}

# ──── Step 6: Health Check ────
health_check() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Waiting for services to start..."
    echo "═══════════════════════════════════════════════════════════"
    
    sleep 15
    
    echo ""
    echo "  Container Status:"
    docker compose -f docker-compose.prod.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    # Check API health
    if curl -sf http://localhost:7070/health > /dev/null 2>&1; then
        echo "  ✓ Backend API: HEALTHY (port 7070)"
    else
        echo "  ⚠ Backend API: starting up (may need more time)"
    fi
    
    # Check Flutter
    if curl -sf http://localhost:3000 > /dev/null 2>&1; then
        echo "  ✓ Flutter Client: HEALTHY (port 3000)"
    else
        echo "  ⚠ Flutter Client: starting up"
    fi
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Deployment Complete!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  🌐 Flutter Web:  http://${SERVER_IP}:3000"
    echo "  🔧 Backend API:  http://${SERVER_IP}:7070"
    echo "  📊 API Health:   http://${SERVER_IP}:7070/health"
    echo ""
    echo "  Useful commands:"
    echo "    View logs:     docker compose -f docker-compose.prod.yml logs -f"
    echo "    Restart:       docker compose -f docker-compose.prod.yml restart"
    echo "    Stop:          docker compose -f docker-compose.prod.yml down"
    echo "    Rebuild:       docker compose -f docker-compose.prod.yml up -d --build"
    echo ""
}

# ──── Run ────
install_docker
setup_project
login_ghcr
configure_env
build_and_start
setup_firewall
health_check
