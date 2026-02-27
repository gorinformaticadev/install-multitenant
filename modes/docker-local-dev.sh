#!/usr/bin/env bash
# =============================================================================
# Modo: Docker Local Desenvolvimento
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALLER_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALL_DIR")/Projeto-menu-multitenant-seguro}"

# common.sh e docker-utils.sh ja foram carregados pelo install.sh

run_docker_local_dev() {
    local domain="$1"
    local email="$2"
    
    print_header "INSTALAÇÃO: Local Desenvolvimento com Docker"
    
    log_info "Este modo usa docker-compose.dev.yml para desenvolvimento local"
    log_info "Hot-reload ativado, portas expostas diretamente"
    
    # Verificar Docker
    check_docker
    check_docker_compose
    
    # Configurar .env files
    log_info "Configurando arquivos de ambiente..."
    
    if [[ ! -f "$PROJECT_ROOT/apps/backend/.env" ]]; then
        cp "$PROJECT_ROOT/apps/backend/.env.example" "$PROJECT_ROOT/apps/backend/.env" 2>/dev/null || true
    fi
    
    if [[ ! -f "$PROJECT_ROOT/apps/frontend/.env.local" ]]; then
        cp "$PROJECT_ROOT/apps/frontend/.env.example" "$PROJECT_ROOT/apps/frontend/.env.local" 2>/dev/null || true
    fi
    
    # Subir containers
    log_info "Iniciando containers de desenvolvimento..."
    cd "$PROJECT_ROOT"
    docker compose -f docker-compose.dev.yml up -d --build
    
    # Aguardar serviços
    sleep 10
    
    # Executar migrations
    log_info "Executando migrations..."
    docker exec -it multitenant-backend pnpm prisma migrate dev --name init || true
    
    # Executar seeds
    log_info "Populando banco de dados..."
    docker exec -it multitenant-backend pnpm prisma db seed || true
    
    print_separator
    echogreen "✓ Instalação concluída!"
    echo ""
    echo "Acesse a aplicação:"
    echo "  Frontend: http://localhost:5000"
    echo "  Backend:  http://localhost:4000"
    echo "  API Docs: http://localhost:4000/api"
    echo ""
    echo "Comandos úteis:"
    echo "  Ver logs:   docker compose -f docker-compose.dev.yml logs -f"
    echo "  Parar:      docker compose -f docker-compose.dev.yml down"
    echo "  Rebuild:    docker compose -f docker-compose.dev.yml build --no-cache"
    echo ""
}
