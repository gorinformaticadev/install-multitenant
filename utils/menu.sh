#!/usr/bin/env bash
# =============================================================================
# Sistema de Menu Interativo - Instalador Multitenant
# =============================================================================

# Não carregar common.sh aqui - já foi carregado pelo install.sh
# As funções de common.sh já estão disponíveis

# Variáveis globais do menu
SELECTED_ENVIRONMENT=""
SELECTED_METHOD=""
SELECTED_BUILD_MODE=""
INSTALLATION_MODE=""

# --- Função para exibir menu de ambiente ---
show_environment_menu() {
    print_header "AMBIENTE DE INSTALAÇÃO"
    
    echo "Onde voce deseja instalar o sistema?"
    echo ""
    echo "  1) [LOCAL-DEV] Local (Desenvolvimento)"
    echo "     -> Para desenvolvedores trabalhando no codigo"
    echo ""
    echo "  2) [LOCAL-PROD] Local (Producao - Simulacao)"
    echo "     -> Testar build de producao localmente"
    echo ""
    echo "  3) [VPS-DEV] VPS/Servidor (Desenvolvimento)"
    echo "     -> Ambiente de staging/testes em servidor"
    echo ""
    echo "  4) [VPS-PROD] VPS/Servidor (Producao)"
    echo "     -> Ambiente de producao real"
    echo ""
    
    while true; do
        read -p "Escolha [1-4]: " choice
        case $choice in
            1)
                SELECTED_ENVIRONMENT="local-dev"
                log_success "Selecionado: Local (Desenvolvimento)"
                return 0
                ;;
            2)
                SELECTED_ENVIRONMENT="local-prod"
                log_success "Selecionado: Local (Produção)"
                return 0
                ;;
            3)
                SELECTED_ENVIRONMENT="vps-dev"
                log_success "Selecionado: VPS (Desenvolvimento)"
                return 0
                ;;
            4)
                SELECTED_ENVIRONMENT="vps-prod"
                log_success "Selecionado: VPS (Produção)"
                return 0
                ;;
            *)
                log_error "Opção inválida. Escolha entre 1 e 4."
                ;;
        esac
    done
}

# --- Função para exibir menu de método ---
show_method_menu() {
    print_header "MÉTODO DE INSTALAÇÃO"
    
    echo "Como voce deseja instalar?"
    echo ""
    echo "  1) [DOCKER] Com Docker (Recomendado)"
    echo "     -> Containerizado, facil de gerenciar"
    echo ""
    echo "  2) [NATIVO] Nativo (Node.js + PostgreSQL no sistema)"
    echo "     -> Instalacao direta no sistema operacional"
    echo ""
    
    while true; do
        read -p "Escolha [1-2]: " choice
        case $choice in
            1)
                SELECTED_METHOD="docker"
                log_success "Selecionado: Docker"
                return 0
                ;;
            2)
                SELECTED_METHOD="native"
                log_success "Selecionado: Nativo"
                return 0
                ;;
            *)
                log_error "Opção inválida. Escolha entre 1 e 2."
                ;;
        esac
    done
}

# --- Função para exibir menu de build (apenas para Docker) ---
show_build_menu() {
    print_header "OPÇÕES DE BUILD"
    
    echo "De onde vem a imagem Docker?"
    echo ""
    echo "  1) [REGISTRY] Usar imagem do registry (ghcr.io)"
    echo "     -> Download de imagem pre-construida"
    echo ""
    echo "  2) [LOCAL] Build local no servidor"
    echo "     -> Compilar codigo no proprio servidor"
    echo ""
    
    while true; do
        read -p "Escolha [1-2]: " choice
        case $choice in
            1)
                SELECTED_BUILD_MODE="registry"
                log_success "Selecionado: Imagem do Registry"
                return 0
                ;;
            2)
                SELECTED_BUILD_MODE="local"
                log_success "Selecionado: Build Local"
                return 0
                ;;
            *)
                log_error "Opção inválida. Escolha entre 1 e 2."
                ;;
        esac
    done
}

# --- Função para determinar o modo de instalação ---
determine_installation_mode() {
    if [[ "$SELECTED_METHOD" == "docker" ]]; then
        INSTALLATION_MODE="${SELECTED_ENVIRONMENT}-docker"
    else
        INSTALLATION_MODE="${SELECTED_ENVIRONMENT}-native"
    fi
    
    if [[ "$SELECTED_METHOD" == "docker" && "$SELECTED_BUILD_MODE" == "local" ]]; then
        INSTALLATION_MODE="${INSTALLATION_MODE}-local-build"
    fi
    
    export INSTALLATION_MODE
}

