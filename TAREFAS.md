# TAREFAS - Instalador Multi-Modo v2.0

## STATUS ATUAL

### Concluido (Fase 1 - Estrutura Base)

1. Estrutura de diretorios criada
   - `install-2/utils/` - Funcoes utilitarias
   - `install-2/modes/` - Scripts de modos de instalacao
   - `install-2/templates/` - Templates de configuracao

2. Arquivos utilitarios base criados
   - `utils/common.sh` - Funcoes compartilhadas (incluindo `cleanup_on_error`)
   - `utils/menu.sh` - Sistema de menu interativo
   - `utils/docker-utils.sh` - Utilitarios Docker (verificacao e instalacao basica)
   - `utils/native-utils.sh` - Utilitarios instalacao nativa

3. Modos Docker criados (precisam revisao - ver Tarefa 1.1)
   - `modes/docker-local-dev.sh` - Local desenvolvimento (logica propria)
   - `modes/docker-local-prod.sh` - Local producao (logica propria)
   - `modes/docker-vps-dev.sh` - VPS desenvolvimento (PROBLEMA: delega para `install/install.sh`)
   - `modes/docker-vps-prod.sh` - VPS producao (PROBLEMA: delega para `install/install.sh`)

4. Script principal criado
   - `install.sh` - Orquestrador com menu interativo

5. Modos nativos (placeholders)
   - `modes/native-vps-dev.sh` - Placeholder (nao implementado)
   - `modes/native-vps-prod.sh` - Placeholder (nao implementado)

---

## REGRAS E RESTRICOES

### O QUE PODE SER FEITO

- **Modificar arquivos em `install-2/`**
  - Todos os arquivos nesta pasta sao novos e podem ser editados livremente
  - Nao afeta o instalador original em `install/`

- **Trazer logica Docker para dentro de `install-2/`**
  - `install-2/` deve ser **autossuficiente** -- nao deve chamar `install/install.sh`
  - Os metodos de instalacao Docker do instalador original (compose up, pull/build,
    config .env, nginx, SSL, etc.) devem ser incorporados em `install-2/` como
    funcoes utilitarias (ex: em `utils/docker-install.sh` ou similar)
  - A logica Docker trazida **nao deve ser modificada** -- deve funcionar
    exatamente como funciona no instalador original
  - O que muda e **apenas a interface**: menu interativo, roteamento, UX

- **Alterar a forma como o menu chama a instalacao Docker**
  - O menu interativo, o roteamento e a interface de selecao podem ser ajustados
  - A logica de como `install-2/install.sh` invoca os modos pode ser reestruturada

- **Adicionar novos modos**
  - Criar novos scripts em `modes/`
  - Adicionar cases no `install-2/install.sh`
  - Atualizar menu em `utils/menu.sh`

- **Criar ferramentas auxiliares**
  - Scripts de teste, diagnostico, documentacao

### O QUE NAO PODE SER FEITO

- **NAO modificar o instalador original (`install/install.sh` e demais scripts em `install/`)**
  - Este e o instalador em producao
  - Qualquer mudanca pode quebrar instalacoes existentes
  - So deve ser alterado apos validacao completa do novo instalador

- **NAO modificar os metodos de instalacao Docker**
  - A logica de instalacao Docker que ja funciona no instalador original
    (pull_or_build_stack, obtain_letsencrypt_cert, config nginx, config .env,
    check_and_open_ports, etc.) **funciona bem e nao precisa de ajuste**
  - Ao trazer essa logica para `install-2/`, ela deve ser copiada/incorporada
    **sem alteracoes funcionais** -- apenas reorganizada em modulos
  - **Nao reescrever, nao "melhorar", nao refatorar** esses metodos

- **NAO delegar para `install/install.sh`**
  - Os modos VPS Docker de `install-2/` **nao devem chamar** `install/install.sh`
  - `install-2/` deve ser independente e autossuficiente
  - Toda a logica necessaria deve existir dentro de `install-2/`

- **NAO quebrar compatibilidade**
  - Comando original `bash install/install.sh install ...` deve continuar funcionando
    independentemente (ele nao e tocado)
  - Flags existentes devem ser respeitadas no novo instalador tambem
  - Variaveis de ambiente mantidas

---

## TAREFAS PENDENTES

### Prioridade ALTA

#### Tarefa 1.1: Tornar install-2 autossuficiente (eliminar dependencia de install/)

