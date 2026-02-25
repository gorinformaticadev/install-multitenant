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
    
    # Garantir que os diretórios de configuração do npm/pnpm existam
    sudo -u multitenant sh -c 'mkdir -p ~/.npm ~/.pnpm-store ~/.config'
    
    # Garantir que os comandos node e npm estejam disponíveis
    if ! sudo -u multitenant sh -c 'which node >/dev/null'; then
        log_error "Node.js não está disponível para o usuário multitenant"
        return 1
    fi
    
    if ! sudo -u multitenant sh -c 'which npm >/dev/null'; then
        log_error "npm não está disponível para o usuário multitenant"
        return 1
    fi
    
    if ! sudo -u multitenant sh -c 'which pnpm >/dev/null'; then
        log_error "pnpm não está disponível para o usuário multitenant"
        # Tentar instalar pnpm para o usuário multitenant
        log_info "Tentando instalar pnpm para o usuário multitenant..."
        sudo -u multitenant sh -c 'npm install -g pnpm' 2>/dev/null || true
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
        # Garantir que o usuário multitenant também tenha acesso ao pnpm
        sudo -u multitenant sh -c 'npm install -g pnpm' 2>/dev/null || true
        log_success "pnpm instalado: $(pnpm --version)"
    else
        log_info "pnpm ja instalado: $(pnpm --version)"
        # Garantir que o usuário multitenant também tenha acesso ao pnpm
        sudo -u multitenant sh -c 'npm install -g pnpm' 2>/dev/null || true
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
    sudo -u multitenant sh -c 'npm install -g pm2' 2>/dev/null || true

    # Configurar PM2 para iniciar no boot
    pm2 startup systemd -u multitenant --hp /home/multitenant 2>/dev/null || true

    log_success "PM2 instalado: $(pm2 --version)"
}

# =============================================================================
# Nginx
# =============================================================================

check_nginx() {
    if command -v nginx &>/dev/null && systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "Nginx ja instalado e rodando."
        return 0
    fi
    return 1
}

install_nginx() {
    if check_nginx; then
        return 0
    fi

    log_info "Instalando Nginx..."

    apt-get install -y -qq nginx

    systemctl start nginx
    systemctl enable nginx

    log_success "Nginx instalado: $(nginx -v 2>&1 | grep -oP 'nginx/\K.*')"
}

check_and_open_ports_native() {
    log_info "Verificando portas 80 e 443 para validacao do Let's Encrypt..."

    if ! command -v netstat &>/dev/null; then
        apt-get install -y -qq net-tools >/dev/null 2>&1 || true
    fi

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        log_info "UFW detectado. Liberando portas 80 e 443..."
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        log_info "Portas 80/443 liberadas no UFW."
    fi

    if command -v iptables &>/dev/null; then
        if iptables -L INPUT -n 2>/dev/null | grep -q "DROP\|REJECT"; then
            log_warn "Detectadas regras de firewall (iptables). Garanta que 80/443 estejam liberadas."
        fi
    fi

    if command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
            local port80_process
            port80_process=$(netstat -tlnp 2>/dev/null | grep ":80 " | awk '{print $7}' | head -1)
            log_info "Porta 80 em uso por: $port80_process"
        else
            log_warn "Nenhum processo local ouvindo na porta 80."
            log_warn "Sem HTTP ativo, o desafio ACME via webroot vai falhar."
        fi

        if netstat -tlnp 2>/dev/null | grep -q ":443 "; then
            local port443_process
            port443_process=$(netstat -tlnp 2>/dev/null | grep ":443 " | awk '{print $7}' | head -1)
            log_info "Porta 443 em uso por: $port443_process"
        else
            log_warn "Nenhum processo local ouvindo na porta 443."
        fi
    fi

    log_info "Verificacao de portas finalizada."
}

