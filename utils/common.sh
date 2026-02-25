#!/usr/bin/env bash
# =============================================================================
# Funções Comuns - Instalador Multitenant
# =============================================================================

# --- Cores e formatação ---
echored()   { echo -ne "\033[41m\033[37m\033[1m  $1  \033[0m\n"; }
echoblue()  { echo -ne "\033[44m\033[37m\033[1m  $1  \033[0m\n"; }
echogreen() { echo -ne "\033[42m\033[37m\033[1m  $1  \033[0m\n"; }
echoyellow() { echo -ne "\033[43m\033[30m\033[1m  $1  \033[0m\n"; }
log_info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
log_success() { echo -e "\033[1;32m[✓]\033[0m $*"; }

# --- Validações ---
validate_email() {
    local email="$1"
    local re="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
    if ! [[ "$email" =~ $re ]]; then
        log_error "Email inválido: $email"
        return 1
    fi
    return 0
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Domínio inválido: $domain"
        return 1
    fi
    return 0
}

# --- Verificações de sistema ---
require_bash() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        echored "Este script deve ser executado com Bash."
        exit 1
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echored "Este script deve ser executado como root (sudo)."
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_info "Sistema operacional: $OS $OS_VERSION"
        
        if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
            log_warn "Sistema não testado oficialmente: $OS"
            log_warn "Recomendamos Ubuntu 22.04 LTS ou Debian 11+"
        fi
    else
        log_error "Não foi possível detectar o sistema operacional."
        exit 1
    fi
}

# --- Repositorio da aplicacao ---
ensure_project_repository() {
    local repo_url="${APP_REPO_URL:-https://github.com/gorinformaticadev/Projeto-menu-multitenant-seguro.git}"
    local target_dir="${PROJECT_ROOT:-}"

    if [[ -z "$target_dir" ]]; then
        log_error "PROJECT_ROOT nao definido para clonar/atualizar a aplicacao."
        return 1
    fi

    if ! command -v git &>/dev/null; then
        log_info "Git nao encontrado. Instalando..."
        apt-get update -qq
        apt-get install -y -qq git
    fi

    if [[ -d "$target_dir/.git" ]]; then
        log_info "Repositorio da aplicacao ja existe em: $target_dir"
        git config --global --add safe.directory "$target_dir" 2>/dev/null || true
        return 0
    fi

    if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
        log_error "Diretorio de destino ja existe e nao eh repositorio Git: $target_dir"
        log_error "Defina INSTALL_PROJECT_DIR para outro caminho ou limpe o diretorio."
        return 1
    fi

    mkdir -p "$(dirname "$target_dir")"
    log_info "Clonando aplicacao em: $target_dir"
    git clone "$repo_url" "$target_dir"
    git config --global --add safe.directory "$target_dir" 2>/dev/null || true
    log_success "Repositorio clonado com sucesso."
}

# --- Gerenciamento de arquivos .env ---
ensure_env_file() {
    local env_file="$1"
    local env_example="$2"
    
    if [[ ! -f "$env_file" ]]; then
        if [[ -f "$env_example" ]]; then
            cp "$env_example" "$env_file"
            log_success "Arquivo criado: $env_file"
        else
            log_error "Arquivo de exemplo não encontrado: $env_example"
            return 1
        fi
    fi
    return 0
}

upsert_env() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    if [[ ! -f "$file" ]]; then
        touch "$file"
    fi
    
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        local tmpfile
        tmpfile="$(mktemp)"
        while IFS= read -r line; do
            if [[ "$line" == "${key}="* ]]; then
                echo "${key}=${value}"
            else
                echo "$line"
            fi
        done < "$file" > "$tmpfile"
        mv "$tmpfile" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# --- Geração de secrets ---
generate_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

generate_db_credentials() {
    local domain_prefix="$1"
    
    domain_prefix=$(echo "$domain_prefix" | sed 's/\..*//')
    if [[ "$domain_prefix" == *"."* ]]; then
        domain_prefix=$(echo "$domain_prefix" | cut -d'.' -f1,2 | tr -d '.')
    fi
    domain_prefix=$(echo "$domain_prefix" | tr -cd '[:alnum:]' | cut -c1-16 | tr '[:upper:]' '[:lower:]')
    
    DB_NAME="${DB_NAME:-db_${domain_prefix}}"
    DB_USER="${DB_USER:-us_${domain_prefix}}"
    DB_PASSWORD="${DB_PASSWORD:-$(generate_secret 16)}"
    JWT_SECRET="${JWT_SECRET:-$(generate_secret 32)}"
    ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(generate_secret 32)}"
    
    export DB_NAME DB_USER DB_PASSWORD JWT_SECRET ENCRYPTION_KEY
}

# --- Confirmação do usuário ---
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        read -p "$message [S/n]: " response
        response=${response:-S}
    else
        read -p "$message [s/N]: " response
        response=${response:-N}
    fi
    
    case "$response" in
        [Ss]|[Yy]|[Ss][Ii][Mm]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# --- Exibição de informações ---
print_separator() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echoblue "══════════════════════════════════════════════════════════════"
    echoblue "  $title"
    echoblue "══════════════════════════════════════════════════════════════"
    echo ""
}

# --- Detecção de ambiente ---
detect_environment() {
    local is_local="false"
    local hostname=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    
    if [[ "$hostname" =~ ^127\. ]] || [[ "$hostname" =~ ^192\.168\. ]] || [[ "$hostname" =~ ^10\. ]] || [[ "$hostname" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        is_local="true"
    fi
    
    if command -v docker &>/dev/null; then
        if docker info 2>/dev/null | grep -q "Operating System.*Docker Desktop"; then
            is_local="true"
        fi
    fi
    
    echo "$is_local"
}

# --- Backup de configuração ---
backup_config() {
    local config_file="$1"
    
    if [[ -f "$config_file" ]]; then
        local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup_file"
        log_info "Backup criado: $backup_file"
    fi
}

# --- Limpeza e tratamento de erros ---
cleanup_on_error() {
    log_error "Instalação interrompida devido a um erro."
    log_error "Verifique as mensagens acima para mais detalhes."
    exit 1
}
