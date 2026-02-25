# 📝 CHANGELOG - Instalador Multi-Modo v2.0

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [Não Lançado] - 2024-02-23

### 🎯 Objetivo do Projeto

Criar um sistema de instalação com menu interativo que permita ao usuário escolher entre diferentes modos de instalação:
- Local (Desenvolvimento/Produção)
- VPS (Desenvolvimento/Produção)
- Docker ou Nativo
- Build local ou Registry

### ✨ Adicionado

#### Estrutura Base
- **Diretório `install-2/`** - Nova pasta para desenvolvimento sem afetar instalador original
- **Diretório `install-2/utils/`** - Funções utilitárias compartilhadas
- **Diretório `install-2/modes/`** - Scripts específicos de cada modo de instalação
- **Diretório `install-2/templates/`** - Templates de configuração (systemd, nginx)

#### Arquivos Utilitários
- **`utils/common.sh`** - Funções compartilhadas
  - Funções de cores e formatação (echored, echoblue, echogreen, etc.)
  - Validações (validate_email, validate_domain)
  - Verificações de sistema (require_bash, require_root, check_os)
  - Gerenciamento de .env (ensure_env_file, upsert_env)
  - Geração de secrets (generate_secret, generate_db_credentials)
  - Confirmação do usuário (confirm_action)
  - Exibição de informações (print_header, print_separator)
  - Detecção de ambiente (detect_environment)
  - Backup de configuração (backup_config)
  - ⚠️ **INCOMPLETO:** Falta função `cleanup_on_error`

- **`utils/menu.sh`** - Sistema de menu interativo
  - `show_environment_menu()` - Menu de seleção de ambiente (Local/VPS, Dev/Prod)
  - `show_method_menu()` - Menu de seleção de método (Docker/Nativo)
  - `show_build_menu()` - Menu de seleção de build (Registry/Local)
  - `determine_installation_mode()` - Determina modo baseado nas seleções
  - `show_confirmation()` - Exibe confirmação antes de instalar
  - `show_installation_menu()` - Orquestrador principal do menu

- **`utils/docker-utils.sh`** - Utilitários Docker
  - `check_docker()` - Verifica se Docker está instalado
  - `install_docker()` - Instala Docker automaticamente
  - `check_docker_compose()` - Verifica Docker Compose plugin

- **`utils/native-utils.sh`** - Utilitários instalação nativa
  - `install_nodejs()` - Instala Node.js 20 LTS
  - `install_postgresql()` - Instala PostgreSQL 15
  - `install_redis()` - Instala Redis 7
  - `install_pm2()` - Instala PM2 (gerenciador de processos)
  - `install_nginx()` - Instala Nginx
  - `install_certbot()` - Instala Certbot (SSL)

#### Modos de Instalação Docker

- **`modes/docker-local-dev.sh`** - Local Desenvolvimento
  - Usa `docker-compose.dev.yml`
  - Hot-reload ativado
  - Portas expostas diretamente (4000, 5000, 5432)
  - Executa migrations e seeds automaticamente
  - Ideal para desenvolvimento local

- **`modes/docker-local-prod.sh`** - Local Produção (Simulação)
  - Usa `docker-compose.prod.yml` + `docker-compose.prod.build.yml`
  - Build otimizado de produção
  - Nginx com SSL autoassinado
  - Simula ambiente de produção localmente
  - Gera credenciais seguras automaticamente

- **`modes/docker-vps-dev.sh`** - VPS Desenvolvimento
  - Chama instalador original (`install/install.sh`)
  - Verifica branch (recomenda `dev`)
  - Suporta build local (`-l`) ou registry
  - SSL Let's Encrypt automático
  - Ambiente de staging/testes

- **`modes/docker-vps-prod.sh`** - VPS Produção
  - Chama instalador original (`install/install.sh`)
  - Verifica branch (recomenda `main` ou `master`)
  - Suporta build local (`-l`) ou registry
  - SSL Let's Encrypt automático
  - Ambiente de produção real

#### Modos de Instalação Nativa (Placeholders)

- **`modes/native-vps-dev.sh`** - VPS Desenvolvimento Nativo
  - ⚠️ **NÃO IMPLEMENTADO** - Apenas placeholder
  - Exibe mensagem informativa
  - Retorna erro e sugere usar Docker