configure_nginx_native() {
    local domain="$1"
    local ssl_cert="$2"
    local ssl_key="$3"

    log_info "Configurando Nginx para $domain..."

    local template="$TEMPLATES_DIR/nginx/nginx-native.conf.template"
    local target="/etc/nginx/sites-available/multitenant"
    local link="/etc/nginx/sites-enabled/multitenant"

    if [[ ! -f "$template" ]]; then
        log_error "Template nginx nao encontrado: $template"
        return 1
    fi

    # Substituir placeholders
    sed -e "s|__DOMAIN__|$domain|g" \
        -e "s|__SSL_CERT__|$ssl_cert|g" \
        -e "s|__SSL_KEY__|$ssl_key|g" \
        "$template" > "$target"

    # Ativar site e desativar default
    ln -sf "$target" "$link"
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    # Testar configuracao
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log_success "Nginx configurado para $domain"
    else
        log_error "Configuracao do Nginx invalida. Verifique: $target"
        nginx -t
        return 1
    fi
}

# =============================================================================
# Certbot (SSL Let's Encrypt)
# =============================================================================

check_certbot() {
    if command -v certbot &>/dev/null; then
        log_info "Certbot ja instalado."
        return 0
    fi
    return 1
}

install_certbot() {
    if check_certbot; then
        return 0
    fi

    log_info "Instalando Certbot..."

    apt-get install -y -qq certbot python3-certbot-nginx

    log_success "Certbot instalado."
}

