-- ============================================================
-- Funcao: normalizar_nome_coluna(p_nome)
-- Auxiliar para normalizar nomes de colunas Airbyte
-- Ex: "Data de abertura" -> "Data_de_abertura"
-- Ex: "Posicao" -> "Posicao"
-- Ex: "ID Position\nADP" -> "ID_Position_ADP"
-- ============================================================
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
-- Funcao: public.dashboard_criar_views(p_schema, p_versao)
-- Cria views DINAMICAMENTE baseadas nos dicionarios:
-- - vw_vagas_nomeFixo (lido de USO_dicionarioVagas)
-- - vw_candidatos_nomeFixo (lido de USO_dicionarioCandidatos)
-- - mv_SLAs (SLAs em linhas)
-- ============================================================
-- VERSAO 3.0 - COM SUPORTE A VERSAO
-- Quando p_versao = 'V2': tabelas fonte V2_USO_*, objetos V2_vw_*, V2_mv_*
-- Quando p_versao IS NULL: comportamento identico ao anterior (sem prefixo)
-- ============================================================

DROP FUNCTION IF EXISTS public.dashboard_criar_views(TEXT, TEXT);
DROP FUNCTION IF EXISTS criar_views_dashboard(TEXT);

CREATE OR REPLACE FUNCTION public.dashboard_criar_views(p_schema TEXT, p_versao TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
    v_prefixo TEXT;
    -- Tabelas fonte (versionadas)
    v_tbl_configGerais TEXT;
    v_tbl_dicionarioVagas TEXT;
    v_tbl_dicionarioCandidatos TEXT;
    v_tbl_statusVagas TEXT;
    -- Objetos de saida (versionados)
    v_out_vw_vagas TEXT;
    v_out_vw_candidatos TEXT;
    v_out_mv_slas TEXT;
    -- Variaveis de trabalho
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
    -- Logica de prefixo
    -- ============================================================
    IF p_versao IS NOT NULL AND TRIM(p_versao) <> '' THEN
        v_prefixo := TRIM(p_versao) || '_';
    ELSE
        v_prefixo := '';
    END IF;

    -- Tabelas fonte
    v_tbl_configGerais := v_prefixo || 'USO_configuracoesGerais';
    v_tbl_dicionarioVagas := v_prefixo || 'USO_dicionarioVagas';
    v_tbl_dicionarioCandidatos := v_prefixo || 'USO_dicionarioCandidatos';
    v_tbl_statusVagas := v_prefixo || 'USO_statusVagas';

    -- Objetos de saida
    v_out_vw_vagas := v_prefixo || 'vw_vagas_nomeFixo';
    v_out_vw_candidatos := v_prefixo || 'vw_candidatos_nomeFixo';
    v_out_mv_slas := v_prefixo || 'MV_SLAs';

    IF v_prefixo <> '' THEN
        v_resultado := v_resultado || 'Versao: ' || p_versao || ' (prefixo: ' || v_prefixo || ')' || E'\n';
    END IF;

    -- ============================================================
    -- Buscar nome das tabelas na configuracao
    -- ============================================================
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Nome da aba de controle vagas'
    ) INTO v_tabela_vagas;

    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Nome da aba de controle candidatos'
    ) INTO v_tabela_candidatos;

    -- Formatar nomes (substituir espacos por _)
    v_tabela_vagas := v_prefixo || 'USO_' || REPLACE(v_tabela_vagas, ' ', '_');
    v_tabela_candidatos := v_prefixo || 'USO_' || REPLACE(v_tabela_candidatos, ' ', '_');

    v_resultado := v_resultado || 'Tabela vagas: ' || v_tabela_vagas || E'\n';
    v_resultado := v_resultado || 'Tabela candidatos: ' || v_tabela_candidatos || E'\n';

    -- ============================================================
    -- VIEW: vw_vagas_nomeFixo (DINAMICA baseada no dicionario)
    -- ============================================================
    v_select_vagas := '';
    v_count := 0;

    FOR v_col IN
        EXECUTE format(
            'SELECT "nomeFixo", "nomeAmigavel" FROM %I.%I
             WHERE "nomeFixo" IS NOT NULL
               AND TRIM("nomeFixo") <> ''''
               AND "nomeFixo" NOT IN (
                   ''operacao_atraso_status'', ''operacao_SLA_status'',
                   ''operacao_status_ultima_proposta'', ''ocorrencia_proposta'',
                   ''operacao_dias_status'', ''ocorrencia_status'',
                   ''operacao_selecionado_ultima_proposta'',
                   ''operacao_motivo_declinio_ultima_proposta''
               )',
            p_schema, v_tbl_dicionarioVagas
        )
    LOOP
        DECLARE
            v_col_name TEXT := NULL;
        BEGIN
            -- Primeiro: tentar nome exato do dicionario
            EXECUTE format(
                'SELECT column_name FROM information_schema.columns
                 WHERE table_schema = %L AND table_name = %L AND column_name = %L',
                p_schema, v_tabela_vagas, v_col."nomeAmigavel"
            ) INTO v_col_name;

            -- Se nao encontrou, tentar nome normalizado
            IF v_col_name IS NULL THEN
                EXECUTE format(
                    'SELECT column_name FROM information_schema.columns
                     WHERE table_schema = %L AND table_name = %L AND column_name = %L',
                    p_schema, v_tabela_vagas, normalizar_nome_coluna(v_col."nomeAmigavel")
                ) INTO v_col_name;
            END IF;

            -- Se nao encontrou, tentar nome normalizado com _ no final (padrao Airbyte)
            IF v_col_name IS NULL THEN
                EXECUTE format(
                    'SELECT column_name FROM information_schema.columns
                     WHERE table_schema = %L AND table_name = %L AND column_name = %L',
                    p_schema, v_tabela_vagas, normalizar_nome_coluna(v_col."nomeAmigavel") || '_'
                ) INTO v_col_name;
            END IF;

            IF v_col_name IS NOT NULL THEN
                IF v_select_vagas <> '' THEN
                    v_select_vagas := v_select_vagas || ',' || E'\n            ';
                END IF;
                v_select_vagas := v_select_vagas ||
                    format('"%s" AS %s', v_col_name, v_col."nomeFixo");
                v_count := v_count + 1;
            END IF;
        END;
    END LOOP;

    IF v_select_vagas <> '' THEN
        v_sql := format('
            DROP VIEW IF EXISTS %I.%I CASCADE;
            CREATE VIEW %I.%I AS
            SELECT
                %s
            FROM %I.%I
        ', p_schema, v_out_vw_vagas, p_schema, v_out_vw_vagas, v_select_vagas, p_schema, v_tabela_vagas);

        EXECUTE v_sql;
        v_resultado := v_resultado || 'View ' || v_out_vw_vagas || ' criada (' || v_count || ' colunas)' || E'\n';
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
            'SELECT "nomeFixo", "nomeAmigavel" FROM %I.%I
             WHERE "nomeFixo" IS NOT NULL
               AND TRIM("nomeFixo") <> ''''',
            p_schema, v_tbl_dicionarioCandidatos
        )
    LOOP
        DECLARE
            v_col_name TEXT := NULL;
        BEGIN
            -- Primeiro: tentar nome exato do dicionario
            EXECUTE format(
                'SELECT column_name FROM information_schema.columns
                 WHERE table_schema = %L AND table_name = %L AND column_name = %L',
                p_schema, v_tabela_candidatos, v_col."nomeAmigavel"
            ) INTO v_col_name;

            -- Se nao encontrou, tentar nome normalizado
            IF v_col_name IS NULL THEN
                EXECUTE format(
                    'SELECT column_name FROM information_schema.columns
                     WHERE table_schema = %L AND table_name = %L AND column_name = %L',
                    p_schema, v_tabela_candidatos, normalizar_nome_coluna(v_col."nomeAmigavel")
                ) INTO v_col_name;
            END IF;

            -- Se nao encontrou, tentar nome normalizado com _ no final (padrao Airbyte)
            IF v_col_name IS NULL THEN
                EXECUTE format(
                    'SELECT column_name FROM information_schema.columns
                     WHERE table_schema = %L AND table_name = %L AND column_name = %L',
                    p_schema, v_tabela_candidatos, normalizar_nome_coluna(v_col."nomeAmigavel") || '_'
                ) INTO v_col_name;
            END IF;

            IF v_col_name IS NOT NULL THEN
                IF v_select_candidatos <> '' THEN
                    v_select_candidatos := v_select_candidatos || ',' || E'\n            ';
                END IF;
                v_select_candidatos := v_select_candidatos ||
                    format('"%s" AS %s', v_col_name, v_col."nomeFixo");
                v_count := v_count + 1;
            END IF;
        END;
    END LOOP;

    IF v_select_candidatos <> '' THEN
        v_sql := format('
            DROP VIEW IF EXISTS %I.%I CASCADE;
            CREATE VIEW %I.%I AS
            SELECT
                %s
            FROM %I.%I
        ', p_schema, v_out_vw_candidatos, p_schema, v_out_vw_candidatos, v_select_candidatos, p_schema, v_tabela_candidatos);

        EXECUTE v_sql;
        v_resultado := v_resultado || 'View ' || v_out_vw_candidatos || ' criada (' || v_count || ' colunas)' || E'\n';
    ELSE
        v_resultado := v_resultado || 'ERRO: Nenhuma coluna mapeada para candidatos' || E'\n';
    END IF;

    -- ============================================================
    -- MATERIALIZED VIEW: mv_SLAs
    -- Transforma colunas de SLA em linhas usando JSON (dinamico)
    -- ============================================================
    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I.%I CASCADE;

        CREATE MATERIALIZED VIEW %I.%I AS
        SELECT
            %s AS status,
            t."sequencia"::INTEGER AS sequencia_status,
            REPLACE(kv.key, ''_'', '' '') AS tipo_sla,
            kv.key AS tipo_sla_original,
            kv.value::INTEGER AS valor_sla
        FROM %I.%I t,
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
    ', p_schema, v_out_mv_slas, p_schema, v_out_mv_slas,
       CASE WHEN v_prefixo <> '' THEN 'UPPER(LEFT(TRIM(t.status), 1)) || LOWER(SUBSTRING(TRIM(t.status) FROM 2))' ELSE 't.status' END,
       p_schema, v_tbl_statusVagas);

    EXECUTE v_sql;
    v_resultado := v_resultado || 'Materialized view ' || v_out_mv_slas || ' criada' || E'\n';

    -- ============================================================
    -- GRANT: Permissoes para rpo_user em todos os objetos criados
    -- ============================================================
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_vw_vagas);
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_vw_candidatos);
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_mv_slas);
    v_resultado := v_resultado || 'Permissoes concedidas para rpo_user' || E'\n';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT dashboard_criar_views('RPO_cielo');
