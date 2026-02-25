#!/usr/bin/env bash
# =============================================================================
# Modo: Nativo VPS Desenvolvimento
# =============================================================================
# Instala todos os componentes diretamente no sistema operacional:
# Node.js 20, pnpm, PostgreSQL 15, Redis 7, PM2, Nginx, Certbot
# Usa PM2 para gerenciar processos (mais flexivel para dev).
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALLER_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALL_DIR")/Projeto-menu-multitenant-seguro}"

# common.sh, docker-utils.sh e native-utils.sh ja foram carregados pelo install.sh

run_native_vps_dev() {
    local domain="$1"
    local email="$2"

    print_header "INSTALACAO: VPS Desenvolvimento Nativo (sem Docker)"

    log_info "Ambiente: VPS/Servidor (Desenvolvimento)"
    log_info "Metodo: Instalacao nativa (Node.js + PostgreSQL + Redis no sistema)"
    log_info "Gerenciador de processos: PM2"
    log_info "Branch recomendada: dev"

    # --- Verificar branch ---
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        # Lidar com o problema de segurança do Git sobre propriedade duvidosa
        git config --global --add safe.directory "$PROJECT_ROOT" 2>/dev/null || true
        local current_branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null)
        if [[ -n "$current_branch" ]] && [[ "$current_branch" != "dev" ]]; then
            log_warn "Branch atual: $current_branch (recomendado: dev)"
            if ! confirm_action "Deseja continuar mesmo assim?" "n"; then
                log_error "Instalacao cancelada. Mude para branch dev primeiro."
                exit 1
            fi
        fi
    fi

    # --- Perguntar credenciais ---
    local admin_email="${INSTALL_ADMIN_EMAIL:-$email}"
    local admin_pass="${INSTALL_ADMIN_PASSWORD:-}"

    if [[ "$INSTALL_NO_PROMPT" != "true" ]]; then
        [[ -z "$admin_email" ]] && admin_email="$email"
        read -sp "Senha inicial do admin [123456]: " admin_pass
        echo
        admin_pass="${admin_pass:-123456}"
    else
        admin_pass="${admin_pass:-123456}"
    fi

    # --- Gerar credenciais ---
    local domain_prefix=$(echo "$domain" | tr -cd '[:alnum:]' | cut -c1-16 | tr '[:upper:]' '[:lower:]')
    local db_name="${DB_NAME:-db_${domain_prefix}}"
    local db_user="${DB_USER:-us_${domain_prefix}}"
    local db_pass="${DB_PASSWORD:-$(openssl rand -hex 16)}"
    local jwt_secret="${JWT_SECRET:-$(openssl rand -hex 32)}"
    local enc_key="${ENCRYPTION_KEY:-$(openssl rand -hex 32)}"

    print_separator
    log_info "Iniciando instalacao dos componentes..."

    # --- 1. Preparacao ---
    apt-get update -qq
    create_system_user
    setup_timezone
    setup_directories

    # --- 2. Instalar dependencias ---
    install_nodejs
    # Preparar ambiente do usuário multitenant após instalação do Node.js e pnpm
    prepare_multitenant_environment
    install_postgresql
    install_redis
    install_pm2
    install_nginx
    install_certbot

    print_separator
    log_info "Componentes instalados. Configurando aplicacao..."

    # --- 3. Configurar PostgreSQL ---
    configure_postgresql "$db_name" "$db_user" "$db_pass"

    # --- 4. Ajustar permissoes ---
    fix_project_permissions

    # --- 5. Configurar .env dos apps ---
    configure_backend_env "$domain" "$db_user" "$db_pass" "$db_name" \
        "$jwt_secret" "$enc_key" "$admin_email" "$admin_pass" "development"
    configure_frontend_env "$domain"

    # --- 6. Build da aplicacao ---
    build_application "development"

    # --- 7. Migrations e Seeds ---
    run_migrations
    run_seeds

    # --- 8. SSL ---
    local ssl_cert="/etc/ssl/multitenant/cert.pem"
    local ssl_key="/etc/ssl/multitenant/key.pem"

    generate_self_signed_cert "$domain"

    # Configurar nginx com autoassinado antes do Certbot para servir ACME challenge.
    configure_nginx_native "$domain" "$ssl_cert" "$ssl_key"

    # Tentar Let's Encrypt (pode falhar em dev)
    if obtain_native_ssl_cert "$domain" "$email" 2>/dev/null; then
        ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"
        configure_nginx_native "$domain" "$ssl_cert" "$ssl_key"
        setup_certbot_renewal
    else
        log_info "Usando certificado autoassinado (OK para desenvolvimento)."
    fi

    # --- 10. Iniciar com PM2 ---
    setup_pm2_services "development" 1
    start_pm2_services

    # --- 11. Verificar saude ---
    check_native_health "$domain"

    # --- Relatorio final ---
    print_native_report "$domain" "$admin_email" "$admin_pass" \
        "$db_name" "$db_user" "$db_pass" "$jwt_secret" "$enc_key" "pm2"
}