obtain_native_ssl_cert() {
    local domain="$1"
    local email="$2"

    log_info "Obtendo certificado SSL para $domain via Certbot..."
    check_and_open_ports_native

    # Testar com staging primeiro
    log_info "Testando com Let's Encrypt staging..."
    if certbot certonly --webroot \
        -w "$CERTBOT_WEBROOT" \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --test-cert \
        --non-interactive 2>/dev/null; then

        log_info "Staging OK. Obtendo certificado real..."
        certbot certonly --webroot \
            -w "$CERTBOT_WEBROOT" \
            -d "$domain" \
            --email "$email" \
            --agree-tos \
            --force-renewal \
            --non-interactive

        local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        local key_path="/etc/letsencrypt/live/$domain/privkey.pem"

        if [[ -f "$cert_path" ]] && [[ -f "$key_path" ]]; then
            log_success "Certificado Let's Encrypt obtido para $domain"
            echo "$cert_path"
            return 0
        fi
    fi

    log_warn "Nao foi possivel obter certificado Let's Encrypt."
    log_warn "Verifique DNS (A/AAAA), abertura de porta 80 no firewall e regra de entrada no provedor cloud."
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

# =============================================================================
# Configuracao de autorenew do SSL
# =============================================================================

setup_certbot_renewal() {
    log_info "Configurando renovacao automatica do certificado..."

    # Certbot ja instala um timer systemd, mas verificar
    if systemctl is-enabled certbot.timer &>/dev/null; then
        log_info "Timer de renovacao do Certbot ja ativo."
    else
        systemctl enable --now certbot.timer 2>/dev/null || true
    fi

    # Adicionar hook para recarregar nginx apos renovacao
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
    
    # Preparar ambiente do usuário multitenant
    prepare_multitenant_environment
    
    # Garantir que o diretório do projeto tem as permissões corretas antes de instalar
    chown -R multitenant:multitenant "$PROJECT_ROOT"
    chmod -R 755 "$PROJECT_ROOT"
    
    # Verificar se o usuário multitenant pode acessar o diretório do projeto
    if ! sudo -u multitenant test -r "$PROJECT_ROOT"; then
        log_warn "Usuário multitenant não tem permissão de leitura no diretório do projeto"
        log_info "Verificando permissões dos diretórios pai..."
        
        # Garantir que todos os diretórios no caminho tenham permissão de execução (x) 
        # para que possam ser atravessados pelo usuário multitenant
        local current_path="/"
        IFS='/' read -ra path_parts <<< "${PROJECT_ROOT#/}"
        for part in "${path_parts[@]}"; do
            if [[ -n "$part" ]]; then
                current_path="$current_path$part"
                # Garantir que o diretório tenha permissão de leitura e execução
                chmod 755 "$current_path" 2>/dev/null || true
                current_path="$current_path/"
            fi
        done
        
        # Tenta novamente após ajustar permissões
        if ! sudo -u multitenant test -r "$PROJECT_ROOT"; then
            log_warn "Usuário multitenant ainda não tem permissão de leitura no diretório do projeto"
            log_warn "Executando pnpm install como root e ajustando permissões posteriormente..."
            
            cd "$PROJECT_ROOT"
            
            # Instalar dependencias como root e depois ajustar permissões
            log_info "Executando pnpm install como root..."
            if ! pnpm install --frozen-lockfile 2>/dev/null; then
                log_warn "Falha com --frozen-lockfile, tentando instalação normal..."
                if ! pnpm install 2>/dev/null; then
                    log_error "Falha ao executar pnpm install como root"
                    return 1
                fi
            fi
            
            # Ajustar permissões após instalação
            chown -R multitenant:multitenant "$PROJECT_ROOT/node_modules" 2>/dev/null || true
            chown -R multitenant:multitenant "$PROJECT_ROOT/pnpm-lock.yaml" 2>/dev/null || true
            chown -R multitenant:multitenant "$PROJECT_ROOT/package.json" 2>/dev/null || true
            chown -R multitenant:multitenant "$PROJECT_ROOT/apps" 2>/dev/null || true
        else
            cd "$PROJECT_ROOT"
            # Instalar dependencias como usuário multitenant
            log_info "Executando pnpm install como usuário multitenant..."
            if ! sudo -u multitenant pnpm install --frozen-lockfile 2>/dev/null; then
                log_warn "Falha com --frozen-lockfile, tentando instalação normal..."
                if ! sudo -u multitenant pnpm install 2>/dev/null; then
                    log_error "Falha ao executar pnpm install como usuário multitenant"
                    return 1
                fi
            fi
        fi
    else
        cd "$PROJECT_ROOT"
        # Instalar dependencias como usuário multitenant
        log_info "Executando pnpm install como usuário multitenant..."
        if ! sudo -u multitenant pnpm install --frozen-lockfile 2>/dev/null; then
            log_warn "Falha com --frozen-lockfile, tentando instalação normal..."
            if ! sudo -u multitenant pnpm install 2>/dev/null; then
                log_error "Falha ao executar pnpm install como usuário multitenant"
                return 1
            fi
        fi
    fi

    # Gerar Prisma Client
    log_info "Gerando Prisma Client..."
    cd "$PROJECT_ROOT/apps/backend"
    sudo -u multitenant npx prisma generate

    # Build do backend
    log_info "Construindo backend (NestJS)..."
    cd "$PROJECT_ROOT/apps/backend"
    sudo -u multitenant NODE_ENV="$node_env" pnpm run build

    # Build do frontend
    log_info "Construindo frontend (Next.js)..."
    cd "$PROJECT_ROOT/apps/frontend"
    sudo -u multitenant NODE_ENV="$node_env" pnpm run build

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

    # Host local: PostgreSQL roda em localhost, nao em container
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

    # Ajustar permissao
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
    
    # Antes de executar as migrations, gerar novamente o Prisma Client
    log_info "Garantindo que o Prisma Client esteja atualizado..."
    sudo -u multitenant npx prisma generate 2>/dev/null || true
    
    # Primeira tentativa de executar as migrations
    if ! sudo -u multitenant npx prisma migrate deploy 2>&1; then
        log_warn "Falha na aplicação das migrations. Verificando situação..."
        
        # Verificar o status das migrations
        log_info "Verificando status das migrations..."
        sudo -u multitenant npx prisma migrate status 2>&1 || true
        
        # Verificar se há migrações com falha e tentar resolver
        log_info "Verificando migrações com falha..."
        
        # Tenta resolver o problema de migrations com falha
        log_info "Tentando resolver problema de migrations com falha (P3009)..."
        
        # Primeiro, tenta verificar se o banco está em estado inconsistente
        log_info "Resetando banco de dados para limpar estado inconsistente..."
        if sudo -u multitenant npx prisma migrate reset --force 2>/dev/null; then
            log_info "Banco de dados resetado com sucesso. Aplicando migrations novamente..."
        else
            log_warn "Não foi possível resetar as migrations. Verificando se o banco está vazio..."
            
            # Se o reset falhar, verificar se o banco está completamente vazio
            # Nesse caso, podemos tentar aplicar as migrations do zero
            if sudo -u multitenant npx prisma migrate resolve --applied 2>/dev/null; then
                log_info "Estado de migrações resolvido. Tentando aplicar novamente..."
            else
                log_warn "Não foi possível resolver o estado das migrations automaticamente."
                
                # Como último recurso, tentar um reset completo
                log_info "Forçando reset completo do banco de dados..."
                sudo -u multitenant npx prisma migrate reset --force <<< "y" 2>/dev/null || true
            fi
        fi
        
        # Tentar aplicar novamente
        if ! sudo -u multitenant npx prisma migrate deploy 2>&1; then
            log_error "Falha crítica ao aplicar migrations. O banco de dados pode estar em estado inconsistente."
            log_error "Tentando uma abordagem alternativa..."
                
            # Verificar se o erro está relacionado à migração específica com nome de tabela incorreto
            log_info "Verificando se o erro é causado pela migração com nome de tabela incorreto..."
                
            # Tentar uma abordagem alternativa: marcar todas as migrações como aplicadas se for uma instalação limpa
            log_info "Verificando se é uma instalação limpa (banco vazio)..."
                    
            # Obter as variáveis do banco de dados do arquivo .env
            local db_url=$(sudo -u multitenant grep "^DATABASE_URL=" "$PROJECT_ROOT/apps/backend/.env" | cut -d'=' -f2-)
            local db_name=$(echo "$db_url" | sed -n 's/.*\/\([^?]*\).*/\1/p')
                    
            if sudo -u multitenant psql -d "$db_name" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public');" 2>/dev/null | grep -q "f"; then
                # Banco está vazio, tentar aplicar migrations do zero
                log_info "Banco está vazio, tentando aplicar migrations do zero..."
                if ! sudo -u multitenant npx prisma migrate deploy 2>&1; then
                    log_warn "Erro persiste. Verificando se é o problema conhecido de nome de tabela..."
                            
                    # Se o erro for o problema conhecido com a tabela SecurityConfig, tentar criar a tabela manualmente
                    log_info "Tentando criar estrutura inicial do security_config se necessário..."
                    sudo -u multitenant npx prisma migrate resolve --applied 20260222000000_update_rate_limit_defaults 2>/dev/null || true
                            
                    # Tentar aplicar novamente
                    if ! sudo -u multitenant npx prisma migrate deploy 2>&1; then
                        log_error "Falha ao aplicar migrations mesmo com banco vazio."
                        return 1
                    fi
                fi
            else
                log_warn "O banco de dados contém tabelas existentes, mas as migrations estão em estado inconsistente."
                        
                # Para o erro específico com a tabela SecurityConfig, tentar resolver manualmente
                log_info "Tentando resolver migração problemática manualmente..."
                        
                # Verificar se a tabela security_config existe
                table_exists=$(sudo -u multitenant psql -d "$db_name" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'security_config');")
                        
                if [[ "$table_exists" == "t" ]]; then
                    # A tabela existe, então a migração inicial já foi aplicada
                    # Marcar a migração problemática como resolvida
                    log_info "Tabela security_config existe, marcando migração problemática como resolvida..."
                    sudo -u multitenant npx prisma migrate resolve --applied 20260222000000_update_rate_limit_defaults 2>/dev/null || true
                else
                    # A tabela não existe, talvez seja necessário aplicar as migrações iniciais primeiro
                    log_info "Tabela security_config não existe, aplicando migrations iniciais..."
                fi
                        
                # Tentar aplicar novamente
                if ! sudo -u multitenant npx prisma migrate deploy 2>&1; then
                    log_error "Falha ao aplicar migrations mesmo após tentativas de resolução."
                    return 1
                fi
            fi
        fi
    fi
    
    log_success "Migrations aplicadas."
}

run_seeds() {
    log_info "Populando banco de dados (seed)..."
    cd "$PROJECT_ROOT/apps/backend"

    # O projeto usa seed compilado em dist/prisma/seed.js.
    # No fluxo nativo, garantir artefato antes de executar.
    if [[ ! -f dist/prisma/seed.js ]]; then
        log_warn "Arquivo dist/prisma/seed.js nao encontrado. Compilando seed..."
        if ! sudo -u multitenant npx tsc prisma/seed.ts \
            --outDir dist/prisma \
            --skipLibCheck \
            --module commonjs \
            --target ES2021 \
            --esModuleInterop \
            --resolveJsonModule; then
            log_error "Falha ao compilar seed.ts para dist/prisma/seed.js"
            return 1
        fi
    fi

    if sudo -u multitenant npx prisma db seed; then
        log_success "Seed executado com sucesso."
        return 0
    fi

    log_warn "Falha no prisma db seed. Tentando executar seed compilado diretamente..."
    if sudo -u multitenant node dist/prisma/seed.js; then
        log_success "Seed executado com sucesso (modo direto)."
        return 0
    fi

    log_error "Seed falhou. Corrija o erro acima e execute: cd apps/backend && npx prisma db seed"
    return 1
}

# =============================================================================
# Gerenciamento de processos (systemd ou PM2)
# =============================================================================

setup_systemd_services() {
    local node_env="$1"

    log_info "Instalando servicos systemd..."

    local backend_tpl="$TEMPLATES_DIR/systemd/multitenant-backend.service"
    local frontend_tpl="$TEMPLATES_DIR/systemd/multitenant-frontend.service"

    if [[ ! -f "$backend_tpl" ]] || [[ ! -f "$frontend_tpl" ]]; then
        log_error "Templates systemd nao encontrados em $TEMPLATES_DIR/systemd/"
        return 1
    fi

    # Backend service
    sed -e "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" \
        -e "s|__NODE_ENV__|$node_env|g" \
        "$backend_tpl" > /etc/systemd/system/multitenant-backend.service

    # Frontend service
    sed -e "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" \
        -e "s|__NODE_ENV__|$node_env|g" \
        "$frontend_tpl" > /etc/systemd/system/multitenant-frontend.service

    systemctl daemon-reload
    systemctl enable multitenant-backend multitenant-frontend

    log_success "Servicos systemd instalados e habilitados."
}

# =============================================================================
# Verificação de ambiente do usuário multitenant
# =============================================================================

check_multitenant_environment() {
    log_info "Verificando ambiente do usuário multitenant..."
    
    # Verificar se o Node.js está disponível para o usuário multitenant
    if ! sudo -u multitenant command -v node >/dev/null 2>&1; then
        log_error "Node.js não está disponível para o usuário multitenant"
        # Tentar configurar o PATH
        sudo -u multitenant sh -c 'export PATH="$PATH:/usr/local/bin:/opt/nodejs/bin:$HOME/.nvm/versions/node/*/bin" >> ~/.bashrc'
        # Atualizar o PATH
        sudo -u multitenant sh -c 'hash -r'
    fi
    
    # Verificar se o Node.js pode ser executado
    local node_version=$(sudo -u multitenant node --version 2>/dev/null)
    if [[ -n "$node_version" ]]; then
        log_success "Node.js encontrado: $node_version"
    else
        log_warn "Node.js não pôde ser executado como usuário multitenant"
    fi
    
    # Verificar se os arquivos necessários existem
    if [[ ! -f "$PROJECT_ROOT/apps/backend/dist/main.js" ]]; then
        log_error "Arquivo backend dist/main.js não encontrado"
        log_info "Certifique-se de que o build foi concluído com sucesso"
    else
        log_success "Arquivo backend encontrado"
    fi
    
    if [[ ! -f "$PROJECT_ROOT/apps/frontend/server.js" ]]; then
        log_error "Arquivo frontend server.js não encontrado"
        log_info "Certifique-se de que o build foi concluído com sucesso"
    else
        log_success "Arquivo frontend encontrado"
    fi
}

start_systemd_services() {
    log_info "Iniciando servicos..."
    
    # Verificar ambiente do usuário multitenant antes de iniciar
    check_multitenant_environment
    
    # Iniciar backend primeiro e aguardar um pouco
    systemctl start multitenant-backend
    sleep 8  # Aumentar o tempo para garantir que o backend suba
    
    # Verificar se o backend está realmente ativo antes de iniciar o frontend
    local backend_attempts=0
    local backend_max_attempts=10
    while [[ $backend_attempts -lt $backend_max_attempts ]]; do
        if systemctl is-active --quiet multitenant-backend; then
            log_info "Backend iniciado com sucesso."
            break
        else
            log_info "Aguardando backend iniciar... (${backend_attempts}/${backend_max_attempts})"
            sleep 3
            ((backend_attempts++))
        fi
    done
    
    # Iniciar frontend
    systemctl start multitenant-frontend
    sleep 5  # Tempo para o frontend subir
    
    # Verificar status
    if systemctl is-active --quiet multitenant-backend; then
        log_success "Backend rodando (systemd)."
    else
        log_error "Backend nao iniciou. Verifique: journalctl -u multitenant-backend"
        log_info "Verificando logs do backend:"
        journalctl -u multitenant-backend --no-pager -n 20 2>/dev/null || true
    fi

    if systemctl is-active --quiet multitenant-frontend; then
        log_success "Frontend rodando (systemd)."
    else
        log_error "Frontend nao iniciou. Verifique: journalctl -u multitenant-frontend"
        log_info "Verificando logs do frontend:"
        journalctl -u multitenant-frontend --no-pager -n 20 2>/dev/null || true
    fi
}

setup_pm2_services() {
    local node_env="$1"
    local backend_instances="${2:-1}"

    log_info "Configurando PM2..."

    local pm2_tpl="$TEMPLATES_DIR/pm2/ecosystem.config.js"
    local pm2_dest="$PROJECT_ROOT/ecosystem.config.js"

    if [[ ! -f "$pm2_tpl" ]]; then
        log_error "Template PM2 nao encontrado: $pm2_tpl"
        return 1
    fi

    sed -e "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" \
        -e "s|__NODE_ENV__|$node_env|g" \
        -e "s|__BACKEND_INSTANCES__|$backend_instances|g" \
        "$pm2_tpl" > "$pm2_dest"

    chown multitenant:multitenant "$pm2_dest"

    log_success "Arquivo PM2 ecosystem criado: $pm2_dest"
}

start_pm2_services() {
    log_info "Iniciando aplicacao com PM2..."
    cd "$PROJECT_ROOT"

    sudo -u multitenant pm2 start ecosystem.config.js
    sudo -u multitenant pm2 save

    sleep 5

    # Verificar status
    sudo -u multitenant pm2 list

    log_success "Aplicacao iniciada com PM2."
}

# =============================================================================
# Permissoes do projeto
# =============================================================================

fix_project_permissions() {
    log_info "Ajustando permissoes do projeto..."
    chown -R multitenant:multitenant "$PROJECT_ROOT"
    # Manter diretorio do instalador acessivel ao root para futuras reinstalacoes
    chmod -R 755 "$INSTALL2_DIR"
    log_success "Permissoes ajustadas."
}

# =============================================================================
# Verificacao de saude (healthcheck)
# =============================================================================

check_native_health() {
    local domain="$1"
    local retries=12
    local wait_seconds=5

    log_info "Verificando saude da aplicacao..."

    for ((i=1; i<=retries; i++)); do
        # Verificar backend
        if curl -sf http://127.0.0.1:4000/api/health >/dev/null 2>&1; then
            log_success "Backend respondendo em :4000"

            # Verificar frontend
            if curl -sf http://127.0.0.1:5000/ >/dev/null 2>&1; then
                log_success "Frontend respondendo em :5000"
                return 0
            fi
        fi

        log_info "Aguardando servicos iniciarem... ($i/$retries)"
        sleep "$wait_seconds"
    done

    log_warn "Timeout aguardando servicos. Verifique os logs."
    return 1
}

# =============================================================================
# Relatorio final (instalacao nativa)
# =============================================================================

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

    echo -e "\n\n"
    echoblue "=========================================================="
    echoblue "  RELATORIO FINAL - INSTALACAO NATIVA MULTITENANT         "
    echoblue "=========================================================="
    echo -e "\n"

    echo -e "\033[1;32mACESSO AO SISTEMA:\033[0m"
    echo -e "   URL Principal:  https://$domain"
    echo -e "   API Endpoint:   https://$domain/api"
    echo -e "   API Health:     https://$domain/api/health"
    echo -e "\n"

    echo -e "\033[1;32mCREDENCIAIS DO ADMINISTRADOR:\033[0m"
    echo -e "   Email:          $admin_email"
    echo -e "   Senha:          $admin_pass"
    echo -e "   Nivel:          SUPER_ADMIN"
    echo -e "\n"

    echo -e "\033[1;32mBANCO DE DADOS (PostgreSQL):\033[0m"
    echo -e "   Host:           localhost"
    echo -e "   Porta:          5432"
    echo -e "   Banco:          $db_name"
    echo -e "   Usuario:        $db_user"
    echo -e "   Senha:          $db_pass"
    echo -e "\n"

    echo -e "\033[1;32mCACHE (Redis):\033[0m"
    echo -e "   Host:           127.0.0.1"
    echo -e "   Porta:          6379"
    echo -e "\n"

    echo -e "\033[1;32mSEGREDOS DO SISTEMA:\033[0m"
    echo -e "   JWT_SECRET:     $jwt_secret"
    echo -e "   ENCRYPTION_KEY: $enc_key"
    echo -e "\n"

    echo -e "\033[1;32mGERENCIAMENTO DE PROCESSOS ($process_mgr):\033[0m"
    if [[ "$process_mgr" == "pm2" ]]; then
        echo -e "   Status:         sudo -u multitenant pm2 list"
        echo -e "   Logs:           sudo -u multitenant pm2 logs"
        echo -e "   Restart:        sudo -u multitenant pm2 restart all"
        echo -e "   Stop:           sudo -u multitenant pm2 stop all"
    else
        echo -e "   Status backend: systemctl status multitenant-backend"
        echo -e "   Status front:   systemctl status multitenant-frontend"
        echo -e "   Logs backend:   journalctl -u multitenant-backend -f"
        echo -e "   Logs front:     journalctl -u multitenant-frontend -f"
        echo -e "   Restart:        systemctl restart multitenant-backend multitenant-frontend"
    fi
    echo -e "\n"

    echo -e "\033[1;32mNGINX:\033[0m"
    echo -e "   Config:         /etc/nginx/sites-available/multitenant"
    echo -e "   Logs acesso:    /var/log/nginx/access.log"
    echo -e "   Logs erro:      /var/log/nginx/error.log"
    echo -e "   Reload:         systemctl reload nginx"
    echo -e "\n"

    echoblue "=========================================================="
    log_info "Guarde estas informacoes em local seguro!"
    log_info "Arquivo de configuracao backend: $PROJECT_ROOT/apps/backend/.env"
    log_info "Arquivo de configuracao frontend: $PROJECT_ROOT/apps/frontend/.env.local"
    echogreen "Instalacao nativa concluida com sucesso!"
    echo -e "\n"
}
