#!/usr/bin/env bash
# =============================================================================
# Funcoes de Instalacao Docker - Instalador Multitenant v2.0
# =============================================================================
# Funcoes trazidas de install/install.sh SEM modificacao de logica.
# Apenas reorganizadas em modulo independente para install-2/.
# =============================================================================

# --- Paths (definidos quando sourced; SCRIPT_DIR e PROJECT_ROOT vem de install.sh) ---
INSTALL2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER_ROOT="${INSTALLER_ROOT:-$INSTALL2_DIR}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$INSTALLER_ROOT")/Projeto-menu-multitenant-seguro}"

COMPOSE_PROD="$PROJECT_ROOT/docker-compose.prod.yml"
COMPOSE_PROD_BUILD="$PROJECT_ROOT/docker-compose.prod.build.yml"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"
ENV_INSTALLER_EXAMPLE="$INSTALL2_DIR/.env.installer.example"
ENV_PRODUCTION="$INSTALL2_DIR/.env.production"
NGINX_TEMPLATE_DOCKER="$INSTALL2_DIR/nginx-docker.conf.template"
NGINX_TEMPLATE_ACME="$PROJECT_ROOT/multitenant-docker-acme/confs/nginx-multitenant.conf"
NGINX_CONF_DIR="$PROJECT_ROOT/nginx/conf.d"
NGINX_CERTS_DIR="$PROJECT_ROOT/nginx/certs"
NGINX_WEBROOT="$PROJECT_ROOT/nginx/webroot"

# --- Verificacao de portas (copiado de install/install.sh) ---
check_and_open_ports() {
    log_info "Verificando portas 80 e 443..."
    
    # Instalar net-tools se necessario (para netstat)
    if ! command -v netstat &>/dev/null; then
        apt-get install -y -qq net-tools >/dev/null 2>&1 || true
    fi
    
    # Verificar se ufw esta instalado e ativo
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        log_info "UFW detectado. Liberando portas 80 e 443..."
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        log_info "Portas liberadas no UFW."
    fi
    
    # Verificar se iptables esta bloqueando
    if command -v iptables &>/dev/null; then
        if iptables -L INPUT -n 2>/dev/null | grep -q "DROP\|REJECT"; then
            log_warn "Detectadas regras de firewall. Certifique-se de que as portas 80 e 443 estao liberadas."
        fi
    fi
    
    # Verificar se as portas estao em uso
    if command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
            local port80_process=$(netstat -tlnp 2>/dev/null | grep ":80 " | awk '{print $7}' | head -1)
            if [[ "$port80_process" != *"docker"* ]]; then
                log_warn "Porta 80 ja esta em uso por: $port80_process"
                log_warn "Isso pode causar conflitos. Considere parar o servico antes de continuar."
            fi
        fi
        
        if netstat -tlnp 2>/dev/null | grep -q ":443 "; then
            local port443_process=$(netstat -tlnp 2>/dev/null | grep ":443 " | awk '{print $7}' | head -1)
            if [[ "$port443_process" != *"docker"* ]]; then
                log_warn "Porta 443 ja esta em uso por: $port443_process"
                log_warn "Isso pode causar conflitos. Considere parar o servico antes de continuar."
            fi
        fi
    fi
    
    log_info "Verificacao de portas concluida."
}

# --- Resolver image owner (copiado de install/install.sh) ---
resolve_image_owner() {
    local owner="${IMAGE_OWNER:-${GHCR_OWNER:-}}"
    if [[ -n "$owner" ]]; then
        echo "$owner" | tr '[:upper:]' '[:lower:]'
        return 0
    fi

    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        # Lidar com o problema de segurança do Git sobre propriedade duvidosa
        git config --global --add safe.directory "$PROJECT_ROOT" 2>/dev/null || true
        local remote_url
        remote_url="$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true)"
        if [[ -n "$remote_url" ]]; then
            owner="$(echo "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)##' | cut -d'/' -f1)"
            if [[ -n "$owner" ]]; then
                echo "$owner" | tr '[:upper:]' '[:lower:]'
                return 0
            fi
        fi
    fi

    echo ""
}

