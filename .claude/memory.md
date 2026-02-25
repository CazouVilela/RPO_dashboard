# RPO_dashboard - Memória do Projeto

> **Referência**: Este projeto segue o template documentado em [TEMPLATE_PROJETO.md](.claude/TEMPLATE_PROJETO.md)

<!-- CHAPTER: 1 Visão Geral -->

## Sobre o Projeto

Dashboard para visualização e análise de dados das planilhas de RPO criadas no projeto RPO-V4.
Este projeto controla dashboards diferentes para clientes diferentes.

## Informações Principais

**Versão Atual**: v1.0.0
**Stack**: Python, PostgreSQL, Streamlit (a definir)
**Status**: Em desenvolvimento

## Estrutura de Dashboards

Cada dashboard possui os seguintes parâmetros:
- **cliente**: Identificador único do cliente
- **planilha**: URL da planilha Google Sheets de origem (referência)
- **banco**: Banco PostgreSQL onde os dados estão
- **schema**: Schema no banco onde os dados estão
- **configuracoes**: Tabela de configurações com parâmetros específicos

<!-- CHAPTER: 2 Clientes e Dashboards -->

## Clientes Cadastrados

### 1. semper_laser
| Parâmetro | Valor |
|-----------|-------|
| Cliente | semper_laser |
| Planilha | https://docs.google.com/spreadsheets/d/1ofrXUDXfqJgxUUi_ooEwBdw60T4NS-mqqICKzkERIS0/edit?gid=369670849#gid=369670849 |
| Banco | HUB |
| Schema | RPO_semper_laser |
| Configurações | RAW_AIRBYTE_configuracoesGerais |

**Tabelas dinâmicas:**
| Tabela | Nome |
|--------|------|
| Vagas | `RAW_AIRBYTE_Job_Openings_Control` |
| Candidatos | `RAW_AIRBYTE_Candidates_Control` |

**Tabelas fixas:** statusVagas, statusCandidatos, dicionarioVagas, dicionarioCandidatos, feriados, USO_historicoVagas, USO_historicoCandidatos, FALLBACK_historicoVagas, FALLBACK_historicoCandidatos

**Tabelas customizadas:**
- `USO_Listas` - Mapeamento lojas -> cidade/estado (38 registros)

**Tabelas com dados importados (NÃO RECRIAR):**
- `USO_historicoVagas` - Contém dados importados do HISTORICO_ORIGINAL (~400 registros). Fonte da verdade, carregados do PG para planilha. Não recriar.
- `USO_historicoCandidatos` - Contém 170 registros importados da planilha (2026-02-03). Estrutura normalizada igual a cielo. Não recriar.

**Tipo contagem:** Dias úteis
**Formato datas:** americano (MM/DD/YYYY)

**Campos extras em mv_CONSUMO_vagas:**
- `geo_city` - Cidade da loja
- `geo_state` - Estado da loja
- `geo_location` - Cidade + Estado concatenados

### 2. cielo
| Parâmetro | Valor |
|-----------|-------|
| Cliente | cielo |
| Planilha | https://docs.google.com/spreadsheets/d/1swF0vtbgftzFIKXFnUAf3Osn9tkR3XB1J-Y3zxrhTN0/edit?gid=0#gid=0 |
| Banco | HUB |
| Schema | RPO_cielo |
| Configurações | USO_configuracoesGerais |

**Tabelas dinâmicas:**
| Tabela | Nome |
|--------|------|
| Vagas | `USO_vagas` |
| Candidatos | `USO_candidatos` |

**Tabelas fixas:** USO_statusVagas, USO_statusCandidatos, USO_dicionarioVagas, USO_dicionarioCandidatos, USO_feriados, USO_historicoVagas, USO_historicoCandidatos, USO_FALLBACK_historicoVagas, USO_FALLBACK_historicoCandidatos

**Tabela historico_log_vagas (extraída de Google Sheets version history):**
- 334 status changes tracked (Jan 2 - Feb 4, 2025)
- 84 unique RPs with recorded changes
- 9 unique editors: Jessica, Emily, Carolina, Gessica, Ariane, Liliane, Cazou, Taina, Gabrielle
- Colunas: id, rp, old_status, new_status, change_datetime, changed_by, revision_id, prev_revision_id
- Extraída via CDP (Chrome DevTools Protocol) do histórico de versões do Google Sheets
- Scripts em `/home/cazouvilela/projetos/RPO-V4/api_historico/`: cdp_map_rev_ids.js, extract_status_changes.py
- A coluna "Log de atividades" (AQ) da planilha foi rejeitada como não confiável pelo usuário

**Tabela log_history_rebuild (reconstrução COMPLETA do histórico simulando AppScript):**
- 334 registros com TODOS os campos preenchidos (snapshot completo de cada mudança de status)
- Estrutura idêntica a USO_historicoVagas (22 colunas)
- 84 requisições únicas, 9 usuários
- Período: 2 de janeiro a 4 de fevereiro de 2025
- 47 registros com selecionado_nome preenchido
- 109 registros com cdd_totais_sl preenchido
- Campos de proposta (operacao_*) também preenchidos
- Script de rebuild: scripts/rebuild_history_complete.py

**Tabela log_history_rebuildCandidatos (reconstrução COMPLETA do histórico de candidatos):**
- 2001 registros com todos os campos preenchidos
- Estrutura idêntica a USO_historicoCandidatos (14 colunas)
- 1354 candidatos únicos
- Período: 2 de janeiro a 4 de fevereiro de 2025
- Script de rebuild: scripts/rebuild_history_candidatos.py

**Tipo contagem:** Dias úteis
**Formato datas:** brasileiro (DD/MM/YYYY)

**Views criadas:**
- `vw_vagas_nomeFixo` - 163 registros (mapeamento colunas Airbyte -> nomeFixo)
- `mv_SLAs` - 60 registros (SLAs em formato linha)
- `mv_CONSUMO_vagas` - 160 registros (dados processados para dashboard)

**SLAs disponíveis:** CP, DDN, Corporativo, Grandes_contas

**Campos time_to_fill e time_to_start (calculados diretamente em USO_historicoVagas):**
- `time_to_fill`: dias úteis (excl. feriados) de data_abertura até created_at do status FECHADA
- `time_to_start`: dias úteis (excl. feriados) de data_abertura até data_admissao (da vw_vagas_nomeFixo)
- Cielo não possui variantes `_no_holidays` (diferente de semper_laser)

**Correções no dicionário cielo:**
- `selecionado_empregado` → nomeAmigavel = `Selecionado_estava_empregado_`
- `selecionado_PCD` → nomeAmigavel = `Selecionado_e_PCD_`
- `contatos_candidato` (candidatos) → nomeAmigavel = `Telefone__E_mail`

**Problema de qualidade de dados cielo:**
- 13/51 registros FECHADA têm created_at=2025-09-12 (data de importação em lote, não data real de fechamento)
- Datas futuras corrigidas (ver Troubleshooting: Corrupção de dados históricos)
- Impacta cálculos de time_to_fill (média distorcida)

**V2 Dashboard (RPO_cielo):**

Tabelas V2 criadas com prefixo `V2_`:
| Tabela V2 | Fonte | Registros |
|-----------|-------|-----------|
| V2_USO_vagas | RAW_AIRBYTE_vagas | 172 |
| V2_USO_candidatos | RAW_AIRBYTE_candidatos | 1320 |
| V2_USO_statusVagas | RAW_AIRBYTE_statusVagas | 15 |
| V2_USO_statusCandidatos | RAW_AIRBYTE_statusCandidatos | 20 |
| V2_USO_configuracoesGerais | RAW_AIRBYTE_configuracoesGerais | 8 |
| V2_USO_feriados | RAW_AIRBYTE_feriados | 30 |
| V2_USO_dicionarioVagas | RAW_dicionarioVagas | 43 |
| V2_USO_dicionarioCandidatos | RAW_dicionarioCandidatos | 11 |
| V2_USO_historicoVagas | USO_historicoVagas | 589 |
| V2_USO_historicoCandidatos | USO_historicoCandidatos | 1107 |

### 3. appian
| Parâmetro | Valor |
|-----------|-------|
| Cliente | appian |
| Planilha | https://docs.google.com/spreadsheets/d/1aW71mfAHBSbzIeS9-be9qcpfzTWjzEPf/edit?gid=744894324#gid=744894324 |
| Banco | HUB |
| Schema | RPO_Appian |

**NOTA:** Este dashboard é totalmente diferente dos anteriores (semper_laser/cielo). Não segue o padrão de tabelas RAW_AIRBYTE/USO/dicionário/MV. Estrutura própria e simplificada.

**Tabelas:**
| Tabela | Registros | Descrição |
|--------|-----------|-----------|
| `acompanhamento` | 50 | Dados de vagas importados via Airbyte |
| `feriados` | 43 | Feriados (2024-2026) |
| `dashboard` | 50 | Tabela calculada (recriada diariamente via pg_cron) |

**Colunas da tabela `acompanhamento`:**
id, cargo, etapa, e_mail, gestor, status (texto livre), destino, situacao, historico, recrutador, confidencial, descricao_de_cargo, abertura_da_vaga, envio_da_shortlist, proposta, admissao, planejamento_admissao

**Tabela `dashboard` (colunas extras calculadas):**
- `dias_shortlist` - Dias úteis entre abertura_da_vaga e envio_da_shortlist
- `dias_proposta` - Dias úteis entre abertura_da_vaga e proposta
- `dias_admissao` - Dias úteis entre abertura_da_vaga e admissao
- Cálculo exclui sábados, domingos e feriados da tabela `feriados`

**Função `dias_uteis(date, date)`:** Criada no schema RPO_Appian, calcula dias úteis entre duas datas.

**Etapas (10):** Briefing, Descrição de Cargo, Divulgação/Hunting, Triagem/Entrevistas RH, Entrevistas Gestor, Proposta Salarial, Exames Médicos/Documentação/Mobilização, Admissão, Interrompido, Não iniciado

**Situações (4):** Em andamento, Concluído, Interrompido, Planejado

**Tipo contagem:** Dias úteis
**Formato datas:** Timestamps (já em formato date no PostgreSQL)

**pg_cron (job 123):** `0 1 * * *` - Recria tabela `dashboard` todos os dias à 1h da manhã

<!-- CHAPTER: 3 Tabela de Configurações -->

## Tabela de Configurações (Padrão para todos os dashboards)

A tabela de configurações (definida no parâmetro `configuracoes`) possui a estrutura:
- **Coluna Configuracao**: Nome da configuração
- **Coluna Valor**: Valor da configuração

### Configurações a serem carregadas:

| Configuracao | Uso | Tabela Resultante |
|--------------|-----|-------------------|
| Nome da aba de controle vagas | Define tabela de vagas | `RAW_AIRBYTE_[Valor]` (espaços → _) |
| Nome da aba de controle candidatos | Define tabela de candidatos | `RAW_AIRBYTE_[Valor]` (espaços → _) |
| Tipo da contagem de dias | Define cálculo de dias | `dias corridos` ou `dias úteis` |
| Formato das datas | Define formato de parsing | `americano` (MM/DD/YYYY) ou `brasileiro` (DD/MM/YYYY) |

**Configurações ignoradas:**
- Nome da aba do Form de inserção de vagas (não utilizado)
- Tamanho dicionário vagas (não utilizado)
- Tamanho dicionário candidatos (não utilizado)
- Nome do schema no banco (já definido nos parâmetros)

### Regra de Nomenclatura de Tabelas
```
RAW_AIRBYTE_[Valor com espaços substituídos por _]
```

### Tipo da Contagem de Dias
- **dias corridos**: Cálculos consideram todos os dias
- **dias úteis**: Cálculos excluem:
  - Finais de semana (sábado e domingo)
  - Datas presentes na tabela `RAW_AIRBYTE_feriados`

