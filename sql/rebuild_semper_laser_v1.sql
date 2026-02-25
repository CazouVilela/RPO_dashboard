-- =============================================================================
-- Rebuild Dashboard V1 - Semper Laser
-- Recria tabelas USO, views e materialized views a partir dos dados RAW atualizados
-- Deduplica dados Airbyte (multiplas geracoes) usando apenas a geracao mais recente
-- Executar: psql -h /tmp -p 15432 -U cazouvilela -d HUB -f sql/rebuild_semper_laser_v1.sql
-- =============================================================================

BEGIN;

-- =========================================================
-- PASSO 0: Dropar MVs e Views existentes
-- =========================================================
DROP MATERIALIZED VIEW IF EXISTS "RPO_semper_laser"."MV_CONSUMO_candidatos" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_semper_laser"."MV_CONSUMO_historicoCandidatos" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_semper_laser"."MV_CONSUMO_historicoVagas" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_semper_laser"."MV_CONSUMO_ERROS_VAGAS" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_semper_laser"."MV_CONSUMO_vagas" CASCADE;
DROP MATERIALIZED VIEW IF EXISTS "RPO_semper_laser"."MV_SLAs" CASCADE;
DROP VIEW IF EXISTS "RPO_semper_laser"."vw_vagas_nomeFixo" CASCADE;
DROP VIEW IF EXISTS "RPO_semper_laser"."vw_candidatos_nomeFixo" CASCADE;

-- =========================================================
-- PASSO 1: Recriar tabelas USO a partir das RAW atualizadas
-- (NAO recria USO_historicoVagas, USO_historicoCandidatos, USO_Listas)
-- Filtra pela geracao mais recente do Airbyte para evitar duplicatas
-- =========================================================

-- USO_configuracoesGerais
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_configuracoesGerais" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_configuracoesGerais" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_configuracoesGerais"
  WHERE _airbyte_generation_id = (
    SELECT _airbyte_generation_id FROM "RPO_semper_laser"."RAW_AIRBYTE_configuracoesGerais"
    ORDER BY _airbyte_extracted_at DESC LIMIT 1
  );

-- USO_dicionarioVagas (RAW_dicionarioVagas nao tem _airbyte_generation_id, copia direta)
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_dicionarioVagas" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_dicionarioVagas" AS
  SELECT * FROM "RPO_semper_laser"."RAW_dicionarioVagas";

-- Corrigir nomeAmigavel para colunas Airbyte com parenteses/caracteres especiais
UPDATE "RPO_semper_laser"."USO_dicionarioVagas" SET "nomeAmigavel" = 'Start_Date__Admission_' WHERE "nomeFixo" = 'data_admissao';
UPDATE "RPO_semper_laser"."USO_dicionarioVagas" SET "nomeAmigavel" = 'Selected_Candidate__Full_name_' WHERE "nomeFixo" = 'selecionado_nome';
UPDATE "RPO_semper_laser"."USO_dicionarioVagas" SET "nomeAmigavel" = 'Hiring_Manager__SSD_or_SM_' WHERE "nomeFixo" = 'gestao_gestor';
UPDATE "RPO_semper_laser"."USO_dicionarioVagas" SET "nomeAmigavel" = 'Area_Manager__when_applicable_' WHERE "nomeFixo" = 'gestao_regional';
UPDATE "RPO_semper_laser"."USO_dicionarioVagas" SET "nomeAmigavel" = 'No_Vacancies' WHERE "nomeFixo" = 'vagas_quantidade';

-- USO_dicionarioCandidatos (RAW_dicionarioCandidatos nao tem _airbyte_generation_id, copia direta)
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_dicionarioCandidatos" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_dicionarioCandidatos" AS
  SELECT * FROM "RPO_semper_laser"."RAW_dicionarioCandidatos";

-- Corrigir nomeAmigavel para coluna Airbyte com parenteses
UPDATE "RPO_semper_laser"."USO_dicionarioCandidatos" SET "nomeAmigavel" = 'Source__Indeed_ADP__Referral_Etc__' WHERE "nomeFixo" = 'candidato_origem';

-- USO_statusVagas
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_statusVagas" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_statusVagas" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_statusVagas"
  WHERE _airbyte_generation_id = (
    SELECT _airbyte_generation_id FROM "RPO_semper_laser"."RAW_AIRBYTE_statusVagas"
    ORDER BY _airbyte_extracted_at DESC LIMIT 1
  );

