-- ============================================================
-- Funcao: public.dashboard_criar_mv_consumo_historico_vagas(p_schema, p_versao)
-- Cria a materialized view MV_CONSUMO_historicoVagas
-- ============================================================
-- VERSAO 4.0 - COM SUPORTE A VERSAO
-- Quando p_versao = 'V2': tabelas fonte V2_USO_*, objetos V2_MV_*, V2_vw_*
-- Quando p_versao IS NULL: comportamento identico ao anterior (sem prefixo)
-- ============================================================
-- Contem todos os campos de USO_historicoVagas mais:
-- - fimFluxo, sequencia, responsavel, funcaoSistema (de USO_statusVagas)
-- - status_fim: data do proximo registro da mesma requisicao
-- - primeira_ocorrencia: sim/nao se e a primeira vez deste status para a requisicao
-- - vaga_titulo, geo_local, data_abertura_vaga (de vw_vagas_nomeFixo)
-- - indice: concatenacao de requisicao e vaga_titulo
-- - sucesso_status: sim/nao baseado na sequencia do proximo status
-- - dias_abertura_ate_status, dias_no_status
-- ============================================================

DROP FUNCTION IF EXISTS public.dashboard_criar_mv_consumo_historico_vagas(TEXT, TEXT);
DROP FUNCTION IF EXISTS criar_mv_consumo_historico_vagas(TEXT);

