#!/usr/bin/env bash
# =============================================================================
# Utilitarios Instalacao Nativa - Instalador Multitenant v2.0
# =============================================================================
# Funcoes para instalar e configurar todos os componentes necessarios
# para rodar a aplicacao diretamente no sistema operacional (sem Docker).
#
# Componentes: Node.js 20, pnpm, PostgreSQL 15, Redis 7, PM2, Nginx, Certbot
# =============================================================================

# Nao carregar common.sh aqui - ja foi carregado pelo install.sh

INSTALL2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER_ROOT="${INSTALLER_ROOT:-$INSTALL2_DIR}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALLER_ROOT")/Projeto-menu-multitenant-seguro}"
TEMPLATES_DIR="$INSTALL2_DIR/templates"

# Diretorios de log e dados
MULTITENANT_LOG_DIR="/var/log/multitenant"
MULTITENANT_DATA_DIR="/var/lib/multitenant"
CERTBOT_WEBROOT="/var/www/certbot"

# =============================================================================
# Timezone
# =============================================================================

setup_timezone() {
    local tz="${INSTALL_TIMEZONE:-Etc/UTC}"

    if command -v timedatectl &>/dev/null; then
        if timedatectl set-timezone "$tz" 2>/dev/null; then
            log_info "Timezone configurado para: $tz"
            return 0
        fi
    fi

    if [[ -f "/usr/share/zoneinfo/$tz" ]]; then
        ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        echo "$tz" > /etc/timezone
        log_info "Timezone configurado para: $tz"
        return 0
    fi

    log_warn "Timezone '$tz' invalido. Mantendo timezone atual."
    return 0
}

# =============================================================================
# Usuario do sistema
# =============================================================================

create_system_user() {
    if id "multitenant" &>/dev/null; then
        log_info "Usuario 'multitenant' ja existe."
        return 0
    fi
    log_info "Criando usuario de sistema 'multitenant'..."
    useradd --system --create-home --shell /bin/bash --home-dir /home/multitenant multitenant
    log_success "Usuario 'multitenant' criado."
}

setup_directories() {
    log_info "Criando diretorios necessarios..."
    mkdir -p "$MULTITENANT_LOG_DIR"
    mkdir -p "$MULTITENANT_DATA_DIR"
    mkdir -p "$CERTBOT_WEBROOT"
    # Garantir que o diretório home do usuário multitenant tenha permissões corretas
    mkdir -p /home/multitenant
    chown -R multitenant:multitenant "$MULTITENANT_LOG_DIR"
    chown -R multitenant:multitenant "$MULTITENANT_DATA_DIR"
    chown -R multitenant:multitenant /home/multitenant
    log_success "Diretorios criados."
}

# =============================================================================
# Preparação do ambiente do usuário multitenant
# =============================================================================

prepare_multitenant_environment() {
    log_info "Preparando ambiente do usuário multitenant..."
    
    # Garantir que os diretórios de configuração existam
    sudo -u multitenant mkdir -p /home/multitenant/.npm /home/multitenant/.pnpm-store /home/multitenant/.config /home/multitenant/.local/bin 2>/dev/null || true
    
    # Criar links simbólicos para Node.js, npm e npx no bin do usuário
    log_info "Criando links simbólicos para Node.js..."
    sudo -u multitenant ln -sf /usr/bin/node /home/multitenant/.local/bin/node 2>/dev/null || true
    sudo -u multitenant ln -sf /usr/bin/npm /home/multitenant/.local/bin/npm 2>/dev/null || true
    sudo -u multitenant ln -sf /usr/bin/npx /home/multitenant/.local/bin/npx 2>/dev/null || true
    
    # Adicionar .local/bin ao PATH permanentemente no .bashrc e .profile do usuário
    if ! sudo -u multitenant grep -q "export PATH.*\.local/bin" /home/multitenant/.bashrc 2>/dev/null; then
        sudo -u multitenant bash -c 'echo "export PATH=\"\$HOME/.local/bin:/usr/bin:\$PATH\"" >> ~/.bashrc'
    fi
    
    if ! sudo -u multitenant grep -q "export PATH.*\.local/bin" /home/multitenant/.profile 2>/dev/null; then
        sudo -u multitenant bash -c 'echo "export PATH=\"\$HOME/.local/bin:/usr/bin:\$PATH\"" >> ~/.profile'
    fi
    
    # Verificar se Node.js está acessível
    if ! sudo -u multitenant bash -lc 'command -v node' >/dev/null 2>&1; then
        log_error "Node.js não está disponível para o usuário multitenant"
        return 1
    fi
    
    # Instalar ou verificar pnpm globalmente e no usuário
    if ! command -v pnpm &>/dev/null; then
        npm install -g pnpm
    fi

    if ! sudo -u multitenant bash -lc 'command -v pnpm' >/dev/null 2>&1; then
        log_info "Instalando pnpm para o usuário multitenant..."
        sudo -u multitenant bash -lc 'npm install -g pnpm' 2>/dev/null || true
        
        # Link simbólico se necessário
        if [[ -f /usr/local/bin/pnpm ]]; then
            sudo -u multitenant ln -sf /usr/local/bin/pnpm /home/multitenant/.local/bin/pnpm 2>/dev/null || true
        elif [[ -f /usr/bin/pnpm ]]; then
            sudo -u multitenant ln -sf /usr/bin/pnpm /home/multitenant/.local/bin/pnpm 2>/dev/null || true
        fi
    fi
    
    log_success "Ambiente do usuário multitenant preparado."
}

