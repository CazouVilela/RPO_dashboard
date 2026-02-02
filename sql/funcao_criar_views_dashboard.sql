-- ============================================================
-- Funcao: criar_views_dashboard(schema_name)
-- Cria views DINAMICAMENTE baseadas nos dicionarios:
-- - vw_vagas_nomeFixo (lido de USO_dicionarioVagas)
-- - vw_candidatos_nomeFixo (lido de USO_dicionarioCandidatos)
-- - mv_SLAs (SLAs em linhas)
-- ============================================================
-- VERSAO 2.0 - DINAMICA
-- As colunas sao lidas dos dicionarios, nao mais fixas no codigo.
-- Qualquer alteracao no dicionario reflete na view ao recriar.
-- ============================================================
-- REGRAS DE REMOCAO (APLICADAS AUTOMATICAMENTE):
-- 1. Colunas _airbyte_* sao sempre removidas
-- 2. View de vagas: remove campos de operacao/ocorrencia:
--    - operacao_atraso_status, operacao_SLA_status
--    - operacao_status_ultima_proposta, ocorrencia_proposta
--    - operacao_dias_status, ocorrencia_status
--    - operacao_selecionado_ultima_proposta
--    - operacao_motivo_declinio_ultima_proposta
-- ============================================================

-- Funcao auxiliar para normalizar nomes de colunas Airbyte
-- Ex: "Data de abertura" -> "Data_de_abertura"
-- Ex: "Posição" -> "Posicao"
-- Ex: "ID Position\nADP" -> "ID_Position_ADP"
CREATE OR REPLACE FUNCTION normalizar_nome_coluna(p_nome TEXT)
RETURNS TEXT AS $$
DECLARE
    v_resultado TEXT;
BEGIN
    v_resultado := p_nome;

    -- Remover quebras de linha e substituir por _
    v_resultado := REGEXP_REPLACE(v_resultado, E'[\r\n]+', '_', 'g');

    -- Substituir espacos por _
    v_resultado := REPLACE(v_resultado, ' ', '_');

    -- Remover acentos
    v_resultado := TRANSLATE(v_resultado,
        'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
        'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC');

    -- Substituir caracteres especiais
    v_resultado := REPLACE(v_resultado, '?', '_');
    v_resultado := REPLACE(v_resultado, '(', '');
    v_resultado := REPLACE(v_resultado, ')', '');
    v_resultado := REPLACE(v_resultado, '/', '_');
    v_resultado := REPLACE(v_resultado, '.', '');
    v_resultado := REPLACE(v_resultado, ',', '');
    v_resultado := REPLACE(v_resultado, ':', '');
    v_resultado := REPLACE(v_resultado, ';', '');

    -- Remover underscores duplicados
    v_resultado := REGEXP_REPLACE(v_resultado, '_+', '_', 'g');

    -- Remover underscore no final
    v_resultado := REGEXP_REPLACE(v_resultado, '_$', '');

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================
-- Funcao principal: criar_views_dashboard
-- ============================================================
DROP FUNCTION IF EXISTS criar_views_dashboard(TEXT);

CREATE OR REPLACE FUNCTION criar_views_dashboard(p_schema TEXT)
RETURNS TEXT AS $$
DECLARE
    v_tabela_vagas TEXT;
    v_tabela_candidatos TEXT;
    v_sql TEXT;
    v_select_vagas TEXT := '';
    v_select_candidatos TEXT := '';
    v_col RECORD;
    v_resultado TEXT := '';
    v_col_exists BOOLEAN;
    v_count INTEGER := 0;
