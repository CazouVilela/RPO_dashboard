-- ============================================================
-- Funcao: public.dashboard_criar_mv_consumo_erros_vagas(p_schema, p_versao)
-- Cria a materialized view MV_CONSUMO_ERROS_VAGAS
-- ============================================================
-- VERSAO 2.0 - COM SUPORTE A VERSAO
-- Quando p_versao = 'V2': tabelas fonte V2_USO_*, objetos V2_MV_*, V2_vw_*
-- Quando p_versao IS NULL: comportamento identico ao anterior (sem prefixo)
-- ============================================================
-- Erros detectados:
-- 1. data_abertura vazia, formato invalido, ou futura
-- 2. data_admissao futura ou anterior ao status Fechada
-- 3. requisicao vazia ou duplicada
-- 4. sla_utilizado vazio ou sem correspondencia em USO_statusVagas
-- 5. status vazio ou nao presente em USO_statusVagas
-- ============================================================

DROP FUNCTION IF EXISTS public.dashboard_criar_mv_consumo_erros_vagas(TEXT, TEXT);
DROP FUNCTION IF EXISTS criar_mv_consumo_erros_vagas(TEXT);

CREATE OR REPLACE FUNCTION public.dashboard_criar_mv_consumo_erros_vagas(p_schema TEXT, p_versao TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
    v_prefixo TEXT;
    -- Tabelas fonte (versionadas)
    v_tbl_configGerais TEXT;
    v_tbl_statusVagas TEXT;
    v_tbl_historicoVagas TEXT;
    -- Objetos de saida e cross-refs (versionados)
    v_out_vw_vagas TEXT;
    v_out_mv_erros TEXT;
    -- Variaveis de trabalho
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_formato_pg TEXT;
    v_formato_datas TEXT;
    v_status_fechada TEXT;
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
    v_tbl_statusVagas := v_prefixo || 'USO_statusVagas';
    v_tbl_historicoVagas := v_prefixo || 'USO_historicoVagas';

    -- Objetos de saida e cross-refs
    v_out_vw_vagas := v_prefixo || 'vw_vagas_nomeFixo';
    v_out_mv_erros := v_prefixo || 'MV_CONSUMO_ERROS_VAGAS';

    IF v_prefixo <> '' THEN
        v_resultado := v_resultado || 'Versao: ' || p_versao || ' (prefixo: ' || v_prefixo || ')' || E'\n';
    END IF;

    -- Buscar formato de datas
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Formato das datas'
    ) INTO v_formato_datas;

    IF LOWER(COALESCE(v_formato_datas, 'americano')) = 'brasileiro' THEN
        v_formato_pg := 'DD/MM/YYYY';
    ELSE
        v_formato_pg := 'MM/DD/YYYY';
    END IF;

    -- Buscar nome do status com funcaoSistema = 'Fechada'
    EXECUTE format(
        'SELECT status FROM %I.%I WHERE "funcaoSistema" = ''Fechada'' LIMIT 1',
        p_schema, v_tbl_statusVagas
    ) INTO v_status_fechada;

    v_resultado := v_resultado || 'Formato datas: ' || v_formato_pg || E'\n';
    v_resultado := v_resultado || 'Status fechada: ' || COALESCE(v_status_fechada, 'nao encontrado') || E'\n';

    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I.%I;

        CREATE MATERIALIZED VIEW %I.%I AS

        -- ============================================================
        -- 1. data_abertura vazia
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''data_abertura vazia'' AS erro,
            NULL::TEXT AS dado_erro
        FROM %I.%I v
        WHERE v.data_abertura IS NULL OR TRIM(v.data_abertura) = ''''

        UNION ALL

        -- ============================================================
        -- 1b. data_abertura com formato invalido
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''data_abertura formato invalido'' AS erro,
            v.data_abertura AS dado_erro
        FROM %I.%I v
        WHERE v.data_abertura IS NOT NULL
          AND TRIM(v.data_abertura) <> ''''
          AND v.data_abertura !~ ''^\d{1,2}/\d{1,2}/\d{4}$''
          AND v.data_abertura !~ ''^\d{4}-\d{2}-\d{2}$''

        UNION ALL

        -- ============================================================
        -- 1c. data_abertura futura
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''data_abertura futura'' AS erro,
            v.data_abertura AS dado_erro
        FROM %I.%I v
        WHERE v.data_abertura IS NOT NULL
          AND TRIM(v.data_abertura) <> ''''
          AND (
              (v.data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$'' AND TO_DATE(v.data_abertura, %L) > CURRENT_DATE)
              OR
              (v.data_abertura ~ ''^\d{4}-\d{2}-\d{2}$'' AND TO_DATE(v.data_abertura, ''YYYY-MM-DD'') > CURRENT_DATE)
          )

        UNION ALL

        -- ============================================================
        -- 2a. data_admissao futura
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''data_admissao futura'' AS erro,
            v.data_admissao AS dado_erro
        FROM %I.%I v
        WHERE v.data_admissao IS NOT NULL
          AND TRIM(v.data_admissao) <> ''''
          AND (
              (v.data_admissao ~ ''^\d{1,2}/\d{1,2}/\d{4}$'' AND TO_DATE(v.data_admissao, %L) > CURRENT_DATE)
              OR
              (v.data_admissao ~ ''^\d{4}-\d{2}-\d{2}$'' AND TO_DATE(v.data_admissao, ''YYYY-MM-DD'') > CURRENT_DATE)
          )

        UNION ALL

        -- ============================================================
        -- 2b. data_admissao anterior ao status Fechada no historico
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''data_admissao anterior ao fechamento'' AS erro,
            ''admissao: '' || v.data_admissao || '' | fechamento: '' || TO_CHAR(h.created_at, %L) AS dado_erro
        FROM %I.%I v
        INNER JOIN %I.%I h
            ON TRIM(h.requisicao) = TRIM(v.requisicao)
            AND TRIM(h.status) = %L
        WHERE v.data_admissao IS NOT NULL
          AND TRIM(v.data_admissao) <> ''''
          AND (
              CASE
                  WHEN v.data_admissao ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                  THEN TO_DATE(v.data_admissao, %L)
                  WHEN v.data_admissao ~ ''^\d{4}-\d{2}-\d{2}$''
                  THEN TO_DATE(v.data_admissao, ''YYYY-MM-DD'')
              END
          ) < h.created_at::DATE

        UNION ALL

        -- ============================================================
        -- 2c. historico com created_at anterior a data_abertura
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''historico anterior a abertura ('' || h.status || '')'' AS erro,
            ''status: '' || TO_CHAR(h.created_at, %L) || '' | abertura: '' || v.data_abertura AS dado_erro
        FROM %I.%I v
        INNER JOIN %I.%I h
            ON TRIM(h.requisicao) = TRIM(v.requisicao)
        WHERE v.data_abertura IS NOT NULL
          AND TRIM(v.data_abertura) <> ''''
          AND (
              h.created_at::DATE < CASE
                  WHEN v.data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                  THEN TO_DATE(v.data_abertura, %L)
                  WHEN v.data_abertura ~ ''^\d{4}-\d{2}-\d{2}$''
                  THEN TO_DATE(v.data_abertura, ''YYYY-MM-DD'')
              END
          )

        UNION ALL

        -- ============================================================
        -- 3a. requisicao vazia
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''requisicao vazia'' AS erro,
            NULL::TEXT AS dado_erro
        FROM %I.%I v
        WHERE v.requisicao IS NULL OR TRIM(v.requisicao) = ''''

        UNION ALL

        -- ============================================================
        -- 3b. requisicao duplicada
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''requisicao duplicada ('' || dup.qtd || '' ocorrencias)'' AS erro,
            NULL::TEXT AS dado_erro
        FROM %I.%I v
        INNER JOIN (
            SELECT requisicao, COUNT(*) AS qtd
            FROM %I.%I
            WHERE requisicao IS NOT NULL AND TRIM(requisicao) <> ''''
            GROUP BY requisicao
            HAVING COUNT(*) > 1
        ) dup ON TRIM(dup.requisicao) = TRIM(v.requisicao)

        UNION ALL

        -- ============================================================
        -- 4a. sla_utilizado vazio
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''sla_utilizado vazio'' AS erro,
            NULL::TEXT AS dado_erro
        FROM %I.%I v
        WHERE v.sla_utilizado IS NULL OR TRIM(v.sla_utilizado) = ''''

        UNION ALL

        -- ============================================================
        -- 4b. sla_utilizado sem correspondencia em USO_statusVagas
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''sla_utilizado inconsistente'' AS erro,
            v.sla_utilizado AS dado_erro
        FROM %I.%I v
        WHERE v.sla_utilizado IS NOT NULL
          AND TRIM(v.sla_utilizado) <> ''''
          AND NOT EXISTS (
              SELECT 1 FROM information_schema.columns c
              WHERE c.table_schema = %L
                AND c.table_name = %L
                AND c.column_name NOT IN (''status'',''fimFluxo'',''sequencia'',''responsavel'',''funcaoSistema'',
                    ''_airbyte_raw_id'',''_airbyte_extracted_at'',''_airbyte_meta'',''_airbyte_generation_id'')
                AND (
                    LOWER(c.column_name) = LOWER(REPLACE(TRIM(v.sla_utilizado), '' '', ''_''))
                    OR LOWER(c.column_name) = LOWER(REPLACE(TRIM(v.sla_utilizado), '' '', ''_'') || ''_'')
                )
          )

        UNION ALL

        -- ============================================================
        -- 5a. status vazio
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''status vazio'' AS erro,
            NULL::TEXT AS dado_erro
        FROM %I.%I v
        WHERE v.status IS NULL OR TRIM(v.status) = ''''

        UNION ALL

        -- ============================================================
        -- 5b. status nao presente em USO_statusVagas
        -- ============================================================
        SELECT
            v.requisicao,
            v.vaga_titulo,
            v.operacao_recrutador AS recrutador,
            ''status nao cadastrado'' AS erro,
            v.status AS dado_erro
        FROM %I.%I v
        WHERE v.status IS NOT NULL
          AND TRIM(v.status) <> ''''
          AND NOT EXISTS (
              SELECT 1 FROM %I.%I sv
              WHERE TRIM(sv.status) = TRIM(v.status)
          )

        ORDER BY requisicao, erro
    ',
    p_schema, v_out_mv_erros,                  -- 1-2: DROP
    p_schema, v_out_mv_erros,                  -- 3-4: CREATE
    p_schema, v_out_vw_vagas,                  -- 5-6: data_abertura vazia
    p_schema, v_out_vw_vagas,                  -- 7-8: data_abertura formato invalido
    p_schema, v_out_vw_vagas, v_formato_pg,    -- 9-11: data_abertura futura
    p_schema, v_out_vw_vagas, v_formato_pg,    -- 12-14: data_admissao futura
    v_formato_pg,                              -- 15: TO_CHAR formato (data_admissao anterior)
    p_schema, v_out_vw_vagas,                  -- 16-17: vw_vagas (data_admissao anterior)
    p_schema, v_tbl_historicoVagas,            -- 18-19: historicoVagas (data_admissao anterior)
    v_status_fechada, v_formato_pg,            -- 20-21: status fechada, formato
    v_formato_pg,                              -- 22: TO_CHAR formato (historico anterior abertura)
    p_schema, v_out_vw_vagas,                  -- 23-24: vw_vagas (historico anterior abertura)
    p_schema, v_tbl_historicoVagas,            -- 25-26: historicoVagas (historico anterior abertura)
    v_formato_pg,                              -- 27: TO_DATE formato
    p_schema, v_out_vw_vagas,                  -- 28-29: requisicao vazia
    p_schema, v_out_vw_vagas,                  -- 30-31: requisicao duplicada (v)
    p_schema, v_out_vw_vagas,                  -- 32-33: requisicao duplicada (subquery)
    p_schema, v_out_vw_vagas,                  -- 34-35: sla_utilizado vazio
    p_schema, v_out_vw_vagas,                  -- 36-37: sla_utilizado inconsistente (v)
    p_schema, v_tbl_statusVagas,               -- 38-39: info_schema table_name
    p_schema, v_out_vw_vagas,                  -- 40-41: status vazio
    p_schema, v_out_vw_vagas,                  -- 42-43: status nao cadastrado (v)
    p_schema, v_tbl_statusVagas);              -- 44-45: statusVagas

    EXECUTE v_sql;

    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema, v_out_mv_erros) INTO v_count;
    v_resultado := v_resultado || v_out_mv_erros || ' criada com ' || v_count || ' erros' || E'\n';

    -- Resumo por tipo de erro
    FOR v_status_fechada IN
        EXECUTE format('SELECT erro || '': '' || COUNT(*)::TEXT FROM %I.%I GROUP BY erro ORDER BY erro', p_schema, v_out_mv_erros)
    LOOP
        v_resultado := v_resultado || '  - ' || v_status_fechada || E'\n';
    END LOOP;

    -- GRANT
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_mv_erros);
    v_resultado := v_resultado || 'Permissoes concedidas para rpo_user';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cielo');
-- SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_cielo', 'V2');
-- ============================================================