# =============================================================================
# Node.js 20 LTS + pnpm
# =============================================================================

check_nodejs() {
    if command -v node &>/dev/null; then
        local version=$(node --version 2>/dev/null)
        if [[ "$version" =~ ^v2[0-9]\. ]]; then
            log_info "Node.js ja instalado: $version"
            return 0
        else
            log_warn "Node.js encontrado ($version) mas versao 20+ e recomendada."
            return 1
        fi
    fi
    return 1
}

install_nodejs() {
    if check_nodejs; then
        return 0
    fi

    log_info "Instalando Node.js 20 LTS..."

    # Adicionar repositorio NodeSource
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg
    mkdir -p /etc/apt/keyrings

    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq nodejs

    log_success "Node.js instalado: $(node --version)"

    # Instalar pnpm globalmente
    if ! command -v pnpm &>/dev/null; then
        log_info "Instalando pnpm..."
        npm install -g pnpm
        log_success "pnpm instalado: $(pnpm --version)"
    fi
}

# =============================================================================
# PostgreSQL 15
# =============================================================================

check_postgresql() {
    if command -v psql &>/dev/null && systemctl is-active --quiet postgresql 2>/dev/null; then
        log_info "PostgreSQL ja instalado e rodando."
        return 0
    fi
    return 1
}

install_postgresql() {
    if check_postgresql; then
        return 0
    fi

    log_info "Instalando PostgreSQL 15..."

    # Verificar se pacote postgresql-15 esta disponivel; senao, usar repo oficial
    if ! apt-cache show postgresql-15 &>/dev/null; then
        log_info "Adicionando repositorio oficial do PostgreSQL..."
        apt-get install -y -qq curl ca-certificates
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
            | gpg --dearmor --yes -o /etc/apt/keyrings/postgresql.gpg 2>/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
            | tee /etc/apt/sources.list.d/pgdg.list > /dev/null
        apt-get update -qq
    fi

    apt-get install -y -qq postgresql-15 postgresql-contrib-15

    systemctl start postgresql
    systemctl enable postgresql

    log_success "PostgreSQL 15 instalado e rodando."
}

configure_postgresql() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"

    log_info "Configurando banco de dados PostgreSQL..."

    # Criar usuario se nao existir
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" | grep -q 1; then
        log_info "Usuario PostgreSQL '$db_user' ja existe."
        # Atualizar senha
        sudo -u postgres psql -c "ALTER USER \"$db_user\" WITH PASSWORD '$db_pass';" >/dev/null 2>&1
    else
        sudo -u postgres psql -c "CREATE USER \"$db_user\" WITH PASSWORD '$db_pass';" >/dev/null 2>&1
        log_success "Usuario PostgreSQL '$db_user' criado."
    fi

    # Criar banco se nao existir
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" | grep -q 1; then
        log_info "Banco de dados '$db_name' ja existe."
    else
        sudo -u postgres psql -c "CREATE DATABASE \"$db_name\" OWNER \"$db_user\";" >/dev/null 2>&1
        log_success "Banco de dados '$db_name' criado."
    fi

    # Conceder privilegios
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"$db_name\" TO \"$db_user\";" >/dev/null 2>&1
    sudo -u postgres psql -d "$db_name" -c "GRANT ALL ON SCHEMA public TO \"$db_user\";" >/dev/null 2>&1

    log_success "PostgreSQL configurado: banco=$db_name, usuario=$db_user"
}

# =============================================================================
# Redis 7
# =============================================================================

check_redis() {
    if command -v redis-cli &>/dev/null && systemctl is-active --quiet redis-server 2>/dev/null; then
        log_info "Redis ja instalado e rodando."
        return 0
    fi
    return 1
}

