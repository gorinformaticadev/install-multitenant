#!/usr/bin/env bash
# =============================================================================
# Utilitários de Atualização - Instalador Multitenant
# =============================================================================

run_update_docker() {
    local build_mode="$1" # "local" or "registry"
    local branch="${2:-}"
    local installer_root="${INSTALLER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    
    log_info "Iniciando atualização Docker (Modo: $build_mode)..."
    
    # 1. Atualizar código via Git
    update_git_code "$branch"
    
    # 2. Determinar arquivos de composição
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
    
    log_info "Usando arquivo de composição: $compose_file"
    
    # 3. Executar atualização baseada no modo
    if [[ "$build_mode" == "registry" ]]; then
        log_info "Fazendo pull de imagens atualizadas..."
        docker compose -f "$PROJECT_ROOT/$compose_file" --env-file "$env_file" pull || log_warn "Falha ao baixar imagens. Tentando com as locais."
        
        log_info "Reiniciando containers..."
        docker compose -f "$PROJECT_ROOT/$compose_file" --env-file "$env_file" up -d --remove-orphans
    else
        log_info "Reconstruindo imagens localmente..."
        docker compose -f "$PROJECT_ROOT/$compose_file" --env-file "$env_file" up -d --build --remove-orphans
    fi
    
    # 4. Verificar saúde
    wait_for_backend_healthy
    
    log_success "Atualização Docker concluída!"
}

run_update_native() {
    local branch="${1:-}"
    
    log_info "Iniciando atualização Nativa..."
    
    # 1. Atualizar código via Git
    update_git_code "$branch"
    
    # Garantir permissões
    if id "multitenant" &>/dev/null; then
        chown -R multitenant:multitenant "$PROJECT_ROOT"
        local exec_user="sudo -u multitenant"
    else
        local exec_user=""
    fi
    
    # 2. Instalar dependências e rodar migrations
    log_info "Atualizando dependências do backend..."
    cd "$PROJECT_ROOT/apps/backend"
    $exec_user pnpm install --frozen-lockfile || $exec_user pnpm install
    $exec_user pnpm exec prisma generate
    $exec_user pnpm exec prisma migrate deploy
    
    log_info "Atualizando dependências do frontend..."
    cd "$PROJECT_ROOT/apps/frontend"
    $exec_user pnpm install --frozen-lockfile || $exec_user pnpm install
    $exec_user pnpm run build
    
    # 3. Reiniciar serviços
    log_info "Reiniciando serviços do sistema..."
    systemctl restart multitenant-backend || log_warn "Falha ao reiniciar backend. Certifique-se de que o serviço existe."
    systemctl restart multitenant-frontend || log_warn "Falha ao reiniciar frontend. Certifique-se de que o serviço existe."
    systemctl restart nginx
    
    log_success "Atualização Nativa concluída!"
}

update_git_code() {
    local branch="$1"
    
    cd "$PROJECT_ROOT"
    
    if [[ ! -d ".git" ]]; then
        log_error "Diretório atual não é um repositório Git."
        return 1
    fi
    
    log_info "Buscando atualizações do repositório..."
    git fetch --all --prune
    
    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD)
    fi
    
    log_info "Fazendo checkout da branch: $branch"
    
    # Salvar alterações locais se houver
    if ! git diff-index --quiet HEAD --; then
        log_warn "Salvando alterações locais com git stash..."
        git stash push -m "Auto-backup antes de atualização $(date +'%Y-%m-%d %H:%M:%S')"
    fi
    
    git checkout "$branch"
    git pull origin "$branch"
}

wait_for_backend_healthy() {
    log_info "Aguardando backend ficar saudável (até 2 minutos)..."
    
    local container_name="multitenant-backend"
    # Tenta encontrar o nome real do container caso tenha prefixo
    local real_name=$(docker ps --format '{{.Names}}' | grep "backend" | head -n 1)
    [[ -n "$real_name" ]] && container_name="$real_name"
    
    for i in $(seq 1 12); do
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "not_found")
        log_info "Status: $health (${i}/12)"
        
        if [[ "$health" == "healthy" ]]; then
            log_success "Backend saudável!"
            return 0
        fi
        
        if [[ "$health" == "unhealthy" ]]; then
            log_error "Backend está unhealthy! Verificando logs..."
            docker logs --tail 50 "$container_name"
            return 1
        fi
        
        sleep 10
    done
    
    log_warn "Timeout aguardando backend ficar saudável."
}