### Formato das Datas
- **americano**: Datas no formato MM/DD/YYYY (padrão semper_laser)
- **brasileiro**: Datas no formato DD/MM/YYYY

A conversão de datas é dinâmica baseada na tabela `USO_dicionarioVagas`:
- Colunas com `tipoDoDado = 'date'` são convertidas automaticamente para DATE na MV
- O formato de parsing segue o parâmetro "Formato das datas" em `USO_configuracoesGerais`
- Suporta também formato ISO (YYYY-MM-DD) automaticamente

### Regras de Filtro de Vagas (OBRIGATÓRIO em todas as MVs)

**IMPORTANTE:** Os seguintes filtros devem ser aplicados em TODAS as Materialized Views que utilizam dados de vagas. Os dados NÃO são excluídos das tabelas USO_, apenas filtrados na construção das MVs.

| Filtro | Regra | Motivo |
|--------|-------|--------|
| `requisicao` vazia | Excluir registros com requisicao NULL ou vazia | Não é possível identificar a vaga |
| `requisicao` duplicada | Manter apenas o registro mais recente (por data_abertura DESC) | Evitar multiplicação nos JOINs |
| `vaga_titulo` vazio | Excluir registros com vaga_titulo NULL ou vazio | Vaga sem identificação |
| `data_abertura` inválida | Excluir registros com data_abertura que não seja formato válido (MM/DD/YYYY ou YYYY-MM-DD) | Impossível calcular métricas de tempo |
| `data_abertura` futura | Excluir registros com data_abertura > CURRENT_DATE | Dados inconsistentes |

**Implementação:**
```sql
-- Filtro padrão aplicado nas MVs
WHERE requisicao IS NOT NULL AND TRIM(requisicao) <> ''
  AND vaga_titulo IS NOT NULL AND TRIM(vaga_titulo) <> ''
  AND data_abertura IS NOT NULL AND TRIM(data_abertura) <> ''
  AND data_abertura ~ '^\d{1,2}/\d{1,2}/\d{4}$|^\d{4}-\d{2}-\d{2}$'
  AND TO_DATE(data_abertura, 'formato') <= CURRENT_DATE

-- Para duplicadas, usar ROW_NUMBER:
ROW_NUMBER() OVER (PARTITION BY requisicao ORDER BY data_abertura DESC) as rn
-- E depois filtrar: WHERE rn = 1
```

### Tabelas do Schema

**Tabelas dinâmicas (nome vem das configurações):**
- `RAW_AIRBYTE_configuracoesGerais` - Configurações
- `RAW_AIRBYTE_[vagas]` - Controle de vagas
- `RAW_AIRBYTE_[candidatos]` - Controle de candidatos

**Tabelas fixas (mesmo nome em todos os dashboards):**
- `RAW_AIRBYTE_feriados` - Feriados (usado se tipo = dias úteis)
- `RAW_AIRBYTE_statusVagas` - Status disponíveis para vagas e SLAs
- `RAW_AIRBYTE_statusCandidatos` - Status disponíveis para candidatos
- `RAW_dicionarioVagas` - Dicionário de nomenclatura de colunas das vagas
- `RAW_dicionarioCandidatos` - Dicionário de nomenclatura de colunas dos candidatos
- `USO_historicoVagas` - Histórico de andamento das vagas
- `USO_historicoCandidatos` - Histórico de andamento dos candidatos
- `RAW_AIRBYTE_FALLBACK_historicoVagas` - Fallback do histórico de vagas
- `RAW_AIRBYTE_FALLBACK_historicoCandidatos` - Fallback do histórico de candidatos

### Regra de Criação de Tabelas USO_

**SEMPRE na criação de um novo dashboard**, criar tabelas USO_ como cópia das tabelas RAW_/RAW_AIRBYTE_:

| Tabela Origem | Tabela USO_ |
|---------------|-------------|
| `RAW_AIRBYTE_configuracoesGerais` | `USO_configuracoesGerais` |
| `RAW_AIRBYTE_[vagas]` | `USO_[vagas]` |
| `RAW_AIRBYTE_[candidatos]` | `USO_[candidatos]` |
| `RAW_AIRBYTE_feriados` | `USO_feriados` |
| `RAW_AIRBYTE_statusVagas` | `USO_statusVagas` |
| `RAW_AIRBYTE_statusCandidatos` | `USO_statusCandidatos` |
| `RAW_dicionarioVagas` | `USO_dicionarioVagas` |
| `RAW_dicionarioCandidatos` | `USO_dicionarioCandidatos` |
| `RAW_AIRBYTE_FALLBACK_historicoVagas` | `USO_FALLBACK_historicoVagas` |
| `RAW_AIRBYTE_FALLBACK_historicoCandidatos` | `USO_FALLBACK_historicoCandidatos` |

Comando SQL padrão:
```sql
DROP TABLE IF EXISTS "schema"."USO_[nome]";
CREATE TABLE "schema"."USO_[nome]" AS SELECT * FROM "schema"."RAW_[nome]";
```

### PROCESSO COMPLETO - Criação/Recriação de Dashboard

**IMPORTANTE:** As 3 etapas devem ser executadas NA ORDEM indicada. Cada etapa depende da anterior.

---

#### PASSO 0 (OBRIGATÓRIO): Verificar e Remover Dependências

**CRÍTICO:** As Materialized Views dependem das tabelas USO_. Tentar dropar USO_ sem remover as MVs primeiro causa erro de dependência CASCADE.

```sql
-- ============================================================
-- PASSO 0: REMOVER MVs ANTES DE RECRIAR TABELAS USO_
-- ============================================================
-- OBRIGATÓRIO se as tabelas USO_ forem recriadas

-- Ordem de remoção (respeita dependências):
DROP MATERIALIZED VIEW IF EXISTS "RPO_cliente"."MV_CONSUMO_candidatos" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_cliente"."MV_CONSUMO_historicoVagas" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_cliente"."mv_CONSUMO_vagas" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_cliente"."mv_SLAs" CASCADE;
DROP VIEW IF EXISTS "RPO_cliente"."vw_vagas_nomeFixo" CASCADE;
DROP VIEW IF EXISTS "RPO_cliente"."vw_candidatos_nomeFixo" CASCADE;
```

**Sintoma do erro (se não executar PASSO 0):**
```
ERROR: cannot drop table "USO_xxx" because other objects depend on it
DETAIL: materialized view mv_CONSUMO_vagas depends on table USO_xxx
HINT: Use DROP ... CASCADE to drop the dependent objects too.
```

---

#### ETAPA 1: Criar/Recriar Tabelas USO_ (cópia das RAW_)

**Quando executar:**
- Na criação de um novo dashboard
- Quando os dados de origem (RAW_) forem atualizados pelo Airbyte
- Quando o dicionário de campos for alterado

**Tabelas a serem criadas:**

```sql
-- ============================================================
-- ETAPA 1: TABELAS USO_ (executar TODAS na ordem)
-- ============================================================
-- Substituir 'RPO_cliente' pelo schema do cliente

-- 1.1 Configurações gerais
DROP TABLE IF EXISTS "RPO_cliente"."USO_configuracoesGerais";
CREATE TABLE "RPO_cliente"."USO_configuracoesGerais" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_configuracoesGerais";

-- 1.2 Dicionário de vagas (CRÍTICO - define colunas das views)
DROP TABLE IF EXISTS "RPO_cliente"."USO_dicionarioVagas";
CREATE TABLE "RPO_cliente"."USO_dicionarioVagas" AS
SELECT * FROM "RPO_cliente"."RAW_dicionarioVagas";

-- 1.3 Dicionário de candidatos
DROP TABLE IF EXISTS "RPO_cliente"."USO_dicionarioCandidatos";
CREATE TABLE "RPO_cliente"."USO_dicionarioCandidatos" AS
SELECT * FROM "RPO_cliente"."RAW_dicionarioCandidatos";

-- 1.4 Status de vagas (SLAs e fluxo)
DROP TABLE IF EXISTS "RPO_cliente"."USO_statusVagas";
CREATE TABLE "RPO_cliente"."USO_statusVagas" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_statusVagas";

-- 1.5 Status de candidatos
DROP TABLE IF EXISTS "RPO_cliente"."USO_statusCandidatos";
CREATE TABLE "RPO_cliente"."USO_statusCandidatos" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_statusCandidatos";

-- 1.6 Feriados (para cálculo de dias úteis)
DROP TABLE IF EXISTS "RPO_cliente"."USO_feriados";
CREATE TABLE "RPO_cliente"."USO_feriados" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_feriados";

-- **NOTA**: As funções agora usam o formato configurado em USO_configuracoesGerais
-- para parsing de feriados. Não é necessário converter manualmente.

-- 1.7 Tabela de vagas (nome vem de USO_configuracoesGerais)
-- Verificar nome em: SELECT "Valor" FROM "RPO_cliente"."USO_configuracoesGerais"
--                    WHERE "Configuracao" = 'Nome da aba de controle vagas';
DROP TABLE IF EXISTS "RPO_cliente"."USO_[nome_vagas]";
CREATE TABLE "RPO_cliente"."USO_[nome_vagas]" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_[nome_vagas]";

-- 1.8 Tabela de candidatos (nome vem de USO_configuracoesGerais)
DROP TABLE IF EXISTS "RPO_cliente"."USO_[nome_candidatos]";
CREATE TABLE "RPO_cliente"."USO_[nome_candidatos]" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_[nome_candidatos]";

-- 1.9 Histórico de vagas
-- **ATENÇÃO semper_laser**: NÃO recriar esta tabela se contém dados importados!
-- Verificar se existe e tem dados antes de dropar:
-- SELECT COUNT(*) FROM "RPO_semper_laser"."USO_historicoVagas";
DROP TABLE IF EXISTS "RPO_cliente"."USO_historicoVagas";
CREATE TABLE "RPO_cliente"."USO_historicoVagas" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_historicoVagas";

-- 1.10 Histórico de candidatos
DROP TABLE IF EXISTS "RPO_cliente"."USO_historicoCandidatos";
CREATE TABLE "RPO_cliente"."USO_historicoCandidatos" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_historicoCandidatos";

-- 1.11 Fallback histórico vagas
DROP TABLE IF EXISTS "RPO_cliente"."USO_FALLBACK_historicoVagas";
CREATE TABLE "RPO_cliente"."USO_FALLBACK_historicoVagas" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_FALLBACK_historicoVagas";

-- 1.12 Fallback histórico candidatos
DROP TABLE IF EXISTS "RPO_cliente"."USO_FALLBACK_historicoCandidatos";
CREATE TABLE "RPO_cliente"."USO_FALLBACK_historicoCandidatos" AS
SELECT * FROM "RPO_cliente"."RAW_AIRBYTE_FALLBACK_historicoCandidatos";

-- 1.13 CUSTOMIZAÇÕES (se aplicável ao cliente)
-- Ver seção "Customizações por Cliente" para detalhes

-- ============================================================
-- 1.14 PERMISSÕES PARA rpo_user (OBRIGATÓRIO)
-- ============================================================
-- O usuário rpo_user é usado pela API do RPO-V4 para acessar os dados.
-- TODAS as tabelas USO_ devem ter permissões concedidas.

-- Permissões no schema
GRANT USAGE ON SCHEMA "RPO_cliente" TO rpo_user;

-- Permissões em TODAS as tabelas do schema
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "RPO_cliente" TO rpo_user;

-- Permissões em TODAS as sequences do schema (necessário para INSERT com SERIAL/IDENTITY)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA "RPO_cliente" TO rpo_user;

-- Permissões padrão para objetos futuros
ALTER DEFAULT PRIVILEGES IN SCHEMA "RPO_cliente" GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rpo_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA "RPO_cliente" GRANT USAGE, SELECT ON SEQUENCES TO rpo_user;
```

**Tabelas customizadas por cliente:**

