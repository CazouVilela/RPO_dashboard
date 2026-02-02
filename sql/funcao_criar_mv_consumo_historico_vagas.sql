-- ============================================================
-- Função: criar_mv_consumo_historico_vagas(schema_name)
-- Cria a materialized view MV_CONSUMO_historicoVagas
-- ============================================================
-- VERSÃO 3.7 - COLUNAS TOTALMENTE DINÂMICAS
-- As colunas são lidas dinamicamente da tabela USO_historicoVagas
-- Funciona com estruturas diferentes entre schemas
-- v3.6: Colunas do historico_base geradas dinamicamente
--       "waiting to start" aplicado APENAS para RPO_semper_laser
-- v3.7: Adicionado geo_local (location_store) vindo de vw_vagas_nomeFixo
-- ============================================================
-- Contém todos os campos de USO_historicoVagas mais:
-- - fimFluxo, sequencia, responsavel, funcaoSistema (de USO_statusVagas)
-- - status_fim: data do próximo registro da mesma requisição
-- - primeira_ocorrencia: sim/não se é a primeira vez deste status para a requisição
-- - vaga_titulo: título da vaga (de USO_[vagas] via requisicao)
-- - geo_local: location/store da vaga (de vw_vagas_nomeFixo via requisicao)
-- - indice: concatenação de requisicao e vaga_titulo (formato: "requisicao - vaga_titulo")
-- - sucesso_status: sim/não baseado na sequência do próximo status
-- - data_abertura_vaga: data de abertura da vaga (de USO_[vagas] via requisicao)
-- - dias_abertura_ate_status: dias entre data_abertura_vaga e created_at
-- - dias_no_status: dias entre created_at e status_fim (ou hoje)
-- ============================================================

CREATE OR REPLACE FUNCTION criar_mv_consumo_historico_vagas(p_schema TEXT)
RETURNS TEXT AS $$
DECLARE
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_col RECORD;
    v_tabela_vagas TEXT;
    v_tipo_contagem TEXT;
    v_formato_datas TEXT;
    v_formato_pg TEXT;
    -- Colunas dinâmicas
    v_colunas_h TEXT := '';        -- h.col1, h.col2, ...
    v_colunas_hcs TEXT := '';      -- hcs.col1, hcs.col2, ...
    v_colunas_union TEXT := '';    -- -1 AS id, ... NULL AS col, ...
    -- waiting to start e dias_ate_inicio (apenas para semper_laser)
    v_has_waiting_to_start BOOLEAN := FALSE;
    v_waiting_to_start_sql TEXT := '';
    v_status_fim_waiting_sql TEXT := '';
    v_dias_ate_inicio_sql TEXT := '';
    -- geo_local (verificar se existe na view de vagas)
    v_has_geo_local BOOLEAN := FALSE;
    v_geo_local_select TEXT := '';
    v_geo_local_vagas_com_rn TEXT := '';
    v_geo_local_vagas_info TEXT := '';
    v_geo_local_hcs TEXT := '';