Os scripts `modes/docker-vps-dev.sh` e `modes/docker-vps-prod.sh` atualmente
chamam `bash install/install.sh install ...`. Isso precisa ser corrigido.

- [ ] Criar `utils/docker-install.sh` com as funcoes de instalacao Docker
      trazidas do instalador original (`install/install.sh`), sem modificar a logica:
  - `pull_or_build_stack()` - pull de imagens ou build local
  - `obtain_letsencrypt_cert()` - certificado Let's Encrypt
  - `check_and_open_ports()` - verificacao de portas 80/443
  - `resolve_image_owner()` - resolver owner de imagem GHCR
  - Configuracao de .env de producao (upsert de variaveis)
  - Configuracao de nginx (gerar default.conf a partir de template)
  - Geracao de certificado autoassinado
  - Configuracao de .env do backend e frontend
  - Relatorio final de credenciais
- [ ] Copiar templates nginx necessarios para `install-2/`:
  - `nginx-docker.conf.template`
  - `nginx-docker-http-only.conf.template`
- [ ] Copiar `.env.installer.example` para `install-2/` (se nao existir)
- [ ] Reescrever `modes/docker-vps-dev.sh` para usar funcoes de `utils/docker-install.sh`
      ao inves de chamar `install/install.sh`
- [ ] Reescrever `modes/docker-vps-prod.sh` para usar funcoes de `utils/docker-install.sh`
      ao inves de chamar `install/install.sh`
- [ ] Verificar que `modes/docker-local-dev.sh` e `modes/docker-local-prod.sh`
      tambem nao dependem de nada em `install/`

#### Tarefa 1.2: Validar que o menu interativo funciona corretamente
- [ ] Executar: `sudo bash install-2/install.sh install -d teste.local -e admin@teste.com`
- [ ] Verificar se o menu de ambiente aparece (opcoes 1-4)
- [ ] Testar navegacao entre menus (ambiente -> metodo -> build -> confirmacao)
- [ ] Testar confirmacao final e cancelamento

#### Tarefa 1.3: Validar modos Docker
- [ ] Testar modo Local Desenvolvimento: containers sobem, hot-reload, migrations, seeds
- [ ] Testar modo Local Producao: build otimizado, Nginx, certificado autoassinado
- [ ] Testar modo VPS Desenvolvimento (build local e registry) -- agora usando funcoes internas
- [ ] Testar modo VPS Producao (build local e registry) -- agora usando funcoes internas
- [ ] Confirmar que o comportamento final e identico ao do instalador original

### Prioridade MEDIA

#### Tarefa 2.1: Criar script de diagnostico (`diagnose.sh`)
- [ ] Verificar existencia de todos os arquivos necessarios em `install-2/`
- [ ] Verificar permissoes de execucao
- [ ] Verificar carregamento das funcoes de `common.sh`, `menu.sh`, `docker-install.sh`
- [ ] Verificar templates nginx e .env.installer.example

#### Tarefa 2.2: Criar script de teste do menu (`test-menu.sh`)
- [ ] Permitir teste do menu sem sudo e sem instalacao real
- [ ] Exibir modo selecionado ao final sem executar nada

#### Tarefa 2.3: Documentacao
- [ ] Criar README.md com instrucoes de uso
- [ ] Documentar cada modo de instalacao
- [ ] Criar guia de troubleshooting
- [ ] Adicionar exemplos de uso

### Prioridade BAIXA (Futuro)

#### Tarefa 3.1: Implementar instalacao nativa
- [ ] Implementar `native-vps-dev.sh` (Node.js 20, PostgreSQL 15, Redis 7, PM2, Nginx, Certbot, systemd)
- [ ] Implementar `native-vps-prod.sh` (mesma base + hardening + otimizacoes de producao)

#### Tarefa 3.2: Templates de configuracao
- [ ] Criar `multitenant-backend.service` (systemd)
- [ ] Criar `multitenant-frontend.service` (systemd)
- [ ] Criar `nginx-native.conf.template`
- [ ] Criar template PM2 ecosystem

#### Tarefa 3.3: Testes automatizados
- [ ] Criar suite de testes para cada modo
- [ ] Testar em Ubuntu 22.04 e Debian 11 limpos
- [ ] Validar rollback em caso de erro

---

## SEQUENCIA DE EXECUCAO RECOMENDADA