-- SELECT dashboard_criar_views('RPO_cielo', 'V2');
-- ============================================================


-- ============================================================
-- Funcao: public.dashboard_criar_mv_consumo_vagas(p_schema, p_versao)
-- Cria a materialized view mv_CONSUMO_vagas
-- ============================================================
-- PRE-REQUISITO: Executar dashboard_criar_views() antes
-- (cria mv_SLAs necessaria para o JOIN)
-- ============================================================
-- VERSAO 2.0 - COM SUPORTE A VERSAO
-- Quando p_versao = 'V2': tabelas fonte V2_USO_*, objetos V2_mv_*
-- ============================================================

DROP FUNCTION IF EXISTS public.dashboard_criar_mv_consumo_vagas(TEXT, TEXT);
DROP FUNCTION IF EXISTS criar_mv_consumo_vagas(TEXT);

CREATE OR REPLACE FUNCTION public.dashboard_criar_mv_consumo_vagas(p_schema TEXT, p_versao TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
    v_prefixo TEXT;
    -- Tabelas fonte (versionadas)
    v_tbl_configGerais TEXT;
    v_tbl_dicionarioVagas TEXT;
    v_tbl_listas TEXT;
    v_tbl_statusVagas TEXT;
    v_tbl_historicoVagas TEXT;
    v_tbl_feriados TEXT;
    -- Objetos de saida e cross-refs (versionados)
    v_out_vw_vagas TEXT;
    v_out_vw_candidatos TEXT;
    v_out_mv_slas TEXT;
    v_out_mv_consumo_vagas TEXT;
    v_out_mv_erros_vagas TEXT;
    -- Variaveis de trabalho
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
    v_has_erros_vagas BOOLEAN := FALSE;
    v_filtro_erros TEXT := '';
    v_geo_select TEXT := '';
    v_geo_join TEXT := '';
    v_colunas_vagas TEXT := '';
    v_colunas_vagas_v TEXT := '';
BEGIN
    -- ============================================================
    -- Logica de prefixo
    -- ============================================================
    IF p_versao IS NOT NULL AND TRIM(p_versao) <> '' THEN
        v_prefixo := TRIM(p_versao) || '_';
    ELSE
        v_prefixo := '';
    END IF;

    -- Tabelas fonte
    v_tbl_configGerais := v_prefixo || 'USO_configuracoesGerais';
    v_tbl_dicionarioVagas := v_prefixo || 'USO_dicionarioVagas';
    v_tbl_listas := v_prefixo || 'USO_Listas';
    v_tbl_statusVagas := v_prefixo || 'USO_statusVagas';
    v_tbl_historicoVagas := v_prefixo || 'USO_historicoVagas';
    v_tbl_feriados := v_prefixo || 'USO_feriados';

    -- Objetos de saida e cross-refs
    v_out_vw_vagas := v_prefixo || 'vw_vagas_nomeFixo';
    v_out_vw_candidatos := v_prefixo || 'vw_candidatos_nomeFixo';
    v_out_mv_slas := v_prefixo || 'MV_SLAs';
    v_out_mv_consumo_vagas := v_prefixo || 'MV_CONSUMO_vagas';
    v_out_mv_erros_vagas := v_prefixo || 'MV_CONSUMO_ERROS_VAGAS';

    IF v_prefixo <> '' THEN
        v_resultado := v_resultado || 'Versao: ' || p_versao || ' (prefixo: ' || v_prefixo || ')' || E'\n';
    END IF;

    -- Buscar tipo de contagem de dias na configuracao
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Tipo da contagem de dias'
    ) INTO v_tipo_contagem;

    v_resultado := v_resultado || 'Tipo contagem: ' || COALESCE(v_tipo_contagem, 'nao definido') || E'\n';

    -- Buscar formato de datas na configuracao
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Formato das datas'
    ) INTO v_formato_datas;

    IF LOWER(COALESCE(v_formato_datas, 'americano')) = 'brasileiro' THEN
        v_formato_pg := 'DD/MM/YYYY';
    ELSE
        v_formato_pg := 'MM/DD/YYYY';
    END IF;

    v_resultado := v_resultado || 'Formato datas: ' || COALESCE(v_formato_datas, 'americano (padrao)') || ' (' || v_formato_pg || ')' || E'\n';

    -- ============================================================
    -- Verificar se existe tabela USO_Listas para geolocalizacao
    -- ============================================================
    EXECUTE format(
        'SELECT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = %L AND table_name = %L
        )',
        p_schema, v_tbl_listas
    ) INTO v_has_listas;

    IF v_has_listas THEN
        v_resultado := v_resultado || v_tbl_listas || ' encontrada: campos geo_city, geo_state, geo_location serao incluidos' || E'\n';
        v_geo_select := ',
            listas."City_" AS calc_geo_city,
            listas."State_" AS calc_geo_state,
            listas."City_" || '' - '' || listas."State_" AS calc_geo_location';
        v_geo_join := format('
        LEFT JOIN %I.%I listas
            ON TRIM(v.geo_local) = TRIM(listas."Lojas_")', p_schema, v_tbl_listas);
    ELSE
        v_resultado := v_resultado || v_tbl_listas || ' nao encontrada: campos geo_* nao serao incluidos' || E'\n';
    END IF;

    -- ============================================================
    -- Verificar se existe MV_CONSUMO_ERROS_VAGAS para excluir requisicoes com erro
    -- ============================================================
    EXECUTE format(
        'SELECT EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = %L AND c.relname = %L
        )',
        p_schema, v_out_mv_erros_vagas
    ) INTO v_has_erros_vagas;

    IF v_has_erros_vagas AND v_prefixo <> '' THEN
        -- V2: exclusao agressiva - remove requisicoes com qualquer erro
        v_filtro_erros := format('
              AND NOT EXISTS (
                  SELECT 1 FROM %I.%I ev
                  WHERE TRIM(ev.requisicao) = TRIM(vagas_com_rn.requisicao)
              )', p_schema, v_out_mv_erros_vagas);
        v_resultado := v_resultado || v_out_mv_erros_vagas || ' encontrada: requisicoes com erro serao excluidas (V2)' || E'\n';
    ELSIF v_has_erros_vagas THEN
        -- V1: erros sao apenas informativos, nao excluem vagas
        v_resultado := v_resultado || v_out_mv_erros_vagas || ' encontrada: apenas informativo (V1, sem exclusao)' || E'\n';
    ELSE
        v_resultado := v_resultado || v_out_mv_erros_vagas || ' nao encontrada: nenhuma exclusao aplicada' || E'\n';
    END IF;

    -- ============================================================
    -- Buscar colunas marcadas como 'date' no dicionario
    -- ============================================================
    v_resultado := v_resultado || 'Colunas tipo date no dicionario:' || E'\n';

    FOR v_col IN
        EXECUTE format(
            'SELECT "nomeFixo" FROM %I.%I WHERE LOWER("tipoDoDado") = ''date''',
            p_schema, v_tbl_dicionarioVagas
        )
    LOOP
        v_colunas_date := array_append(v_colunas_date, v_col."nomeFixo");
        v_resultado := v_resultado || '  - ' || v_col."nomeFixo" || E'\n';
    END LOOP;

    -- ============================================================
    -- Buscar colunas de vw_vagas_nomeFixo
    -- Aplicar conversao TO_DATE nas colunas marcadas como date
    -- ============================================================
    FOR v_col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = v_out_vw_vagas
        ORDER BY ordinal_position
    LOOP
        IF v_colunas_vagas <> '' THEN
            v_colunas_vagas := v_colunas_vagas || ', ';
            v_colunas_vagas_v := v_colunas_vagas_v || ', ';
        END IF;

        IF v_col.column_name = ANY(v_colunas_date) THEN
            v_colunas_vagas := v_colunas_vagas || v_col.column_name;
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
        ELSIF v_col.column_name IN ('geo_regiao', 'geo_cidade', 'status', 'vaga_titulo') THEN
            v_colunas_vagas := v_colunas_vagas || v_col.column_name;
            IF v_prefixo <> '' OR v_col.column_name <> 'status' THEN
                v_colunas_vagas_v := v_colunas_vagas_v || format('UPPER(LEFT(TRIM(v.%I), 1)) || LOWER(SUBSTRING(TRIM(v.%I) FROM 2)) AS %I', v_col.column_name, v_col.column_name, v_col.column_name);
            ELSE
                v_colunas_vagas_v := v_colunas_vagas_v || 'v.' || v_col.column_name;
            END IF;
        ELSIF v_col.column_name IN ('geo_uf', 'vaga_banco') THEN
            v_colunas_vagas := v_colunas_vagas || v_col.column_name;
            v_colunas_vagas_v := v_colunas_vagas_v || format('UPPER(TRIM(v.%I)) AS %I', v_col.column_name, v_col.column_name);
        ELSE
            v_colunas_vagas := v_colunas_vagas || v_col.column_name;
            v_colunas_vagas_v := v_colunas_vagas_v || 'v.' || v_col.column_name;
        END IF;
    END LOOP;

    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I.%I CASCADE;

        CREATE MATERIALIZED VIEW %I.%I AS
        WITH vagas_com_rn AS (
            SELECT *,
                   ROW_NUMBER() OVER (PARTITION BY requisicao ORDER BY data_abertura DESC) as rn
            FROM %I.%I
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
        vagas_filtradas AS (
            SELECT %s FROM vagas_com_rn WHERE rn = 1
            %s
        ),
        dados_base AS (
        SELECT
            %s,
            sv.valor_sla::INTEGER AS calc_SLA_do_status,
            st."fimFluxo" AS fim_fluxo,
            st."sequencia" AS sequencia_status,
            UPPER(LEFT(TRIM(st."responsavel"), 1)) || LOWER(SUBSTRING(TRIM(st."responsavel") FROM 2)) AS responsavel_status,
            st."funcaoSistema" AS funcao_sistema,
            hist.data_inicio_status AS calc_data_inicio_status,
            CASE
                WHEN st."fimFluxo" = ''Sim''
                THEN hist.data_inicio_status
                ELSE hist_fim.data_final_status
            END AS calc_data_final_status,
            (
                SELECT COALESCE(SUM(sv2.valor_sla::INTEGER), 0)
                FROM %I.%I sv2
                INNER JOIN %I.%I st2
                    ON TRIM(st2.status) = TRIM(sv2.status)
                WHERE TRIM(sv2.tipo_sla) = TRIM(v.sla_utilizado)
                  AND st2."sequencia" IS NOT NULL
                  AND st2."sequencia"::INTEGER <= st."sequencia"::INTEGER
            ) AS calc_SLA_da_abertura,
            CASE
                WHEN st."fimFluxo" = ''Sim'' THEN 0
                WHEN hist.data_inicio_status IS NULL THEN NULL
                WHEN %L ILIKE ''%%teis%%'' THEN (
                    SELECT COUNT(*)::INTEGER
                    FROM generate_series(
                        hist.data_inicio_status,
                        COALESCE(hist_fim.data_final_status, CURRENT_DATE) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (
                          SELECT 1 FROM %I.%I f
                          WHERE TO_DATE(f."Data", %L) = d.dt::DATE
                      )
                )
                ELSE (
                    COALESCE(hist_fim.data_final_status, CURRENT_DATE) - hist.data_inicio_status
                )::INTEGER
            END AS calc_dias_no_status,
            CASE
                WHEN v.data_abertura IS NULL THEN NULL
                WHEN st."fimFluxo" = ''Sim'' AND hist.data_inicio_status IS NULL THEN NULL
                WHEN %L ILIKE ''%%teis%%'' THEN (
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
                                WHEN st."fimFluxo" = ''Sim''
                                THEN hist.data_inicio_status
                                ELSE hist_fim.data_final_status
                            END,
                            CURRENT_DATE
                        ) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (
                          SELECT 1 FROM %I.%I f
                          WHERE TO_DATE(f."Data", %L) = d.dt::DATE
                      )
                )
                ELSE (
                    COALESCE(
                        CASE
                            WHEN st."fimFluxo" = ''Sim''
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
            END AS calc_dias_da_abertura,
            (
                SELECT COUNT(*)::INTEGER
                FROM %I.%I c
                WHERE c.operacao_posicoesconsideradas IS NOT NULL
                  AND (
                      c.operacao_posicoesconsideradas LIKE ''%%['' || v.requisicao || '']%%''
                      OR c.operacao_posicoesconsideradas LIKE ''%%--- '' || v.requisicao
                      OR c.operacao_posicoesconsideradas LIKE ''%%--- '' || v.requisicao || '',%%''
                  )
            ) AS calc_candidatos_considerados
            %s
        FROM vagas_filtradas v
        %s
        LEFT JOIN %I.%I sv
            ON UPPER(TRIM(sv.status)) = UPPER(TRIM(v.status))
            AND UPPER(TRIM(sv.tipo_sla)) = UPPER(TRIM(v.sla_utilizado))
        LEFT JOIN %I.%I st
            ON UPPER(TRIM(st.status)) = UPPER(TRIM(v.status))
        LEFT JOIN LATERAL (
            SELECT MAX(h.created_at)::DATE AS data_inicio_status
            FROM %I.%I h
            WHERE TRIM(h.requisicao) = TRIM(v.requisicao)
              AND UPPER(TRIM(h.status)) = UPPER(TRIM(v.status))
        ) hist ON TRUE
        LEFT JOIN LATERAL (
            SELECT MIN(h2.created_at)::DATE AS data_final_status
            FROM %I.%I h2
            WHERE TRIM(h2.requisicao) = TRIM(v.requisicao)
              AND h2.created_at > (
                  SELECT MAX(h3.created_at)
                  FROM %I.%I h3
                  WHERE TRIM(h3.requisicao) = TRIM(v.requisicao)
                    AND UPPER(TRIM(h3.status)) = UPPER(TRIM(v.status))
              )
        ) hist_fim ON hist.data_inicio_status IS NOT NULL
        )
        SELECT
            *,
            CASE
                WHEN calc_SLA_do_status IS NULL OR calc_dias_no_status IS NULL THEN NULL
                ELSE calc_SLA_do_status - calc_dias_no_status
            END AS calc_GAP_SLA_status,
            CASE
                WHEN calc_SLA_da_abertura IS NULL OR calc_dias_da_abertura IS NULL THEN NULL
                ELSE calc_SLA_da_abertura - calc_dias_da_abertura
            END AS calc_GAP_SLA_abertura
        FROM dados_base
    ',
    p_schema, v_out_mv_consumo_vagas,                          -- DROP
    p_schema, v_out_mv_consumo_vagas,                          -- CREATE
    p_schema, v_out_vw_vagas, v_formato_pg,                    -- vagas_com_rn (view + formato)
    v_colunas_vagas,                                           -- vagas_filtradas
    v_filtro_erros,                                            -- exclusao de requisicoes com erro
    v_colunas_vagas_v,                                         -- dados_base SELECT
    p_schema, v_out_mv_slas,                                   -- SLA_da_abertura: mv_SLAs
    p_schema, v_tbl_statusVagas,                               -- SLA_da_abertura: statusVagas
    v_tipo_contagem,                                           -- dias_no_status: tipo_contagem
    p_schema, v_tbl_feriados, v_formato_pg,                    -- dias_no_status: feriados
    v_tipo_contagem, v_formato_pg,                             -- dias_da_abertura: tipo_contagem, formato
    p_schema, v_tbl_feriados, v_formato_pg,                    -- dias_da_abertura: feriados
    v_formato_pg,                                              -- dias_da_abertura: formato final
    p_schema, v_out_vw_candidatos,                             -- candidatos_considerados
    v_geo_select,                                              -- campos geo
    v_geo_join,                                                -- join geo
    p_schema, v_out_mv_slas,                                   -- JOIN mv_SLAs
    p_schema, v_tbl_statusVagas,                               -- JOIN statusVagas
    p_schema, v_tbl_historicoVagas,                            -- LATERAL hist
    p_schema, v_tbl_historicoVagas,                            -- LATERAL hist_fim
    p_schema, v_tbl_historicoVagas);                           -- LATERAL hist_fim (subquery)

    -- V1: remover prefixo calc_ dos campos calculados
    IF v_prefixo = '' THEN
        v_sql := REPLACE(v_sql, 'calc_', '');
    END IF;

    EXECUTE v_sql;

    -- Contar registros
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema, v_out_mv_consumo_vagas) INTO v_count;
    v_resultado := v_resultado || 'Materialized view ' || v_out_mv_consumo_vagas || ' criada com ' || v_count || ' registros' || E'\n';

    -- GRANT: Permissoes para rpo_user
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_mv_consumo_vagas);
    v_resultado := v_resultado || 'Permissoes concedidas para rpo_user';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT dashboard_criar_mv_consumo_vagas('RPO_cielo');
-- SELECT dashboard_criar_mv_consumo_vagas('RPO_cielo', 'V2');
--
-- Para atualizar a materialized view:
-- REFRESH MATERIALIZED VIEW "RPO_cielo"."mv_CONSUMO_vagas";
-- REFRESH MATERIALIZED VIEW "RPO_cielo"."V2_mv_CONSUMO_vagas";
-- ============================================================
