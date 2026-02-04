-- ============================================================
-- Funcao: public.dashboard_criar_mv_consumo_candidatos(p_schema, p_versao)
-- Cria a materialized view MV_CONSUMO_candidatos
-- ============================================================
-- VERSAO 2.0 - COM SUPORTE A VERSAO
-- Quando p_versao = 'V2': tabelas fonte V2_USO_*, objetos V2_MV_*, V2_vw_*
-- Quando p_versao IS NULL: comportamento identico ao anterior (sem prefixo)
-- ============================================================
-- Expande o campo operacao_posicoesconsideradas em multiplas linhas
-- Uma linha para cada requisicao considerada pelo candidato
-- ============================================================

DROP FUNCTION IF EXISTS public.dashboard_criar_mv_consumo_candidatos(TEXT, TEXT);
DROP FUNCTION IF EXISTS criar_mv_consumo_candidatos(TEXT);

CREATE OR REPLACE FUNCTION public.dashboard_criar_mv_consumo_candidatos(p_schema TEXT, p_versao TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
    v_prefixo TEXT;
    -- Objetos de saida e cross-refs (versionados)
    v_out_vw_candidatos TEXT;
    v_out_mv_candidatos TEXT;
    -- Variaveis de trabalho
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_colunas TEXT := '';
    v_colunas_select TEXT := '';
    v_col RECORD;
    v_formato TEXT;
BEGIN
    -- ============================================================
    -- Logica de prefixo
    -- ============================================================
    IF p_versao IS NOT NULL AND TRIM(p_versao) <> '' THEN
        v_prefixo := TRIM(p_versao) || '_';
    ELSE
        v_prefixo := '';
    END IF;

    -- Objetos de saida e cross-refs
    v_out_vw_candidatos := v_prefixo || 'vw_candidatos_nomeFixo';
    v_out_mv_candidatos := v_prefixo || 'MV_CONSUMO_candidatos';

    IF v_prefixo <> '' THEN
        v_resultado := v_resultado || 'Versao: ' || p_versao || ' (prefixo: ' || v_prefixo || ')' || E'\n';
    END IF;

    -- ============================================================
    -- Detectar formato baseado no schema
    -- ============================================================
    IF p_schema = 'RPO_cielo' THEN
        v_formato := 'cielo';
    ELSIF p_schema = 'RPO_semper_laser' THEN
        v_formato := 'semper_laser';
    ELSE
        EXECUTE format(
            'SELECT CASE
                WHEN EXISTS (
                    SELECT 1 FROM %I.%I
                    WHERE operacao_posicoesconsideradas LIKE ''%%[%%]%%''
                    LIMIT 1
                ) THEN ''cielo''
                ELSE ''semper_laser''
            END',
            p_schema, v_out_vw_candidatos
        ) INTO v_formato;
    END IF;

    v_resultado := v_resultado || 'Formato detectado: ' || v_formato || E'\n';

    -- ============================================================
    -- Buscar todas as colunas da view vw_candidatos_nomeFixo
    -- ============================================================
    FOR v_col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = p_schema
          AND table_name = v_out_vw_candidatos
        ORDER BY ordinal_position
    LOOP
        IF v_colunas <> '' THEN
            v_colunas := v_colunas || ', ';
            v_colunas_select := v_colunas_select || ',' || E'\n            ';
        END IF;
        v_colunas := v_colunas || format('%I', v_col.column_name);
        IF v_col.column_name IN ('status_candidato') AND v_prefixo <> '' THEN
            v_colunas_select := v_colunas_select || format('UPPER(LEFT(TRIM(c.%I), 1)) || LOWER(SUBSTRING(TRIM(c.%I) FROM 2)) AS %I', v_col.column_name, v_col.column_name, v_col.column_name);
        ELSE
            v_colunas_select := v_colunas_select || format('c.%I', v_col.column_name);
        END IF;
    END LOOP;

    v_resultado := v_resultado || 'Colunas encontradas em ' || v_out_vw_candidatos || E'\n';

    -- ============================================================
    -- Criar a MV baseado no formato
    -- ============================================================
    IF v_formato = 'cielo' THEN
        v_sql := format('
            DROP MATERIALIZED VIEW IF EXISTS %I.%I;

            CREATE MATERIALIZED VIEW %I.%I AS
            WITH candidatos_com_posicoes AS (
                SELECT
                    %s,
                    UNNEST(
                        STRING_TO_ARRAY(
                            operacao_posicoesconsideradas,
                            '', [''
                        )
                    ) AS posicao_raw
                FROM %I.%I c
                WHERE operacao_posicoesconsideradas IS NOT NULL
                  AND TRIM(operacao_posicoesconsideradas) <> ''''
            ),
            posicoes_extraidas AS (
                SELECT
                    %s,
                    posicao_raw,
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(posicao_raw, ''^\['', ''''),
                            ''\].*$'', ''''
                        )
                    ) AS requisicao_extraida
                FROM candidatos_com_posicoes c
            )
            SELECT
                %s,
                requisicao_extraida AS requisicao
            FROM posicoes_extraidas c
            WHERE requisicao_extraida IS NOT NULL
              AND TRIM(requisicao_extraida) <> ''''
              AND requisicao_extraida ~ ''^\d+$''
            ORDER BY requisicao_extraida, c.id_candidato
        ', p_schema, v_out_mv_candidatos,
           p_schema, v_out_mv_candidatos,
           v_colunas_select, p_schema, v_out_vw_candidatos,
           v_colunas_select,
           v_colunas_select);
    ELSE
        v_sql := format('
            DROP MATERIALIZED VIEW IF EXISTS %I.%I;

            CREATE MATERIALIZED VIEW %I.%I AS
            WITH candidatos_com_posicoes AS (
                SELECT
                    %s,
                    UNNEST(
                        STRING_TO_ARRAY(
                            operacao_posicoesconsideradas,
                            '', ''
                        )
                    ) AS posicao_raw
                FROM %I.%I c
                WHERE operacao_posicoesconsideradas IS NOT NULL
                  AND TRIM(operacao_posicoesconsideradas) <> ''''
            ),
            posicoes_filtradas AS (
                SELECT
                    %s,
                    posicao_raw
                FROM candidatos_com_posicoes c
                WHERE posicao_raw LIKE ''%%--- %%''
            ),
            posicoes_extraidas AS (
                SELECT
                    %s,
                    posicao_raw,
                    TRIM(
                        REVERSE(
                            SPLIT_PART(
                                REVERSE(posicao_raw),
                                '' ---'',
                                1
                            )
                        )
                    ) AS requisicao_extraida
                FROM posicoes_filtradas c
            )
            SELECT
                %s,
                requisicao_extraida AS requisicao
            FROM posicoes_extraidas c
            WHERE requisicao_extraida IS NOT NULL
              AND TRIM(requisicao_extraida) <> ''''
              AND requisicao_extraida ~ ''^\d+$''
            ORDER BY requisicao_extraida, c.id_candidato
        ', p_schema, v_out_mv_candidatos,
           p_schema, v_out_mv_candidatos,
           v_colunas_select, p_schema, v_out_vw_candidatos,
           v_colunas_select,
           v_colunas_select,
           v_colunas_select);
    END IF;

    EXECUTE v_sql;

    -- Contar registros
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema, v_out_mv_candidatos) INTO v_count;
    v_resultado := v_resultado || 'Materialized view ' || v_out_mv_candidatos || ' criada com ' || v_count || ' registros' || E'\n';

    -- GRANT: Permissoes para rpo_user
    EXECUTE format('GRANT SELECT ON %I.%I TO rpo_user', p_schema, v_out_mv_candidatos);
    v_resultado := v_resultado || 'Permissoes concedidas para rpo_user';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT dashboard_criar_mv_consumo_candidatos('RPO_cielo');
-- SELECT dashboard_criar_mv_consumo_candidatos('RPO_cielo', 'V2');
--
-- Para atualizar a materialized view:
-- REFRESH MATERIALIZED VIEW "RPO_cielo"."MV_CONSUMO_candidatos";
-- REFRESH MATERIALIZED VIEW "RPO_cielo"."V2_MV_CONSUMO_candidatos";
-- ============================================================
