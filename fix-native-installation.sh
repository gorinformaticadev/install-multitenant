#!/usr/bin/env bash
# =============================================================================
# Script de Correção Automática - Instalação Nativa
# =============================================================================
# Este script corrige os problemas identificados na instalação nativa:
# 1. Node.js não acessível pelo usuário multitenant
# 2. Duplicação da função cleanup_on_error em common.sh
# 3. Carregamento duplo do common.sh em menu.sh
# 4. Modo strict muito restritivo em install.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  CORREÇÃO AUTOMÁTICA - INSTALADOR v2.0"
echo "=========================================="
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# =============================================================================
# Correção 1: Remover duplicação em common.sh
# =============================================================================

fix_common_sh() {
    log_info "Correção 1: Removendo duplicação em common.sh..."
    
    local file="$SCRIPT_DIR/utils/common.sh"
    
    if [[ ! -f "$file" ]]; then
        log_error "Arquivo não encontrado: $file"
        return 1
    fi
    
    # Backup
    cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remover últimas 6 linhas (duplicação da função cleanup_on_error)
    head -n -6 "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    
    log_success "common.sh corrigido (duplicação removida)"
}

# =============================================================================
# Correção 2: Corrigir menu.sh (remover carregamento duplo)
# =============================================================================

fix_menu_sh() {
    log_info "Correção 2: Corrigindo menu.sh..."
    
    local file="$SCRIPT_DIR/utils/menu.sh"
    
    if [[ ! -f "$file" ]]; then
        log_error "Arquivo não encontrado: $file"
        return 1
    fi
    
    # Backup
    cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remover as linhas que carregam common.sh
    sed -i '/^SCRIPT_DIR=.*dirname.*BASH_SOURCE/d' "$file"
    sed -i '/^source.*common\.sh/d' "$file"
    
    # Adicionar comentário no início
    sed -i '4i\# Não carregar common.sh aqui - já foi carregado pelo install.sh' "$file"
    sed -i '5i\# As funções de common.sh já estão disponíveis\n' "$file"
    
    log_success "menu.sh corrigido (carregamento duplo removido)"
}

# =============================================================================
# Correção 3: Suavizar modo strict em install.sh
# =============================================================================

fix_install_sh() {
    log_info "Correção 3: Suavizando modo strict em install.sh..."
    
    local file="$SCRIPT_DIR/install.sh"
    
    if [[ ! -f "$file" ]]; then
        log_error "Arquivo não encontrado: $file"
        return 1
    fi
    
    # Backup
    cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Substituir set -Eeuo pipefail por set -Eeo pipefail (remover -u)
    sed -i 's/set -Eeuo pipefail/set -Eeo pipefail/' "$file"
    
    log_success "install.sh corrigido (modo strict suavizado)"
}

# =============================================================================
# Correção 4: Corrigir prepare_multitenant_environment em native-utils.sh
# =============================================================================

