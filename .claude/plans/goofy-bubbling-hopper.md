# Plano: Criar função `dashboard_criar_tabelas_uso`

## Resumo

Criar função SQL que automatiza a criação/recriação das tabelas USO_ (ou V2_USO_) a partir das tabelas RAW. Esta é a etapa 1 do processo de criação do dashboard, que hoje é manual.

## Arquivo

**Novo**: `sql/dashboard_criar_tabelas_uso.sql`

### Assinatura

```sql
CREATE OR REPLACE FUNCTION public.dashboard_criar_tabelas_uso(
    p_schema TEXT, p_versao TEXT DEFAULT NULL
) RETURNS TEXT AS $$
```

## Lógica

### 1. Determinar prefixo

- `p_versao = 'V2'` → prefixo `V2_`
- `p_versao IS NULL` → prefixo vazio

### 2. Dropar dependências (Views e MVs)

Antes de recriar tabelas USO_, dropar na ordem:
```
[prefix]MV_CONSUMO_historicoCandidatos CASCADE
[prefix]MV_CONSUMO_candidatos CASCADE
[prefix]MV_CONSUMO_historicoVagas CASCADE
[prefix]MV_CONSUMO_ERROS_VAGAS CASCADE
[prefix]MV_CONSUMO_vagas CASCADE
[prefix]MV_SLAs CASCADE
[prefix]vw_vagas_nomeFixo CASCADE
[prefix]vw_candidatos_nomeFixo CASCADE
```

### 3. Ler nomes dinâmicos de vagas/candidatos

Ler de `RAW_AIRBYTE_configuracoesGerais` (fonte direta, não da USO que pode estar desatualizada):
- `Nome da aba de controle vagas` → nome_vagas (ex: `vagas`, `Job_Openings_Control`)
- `Nome da aba de controle candidatos` → nome_candidatos (ex: `candidatos`, `Candidates_Control`)

Espaços substituídos por `_`.

### 4. Copiar tabelas (regras de fonte)

| Tabela USO_ | Fonte | Observação |
|---|---|---|
| `configuracoesGerais` | `RAW_AIRBYTE_configuracoesGerais` | Sempre |
| `dicionarioVagas` | `RAW_dicionarioVagas` | Sem AIRBYTE |
| `dicionarioCandidatos` | `RAW_dicionarioCandidatos` | Sem AIRBYTE |
| `statusVagas` | `RAW_AIRBYTE_statusVagas` | **NÃO** usar RAW_statusVagas |
| `statusCandidatos` | `RAW_AIRBYTE_statusCandidatos` | **NÃO** usar RAW_statusCandidatos |
| `feriados` | `RAW_AIRBYTE_feriados` | Sempre |
| `[nome_vagas]` | `RAW_AIRBYTE_[nome_vagas]` | Nome dinâmico |
| `[nome_candidatos]` | `RAW_AIRBYTE_[nome_candidatos]` | Nome dinâmico |
| `historicoVagas` | V2: `USO_historicoVagas` / V1: skip | V1 gerenciado pela API |
| `historicoCandidatos` | V2: `USO_historicoCandidatos` / V1: skip | V1 gerenciado pela API |
| `FALLBACK_historicoVagas` | `RAW_AIRBYTE_FALLBACK_historicoVagas` | Se existir |
| `FALLBACK_historicoCandidatos` | `RAW_AIRBYTE_FALLBACK_historicoCandidatos` | Se existir |

Para cada tabela:
1. Verificar se fonte existe (via `pg_tables`)
2. Se sim: `DROP TABLE IF EXISTS target; CREATE TABLE target AS SELECT * FROM source;`
3. Se não: pular e registrar no log
4. `GRANT SELECT ON target TO rpo_user;`

### 5. Tabelas customizadas (detecção automática)

Verificar se existe `RAW_AIRBYTE_Listas` no schema. Se sim, criar `[prefix]USO_Listas` com `SELECT * FROM RAW_AIRBYTE_Listas`.

### 6. Retorno

String com log de cada tabela criada, contagem de registros, e tabelas puladas.

## Implementação (resumo)

```sql
-- Para cada par (fonte, destino):
v_fonte := 'RAW_AIRBYTE_configuracoesGerais';
v_destino := v_prefixo || 'USO_configuracoesGerais';

-- Verificar existência da fonte
SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = p_schema AND tablename = v_fonte) INTO v_existe;

IF v_existe THEN
    EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', p_schema, v_destino);
    EXECUTE format('CREATE TABLE %I.%I AS SELECT * FROM %I.%I', p_schema, v_destino, p_schema, v_fonte);
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema, v_destino) INTO v_count;
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_destino);
    v_resultado := v_resultado || v_destino || ' ← ' || v_fonte || ' (' || v_count || ' registros)' || E'\n';
ELSE
    v_resultado := v_resultado || v_destino || ': fonte ' || v_fonte || ' NAO EXISTE, pulada' || E'\n';
END IF;
```

Usar loop com ARRAY de records para evitar repetição.

## Verificação

```sql
-- Testar V2 cielo
SELECT dashboard_criar_tabelas_uso('RPO_cielo', 'V2');
-- Verificar sequencia de CONGELADA
SELECT status, "sequencia" FROM "RPO_cielo"."V2_USO_statusVagas" WHERE status = 'CONGELADA';

-- Testar V1 semper_laser (historicos devem ser pulados)
SELECT dashboard_criar_tabelas_uso('RPO_semper_laser');
```
