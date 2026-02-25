#!/usr/bin/env bash
# =============================================================================
# Modo: Docker VPS Producao
# Usa funcoes internas de utils/docker-install.sh (NAO delega para install/)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALLER_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALL_DIR")/Projeto-menu-multitenant-seguro}"

# common.sh e docker-utils.sh ja foram carregados pelo install.sh
# Carregar funcoes de instalacao Docker
source "$INSTALL_DIR/utils/docker-install.sh"

run_docker_vps_prod() {
    local domain="$1"
    local email="$2"
    local build_mode="$3"  # "local" ou "registry"
    
    print_header "INSTALACAO: VPS Producao com Docker"
    
    log_info "Ambiente: VPS/Servidor (Producao)"
    log_info "Branch recomendada: main"
    log_info "Build: ${build_mode}"
    
    # Verificar Docker
    check_docker
    check_docker_compose
    check_and_open_ports
    
    # Verificar branch
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        # Lidar com o problema de segurança do Git sobre propriedade duvidosa
        git config --global --add safe.directory "$PROJECT_ROOT" 2>/dev/null || true
        local current_branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null)
        if [[ -n "$current_branch" ]] && [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
            log_warn "Branch atual: $current_branch"
            log_warn "Recomendado: main ou master"
            if ! confirm_action "Deseja continuar mesmo assim?" "n"; then
                log_error "Instalacao cancelada. Mude para branch main primeiro."
                exit 1
            fi
        fi
    fi
    
    # Executar instalacao Docker usando funcoes internas
    log_info "Iniciando instalacao Docker VPS (Producao)..."
    run_docker_vps_install "$domain" "$email" "$build_mode"
}
