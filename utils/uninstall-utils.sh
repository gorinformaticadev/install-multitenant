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
        log_info "Removendo Docker e dependencias..."
        apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        rm -rf /var/lib/docker

        log_info "Removendo Nginx..."
        apt-get purge -y nginx nginx-common
        rm -rf /etc/nginx

        log_info "Removendo certificados..."
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
        log_info "Removendo Node.js, pnpm e PostgreSQL..."
        if confirm_action "Deseja remover o PostgreSQL (CUIDADO!)?" "n"; then
            apt-get purge -y postgresql*
            rm -rf /var/lib/postgresql
        fi
        apt-get purge -y nodejs
        npm uninstall -g pnpm || true
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

    log_success "Desinstalacao concluida!"
    exit 0
}