# --- Pull ou build da stack (copiado de install/install.sh) ---
pull_or_build_stack() {
    local compose_base=(-f docker-compose.prod.yml)
    local compose_build=(-f docker-compose.prod.yml -f docker-compose.prod.build.yml)
    local compose_cmd=(docker compose --env-file "$ENV_PRODUCTION")
    local local_build_only="${LOCAL_BUILD_ONLY:-false}"

    print_stack_diagnostics() {
        log_warn "Falha ao subir stack. Coletando diagnostico..."
        "${compose_cmd[@]}" "${compose_base[@]}" ps || true
        docker logs --tail 200 multitenant-backend 2>/dev/null || true
        docker logs --tail 120 multitenant-postgres 2>/dev/null || true
    }

    if [[ "$local_build_only" == "true" ]]; then
        log_info "Modo LOCAL_BUILD_ONLY=true: executando build local no servidor."
        "${compose_cmd[@]}" "${compose_build[@]}" build backend frontend
        if ! "${compose_cmd[@]}" "${compose_build[@]}" up -d; then
            print_stack_diagnostics
            return 1
        fi
        return 0
    fi

    # Primeira tentativa: pull da tag definida
    if "${compose_cmd[@]}" "${compose_base[@]}" pull; then
        if "${compose_cmd[@]}" "${compose_base[@]}" up -d; then
            return 0
        fi
        print_stack_diagnostics
        log_warn "Pull funcionou, mas os containers nao ficaram saudaveis."
    fi

    # Segunda tentativa: se tag comecar com v, tenta sem o prefixo v
    if [[ "${IMAGE_TAG:-}" =~ ^v[0-9] ]]; then
        local fallback_tag="${IMAGE_TAG#v}"
        log_warn "Pull falhou para tag ${IMAGE_TAG}. Tentando tag ${fallback_tag}..."
        upsert_env "IMAGE_TAG" "$fallback_tag" "$ENV_PRODUCTION"
        IMAGE_TAG="$fallback_tag"
        if "${compose_cmd[@]}" "${compose_base[@]}" pull; then
            if "${compose_cmd[@]}" "${compose_base[@]}" up -d; then
                return 0
            fi
            print_stack_diagnostics
            log_warn "Tag ${fallback_tag} foi baixada, mas os containers nao ficaram saudaveis."
        fi
    fi

    log_warn "Imagem nao encontrada no registry. Iniciando build local..."
    "${compose_cmd[@]}" "${compose_build[@]}" build backend frontend
    if ! "${compose_cmd[@]}" "${compose_build[@]}" up -d; then
        print_stack_diagnostics
        return 1
    fi
}

# --- Certificado Let's Encrypt (copiado de install/install.sh) ---
obtain_letsencrypt_cert() {
    local domain="$1"
    local email="$2"
    mkdir -p "$NGINX_WEBROOT"
    log_info "Obtendo certificado Let's Encrypt para $domain ..."
    # Tentar primeiro com --test-cert para nao queimar limite se houver erro de DNS/Porta
    log_info "Testando conexao para Let's Encrypt (staging)..."
    if docker run --rm \
        -v "${NGINX_WEBROOT}:/var/www/certbot:rw" \
        -v "${NGINX_CERTS_DIR}:/etc/letsencrypt:rw" \
        certbot/certbot certonly --webroot \
        -w /var/www/certbot \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --test-cert \
        --non-interactive; then
        
        log_info "Teste de staging OK. Solicitando certificado real..."
        if docker run --rm \
            -v "${NGINX_WEBROOT}:/var/www/certbot:rw" \
            -v "${NGINX_CERTS_DIR}:/etc/letsencrypt:rw" \
            certbot/certbot certonly --webroot \
            -w /var/www/certbot \
            -d "$domain" \
            --email "$email" \
            --agree-tos \
            --force-renewal \
            --non-interactive; then
            log_info "Certificado real obtido com sucesso."
        fi
        
        local live_cert="$NGINX_CERTS_DIR/live/$domain/fullchain.pem"
        local live_key="$NGINX_CERTS_DIR/live/$domain/privkey.pem"
        if [[ -f "$live_cert" ]] && [[ -f "$live_key" ]]; then
            cp "$live_cert" "$NGINX_CERTS_DIR/cert.pem"
            cp "$live_key" "$NGINX_CERTS_DIR/key.pem"
            log_info "Certificado Let's Encrypt instalado em nginx/certs/"
            cd "$PROJECT_ROOT"
            docker compose --env-file "$ENV_PRODUCTION" -f docker-compose.prod.yml restart nginx 2>/dev/null || true
            return 0
        fi
    fi
    log_warn "Nao foi possivel obter certificado Let's Encrypt (verifique DNS e porta 80). Mantido certificado autoassinado."
    return 1
}

