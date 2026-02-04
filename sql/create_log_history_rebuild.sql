-- Create log_history_rebuild table
-- Simulates how USO_historicoVagas would have been populated by AppScript
-- Based on status changes extracted from Google Sheets version history

DROP TABLE IF EXISTS "RPO_cielo".log_history_rebuild;

CREATE TABLE "RPO_cielo".log_history_rebuild (
    id SERIAL PRIMARY KEY,
    requisicao VARCHAR(100) NOT NULL,
    status VARCHAR(100) NOT NULL,
    alterado_por VARCHAR(255),
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    version INTEGER DEFAULT 1,
    -- Campos de candidatos (shortlist)
    cdd_totais_sl TEXT,
    cdd_mulher_sl TEXT,
    cdd_pcd_sl TEXT,
    cdd_diversidade_racial_sl TEXT,
    -- Campos de selecionado
    selecionado_nome TEXT,
    selecionado_fonte TEXT,
    selecionado_genero TEXT,
    selecionado_pcd TEXT,
    selecionado_diversidade_racial TEXT,
    -- Campos de proposta
    operacao_status_ultima_proposta TEXT,
    operacao_selecionado_ultima_proposta TEXT,
    operacao_motivo_declinio_ultima_proposta TEXT,
    -- Campos adicionais do selecionado
    selecionado_tipo TEXT,
    selecionado_empregado TEXT,
    selecionado_empresa_anterior TEXT
);

-- Create indexes for efficient queries
CREATE INDEX idx_log_history_rebuild_req ON "RPO_cielo".log_history_rebuild(requisicao);
CREATE INDEX idx_log_history_rebuild_created ON "RPO_cielo".log_history_rebuild(created_at DESC);
CREATE INDEX idx_log_history_rebuild_status ON "RPO_cielo".log_history_rebuild(status);

COMMENT ON TABLE "RPO_cielo".log_history_rebuild IS 'Reconstructed history based on Google Sheets version history (Jan 2 - Feb 4, 2025). Simulates how AppScript would have populated USO_historicoVagas.';