# --- Função para exibir confirmação ---
show_confirmation() {
    local domain="$1"
    local email="$2"
    
    print_header "CONFIRMAÇÃO"
    
    local mode_description=""
    case "$INSTALLATION_MODE" in
        local-dev-docker*)
            mode_description="Local Desenvolvimento com Docker"
            ;;
        local-prod-docker*)
            mode_description="Local Produção com Docker"
            ;;
        vps-dev-docker*local-build)
            mode_description="VPS Desenvolvimento com Docker (Build Local)"
            ;;
        vps-dev-docker*)
            mode_description="VPS Desenvolvimento com Docker (Registry)"
            ;;
        vps-prod-docker*local-build)
            mode_description="VPS Produção com Docker (Build Local)"
            ;;
        vps-prod-docker*)
            mode_description="VPS Produção com Docker (Registry)"
            ;;
        *-native)
            mode_description="${SELECTED_ENVIRONMENT} Nativo (sem Docker)"
            ;;
    esac
    
    echo -e "\033[1;36mModo selecionado:\033[0m $mode_description"
    echo -e "\033[1;36mDomínio:\033[0m $domain"
    echo -e "\033[1;36mEmail:\033[0m $email"
    echo ""
    
    if confirm_action "Confirma instalação?" "y"; then
        return 0
    else
        log_warn "Instalação cancelada pelo usuário."
        exit 0
    fi
}

# --- Menu de Atualização ---
show_update_menu() {
    print_header "MENU DE ATUALIZAÇÃO"
    
    local method=""
    if command -v docker &>/dev/null && docker ps -a | grep -i "multitenant" > /dev/null; then
        method="docker"
        log_info "Detectado: Instalação Docker"
    elif [[ -f "/etc/systemd/system/multitenant-backend.service" ]]; then
        method="native"
        log_info "Detectado: Instalação Nativa"
    else
        echo "Como o sistema está instalado?"
        echo "  1) Docker"
        echo "  2) Nativo (sem Docker)"
        read -p "Escolha [1-2]: " method_choice
        [[ "$method_choice" == "1" ]] && method="docker" || method="native"
    fi
    
    local branch=""
    echo ""
    read -p "Digite a branch para atualizar (Enter para atual): " branch
    
    if [[ "$method" == "docker" ]]; then
        echo ""
        echo "Como deseja atualizar o Docker?"
        echo "  1) [REGISTRY] Usar imagens prontas (Download)"
        echo "  2) [LOCAL] Reconstruir imagens localmente (Build)"
        read -p "Escolha [1-2]: " build_choice
        
        if [[ "$build_choice" == "1" ]]; then
            run_update_docker "registry" "$branch"
        else
            run_update_docker "local" "$branch"
        fi
    else
        run_update_native "$branch"
    fi
}

# --- Menu de Desinstalação ---
show_uninstall_menu() {
    print_header "MENU DE DESINSTALAÇÃO"
    
    echo -e "\033[1;31m⚠️  AVISO: Esta ação é irreversível!\033[0m"
    echo ""
    echo "Escolha o tipo de desinstalação:"
    echo "  1) Apenas a Aplicação (Remove containers/serviços e arquivos)"
    echo "  2) Limpeza Total (Remove Aplicação + Docker/Nginx/Certificados)"
    echo "  q) Sair"
    read -p "Escolha [1, 2 ou q]: " choice
    
    case "$choice" in
        1)
            if command -v docker &>/dev/null && docker ps -a | grep -i "multitenant" > /dev/null; then
                run_uninstall_docker "false"
            else
                run_uninstall_native "false"
            fi
            ;;
        2)
            if command -v docker &>/dev/null && docker ps -a | grep -i "multitenant" > /dev/null; then
                run_uninstall_docker "true"
            else
                run_uninstall_native "true"
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# --- Função principal do menu ---
show_installation_menu() {
    local domain="$1"
    local email="$2"
    
    print_header "INSTALADOR MULTITENANT - Seleção de Modo"
    
    echo -e "\033[1;36mDomínio:\033[0m $domain"
    echo -e "\033[1;36mEmail:\033[0m $email"
    echo ""
    
    show_environment_menu
    print_separator
    
    show_method_menu
    print_separator
    
    if [[ "$SELECTED_METHOD" == "docker" ]] && [[ "$SELECTED_ENVIRONMENT" != "local-dev" ]]; then
        show_build_menu
        print_separator
    elif [[ "$SELECTED_METHOD" == "docker" ]] && [[ "$SELECTED_ENVIRONMENT" == "local-dev" ]]; then
        SELECTED_BUILD_MODE="local"
    fi
    
    determine_installation_mode
    show_confirmation "$domain" "$email"
}