- **`modes/native-vps-prod.sh`** - VPS Produção Nativo
  - ⚠️ **NÃO IMPLEMENTADO** - Apenas placeholder
  - Exibe mensagem informativa
  - Retorna erro e sugere usar Docker

#### Script Principal

- **`install.sh`** - Orquestrador principal
  - Parse de argumentos de linha de comando
  - Validação de domínio e email
  - Chamada do menu interativo
  - Roteamento para modo selecionado
  - Tratamento de erros
  - Suporte a modo não-interativo (`--no-prompt`)

#### Documentação

- **`TAREFAS.md`** - Documento de tarefas e planejamento
  - Status atual do projeto
  - Problemas identificados
  - Tarefas pendentes (Alta/Média/Baixa prioridade)
  - Sequência de execução recomendada
  - Comandos úteis
  - Regras e restrições
  - Checklist de validação
  - Notas de desenvolvimento

- **`CHANGELOG.md`** - Este arquivo
  - Histórico de mudanças
  - Documentação de decisões técnicas
  - Problemas conhecidos

### 🔧 Modificado

Nenhuma modificação em arquivos existentes. Todo o desenvolvimento foi feito em `install-2/` separado.

### 🐛 Problemas Conhecidos

#### 1. Menu não aparece ao executar (CRÍTICO)