-- USO_statusCandidatos
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_statusCandidatos" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_statusCandidatos" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_statusCandidatos"
  WHERE _airbyte_generation_id = (
    SELECT _airbyte_generation_id FROM "RPO_semper_laser"."RAW_AIRBYTE_statusCandidatos"
    ORDER BY _airbyte_extracted_at DESC LIMIT 1
  );

-- USO_feriados
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_feriados" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_feriados" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_feriados"
  WHERE _airbyte_generation_id = (
    SELECT _airbyte_generation_id FROM "RPO_semper_laser"."RAW_AIRBYTE_feriados"
    ORDER BY _airbyte_extracted_at DESC LIMIT 1
  );

-- Corrigir serial number do Excel em feriados (45778 = 05/01/2025 Dia do Trabalho)
UPDATE "RPO_semper_laser"."USO_feriados"
  SET "Data" = TO_CHAR(DATE '1899-12-30' + "Data"::INTEGER, 'MM/DD/YYYY')
  WHERE "Data" ~ '^\d{5,}$';

-- USO_Job_Openings_Control
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_Job_Openings_Control" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_Job_Openings_Control" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_Job_Openings_Control"
  WHERE _airbyte_generation_id = (
    SELECT _airbyte_generation_id FROM "RPO_semper_laser"."RAW_AIRBYTE_Job_Openings_Control"
    ORDER BY _airbyte_extracted_at DESC LIMIT 1
  );

-- USO_Candidates_Control
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_Candidates_Control" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_Candidates_Control" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_Candidates_Control"
  WHERE _airbyte_generation_id = (
    SELECT _airbyte_generation_id FROM "RPO_semper_laser"."RAW_AIRBYTE_Candidates_Control"
    ORDER BY _airbyte_extracted_at DESC LIMIT 1
  );

-- USO_FALLBACK_historicoVagas
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_FALLBACK_historicoVagas" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_FALLBACK_historicoVagas" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_FALLBACK_historicoVagas";

-- USO_FALLBACK_historicoCandidatos
DROP TABLE IF EXISTS "RPO_semper_laser"."USO_FALLBACK_historicoCandidatos" CASCADE;
CREATE TABLE "RPO_semper_laser"."USO_FALLBACK_historicoCandidatos" AS
  SELECT * FROM "RPO_semper_laser"."RAW_AIRBYTE_FALLBACK_historicoCandidatos";

-- =========================================================
-- PASSO 2: Permissoes
-- =========================================================
GRANT USAGE ON SCHEMA "RPO_semper_laser" TO rpo_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "RPO_semper_laser" TO rpo_user;

-- =========================================================
-- PASSO 3: Recriar Views e MVs (ordem obrigatoria)
-- =========================================================

-- 3.1: Views base + MV_SLAs
SELECT dashboard_criar_views('RPO_semper_laser');

-- 3.2: MV_CONSUMO_ERROS_VAGAS
SELECT dashboard_criar_mv_consumo_erros_vagas('RPO_semper_laser');

-- 3.3: MV_CONSUMO_vagas (usa ERROS se existir)
SELECT dashboard_criar_mv_consumo_vagas('RPO_semper_laser');

-- 3.4: MV_CONSUMO_historicoVagas
SELECT dashboard_criar_mv_consumo_historico_vagas('RPO_semper_laser');

-- 3.5: MV_CONSUMO_candidatos
SELECT dashboard_criar_mv_consumo_candidatos('RPO_semper_laser');

COMMIT;

-- =========================================================
-- VERIFICACAO: Contagem de registros
-- =========================================================
SELECT 'MV_CONSUMO_vagas' as mv, count(*) FROM "RPO_semper_laser"."MV_CONSUMO_vagas"
UNION ALL SELECT 'MV_CONSUMO_historicoVagas', count(*) FROM "RPO_semper_laser"."MV_CONSUMO_historicoVagas"
UNION ALL SELECT 'MV_CONSUMO_candidatos', count(*) FROM "RPO_semper_laser"."MV_CONSUMO_candidatos"
UNION ALL SELECT 'MV_CONSUMO_ERROS_VAGAS', count(*) FROM "RPO_semper_laser"."MV_CONSUMO_ERROS_VAGAS"
UNION ALL SELECT 'MV_SLAs', count(*) FROM "RPO_semper_laser"."MV_SLAs";