CREATE OR REPLACE FUNCTION public.dashboard_criar_mv_consumo_historico_vagas(p_schema TEXT, p_versao TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
    v_prefixo TEXT;
    -- Tabelas fonte (versionadas)
    v_tbl_configGerais TEXT;
    v_tbl_historicoVagas TEXT;
    v_tbl_statusVagas TEXT;
    v_tbl_feriados TEXT;
    v_tbl_dicionarioVagas TEXT;
    -- Objetos de saida e cross-refs (versionados)
    v_out_vw_vagas TEXT;
    v_out_mv_consumo_vagas TEXT;
    v_out_mv_historico TEXT;
    -- Variaveis de trabalho
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_col RECORD;
    v_tabela_vagas TEXT;
    v_tipo_contagem TEXT;
    v_formato_datas TEXT;
    v_formato_pg TEXT;
    -- Colunas dinamicas
    v_colunas_h TEXT := '';
    v_colunas_hcs TEXT := '';
    v_colunas_union TEXT := '';
    -- waiting to start
    v_has_waiting_to_start BOOLEAN := FALSE;
    v_waiting_to_start_sql TEXT := '';
    v_status_fim_waiting_sql TEXT := '';
    v_dias_ate_inicio_sql TEXT := '';
    -- geo_local
    v_has_geo_local BOOLEAN := FALSE;
    v_geo_local_select TEXT := '';
    v_geo_local_vagas_com_rn TEXT := '';
    v_geo_local_vagas_info TEXT := '';
    v_geo_local_hcs TEXT := '';
    -- selecionado_* extras
    v_sel_vagas_com_rn TEXT := '';
    v_sel_vagas_info TEXT := '';
    v_sel_hcs TEXT := '';
    v_sel_select TEXT := '';
    -- waiting to start generico
    v_has_data_admissao BOOLEAN := FALSE;
    v_status_fechada TEXT := NULL;
    v_colunas_union_generic TEXT := '';
    v_col_in_view BOOLEAN;
    -- time_to_* fields
    v_time_to_sql TEXT := '';
    v_has_admissao_in_view BOOLEAN := FALSE;
    v_has_form_in_view BOOLEAN := FALSE;
    v_filled_sub TEXT;
    v_admissao_sub TEXT;
    v_form_sub TEXT;
    v_holidays_sub TEXT;
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
    v_tbl_historicoVagas := v_prefixo || 'USO_historicoVagas';
    v_tbl_statusVagas := v_prefixo || 'USO_statusVagas';
    v_tbl_feriados := v_prefixo || 'USO_feriados';
    v_tbl_dicionarioVagas := v_prefixo || 'USO_dicionarioVagas';

    -- Objetos de saida e cross-refs
    v_out_vw_vagas := v_prefixo || 'vw_vagas_nomeFixo';
    v_out_mv_consumo_vagas := v_prefixo || 'MV_CONSUMO_vagas';
    v_out_mv_historico := v_prefixo || 'MV_CONSUMO_historicoVagas';

    IF v_prefixo <> '' THEN
        v_resultado := v_resultado || 'Versao: ' || p_versao || ' (prefixo: ' || v_prefixo || ')' || E'\n';
    END IF;

    -- ============================================================
    -- Buscar configuracoes do dashboard
    -- ============================================================

    -- Nome da tabela de vagas
    EXECUTE format(
        'SELECT "Valor" FROM %I.%I WHERE "Configuracao" = %L',
        p_schema, v_tbl_configGerais, 'Nome da aba de controle vagas'
    ) INTO v_tabela_vagas;
    v_tabela_vagas := v_prefixo || 'USO_' || REPLACE(v_tabela_vagas, ' ', '_');

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

    v_resultado := v_resultado || 'Tabela vagas: ' || v_tabela_vagas || E'\n';
    v_resultado := v_resultado || 'Tipo contagem: ' || COALESCE(v_tipo_contagem, 'nao definido') || E'\n';
    v_resultado := v_resultado || 'Formato datas: ' || COALESCE(v_formato_datas, 'americano') || ' (' || v_formato_pg || ')' || E'\n';

    -- ============================================================
    -- Verificar se geo_local existe na view de vagas
    -- ============================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = v_out_vw_vagas
          AND column_name = 'geo_local'
    ) INTO v_has_geo_local;

    IF v_has_geo_local THEN
        v_geo_local_vagas_com_rn := ', v.geo_local';
        v_geo_local_vagas_info := ', geo_local';
        v_geo_local_hcs := ', vi.geo_local';
        v_geo_local_select := ', hcs.geo_local';
        v_resultado := v_resultado || 'geo_local: INCLUIDO' || E'\n';
    ELSE
        v_geo_local_vagas_com_rn := '';
        v_geo_local_vagas_info := '';
        v_geo_local_hcs := '';
        v_geo_local_select := ', NULL::TEXT AS geo_local';
        v_resultado := v_resultado || 'geo_local: NAO EXISTE (NULL)' || E'\n';
    END IF;

    -- ============================================================
    -- Buscar campos DADOS_SELECIONADO de vw_vagas_nomeFixo
    -- ============================================================
    FOR v_col IN
        EXECUTE format(
            'SELECT LOWER(d."nomeFixo") AS column_name
             FROM %I.%I d
             WHERE UPPER(TRIM(d."grupoDoCampo")) = ''DADOS_SELECIONADO''
               AND d."nomeFixo" IS NOT NULL AND TRIM(d."nomeFixo") <> ''''
               AND EXISTS (
                   SELECT 1 FROM pg_attribute a
                   JOIN pg_class c ON c.oid = a.attrelid
                   JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE n.nspname = %L AND c.relname = %L
                     AND a.attnum > 0 AND NOT a.attisdropped
                     AND a.attname = LOWER(d."nomeFixo")
               )
               AND NOT EXISTS (
                   SELECT 1 FROM pg_attribute a2
                   JOIN pg_class c2 ON c2.oid = a2.attrelid
                   JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
                   WHERE n2.nspname = %L AND c2.relname = %L
                     AND a2.attnum > 0 AND NOT a2.attisdropped
                     AND a2.attname = LOWER(d."nomeFixo")
               )
             ORDER BY d."nomeFixo"',
            p_schema, v_tbl_dicionarioVagas,
            p_schema, v_out_vw_vagas,
            p_schema, v_tbl_historicoVagas
        )
    LOOP
        v_sel_vagas_com_rn := v_sel_vagas_com_rn || format(', v.%I', v_col.column_name);
        v_sel_vagas_info := v_sel_vagas_info || format(', %I', v_col.column_name);
        v_sel_hcs := v_sel_hcs || format(', vi.%I', v_col.column_name);
        v_sel_select := v_sel_select || format(', hcs.%I', v_col.column_name);
        v_resultado := v_resultado || 'DADOS_SELECIONADO extra (de vagas): ' || v_col.column_name || E'\n';
    END LOOP;

    -- Concatenar fragmentos selecionado aos geo_local
    v_geo_local_vagas_com_rn := v_geo_local_vagas_com_rn || v_sel_vagas_com_rn;
    v_geo_local_vagas_info := v_geo_local_vagas_info || v_sel_vagas_info;
    v_geo_local_hcs := v_geo_local_hcs || v_sel_hcs;
    v_geo_local_select := v_geo_local_select || v_sel_select;

    -- ============================================================
    -- Gerar colunas dinamicamente de USO_historicoVagas
    -- ============================================================
    FOR v_col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = v_tbl_historicoVagas
        ORDER BY ordinal_position
    LOOP
        IF v_colunas_h <> '' THEN
            v_colunas_h := v_colunas_h || ', ';
            v_colunas_hcs := v_colunas_hcs || ', ';
            v_colunas_union := v_colunas_union || ', ';
        END IF;
        v_colunas_h := v_colunas_h || format('h.%I', v_col.column_name);
        v_colunas_hcs := v_colunas_hcs || format('hcs.%I', v_col.column_name);

        CASE v_col.column_name
            WHEN 'id' THEN v_colunas_union := v_colunas_union || '-1 AS id';
            WHEN 'requisicao' THEN v_colunas_union := v_colunas_union || 'TRIM(vg."ID_Position_ADP") AS requisicao';
            WHEN 'status' THEN v_colunas_union := v_colunas_union || '''waiting to start'' AS status';
            WHEN 'created_at' THEN v_colunas_union := v_colunas_union || format('(SELECT h.created_at FROM %I.%I h WHERE TRIM(h.requisicao) = TRIM(vg."ID_Position_ADP") AND h.status = ''Filled'' ORDER BY h.created_at DESC LIMIT 1) AS created_at', p_schema, v_tbl_historicoVagas);
            WHEN 'alterado_por' THEN v_colunas_union := v_colunas_union || '''gerado_mv'' AS alterado_por';
            WHEN 'updated_at' THEN v_colunas_union := v_colunas_union || 'CURRENT_TIMESTAMP AS updated_at';
            WHEN 'version' THEN v_colunas_union := v_colunas_union || '1 AS version';
            WHEN 'selecionado_nome' THEN v_colunas_union := v_colunas_union || 'vg."Selected_Candidate__Full_name_" AS selecionado_nome';
            ELSE v_colunas_union := v_colunas_union || format('NULL::%s AS %I',
                (SELECT data_type FROM information_schema.columns
                 WHERE table_schema = p_schema AND table_name = v_tbl_historicoVagas AND column_name = v_col.column_name),
                v_col.column_name);
        END CASE;
    END LOOP;

    v_resultado := v_resultado || 'Colunas de ' || v_tbl_historicoVagas || ' geradas dinamicamente' || E'\n';

    -- ============================================================
    -- waiting to start: APENAS para RPO_semper_laser
    -- ============================================================
    IF p_schema = 'RPO_semper_laser' THEN
        v_has_waiting_to_start := TRUE;
        v_resultado := v_resultado || 'waiting to start: ATIVADO (semper_laser)' || E'\n';

        v_waiting_to_start_sql := format('
            UNION ALL

            SELECT
                %s
            FROM (
                SELECT vg.*, ROW_NUMBER() OVER (PARTITION BY TRIM(vg."ID_Position_ADP") ORDER BY vg."ID_Position_ADP") as rn
                FROM %I.%I vg
                WHERE vg."Start_Date__Admission_" IS NOT NULL
                  AND TRIM(vg."Start_Date__Admission_") <> ''''
                  AND vg."Start_Date__Admission_" ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                  AND TRIM(vg."ID_Position_ADP") IS NOT NULL
                  AND TRIM(vg."ID_Position_ADP") <> ''''
            ) vg
            WHERE vg.rn = 1
              AND EXISTS (
                  SELECT 1 FROM %I.%I mv
                  WHERE TRIM(mv.requisicao) = TRIM(vg."ID_Position_ADP")
              )
              AND EXISTS (
                  SELECT 1 FROM %I.%I h
                  WHERE TRIM(h.requisicao) = TRIM(vg."ID_Position_ADP")
                    AND h.status = ''Filled''
              )
        ', v_colunas_union, p_schema, v_tabela_vagas, p_schema, v_out_mv_consumo_vagas, p_schema, v_tbl_historicoVagas);

        v_status_fim_waiting_sql := format('
                    WHEN ho.status = ''waiting to start'' THEN (
                        SELECT CASE
                            WHEN vg."Start_Date__Admission_" ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                            THEN TO_DATE(vg."Start_Date__Admission_", %L)
                            ELSE NULL
                        END
                        FROM %I.%I vg
                        WHERE TRIM(vg."ID_Position_ADP") = TRIM(ho.requisicao)
                        LIMIT 1
                    )
        ', v_formato_pg, p_schema, v_tabela_vagas);

        v_dias_ate_inicio_sql := format(',
            CASE
                WHEN hcs.data_abertura_vaga IS NULL THEN NULL
                WHEN (SELECT vg."Start_Date__Admission_" FROM %I.%I vg WHERE TRIM(vg."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1) IS NULL THEN NULL
                WHEN TRIM((SELECT vg."Start_Date__Admission_" FROM %I.%I vg WHERE TRIM(vg."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1)) = '''' THEN NULL
                WHEN (SELECT vg."Start_Date__Admission_" FROM %I.%I vg WHERE TRIM(vg."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1) !~ ''^\d{1,2}/\d{1,2}/\d{4}$'' THEN NULL
                WHEN %L ILIKE ''%%%%uteis%%%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.data_abertura_vaga,
                        TO_DATE((SELECT vg2."Start_Date__Admission_" FROM %I.%I vg2 WHERE TRIM(vg2."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1), %L) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I.%I f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (
                    TO_DATE((SELECT vg3."Start_Date__Admission_" FROM %I.%I vg3 WHERE TRIM(vg3."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1), %L) - hcs.data_abertura_vaga
                )::INTEGER
            END AS dias_ate_inicio
        ', p_schema, v_tabela_vagas,
           p_schema, v_tabela_vagas,
           p_schema, v_tabela_vagas,
           v_tipo_contagem,
           p_schema, v_tabela_vagas, v_formato_pg,
           p_schema, v_tbl_feriados, v_formato_pg,
           p_schema, v_tabela_vagas, v_formato_pg);
    ELSE
        -- ============================================================
        -- waiting to start GENERICO: para schemas com data_admissao
        -- ============================================================
        SELECT EXISTS (
            SELECT 1 FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = p_schema AND c.relname = v_out_vw_vagas
              AND a.attnum > 0 AND NOT a.attisdropped
              AND a.attname = 'data_admissao'
        ) INTO v_has_data_admissao;

        IF v_has_data_admissao THEN
            EXECUTE format(
                'SELECT status FROM %I.%I WHERE "funcaoSistema" = ''Fechada'' LIMIT 1',
                p_schema, v_tbl_statusVagas
            ) INTO v_status_fechada;
        END IF;

        IF v_has_data_admissao AND v_status_fechada IS NOT NULL THEN
            v_has_waiting_to_start := TRUE;
            v_resultado := v_resultado || 'waiting to start: ATIVADO (generico, status fechada: ' || v_status_fechada || ')' || E'\n';

            v_colunas_union_generic := '';
            FOR v_col IN
                SELECT column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = p_schema
                  AND table_name = v_tbl_historicoVagas
                ORDER BY ordinal_position
            LOOP
                IF v_colunas_union_generic <> '' THEN
                    v_colunas_union_generic := v_colunas_union_generic || ', ';
                END IF;

                SELECT EXISTS (
                    SELECT 1 FROM pg_attribute a
                    JOIN pg_class c ON c.oid = a.attrelid
                    JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = p_schema AND c.relname = v_out_vw_vagas
                      AND a.attnum > 0 AND NOT a.attisdropped
                      AND a.attname = v_col.column_name
                ) INTO v_col_in_view;

                CASE v_col.column_name
                    WHEN 'id' THEN v_colunas_union_generic := v_colunas_union_generic || '-1 AS id';
                    WHEN 'requisicao' THEN v_colunas_union_generic := v_colunas_union_generic || 'v.requisicao';
                    WHEN 'status' THEN v_colunas_union_generic := v_colunas_union_generic || '''waiting to start'' AS status';
                    WHEN 'created_at' THEN v_colunas_union_generic := v_colunas_union_generic || format(
                        '(SELECT h.created_at FROM %I.%I h WHERE TRIM(h.requisicao) = TRIM(v.requisicao) AND TRIM(h.status) = %L ORDER BY h.created_at DESC LIMIT 1) AS created_at',
                        p_schema, v_tbl_historicoVagas, v_status_fechada);
                    WHEN 'alterado_por' THEN v_colunas_union_generic := v_colunas_union_generic || '''gerado_mv'' AS alterado_por';
                    WHEN 'updated_at' THEN v_colunas_union_generic := v_colunas_union_generic || 'CURRENT_TIMESTAMP AS updated_at';
                    WHEN 'version' THEN v_colunas_union_generic := v_colunas_union_generic || '1 AS version';
                    ELSE
                        IF v_col_in_view THEN
                            v_colunas_union_generic := v_colunas_union_generic || format('v.%I', v_col.column_name);
                        ELSE
                            v_colunas_union_generic := v_colunas_union_generic || format('NULL::%s AS %I', v_col.data_type, v_col.column_name);
                        END IF;
                END CASE;
            END LOOP;

            v_waiting_to_start_sql := format('
                UNION ALL

                SELECT
                    %s
                FROM (
                    SELECT v.*, ROW_NUMBER() OVER (PARTITION BY TRIM(v.requisicao) ORDER BY v.requisicao) as rn
                    FROM %I.%I v
                    WHERE v.data_admissao IS NOT NULL
                      AND TRIM(v.data_admissao) <> ''''
                      AND v.data_admissao ~ ''^\d{1,2}/\d{1,2}/\d{4}$|^\d{4}-\d{2}-\d{2}$''
                      AND v.requisicao IS NOT NULL
                      AND TRIM(v.requisicao) <> ''''
                ) v
                WHERE v.rn = 1
                  AND EXISTS (
                      SELECT 1 FROM %I.%I mv
                      WHERE TRIM(mv.requisicao) = TRIM(v.requisicao)
                  )
                  AND EXISTS (
                      SELECT 1 FROM %I.%I h
                      WHERE TRIM(h.requisicao) = TRIM(v.requisicao)
                        AND TRIM(h.status) = %L
                  )
            ', v_colunas_union_generic, p_schema, v_out_vw_vagas, p_schema, v_out_mv_consumo_vagas, p_schema, v_tbl_historicoVagas, v_status_fechada);

            v_status_fim_waiting_sql := format('
                        WHEN ho.status = ''waiting to start'' THEN (
                            SELECT CASE
                                WHEN vw.data_admissao ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                                THEN TO_DATE(vw.data_admissao, %L)
                                WHEN vw.data_admissao ~ ''^\d{4}-\d{2}-\d{2}$''
                                THEN TO_DATE(vw.data_admissao, ''YYYY-MM-DD'')
                                ELSE NULL
                            END
                            FROM %I.%I vw
                            WHERE TRIM(vw.requisicao) = TRIM(ho.requisicao)
                            LIMIT 1
                        )
            ', v_formato_pg, p_schema, v_out_vw_vagas);

            v_dias_ate_inicio_sql := format(',
                CASE
                    WHEN hcs.data_abertura_vaga IS NULL THEN NULL
                    WHEN (SELECT vw.data_admissao FROM %I.%I vw WHERE TRIM(vw.requisicao) = TRIM(hcs.requisicao) LIMIT 1) IS NULL THEN NULL
                    WHEN TRIM((SELECT vw.data_admissao FROM %I.%I vw WHERE TRIM(vw.requisicao) = TRIM(hcs.requisicao) LIMIT 1)) = '''' THEN NULL
                    WHEN %L ILIKE ''%%%%uteis%%%%'' THEN (
                        SELECT COUNT(*)::INTEGER FROM generate_series(
                            hcs.data_abertura_vaga,
                            CASE
                                WHEN (SELECT vw2.data_admissao FROM %I.%I vw2 WHERE TRIM(vw2.requisicao) = TRIM(hcs.requisicao) LIMIT 1) ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                                THEN TO_DATE((SELECT vw2.data_admissao FROM %I.%I vw2 WHERE TRIM(vw2.requisicao) = TRIM(hcs.requisicao) LIMIT 1), %L)
                                ELSE TO_DATE((SELECT vw2.data_admissao FROM %I.%I vw2 WHERE TRIM(vw2.requisicao) = TRIM(hcs.requisicao) LIMIT 1), ''YYYY-MM-DD'')
                            END - INTERVAL ''1 day'',
                            ''1 day''::INTERVAL
                        ) AS d(dt)
                        WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                          AND NOT EXISTS (SELECT 1 FROM %I.%I f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                    ELSE (
                        CASE
                            WHEN (SELECT vw3.data_admissao FROM %I.%I vw3 WHERE TRIM(vw3.requisicao) = TRIM(hcs.requisicao) LIMIT 1) ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                            THEN TO_DATE((SELECT vw3.data_admissao FROM %I.%I vw3 WHERE TRIM(vw3.requisicao) = TRIM(hcs.requisicao) LIMIT 1), %L)
                            ELSE TO_DATE((SELECT vw3.data_admissao FROM %I.%I vw3 WHERE TRIM(vw3.requisicao) = TRIM(hcs.requisicao) LIMIT 1), ''YYYY-MM-DD'')
                        END - hcs.data_abertura_vaga
                    )::INTEGER
                END AS dias_ate_inicio
            ', p_schema, v_out_vw_vagas,
               p_schema, v_out_vw_vagas,
               v_tipo_contagem,
               p_schema, v_out_vw_vagas,
               p_schema, v_out_vw_vagas, v_formato_pg,
               p_schema, v_out_vw_vagas,
               p_schema, v_tbl_feriados, v_formato_pg,
               p_schema, v_out_vw_vagas,
               p_schema, v_out_vw_vagas, v_formato_pg,
               p_schema, v_out_vw_vagas);
        ELSE
            v_resultado := v_resultado || 'waiting to start: DESATIVADO (sem data_admissao ou status Fechada)' || E'\n';
            v_waiting_to_start_sql := '';
            v_status_fim_waiting_sql := 'WHEN FALSE THEN NULL';
            v_dias_ate_inicio_sql := ',
                NULL::INTEGER AS dias_ate_inicio';
        END IF;
    END IF;

    -- ============================================================
    -- time_to_* fields
    -- ============================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = p_schema AND table_name = v_out_vw_vagas AND column_name = 'data_admissao'
    ) INTO v_has_admissao_in_view;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = p_schema AND table_name = v_out_vw_vagas AND column_name = 'vaga_data_form'
    ) INTO v_has_form_in_view;

    -- Subquery: filled date (data do ultimo status com funcaoSistema = Fechada)
    v_filled_sub := format(
        '(SELECT MAX(h_f.created_at)::DATE FROM historico_base h_f LEFT JOIN %I.%I sv_f ON TRIM(sv_f.status) = TRIM(h_f.status) WHERE TRIM(h_f.requisicao) = TRIM(hcs.requisicao) AND sv_f."funcaoSistema" = ''Fechada'')',
        p_schema, v_tbl_statusVagas
    );

    -- Subquery: holidays check
    v_holidays_sub := format(
        'NOT EXISTS (SELECT 1 FROM %I.%I f WHERE TO_DATE(f."Data", %L) = d.dt::DATE)',
        p_schema, v_tbl_feriados, v_formato_pg
    );

    -- Subquery: admissao date (parsed)
    IF v_has_admissao_in_view THEN
        v_admissao_sub := format(
            '(SELECT CASE WHEN vw_a.data_admissao ~ ''^\d{1,2}/\d{1,2}/\d{4}$'' THEN TO_DATE(vw_a.data_admissao, %L) WHEN vw_a.data_admissao ~ ''^\d{4}-\d{2}-\d{2}$'' THEN TO_DATE(vw_a.data_admissao, ''YYYY-MM-DD'') ELSE NULL END FROM %I.%I vw_a WHERE TRIM(vw_a.requisicao) = TRIM(hcs.requisicao) LIMIT 1)',
            v_formato_pg, p_schema, v_out_vw_vagas
        );
    ELSE
        v_admissao_sub := 'NULL::DATE';
    END IF;

    -- Subquery: form date (parsed)
    IF v_has_form_in_view THEN
        v_form_sub := format(
            '(SELECT CASE WHEN vw_f.vaga_data_form ~ ''^\d{1,2}/\d{1,2}/\d{4}$'' THEN TO_DATE(vw_f.vaga_data_form, %L) WHEN vw_f.vaga_data_form ~ ''^\d{4}-\d{2}-\d{2}$'' THEN TO_DATE(vw_f.vaga_data_form, ''YYYY-MM-DD'') ELSE NULL END FROM %I.%I vw_f WHERE TRIM(vw_f.requisicao) = TRIM(hcs.requisicao) LIMIT 1)',
            v_formato_pg, p_schema, v_out_vw_vagas
        );
    ELSE
        v_form_sub := 'NULL::DATE';
    END IF;

    -- Montar os 6 campos time_to_*
    -- time_to_fill* so preenchido para status com funcaoSistema = 'Fechada'
    v_time_to_sql :=
        -- 1. time_to_fill (dias corridos: abertura -> filled)
        ',
            CASE
                WHEN hcs.funcao_sistema = ''Fechada'' AND hcs.data_abertura_vaga IS NOT NULL
                THEN (' || v_filled_sub || ' - hcs.data_abertura_vaga)::INTEGER
                ELSE NULL
            END AS time_to_fill' ||
        -- 2. time_to_start (dias corridos: abertura -> admissao)
        ',
            CASE
                WHEN hcs.data_abertura_vaga IS NULL THEN NULL
                WHEN ' || v_admissao_sub || ' IS NULL THEN NULL
                ELSE (' || v_admissao_sub || ' - hcs.data_abertura_vaga)::INTEGER
            END AS time_to_start' ||
        -- 3. time_to_fill_no_holidays (dias uteis: abertura -> filled)
        ',
            CASE
                WHEN hcs.funcao_sistema = ''Fechada'' AND hcs.data_abertura_vaga IS NOT NULL AND ' || v_filled_sub || ' IS NOT NULL
                THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.data_abertura_vaga,
                        ' || v_filled_sub || ' - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND ' || v_holidays_sub || '
                )
                ELSE NULL
            END AS time_to_fill_no_holidays' ||
        -- 4. time_to_start_no_holidays (dias uteis: abertura -> admissao)
        ',
            CASE
                WHEN hcs.data_abertura_vaga IS NULL THEN NULL
                WHEN ' || v_admissao_sub || ' IS NULL THEN NULL
                ELSE (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.data_abertura_vaga,
                        ' || v_admissao_sub || ' - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND ' || v_holidays_sub || '
                )
            END AS time_to_start_no_holidays' ||
        -- 5. time_to_fill_forms (dias corridos: form_date -> filled)
        ',
            CASE
                WHEN hcs.funcao_sistema = ''Fechada'' AND ' || v_form_sub || ' IS NOT NULL AND ' || v_filled_sub || ' IS NOT NULL
                THEN (' || v_filled_sub || ' - ' || v_form_sub || ')::INTEGER
                ELSE NULL
            END AS time_to_fill_forms' ||
        -- 6. time_to_start_forms (dias corridos: form_date -> admissao)
        ',
            CASE
                WHEN ' || v_form_sub || ' IS NULL THEN NULL
                WHEN ' || v_admissao_sub || ' IS NULL THEN NULL
                ELSE (' || v_admissao_sub || ' - ' || v_form_sub || ')::INTEGER
            END AS time_to_start_forms';

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
                SELECT 1 FROM %I.%I mv
                WHERE TRIM(mv.requisicao) = TRIM(h.requisicao)
            )
            %s
        ),
        historico_ordenado AS (
            SELECT
                h.*,
                ROW_NUMBER() OVER (PARTITION BY h.requisicao ORDER BY h.created_at, h.id) AS ordem_geral,
                LEAD(h.created_at) OVER (PARTITION BY h.requisicao ORDER BY h.created_at, h.id) AS proxima_data,
                LEAD(h.status) OVER (PARTITION BY h.requisicao ORDER BY h.created_at, h.id) AS proximo_status
            FROM historico_base h
        ),
        primeira_ocorrencia_calc AS (
            SELECT requisicao, status, MIN(created_at) AS primeira_data
            FROM historico_base
            GROUP BY requisicao, status
        ),
        vagas_com_rn AS (
            SELECT
                v.requisicao, v.vaga_titulo, v.data_abertura%s,
                ROW_NUMBER() OVER (PARTITION BY v.requisicao ORDER BY v.data_abertura DESC) as rn
            FROM %I.%I v
            WHERE v.requisicao IS NOT NULL AND TRIM(v.requisicao) <> ''''
              AND v.vaga_titulo IS NOT NULL AND TRIM(v.vaga_titulo) <> ''''
              AND v.data_abertura IS NOT NULL AND TRIM(v.data_abertura) <> ''''
              AND v.data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$|^\d{4}-\d{2}-\d{2}$''
              AND (
                  CASE
                      WHEN v.data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                      THEN TO_DATE(v.data_abertura, %L)
                      WHEN v.data_abertura ~ ''^\d{4}-\d{2}-\d{2}$''
                      THEN TO_DATE(v.data_abertura, ''YYYY-MM-DD'')
                  END
              ) <= CURRENT_DATE
        ),
        vagas_info AS (
            SELECT requisicao, vaga_titulo%s,
                CASE
                    WHEN data_abertura ~ ''^\d{1,2}/\d{1,2}/\d{4}$''
                    THEN TO_DATE(data_abertura, %L)
                    WHEN data_abertura ~ ''^\d{4}-\d{2}-\d{2}$''
                    THEN TO_DATE(data_abertura, ''YYYY-MM-DD'')
                    ELSE NULL
                END AS data_abertura_vaga
            FROM vagas_com_rn WHERE rn = 1
        ),
        historico_com_status AS (
            SELECT
                ho.*,
                sv."fimFluxo" AS fim_fluxo,
                CASE WHEN ho.status = ''waiting to start'' THEN 9999 ELSE sv."sequencia"::INTEGER END AS sequencia_status,
                sv."responsavel" AS responsavel_status,
                sv."funcaoSistema" AS funcao_sistema,
                CASE
                    %s
                    WHEN sv."fimFluxo" = ''Sim'' THEN ho.created_at::DATE
                    ELSE COALESCE(ho.proxima_data::DATE, CURRENT_DATE)
                END AS status_fim,
                CASE WHEN ho.created_at = poc.primeira_data THEN ''Sim'' ELSE ''Nao'' END AS primeira_ocorrencia,
                sv_prox."sequencia" AS sequencia_proximo,
                sv_prox."funcaoSistema" AS funcao_sistema_proximo,
                vi.vaga_titulo%s,
                vi.data_abertura_vaga
            FROM historico_ordenado ho
            LEFT JOIN %I.%I sv ON TRIM(sv.status) = TRIM(ho.status)
            LEFT JOIN %I.%I sv_prox ON TRIM(sv_prox.status) = TRIM(ho.proximo_status)
            LEFT JOIN primeira_ocorrencia_calc poc ON TRIM(poc.requisicao) = TRIM(ho.requisicao) AND TRIM(poc.status) = TRIM(ho.status)
            LEFT JOIN vagas_info vi ON TRIM(vi.requisicao) = TRIM(ho.requisicao)
        ),
        proximo_valido AS (
            SELECT
                hcs.requisicao, hcs.created_at, hcs.status, hcs.sequencia_status, hcs.funcao_sistema,
                hcs.proximo_status, hcs.sequencia_proximo, hcs.funcao_sistema_proximo,
                CASE
                    WHEN hcs.funcao_sistema_proximo = ''Congelada'' THEN
                        (SELECT h2.status FROM historico_ordenado h2
                         LEFT JOIN %I.%I sv2 ON TRIM(sv2.status) = TRIM(h2.status)
                         WHERE TRIM(h2.requisicao) = TRIM(hcs.requisicao)
                           AND h2.created_at > (SELECT MIN(h3.created_at) FROM historico_ordenado h3
                               WHERE TRIM(h3.requisicao) = TRIM(hcs.requisicao)
                                 AND TRIM(h3.status) = TRIM(hcs.proximo_status)
                                 AND h3.created_at > hcs.created_at)
                           AND COALESCE(sv2."funcaoSistema", '''') <> ''Congelada''
                         ORDER BY h2.created_at LIMIT 1)
                    ELSE hcs.proximo_status
                END AS proximo_status_efetivo
            FROM historico_com_status hcs
        )
        SELECT
            %s,
            hcs.fim_fluxo, hcs.sequencia_status, hcs.responsavel_status, hcs.funcao_sistema,
            hcs.status_fim, hcs.primeira_ocorrencia, hcs.vaga_titulo%s,
            hcs.requisicao || '' - '' || COALESCE(hcs.vaga_titulo, '''') AS indice,
            CASE
                WHEN pv.proximo_status_efetivo IS NULL THEN NULL
                WHEN (SELECT sv_ef."funcaoSistema" FROM %I.%I sv_ef
                      WHERE TRIM(sv_ef.status) = TRIM(pv.proximo_status_efetivo)) IN (''Fechada'', ''Cancelada'') THEN ''Sim''
                WHEN (SELECT sv_ef."sequencia"::INTEGER FROM %I.%I sv_ef
                      WHERE TRIM(sv_ef.status) = TRIM(pv.proximo_status_efetivo)) > COALESCE(hcs.sequencia_status::INTEGER, 0) THEN ''Sim''
                WHEN (SELECT sv_ef."sequencia"::INTEGER FROM %I.%I sv_ef
                      WHERE TRIM(sv_ef.status) = TRIM(pv.proximo_status_efetivo)) < COALESCE(hcs.sequencia_status::INTEGER, 999999) THEN ''Nao''
                ELSE NULL
            END AS sucesso_status,
            hcs.data_abertura_vaga,
            CASE
                WHEN hcs.data_abertura_vaga IS NULL OR hcs.created_at IS NULL THEN NULL
                WHEN %L ILIKE ''%%uteis%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.data_abertura_vaga,
                        hcs.created_at::DATE - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I.%I f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (hcs.created_at::DATE - hcs.data_abertura_vaga)::INTEGER
            END AS dias_abertura_ate_status,
            CASE
                WHEN hcs.created_at IS NULL THEN NULL
                WHEN %L ILIKE ''%%uteis%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.created_at::DATE,
                        COALESCE(hcs.status_fim, CURRENT_DATE) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I.%I f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (COALESCE(hcs.status_fim, CURRENT_DATE) - hcs.created_at::DATE)::INTEGER
            END AS dias_no_status,
            CASE
                WHEN hcs.funcao_sistema = ''Fechada'' THEN
                    CASE WHEN hcs.created_at = (
                        SELECT MAX(h_uf.created_at)
                        FROM historico_base h_uf
                        LEFT JOIN %I.%I sv_uf ON TRIM(sv_uf.status) = TRIM(h_uf.status)
                        WHERE TRIM(h_uf.requisicao) = TRIM(hcs.requisicao)
                          AND sv_uf."funcaoSistema" = ''Fechada''
                    ) THEN ''Sim'' ELSE ''Nao'' END
                ELSE NULL
            END AS ultimo_filled
            %s
        FROM historico_com_status hcs
        LEFT JOIN proximo_valido pv ON TRIM(pv.requisicao) = TRIM(hcs.requisicao) AND pv.created_at = hcs.created_at AND TRIM(pv.status) = TRIM(hcs.status)
        ORDER BY hcs.requisicao, hcs.created_at
    ', p_schema, v_out_mv_historico,                           -- 1-2: DROP, CREATE
       p_schema, v_out_mv_historico,                           -- 3-4: CREATE name
       v_colunas_h,                                            -- 5: colunas dinamicas
       p_schema, v_tbl_historicoVagas,                         -- 6-7: USO_historicoVagas
       p_schema, v_out_mv_consumo_vagas,                       -- 8-9: mv_CONSUMO_vagas
       v_waiting_to_start_sql,                                 -- 10: UNION ALL
       v_geo_local_vagas_com_rn,                               -- 11: geo_local em vagas_com_rn
       p_schema, v_out_vw_vagas, v_formato_pg,                 -- 12-14: vw_vagas_nomeFixo, TO_DATE
       v_geo_local_vagas_info,                                 -- 15: geo_local em vagas_info
       v_formato_pg,                                           -- 16: TO_DATE
       v_status_fim_waiting_sql,                               -- 17: CASE para status_fim
       v_geo_local_hcs,                                        -- 18: geo_local em historico_com_status
       p_schema, v_tbl_statusVagas,                            -- 19-20: USO_statusVagas (sv)
       p_schema, v_tbl_statusVagas,                            -- 21-22: USO_statusVagas (sv_prox)
       p_schema, v_tbl_statusVagas,                            -- 23-24: USO_statusVagas (sv2)
       v_colunas_hcs,                                          -- 25: colunas dinamicas
       v_geo_local_select,                                     -- 26: geo_local no SELECT final
       p_schema, v_tbl_statusVagas,                            -- 27-28: USO_statusVagas (sucesso 1)
       p_schema, v_tbl_statusVagas,                            -- 29-30: USO_statusVagas (sucesso 2)
       p_schema, v_tbl_statusVagas,                            -- 31-32: USO_statusVagas (sucesso 3)
       v_tipo_contagem, p_schema, v_tbl_feriados, v_formato_pg, -- 33-36: dias_abertura_ate_status
       v_tipo_contagem, p_schema, v_tbl_feriados, v_formato_pg, -- 37-40: dias_no_status
       p_schema, v_tbl_statusVagas,                            -- 41-42: ultimo_filled
       v_dias_ate_inicio_sql || v_time_to_sql);                -- 43: dias_ate_inicio + time_to_*

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
-- SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cielo');
-- SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_cielo', 'V2');
-- ============================================================
