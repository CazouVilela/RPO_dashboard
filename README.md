# RPO_dashboard

Dashboard para visualização e análise de dados das planilhas de RPO criadas no projeto RPO-V4.

## Estrutura

Este projeto controla dashboards diferentes para clientes diferentes. Cada dashboard possui:

| Parâmetro | Descrição |
|-----------|-----------|
| cliente | Identificador único do cliente |
| planilha | URL da planilha Google Sheets (referência) |
| banco | Banco PostgreSQL onde os dados estão |
| schema | Schema no banco onde os dados estão |
| configuracoes | Tabela de configurações específicas |

## Clientes Cadastrados

- **semper_laser** - Schema: `RPO_semper_laser`

## Documentação

Toda a documentação detalhada está na pasta [`/documentacao`](./documentacao)

## Configuração

As configurações dos dashboards estão em `config/dashboards.yaml`
