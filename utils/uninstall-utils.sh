#!/usr/bin/env bash
# =============================================================================
# Utilitarios de Desinstalacao - Instalador Multitenant
# =============================================================================

run_uninstall_docker() {
    local total_purge="${1:-false}"
    local installer_root="${INSTALLER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

    print_header "DESINSTALACAO DOCKER"

    if [[ "$total_purge" == "true" ]]; then
        log_warn "Acao critica: Limpeza total do VPS selecionada."
    fi

    if ! confirm_action "Isso removera os containers e volumes da aplicacao. Continuar?" "n"; then
        log_info "Cancelado."
        return 0
    fi

    # 1. Parar a aplicacao
    local compose_file="docker-compose.prod.yml"
    local env_file="$installer_root/.env.production"

    if [[ ! -f "$PROJECT_ROOT/$compose_file" ]]; then
        compose_file="docker-compose.yml"
    fi

    if [[ ! -f "$env_file" ]] && [[ -f "$PROJECT_ROOT/.env.production" ]]; then
        env_file="$PROJECT_ROOT/.env.production"
    elif [[ ! -f "$env_file" ]] && [[ -f "$PROJECT_ROOT/.env" ]]; then
        env_file="$PROJECT_ROOT/.env"
    fi

    if [[ -f "$PROJECT_ROOT/$compose_file" ]]; then
        log_info "Removendo containers e volumes..."
        docker compose -f "$PROJECT_ROOT/$compose_file" --env-file "$env_file" down -v --remove-orphans
    fi

    # 2. Remover imagens do projeto
    log_info "Limpando imagens Docker do projeto..."
    docker images --format "{{.Repository}} {{.ID}}" | grep "multitenant" | awk '{print $2}' | xargs -r docker rmi -f || true

    # 3. Limpeza total se solicitado
    if [[ "$total_purge" == "true" ]]; then
        # Reverter regras de firewall abertas pelo instalador (80/443)
        if [[ -f /var/lib/multitenant/firewall_ports_80_443_opened ]] && command -v ufw &>/dev/null; then
            log_info "Revertendo regras de firewall (portas 80 e 443)..."
            ufw delete allow 80/tcp >/dev/null 2>&1 || true
            ufw delete allow 443/tcp >/dev/null 2>&1 || true
            rm -f /var/lib/multitenant/firewall_ports_80_443_opened 2>/dev/null || true
        fi

        # Remover Docker apenas se instalado pelo instalador
        if [[ -f /var/lib/multitenant/installed_docker ]]; then
            log_info "Removendo Docker e dependencias instaladas pelo instalador..."
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            rm -rf /var/lib/docker
        else
            log_info "Docker nao foi instalado pelo instalador. Mantendo pacote Docker."
        fi

        # Remover Nginx de sistema apenas se instalado pelo instalador
        if [[ -f /var/lib/multitenant/installed_nginx ]]; then
            log_info "Removendo Nginx instalado pelo instalador..."
            apt-get purge -y nginx nginx-common
            rm -rf /etc/nginx
        fi

        log_info "Removendo certificados gerenciados pelo instalador..."
        rm -rf /etc/letsencrypt
        rm -rf /etc/ssl/multitenant
    fi

    # 4. Remover arquivos do projeto
    if [[ "$PROJECT_ROOT" == "$installer_root" ]]; then
        log_error "PROJECT_ROOT aponta para o instalador. Abortando remocao por seguranca."
    else
        log_info "Removendo diretorio do projeto..."
        (sleep 2 && rm -rf "$PROJECT_ROOT") &
    fi

    # 5. Remover usuario de sistema do aplicativo
    if id "multitenant" &>/dev/null; then
        log_info "Removendo usuario de sistema 'multitenant'..."
        userdel -r multitenant 2>/dev/null || userdel multitenant 2>/dev/null || true
    fi
    rm -rf /var/log/multitenant /var/lib/multitenant /home/multitenant 2>/dev/null || true

    log_success "Desinstalacao concluida!"
    exit 0
}

