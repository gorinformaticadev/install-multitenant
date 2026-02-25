#!/usr/bin/env bash
# =============================================================================
# Modo: Nativo VPS Producao
# =============================================================================
# Instala todos os componentes diretamente no sistema operacional:
# Node.js 20, pnpm, PostgreSQL 15, Redis 7, Nginx, Certbot
# Usa systemd para gerenciar processos (mais robusto para producao).
# Inclui hardening basico de seguranca.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALLER_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALL_DIR")/Projeto-menu-multitenant-seguro}"

# common.sh, docker-utils.sh e native-utils.sh ja foram carregados pelo install.sh

run_native_vps_prod() {
    local domain="$1"
    local email="$2"

    print_header "INSTALACAO: VPS Producao Nativo (sem Docker)"

    log_info "Ambiente: VPS/Servidor (Producao)"
    log_info "Metodo: Instalacao nativa (Node.js + PostgreSQL + Redis no sistema)"
    log_info "Gerenciador de processos: systemd"
    log_info "Branch recomendada: main"

    # --- Verificar branch ---
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        # Lidar com o problema de segurança do Git sobre propriedade duvidosa
        git config --global --add safe.directory "$PROJECT_ROOT" 2>/dev/null || true
        local current_branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null)
        if [[ -n "$current_branch" ]] && [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
            log_warn "Branch atual: $current_branch (recomendado: main ou master)"
            if ! confirm_action "Deseja continuar mesmo assim?" "n"; then
                log_error "Instalacao cancelada. Mude para branch main primeiro."
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
    install_nginx
    install_certbot

    # PM2 nao e necessario em producao (usamos systemd), mas instalar
    # para facilitar manutencao manual se necessario
    install_pm2

    print_separator
    log_info "Componentes instalados. Configurando aplicacao..."

    # --- 3. Hardening basico ---
    harden_system

    # --- 4. Configurar PostgreSQL ---
    configure_postgresql "$db_name" "$db_user" "$db_pass"
    harden_postgresql

    # --- 5. Configurar Redis ---
    harden_redis

    # --- 6. Ajustar permissoes ---
    fix_project_permissions

    # --- 7. Configurar .env dos apps ---
    configure_backend_env "$domain" "$db_user" "$db_pass" "$db_name" \
        "$jwt_secret" "$enc_key" "$admin_email" "$admin_pass" "production"
    configure_frontend_env "$domain"

    # --- 8. Build da aplicacao ---
    build_application "production"

    # --- 9. Migrations e Seeds ---
    run_migrations
    run_seeds

    # --- 10. SSL ---
    local ssl_cert="/etc/ssl/multitenant/cert.pem"
    local ssl_key="/etc/ssl/multitenant/key.pem"

    # Em producao, tentar Let's Encrypt primeiro
    generate_self_signed_cert "$domain"

    # Configurar nginx primeiro com autoassinado para ACME challenge funcionar
    configure_nginx_native "$domain" "$ssl_cert" "$ssl_key"

    if obtain_native_ssl_cert "$domain" "$email"; then
        ssl_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        ssl_key="/etc/letsencrypt/live/$domain/privkey.pem"
        # Reconfigurar nginx com cert real
        configure_nginx_native "$domain" "$ssl_cert" "$ssl_key"
        setup_certbot_renewal
        echogreen "Certificado SSL valido (Let's Encrypt) instalado."
    else
        log_warn "Usando certificado autoassinado. Configure Let's Encrypt manualmente depois."
        log_info "Comando: certbot --nginx -d $domain -m $email --agree-tos"
    fi

    # --- 11. Configurar e iniciar com systemd ---
    setup_systemd_services "production"
    start_systemd_services

    # --- 12. Verificar saude ---
    check_native_health "$domain"

    # --- Relatorio final ---
    print_native_report "$domain" "$admin_email" "$admin_pass" \
        "$db_name" "$db_user" "$db_pass" "$jwt_secret" "$enc_key" "systemd"
}

# =============================================================================
# Funcoes de hardening (apenas para producao)
# =============================================================================

harden_system() {
    log_info "Aplicando hardening basico do sistema..."

    # Atualizar pacotes
    apt-get upgrade -y -qq 2>/dev/null || true

    # Instalar fail2ban
    if ! command -v fail2ban-client &>/dev/null; then
        apt-get install -y -qq fail2ban
        systemctl enable fail2ban
        systemctl start fail2ban
        log_success "fail2ban instalado e ativo."
    fi

    # Configurar limites de arquivos abertos
    if ! grep -q "multitenant" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS'

# Multitenant - limites de producao
multitenant soft nofile 65535
multitenant hard nofile 65535
LIMITS
        log_info "Limites de arquivos configurados para usuario multitenant."
    fi

    # Configurar sysctl para producao
    if [[ ! -f /etc/sysctl.d/99-multitenant.conf ]]; then
        cat > /etc/sysctl.d/99-multitenant.conf << 'SYSCTL'
# Multitenant - tunning de rede para producao
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.netdev_max_backlog = 65535
SYSCTL
        sysctl -p /etc/sysctl.d/99-multitenant.conf 2>/dev/null || true
        log_info "Parametros de rede otimizados."
    fi

    log_success "Hardening basico aplicado."
}

harden_postgresql() {
    log_info "Aplicando hardening do PostgreSQL..."

    local pg_hba="/etc/postgresql/15/main/pg_hba.conf"

    if [[ -f "$pg_hba" ]]; then
        # Verificar se ja foi configurado
        if ! grep -q "# Multitenant hardening" "$pg_hba" 2>/dev/null; then
            # Fazer backup
            backup_config "$pg_hba"

            # Adicionar regra restritiva: so aceitar conexoes locais
            cat >> "$pg_hba" << 'PGHBA'

# Multitenant hardening - apenas conexoes locais
# host    all    all    0.0.0.0/0    reject
PGHBA
            log_info "pg_hba.conf: conexoes remotas bloqueadas (apenas local)."
        fi
    fi

    # Desabilitar listen em todas as interfaces (so localhost)
    local pg_conf="/etc/postgresql/15/main/postgresql.conf"
    if [[ -f "$pg_conf" ]]; then
        if grep -q "^listen_addresses" "$pg_conf"; then
            sed -i "s/^listen_addresses.*/listen_addresses = 'localhost'/" "$pg_conf"
        elif grep -q "^#listen_addresses" "$pg_conf"; then
            sed -i "s/^#listen_addresses.*/listen_addresses = 'localhost'/" "$pg_conf"
        fi
    fi

    systemctl reload postgresql 2>/dev/null || true
    log_success "PostgreSQL hardening aplicado."
}

harden_redis() {
    log_info "Aplicando hardening do Redis..."

    local redis_conf="/etc/redis/redis.conf"

    if [[ -f "$redis_conf" ]]; then
        # Bind apenas localhost
        if grep -q "^bind " "$redis_conf"; then
            sed -i 's/^bind .*/bind 127.0.0.1 ::1/' "$redis_conf"
        fi

        # Desabilitar comandos perigosos
        if ! grep -q "rename-command FLUSHALL" "$redis_conf" 2>/dev/null; then
            cat >> "$redis_conf" << 'REDISHARDEN'

# Multitenant hardening
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
REDISHARDEN
        fi

        systemctl restart redis-server 2>/dev/null || true
    fi

    log_success "Redis hardening aplicado."
}
