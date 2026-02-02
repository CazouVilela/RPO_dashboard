-- ============================================================
-- Função: criar_mv_consumo_candidatos(schema_name)
-- Cria a materialized view MV_CONSUMO_candidatos
-- ============================================================
-- VERSÃO 1.0 - DINÂMICA
-- Expande o campo operacao_posicoesconsideradas em múltiplas linhas
-- Uma linha para cada requisição considerada pelo candidato
-- ============================================================
-- Formatos suportados:
-- - cielo: [REQUISICAO] - TITULO (local) --- <STATUS>
-- - semper_laser: TITULO --- (loja) --- REQUISICAO
-- ============================================================

CREATE OR REPLACE FUNCTION criar_mv_consumo_candidatos(p_schema TEXT)
RETURNS TEXT AS $$
DECLARE
    v_sql TEXT;
    v_resultado TEXT := '';
    v_count INTEGER;
    v_colunas TEXT := '';
    v_colunas_select TEXT := '';
    v_col RECORD;
    v_formato TEXT;
BEGIN
    -- ============================================================
    -- Detectar formato baseado no schema
    -- ============================================================
    IF p_schema = 'RPO_cielo' THEN
        v_formato := 'cielo';
    ELSIF p_schema = 'RPO_semper_laser' THEN
        v_formato := 'semper_laser';
    ELSE
        -- Tentar detectar automaticamente pelo conteúdo
        EXECUTE format(
            'SELECT CASE
                WHEN EXISTS (
                    SELECT 1 FROM %I."vw_candidatos_nomeFixo"
                    WHERE operacao_posicoesconsideradas LIKE ''%%[%%]%%''
                    LIMIT 1
                ) THEN ''cielo''
                ELSE ''semper_laser''
            END',
            p_schema
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
          AND table_name = 'vw_candidatos_nomeFixo'
        ORDER BY ordinal_position
    LOOP
        IF v_colunas <> '' THEN
            v_colunas := v_colunas || ', ';
            v_colunas_select := v_colunas_select || ',' || E'\n            ';
        END IF;
        v_colunas := v_colunas || format('%I', v_col.column_name);
        v_colunas_select := v_colunas_select || format('c.%I', v_col.column_name);
    END LOOP;

    v_resultado := v_resultado || 'Colunas encontradas em vw_candidatos_nomeFixo' || E'\n';

    -- ============================================================
    -- Criar a MV baseado no formato
    -- ============================================================
    IF v_formato = 'cielo' THEN
        -- Formato cielo: [REQUISICAO] - TITULO (local) --- <STATUS>
        -- Separador: ", [" entre posições
        v_sql := format('
            DROP MATERIALIZED VIEW IF EXISTS %I."MV_CONSUMO_candidatos";

            CREATE MATERIALIZED VIEW %I."MV_CONSUMO_candidatos" AS
            WITH candidatos_com_posicoes AS (
                SELECT
                    %s,
                    -- Extrai cada posição separada por ", ["
                    UNNEST(
                        STRING_TO_ARRAY(
                            operacao_posicoesconsideradas,
                            '', [''
                        )
                    ) AS posicao_raw
                FROM %I."vw_candidatos_nomeFixo" c
                WHERE operacao_posicoesconsideradas IS NOT NULL
                  AND TRIM(operacao_posicoesconsideradas) <> ''''
            ),
            posicoes_extraidas AS (
                SELECT
                    %s,
                    posicao_raw,
                    -- Extrai a requisição dos colchetes
                    -- Remove [ do início se existir e ] do final
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
        ', p_schema, p_schema,
           v_colunas_select, p_schema,
           v_colunas_select,
           v_colunas_select);
    ELSE
        -- Formato semper_laser: TITULO --- (loja) --- REQUISICAO
        -- Separador: ", " entre posições
        -- Requisição está no final após "--- "
        v_sql := format('
            DROP MATERIALIZED VIEW IF EXISTS %I."MV_CONSUMO_candidatos";

            CREATE MATERIALIZED VIEW %I."MV_CONSUMO_candidatos" AS
            WITH candidatos_com_posicoes AS (
                SELECT
                    %s,
                    -- Divide por ", " para separar cada posição
                    UNNEST(
                        STRING_TO_ARRAY(
                            operacao_posicoesconsideradas,
                            '', ''
                        )
                    ) AS posicao_raw
                FROM %I."vw_candidatos_nomeFixo" c
                WHERE operacao_posicoesconsideradas IS NOT NULL
                  AND TRIM(operacao_posicoesconsideradas) <> ''''
            ),
            posicoes_filtradas AS (
                -- Filtra apenas as partes que contêm " --- " (são posições completas)
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
                    -- Extrai a requisição (última parte após "--- ")
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
        ', p_schema, p_schema,
           v_colunas_select, p_schema,
           v_colunas_select,
           v_colunas_select,
           v_colunas_select);
    END IF;

    EXECUTE v_sql;

    -- Contar registros
    EXECUTE format('SELECT COUNT(*) FROM %I."MV_CONSUMO_candidatos"', p_schema) INTO v_count;
    v_resultado := v_resultado || 'Materialized view MV_CONSUMO_candidatos criada com ' || v_count || ' registros';

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Exemplo de uso:
-- SELECT criar_mv_consumo_candidatos('RPO_cielo');
-- SELECT criar_mv_consumo_candidatos('RPO_semper_laser');
--
-- Para atualizar a materialized view:
-- REFRESH MATERIALIZED VIEW "RPO_cielo"."MV_CONSUMO_candidatos";
-- ============================================================