BEGIN
    -- ============================================================
    -- Buscar configurações do dashboard
    -- ============================================================

    -- Nome da tabela de vagas
    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Nome da aba de controle vagas'
    ) INTO v_tabela_vagas;
    v_tabela_vagas := 'USO_' || REPLACE(v_tabela_vagas, ' ', '_');

    -- Tipo de contagem de dias
    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Tipo da contagem de dias'
    ) INTO v_tipo_contagem;

    -- Formato das datas
    EXECUTE format(
        'SELECT "Valor" FROM %I."USO_configuracoesGerais" WHERE "Configuracao" = %L',
        p_schema, 'Formato das datas'
    ) INTO v_formato_datas;

    -- Definir formato PostgreSQL baseado na configuração
    IF LOWER(COALESCE(v_formato_datas, 'americano')) = 'brasileiro' THEN
        v_formato_pg := 'DD/MM/YYYY';
    ELSE
        v_formato_pg := 'MM/DD/YYYY';
    END IF;

    v_resultado := v_resultado || 'Tabela vagas: ' || v_tabela_vagas || E'\n';
    v_resultado := v_resultado || 'Tipo contagem: ' || COALESCE(v_tipo_contagem, 'não definido') || E'\n';
    v_resultado := v_resultado || 'Formato datas: ' || COALESCE(v_formato_datas, 'americano') || ' (' || v_formato_pg || ')' || E'\n';

    -- ============================================================
    -- Verificar se geo_local existe na view de vagas
    -- ============================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = 'vw_vagas_nomeFixo'
          AND column_name = 'geo_local'
    ) INTO v_has_geo_local;

    IF v_has_geo_local THEN
        v_geo_local_vagas_com_rn := ', v.geo_local';
        v_geo_local_vagas_info := ', geo_local';
        v_geo_local_hcs := ', vi.geo_local';
        v_geo_local_select := ', hcs.geo_local';
        v_resultado := v_resultado || 'geo_local: INCLUÍDO' || E'\n';
    ELSE
        v_geo_local_vagas_com_rn := '';
        v_geo_local_vagas_info := '';
        v_geo_local_hcs := '';
        v_geo_local_select := ', NULL::TEXT AS geo_local';
        v_resultado := v_resultado || 'geo_local: NÃO EXISTE (NULL)' || E'\n';
    END IF;

    -- ============================================================
    -- Gerar colunas dinamicamente de USO_historicoVagas
    -- ============================================================
    FOR v_col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = 'USO_historicoVagas'
        ORDER BY ordinal_position
    LOOP
        -- Colunas para SELECT h.* (historico_base)
        IF v_colunas_h <> '' THEN
            v_colunas_h := v_colunas_h || ', ';
            v_colunas_hcs := v_colunas_hcs || ', ';
            v_colunas_union := v_colunas_union || ', ';
        END IF;
        v_colunas_h := v_colunas_h || format('h.%I', v_col.column_name);
        v_colunas_hcs := v_colunas_hcs || format('hcs.%I', v_col.column_name);

        -- Colunas para UNION ALL (waiting to start)
        -- created_at usa data do Filled (não Offer_accepted_) para que dias_no_status = Filled → Start_Date
        CASE v_col.column_name
            WHEN 'id' THEN v_colunas_union := v_colunas_union || '-1 AS id';
            WHEN 'requisicao' THEN v_colunas_union := v_colunas_union || 'TRIM(vg."ID_Position_ADP") AS requisicao';
            WHEN 'status' THEN v_colunas_union := v_colunas_union || '''waiting to start'' AS status';
            WHEN 'created_at' THEN v_colunas_union := v_colunas_union || format('(SELECT h.created_at FROM %I."USO_historicoVagas" h WHERE TRIM(h.requisicao) = TRIM(vg."ID_Position_ADP") AND h.status = ''Filled'' ORDER BY h.created_at DESC LIMIT 1) AS created_at', p_schema);
            WHEN 'alterado_por' THEN v_colunas_union := v_colunas_union || '''gerado_mv'' AS alterado_por';
            WHEN 'updated_at' THEN v_colunas_union := v_colunas_union || 'CURRENT_TIMESTAMP AS updated_at';
            WHEN 'version' THEN v_colunas_union := v_colunas_union || '1 AS version';
            WHEN 'selecionado_nome' THEN v_colunas_union := v_colunas_union || 'vg."Selected_Candidate__Full_name_" AS selecionado_nome';
            ELSE v_colunas_union := v_colunas_union || format('NULL::%s AS %I',
                (SELECT data_type FROM information_schema.columns
                 WHERE table_schema = p_schema AND table_name = 'USO_historicoVagas' AND column_name = v_col.column_name),
                v_col.column_name);
        END CASE;
    END LOOP;

    v_resultado := v_resultado || 'Colunas de USO_historicoVagas geradas dinamicamente' || E'\n';

    -- ============================================================
    -- waiting to start: APENAS para RPO_semper_laser
    -- ============================================================
    IF p_schema = 'RPO_semper_laser' THEN
        v_has_waiting_to_start := TRUE;
        v_resultado := v_resultado || 'waiting to start: ATIVADO (semper_laser)' || E'\n';

        v_waiting_to_start_sql := format('
            UNION ALL

            -- Gera registros de "waiting to start" dinamicamente
            -- Para todas as vagas que têm Filled no histórico e Start_Date preenchido
            -- Usa subquery com ROW_NUMBER para garantir 1 registro por requisição
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
                  SELECT 1 FROM %I."mv_CONSUMO_vagas" mv
                  WHERE TRIM(mv.requisicao) = TRIM(vg."ID_Position_ADP")
              )
              -- Verifica se existe pelo menos um registro Filled no histórico
              AND EXISTS (
                  SELECT 1 FROM %I."USO_historicoVagas" h
                  WHERE TRIM(h.requisicao) = TRIM(vg."ID_Position_ADP")
                    AND h.status = ''Filled''
              )
        ', v_colunas_union, p_schema, v_tabela_vagas, p_schema, p_schema);

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

        -- dias_ate_inicio: dias entre data_abertura_vaga e Start_Date__Admission_
        v_dias_ate_inicio_sql := format(',
            CASE
                WHEN hcs.data_abertura_vaga IS NULL THEN NULL
                WHEN (SELECT vg."Start_Date__Admission_" FROM %I.%I vg WHERE TRIM(vg."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1) IS NULL THEN NULL
                WHEN TRIM((SELECT vg."Start_Date__Admission_" FROM %I.%I vg WHERE TRIM(vg."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1)) = '''' THEN NULL
                WHEN (SELECT vg."Start_Date__Admission_" FROM %I.%I vg WHERE TRIM(vg."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1) !~ ''^\d{1,2}/\d{1,2}/\d{4}$'' THEN NULL
                WHEN %L ILIKE ''%%%%úteis%%%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.data_abertura_vaga,
                        TO_DATE((SELECT vg2."Start_Date__Admission_" FROM %I.%I vg2 WHERE TRIM(vg2."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1), %L) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I."USO_feriados" f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (
                    TO_DATE((SELECT vg3."Start_Date__Admission_" FROM %I.%I vg3 WHERE TRIM(vg3."ID_Position_ADP") = TRIM(hcs.requisicao) LIMIT 1), %L) - hcs.data_abertura_vaga
                )::INTEGER
            END AS dias_ate_inicio
        ', p_schema, v_tabela_vagas,           -- 1-2: subquery para verificar NULL
           p_schema, v_tabela_vagas,           -- 3-4: subquery para verificar vazio
           p_schema, v_tabela_vagas,           -- 5-6: subquery para verificar regex
           v_tipo_contagem,                    -- 7: tipo contagem
           p_schema, v_tabela_vagas, v_formato_pg,  -- 8-10: subquery para TO_DATE no generate_series
           p_schema, v_formato_pg,             -- 11-12: feriados schema e formato
           p_schema, v_tabela_vagas, v_formato_pg); -- 13-15: subquery para TO_DATE no ELSE
    ELSE
        v_resultado := v_resultado || 'waiting to start: DESATIVADO (não é semper_laser)' || E'\n';
        v_waiting_to_start_sql := '';
        v_status_fim_waiting_sql := 'WHEN FALSE THEN NULL';
        v_dias_ate_inicio_sql := ',
            NULL::INTEGER AS dias_ate_inicio';
    END IF;

    -- ============================================================
    -- Construir SQL principal
    -- ============================================================
    v_sql := format('
        DROP MATERIALIZED VIEW IF EXISTS %I."MV_CONSUMO_historicoVagas";

        CREATE MATERIALIZED VIEW %I."MV_CONSUMO_historicoVagas" AS
        WITH historico_base AS (
            SELECT %s
            FROM %I."USO_historicoVagas" h
            WHERE EXISTS (
                SELECT 1 FROM %I."mv_CONSUMO_vagas" mv
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
            FROM %I."vw_vagas_nomeFixo" v
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
                -- status_fim:
                -- 1. waiting to start: usa Start_Date__Admission_ (semper_laser)
                -- 2. fimFluxo=Sim: data_final = data_inicio (0 dias)
                -- 3. outros: proxima_data ou hoje
                CASE
                    %s
                    WHEN sv."fimFluxo" = ''Sim'' THEN ho.created_at::DATE
                    ELSE COALESCE(ho.proxima_data::DATE, CURRENT_DATE)
                END AS status_fim,
                CASE WHEN ho.created_at = poc.primeira_data THEN ''Sim'' ELSE ''Não'' END AS primeira_ocorrencia,
                sv_prox."sequencia" AS sequencia_proximo,
                sv_prox."funcaoSistema" AS funcao_sistema_proximo,
                vi.vaga_titulo%s,
                vi.data_abertura_vaga
            FROM historico_ordenado ho
            LEFT JOIN %I."USO_statusVagas" sv ON TRIM(sv.status) = TRIM(ho.status)
            LEFT JOIN %I."USO_statusVagas" sv_prox ON TRIM(sv_prox.status) = TRIM(ho.proximo_status)
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
                         LEFT JOIN %I."USO_statusVagas" sv2 ON TRIM(sv2.status) = TRIM(h2.status)
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
                WHEN (SELECT sv_ef."funcaoSistema" FROM %I."USO_statusVagas" sv_ef
                      WHERE TRIM(sv_ef.status) = TRIM(pv.proximo_status_efetivo)) IN (''Fechada'', ''Cancelada'') THEN ''Sim''
                WHEN (SELECT sv_ef."sequencia"::INTEGER FROM %I."USO_statusVagas" sv_ef
                      WHERE TRIM(sv_ef.status) = TRIM(pv.proximo_status_efetivo)) > COALESCE(hcs.sequencia_status::INTEGER, 0) THEN ''Sim''
                WHEN (SELECT sv_ef."sequencia"::INTEGER FROM %I."USO_statusVagas" sv_ef
                      WHERE TRIM(sv_ef.status) = TRIM(pv.proximo_status_efetivo)) < COALESCE(hcs.sequencia_status::INTEGER, 999999) THEN ''Não''
                ELSE NULL
            END AS sucesso_status,
            hcs.data_abertura_vaga,
            -- dias_abertura_ate_status: dias entre data_abertura_vaga e created_at (inicio do status)
            -- Lógica: COUNT de dias entre [data_inicial, data_final) - não inclui data_final
            CASE
                WHEN hcs.data_abertura_vaga IS NULL OR hcs.created_at IS NULL THEN NULL
                WHEN %L ILIKE ''%%úteis%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.data_abertura_vaga,
                        hcs.created_at::DATE - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I."USO_feriados" f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (hcs.created_at::DATE - hcs.data_abertura_vaga)::INTEGER
            END AS dias_abertura_ate_status,
            -- dias_no_status: dias entre created_at (inicio) e status_fim (ou hoje)
            -- Lógica: COUNT de dias entre [data_inicial, data_final) - não inclui data_final
            CASE
                WHEN hcs.created_at IS NULL THEN NULL
                WHEN %L ILIKE ''%%úteis%%'' THEN (
                    SELECT COUNT(*)::INTEGER FROM generate_series(
                        hcs.created_at::DATE,
                        COALESCE(hcs.status_fim, CURRENT_DATE) - INTERVAL ''1 day'',
                        ''1 day''::INTERVAL
                    ) AS d(dt)
                    WHERE EXTRACT(DOW FROM d.dt) NOT IN (0, 6)
                      AND NOT EXISTS (SELECT 1 FROM %I."USO_feriados" f WHERE TO_DATE(f."Data", %L) = d.dt::DATE))
                ELSE (COALESCE(hcs.status_fim, CURRENT_DATE) - hcs.created_at::DATE)::INTEGER
            END AS dias_no_status,
            -- ultimo_filled: indica se é o último registro Filled da requisição
            CASE
                WHEN hcs.funcao_sistema = ''Fechada'' THEN
                    CASE WHEN hcs.created_at = (
                        SELECT MAX(h_uf.created_at)
                        FROM historico_base h_uf
                        LEFT JOIN %I."USO_statusVagas" sv_uf ON TRIM(sv_uf.status) = TRIM(h_uf.status)
                        WHERE TRIM(h_uf.requisicao) = TRIM(hcs.requisicao)
                          AND sv_uf."funcaoSistema" = ''Fechada''
                    ) THEN ''Sim'' ELSE ''Não'' END
                ELSE NULL
            END AS ultimo_filled
            %s
        FROM historico_com_status hcs
        LEFT JOIN proximo_valido pv ON TRIM(pv.requisicao) = TRIM(hcs.requisicao) AND pv.created_at = hcs.created_at AND TRIM(pv.status) = TRIM(hcs.status)
        ORDER BY hcs.requisicao, hcs.created_at
    ', p_schema, p_schema,                             -- 1-2: DROP, CREATE
       v_colunas_h,                                    -- 3: colunas dinâmicas (h.col1, h.col2, ...)
       p_schema, p_schema,                             -- 4-5: USO_historicoVagas, mv_CONSUMO_vagas
       v_waiting_to_start_sql,                         -- 6: UNION ALL (apenas semper_laser)
       v_geo_local_vagas_com_rn,                       -- 7: geo_local em vagas_com_rn (condicional)
       p_schema, v_formato_pg,                         -- 8-9: vw_vagas_nomeFixo, TO_DATE
       v_geo_local_vagas_info,                         -- 10: geo_local em vagas_info (condicional)
       v_formato_pg,                                   -- 11: TO_DATE
       v_status_fim_waiting_sql,                       -- 12: CASE para status_fim
       v_geo_local_hcs,                                -- 13: geo_local em historico_com_status (condicional)
       p_schema, p_schema, p_schema,                   -- 14-16: USO_statusVagas (sv, sv_prox, sv2)
       v_colunas_hcs,                                  -- 17: colunas dinâmicas (hcs.col1, ...)
       v_geo_local_select,                             -- 18: geo_local no SELECT final (condicional)
       p_schema, p_schema, p_schema,                   -- 19-21: USO_statusVagas (sucesso_status)
       v_tipo_contagem, p_schema, v_formato_pg,        -- 22-24: tipo_contagem, feriados schema, feriados formato (dias_abertura_ate_status)
       v_tipo_contagem, p_schema, v_formato_pg,        -- 25-27: tipo_contagem, feriados schema, feriados formato (dias_no_status)
       p_schema,                                       -- 28: USO_statusVagas (ultimo_filled)
       v_dias_ate_inicio_sql);                         -- 29: dias_ate_inicio (condicional)

    EXECUTE v_sql;

    EXECUTE format('SELECT COUNT(*) FROM %I."MV_CONSUMO_historicoVagas"', p_schema) INTO v_count;
    v_resultado := v_resultado || 'MV_CONSUMO_historicoVagas criada com ' || v_count || ' registros' || E'\n';

    -- GRANT: Permissões para rpo_user
    EXECUTE format('GRANT SELECT ON %I."MV_CONSUMO_historicoVagas" TO rpo_user', p_schema);
    v_resultado := v_resultado || 'Permissões concedidas para rpo_user';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT criar_mv_consumo_historico_vagas('RPO_cielo');
-- SELECT criar_mv_consumo_historico_vagas('RPO_semper_laser');
-- ============================================================