# --- Ensure env file para producao (adaptado de install/install.sh) ---
ensure_production_env_file() {
    if [[ ! -f "$ENV_PRODUCTION" ]]; then
        if [[ -f "$ENV_INSTALLER_EXAMPLE" ]]; then
            cp "$ENV_INSTALLER_EXAMPLE" "$ENV_PRODUCTION"
            log_info "Arquivo de producao criado: $INSTALLER_ROOT/.env.production"
        elif [[ -f "$ENV_EXAMPLE" ]]; then
            cp "$ENV_EXAMPLE" "$ENV_PRODUCTION"
            log_info "Arquivo de producao criado: $INSTALLER_ROOT/.env.production"
        else
            log_error "Nenhum .env.example ou .env.installer.example encontrado."
            exit 1
        fi
    fi
}

# =============================================================================
# Funcao principal de instalacao Docker VPS
# Logica extraida de run_install() em install/install.sh sem modificacao.
# Recebe parametros ja validados pelo menu.
# =============================================================================
run_docker_vps_install() {
    local domain="$1"
    local email="$2"
    local build_mode="$3"  # "local" ou "registry"

    local image_owner="${IMAGE_OWNER:-}"
    local image_repo="${IMAGE_REPO:-projeto-menu-multitenant-seguro}"
    local image_tag="${IMAGE_TAG:-latest}"
    local local_build_only="false"
    local admin_email="${INSTALL_ADMIN_EMAIL:-$email}"
    local admin_pass="${INSTALL_ADMIN_PASSWORD:-123456}"
    local no_prompt="${INSTALL_NO_PROMPT:-false}"
    local clean_install="${CLEAN_INSTALL:-false}"

    if [[ "$build_mode" == "local" ]]; then
        local_build_only="true"
    fi

    if [[ "$no_prompt" != "true" ]]; then
        if [[ -z "$image_owner" && "$local_build_only" != "true" ]]; then
            read -p "GHCR owner (ex: org/user): " image_owner
        fi
        [[ -z "$image_repo" ]] && read -p "Image repo prefix [projeto-menu-multitenant-seguro]: " image_repo
        image_repo="${image_repo:-projeto-menu-multitenant-seguro}"
        [[ -z "$image_tag" ]] && image_tag="latest"
        [[ -z "$admin_email" ]] && admin_email="$email"
        read -sp "Senha inicial do admin [123456]: " admin_pass
        echo
        admin_pass="${admin_pass:-123456}"
    fi

    if [[ -z "$image_owner" && "$local_build_only" != "true" ]]; then
        image_owner="$(resolve_image_owner)"
    fi

    if [[ "$local_build_only" != "true" && -z "$image_owner" ]]; then
        log_error "IMAGE_OWNER e obrigatorio quando LOCAL_BUILD_ONLY=false."
        exit 1
    fi
    validate_email "$email"
    [[ -n "$admin_email" ]] && validate_email "$admin_email"

    image_owner="${image_owner:-local-build}"
    image_owner="$(echo "$image_owner" | tr '[:upper:]' '[:lower:]')"
    image_repo="$(echo "$image_repo" | tr '[:upper:]' '[:lower:]')"
    local_build_only="$(echo "$local_build_only" | tr '[:upper:]' '[:lower:]')"
    LOCAL_BUILD_ONLY="$local_build_only"
    ensure_production_env_file

    # Limpar volumes se solicitado
    if [[ "$clean_install" == "true" ]]; then
        log_warn "Limpeza solicitada: removendo containers e volumes existentes..."
        cd "$PROJECT_ROOT"
        docker compose --env-file "$ENV_PRODUCTION" -f docker-compose.prod.yml down -v 2>/dev/null || true
        log_info "Volumes removidos. Iniciando instalacao limpa..."
    fi

    # Gerar prefixo baseado no dominio
    local domain_prefix=$(echo "$domain" | sed 's/\..*//')
    if [[ "$domain" == *"."* ]]; then
        domain_prefix=$(echo "$domain" | cut -d'.' -f1,2 | tr -d '.')
    fi
    domain_prefix=$(echo "$domain_prefix" | tr -cd '[:alnum:]' | cut -c1-16 | tr '[:upper:]' '[:lower:]')
    
    # Secrets gerados se nao fornecidos
    local db_name="${DB_NAME:-db_${domain_prefix}}"
    local db_user="${DB_USER:-us_${domain_prefix}}"
    local db_pass="${DB_PASSWORD:-$(openssl rand -hex 16)}"
    local jwt_secret="${JWT_SECRET:-$(openssl rand -hex 32)}"
    local enc_key="${ENCRYPTION_KEY:-$(openssl rand -hex 32)}"

    log_info "Configurando .env..."
    upsert_env "DOMAIN" "$domain" "$ENV_PRODUCTION"
    upsert_env "LETSENCRYPT_EMAIL" "$email" "$ENV_PRODUCTION"
    upsert_env "LETSENCRYPT_HOST" "$domain" "$ENV_PRODUCTION"
    upsert_env "VIRTUAL_HOST" "$domain" "$ENV_PRODUCTION"
    upsert_env "IMAGE_OWNER" "$image_owner" "$ENV_PRODUCTION"
    upsert_env "IMAGE_REPO" "$image_repo" "$ENV_PRODUCTION"
    upsert_env "IMAGE_TAG" "$image_tag" "$ENV_PRODUCTION"
    upsert_env "LOCAL_BUILD_ONLY" "$local_build_only" "$ENV_PRODUCTION"
    upsert_env "FRONTEND_URL" "https://$domain" "$ENV_PRODUCTION"
    upsert_env "NEXT_PUBLIC_API_URL" "https://$domain/api" "$ENV_PRODUCTION"
    upsert_env "DB_USER" "$db_user" "$ENV_PRODUCTION"
    upsert_env "DB_PASSWORD" "$db_pass" "$ENV_PRODUCTION"
    upsert_env "DB_NAME" "$db_name" "$ENV_PRODUCTION"
    upsert_env "DATABASE_URL" "postgresql://$db_user:$db_pass@db:5432/$db_name?schema=public" "$ENV_PRODUCTION"
    upsert_env "JWT_SECRET" "$jwt_secret" "$ENV_PRODUCTION"
    upsert_env "ENCRYPTION_KEY" "$enc_key" "$ENV_PRODUCTION"
    upsert_env "REQUIRE_SECRET_MANAGER" "false" "$ENV_PRODUCTION"
    upsert_env "NODE_ENV" "production" "$ENV_PRODUCTION"
    upsert_env "PORT" "4000" "$ENV_PRODUCTION"
    upsert_env "INSTALL_DOMAIN" "$domain" "$ENV_PRODUCTION"
    upsert_env "INSTALL_ADMIN_EMAIL" "${admin_email:-$email}" "$ENV_PRODUCTION"
    upsert_env "INSTALL_ADMIN_PASSWORD" "$admin_pass" "$ENV_PRODUCTION"

    # Criar .env em apps/backend e .env.local em apps/frontend
    local BACKEND_ENV="$PROJECT_ROOT/apps/backend/.env"
    local FRONTEND_ENV="$PROJECT_ROOT/apps/frontend/.env.local"
    local BACKEND_EXAMPLE="$PROJECT_ROOT/apps/backend/.env.example"
    local FRONTEND_EXAMPLE="$PROJECT_ROOT/apps/frontend/.env.local.example"
    if [[ -f "$BACKEND_EXAMPLE" ]]; then
        if [[ ! -f "$BACKEND_ENV" ]]; then
            cp "$BACKEND_EXAMPLE" "$BACKEND_ENV"
            log_info "Criado apps/backend/.env a partir de .env.example"
        fi
        upsert_env "DATABASE_URL" "postgresql://$db_user:$db_pass@db:5432/$db_name?schema=public" "$BACKEND_ENV"
        upsert_env "JWT_SECRET" "$jwt_secret" "$BACKEND_ENV"
        upsert_env "ENCRYPTION_KEY" "$enc_key" "$BACKEND_ENV"
        upsert_env "FRONTEND_URL" "https://$domain" "$BACKEND_ENV"
        upsert_env "PORT" "4000" "$BACKEND_ENV"
        upsert_env "NODE_ENV" "production" "$BACKEND_ENV"
        upsert_env "INSTALL_ADMIN_EMAIL" "${admin_email:-$email}" "$BACKEND_ENV"
        upsert_env "INSTALL_ADMIN_PASSWORD" "$admin_pass" "$BACKEND_ENV"
    fi
    if [[ -f "$FRONTEND_EXAMPLE" ]]; then
        if [[ ! -f "$FRONTEND_ENV" ]]; then
            cp "$FRONTEND_EXAMPLE" "$FRONTEND_ENV"
            log_info "Criado apps/frontend/.env.local a partir de .env.local.example"
        fi
        upsert_env "NEXT_PUBLIC_API_URL" "https://$domain/api" "$FRONTEND_ENV"
    fi

    # Nginx embutido (docker-compose.prod.yml): criar dirs, cert e config
    if [[ -f "$COMPOSE_PROD" ]]; then
        mkdir -p "$NGINX_CONF_DIR" "$NGINX_CERTS_DIR" "$NGINX_WEBROOT"
        # Certificado autoassinado para HTTPS
        if [[ ! -f "$NGINX_CERTS_DIR/cert.pem" ]] || [[ ! -f "$NGINX_CERTS_DIR/key.pem" ]]; then
            log_info "Gerando certificado autoassinado para HTTPS em $NGINX_CERTS_DIR"
            if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$NGINX_CERTS_DIR/key.pem" \
                -out "$NGINX_CERTS_DIR/cert.pem" \
                -subj "/CN=$domain" 2>/dev/null; then
                log_info "Certificado autoassinado criado. Para producao, substitua por Let's Encrypt."
            fi
        fi
        # Template Docker: upstream frontend:5000, backend:4000
        local NGINX_HTTP_ONLY="$INSTALL2_DIR/nginx-docker-http-only.conf.template"
        if [[ -f "$NGINX_TEMPLATE_DOCKER" ]] && [[ -f "$NGINX_CERTS_DIR/cert.pem" ]]; then
            sed "s/__DOMAIN__/$domain/g" "$NGINX_TEMPLATE_DOCKER" > "$NGINX_CONF_DIR/default.conf"
            log_info "Config Nginx gerado (HTTP + HTTPS) em $NGINX_CONF_DIR/default.conf"
        elif [[ -f "$NGINX_TEMPLATE_DOCKER" ]]; then
            if [[ -f "$NGINX_HTTP_ONLY" ]]; then
                sed "s/__DOMAIN__/$domain/g" "$NGINX_HTTP_ONLY" > "$NGINX_CONF_DIR/default.conf"
                log_info "Config Nginx gerado (apenas HTTP) em $NGINX_CONF_DIR/default.conf"
            else
                sed "s/__DOMAIN__/$domain/g" "$NGINX_TEMPLATE_DOCKER" > "$NGINX_CONF_DIR/default.conf"
            fi
        elif [[ -f "$NGINX_TEMPLATE_ACME" ]]; then
            sed "s/__DOMAIN__/$domain/g" "$NGINX_TEMPLATE_ACME" > "$NGINX_CONF_DIR/default.conf"
            log_warn "Usando template ACME; no Docker use nginx-docker.conf.template para evitar 502."
        else
            log_warn "Nenhum template nginx encontrado. Configure manualmente $NGINX_CONF_DIR/default.conf"
        fi
    fi

    log_info "Subindo stack (docker-compose.prod.yml) com $INSTALLER_ROOT/.env.production..."
    cd "$PROJECT_ROOT"
    pull_or_build_stack

    # Tentar obter certificado Let's Encrypt
    sleep 5
    if obtain_letsencrypt_cert "$domain" "$email"; then
        echogreen "Certificado SSL valido (Let's Encrypt) instalado."
    fi

    # Aguardar inicializacao completa do sistema
    log_info "Aguardando inicializacao completa do sistema..."
    sleep 10

    # Relatorio Final de Credenciais
    echo -e "\n\n"
    echoblue "=========================================================="
    echoblue "      RELATORIO FINAL DE INSTALACAO - MULTITENANT         "
    echoblue "=========================================================="
    echo -e "\n"
    
    echo -e "\033[1;32mACESSO AO SISTEMA:\033[0m"
    echo -e "   URL Principal:  https://$domain"
    echo -e "   API Endpoint:   https://$domain/api"
    echo -e "\n"

    echo -e "\033[1;32mCREDENCIAIS DO ADMINISTRADOR:\033[0m"
    echo -e "   Email:          $admin_email"
    echo -e "   Senha:          $admin_pass"
    echo -e "   Nivel:          SUPER_ADMIN"
    echo -e "\n"

    echo -e "\033[1;32mBANCO DE DADOS (PostgreSQL):\033[0m"
    echo -e "   Host:           db (interno) / localhost (se exposto)"
    echo -e "   Porta:          5432"
    echo -e "   Banco:          $db_name"
    echo -e "   Usuario:        $db_user"
    echo -e "   Senha:          $db_pass"
    echo -e "\n"

    echo -e "\033[1;32mCACHE (Redis):\033[0m"
    echo -e "   Host:           redis"
    echo -e "   Porta:          6379"
    echo -e "\n"

    echo -e "\033[1;32mSEGREDOS DO SISTEMA:\033[0m"
    echo -e "   JWT_SECRET:     $jwt_secret"
    echo -e "   ENCRYPTION_KEY: $enc_key"
    echo -e "\n"

    echoblue "=========================================================="
    log_info "Guarde estas informacoes em local seguro!"
    log_info "Arquivo de configuracao: $INSTALLER_ROOT/.env.production"
    echogreen "Instalacao concluida com sucesso!"
    echo -e "\n"
}