install_redis() {
    if check_redis; then
        return 0
    fi

    log_info "Instalando Redis..."

    apt-get install -y -qq redis-server

    # Configurar para rodar como servico
    systemctl start redis-server
    systemctl enable redis-server

    # Verificar conexao
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        log_success "Redis instalado e respondendo."
    else
        log_warn "Redis instalado, mas nao respondeu ao ping. Verifique a configuracao."
    fi
}

# =============================================================================
# PM2 (gerenciador de processos)
# =============================================================================

check_pm2() {
    if command -v pm2 &>/dev/null; then
        log_info "PM2 ja instalado: $(pm2 --version 2>/dev/null)"
        return 0
    fi
    return 1
}

install_pm2() {
    if check_pm2; then
        return 0
    fi

    log_info "Instalando PM2..."
    npm install -g pm2
    
    # Garantir que o usuário multitenant também tenha acesso ao PM2
    sudo -u multitenant sh -lc 'npm install -g pm2' 2>/dev/null || true

    # Configurar PM2 para iniciar no boot
    sudo -u multitenant pm2 startup systemd -u multitenant --hp /home/multitenant 2>/dev/null || true

    log_success "PM2 instalado."
}

# =============================================================================
# Nginx
# =============================================================================

install_nginx() {
    # Remover Apache se existir para evitar conflito na porta 80
    if command -v apache2 &>/dev/null; then
        log_info "Removendo Apache para evitar conflitos de porta..."
        systemctl stop apache2 2>/dev/null || true
        apt-get remove -y -qq apache2 apache2-bin apache2-utils apache2-data 2>/dev/null || true
        apt-get autoremove -y -qq 2>/dev/null || true
    fi

    if command -v nginx &>/dev/null; then
        log_info "Nginx ja instalado."
        return 0
    fi

    log_info "Instalando Nginx..."
    apt-get install -y -qq nginx
    systemctl start nginx
    systemctl enable nginx
    log_success "Nginx instalado e rodando."
}

configure_nginx_native() {
    local domain="$1"
    local ssl_cert="$2"
    local ssl_key="$3"

    log_info "Configurando Nginx para $domain..."

    local tpl="$TEMPLATES_DIR/nginx/nginx-native.conf.template"
    local dest="/etc/nginx/sites-available/multitenant"

    if [[ ! -f "$tpl" ]]; then
        log_error "Template Nginx nao encontrado: $tpl"
        return 1
    fi

    sed -e "s|__DOMAIN__|$domain|g" \
        -e "s|__SSL_CERT__|$ssl_cert|g" \
        -e "s|__SSL_KEY__|$ssl_key|g" \
        "$tpl" > "$dest"

    # Remover o default para evitar conflito de porta 80
    rm -f /etc/nginx/sites-enabled/default
    ln -sf "$dest" /etc/nginx/sites-enabled/multitenant 2>/dev/null || true

    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        log_success "Nginx configurado com sucesso."
    else
        log_error "Erro na configuracao do Nginx. Verifique com 'nginx -t'."
        return 1
    fi
}

# =============================================================================
# Certbot / SSL
# =============================================================================

install_certbot() {
    if command -v certbot &>/dev/null; then
        log_info "Certbot ja instalado."
        return 0
    fi

    log_info "Instalando Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx
    log_success "Certbot instalado."
}

obtain_native_ssl_cert() {
    local domain="$1"
    local email="$2"

    log_info "Tentando obter certificado Let's Encrypt para $domain..."

    # Verificar se ja existe
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        log_info "Certificado ja existe para $domain"
        return 0
    fi

    # Desafio webroot (Nginx deve estar rodando e servindo /.well-known/acme-challenge/)
    mkdir -p "$CERTBOT_WEBROOT"
    
    # Criar um arquivo de teste para verificar se o Nginx esta servindo o webroot
    local acme_file="$CERTBOT_WEBROOT/test.txt"
    echo "ACME-TEST" > "$acme_file"
    
    # Tentar obter via webroot
    if certbot certonly --webroot -w "$CERTBOT_WEBROOT" \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --quiet; then
        
        log_success "Certificado Let's Encrypt obtido com sucesso para $domain"
        rm -f "$acme_file"
        return 0
    fi

    log_warn "Falha ao obter certificado via webroot. Tentando via plugin Nginx..."
    
    if certbot certonly --nginx \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --quiet; then
        
        log_success "Certificado Let's Encrypt obtido com sucesso via plugin Nginx."
        rm -f "$acme_file"
        return 0
    fi

    rm -f "$acme_file"
    return 1
}