fix_native_utils_sh() {
    log_info "Correção 4: Corrigindo prepare_multitenant_environment..."
    
    local file="$SCRIPT_DIR/utils/native-utils.sh"
    
    if [[ ! -f "$file" ]]; then
        log_error "Arquivo não encontrado: $file"
        return 1
    fi
    
    # Backup
    cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Criar a nova função corrigida
    cat > /tmp/prepare_multitenant_fixed.txt << 'NEWFUNC'
prepare_multitenant_environment() {
    log_info "Preparando ambiente do usuário multitenant..."
    
    # Garantir que os diretórios de configuração existam
    sudo -u multitenant mkdir -p ~/.npm ~/.pnpm-store ~/.config ~/.local/bin 2>/dev/null || true
    
    # Criar links simbólicos para Node.js, npm e npx
    log_info "Criando links simbólicos para Node.js..."
    sudo -u multitenant ln -sf /usr/bin/node /home/multitenant/.local/bin/node 2>/dev/null || true
    sudo -u multitenant ln -sf /usr/bin/npm /home/multitenant/.local/bin/npm 2>/dev/null || true
    sudo -u multitenant ln -sf /usr/bin/npx /home/multitenant/.local/bin/npx 2>/dev/null || true
    
    # Adicionar .local/bin ao PATH permanentemente
    if ! grep -q "export PATH.*\.local/bin" /home/multitenant/.bashrc 2>/dev/null; then
        sudo -u multitenant bash -c 'echo "export PATH=\"\$HOME/.local/bin:/usr/bin:\$PATH\"" >> ~/.bashrc'
    fi
    
    if ! grep -q "export PATH.*\.local/bin" /home/multitenant/.profile 2>/dev/null; then
        sudo -u multitenant bash -c 'echo "export PATH=\"\$HOME/.local/bin:/usr/bin:\$PATH\"" >> ~/.profile'
    fi
    
    # Verificar se Node.js está acessível (usar bash -lc para carregar .bashrc)
    if ! sudo -u multitenant bash -lc 'command -v node' >/dev/null 2>&1; then
        log_error "Node.js não está disponível para o usuário multitenant"
        log_info "Tentando configuração alternativa..."
        
        # Tentar adicionar diretamente ao PATH do sistema
        if [[ -f /usr/bin/node ]]; then
            # Criar wrapper script
            cat > /home/multitenant/.local/bin/node << 'NODEWRAPPER'
#!/bin/bash
exec /usr/bin/node "$@"
NODEWRAPPER
            chmod +x /home/multitenant/.local/bin/node
            chown multitenant:multitenant /home/multitenant/.local/bin/node
        fi
        
        # Verificar novamente
        if ! sudo -u multitenant bash -lc 'command -v node' >/dev/null 2>&1; then
            log_error "Falha crítica: Node.js não pode ser acessado pelo usuário multitenant"
            log_info "Verifique manualmente: sudo -u multitenant bash -lc 'which node'"
            return 1
        fi
    fi
    
    # Verificar npm
    if ! sudo -u multitenant bash -lc 'command -v npm' >/dev/null 2>&1; then
        log_error "npm não está disponível para o usuário multitenant"
        
        # Criar wrapper para npm também
        if [[ -f /usr/bin/npm ]]; then
            cat > /home/multitenant/.local/bin/npm << 'NPMWRAPPER'
#!/bin/bash
exec /usr/bin/npm "$@"
NPMWRAPPER
            chmod +x /home/multitenant/.local/bin/npm
            chown multitenant:multitenant /home/multitenant/.local/bin/npm
        fi
    fi
    
    # Instalar ou verificar pnpm
    if ! sudo -u multitenant bash -lc 'command -v pnpm' >/dev/null 2>&1; then
        log_info "Instalando pnpm para o usuário multitenant..."
        if ! sudo -u multitenant bash -lc 'npm install -g pnpm' 2>/dev/null; then
            log_warn "Falha ao instalar pnpm como usuário multitenant, tentando como root..."
            npm install -g pnpm
            
            # Criar link simbólico se necessário
            if [[ -f /usr/local/bin/pnpm ]]; then
                sudo -u multitenant ln -sf /usr/local/bin/pnpm /home/multitenant/.local/bin/pnpm 2>/dev/null || true
            elif [[ -f /usr/bin/pnpm ]]; then
                sudo -u multitenant ln -sf /usr/bin/pnpm /home/multitenant/.local/bin/pnpm 2>/dev/null || true
            fi
        fi
    fi
    
    log_success "Ambiente do usuário multitenant preparado."
    
    # Exibir informações de debug
    log_info "Verificando comandos disponíveis para o usuário multitenant:"
    if sudo -u multitenant bash -lc 'command -v node' >/dev/null 2>&1; then
        local node_ver=$(sudo -u multitenant bash -lc 'node --version' 2>/dev/null)
        log_success "Node.js: $node_ver"
    else
        log_warn "Node.js não encontrado"
    fi
    
    if sudo -u multitenant bash -lc 'command -v npm' >/dev/null 2>&1; then
        local npm_ver=$(sudo -u multitenant bash -lc 'npm --version' 2>/dev/null)
        log_success "npm: $npm_ver"
    else
        log_warn "npm não encontrado"
    fi
    
    if sudo -u multitenant bash -lc 'command -v pnpm' >/dev/null 2>&1; then
        local pnpm_ver=$(sudo -u multitenant bash -lc 'pnpm --version' 2>/dev/null)
        log_success "pnpm: $pnpm_ver"
    else
        log_warn "pnpm não encontrado"
    fi
}
NEWFUNC
    
    # Encontrar a linha onde começa a função prepare_multitenant_environment
    local line_start=$(grep -n "^prepare_multitenant_environment()" "$file" | cut -d: -f1)
    
    if [[ -z "$line_start" ]]; then
        log_error "Função prepare_multitenant_environment não encontrada"
        return 1
    fi
    
    # Encontrar a linha onde termina a função (próximo '}' no início da linha)
    local line_end=$(awk "NR>$line_start && /^}$/ {print NR; exit}" "$file")
    
    if [[ -z "$line_end" ]]; then
        log_error "Fim da função prepare_multitenant_environment não encontrado"
        return 1
    fi
    
    # Criar arquivo temporário com a correção
    head -n $((line_start - 1)) "$file" > "${file}.tmp"
    cat /tmp/prepare_multitenant_fixed.txt >> "${file}.tmp"
    tail -n +$((line_end + 1)) "$file" >> "${file}.tmp"
    
    # Substituir o arquivo original
    mv "${file}.tmp" "$file"
    chmod +x "$file"
    
    # Limpar arquivo temporário
    rm -f /tmp/prepare_multitenant_fixed.txt
    
    log_success "native-utils.sh corrigido (prepare_multitenant_environment atualizado)"
}

# =============================================================================
# Executar todas as correções
# =============================================================================

main() {
    echo ""
    log_info "Iniciando correções automáticas..."
    echo ""
    
    # Verificar se estamos no diretório correto
    if [[ ! -d "$SCRIPT_DIR/utils" ]] || [[ ! -d "$SCRIPT_DIR/modes" ]]; then
        log_error "Este script deve ser executado do diretório install-2/"
        log_error "Diretório atual: $SCRIPT_DIR"
        exit 1
    fi
    
    # Executar correções
    fix_common_sh
    echo ""
    
    fix_menu_sh
    echo ""
    
    fix_install_sh
    echo ""
    
    fix_native_utils_sh
    echo ""
    
    echo "=========================================="
    log_success "Todas as correções aplicadas com sucesso!"
    echo "=========================================="
    echo ""
    
    log_info "Backups criados com extensão .backup.YYYYMMDD_HHMMSS"
    log_info "Você pode testar a instalação agora:"
    echo ""
    echo "  sudo bash install-2/install.sh install -d seu-dominio.com -e seu-email@exemplo.com"
    echo ""
    
    log_info "Para testar se o usuário multitenant pode acessar Node.js:"
    echo ""
    echo "  sudo -u multitenant bash -lc 'node --version'"
    echo "  sudo -u multitenant bash -lc 'npm --version'"
    echo "  sudo -u multitenant bash -lc 'pnpm --version'"
    echo ""
}

main "$@"