| Cliente | Tabela | Origem | Função |
|---------|--------|--------|--------|
| semper_laser | USO_Listas | RAW_AIRBYTE_Listas | Geolocalização (geo_city, geo_state, geo_location) |

```sql
-- Exemplo: semper_laser - Geolocalização
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_Listas";
CREATE TABLE "RPO_semper_laser"."USO_Listas" AS
SELECT "City_", "Lojas_", "State_" FROM "RPO_semper_laser"."RAW_AIRBYTE_Listas";
```

---

#### ETAPA 2: Criar/Recriar Views Dinâmicas

**Quando executar:**
- Após a Etapa 1
- Quando os dicionários (USO_dicionarioVagas, USO_dicionarioCandidatos) forem alterados
- Quando os status (USO_statusVagas) forem alterados

**Comando:**
```sql
-- ============================================================
-- ETAPA 2: VIEWS DINÂMICAS
-- ============================================================
-- V1 (sem versão):
SELECT dashboard_criar_views('RPO_cliente');
-- V2 (com versão):
SELECT dashboard_criar_views('RPO_cliente', 'V2');
```

**Resultado esperado:**
```
Tabela vagas: USO_[nome_vagas]
Tabela candidatos: USO_[nome_candidatos]
View vw_vagas_nomeFixo criada (X colunas)
View vw_candidatos_nomeFixo criada (Y colunas)
Materialized view mv_SLAs criada
```

**Objetos criados:**
| Objeto | Tipo | Descrição |
|--------|------|-----------|
| vw_vagas_nomeFixo | VIEW | Colunas renomeadas conforme USO_dicionarioVagas |
| vw_candidatos_nomeFixo | VIEW | Colunas renomeadas conforme USO_dicionarioCandidatos |
| mv_SLAs | MATERIALIZED VIEW | SLAs transformados em linhas com tipo_sla em formato amigável |

---

#### ETAPA 3: Criar/Recriar Materialized Views

**Quando executar:**
- Após a Etapa 2
- Quando as views forem recriadas
- Para atualizar dados: usar REFRESH em vez de recriar

**Comandos (executar na ordem):**
```sql
-- ============================================================
-- ETAPA 3: MATERIALIZED VIEWS (ordem obrigatória)
-- ============================================================

-- V1 (sem versão):
SELECT dashboard_criar_mv_consumo_vagas('RPO_cliente');
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cliente');
SELECT dashboard_criar_mv_consumo_candidatos('RPO_cliente');
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cliente');

-- V2 (com versão):
SELECT dashboard_criar_mv_consumo_vagas('RPO_cliente', 'V2');
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cliente', 'V2');
SELECT dashboard_criar_mv_consumo_candidatos('RPO_cliente', 'V2');
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cliente', 'V2');
```

**Resultado esperado:**
```
mv_CONSUMO_vagas criada com X registros
MV_CONSUMO_historicoVagas criada com Y registros
MV_CONSUMO_candidatos criada com Z registros
```

**Para apenas atualizar dados (sem recriar estrutura):**
```sql
REFRESH MATERIALIZED VIEW "RPO_cliente"."mv_CONSUMO_vagas";
REFRESH MATERIALIZED VIEW "RPO_cliente"."MV_CONSUMO_historicoVagas";
REFRESH MATERIALIZED VIEW "RPO_cliente"."MV_CONSUMO_candidatos";
```

---

#### RESUMO: Quando executar cada etapa

| Situação | Etapa 1 | Etapa 2 | Etapa 3 |
|----------|---------|---------|---------|
| Novo dashboard | SIM | SIM | SIM |
| Dados atualizados (Airbyte) | SIM | NÃO | REFRESH |
| Dicionário alterado | SIM (dicionários) | SIM | SIM |
| Status/SLAs alterados | SIM (statusVagas) | SIM | SIM |
| Apenas refresh de dados | NÃO | NÃO | REFRESH |

**Objetos criados por dashboard:**
| Objeto | Tipo | Função Criadora |
|--------|------|-----------------|
| [V2_]vw_vagas_nomeFixo | VIEW | dashboard_criar_views(schema, [versao]) |
| [V2_]vw_candidatos_nomeFixo | VIEW | dashboard_criar_views(schema, [versao]) |
| [V2_]mv_SLAs | MATERIALIZED VIEW | dashboard_criar_views(schema, [versao]) |
| [V2_]mv_CONSUMO_vagas | MATERIALIZED VIEW | dashboard_criar_mv_consumo_vagas(schema, [versao]) |
| [V2_]MV_CONSUMO_historicoVagas | MATERIALIZED VIEW | dashboard_criar_mv_consumo_historico_vagas(schema, [versao]) |
| [V2_]MV_CONSUMO_candidatos | MATERIALIZED VIEW | dashboard_criar_mv_consumo_candidatos(schema, [versao]) |
| [V2_]MV_CONSUMO_ERROS_VAGAS | MATERIALIZED VIEW | dashboard_criar_mv_consumo_erros_vagas(schema, [versao]) |

**Para atualizar dados existentes (REFRESH):**
```sql
-- Executar periodicamente ou após carga de dados
-- IMPORTANTE: Ordem de refresh deve respeitar dependências

-- 1. Primeiro mv_SLAs (se USO_statusVagas foi alterada)
REFRESH MATERIALIZED VIEW "RPO_cliente"."mv_SLAs";

-- 2. Depois as MVs de consumo
REFRESH MATERIALIZED VIEW "RPO_cliente"."mv_CONSUMO_vagas";
REFRESH MATERIALIZED VIEW "RPO_cliente"."MV_CONSUMO_historicoVagas";
REFRESH MATERIALIZED VIEW "RPO_cliente"."MV_CONSUMO_candidatos";
REFRESH MATERIALIZED VIEW "RPO_cliente"."MV_CONSUMO_ERROS_VAGAS";
```

### Função dashboard_criar_views (PostgreSQL) - VERSÃO 3.0 COM SUPORTE A VERSÃO

**Assinatura:** `public.dashboard_criar_views(p_schema TEXT, p_versao TEXT DEFAULT NULL)`

**Uso:**
```sql
SELECT dashboard_criar_views('RPO_semper_laser');
SELECT dashboard_criar_views('RPO_cielo');
SELECT dashboard_criar_views('RPO_cielo', 'V2');  -- cria V2_vw_vagas_nomeFixo, V2_vw_candidatos_nomeFixo, V2_mv_SLAs
```

**O que faz:**
1. Lê a tabela `USO_configuracoesGerais` do schema para descobrir os nomes das tabelas de vagas e candidatos
2. Lê o dicionário `USO_dicionarioVagas` e cria a view `vw_vagas_nomeFixo` DINAMICAMENTE
3. Lê o dicionário `USO_dicionarioCandidatos` e cria a view `vw_candidatos_nomeFixo` DINAMICAMENTE
4. Cria a materialized view `mv_SLAs` (transforma colunas SLA em linhas via JSON, com tipo_sla em formato amigável)

**IMPORTANTE - Versão 2.0 Dinâmica:**
- As colunas das views são lidas dos dicionários, não mais fixas no código
- Qualquer alteração no dicionário reflete na view ao recriá-la
- A função `normalizar_nome_coluna()` converte nomes amigáveis para formato Airbyte
- Colunas que não existem na tabela são ignoradas silenciosamente

**Função `normalizar_nome_coluna()`** - Converte nomes do dicionário para formato Airbyte:

| Transformação | Exemplo |
|--------------|---------|
| Quebras de linha → `_` | "ID Position\nADP" → "ID_Position_ADP" |
| Espaços → `_` | "Data de abertura" → "Data_de_abertura" |
| Remove acentos | "Posição" → "Posicao" |
| Remove `?`, `(`, `)`, `.`, `,`, `:`, `;` | "Confidential?" → "Confidential" |
| `/` → `_` | "SSD/SM" → "SSD_SM" |
| Remove `_` duplicados | "Data__abertura" → "Data_abertura" |
| Remove `_` no final | "Status_" → "Status" |

```sql
-- Código da função:
CREATE OR REPLACE FUNCTION normalizar_nome_coluna(p_nome TEXT)
RETURNS TEXT AS $$
  -- 1. Quebras de linha → _
  -- 2. Espaços → _
  -- 3. Remove acentos (TRANSLATE)
  -- 4. Remove caracteres especiais
  -- 5. Remove _ duplicados
  -- 6. Remove _ final
$$;
```

**Retorno:**
```
Tabela vagas: USO_vagas
Tabela candidatos: USO_candidatos
View vw_vagas_nomeFixo criada (X colunas)
View vw_candidatos_nomeFixo criada (Y colunas)
Materialized view mv_SLAs criada
```

**Arquivo:** `sql/dashboard_criar_views.sql`

**Estrutura esperada dos dicionários:**
| Coluna | Descrição |
|--------|-----------|
| nomeAmigavel | Nome original da coluna (ex: "Data de abertura") |
| nomeFixo | Nome padronizado (ex: "data_abertura") |
| tipoDoDado | Tipo do dado (text, date, integer, etc.) |

### Função dashboard_criar_mv_consumo_vagas (PostgreSQL) - VERSÃO 2.0 COM SUPORTE A VERSÃO

**Assinatura:** `public.dashboard_criar_mv_consumo_vagas(p_schema TEXT, p_versao TEXT DEFAULT NULL)`

**Uso:**
```sql
SELECT dashboard_criar_mv_consumo_vagas('RPO_semper_laser');
SELECT dashboard_criar_mv_consumo_vagas('RPO_cielo', 'V2');  -- cria V2_mv_CONSUMO_vagas
```

**Pré-requisito:** Executar `dashboard_criar_views()` antes (cria a view `[V2_]mv_SLAs`)

**Parâmetros lidos da configuração:**
- `Tipo da contagem de dias`: Define cálculo de dias úteis/corridos
- `Formato das datas`: Define formato de parsing (americano=MM/DD/YYYY, brasileiro=DD/MM/YYYY)

**Conversão automática de datas:**
- Busca colunas com `tipoDoDado = 'date'` em `USO_dicionarioVagas`
- Converte para tipo DATE na MV usando o formato configurado
- Suporta automaticamente formato ISO (YYYY-MM-DD)

**O que faz:**
1. Cria materialized view `mv_CONSUMO_vagas` com dados filtrados e validados
2. Busca dinamicamente o SLA correto via JOIN com `mv_SLAs`
3. Busca `data_inicio_status` via JOIN com `USO_historicoVagas`

**Filtros aplicados:**
- `requisicao` não vazio e não duplicado (mantém o mais recente)
- `data_abertura` válida, não vazia e não futura
- `vaga_titulo` não vazio

**Colunas da view de vagas (dinâmicas):**
- Todas as colunas de `vw_vagas_nomeFixo` são incluídas automaticamente
- A quantidade varia conforme o dicionário do cliente

**Colunas agregadas de USO_statusVagas:**
- `SLA_do_status` (INTEGER): Busca dinâmica na `mv_SLAs`
  - Ex: se `sla_utilizado = "Sales Manager"` e `status = "Open"`, busca o valor onde `tipo_sla = "Sales Manager"` e `status = "Open"`
  - O JOIN usa comparação direta: `TRIM(sv.tipo_sla) = TRIM(v.sla_utilizado)`
- `fim_fluxo` (VARCHAR): Campo `fimFluxo` da tabela `USO_statusVagas` - indica se é status final ("Sim"/"Não")
- `sequencia_status` (VARCHAR): Campo `sequencia` da tabela `USO_statusVagas` - ordem do status no fluxo
- `responsavel_status` (VARCHAR): Campo `responsavel` da tabela `USO_statusVagas` - responsável pelo status (CONSULTORIA/CLIENTE)
- `funcao_sistema` (VARCHAR): Campo `funcaoSistema` da tabela `USO_statusVagas` - função do sistema para o status

**Materialzed View `mv_SLAs`:**

A `mv_SLAs` transforma colunas de SLA em linhas e normaliza o nome para formato amigável:

```sql
-- Transformação do nome da coluna (preserva espaços):
REPLACE(coluna, '_', ' ')
-- "Sales_Manager_" → "Sales Manager " (com espaço final)
-- "Grandes_contas" → "Grandes contas"
```

| tipo_sla (mv_SLAs) | tipo_sla_original (coluna) |
|-------------------|---------------------------|
| Sales Manager  (com espaço) | Sales_Manager_ |
| Laser Technician  (com espaço) | Laser_Technician_ |
| Grandes contas | Grandes_contas |
| DDN | DDN |

**IMPORTANTE:** O `tipo_sla` mantém exatamente o mesmo formato do campo `sla_utilizado` nas vagas, permitindo JOIN direto sem necessidade de TRIM.

**Estrutura da mv_SLAs:**
| Campo | Descrição |
|-------|-----------|
| `status` | Status da vaga |
| `tipo_sla` | Nome amigável do SLA (igual ao `sla_utilizado` nas vagas) |
| `tipo_sla_original` | Nome original da coluna Airbyte |
| `valor_sla` | Valor do SLA em dias |

**Processo de busca (simplificado):**
1. `mv_SLAs` transforma colunas de SLA em linhas usando `jsonb_each_text`
2. `tipo_sla` preserva o formato original (underscores → espaços, incluindo espaço final se houver)
3. JOIN com `mv_CONSUMO_vagas` usa comparação direta: `v.sla_utilizado = s.tipo_sla`
4. Retorna `valor_sla` correspondente

**Exemplo de query:**
```sql
SELECT v.*, s.valor_sla
FROM "RPO_cliente"."mv_CONSUMO_vagas" v
LEFT JOIN "RPO_cliente"."mv_SLAs" s
    ON v.sla_utilizado = s.tipo_sla
    AND v.status = s.status;
```

**IMPORTANTE:** A tabela `USO_statusVagas` deve ser criada a partir de `RAW_AIRBYTE_statusVagas` (não `RAW_statusVagas`) para incluir as colunas de SLA.

**Colunas de datas calculadas:**
- `data_inicio_status` (DATE): Busca na `USO_historicoVagas` o MAX(created_at) onde `requisicao` e `status` sejam iguais
  - Retorna a data mais recente em que a vaga entrou no status atual
  - NULL se não houver registro no histórico
- `data_final_status` (DATE): Data de saída do status
  - Busca na `USO_historicoVagas` a próxima data após `data_inicio_status` para a mesma requisição
  - **Se `sla_do_status = 0` E `fimFluxo = 'Sim'` (status final)**: `data_final_status = data_inicio_status`
  - NULL se não houver transição posterior ou se `data_inicio_status` for NULL

**Colunas de contagem de dias:**
- `dias_no_status` (INTEGER): Calcula os dias entre `data_inicio_status` e `data_final_status`
  - **Se `fimFluxo = 'Sim'`, retorna 0** (status final não tem dias de permanência)
  - Se `data_final_status` for NULL, usa a data atual
  - Se `data_inicio_status` for NULL, retorna NULL
  - Respeita a configuração "Tipo da contagem de dias" em `USO_configuracoesGerais`:
    - "Dias úteis": exclui sábados, domingos e feriados (tabela `USO_feriados`)
    - "Dias corridos": conta todos os dias
- `dias_da_abertura` (INTEGER): Calcula os dias desde `data_abertura` até `data_final_status`
  - Se `data_final_status` for NULL, usa a data atual
  - Segue a mesma lógica de dias úteis/corridos da configuração

**Colunas de SLA acumulado:**
- `SLA_da_abertura` (BIGINT): Soma dos SLAs de todos os status com sequência <= sequência atual
  - Busca a `sequencia` do status atual na `USO_statusVagas`
  - Se `sequencia` for NULL, busca o último status com sequência não NULL no `USO_historicoVagas` para a mesma requisição
  - Soma os SLAs de todos os status onde `sequencia <= sequencia_efetiva` usando o mesmo `sla_utilizado`
  - Representa o tempo total esperado (em dias) desde a abertura até o status atual

**Colunas de GAP (diferença entre SLA e dias reais):**
- `GAP_SLA_status` (INTEGER): Diferença entre SLA esperado e dias gastos no status
  - Fórmula: `SLA_do_status - dias_no_status`
  - **Valor positivo**: dentro do SLA (dias de folga)
  - **Valor negativo**: fora do SLA (dias de atraso)
  - NULL se SLA_do_status ou dias_no_status for NULL
- `GAP_SLA_abertura` (BIGINT): Diferença entre SLA acumulado e dias totais desde abertura
  - Fórmula: `SLA_da_abertura - dias_da_abertura`
  - **Valor positivo**: dentro do SLA acumulado
  - **Valor negativo**: fora do SLA acumulado
  - NULL se SLA_da_abertura ou dias_da_abertura for NULL

**Coluna de candidatos:**
- `candidatos_considerados` (INTEGER): Conta quantos candidatos estão considerando esta vaga
  - Busca na `vw_candidatos_nomeFixo` candidatos onde `requisicao` aparece em `operacao_posicoesconsideradas`
  - Suporta múltiplos formatos de dados:
    - **cielo**: `[requisicao] - título...` → busca `[requisicao]`
    - **semper_laser**: `TITULO --- (loja) --- requisicao` → busca `--- requisicao`
  - Conta candidatos que estão em processo para a vaga, mesmo que considerem múltiplas vagas

**IMPORTANTE - Isolamento por schema/dashboard:**
- Cada dashboard (schema) terá seus próprios objetos:
  ```
  RPO_cliente_x/
  ├── USO_statusVagas              → Tabela com SLAs/status específicos deste cliente
  ├── vw_vagas_nomeFixo            → View criada por dashboard_criar_views()
  ├── vw_candidatos_nomeFixo       → View criada por dashboard_criar_views()
  ├── mv_SLAs                      → MV de SLAs criada por dashboard_criar_views()
  ├── mv_CONSUMO_vagas             → MV criada por dashboard_criar_mv_consumo_vagas()
  └── MV_CONSUMO_historicoVagas    → MV criada por dashboard_criar_mv_consumo_historico_vagas()
  ```
- Cada dashboard pode ter **nomes e quantidades de SLAs diferentes**
- Cada dashboard pode ter **nomes e quantidades de status diferentes**
- As funções criam objetos isolados por schema
- A MV pode ser recriada sem CASCADE pois não depende diretamente das views de dados

**IMPORTANTE - Comportamento dinâmico:**
- A materialized view `mv_SLAs` usa JSON para transformar colunas em linhas dinamicamente
- O campo `tipo_sla` é normalizado para formato amigável (ex: "Sales Manager" em vez de "Sales_Manager_")
- **Novos SLAs ou status são reconhecidos automaticamente no REFRESH da mv_SLAs**, sem precisar recriar a MV
- Nem todos os status da tabela `USO_statusVagas` precisam existir na `vw_vagas_nomeFixo` no momento da criação

**Para atualizar mv_SLAs após alteração em USO_statusVagas:**
```sql
REFRESH MATERIALIZED VIEW "RPO_cliente"."mv_SLAs";
-- Depois atualizar mv_CONSUMO_vagas para refletir novos SLAs
REFRESH MATERIALIZED VIEW "RPO_cliente"."mv_CONSUMO_vagas";
```

**Para atualizar os dados (reconhece novos SLAs/status):**
```sql
REFRESH MATERIALIZED VIEW "RPO_semper_laser"."mv_CONSUMO_vagas";
```

**Materialized view auxiliar mv_SLAs:**
```sql
-- mv_SLAs transforma colunas de SLA em linhas:
-- USO_statusVagas:
-- | status | Sales_Manager_ | Laser_Technician_ |
-- | Open   | 1              | 1                 |
--
-- mv_SLAs (tipo_sla em formato amigável):
-- | status | tipo_sla         | tipo_sla_original  | valor_sla |
-- | Open   | Sales Manager    | Sales_Manager_     | 1         |
-- | Open   | Laser Technician | Laser_Technician_  | 1         |
--
-- O JOIN é feito por comparação direta:
-- TRIM(sv.tipo_sla) = TRIM(v.sla_utilizado)
```

### Função dashboard_criar_mv_consumo_historico_vagas (PostgreSQL) - VERSÃO 4.0 COM SUPORTE A VERSÃO

**OBRIGATÓRIO: Esta MV deve ser criada em TODOS os dashboards.**

**Assinatura:** `public.dashboard_criar_mv_consumo_historico_vagas(p_schema TEXT, p_versao TEXT DEFAULT NULL)`

**Uso:**
```sql
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cielo');
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_semper_laser');
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cielo', 'V2');  -- cria V2_MV_CONSUMO_historicoVagas
```

**O que faz:**
Cria a materialized view `MV_CONSUMO_historicoVagas` com todos os campos de `USO_historicoVagas` mais campos calculados e agregados.

**Arquivo:** `sql/dashboard_criar_mv_consumo_historico_vagas.sql`

**IMPORTANTE - Versão 3.9 Dinâmica:**
- As colunas são lidas DINAMICAMENTE da tabela `USO_historicoVagas` de cada schema
- Funciona com estruturas de tabela diferentes entre clientes
- Não requer alteração no código ao adicionar novos clientes
- A quantidade de colunas originais varia conforme o schema
- Busca `vaga_titulo` da tabela de vagas usando `requisicao` como chave
- Cria campo `indice` concatenando `requisicao - vaga_titulo`
- Busca `data_abertura_vaga` da tabela de vagas usando `requisicao` como chave
- Calcula `dias_abertura_ate_status` respeitando configuração de dias úteis/corridos
- **v3.2:** Calcula `dias_no_status` (dias entre created_at e status_fim)
- **v3.3:** Gera status "waiting to start" dinamicamente na MV (não armazenado em USO_historicoVagas)
- **v3.4:** Usa `USO_[vagas]` para "waiting to start" (campos `Offer_accepted_` e `Start_Date__Admission_`)
- **v3.8:** Inclui campos DADOS_SELECIONADO extras de vw_vagas_nomeFixo (detecção via `grupoDoCampo` no dicionário)
- **v3.9:** "waiting to start" genérico para schemas com `data_admissao` e `funcaoSistema='Fechada'`

**Pré-requisito:**
- Tabelas `USO_historicoVagas` e `USO_statusVagas` devem existir no schema
- View `vw_vagas_nomeFixo` deve existir (criada por `dashboard_criar_views()`)
- Tabela `USO_feriados` deve existir para cálculo de dias úteis

**Filtros aplicados no JOIN com vagas (mesmos de dashboard_criar_mv_consumo_vagas):**
- `requisicao` não vazia
- `vaga_titulo` não vazio
- `data_abertura` válida (formato MM/DD/YYYY ou YYYY-MM-DD)
- `data_abertura` não futura
- Para requisições duplicadas na tabela de vagas, mantém apenas a com `data_abertura` mais recente

**IMPORTANTE:** A MV_CONSUMO_historicoVagas inclui apenas registros de histórico cujas requisições existem em `mv_CONSUMO_vagas`. Requisições órfãs (que existem apenas no histórico mas não na tabela de vagas) são automaticamente excluídas.

**Campos agregados de USO_statusVagas (usando status como chave):**
| Campo | Origem | Descrição |
|-------|--------|-----------|
| `fim_fluxo` | fimFluxo | "Sim"/"Não" - indica se é status final |
| `sequencia_status` | sequencia | Ordem do status no fluxo (20, 30, 40...) |
| `responsavel_status` | responsavel | CONSULTORIA ou CLIENTE |
| `funcao_sistema` | funcaoSistema | Triagem, EntrevistaRH, Fechada, Cancelada, Congelada, etc. |