### Fase 1: Autossuficiencia e Validacao (ATUAL)
1. Tornar install-2 autossuficiente (Tarefa 1.1) -- **BLOQUEADOR**
2. Validar menu interativo (Tarefa 1.2)
3. Validar todos os modos Docker (Tarefa 1.3)

### Fase 2: Ferramentas de Suporte
1. Criar script de diagnostico (Tarefa 2.1)
2. Criar script de teste do menu (Tarefa 2.2)
3. Documentacao basica (Tarefa 2.3)

### Fase 3: Instalacao Nativa (Futuro)
1. Implementar modo nativo dev/prod (Tarefa 3.1)
2. Criar templates (Tarefa 3.2)
3. Testes completos (Tarefa 3.3)

---

## REFERENCIA: Funcoes do instalador original a incorporar

As seguintes funcoes de `install/install.sh` devem ser trazidas para
`install-2/utils/docker-install.sh` **sem modificacao de logica**:

| Funcao                     | Descricao                                        |
|----------------------------|--------------------------------------------------|
| `resolve_image_owner()`    | Infere owner GHCR a partir do git remote         |
| `pull_or_build_stack()`    | Pull de imagens ou fallback para build local      |
| `obtain_letsencrypt_cert()`| Obtem certificado Let's Encrypt via certbot       |
| `check_and_open_ports()`   | Verifica/libera portas 80 e 443                  |
| Bloco de config `.env`     | Upsert de todas as variaveis de producao         |
| Bloco de config nginx      | Gera default.conf a partir de template           |
| Bloco de config apps       | Cria .env do backend e .env.local do frontend    |
| Bloco de relatorio final   | Exibe credenciais e URLs apos instalacao         |

---

## COMANDOS UTEIS

```bash
# Verificar estrutura
ls -lR install-2/

# Testar carregamento de scripts
bash -c "source install-2/utils/common.sh && echo 'common.sh OK'"
bash -c "source install-2/utils/menu.sh && echo 'menu.sh OK'"

# Verificar funcoes definidas
bash -c "source install-2/utils/common.sh && declare -F | grep -E '(log_|print_|validate_|cleanup_)'"
bash -c "source install-2/utils/menu.sh && declare -F | grep -E '(show_|determine_)'"

# Debug do instalador
bash -x install-2/install.sh install -d teste.local -e admin@teste.com 2>&1 | head -100

# Verificar permissoes
find install-2 -name "*.sh" -exec ls -lh {} \;
```

---

## CHECKLIST DE VALIDACAO

Antes de considerar concluido, validar:

**Autossuficiencia**
- [ ] `install-2/` nao faz nenhuma chamada a `install/install.sh`
- [ ] Todas as funcoes Docker necessarias existem em `install-2/utils/`
- [ ] Templates nginx existem em `install-2/`
- [ ] `.env.installer.example` existe em `install-2/`

**Menu Interativo**
- [ ] Menu de ambiente aparece corretamente (opcoes 1-4)
- [ ] Menu de metodo aparece corretamente (Docker/Nativo)
- [ ] Menu de build aparece (quando aplicavel - VPS Docker)
- [ ] Confirmacao exibe informacoes corretas
- [ ] Cancelamento funciona (Ctrl+C ou resposta negativa)

**Modos Docker Local**
- [ ] Local Dev: Containers sobem com hot-reload
- [ ] Local Dev: Migrations executam
- [ ] Local Dev: Seeds populam banco
- [ ] Local Prod: Build otimizado funciona
- [ ] Local Prod: Nginx configurado corretamente

**Modos Docker VPS (funcoes internas)**
- [ ] VPS Dev: Instala via funcoes de `utils/docker-install.sh` (build local)
- [ ] VPS Dev: Instala via funcoes de `utils/docker-install.sh` (registry)
- [ ] VPS Dev: Verifica branch (recomenda `dev`)
- [ ] VPS Prod: Instala via funcoes de `utils/docker-install.sh` (build local)
- [ ] VPS Prod: Instala via funcoes de `utils/docker-install.sh` (registry)
- [ ] VPS Prod: Verifica branch (recomenda `main`)
- [ ] Resultado final identico ao do instalador original

**Documentacao**
- [ ] README.md existe e esta completo
- [ ] Exemplos de uso estao corretos
- [ ] Troubleshooting cobre problemas comuns

---

Ultima atualizacao: 2025-02-23
Status: Em desenvolvimento - Fase 1 (Autossuficiencia e Validacao)