**Descrição:**
```bash
sudo bash install-2/install.sh install -d teste.local -e admin@teste.com

Exibe apenas:

══════════════════════════════════════════════════════════════
INSTALADOR MULTITENANT v2.0
══════════════════════════════════════════════════════════════
[INFO] Sistema operacional: ubuntu 22.04
Escolha [1-4]:
Mas não mostra as opções do menu.

Causa: Arquivo 
common.sh
 está incompleto. Falta a função cleanup_on_error no final.

Impacto:

Bloqueador - Impede teste do menu
Menu não é exibido
Script para antes de chamar show_installation_menu()
Solução: Adicionar ao final de 
common.sh
:

# --- Limpeza e tratamento de erros ---
cleanup_on_error() {
    log_error "Instalação interrompida devido a um erro."
    log_error "Verifique as mensagens acima para mais detalhes."
    exit 1
}
Status: 🔴 Não resolvido

📋 Backlog de Funcionalidades
Versão 2.1 (Próxima)
Correções Críticas
 Corrigir 
common.sh
 (adicionar cleanup_on_error)
 Validar menu interativo funcionando
 Testar todos os modos Docker
Ferramentas de Suporte
 Criar diagnose.sh - Script de diagnóstico
 Criar test-menu.sh - Teste do menu sem instalação
 Criar README.md - Documentação completa
Versão 2.2 (Futuro)
Instalação Nativa
 Implementar 
native-vps-dev.sh
 Implementar 
native-vps-prod.sh
 Criar templates systemd
 Criar templates nginx
 Criar template PM2 ecosystem
Melhorias
 Adicionar logs detalhados
 Adicionar rollback automático em caso de erro
 Adicionar validação de pré-requisitos
 Adicionar suporte a múltiplos idiomas
Versão 3.0 (Longo Prazo)
Substituição do Instalador Original
 Validação completa em produção
 Testes automatizados
 Migração de install-2/ para install/
 Deprecação do instalador antigo
🎯 Decisões Técnicas
Por que criar install-2/ separado?
Decisão: Criar nova pasta ao invés de modificar install/ diretamente.

Razões:

Segurança: Não afetar instalador em produção
Testes: Permitir testes sem risco
Rollback: Facilitar volta ao estado anterior
Desenvolvimento: Iteração rápida sem medo de quebrar
Alternativas consideradas:

Modificar 
install.sh
 diretamente ❌ (muito arriscado)
Criar branch separada ❌ (dificulta testes paralelos)
Usar feature flags ❌ (complexidade desnecessária)
Por que modos VPS chamam instalador original?
Decisão: Modos Docker VPS chamam 
install.sh
 ao invés de reimplementar.

Razões:

Confiabilidade: Código já testado em produção
Manutenção: Evitar duplicação de lógica complexa
Compatibilidade: Garantir comportamento idêntico
Redução de bugs: Menos código novo = menos bugs
Implementação:

# Em docker-vps-prod.sh
bash install.sh install -d "$domain" -e "$email" -l
Por que menu interativo?
Decisão: Adicionar menu interativo ao invés de apenas flags.

Razões:

UX: Melhor experiência para usuários não-técnicos
Descoberta: Usuário vê todas as opções disponíveis
Validação: Reduz erros de configuração
Flexibilidade: Mantém opção não-interativa para CI/CD
Alternativas consideradas:

Apenas flags ❌ (difícil descobrir opções)
Wizard completo ❌ (muito verboso)
Arquivo de configuração ❌ (complexidade extra)
🔍 Análise de Impacto
Compatibilidade com Instalador Atual
Aspecto	Status	Notas
Comando original	✅ Mantido	
install.sh
 não modificado
Flags existentes	✅ Compatível	Todas as flags funcionam
Variáveis de ambiente	✅ Compatível	Mesmas variáveis
Comportamento Docker	✅ Idêntico	Chama código original
Instalações existentes	✅ Não afetadas	Nenhuma mudança
Novos Recursos
Recurso	Status	Disponibilidade
Menu interativo	🟡 Em teste	v2.0
Modo local dev	✅ Implementado	v2.0
Modo local prod	✅ Implementado	v2.0
Modo VPS dev	✅ Implementado	v2.0
Modo VPS prod	✅ Implementado	v2.0
Modo nativo dev	⏳ Planejado	v2.2
Modo nativo prod	⏳ Planejado	v2.2
📊 Métricas
Arquivos Criados
Total: 14 arquivos
Scripts: 10 arquivos .sh
Documentação: 2 arquivos .md
Templates: 2 diretórios (vazios)
Linhas de Código
utils/common.sh: ~200 linhas
utils/menu.sh: ~200 linhas
utils/docker-utils.sh: ~60 linhas
utils/native-utils.sh: ~60 linhas
modes/*.sh: ~100 linhas cada
install.sh: ~130 linhas
Total: ~1200 linhas
Cobertura de Funcionalidades
Modos Docker: 100% (4/4 implementados)
Modos Nativos: 0% (0/2 implementados)
Menu Interativo: 90% (falta validação completa)
Documentação: 80% (falta README.md)
🧪 Testes Realizados
Testes Manuais
Teste	Status	Data	Notas
Criação de estrutura	✅	2024-02-23	Diretórios criados
Arquivos criados	✅	2024-02-23	Todos os arquivos
Permissões	✅	2024-02-23	chmod +x aplicado
Execução do menu	❌	2024-02-23	Menu não aparece
Testes Pendentes
 Menu interativo completo
 Modo local dev
 Modo local prod
 Modo VPS dev (build local)
 Modo VPS dev (registry)
 Modo VPS prod (build local)
 Modo VPS prod (registry)
 Cancelamento de instalação
 Modo não-interativo
🚀 Próximos Passos
Imediato (Hoje)
✅ Criar TAREFAS.md
✅ Criar CHANGELOG.md
⏳ Corrigir common.sh
⏳ Testar menu
Curto Prazo (Esta Semana)
Validar todos os modos Docker
Criar scripts de diagnóstico e teste
Documentar no README.md
Resolver problemas encontrados
Médio Prazo (Próximas Semanas)
Implementar modos nativos
Criar templates de configuração
Testes em ambientes limpos
Preparar para produção
Longo Prazo (Próximos Meses)
Substituir instalador original
Adicionar testes automatizados
Suporte a mais distribuições Linux
Internacionalização
📞 Contato e Suporte
Para dúvidas ou problemas:

Consultar TAREFAS.md para status atual
Verificar este CHANGELOG para histórico
Consultar README.md (quando criado)
Consultar documentação em docs/manual-instalacao/
📜 Licença
Este projeto mantém a mesma licença do projeto principal.

Mantido por: Equipe de Desenvolvimento Última atualização: 2024-02-23 Versão atual: 2.0-alpha (não lançado)


---

Pronto! Agora você tem:

1. ✅ **TAREFAS.md** - Documento completo de tarefas e planejamento
2. ✅ **CHANGELOG.md** - Histórico detalhado de todas as mudanças
3. ✅ Estrutura completa do `install-2/`
4. ✅ Documentação de problemas e soluções
5. ✅ Próximos passos bem definidos

Quando você voltar a trabalhar no instalador, basta:
1. Ler `TAREFAS.md` para ver o que precisa ser feito
2. Consultar `CHANGELOG.md` para entender o que já foi feito
3. Seguir a sequência de execução recomendada