**Campos calculados:**
| Campo | Tipo | Descrição |
|-------|------|-----------|
| `status_fim` | DATE | Data do `created_at` do próximo registro da mesma requisição (ordenado por created_at, id). Quando o próximo status é `fimFluxo = 'Sim'`, esta é a data de entrada no status final. **Exceção "waiting to start"**: usa `Start_Date__Admission_` da tabela `USO_Job_Openings_Control`. NULL se não existir próximo |
| `primeira_ocorrencia` | TEXT | "Sim"/"Não" - primeira vez deste status para a requisição (baseado em MIN(created_at)) |
| `vaga_titulo` | TEXT | Título da vaga (JOIN com `vw_vagas_nomeFixo` via `requisicao`) |
| `indice` | TEXT | Concatenação: `requisicao - vaga_titulo` (ex: "2669353 - GTE DE NEGOCIOS PL") |
| `sucesso_status` | TEXT | "Sim"/"Não"/NULL - análise do progresso da vaga (ver regras abaixo) |
| `data_abertura_vaga` | DATE | Data de abertura da vaga (JOIN com `vw_vagas_nomeFixo` via `requisicao`) |
| `dias_abertura_ate_status` | INTEGER | Dias entre `data_abertura_vaga` e `created_at` do histórico |
| `dias_no_status` | INTEGER | Dias entre `created_at` (início do status) e `status_fim` (ou hoje se não houver próximo) |

**Campos DADOS_SELECIONADO extras (v3.8):**
- Campos de vw_vagas_nomeFixo cujo `grupoDoCampo = 'DADOS_SELECIONADO'` no USO_dicionarioVagas
- Apenas campos que existem em vw_vagas_nomeFixo mas NÃO existem em USO_historicoVagas
- Incluídos via LEFT JOIN com vw_vagas_nomeFixo usando requisicao como chave
- Cielo: selecionado_empregado, selecionado_PCD, selecionado_fonte (3 campos extras)

**Regras do campo `dias_abertura_ate_status`:**
- Respeita a configuração "Tipo da contagem de dias" em `USO_configuracoesGerais`:
  - **"Dias úteis"**: exclui sábados, domingos e feriados (tabela `USO_feriados`)
  - **"Dias corridos"**: conta todos os dias
- NULL se `data_abertura_vaga` ou `created_at` for NULL
- O formato de parsing das datas segue a configuração "Formato das datas" do dashboard

**Regras do campo `dias_no_status`:**
- **Se `fimFluxo = 'Sim'` (exceto "waiting to start"), retorna 0** (status final não tem dias de permanência)
- **Exceção "waiting to start"**: mesmo sendo `fimFluxo = 'Sim'`, calcula os dias entre `created_at` e `status_fim` (Start_Date)
- **Data inicial**: `created_at` do registro de histórico (quando entrou no status)
- **Data final**: `status_fim` (próximo registro) ou `CURRENT_DATE` se não houver próximo
- Respeita a mesma configuração "Tipo da contagem de dias":
  - **"Dias úteis"**: exclui sábados, domingos e feriados (tabela `USO_feriados`)
  - **"Dias corridos"**: conta todos os dias
- NULL se `created_at` for NULL
- Segue a mesma lógica do campo `dias_no_status` em `mv_CONSUMO_vagas`

**Regras do campo `sucesso_status`:**
- **"Sim"**: próximo status (ignorando CONGELADA) tem sequência MAIOR que o atual
- **"Sim"**: próximo status tem `funcaoSistema` = 'Fechada' ou 'Cancelada' (status final)
- **"Não"**: próximo status (ignorando CONGELADA) tem sequência MENOR que o atual (retrocesso)
- **NULL**: não há próximo status, ou sequências iguais, ou status sem sequência definida
- **CONGELADA é ignorada**: se o próximo status for CONGELADA, avalia o status seguinte a ela

**Exemplo de análise sucesso_status:**
```
Requisição 50011211-B:
DIVULGAÇÃO (seq 40) → ENTREVISTA RH (seq 70)     = Sim (70 > 40)
ENTREVISTA RH (seq 70) → DIVULGAÇÃO (seq 40)     = Não (40 < 70, retrocesso)
TESTE/PESQUISA (seq 60) → SHORTLIST (seq 90)     = Sim (90 > 60)
SHORTLIST (seq 90) → CONGELADA → ???             = Avalia o que vem depois de CONGELADA
PROPOSTA (seq 130) → FECHADA (funcaoSistema)     = Sim (status final)
```

**Exemplo de dados com novos campos:**
```
RPO_cielo (Dias úteis, formato brasileiro):
requisicao | status   | created_at | data_abertura_vaga | dias_abertura_ate_status
2669353    | PROPOSTA | 2025-12-22 | 2025-10-24         | 40
2669353    | FECHADA  | 2026-01-13 | 2025-10-24         | 55

RPO_semper_laser (Dias úteis, formato americano):
requisicao | status | created_at | data_abertura_vaga | dias_abertura_ate_status
1287       | Offer  | 2026-01-06 | 2025-10-24         | 50
1287       | Filled | 2026-01-06 | 2025-10-24         | 50
```

**Para atualizar os dados:**
```sql
REFRESH MATERIALIZED VIEW "RPO_cielo"."MV_CONSUMO_historicoVagas";
REFRESH MATERIALIZED VIEW "RPO_semper_laser"."MV_CONSUMO_historicoVagas";
```

**Estatísticas atuais (2026-02-03):**
| Schema | mv_CONSUMO_vagas | MV_CONSUMO_historicoVagas | MV_CONSUMO_candidatos | MV_CONSUMO_ERROS_VAGAS |
|--------|------------------|---------------------------|-----------------------|------------------------|
| RPO_cielo | 171 | 721 (incl. 17 waiting to start) | 1010 | 75 |
| RPO_semper_laser | 62 | 379 | 162 | 12 |

**Tabelas de histórico (2026-02-03):**
| Schema | USO_historicoVagas | USO_historicoCandidatos |
|--------|-------------------|------------------------|
| RPO_cielo | ~595 registros | ~1107 registros |
| RPO_semper_laser | 400 registros (PG = fonte da verdade) | 170 registros (importados da planilha) |

**Nota:** Em semper_laser, alguns registros são de status "waiting to start" gerados dinamicamente (não vêm de USO_historicoVagas). O time_to_fill usa contagem inclusiva (mesmo dia = 1).

### Função dashboard_criar_mv_consumo_candidatos (PostgreSQL) - VERSÃO 2.0 COM SUPORTE A VERSÃO

**Assinatura:** `public.dashboard_criar_mv_consumo_candidatos(p_schema TEXT, p_versao TEXT DEFAULT NULL)`

**Uso:**
```sql
SELECT dashboard_criar_mv_consumo_candidatos('RPO_cielo');
SELECT dashboard_criar_mv_consumo_candidatos('RPO_semper_laser');
SELECT dashboard_criar_mv_consumo_candidatos('RPO_cielo', 'V2');  -- cria V2_MV_CONSUMO_candidatos
```

**O que faz:**
Cria a materialized view `MV_CONSUMO_candidatos` expandindo o campo `operacao_posicoesconsideradas` em múltiplas linhas - uma para cada requisição considerada pelo candidato.

**Arquivo:** `sql/dashboard_criar_mv_consumo_candidatos.sql`

**Formatos suportados:**
- **cielo**: `[REQUISICAO] - TITULO (local) --- <STATUS>` - separador: `, [`
- **semper_laser**: `TITULO --- (loja) --- REQUISICAO` - separador: `, `

**Campos:**
- Todos os campos de `vw_candidatos_nomeFixo`
- `requisicao` (TEXT): Requisição extraída do campo `operacao_posicoesconsideradas`

**Exemplo de expansão:**
```
Candidato original:
| id | nome | operacao_posicoesconsideradas |
| 10 | João | [50001] - Cargo A, [50002] - Cargo B |

MV_CONSUMO_candidatos (expandido):
| id | nome | requisicao |
| 10 | João | 50001      |
| 10 | João | 50002      |
```

**Para atualizar os dados:**
```sql
REFRESH MATERIALIZED VIEW "RPO_cielo"."MV_CONSUMO_candidatos";
REFRESH MATERIALIZED VIEW "RPO_semper_laser"."MV_CONSUMO_candidatos";
```

**Estatísticas atuais:**
| Schema | Total Linhas | Candidatos Únicos | Requisições Únicas |
|--------|--------------|-------------------|-------------------|
| RPO_cielo | 1010 | 1006 | 42 |
| RPO_semper_laser | 117 | 116 | 22 |

### Função dashboard_criar_mv_consumo_erros_vagas (PostgreSQL) - VERSÃO 2.0 COM SUPORTE A VERSÃO

**Assinatura:** `public.dashboard_criar_mv_consumo_erros_vagas(p_schema TEXT, p_versao TEXT DEFAULT NULL)`

**Uso:**
```sql
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cielo');
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_semper_laser');
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cielo', 'V2');  -- cria V2_MV_CONSUMO_ERROS_VAGAS
```

**O que faz:**
Cria a materialized view `MV_CONSUMO_ERROS_VAGAS` que identifica erros e inconsistências nos dados de vagas.

**Arquivo:** `sql/dashboard_criar_mv_consumo_erros_vagas.sql`

**Colunas:**
| Campo | Tipo | Descrição |
|-------|------|-----------|
| `requisicao` | TEXT | Identificador da vaga |
| `vaga_titulo` | TEXT | Título da vaga |
| `recrutador` | TEXT | Recrutador responsável |
| `erro` | TEXT | Tipo de erro encontrado |
| `dado_erro` | TEXT | Dado que causou o erro (NULL se não aplicável) |

**Erros detectados:**
| # | Erro | Descrição |
|---|------|-----------|
| 1 | `data_abertura vazia` | data_abertura NULL ou vazia |
| 1b | `data_abertura formato inválido` | Não é DD/MM/YYYY nem YYYY-MM-DD |
| 1c | `data_abertura futura` | Data posterior a CURRENT_DATE |
| 2a | `data_admissao futura` | data_admissao posterior a CURRENT_DATE |
| 2b | `data_admissao anterior ao fechamento` | data_admissao antes do created_at do status Fechada |
| 2c | `historico anterior a abertura (status)` | Registro em USO_historicoVagas com created_at antes de data_abertura |
| 3a | `requisicao vazia` | requisicao NULL ou vazia |
| 3b | `requisicao duplicada (N ocorrências)` | requisicao aparece mais de uma vez |
| 4a | `sla_utilizado vazio` | sla_utilizado NULL ou vazio |
| 4b | `sla_utilizado inconsistente` | sla_utilizado não corresponde a nenhuma coluna em USO_statusVagas |
| 5a | `status vazio` | status NULL ou vazio |
| 5b | `status não cadastrado` | status não presente em USO_statusVagas |

**Detalhes técnicos:**
- Busca formato de datas em USO_configuracoesGerais (brasileiro/americano)
- Usa TO_CHAR(h.created_at, v_formato_pg) para consistência no dado_erro (ambas datas no mesmo formato)
- Validação de SLA verifica coluna com e sem trailing `_` (ex: `Sales_Coordinator` e `Sales_Coordinator_`)
- Exclui colunas fixas de USO_statusVagas da verificação de SLA: status, fimFluxo, sequencia, responsavel, funcaoSistema, _airbyte_*

**Estatísticas atuais (2026-02-03):**
| Schema | Total Erros |
|--------|-------------|
| RPO_cielo | 75 |
| RPO_semper_laser | 12 |

### Regras de Remoção de Colunas (aplicadas pelas funções)

**Colunas sempre removidas das views:**
1. Todas as colunas que iniciam com `_airbyte_*`
2. Na view de vagas, os seguintes campos de operação/ocorrência:
   - `operacao_atraso_status` (Lagging)
   - `operacao_SLA_status` (Status_SLA)
   - `operacao_status_ultima_proposta` (Last_offer_status)
   - `ocorrencia_proposta` (Offer_Letters_Sent)
   - `operacao_dias_status` (Workdays_on_status)
   - `ocorrencia_status` (Current_status_occurences)
   - `operacao_selecionado_ultima_proposta` (Last_offer_Selected_Candidate)
   - `operacao_motivo_declinio_ultima_proposta` (Last_offer_declination_reason)

