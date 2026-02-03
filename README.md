# RPO_dashboard

Dashboard para visualização e análise de dados das planilhas de RPO criadas no projeto RPO-V4.

## Estrutura

Este projeto controla dashboards diferentes para clientes diferentes. Cada dashboard possui:

| Parâmetro | Descrição |
|-----------|-----------|
| cliente | Identificador único do cliente |
| planilha | URL da planilha Google Sheets (referência) |
| banco | Banco PostgreSQL (HUB) |
| schema | Schema no banco (RPO_[cliente]) |
| configuracoes | Tabela de configurações específicas |

## Clientes Cadastrados

| Cliente | Schema | Formato datas | Contagem dias |
|---------|--------|---------------|---------------|
| semper_laser | `RPO_semper_laser` | americano (MM/DD/YYYY) | Dias úteis |
| cielo | `RPO_cielo` | brasileiro (DD/MM/YYYY) | Dias úteis |

## Funções SQL

Funções PostgreSQL para criação dinâmica de views e materialized views:

| Função | Arquivo | Descrição |
|--------|---------|-----------|
| `dashboard_criar_views` | `sql/dashboard_criar_views.sql` | Views dinâmicas (vw_vagas_nomeFixo, vw_candidatos_nomeFixo, mv_SLAs) |
| `dashboard_criar_mv_consumo_vagas` | `sql/dashboard_criar_views.sql` | MV de vagas processadas para dashboard |
| `dashboard_criar_mv_consumo_historico_vagas` | `sql/dashboard_criar_mv_consumo_historico_vagas.sql` | MV de histórico de vagas com campos calculados |
| `dashboard_criar_mv_consumo_candidatos` | `sql/dashboard_criar_mv_consumo_candidatos.sql` | MV de candidatos expandida por requisição |
| `dashboard_criar_mv_consumo_erros_vagas` | `sql/dashboard_criar_mv_consumo_erros_vagas.sql` | MV de erros e inconsistências nos dados |

Todas as funções suportam versionamento via parâmetro `p_versao` (ex: `'V2'`).

## Infraestrutura relacionada (RPO-V4)

| Componente | Descrição |
|------------|-----------|
| API (`server.js`) | REST API para CRUD de histórico (usa `NOW()` para timestamps) |
| Worker Sheets (`worker_sheets_sync.js`) | Sincroniza PostgreSQL -> Google Sheets (formato de data configurável) |
| Worker Valkey | Sincroniza Valkey -> PostgreSQL |
| Apps Script | Automação nas planilhas (envia dados para API) |

## Configuração

As configurações dos dashboards estão em `config/dashboards.yaml`.
Credenciais do banco em `.env`.

## Documentação

Documentação detalhada em [`.claude/memory.md`](.claude/memory.md).
