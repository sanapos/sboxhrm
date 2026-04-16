#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# ZKTeco ADMS - Deploy Script
# Usage: ./deploy.sh [start|stop|restart|logs|status|build]
# ═══════════════════════════════════════════════════════════════

set -e

COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check .env exists
check_env() {
    if [ ! -f "$ENV_FILE" ]; then
        log_warn ".env file not found! Creating from .env.example..."
        if [ -f ".env.example" ]; then
            cp .env.example .env
            log_info "Created .env from .env.example"
            log_warn "Please edit .env with your server settings before deploying!"
            echo ""
            echo "  1. Edit .env file: nano .env"
            echo "  2. Change SERVER_HOST to your server IP"
            echo "  3. Change API_BASE_URL to http://<YOUR_IP>:7070"
            echo "  4. Change JWT secrets for security"
            echo "  5. Run: ./deploy.sh start"
            echo ""
            exit 1
        else
            log_error ".env.example not found!"
            exit 1
        fi
    fi
}

case "${1:-start}" in
    build)
        check_env
        log_info "Building Docker images..."
        docker compose -f $COMPOSE_FILE --env-file $ENV_FILE build --no-cache
        log_info "Build complete!"
        ;;

    start)
        check_env
        log_info "Starting ZKTeco ADMS..."
        docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --build
        echo ""
        log_info "========================================="
        log_info "  ZKTeco ADMS is starting up!"
        log_info "========================================="
        source $ENV_FILE 2>/dev/null || true
        echo "  API Backend:    http://${SERVER_HOST:-localhost}:${API_PORT:-7070}"
        echo "  Flutter Client:  http://${SERVER_HOST:-localhost}:${FLUTTER_PORT:-3000}"
        echo "  PostgreSQL:      ${SERVER_HOST:-localhost}:${POSTGRES_PORT:-5432}"
        echo ""
        echo "  View logs: ./deploy.sh logs"
        echo "  Status:    ./deploy.sh status"
        echo ""
        ;;

    stop)
        log_info "Stopping ZKTeco ADMS..."
        docker compose -f $COMPOSE_FILE down
        log_info "Stopped."
        ;;

    restart)
        log_info "Restarting ZKTeco ADMS..."
        docker compose -f $COMPOSE_FILE --env-file $ENV_FILE down
        docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --build
        log_info "Restarted."
        ;;

    logs)
        docker compose -f $COMPOSE_FILE logs -f ${2:-}
        ;;

    status)
        echo ""
        log_info "Container Status:"
        docker compose -f $COMPOSE_FILE ps
        echo ""
        log_info "Health Check:"
        docker compose -f $COMPOSE_FILE ps --format "table {{.Name}}\t{{.Status}}"
        echo ""
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|build|logs|status}"
        echo ""
        echo "  start    - Build and start all services"
        echo "  stop     - Stop all services"
        echo "  restart  - Rebuild and restart all services"
        echo "  build    - Build images without starting"
        echo "  logs     - View logs (optional: logs api|flutter|postgres)"
        echo "  status   - Show container status"
        ;;
esac