**Mapeamento vagas (vw_vagas_nomeFixo) - DINÂMICO:**

O mapeamento é lido da tabela `USO_dicionarioVagas` de cada schema.
A quantidade de colunas varia conforme o dicionário do cliente.

Colunas removidas automaticamente (campos calculados):
- operacao_atraso_status, operacao_SLA_status
- operacao_status_ultima_proposta, ocorrencia_proposta
- operacao_dias_status, ocorrencia_status
- operacao_selecionado_ultima_proposta, operacao_motivo_declinio_ultima_proposta

Exemplo de colunas comuns:
| nomeAmigavel (dicionário) | nomeFixo (view) |
|---------------------------|-----------------|
| Status | status |
| Posição/Requisição | requisicao |
| Data de abertura | data_abertura |
| Cargo/Título | vaga_titulo |
| SLA Utilizado | sla_utilizado |
| Salário | vaga_salario |
| Recrutador | operacao_recrutador |
| Gestor | gestao_gestor |
| Data de admissão | data_admissao |
| Nome do selecionado | selecionado_nome |
| Origem do selecionado | selecionado_fonte |

**Mapeamento candidatos (vw_candidatos_nomeFixo) - DINÂMICO:**

O mapeamento é lido da tabela `USO_dicionarioCandidatos` de cada schema.
A quantidade de colunas varia conforme o dicionário do cliente.

Exemplo de colunas comuns:
| nomeAmigavel (dicionário) | nomeFixo (view) |
|---------------------------|-----------------|
| ID do candidato | id_candidato |
| Nome do candidato | nome_candidato |
| Status do candidato | status_candidato |
| Recrutador | operacao_recrutador |
| Origem do candidato | candidato_origem |
| Vaga aplicada | vaga_titulo |
| Expectativa salarial | vaga_salario |
| Telefone | telefone_candidato |
| Email | contatos_candidato |
| Cidade/Estado | localidade_candidato |
| Observações | observacao_candidato |

<!-- CHAPTER: 4 Arquitetura -->

## Arquitetura

### Stack Tecnológico
- Python 3.x
- PostgreSQL (banco HUB)
- Streamlit ou Dash (a definir para visualização)

### Estrutura de Arquivos
```
RPO_dashboard/
├── .claude/
│   ├── memory.md                                   # Este arquivo
│   ├── commands/ → symlink                         # Comandos compartilhados
│   └── settings.local.json → symlink               # Permissões compartilhadas
├── config/
│   └── dashboards.yaml                             # Configurações dos dashboards
├── sql/
│   ├── dashboard_criar_views.sql                    # Views dinâmicas + mv_CONSUMO_vagas (v3.0 com versão)
│   ├── dashboard_criar_mv_consumo_historico_vagas.sql # MV histórico (v4.0 com versão)
│   ├── dashboard_criar_mv_consumo_candidatos.sql    # MV candidatos expandida (v2.0 com versão)
│   └── dashboard_criar_mv_consumo_erros_vagas.sql   # MV erros de vagas (v2.0 com versão)
├── dashboards/
│   └── semper_laser/                               # Dashboard específico do cliente
├── documentacao/                                   # Docs detalhadas
├── README.md                                       # Orientações gerais
└── .env                                            # Credenciais do banco
```

### Conexão com Banco de Dados

**IMPORTANTE - NUNCA inventar credenciais!**
Sempre usar o arquivo `.env` na raiz do projeto para obter as credenciais do banco:

```bash
source /home/cazouvilela/projetos/RPO_dashboard/.env
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p $DB_PORT -U $DB_USER -d $DB_NAME
```

**Configuração atual (.env):**
- **Host**: /var/run/postgresql (socket Unix local)
- **Porta**: 5432
- **Banco**: HUB
- **Usuário**: cazouvilela
- **Schemas**: RPO_[cliente]

<!-- CHAPTER: 5 Funcionalidades -->

## Funcionalidades

### Implementadas
- [Nenhuma ainda]

### Em Desenvolvimento
- Estrutura base do projeto
- Dashboard semper_laser

<!-- CHAPTER: 6 Configurações -->

## Configurações

**Variáveis de Ambiente**:
- DATABASE_URL: Conexão com PostgreSQL
- [outras a definir]

**Caminhos Importantes**:
- config/dashboards.yaml: Registro de todos os dashboards

<!-- CHAPTER: 6.5 Customizações por Cliente -->

## Customizações por Cliente

### semper_laser - Geolocalização (USO_Listas)

**Implementado em:** 2026-01-27

A tabela `USO_Listas` mapeia lojas para cidades e estados, permitindo geolocalização das vagas.

**Tabela de origem:** `RAW_AIRBYTE_Listas`

**Campos:**
| Campo | Descrição |
|-------|-----------|
| `Lojas_` | Código/nome da loja (chave para geo_local) |
| `City_` | Nome da cidade |
| `State_` | Estado (ex: "Florida (FL)") |

**Criação da tabela:**
```sql
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_Listas";
CREATE TABLE "RPO_semper_laser"."USO_Listas" AS
SELECT "City_", "Lojas_", "State_"
FROM "RPO_semper_laser"."RAW_AIRBYTE_Listas";
```

**Campos adicionados em mv_CONSUMO_vagas:**
| Campo | Descrição |
|-------|-----------|
| `geo_city` | Cidade da loja (ex: "South Miami") |
| `geo_state` | Estado da loja (ex: "Florida (FL)") |
| `geo_location` | Cidade + Estado concatenados (ex: "South Miami - Florida (FL)") |

**Como funciona:**
- A função `dashboard_criar_mv_consumo_vagas()` detecta automaticamente se existe a tabela `USO_Listas` no schema
- Se existir, faz LEFT JOIN com `mv_CONSUMO_vagas` usando `geo_local = Lojas_`
- Os campos geo são incluídos automaticamente na MV
- Se a tabela não existir, a função funciona normalmente sem os campos geo

**Para outros clientes:**
Se um cliente tiver tabela de lojas/locais similar, criar `USO_Listas` com a mesma estrutura (Lojas_, City_, State_) e os campos geo serão incluídos automaticamente.

### semper_laser - Histórico Original e Status "waiting to start"

**Implementado em:** 2026-01-28

O cliente semper_laser possuía uma tabela de histórico original que foi usada para popular inicialmente o `USO_historicoVagas`. Esses objetos foram renomeados com prefixo BACKUP_ pois não são mais necessários.

**Tabelas de backup (não utilizadas):**
- `BACKUP_HISTORICO_ORIGINAL_Job_Openings_Control` - Tabela original
- `BACKUP_vw_historico_original` - View de expansão
- `BACKUP_vw_historico_importado` - View de importação

**Status que foram importados da tabela HISTORICO_ORIGINAL:**
| Status | Campo de Data na Origem | Tabela Fonte |
|--------|-------------------------|--------------|
| Open | Position_Created_Date_ADP | USO_Job_Openings_Control |
| Screening | Job_Posting_Date | HISTORICO_ORIGINAL |
| Interviewing | HR_Interview_Start_Date | HISTORICO_ORIGINAL |
| Interviewing QT | _1st_Date_Candidates_Sent_to_QT | HISTORICO_ORIGINAL |
| Interviewing Hiring Manager | _1st_Date_Candidates_Sent_to_Hiring_Manager | HISTORICO_ORIGINAL |
| Salary Approval | Salary_Approval___Email_Sent_Date | HISTORICO_ORIGINAL |
| BG Check | BG_Check_Sent_Date | HISTORICO_ORIGINAL |
| Offer | Offer_Letter_Sent_Date | HISTORICO_ORIGINAL |
| Cancelled – No Hire | Position_Cancellation_Date__when_applicable_ | HISTORICO_ORIGINAL |
| Filled | GREATEST(Offer_Accepted_Date, BG_Check_Result_Date) | HISTORICO_ORIGINAL |

**Regra especial para data de Filled:**
- A data de `created_at` do status Filled é a **maior** entre `Offer_Accepted_Date` e `BG_Check_Result_Date`
- Se `BG_Check_Result_Date` for inválida ou vazia, usa apenas `Offer_Accepted_Date`
- Isso garante que o Filled só ocorre após ambos os processos (aceite + resultado do BG Check)
- Impacta diretamente a data de início do "waiting to start" (que usa `created_at` do Filled)

**Campos calculados na importação (time_to_fill e time_to_start):**

| Campo | Fórmula | Contagem | Aplicado a |
|-------|---------|----------|------------|
| `time_to_fill` | data_abertura (USO) → data Filled (HIST) | Dias úteis com feriados | Apenas status Filled |
| `time_to_fill_no_holidays` | data_abertura (USO) → data Filled (HIST) | Dias úteis sem feriados | Apenas status Filled |
| `time_to_start` | data_abertura (USO) → Start_Date__Admission_ (USO) | Dias úteis com feriados | Todos com Start_Date |
| `time_to_start_no_holidays` | data_abertura (USO) → Start_Date__Admission_ (USO) | Dias úteis sem feriados | Todos com Start_Date |

**IMPORTANTE - Contagem de dias INCLUSIVA:**
- Todos os cálculos de `time_to_fill` e `time_to_start` usam contagem **inclusiva** (ambas as datas contam)
- Exemplo: abertura em 10/01 e filled em 10/02 = **2 dias** (não 1)
- Mesmo dia (abertura = filled) = **1 dia** (não 0)
- Implementação: `generate_series(data_inicio, data_fim, '1 day')` sem subtrair intervalo do fim

**Status especial "waiting to start":**
| Propriedade | Valor |
|-------------|-------|
| sequencia_status | 9999 (virtual, definido apenas na MV) |
| fimFluxo | Sim |
| funcaoSistema | Aguardando |
| responsavel | CONSULTORIA |

**IMPORTANTE - "waiting to start" é gerado APENAS na MV:**
- Este status NÃO é armazenado na tabela `USO_historicoVagas`
- É gerado dinamicamente pela função `dashboard_criar_mv_consumo_historico_vagas()` diretamente na `MV_CONSUMO_historicoVagas`
- Identificado pelo campo `alterado_por = 'gerado_mv'`

**Implementação semper_laser (v3.4 - campos específicos):**
- Usa campos da tabela `USO_Job_Openings_Control` (tabela de vagas)
- `created_at` = `created_at` do status Filled em `USO_historicoVagas` (GREATEST entre Offer_Accepted e BG_Check_Result)
- `status_fim` = campo `Start_Date__Admission_` da tabela `USO_Job_Openings_Control` (data de admissão)
- Só é incluído se `Offer_accepted_` e `Start_Date__Admission_` são válidos (formato MM/DD/YYYY)

**Implementação genérica/cielo (v3.9 - usando data_admissao):**
- Ativado quando o schema tem `data_admissao` em `vw_vagas_nomeFixo` e `funcaoSistema='Fechada'` em `USO_statusVagas`
- `created_at` = `created_at` do status com funcaoSistema='Fechada' em `USO_historicoVagas`
- `status_fim` = `data_admissao` da `vw_vagas_nomeFixo` (convertido conforme formato configurado)
- Só é incluído se data_admissao é válida e a requisição tem status Fechada no histórico
- Colunas da UNION são construídas dinamicamente verificando cada coluna de USO_historicoVagas contra vw_vagas_nomeFixo

**Regras comuns:**
- `dias_no_status` = dias úteis/corridos entre `created_at` e `status_fim` (não retorna 0 mesmo sendo fimFluxo = Sim)
- A requisição deve existir em `mv_CONSUMO_vagas`