generate_self_signed_cert() {
    local domain="$1"
    local cert_dir="/etc/ssl/multitenant"

    mkdir -p "$cert_dir"

    if [[ -f "$cert_dir/cert.pem" ]] && [[ -f "$cert_dir/key.pem" ]]; then
        log_info "Certificado autoassinado ja existe em $cert_dir"
        return 0
    fi

    log_info "Gerando certificado autoassinado para $domain..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$cert_dir/key.pem" \
        -out "$cert_dir/cert.pem" \
        -subj "/CN=$domain" 2>/dev/null

    log_success "Certificado autoassinado criado em $cert_dir/"
}

setup_certbot_renewal() {
    log_info "Configurando renovacao automatica do certificado..."
    if systemctl is-enabled certbot.timer &>/dev/null; then
        log_info "Timer de renovacao do Certbot ja ativo."
    else
        systemctl enable --now certbot.timer 2>/dev/null || true
    fi

    local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
    mkdir -p "$hook_dir"
    cat > "$hook_dir/reload-nginx.sh" << 'HOOK'
#!/bin/bash
systemctl reload nginx
HOOK
    chmod +x "$hook_dir/reload-nginx.sh"
    log_success "Renovacao automatica de SSL configurada."
}

# =============================================================================
# Build da aplicacao
# =============================================================================

build_application() {
    local node_env="${1:-production}"

    log_info "Instalando dependencias do projeto (pnpm install)..."
    
    prepare_multitenant_environment
    
    chown -R multitenant:multitenant "$PROJECT_ROOT"
    chmod -R 755 "$PROJECT_ROOT"
    
    cd "$PROJECT_ROOT"
    
    # Instalar dependencias
    log_info "Executando pnpm install..."
    sudo -u multitenant bash -lc 'pnpm install'
    
    # Gerar Prisma Client
    log_info "Gerando Prisma Client..."
    cd "$PROJECT_ROOT/apps/backend"
    sudo -u multitenant bash -lc 'pnpm exec prisma generate'

    # Build do backend
    log_info "Construindo backend (NestJS)..."
    cd "$PROJECT_ROOT/apps/backend"
    sudo -u multitenant bash -lc "NODE_ENV=$node_env pnpm run build"

    # Build do frontend
    log_info "Construindo frontend (Next.js)..."
    cd "$PROJECT_ROOT/apps/frontend"
    sudo -u multitenant bash -lc "NODE_ENV=$node_env pnpm run build"

    cd "$PROJECT_ROOT"
    log_success "Build da aplicacao concluido."
}

# =============================================================================
# Configuracao de .env dos apps
# =============================================================================

configure_backend_env() {
    local domain="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_name="$4"
    local jwt_secret="$5"
    local enc_key="$6"
    local admin_email="$7"
    local admin_pass="$8"
    local node_env="$9"

    local env_file="$PROJECT_ROOT/apps/backend/.env"
    local env_example="$PROJECT_ROOT/apps/backend/.env.example"

    if [[ ! -f "$env_file" ]] && [[ -f "$env_example" ]]; then
        cp "$env_example" "$env_file"
        log_info "Criado apps/backend/.env a partir de .env.example"
    elif [[ ! -f "$env_file" ]]; then
        touch "$env_file"
    fi

    upsert_env "DATABASE_URL" "postgresql://$db_user:$db_pass@localhost:5432/$db_name?schema=public" "$env_file"
    upsert_env "JWT_SECRET" "$jwt_secret" "$env_file"
    upsert_env "ENCRYPTION_KEY" "$enc_key" "$env_file"
    upsert_env "FRONTEND_URL" "https://$domain" "$env_file"
    upsert_env "PORT" "4000" "$env_file"
    upsert_env "NODE_ENV" "$node_env" "$env_file"
    upsert_env "REDIS_HOST" "127.0.0.1" "$env_file"
    upsert_env "REDIS_PORT" "6379" "$env_file"
    upsert_env "INSTALL_ADMIN_EMAIL" "$admin_email" "$env_file"
    upsert_env "INSTALL_ADMIN_PASSWORD" "$admin_pass" "$env_file"
    upsert_env "REQUIRE_SECRET_MANAGER" "false" "$env_file"

    chown multitenant:multitenant "$env_file"
    chmod 600 "$env_file"
    log_success "Backend .env configurado."
}