run_uninstall_native() {
    local total_purge="${1:-false}"
    local installer_root="${INSTALLER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

    print_header "DESINSTALACAO NATIVA"

    if ! confirm_action "Isso removera os servicos e arquivos da aplicacao. Continuar?" "n"; then
        log_info "Cancelado."
        return 0
    fi

    # 1. Parar e remover servicos systemd
    log_info "Removendo servicos do sistema..."
    systemctl stop multitenant-backend || true
    systemctl disable multitenant-backend || true
    rm -f /etc/systemd/system/multitenant-backend.service
    systemctl stop multitenant-frontend || true
    systemctl disable multitenant-frontend || true
    rm -f /etc/systemd/system/multitenant-frontend.service
    systemctl daemon-reload

    # 2. Remover configuracao do Nginx
    log_info "Removendo configuracao do Nginx..."
    rm -f /etc/nginx/sites-enabled/multitenant
    rm -f /etc/nginx/sites-available/multitenant
    systemctl restart nginx || true

    # 3. Limpeza total se solicitado
    if [[ "$total_purge" == "true" ]]; then
        # Reverter regras de firewall abertas pelo instalador (80/443)
        if [[ -f /var/lib/multitenant/firewall_ports_80_443_opened ]] && command -v ufw &>/dev/null; then
            log_info "Revertendo regras de firewall (portas 80 e 443)..."
            ufw delete allow 80/tcp >/dev/null 2>&1 || true
            ufw delete allow 443/tcp >/dev/null 2>&1 || true
            rm -f /var/lib/multitenant/firewall_ports_80_443_opened 2>/dev/null || true
        fi

        log_info "Removendo dependencias instaladas pelo instalador..."

        # PostgreSQL
        if [[ -f /var/lib/multitenant/installed_postgresql ]]; then
            if confirm_action "Remover PostgreSQL instalado pelo instalador (CUIDADO: remove dados)? " "n"; then
                apt-get purge -y postgresql-15 postgresql-contrib-15 postgresql* || true
                rm -rf /var/lib/postgresql
            fi
        else
            log_info "PostgreSQL nao foi marcado como instalado pelo instalador. Mantendo pacote."
        fi

        # Redis
        if [[ -f /var/lib/multitenant/installed_redis ]]; then
            apt-get purge -y redis-server || true
            rm -rf /var/lib/redis
        fi

        # Node.js
        if [[ -f /var/lib/multitenant/installed_nodejs ]]; then
            apt-get purge -y nodejs || true
        fi

        # pnpm
        if [[ -f /var/lib/multitenant/installed_pnpm ]]; then
            npm uninstall -g pnpm || true
        fi

        # PM2
        if [[ -f /var/lib/multitenant/installed_pm2 ]]; then
            npm uninstall -g pm2 || true
            if id "multitenant" &>/dev/null; then
                sudo -u multitenant sh -lc 'npm uninstall -g pm2' 2>/dev/null || true
            fi
        fi

        # Certbot
        if [[ -f /var/lib/multitenant/installed_certbot ]]; then
            apt-get purge -y certbot python3-certbot-nginx || true
        fi

        # fail2ban
        if [[ -f /var/lib/multitenant/installed_fail2ban ]]; then
            apt-get purge -y fail2ban || true
        fi

        rm -rf /etc/letsencrypt
        rm -rf /etc/ssl/multitenant
    fi

    # 4. Remover arquivos do projeto
    if [[ "$PROJECT_ROOT" == "$installer_root" ]]; then
        log_error "PROJECT_ROOT aponta para o instalador. Abortando remocao por seguranca."
    else
        log_info "Removendo diretorio do projeto..."
        (sleep 2 && rm -rf "$PROJECT_ROOT") &
    fi

    # 5. Remover usuario de sistema do aplicativo
    if id "multitenant" &>/dev/null; then
        log_info "Removendo usuario de sistema 'multitenant'..."
        userdel -r multitenant 2>/dev/null || userdel multitenant 2>/dev/null || true
    fi
    rm -rf /var/log/multitenant /var/lib/multitenant /home/multitenant 2>/dev/null || true

    log_success "Desinstalacao concluida!"
    exit 0
}
