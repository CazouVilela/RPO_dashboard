-- Create historico_log_vagas table in RPO_cielo schema
-- This table tracks status changes for vagas extracted from Google Sheets version history

DROP TABLE IF EXISTS "RPO_cielo".historico_log_vagas;

CREATE TABLE "RPO_cielo".historico_log_vagas (
    id SERIAL PRIMARY KEY,
    rp VARCHAR(50) NOT NULL,
    old_status VARCHAR(100),
    new_status VARCHAR(100),
    change_datetime TIMESTAMP,
    changed_by VARCHAR(100),
    revision_id INTEGER,
    prev_revision_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for efficient queries
CREATE INDEX idx_historico_log_vagas_rp ON "RPO_cielo".historico_log_vagas(rp);
CREATE INDEX idx_historico_log_vagas_datetime ON "RPO_cielo".historico_log_vagas(change_datetime);
CREATE INDEX idx_historico_log_vagas_new_status ON "RPO_cielo".historico_log_vagas(new_status);

COMMENT ON TABLE "RPO_cielo".historico_log_vagas IS 'Status change history for vagas, extracted from Google Sheets version history (Jan 2 - Feb 4, 2025)';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.rp IS 'RP number from the vagas sheet';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.old_status IS 'Previous status value';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.new_status IS 'New status value after change';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.change_datetime IS 'Timestamp when the change was made';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.changed_by IS 'Name of the person who made the change';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.revision_id IS 'Google Sheets internal revision number';
COMMENT ON COLUMN "RPO_cielo".historico_log_vagas.prev_revision_id IS 'Previous revision number for comparison';
