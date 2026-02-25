#!/usr/bin/env bash
# =============================================================================
# Instalador Multitenant - Versão 2.0 com Menu Interativo
# =============================================================================

set -Eeo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_ROOT="${INSTALLER_ROOT:-$SCRIPT_DIR}"
PROJECT_ROOT="${PROJECT_ROOT:-${INSTALL_PROJECT_DIR:-$(dirname "$INSTALLER_ROOT")/Projeto-menu-multitenant-seguro}}"
APP_REPO_URL="${APP_REPO_URL:-https://github.com/gorinformaticadev/Projeto-menu-multitenant-seguro.git}"
export INSTALLER_ROOT PROJECT_ROOT APP_REPO_URL

# Carregar utilitarios
source "$SCRIPT_DIR/utils/common.sh"
source "$SCRIPT_DIR/utils/docker-utils.sh"
source "$SCRIPT_DIR/utils/menu.sh"
source "$SCRIPT_DIR/utils/update-utils.sh"
source "$SCRIPT_DIR/utils/uninstall-utils.sh"

# Trap de erro
trap cleanup_on_error ERR

# --- Uso ---
show_usage() {
    cat <<'EOF'
Uso:
  sudo bash install/install.sh install [OPÇÕES]

Comandos:
  install   Instalação inicial com menu interativo
  update    Atualiza a aplicação existente
  uninstall Desinstala a aplicação do sistema

Opções:
  -d, --domain DOMAIN       Domínio (ex: app.exemplo.com.br)
  -e, --email EMAIL         Email para Let's Encrypt e admin
  -u, --user USER           Usuário/owner para imagens (GHCR)
  -n, --no-prompt           Modo não-interativo (requer variáveis de ambiente)

Variáveis de ambiente:
  INSTALL_DOMAIN, LETSENCRYPT_EMAIL, IMAGE_OWNER, INSTALL_PROJECT_DIR, APP_REPO_URL

Exemplos:
  sudo bash install/install.sh install -d dev.empresa.com -e admin@empresa.com -u gorinformatica
  sudo INSTALL_DOMAIN=app.empresa.com LETSENCRYPT_EMAIL=admin@empresa.com bash install/install.sh install --no-prompt
EOF
}

# --- Instalação ---
run_install() {
    local domain="${INSTALL_DOMAIN:-}"
    local email="${LETSENCRYPT_EMAIL:-}"
    local image_owner="${IMAGE_OWNER:-${GHCR_OWNER:-}}"
    local no_prompt="${INSTALL_NO_PROMPT:-false}"

    # Parse opções
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)   domain="$2"; shift 2 ;;
            -e|--email)    email="$2"; shift 2 ;;
            -u|--user)     image_owner="$2"; shift 2 ;;
            -n|--no-prompt) no_prompt="true"; shift ;;
            -h|--help)     show_usage; exit 0 ;;
            *) shift ;;
        esac
    done

    # Solicitar informações se não fornecidas
    if [[ "$no_prompt" != "true" ]]; then
        [[ -z "$domain" ]] && read -p "Domínio (ex: app.empresa.com): " domain
        [[ -z "$email" ]]  && read -p "Email (Let's Encrypt / admin): " email
    fi

    # Validar
    if [[ -z "$domain" || -z "$email" ]]; then
        log_error "Domínio e email são obrigatórios."
        show_usage
        exit 1
    fi

    validate_domain "$domain" || exit 1
    validate_email "$email" || exit 1

    if [[ -n "$image_owner" ]]; then
        IMAGE_OWNER="$image_owner"
        GHCR_OWNER="$image_owner"
        export IMAGE_OWNER GHCR_OWNER
    fi

    ensure_project_repository

    # Mostrar menu e obter modo selecionado
    show_installation_menu "$domain" "$email"
    local installation_mode="$INSTALLATION_MODE"

    log_info "Modo selecionado: $installation_mode"

    # Executar instalação baseado no modo
    case "$installation_mode" in
        local-dev-docker*)
            source "$SCRIPT_DIR/modes/docker-local-dev.sh"
            run_docker_local_dev "$domain" "$email"
            ;;
        local-prod-docker*)
            source "$SCRIPT_DIR/modes/docker-local-prod.sh"
            run_docker_local_prod "$domain" "$email"
            ;;
        vps-dev-docker*local-build)
            source "$SCRIPT_DIR/modes/docker-vps-dev.sh"
            run_docker_vps_dev "$domain" "$email" "local"
            ;;
        vps-dev-docker*)
            source "$SCRIPT_DIR/modes/docker-vps-dev.sh"
            run_docker_vps_dev "$domain" "$email" "registry"
            ;;
        vps-prod-docker*local-build)
            source "$SCRIPT_DIR/modes/docker-vps-prod.sh"
            run_docker_vps_prod "$domain" "$email" "local"
            ;;
        vps-prod-docker*)
            source "$SCRIPT_DIR/modes/docker-vps-prod.sh"
            run_docker_vps_prod "$domain" "$email" "registry"
            ;;
        vps-dev-native)
            source "$SCRIPT_DIR/utils/native-utils.sh"
            source "$SCRIPT_DIR/modes/native-vps-dev.sh"
            run_native_vps_dev "$domain" "$email"
            ;;
        vps-prod-native)
            source "$SCRIPT_DIR/utils/native-utils.sh"
            source "$SCRIPT_DIR/modes/native-vps-prod.sh"
            run_native_vps_prod "$domain" "$email"
            ;;
        *)
            log_error "Modo de instalação desconhecido: $installation_mode"
            exit 1
            ;;
    esac
}

# --- Atualização ---
run_update() {
    ensure_project_repository
    show_update_menu
}

# --- Desinstalação ---
run_uninstall() {
    show_uninstall_menu
}

# --- Menu Principal ---
show_main_menu() {
    print_header "INSTALADOR MULTITENANT v2.0"
    
    echo "Escolha o que deseja fazer:"
    echo "  1) Instalação Inicial"
    echo "  2) Atualizar Aplicação"
    echo "  3) Desinstalar Sistema"
    echo "  q) Sair"
    echo ""
    read -p "Opção: " main_opt
    
    case "$main_opt" in
        1) run_install ;;
        2) run_update  ;;
        3) run_uninstall ;;
        *) exit 0      ;;
    esac
}

# --- Main ---
main() {
    require_bash
    require_root

    print_header "INSTALADOR MULTITENANT v2.0"
    
    check_os

    local cmd="${1:-}"
    shift || true
    
    case "$cmd" in
        install)   run_install "$@" ;;
        update)    run_update "$@" ;;
        uninstall) run_uninstall "$@" ;;
        "")        show_main_menu ;;
        *)         show_usage; exit 1 ;;
    esac
}

main "$@"