configure_frontend_env() {
    local domain="$1"

    local env_file="$PROJECT_ROOT/apps/frontend/.env.local"
    local env_example="$PROJECT_ROOT/apps/frontend/.env.local.example"

    if [[ ! -f "$env_file" ]] && [[ -f "$env_example" ]]; then
        cp "$env_example" "$env_file"
        log_info "Criado apps/frontend/.env.local a partir de .env.local.example"
    elif [[ ! -f "$env_file" ]]; then
        touch "$env_file"
    fi

    upsert_env "NEXT_PUBLIC_API_URL" "https://$domain/api" "$env_file"

    chown multitenant:multitenant "$env_file"
    chmod 600 "$env_file"
    log_success "Frontend .env.local configurado."
}

# =============================================================================
# Migrations e Seeds
# =============================================================================

run_migrations() {
    log_info "Executando migrations do Prisma..."
    cd "$PROJECT_ROOT/apps/backend"
    
    sudo -u multitenant bash -lc 'pnpm exec prisma migrate deploy'
    log_success "Migrations aplicadas."
}

run_seeds() {
    log_info "Populando banco de dados (seed)..."
    cd "$PROJECT_ROOT/apps/backend"
    
    if sudo -u multitenant bash -lc 'pnpm exec prisma db seed'; then
        log_success "Seed executado com sucesso."
    else
        log_warn "Seed via pnpm falhou, tentando via node direto..."
        if [[ -f "dist/prisma/seed.js" ]]; then
            sudo -u multitenant bash -lc 'node dist/prisma/seed.js'
            log_success "Seed executado via node."
        else
            log_error "Nao foi possivel executar o seed."
        fi
    fi
}

# =============================================================================
# Gerenciamento de processos (systemd)
# =============================================================================

setup_systemd_services() {
    local node_env="$1"
    log_info "Instalando servicos systemd..."

    local backend_tpl="$TEMPLATES_DIR/systemd/multitenant-backend.service"
    local frontend_tpl="$TEMPLATES_DIR/systemd/multitenant-frontend.service"

    sed -e "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" \
        -e "s|__NODE_ENV__|$node_env|g" \
        "$backend_tpl" > /etc/systemd/system/multitenant-backend.service

    sed -e "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" \
        -e "s|__NODE_ENV__|$node_env|g" \
        "$frontend_tpl" > /etc/systemd/system/multitenant-frontend.service

    systemctl daemon-reload
    systemctl enable multitenant-backend multitenant-frontend
    log_success "Servicos systemd instalados e habilitados."
}

start_systemd_services() {
    log_info "Iniciando servicos..."
    systemctl restart multitenant-backend
    sleep 5
    systemctl restart multitenant-frontend
    log_success "Servicos reiniciados (systemd)."
}

# =============================================================================
# PM2
# =============================================================================

setup_pm2_services() {
    local node_env="$1"
    local backend_instances="${2:-1}"
    log_info "Configurando PM2..."
    local pm2_tpl="$TEMPLATES_DIR/pm2/ecosystem.config.js"
    local pm2_dest="$PROJECT_ROOT/ecosystem.config.js"

    sed -e "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" \
        -e "s|__NODE_ENV__|$node_env|g" \
        -e "s|__BACKEND_INSTANCES__|$backend_instances|g" \
        "$pm2_tpl" > "$pm2_dest"

    chown multitenant:multitenant "$pm2_dest"
    log_success "PM2 ecosystem criado."
}

start_pm2_services() {
    log_info "Iniciando aplicacao com PM2..."
    cd "$PROJECT_ROOT"
    sudo -u multitenant bash -lc 'pm2 start ecosystem.config.js && pm2 save'
    log_success "Aplicacao iniciada com PM2."
}

# =============================================================================
# Permissoes e Healthcheck
# =============================================================================

fix_project_permissions() {
    log_info "Ajustando permissoes do projeto..."
    chown -R multitenant:multitenant "$PROJECT_ROOT"
    chmod -R 755 "$PROJECT_ROOT"
    log_success "Permissoes ajustadas."
}

check_native_health() {
    local domain="$1"
    log_info "Verificando saude da aplicacao..."
    sleep 10
    if curl -sf http://127.0.0.1:4000/api/health >/dev/null 2>&1; then
        log_success "Backend respondendo."
    else
        log_warn "Backend nao respondeu no healthcheck local."
    fi
}

print_native_report() {
    local domain="$1"
    local admin_email="$2"
    local admin_pass="$3"
    local db_name="$4"
    local db_user="$5"
    local db_pass="$6"
    local jwt_secret="$7"
    local enc_key="$8"
    local process_mgr="$9"

    print_header "RELATORIO FINAL - INSTALACAO NATIVA"
    echo -e "URL: https://$domain"
    echo -e "Admin: $admin_email / $admin_pass"
    echo -e "DB: $db_name (User: $db_user)"
    echo -e "Process Manager: $process_mgr"
    print_separator
}