**Nota:** A tabela `HISTORICO_ORIGINAL_Job_Openings_Control` é utilizada ativamente para importação histórica. Todas as datas seguem o formato configurado em `USO_configuracoesGerais` (americano = MM/DD/YYYY para semper_laser).

**IDs com sufixo alfanumérico:**
- Alguns IDs possuem sufixo (ex: 1291A, 1291B) quando uma posição original foi dividida
- O sistema suporta IDs alfanuméricos sem restrição

**Filtros aplicados na view vw_historico_original:**
- `ID_Position_ADP` (requisicao) não vazio
- Campo de data no formato válido (MM/DD/YYYY) - usa regex `^\d{1,2}/\d{1,2}/\d{4}$`
- Registros com datas inválidas (texto, NULL, vazio) são ignorados

<!-- CHAPTER: 6.7 V2 Dashboard Versioning -->

## V2 Dashboard Versioning

### Conceito

A V2 é uma versão paralela do dashboard que permite trabalhar com dados atualizados (fontes RAW_AIRBYTE_) sem alterar o dashboard V1 em produção. Todos os objetos V2 usam o prefixo `V2_`.

**Status atual:** Implementado apenas para RPO_cielo.

### Convenção de Nomenclatura

- **Prefixo `V2_`** em TODOS os objetos da versão 2 (tabelas, views, materialized views)
- Exemplos: `V2_USO_vagas`, `V2_vw_vagas_nomeFixo`, `V2_mv_CONSUMO_vagas`
- **NÃO usar sufixo** `_V2` (regra alterada durante implementação)

### Regras de Criação de Tabelas V2_USO_

As tabelas V2_USO_ são cópias das tabelas de origem, mas com fontes específicas:

| Tabela V2 | Fonte | Motivo |
|-----------|-------|--------|
| `V2_USO_vagas` | `RAW_AIRBYTE_vagas` | Dados atualizados do Airbyte |
| `V2_USO_candidatos` | `RAW_AIRBYTE_candidatos` | Dados atualizados do Airbyte |
| `V2_USO_statusVagas` | `RAW_AIRBYTE_statusVagas` | Dados atualizados do Airbyte |
| `V2_USO_statusCandidatos` | `RAW_AIRBYTE_statusCandidatos` | Dados atualizados do Airbyte |
| `V2_USO_configuracoesGerais` | `RAW_AIRBYTE_configuracoesGerais` | Dados atualizados do Airbyte |
| `V2_USO_feriados` | `RAW_AIRBYTE_feriados` | Dados atualizados do Airbyte |
| `V2_USO_dicionarioVagas` | `RAW_dicionarioVagas` | Não existe versão RAW_AIRBYTE_ |
| `V2_USO_dicionarioCandidatos` | `RAW_dicionarioCandidatos` | Não existe versão RAW_AIRBYTE_ |
| `V2_USO_historicoVagas` | `USO_historicoVagas` | Não existe fonte RAW (dados gerados pela API) |
| `V2_USO_historicoCandidatos` | `USO_historicoCandidatos` | Não existe fonte RAW (dados gerados pela API) |

### Regras de Fonte (CRÍTICO)

1. **RAW_AIRBYTE_*** - Fonte padrão para maioria das tabelas (vagas, candidatos, statusVagas, statusCandidatos, configuracoesGerais, feriados)
2. **RAW_*** (sem AIRBYTE) - Apenas para dicionários (dicionarioVagas, dicionarioCandidatos), pois não existe versão RAW_AIRBYTE_
3. **USO_*** - Exceção para históricos (historicoVagas, historicoCandidatos), pois não existe fonte RAW/RAW_AIRBYTE_
4. **PROIBIDO**: NÃO usar `RAW_statusVagas` nem `RAW_statusCandidatos` (sem prefixo AIRBYTE) como fonte. Usar SEMPRE `RAW_AIRBYTE_statusVagas` e `RAW_AIRBYTE_statusCandidatos`

### Criação das Tabelas V2

```sql
-- ============================================================
-- V2: CRIAÇÃO DE TABELAS (RPO_cielo)
-- ============================================================

-- Fonte: RAW_AIRBYTE_*
CREATE TABLE "RPO_cielo"."V2_USO_vagas" AS SELECT * FROM "RPO_cielo"."RAW_AIRBYTE_vagas";
CREATE TABLE "RPO_cielo"."V2_USO_candidatos" AS SELECT * FROM "RPO_cielo"."RAW_AIRBYTE_candidatos";
CREATE TABLE "RPO_cielo"."V2_USO_statusVagas" AS SELECT * FROM "RPO_cielo"."RAW_AIRBYTE_statusVagas";
CREATE TABLE "RPO_cielo"."V2_USO_statusCandidatos" AS SELECT * FROM "RPO_cielo"."RAW_AIRBYTE_statusCandidatos";
CREATE TABLE "RPO_cielo"."V2_USO_configuracoesGerais" AS SELECT * FROM "RPO_cielo"."RAW_AIRBYTE_configuracoesGerais";
CREATE TABLE "RPO_cielo"."V2_USO_feriados" AS SELECT * FROM "RPO_cielo"."RAW_AIRBYTE_feriados";

-- Fonte: RAW_* (sem AIRBYTE - não existe versão AIRBYTE para dicionários)
CREATE TABLE "RPO_cielo"."V2_USO_dicionarioVagas" AS SELECT * FROM "RPO_cielo"."RAW_dicionarioVagas";
CREATE TABLE "RPO_cielo"."V2_USO_dicionarioCandidatos" AS SELECT * FROM "RPO_cielo"."RAW_dicionarioCandidatos";

-- Fonte: USO_* (exceção - não existe fonte RAW para históricos)
CREATE TABLE "RPO_cielo"."V2_USO_historicoVagas" AS SELECT * FROM "RPO_cielo"."USO_historicoVagas";
CREATE TABLE "RPO_cielo"."V2_USO_historicoCandidatos" AS SELECT * FROM "RPO_cielo"."USO_historicoCandidatos";

-- Permissões
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "RPO_cielo" TO rpo_user;
```

### Criar Views e MVs V2

As funções agora suportam o parâmetro `p_versao`. Para criar os objetos V2:

```sql
-- Criar views e MVs V2 (usar após criar tabelas V2_USO_)
SELECT dashboard_criar_views('RPO_cielo', 'V2');
SELECT dashboard_criar_mv_consumo_vagas('RPO_cielo', 'V2');
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cielo', 'V2');
SELECT dashboard_criar_mv_consumo_candidatos('RPO_cielo', 'V2');
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cielo', 'V2');
```

Objetos criados: `V2_vw_vagas_nomeFixo`, `V2_vw_candidatos_nomeFixo`, `V2_mv_SLAs`, `V2_mv_CONSUMO_vagas`, `V2_MV_CONSUMO_historicoVagas`, `V2_MV_CONSUMO_candidatos`, `V2_MV_CONSUMO_ERROS_VAGAS`

<!-- CHAPTER: 7 Troubleshooting -->

## Troubleshooting

### Bug: JOIN falha por espaços no final dos valores (Corrigido em 2026-01-23)

**Problema:** Os campos agregados de `USO_statusVagas` (funcao_sistema, sequencia_status, etc.) apareciam como NULL na `MV_CONSUMO_historicoVagas` mesmo quando o status existia na tabela.

**Causa raiz:** Espaços no final dos valores na coluna `status` da tabela `USO_statusVagas`.
- Exemplo: `"Offer "` (6 chars) vs `"Offer"` (5 chars)
- O JOIN `sv.status = ho.status` falhava porque os valores não eram iguais

**Diagnóstico:**
```sql
-- Verificar espaços em campos de chave
SELECT
    status,
    LENGTH(status) as tamanho,
    LENGTH(TRIM(status)) as tamanho_trim,
    CASE WHEN LENGTH(status) <> LENGTH(TRIM(status)) THEN 'TEM ESPAÇO' ELSE 'OK' END as problema
FROM "RPO_cliente"."USO_statusVagas";
```

**Solução aplicada:**
1. Correção dos dados na tabela `USO_statusVagas`:
   ```sql
   UPDATE "RPO_semper_laser"."USO_statusVagas"
   SET status = TRIM(status)
   WHERE LENGTH(status) <> LENGTH(TRIM(status));
   ```

2. Medida preventiva nas funções SQL - todos os JOINs agora usam `TRIM()`:
   ```sql
   -- Antes (vulnerável):
   LEFT JOIN USO_statusVagas sv ON sv.status = ho.status

   -- Depois (protegido):
   LEFT JOIN USO_statusVagas sv ON TRIM(sv.status) = TRIM(ho.status)
   ```

**Arquivos alterados:**
- `sql/dashboard_criar_views.sql` - TRIM em todos os JOINs com status/requisicao
- `sql/dashboard_criar_mv_consumo_historico_vagas.sql` - TRIM em todos os JOINs com status/requisicao

**Prevenção:** Ao importar dados do Airbyte, verificar se há espaços no final dos campos de chave (status, requisicao)

### Bug: Erro de formato de data em USO_feriados (Corrigido em 2026-02-02)

**Problema:** A função `dashboard_criar_mv_consumo_vagas()` falhava com erro de formato de data ao calcular dias úteis.

**Causa raiz:** A função usava formato hardcoded `DD/MM/YYYY` para feriados.

**Solução aplicada:** A função `dashboard_criar_mv_consumo_vagas()` agora usa `v_formato_pg` (formato configurado) para parsing de feriados. Não é mais necessário converter o formato dos feriados manualmente.

### Bug: Permissões insuficientes para rpo_user (Corrigido em 2026-02-02)

**Problema:** O usuário `rpo_user` (usado pela API do RPO-V4) não conseguia acessar tabelas e views criadas no PostgreSQL. Erros como "permissão negada para tabela" ou "relação não existe" ocorriam ao tentar SELECT.

**Causa raiz:** As tabelas USO_ e views/MVs eram criadas pelo usuário `cazouvilela`, mas sem GRANT explícito para `rpo_user`. Quando a API tentava acessar usando `rpo_user`, recebia erro de permissão.

**Diagnóstico:**
```sql
-- Verificar owner e permissões de uma tabela
SELECT
    schemaname, tablename, tableowner,
    has_table_privilege('rpo_user', schemaname || '.' || tablename, 'SELECT') as pode_select
FROM pg_tables
WHERE schemaname = 'RPO_cliente';

-- Verificar se tabela existe mas rpo_user não vê no information_schema
-- (information_schema só mostra objetos que o usuário tem permissão de ver)
SELECT * FROM pg_class WHERE relname = 'USO_historicoVagas';  -- admin vê
SELECT * FROM information_schema.tables WHERE table_name = 'USO_historicoVagas';  -- rpo_user não vê
```

**Soluções aplicadas:**

1. **Funções SQL atualizadas:** Todas as funções de criação de views/MVs agora incluem GRANT automaticamente:
   ```sql
   -- Todas as funções dashboard_criar_* incluem GRANT automaticamente
   -- Objetos versionados (V2_*) também recebem GRANT
   EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_vw_vagas);
   EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_mv_slas);
   -- etc. para cada objeto criado
   ```

2. **ETAPA 1.14 adicionada:** Comandos de GRANT para tabelas USO_ devem ser executados após criação.

**Para corrigir manualmente em schemas existentes:**
```sql
-- Conceder permissões em todas as tabelas existentes
GRANT USAGE ON SCHEMA "RPO_cliente" TO rpo_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "RPO_cliente" TO rpo_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA "RPO_cliente" TO rpo_user;

-- Configurar permissões padrão para novos objetos
ALTER DEFAULT PRIVILEGES IN SCHEMA "RPO_cliente" GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rpo_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA "RPO_cliente" GRANT USAGE, SELECT ON SEQUENCES TO rpo_user;
```

**Prevenção:** Sempre executar ETAPA 1.14 (GRANT) após criar tabelas USO_. As funções de criação de views/MVs agora concedem permissões automaticamente.

