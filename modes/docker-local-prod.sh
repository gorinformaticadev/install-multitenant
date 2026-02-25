#!/usr/bin/env bash
# =============================================================================
# Modo: Docker Local Produção (Simulação)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALLER_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALL_DIR")/Projeto-menu-multitenant-seguro}"

# common.sh e docker-utils.sh ja foram carregados pelo install.sh

run_docker_local_prod() {
    local domain="$1"
    local email="$2"
    
    print_header "INSTALAÇÃO: Local Produção com Docker"
    
    log_info "Este modo simula produção localmente com build otimizado"
    
    # Verificar Docker
    check_docker
    check_docker_compose
    
    # Preparar .env.production
    local env_prod="$INSTALL_DIR/.env.production"
    
    if [[ ! -f "$env_prod" ]]; then
        cp "$INSTALL_DIR/.env.installer.example" "$env_prod" 2>/dev/null || \
        cp "$PROJECT_ROOT/.env.example" "$env_prod" 2>/dev/null || true
    fi
    
    # Configurar variáveis
    generate_db_credentials "$domain"
    
    upsert_env "DOMAIN" "$domain" "$env_prod"
    upsert_env "LETSENCRYPT_EMAIL" "$email" "$env_prod"
    upsert_env "FRONTEND_URL" "http://localhost:5000" "$env_prod"
    upsert_env "NEXT_PUBLIC_API_URL" "http://localhost:4000/api" "$env_prod"
    upsert_env "DATABASE_URL" "postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}?schema=public" "$env_prod"
    upsert_env "JWT_SECRET" "$JWT_SECRET" "$env_prod"
    upsert_env "ENCRYPTION_KEY" "$ENCRYPTION_KEY" "$env_prod"
    upsert_env "LOCAL_BUILD_ONLY" "true" "$env_prod"
    
    # Build e subir containers
    log_info "Construindo e iniciando containers..."
    cd "$PROJECT_ROOT"
    docker compose -f docker-compose.prod.yml -f docker-compose.prod.build.yml --env-file "$env_prod" up -d --build
    
    # Aguardar serviços
    sleep 15
    
    # Executar migrations
    log_info "Executando migrations..."
    docker compose -f docker-compose.prod.yml --env-file "$env_prod" exec backend pnpm exec prisma migrate deploy || true
    
    # Executar seeds
    log_info "Populando banco de dados..."
    docker compose -f docker-compose.prod.yml --env-file "$env_prod" exec backend pnpm exec prisma db seed || true
    
    print_separator
    echogreen "✓ Instalação concluída!"
    echo ""
    echo "Acesse via Nginx (configure /etc/hosts se necessário):"
    echo "  http://localhost (porta 80)"
    echo "  https://localhost (porta 443 - certificado autoassinado)"
    echo ""
    echo "Ou acesse diretamente (se portas expostas):"
    echo "  Frontend: http://localhost:5000"
    echo "  Backend:  http://localhost:4000"
    echo ""
}