BEGIN
    -- ============================================================
    -- Buscar nome das tabelas na configuracao
    -- ============================================================
    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Nome da aba de controle vagas'
    ) INTO v_tabela_vagas;

    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Nome da aba de controle candidatos'
    ) INTO v_tabela_candidatos;

    -- Formatar nomes (substituir espacos por _)
    v_tabela_vagas := 'USO_' || REPLACE(v_tabela_vagas, ' ', '_');
    v_tabela_candidatos := 'USO_' || REPLACE(v_tabela_candidatos, ' ', '_');

    v_resultado := v_resultado || 'Tabela vagas: ' || v_tabela_vagas || E'\n';
    v_resultado := v_resultado || 'Tabela candidatos: ' || v_tabela_candidatos || E'\n';

    -- ============================================================
    -- VIEW: vw_vagas_nomeFixo (DINAMICA baseada no dicionario)
    -- ============================================================
    v_select_vagas := '';
    v_count := 0;

    FOR v_col IN
        EXECUTE format(
            'SELECT "nomeFixo", "nomeAmigavel" FROM %I."USO_dicionarioVagas"
             WHERE "nomeFixo" IS NOT NULL
               AND TRIM("nomeFixo") <> ''''
               AND "nomeFixo" NOT IN (
                   ''operacao_atraso_status'', ''operacao_SLA_status'',
                   ''operacao_status_ultima_proposta'', ''ocorrencia_proposta'',
                   ''operacao_dias_status'', ''ocorrencia_status'',
                   ''operacao_selecionado_ultima_proposta'',
                   ''operacao_motivo_declinio_ultima_proposta''
               )',
            p_schema
        )
    LOOP
        -- Verificar se a coluna existe na tabela de vagas
        EXECUTE format(
            'SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = %L
                  AND table_name = %L
                  AND column_name = %L
            )',
            p_schema, v_tabela_vagas, normalizar_nome_coluna(v_col."nomeAmigavel")
        ) INTO v_col_exists;

        IF v_col_exists THEN
            IF v_select_vagas <> '' THEN
                v_select_vagas := v_select_vagas || ',' || E'\n            ';
            END IF;
            v_select_vagas := v_select_vagas ||
                format('"%s" AS %s', normalizar_nome_coluna(v_col."nomeAmigavel"), v_col."nomeFixo");
            v_count := v_count + 1;
        END IF;
    END LOOP;

    IF v_select_vagas <> '' THEN
        v_sql := format('
            DROP VIEW IF EXISTS %I."vw_vagas_nomeFixo" CASCADE;
            CREATE VIEW %I."vw_vagas_nomeFixo" AS
            SELECT
                %s
            FROM %I.%I
        ', p_schema, p_schema, v_select_vagas, p_schema, v_tabela_vagas);

        EXECUTE v_sql;
        v_resultado := v_resultado || 'View vw_vagas_nomeFixo criada (' || v_count || ' colunas)' || E'\n';
    ELSE
        v_resultado := v_resultado || 'ERRO: Nenhuma coluna mapeada para vagas' || E'\n';
    END IF;

    -- ============================================================
    -- VIEW: vw_candidatos_nomeFixo (DINAMICA baseada no dicionario)
    -- ============================================================
    v_select_candidatos := '';
    v_count := 0;

    FOR v_col IN
        EXECUTE format(
            'SELECT "nomeFixo", "nomeAmigavel" FROM %I."USO_dicionarioCandidatos"
             WHERE "nomeFixo" IS NOT NULL
               AND TRIM("nomeFixo") <> ''''',
            p_schema
        )
    LOOP
        -- Verificar se a coluna existe na tabela de candidatos
        EXECUTE format(
            'SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = %L
                  AND table_name = %L
                  AND column_name = %L
            )',
            p_schema, v_tabela_candidatos, normalizar_nome_coluna(v_col."nomeAmigavel")
        ) INTO v_col_exists;

        IF v_col_exists THEN
            IF v_select_candidatos <> '' THEN
                v_select_candidatos := v_select_candidatos || ',' || E'\n            ';
            END IF;
            v_select_candidatos := v_select_candidatos ||
                format('"%s" AS %s', normalizar_nome_coluna(v_col."nomeAmigavel"), v_col."nomeFixo");
            v_count := v_count + 1;
        END IF;
    END LOOP;

    IF v_select_candidatos <> '' THEN
        v_sql := format('
            DROP VIEW IF EXISTS %I."vw_candidatos_nomeFixo" CASCADE;
            CREATE VIEW %I."vw_candidatos_nomeFixo" AS
            SELECT
                %s
            FROM %I.%I
        ', p_schema, p_schema, v_select_candidatos, p_schema, v_tabela_candidatos);

        EXECUTE v_sql;
        v_resultado := v_resultado || 'View vw_candidatos_nomeFixo criada (' || v_count || ' colunas)' || E'\n';
    ELSE
        v_resultado := v_resultado || 'ERRO: Nenhuma coluna mapeada para candidatos' || E'\n';
    END IF;

    -- ============================================================
    -- MATERIALIZED VIEW: mv_SLAs
    -- Transforma colunas de SLA em linhas usando JSON (dinamico)
    -- tipo_sla é normalizado para formato amigável (sem _ no final, espaços)
    -- Inclui sequencia_status para ordenação
    -- ============================================================
    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I."mv_SLAs" CASCADE;

        CREATE MATERIALIZED VIEW %I."mv_SLAs" AS
        SELECT
            t.status,
            t."sequencia"::INTEGER AS sequencia_status,
            -- Transforma nome da coluna Airbyte para formato igual ao sla_utilizado
            -- Ex: "Sales_Manager_" -> "Sales Manager " (mantém espaço final)
            -- Ex: "Grandes_contas" -> "Grandes contas"
            REPLACE(kv.key, ''_'', '' '') AS tipo_sla,
            kv.key AS tipo_sla_original,
            kv.value::INTEGER AS valor_sla
        FROM %I."USO_statusVagas" t,
        LATERAL (
            SELECT key, value
            FROM jsonb_each_text(
                to_jsonb(t)
                - ''_airbyte_raw_id''
                - ''_airbyte_extracted_at''
                - ''_airbyte_meta''
                - ''_airbyte_generation_id''
                - ''status''
                - ''fimFluxo''
                - ''sequencia''
                - ''responsavel''
                - ''funcaoSistema''
            )
        ) AS kv
        WHERE kv.value IS NOT NULL AND kv.value <> ''''
    ', p_schema, p_schema, p_schema);

    EXECUTE v_sql;
    v_resultado := v_resultado || 'Materialized view mv_SLAs criada' || E'\n';

    -- ============================================================
    -- GRANT: Permissões para rpo_user em todos os objetos criados
    -- ============================================================
    EXECUTE format('GRANT SELECT ON %I."vw_vagas_nomeFixo" TO rpo_user', p_schema);
    EXECUTE format('GRANT SELECT ON %I."vw_candidatos_nomeFixo" TO rpo_user', p_schema);
    EXECUTE format('GRANT SELECT ON %I."mv_SLAs" TO rpo_user', p_schema);
    v_resultado := v_resultado || 'Permissões concedidas para rpo_user' || E'\n';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT criar_views_dashboard('RPO_semper_laser');
-- ============================================================


-- ============================================================
-- Função: criar_mv_consumo_vagas(schema_name)
-- Cria a materialized view mv_CONSUMO_vagas
-- ============================================================
-- PRÉ-REQUISITO: Executar criar_views_dashboard() antes
-- (cria mv_SLAs necessária para o JOIN)
--
-- Filtros aplicados:
-- 1. requisicao não vazio e não duplicado
-- 2. data_abertura válida, não vazia e não futura
-- 3. vaga_titulo não vazio
--
-- Colunas adicionais:
-- - SLA_do_status: busca DINÂMICA via mv_SLAs
-- - data_inicio_status: busca em USO_historicoVagas
--
-- IMPORTANTE: Cada dashboard pode ter SLAs e status diferentes.
-- Novos SLAs/status são reconhecidos automaticamente no REFRESH.
-- ============================================================

CREATE OR REPLACE FUNCTION criar_mv_consumo_vagas(p_schema TEXT)
RETURNS TEXT AS $$
DECLARE
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_tipo_contagem TEXT;
    v_formato_datas TEXT;
    v_formato_pg TEXT;
    v_colunas_date TEXT[];
    v_select_cols TEXT := '';
    v_col RECORD;
    v_has_listas BOOLEAN := FALSE;
    v_geo_select TEXT := '';
    v_geo_join TEXT := '';
    v_colunas_vagas TEXT := '';       -- Lista de colunas sem prefixo (para vagas_filtradas)
    v_colunas_vagas_v TEXT := '';     -- Lista de colunas com prefixo v. (para dados_base)
BEGIN
    -- Buscar tipo de contagem de dias na configuração
    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Tipo da contagem de dias'
    ) INTO v_tipo_contagem;

    v_resultado := v_resultado || 'Tipo contagem: ' || COALESCE(v_tipo_contagem, 'não definido') || E'\n';

    -- Buscar formato de datas na configuração
    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Formato das datas'
    ) INTO v_formato_datas;

    -- Definir formato PostgreSQL baseado na configuração
    -- americano = MM/DD/YYYY, brasileiro = DD/MM/YYYY
    IF LOWER(COALESCE(v_formato_datas, 'americano')) = 'brasileiro' THEN
        v_formato_pg := 'DD/MM/YYYY';
    ELSE
        v_formato_pg := 'MM/DD/YYYY';
    END IF;

    v_resultado := v_resultado || 'Formato datas: ' || COALESCE(v_formato_datas, 'americano (padrão)') || ' (' || v_formato_pg || ')' || E'\n';

    -- ============================================================
    -- Verificar se existe tabela USO_Listas para geolocalização
    -- (customização para clientes com listas de lojas)
    -- ============================================================
    EXECUTE format(
        'SELECT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = %L AND table_name = ''USO_Listas''
        )',
        p_schema
    ) INTO v_has_listas;

    IF v_has_listas THEN
        v_resultado := v_resultado || 'USO_Listas encontrada: campos geo_city, geo_state, geo_location serão incluídos' || E'\n';
        v_geo_select := ',
            listas."City_" AS geo_city,
            listas."State_" AS geo_state,
            listas."City_" || '' - '' || listas."State_" AS geo_location';
        v_geo_join := format('
        LEFT JOIN %I."USO_Listas" listas
            ON TRIM(v.geo_local) = TRIM(listas."Lojas_")', p_schema);
    ELSE
        v_resultado := v_resultado || 'USO_Listas não encontrada: campos geo_* não serão incluídos' || E'\n';
    END IF;

    -- ============================================================
    -- PRIMEIRO: Buscar colunas marcadas como 'date' no dicionário
    -- (necessário ANTES de construir v_colunas_vagas_v)
    -- ============================================================
    v_resultado := v_resultado || 'Colunas tipo date no dicionário:' || E'\n';

    FOR v_col IN
        EXECUTE format(
            'SELECT "nomeFixo" FROM %I."USO_dicionarioVagas" WHERE LOWER("tipoDoDado") = ''date''',
            p_schema
        )
    LOOP
        v_colunas_date := array_append(v_colunas_date, v_col."nomeFixo");
        v_resultado := v_resultado || '  - ' || v_col."nomeFixo" || E'\n';
    END LOOP;

    -- ============================================================
    -- Buscar colunas de vw_vagas_nomeFixo
    -- Aplicar conversão TO_DATE nas colunas marcadas como date
    -- ============================================================
    FOR v_col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = 'vw_vagas_nomeFixo'
        ORDER BY ordinal_position
    LOOP
        IF v_colunas_vagas <> '' THEN
            v_colunas_vagas := v_colunas_vagas || ', ';
            v_colunas_vagas_v := v_colunas_vagas_v || ', ';
        END IF;

        -- Verificar se é coluna de data que precisa conversão
        IF v_col.column_name = ANY(v_colunas_date) THEN
            -- Para vagas_filtradas: manter como texto (usado em ORDER BY)
            v_colunas_vagas := v_colunas_vagas || v_col.column_name;
            -- Para dados_base: converter para DATE usando formato configurado
            v_colunas_vagas_v := v_colunas_vagas_v || format(
                'CASE
                    WHEN v.%I IS NULL OR TRIM(v.%I) = '''' THEN NULL
                    WHEN v.%I ~ ''^\d{1,2}/\d{1,2}/\d{4}$'' THEN TO_DATE(v.%I, %L)
                    WHEN v.%I ~ ''^\d{4}-\d{2}-\d{2}$'' THEN TO_DATE(v.%I, ''YYYY-MM-DD'')
                    ELSE NULL
                END AS %I',
                v_col.column_name, v_col.column_name,
                v_col.column_name, v_col.column_name, v_formato_pg,
                v_col.column_name, v_col.column_name,
                v_col.column_name
            );
        ELSE
            v_colunas_vagas := v_colunas_vagas || v_col.column_name;
            v_colunas_vagas_v := v_colunas_vagas_v || 'v.' || v_col.column_name;
        END IF;
    END LOOP;

    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I."mv_CONSUMO_vagas";

        CREATE MATERIALIZED VIEW %I."mv_CONSUMO_vagas" AS
        WITH vagas_com_rn AS (
            -- Subquery para calcular row_number e filtrar duplicados
            -- Filtros: requisicao não vazia, data_abertura válida e não futura, vaga_titulo não vazio
            SELECT *,
                   ROW_NUMBER() OVER (PARTITION BY requisicao ORDER BY data_abertura DESC) as rn
            FROM %I."vw_vagas_nomeFixo"
            WHERE requisicao IS NOT NULL
              AND TRIM(requisicao) <> ''''
              AND vaga_titulo IS NOT NULL
              AND TRIM(vaga_titulo) <> ''''
              AND data_abertura IS NOT NULL
              AND TRIM(data_abertura) <> ''''
              AND data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$|^\d{4}-\d{2}-\d{2}$''
              AND (
                  CASE
                      WHEN data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                      THEN TO_DATE(data_abertura, %L)
                      WHEN data_abertura ~ ''^\d{4}-\d{2}-\d{2}$''
                      THEN TO_DATE(data_abertura, ''YYYY-MM-DD'')
                  END
              ) <= CURRENT_DATE
        ),
        -- Seleciona apenas registro único por requisição (rn=1), excluindo coluna rn do resultado
        vagas_filtradas AS (
            SELECT %s FROM vagas_com_rn WHERE rn = 1
        ),
        dados_base AS (
        SELECT
            %s,
            sv.valor_sla::INTEGER AS SLA_do_status,
            st."fimFluxo" AS fim_fluxo,
            st."sequencia" AS sequencia_status,
            st."responsavel" AS responsavel_status,
            st."funcaoSistema" AS funcao_sistema,
            hist.data_inicio_status,
            CASE
                WHEN sv.valor_sla::INTEGER = 0 AND st."fimFluxo" = ''Sim''
                THEN hist.data_inicio_status
                ELSE hist_fim.data_final_status
            END AS data_final_status,
            -- SLA_da_abertura: soma dos SLAs de todos os status com sequencia <= sequencia_atual
            (
                SELECT COALESCE(SUM(sv2.valor_sla::INTEGER), 0)
                FROM %I."mv_SLAs" sv2
                INNER JOIN %I."USO_statusVagas" st2
                    ON TRIM(st2.status) = TRIM(sv2.status)
                WHERE TRIM(sv2.tipo_sla) = TRIM(v.sla_utilizado)
                  AND st2."sequencia" IS NOT NULL
                  AND st2."sequencia"::INTEGER <= COALESCE(
                      st."sequencia"::INTEGER,
                      (
                          SELECT st3."sequencia"::INTEGER
                          FROM %I."USO_historicoVagas" h4
                          INNER JOIN %I."USO_statusVagas" st3 ON TRIM(st3.status) = TRIM(h4.status)
                          WHERE TRIM(h4.requisicao) = TRIM(v.requisicao)
                            AND st3."sequencia" IS NOT NULL
                          ORDER BY h4.created_at DESC
                          LIMIT 1
                      )
                  )
            ) AS SLA_da_abertura,
            CASE
                WHEN st."fimFluxo" = ''Sim'' THEN 0
                WHEN hist.data_inicio_status IS NULL THEN NULL
                WHEN %L ILIKE ''%%úteis%%'' THEN (
                    SELECT COUNT(*)::INTEGER
                    FROM generate_series(
                        hist.data_inicio_status,
                        COALESCE(hist_fim.data_final_status, CURRENT_DATE) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (
                          SELECT 1 FROM %I."USO_feriados" f
                          WHERE TO_DATE(f."Data", %L) = d.dt::DATE
                      )
                )
                ELSE (
                    COALESCE(hist_fim.data_final_status, CURRENT_DATE) - hist.data_inicio_status
                )::INTEGER
            END AS dias_no_status,
            -- dias_da_abertura: dias desde data_abertura_date ate data_final_status (ou hoje)
            CASE
                WHEN v.data_abertura IS NULL THEN NULL
                WHEN st."fimFluxo" = ''Sim'' AND hist.data_inicio_status IS NULL THEN NULL
                WHEN %L ILIKE ''%%úteis%%'' THEN (
                    SELECT COUNT(*)::INTEGER
                    FROM generate_series(
                        CASE
                            WHEN v.data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                            THEN TO_DATE(v.data_abertura, %L)
                            WHEN v.data_abertura ~ ''^\d{4}-\d{2}-\d{2}$''
                            THEN TO_DATE(v.data_abertura, ''YYYY-MM-DD'')
                        END,
                        COALESCE(
                            CASE
                                WHEN sv.valor_sla::INTEGER = 0 AND st."fimFluxo" = ''Sim''
                                THEN hist.data_inicio_status
                                ELSE hist_fim.data_final_status
                            END,
                            CURRENT_DATE
                        ) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (
                          SELECT 1 FROM %I."USO_feriados" f
                          WHERE TO_DATE(f."Data", %L) = d.dt::DATE
                      )
                )
                ELSE (
                    COALESCE(
                        CASE
                            WHEN sv.valor_sla::INTEGER = 0 AND st."fimFluxo" = ''Sim''
                            THEN hist.data_inicio_status
                            ELSE hist_fim.data_final_status
                        END,
                        CURRENT_DATE
                    ) - CASE
                            WHEN v.data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                            THEN TO_DATE(v.data_abertura, %L)
                            WHEN v.data_abertura ~ ''^\d{4}-\d{2}-\d{2}$''
                            THEN TO_DATE(v.data_abertura, ''YYYY-MM-DD'')
                        END
                )::INTEGER
            END AS dias_da_abertura,
            -- candidatos_considerados: count de candidatos onde requisicao aparece em operacao_posicoesconsideradas
            -- Formatos suportados:
            --   cielo: [requisicao] - titulo... -> busca [requisicao]
            --   semper_laser: TITULO --- (loja) --- requisicao -> busca --- requisicao
            (
                SELECT COUNT(*)::INTEGER
                FROM %I."vw_candidatos_nomeFixo" c
                WHERE c.operacao_posicoesconsideradas IS NOT NULL
                  AND (
                      -- Formato cielo: [requisicao]
                      c.operacao_posicoesconsideradas LIKE ''%%['' || v.requisicao || '']%%''
                      -- Formato semper_laser: --- requisicao (no final)
                      OR c.operacao_posicoesconsideradas LIKE ''%%--- '' || v.requisicao
                      -- Formato semper_laser: --- requisicao, (seguido de outra vaga)
                      OR c.operacao_posicoesconsideradas LIKE ''%%--- '' || v.requisicao || '',%%''
                  )
            ) AS candidatos_considerados
            %s
        FROM vagas_filtradas v
        %s
        LEFT JOIN %I."mv_SLAs" sv
            ON TRIM(sv.status) = TRIM(v.status)
            AND TRIM(sv.tipo_sla) = TRIM(v.sla_utilizado)
        LEFT JOIN %I."USO_statusVagas" st
            ON TRIM(st.status) = TRIM(v.status)
        LEFT JOIN LATERAL (
            SELECT MAX(h.created_at)::DATE AS data_inicio_status
            FROM %I."USO_historicoVagas" h
            WHERE TRIM(h.requisicao) = TRIM(v.requisicao)
              AND TRIM(h.status) = TRIM(v.status)
        ) hist ON TRUE
        LEFT JOIN LATERAL (
            SELECT MIN(h2.created_at)::DATE AS data_final_status
            FROM %I."USO_historicoVagas" h2
            WHERE TRIM(h2.requisicao) = TRIM(v.requisicao)
              AND h2.created_at > (
                  SELECT MAX(h3.created_at)
                  FROM %I."USO_historicoVagas" h3
                  WHERE TRIM(h3.requisicao) = TRIM(v.requisicao)
                    AND TRIM(h3.status) = TRIM(v.status)
              )
        ) hist_fim ON hist.data_inicio_status IS NOT NULL
        )
        -- Query final com campos GAP calculados
        SELECT
            *,
            -- GAP_SLA_status = SLA_do_status - dias_no_status
            CASE
                WHEN SLA_do_status IS NULL OR dias_no_status IS NULL THEN NULL
                ELSE SLA_do_status - dias_no_status
            END AS GAP_SLA_status,
            -- GAP_SLA_abertura = SLA_da_abertura - dias_da_abertura
            CASE
                WHEN SLA_da_abertura IS NULL OR dias_da_abertura IS NULL THEN NULL
                ELSE SLA_da_abertura - dias_da_abertura
            END AS GAP_SLA_abertura
        FROM dados_base
    ', p_schema, p_schema, p_schema, v_formato_pg,     -- schema x3, formato para filtro data_abertura
       v_colunas_vagas,                                -- colunas sem prefixo (para vagas_filtradas)
       v_colunas_vagas_v,                              -- colunas com prefixo v. (para dados_base)
       p_schema, p_schema, p_schema, p_schema,         -- schema para SLA_da_abertura (unpivot, statusVagas, historicoVagas, statusVagas)
       v_tipo_contagem, p_schema, v_formato_pg,        -- tipo_contagem para dias_no_status, schema feriados, formato feriados
       v_tipo_contagem, v_formato_pg, p_schema, v_formato_pg, v_formato_pg,  -- tipo_contagem, formato abertura, schema feriados, formato feriados, formato abertura final
       p_schema,                                       -- schema para candidatos_considerados (vw_candidatos_nomeFixo)
       v_geo_select,                                   -- campos geo (vazio se não tiver USO_Listas)
       v_geo_join,                                     -- join USO_Listas (vazio se não existir)
       p_schema, p_schema, p_schema, p_schema, p_schema);

    EXECUTE v_sql;

    -- Contar registros
    EXECUTE format('SELECT COUNT(*) FROM %I."mv_CONSUMO_vagas"', p_schema) INTO v_count;
    v_resultado := v_resultado || 'Materialized view mv_CONSUMO_vagas criada com ' || v_count || ' registros' || E'\n';

    -- GRANT: Permissões para rpo_user
    EXECUTE format('GRANT SELECT ON %I."mv_CONSUMO_vagas" TO rpo_user', p_schema);
    v_resultado := v_resultado || 'Permissões concedidas para rpo_user';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT criar_mv_consumo_vagas('RPO_semper_laser');
--
-- Para atualizar a materialized view (reconhece novos SLAs/status):
-- REFRESH MATERIALIZED VIEW "RPO_semper_laser"."mv_CONSUMO_vagas";
-- ============================================================
