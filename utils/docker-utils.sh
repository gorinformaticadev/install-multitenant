#!/usr/bin/env bash
# =============================================================================
# Utilitarios Docker - Instalador Multitenant
# =============================================================================
# Nao carregar common.sh aqui - ja foi carregado pelo install.sh

# --- Verificar e instalar Docker ---
check_docker() {
    if systemctl is-active --quiet docker 2>/dev/null; then
        log_info "Docker já está instalado e rodando."
        log_info "Docker: $(docker --version 2>/dev/null || echo 'instalado')"
        return 0
    fi
    
    if ! command -v docker &>/dev/null; then
        if systemctl list-unit-files | grep -q docker.service; then
            log_info "Docker instalado. Iniciando serviço..."
            systemctl start docker
            systemctl enable docker
            log_info "Docker: $(docker --version)"
            return 0
        fi
        
        log_warn "Docker não encontrado. Instalando Docker..."
        install_docker
    else
        log_info "Docker: $(docker --version)"
    fi
}

install_docker() {
    log_info "Instalando Docker..."
    
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker instalado: $(docker --version)"
}

check_docker_compose() {
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose (plugin) não encontrado."
        log_error "Tente reinstalar o Docker manualmente."
        exit 1
    fi
    log_info "Docker Compose: $(docker compose version --short)"
}