### Achado: Dados de origem com Position_Created = Offer_Accepted (semper_laser, 2026-02-02)

**Problema identificado:** A média de time-to-fill (dias da abertura até Filled) parecia muito baixa (~8 dias). Investigação revelou problema de qualidade nos dados de origem.

**Análise da tabela HISTORICO_ORIGINAL_Job_Openings_Control:**
```sql
-- Estatísticas de time-to-fill
SELECT
    COUNT(*) FILTER (WHERE TO_DATE("Position_Created_Date_ADP", 'MM/DD/YYYY') =
                          TO_DATE("Offer_Accepted_Date", 'MM/DD/YYYY')) AS same_day,
    COUNT(*) FILTER (WHERE TO_DATE("Offer_Accepted_Date", 'MM/DD/YYYY') -
                          TO_DATE("Position_Created_Date_ADP", 'MM/DD/YYYY') <= 7) AS under_7_days,
    COUNT(*) AS total_filled
FROM "RPO_semper_laser"."HISTORICO_ORIGINAL_Job_Openings_Control"
WHERE "Offer_Accepted_Date" ~ '^\d{1,2}/\d{1,2}/\d{4}$';
```

**Resultados (2026-02-02):**
| Métrica | Valor | % |
|---------|-------|---|
| Vagas filled total | 64 | 100% |
| Same day (0 dias) | 22 | 34% |
| Até 7 dias | 37 | 58% |

**Causa provável:**
1. Dados retroativos - vagas já estavam preenchidas quando foram cadastradas no sistema
2. Problema no import/sync da planilha original
3. Preenchimento manual incorreto das datas

**Impacto:**
- mv_CONSUMO_vagas mostra `dias_da_abertura = 0` para 18 posições Filled
- Média de time-to-fill ficou em **16.60 dias** (não 8.12 como reportado anteriormente)
- Distorção nas métricas de eficiência do recrutamento

**Exemplos de registros problemáticos:**
| requisicao | Position_Title | Position_Created | Offer_Accepted |
|------------|---------------|------------------|----------------|
| 1244 | Sales Coordinator | 08/01/2025 | 8/1/2025 |
| 1259 | Sales Coordinator | 08/14/2025 | 8/14/2025 |
| 1268 | Sales Coordinator | 11/19/2025 | 11/19/2025 |

**Não é erro de import:** A verificação mostrou que as datas estão sendo importadas e convertidas corretamente. O problema está nos dados de origem da planilha.

**Recomendação:** Reportar ao cliente para revisão das datas na planilha original. Com contagem inclusiva, mesmo-dia = 1 dia (não mais 0).

### Achado: 19 IDs em HISTORICO_ORIGINAL sem correspondência em USO/RAW (semper_laser, 2026-02-03)

**Problema identificado:** 19 IDs presentes em `HISTORICO_ORIGINAL_Job_Openings_Control` não aparecem na `MV_CONSUMO_historicoVagas`.

**Causa:**
- 18 IDs não existem em `USO_Job_Openings_Control` nem em `RAW_AIRBYTE_Job_Openings_Control` (posições removidas da planilha ativa)
- 1 ID (1277) existe na USO mas com `data_abertura` futura (10/03/2026), excluído pelo filtro

**IDs ausentes:** 1219, 1232, 1238, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253, 1255, 1259, 1263, 1266, 1277, 1286

**Impacto:** Esses registros históricos não são processados. Para incluí-los, as posições precisam ser adicionadas na planilha ativa (RAW).

### Bug: Corrupção de dados históricos - datas futuras e IDs desalinhados (Corrigido em 2026-02-03)

**Problema:** Datas futuras aparecendo nas planilhas de historicoCandidatos e historicoVagas (Cielo e Semper Laser). Exemplo: datas como 03/10/2026 quando deveria ser 10/03/2026.

**Causa raiz (3 fatores encadeados):**

1. **Script de importação `carregar_historico_planilha.py`** tinha parsing de datas com formato americano (MM/DD/YYYY) antes do brasileiro (DD/MM/YYYY). Para datas ambíguas (dia <= 12), o parser americano acertava primeiro e invertia mês/dia, gerando datas futuras.

2. **O mesmo script** excluía a coluna `id` no INSERT (linha 370: `col != 'id'`), fazendo o PostgreSQL auto-gerar IDs via SERIAL. Resultado: IDs no PG (ex: 74-668 para Cielo) não correspondiam aos IDs da planilha (1-507).

3. **O worker `worker_sheets_sync.js`** procurava o ID do PG na coluna A da planilha. Com IDs desalinhados, encontrava a linha errada e sobrescrevia dados de outros registros. 51 vagas e 315 candidatos corrompidos em Cielo.

**Correções aplicadas:**

**Cielo:**
- Restaurados 51 registros de vagas da aba "Cópia de historicoVagas" (fonte da verdade)
- Restaurados 315 registros de candidatos da aba "Cópia de historicoCandidatos"
- Atualizadas datas no PG usando Cópia como referência (107 vagas, 76 candidatos)
- IDs na planilha realinhados com IDs do PG (595 vagas, 45 candidatos)
- Resultado: 0 datas futuras em vagas e candidatos

**Semper Laser:**
- **Vagas**: PG é fonte da verdade (editado diretamente durante criação do dashboard). Planilha limpa e recarregada com 400 registros do PG.
- **Candidatos**: Restaurados 35 registros corrompidos da aba "Cópia de historicoCandidatos"
- Resultado: 0 datas futuras (exceto 1 registro PG ID 16 com data_abertura futura 10/03/2026 - dado de origem incorreto)

**Script corrigido** (`carregar_historico_planilha.py` linha 125-131):
```python
# Ordem corrigida: brasileiro ANTES de americano
formatos = [
    '%d/%m/%Y %H:%M:%S',  # Brasileiro (prioridade)
    '%Y-%m-%d %H:%M:%S',  # ISO
    '%Y-%m-%dT%H:%M:%S',  # ISO com T
    '%d/%m/%Y',            # Brasileiro sem hora
    '%Y-%m-%d',            # ISO sem hora
]
```

**IMPORTANTE - Abas de cópia nas planilhas:**
- "Cópia de historicoVagas" e "Cópia de historicoCandidatos" contêm dados corretos pré-corrupção
- Servem como backup/referência. NÃO excluir estas abas.

### Bug: Worker com formato de data hardcoded (Corrigido em 2026-02-03)

**Problema:** O worker `worker_sheets_sync.js` usava `formatDateBR()` hardcoded para DD/MM/YYYY, ignorando a configuração "Formato das datas" em `configuracoesGerais`. Semper Laser usa formato americano (MM/DD/YYYY) mas recebia datas em formato brasileiro.

**Correções no worker (`/home/cazouvilela/projetos/RPO-V4/api_historico/worker_sheets_sync.js`):**

1. **`getDateFormat(spreadsheetId)`** - Lê "Formato das datas" da aba `configuracoesGerais`, cache de 10 minutos, default `brasileiro`
2. **`formatDate(date, formato)`** - Substitui `formatDateBR()`. Suporta `brasileiro` (DD/MM/YYYY) e `americano` (MM/DD/YYYY)
3. **`syncSchema()`** (vagas) - Busca `dateFormat` e passa para `convertRowToSheetFormat()` e `upsertRowInSheet()`
4. **`syncSchemaCandidatos()`** - Busca `dateFormat` e passa para `convertRowToSheetFormatCandidatos()`

**Fluxo de datas verificado end-to-end:**
- **Apps Script** -> API: NÃO envia datas, apenas dados de negócio
- **API** -> PostgreSQL: Usa `NOW()` para `created_at`/`updated_at` (sempre correto)
- **Worker** -> Planilha: Lê timestamp do PG e formata conforme `configuracoesGerais`

### Fix: Worker quota protection (Implementado em 2026-02-03)

**Problema:** Worker consumia toda a quota do Google Sheets API (642.510 requisições, 96% com erro 429).

**Correções no worker:**
- `SYNC_INTERVAL_MS`: 30s -> 60s
- `MAX_ROWS_PER_CYCLE`: 10 linhas por schema por ciclo
- `THROTTLE_BETWEEN_SCHEMAS_MS`: 5s entre schemas
- `headersCache`: Cache de headers com TTL 5 min
- `withQuotaRetry()`: Exponential backoff para erros 429
- Sleep entre linhas: 1s -> 1.5s

### Fix: Tabela semper_laser candidatos normalizada (Corrigido em 2026-02-03)

**Problema:** `RPO_semper_laser.USO_historicoCandidatos` tinha estrutura Airbyte (colunas como `Candidate_ID`, `Ultima_atualizacao`, `id_do_historico`) em vez da estrutura normalizada usada pelo worker (que espera `id`, `updated_at`, `id_candidato`). Worker falhava com `coluna "updated_at" não existe`.

**Causa:** Tabela foi originalmente importada via Airbyte com nomenclatura diferente.

**Correção:**
1. Tabela estava vazia, então foi dropada e recriada com mesma estrutura de `RPO_cielo.USO_historicoCandidatos`:
   ```sql
   CREATE TABLE "RPO_semper_laser"."USO_historicoCandidatos" (
       id SERIAL PRIMARY KEY,
       id_candidato VARCHAR NOT NULL,
       status_candidato VARCHAR,
       status_micro_candidato VARCHAR,
       alterado_por VARCHAR,
       created_at TIMESTAMP NOT NULL DEFAULT NOW(),
       updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
       nome_candidato TEXT,
       contatos_candidato TEXT,
       localidade_candidato TEXT,
       telefone_candidato TEXT,
       vaga_salario TEXT,
       candidato_origem TEXT
   );
   ```
2. Dados importados da planilha historicoCandidatos (170 registros, IDs preservados da coluna A)
3. Sequence ajustada para max(id) = 171
4. 0 datas futuras após importação

**Worker status após correções (2026-02-03):**
Todos os 4 schemas rodando sem erros:
| Schema | Vagas | Candidatos |
|--------|-------|------------|
| RPO_template3 | OK | OK |
| RPO_cielo_dev | OK | OK |
| RPO_semper_laser | OK | OK |
| RPO_cielo | OK | OK |

**Serviço systemd:** `rpo-worker-sheets.service` (restart via `systemctl restart rpo-worker-sheets.service`)

### Nota: schemas.json - RPO_cielo e RPO_cielo_dev apontam para a mesma planilha

**Arquivo:** `/home/cazouvilela/projetos/RPO-V4/api_historico/schemas.json`

Ambos `RPO_cielo` e `RPO_cielo_dev` usam o mesmo `spreadsheetId`: `1swF0vtbgftzFIKXFnUAf3Osn9tkR3XB1J-Y3zxrhTN0`. O worker sincroniza ambos os schemas para a mesma planilha.

<!-- CHAPTER: 8 Próximas Features -->

## Próximas Funcionalidades

- [x] Estrutura base do projeto
- [x] Dashboard semper_laser (views e MVs criadas)
- [x] Dashboard cielo (views e MVs criadas)
- [x] MV_CONSUMO_historicoVagas (implementada nos 2 schemas)
- [x] MV_CONSUMO_ERROS_VAGAS (implementada nos 2 schemas)
- [x] V2 Dashboard - tabelas V2_USO_ criadas para cielo
- [x] V2 Dashboard - funções refatoradas com suporte a p_versao (dashboard_criar_*)
- [ ] Sistema de seleção de cliente ao iniciar
- [ ] Interface Streamlit para visualização

<!-- CHAPTER: 9 Referências -->

## Referências

- Projeto RPO-V4: /home/cazouvilela/projetos/RPO-V4
- [TEMPLATE_PROJETO.md](.claude/TEMPLATE_PROJETO.md) - Template de organização

---

**Última Atualização**: 2026-02-03
**Versão**: 2.1.0
**Status**: Em produção (ambos dashboards funcionando, worker com formato de data configurável)
