-- ============================================================
-- Funcao: public.dashboard_criar_mv_consumo_historico_candidatos(p_schema, p_versao)
-- Cria a materialized view MV_CONSUMO_historicoCandidatos
-- ============================================================
-- VERSAO 4.0 - COM SUPORTE A VERSAO
-- Quando p_versao = 'V2': tabelas fonte V2_USO_*, objetos V2_MV_*
-- Quando p_versao IS NULL: comportamento identico ao anterior (sem prefixo)
-- ============================================================
-- Contem todos os campos de USO_historicoCandidatos mais:
-- - fimFluxo, sequencia, responsavel, funcaoSistema (de USO_statusCandidatos)
-- - status_fim: data do proximo registro do mesmo candidato
-- - primeira_ocorrencia: sim/nao se e a primeira vez deste status para o candidato
-- - requisicao, operacao_recrutador, canal_atratividade (de MV_CONSUMO_candidatos)
-- - indice: concatenacao de id_candidato e nome_candidato
-- - sucesso_status: sim/nao baseado na sequencia do proximo status
-- - dias_no_status
-- ============================================================

DROP FUNCTION IF EXISTS public.dashboard_criar_mv_consumo_historico_candidatos(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.dashboard_criar_mv_consumo_historico_candidatos(p_schema TEXT, p_versao TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
    v_prefixo TEXT;
    -- Tabelas fonte (versionadas)
    v_tbl_configGerais TEXT;
    v_tbl_historicoCandidatos TEXT;
    v_tbl_statusCandidatos TEXT;
    v_tbl_feriados TEXT;
    -- Objetos de saida e cross-refs (versionados)
    v_out_mv_consumo_candidatos TEXT;
    v_out_mv_historico TEXT;
    -- Variaveis de trabalho
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_col RECORD;
    v_tipo_contagem TEXT;
    v_formato_datas TEXT;
    v_formato_pg TEXT;
    -- Colunas dinamicas
    v_colunas_h TEXT := '';
    v_colunas_hcs TEXT := '';
    -- Colunas dinamicas de MV_CONSUMO_candidatos
    v_mc_select TEXT := '';
    v_has_requisicao BOOLEAN := FALSE;
    v_has_operacao_recrutador BOOLEAN := FALSE;
    v_has_canal_atratividade BOOLEAN := FALSE;
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
    v_tbl_historicoCandidatos := v_prefixo || 'USO_historicoCandidatos';
    v_tbl_statusCandidatos := v_prefixo || 'USO_statusCandidatos';
    v_tbl_feriados := v_prefixo || 'USO_feriados';

    -- Objetos de saida e cross-refs
    v_out_mv_consumo_candidatos := v_prefixo || 'MV_CONSUMO_candidatos';
    v_out_mv_historico := v_prefixo || 'MV_CONSUMO_historicoCandidatos';

    IF v_prefixo <> '' THEN
        v_resultado := v_resultado || 'Versao: ' || p_versao || ' (prefixo: ' || v_prefixo || ')' || E'\n';
    END IF;

    -- ============================================================
    -- Buscar configuracoes do dashboard
    -- ============================================================

    -- Tipo de contagem de dias
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Tipo da contagem de dias'
    ) INTO v_tipo_contagem;

    -- Formato das datas
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Formato das datas'
    ) INTO v_formato_datas;

    IF LOWER(COALESCE(v_formato_datas, 'americano')) = 'brasileiro' THEN
        v_formato_pg := 'DD/MM/YYYY';
    ELSE
        v_formato_pg := 'MM/DD/YYYY';
    END IF;

    v_resultado := v_resultado || 'Tipo contagem: ' || COALESCE(v_tipo_contagem, 'nao definido') || E'\n';
    v_resultado := v_resultado || 'Formato datas: ' || COALESCE(v_formato_datas, 'americano') || ' (' || v_formato_pg || ')' || E'\n';

    -- ============================================================
    -- Gerar colunas dinamicamente de USO_historicoCandidatos
    -- ============================================================
    FOR v_col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = v_tbl_historicoCandidatos
        ORDER BY ordinal_position
    LOOP
        IF v_colunas_h <> '' THEN
            v_colunas_h := v_colunas_h || ', ';
            v_colunas_hcs := v_colunas_hcs || ', ';
        END IF;
        v_colunas_h := v_colunas_h || format('h.%I', v_col.column_name);
        IF v_col.column_name IN ('status_candidato') AND v_prefixo <> '' THEN
            v_colunas_hcs := v_colunas_hcs || format('UPPER(LEFT(TRIM(hcs.%I), 1)) || LOWER(SUBSTRING(TRIM(hcs.%I) FROM 2)) AS %I', v_col.column_name, v_col.column_name, v_col.column_name);
        ELSE
            v_colunas_hcs := v_colunas_hcs || format('hcs.%I', v_col.column_name);
        END IF;
    END LOOP;

    v_resultado := v_resultado || 'Colunas de ' || v_tbl_historicoCandidatos || ' geradas dinamicamente' || E'\n';

    -- ============================================================
    -- Detectar colunas disponiveis em MV_CONSUMO_candidatos
    -- ============================================================
    SELECT EXISTS (
        SELECT 1 FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = p_schema AND c.relname = v_out_mv_consumo_candidatos
          AND a.attnum > 0 AND NOT a.attisdropped AND a.attname = 'requisicao'
    ) INTO v_has_requisicao;

    SELECT EXISTS (
        SELECT 1 FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = p_schema AND c.relname = v_out_mv_consumo_candidatos
          AND a.attnum > 0 AND NOT a.attisdropped AND a.attname = 'operacao_recrutador'
    ) INTO v_has_operacao_recrutador;

    SELECT EXISTS (
        SELECT 1 FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = p_schema AND c.relname = v_out_mv_consumo_candidatos
          AND a.attnum > 0 AND NOT a.attisdropped AND a.attname = 'canal_atratividade'
    ) INTO v_has_canal_atratividade;

    -- Montar fragmento SELECT de MV_CONSUMO_candidatos
    v_mc_select := '';
    IF v_has_requisicao THEN
        v_mc_select := v_mc_select || ', mc.requisicao';
    ELSE
        v_mc_select := v_mc_select || ', NULL::TEXT AS requisicao';
    END IF;
    IF v_has_operacao_recrutador THEN
        v_mc_select := v_mc_select || ', mc.operacao_recrutador';
    ELSE
        v_mc_select := v_mc_select || ', NULL::TEXT AS operacao_recrutador';
    END IF;
    IF v_has_canal_atratividade THEN
        v_mc_select := v_mc_select || ', mc.canal_atratividade';
    ELSE
        v_mc_select := v_mc_select || ', NULL::TEXT AS canal_atratividade';
    END IF;

    v_resultado := v_resultado || 'MV_CONSUMO_candidatos - requisicao: ' || v_has_requisicao::TEXT || ', operacao_recrutador: ' || v_has_operacao_recrutador::TEXT || ', canal_atratividade: ' || v_has_canal_atratividade::TEXT || E'\n';

    -- ============================================================
    -- Construir SQL principal
    -- ============================================================
    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I.%I;

        CREATE MATERIALIZED VIEW %I.%I AS
        WITH historico_base AS (
            SELECT %s
            FROM %I.%I h
            WHERE EXISTS (
                SELECT 1 FROM %I.%I mc
                WHERE TRIM(mc.id_candidato) = TRIM(h.id_candidato)
            )
        ),
        historico_ordenado AS (
            SELECT
                h.*,
                ROW_NUMBER() OVER (PARTITION BY h.id_candidato ORDER BY h.created_at, h.id) AS ordem_geral,
                LEAD(h.created_at) OVER (PARTITION BY h.id_candidato ORDER BY h.created_at, h.id) AS proxima_data,
                LEAD(h.status_candidato) OVER (PARTITION BY h.id_candidato ORDER BY h.created_at, h.id) AS proximo_status
            FROM historico_base h
        ),
        primeira_ocorrencia_calc AS (
            SELECT id_candidato, status_candidato, MIN(created_at) AS primeira_data
            FROM historico_base
            GROUP BY id_candidato, status_candidato
        ),
        historico_com_status AS (
            SELECT
                ho.*,
                sc."fimFluxo" AS fim_fluxo,
                sc."sequencia"::INTEGER AS sequencia_status,
                UPPER(LEFT(TRIM(sc."responsavel"), 1)) || LOWER(SUBSTRING(TRIM(sc."responsavel") FROM 2)) AS responsavel_status,
                sc."funcaoSistema" AS funcao_sistema,
                CASE
                    WHEN sc."fimFluxo" = ''Sim'' THEN ho.created_at::DATE
                    ELSE COALESCE(ho.proxima_data::DATE, CURRENT_DATE)
                END AS status_fim,
                CASE WHEN ho.created_at = poc.primeira_data THEN ''Sim'' ELSE ''Nao'' END AS primeira_ocorrencia,
                sc_prox."sequencia" AS sequencia_proximo,
                sc_prox."funcaoSistema" AS funcao_sistema_proximo
            FROM historico_ordenado ho
            LEFT JOIN %I.%I sc ON TRIM(sc.status) = TRIM(ho.status_candidato)
            LEFT JOIN %I.%I sc_prox ON TRIM(sc_prox.status) = TRIM(ho.proximo_status)
            LEFT JOIN primeira_ocorrencia_calc poc ON TRIM(poc.id_candidato) = TRIM(ho.id_candidato) AND TRIM(poc.status_candidato) = TRIM(ho.status_candidato)
        ),
        proximo_valido AS (
            SELECT
                hcs.id_candidato, hcs.created_at, hcs.status_candidato, hcs.sequencia_status, hcs.funcao_sistema,
                hcs.proximo_status, hcs.sequencia_proximo, hcs.funcao_sistema_proximo,
                CASE
                    WHEN hcs.funcao_sistema_proximo = ''Congelada'' THEN
                        (SELECT h2.status_candidato FROM historico_ordenado h2
                         LEFT JOIN %I.%I sc2 ON TRIM(sc2.status) = TRIM(h2.status_candidato)
                         WHERE TRIM(h2.id_candidato) = TRIM(hcs.id_candidato)
                           AND h2.created_at > (SELECT MIN(h3.created_at) FROM historico_ordenado h3
                               WHERE TRIM(h3.id_candidato) = TRIM(hcs.id_candidato)
                                 AND TRIM(h3.status_candidato) = TRIM(hcs.proximo_status)
                                 AND h3.created_at > hcs.created_at)
                           AND COALESCE(sc2."funcaoSistema", '''') <> ''Congelada''
                         ORDER BY h2.created_at LIMIT 1)
                    ELSE hcs.proximo_status
                END AS proximo_status_efetivo
            FROM historico_com_status hcs
        )
        SELECT
            %s,
            hcs.fim_fluxo, hcs.sequencia_status, hcs.responsavel_status, hcs.funcao_sistema,
            hcs.status_fim AS calc_status_fim, hcs.primeira_ocorrencia AS calc_primeira_ocorrencia
            %s,
            hcs.id_candidato || '' - '' || COALESCE(hcs.nome_candidato, '''') AS calc_indice,
            CASE
                WHEN pv.proximo_status_efetivo IS NULL THEN NULL
                WHEN (SELECT sc_ef."funcaoSistema" FROM %I.%I sc_ef
                      WHERE TRIM(sc_ef.status) = TRIM(pv.proximo_status_efetivo)) IN (''Fechada'', ''Cancelada'') THEN ''Sim''
                WHEN (SELECT sc_ef."sequencia"::INTEGER FROM %I.%I sc_ef
                      WHERE TRIM(sc_ef.status) = TRIM(pv.proximo_status_efetivo)) > COALESCE(hcs.sequencia_status::INTEGER, 0) THEN ''Sim''
                WHEN (SELECT sc_ef."sequencia"::INTEGER FROM %I.%I sc_ef
                      WHERE TRIM(sc_ef.status) = TRIM(pv.proximo_status_efetivo)) < COALESCE(hcs.sequencia_status::INTEGER, 999999) THEN ''Nao''
                ELSE NULL
            END AS calc_sucesso_status,
            CASE
                WHEN hcs.created_at IS NULL THEN NULL
                WHEN %L ILIKE ''%%teis%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.created_at::DATE,
                        COALESCE(hcs.status_fim, CURRENT_DATE) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I.%I f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (COALESCE(hcs.status_fim, CURRENT_DATE) - hcs.created_at::DATE)::INTEGER
            END AS calc_dias_no_status
        FROM historico_com_status hcs
        LEFT JOIN proximo_valido pv ON TRIM(pv.id_candidato) = TRIM(hcs.id_candidato) AND pv.created_at = hcs.created_at AND TRIM(pv.status_candidato) = TRIM(hcs.status_candidato)
        LEFT JOIN %I.%I mc ON TRIM(mc.id_candidato) = TRIM(hcs.id_candidato)
        ORDER BY hcs.id_candidato, hcs.created_at
    ', p_schema, v_out_mv_historico,                           -- 1-2: DROP
       p_schema, v_out_mv_historico,                           -- 3-4: CREATE name
       v_colunas_h,                                            -- 5: colunas dinamicas historico_base
       p_schema, v_tbl_historicoCandidatos,                    -- 6-7: USO_historicoCandidatos
       p_schema, v_out_mv_consumo_candidatos,                  -- 8-9: MV_CONSUMO_candidatos (EXISTS)
       p_schema, v_tbl_statusCandidatos,                       -- 10-11: USO_statusCandidatos (sc)
       p_schema, v_tbl_statusCandidatos,                       -- 12-13: USO_statusCandidatos (sc_prox)
       p_schema, v_tbl_statusCandidatos,                       -- 14-15: USO_statusCandidatos (sc2)
       v_colunas_hcs,                                          -- 16: colunas dinamicas SELECT final
       v_mc_select,                                            -- 17: colunas de MV_CONSUMO_candidatos
       p_schema, v_tbl_statusCandidatos,                       -- 18-19: USO_statusCandidatos (sucesso 1)
       p_schema, v_tbl_statusCandidatos,                       -- 20-21: USO_statusCandidatos (sucesso 2)
       p_schema, v_tbl_statusCandidatos,                       -- 22-23: USO_statusCandidatos (sucesso 3)
       v_tipo_contagem, p_schema, v_tbl_feriados, v_formato_pg, -- 24-27: dias_no_status
       p_schema, v_out_mv_consumo_candidatos);                 -- 28-29: MV_CONSUMO_candidatos (LEFT JOIN)

    -- V1: remover prefixo calc_ dos campos calculados
    IF v_prefixo = '' THEN
        v_sql := REPLACE(v_sql, 'calc_', '');
    END IF;

    EXECUTE v_sql;

    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema, v_out_mv_historico) INTO v_count;
    v_resultado := v_resultado || v_out_mv_historico || ' criada com ' || v_count || ' registros' || E'\n';

    -- GRANT: Permissoes para rpo_user
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_mv_historico);
    v_resultado := v_resultado || 'Permissoes concedidas para rpo_user';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT dashboard_criar_mv_consumo_historico_candidatos('RPO_cielo');
-- SELECT dashboard_criar_mv_consumo_historico_candidatos('RPO_cielo', 'V2');
-- ============================================================
