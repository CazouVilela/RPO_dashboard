#!/usr/bin/env python3
"""
Rebuild USO_historicoVagas from Google Sheets version history data.

This script simulates how the AppScript would have populated USO_historicoVagas
by processing status changes extracted from the Google Sheets version history.

The AppScript behavior:
1. When status changes -> creates a new row in historico with:
   - requisicao, status, alterado_por, created_at, updated_at
   - All other fields (cdd_*, selecionado_*, operacao_*) are empty initially

2. When dados_candidatos change -> API updates the LATEST row with funcaoSistema='shortlist'
   - Updates cdd_totais_sl, cdd_mulher_sl, cdd_pcd_sl, cdd_diversidade_racial_sl

3. When dados_selecionado change -> API updates the LATEST row with funcaoSistema='proposta'
   - Updates selecionado_* and operacao_* fields

Since we only extracted STATUS changes from version history, this script will:
- Create one row per status change (simulating AppScript behavior)
- Leave cdd_* and selecionado_* fields empty (we don't have that historical data)
"""

import psycopg2
from datetime import datetime

# Database connection
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'HUB',
    'user': 'rpo_user',
    'password': 'rpo_super_secret001'
}

# Map short names to emails (based on USO_historicoVagas data)
EMAIL_MAP = {
    'Ariane': 'ariane.moura@hubtalent.com.br',
    'Carolina': 'carolina.silva@hubinfinity.com.br',
    'Cazou': 'cazou.vilela@hubtalent.com.br',
    'Emily': 'emily.alencar@hubinfinity.com.br',
    'Gabrielle': 'gabrielle@hubinfinity.com.br',  # Assumed
    'Gessica': 'gessica.amorim@hubtalent.com.br',
    'Jessica': 'jessica.morais@hubinfinity.com.br',
    'Liliane': 'liliane.ferreira@hubinfinity.com.br',
    'Taina': 'taina.lustosa@hubinfinity.com.br'
}


def main():
    print("=== Rebuilding History from Version Changes ===\n")

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    # Create the table
    print("Creating log_history_rebuild table...")
    with open('/home/cazouvilela/projetos/RPO_dashboard/sql/create_log_history_rebuild.sql', 'r') as f:
        sql = f.read()
    cur.execute(sql)
    conn.commit()
    print("Table created.\n")

    # Get all status changes from historico_log_vagas
    print("Loading status changes from historico_log_vagas...")
    cur.execute("""
        SELECT rp, old_status, new_status, change_datetime, changed_by, revision_id
        FROM "RPO_cielo".historico_log_vagas
        WHERE new_status IS NOT NULL AND TRIM(new_status) != ''
        ORDER BY change_datetime, revision_id
    """)
    changes = cur.fetchall()
    print(f"Loaded {len(changes)} status changes.\n")

    # Insert each status change as a new row in log_history_rebuild
    print("Inserting rows into log_history_rebuild...")

    insert_sql = """
        INSERT INTO "RPO_cielo".log_history_rebuild
        (requisicao, status, alterado_por, created_at, updated_at, version)
        VALUES (%s, %s, %s, %s, %s, 1)
    """

    inserted = 0
    for rp, old_status, new_status, change_datetime, changed_by, revision_id in changes:
        # Map short name to email
        email = EMAIL_MAP.get(changed_by, f'{changed_by.lower()}@hubinfinity.com.br')

        # Use change_datetime for both created_at and updated_at
        timestamp = change_datetime if change_datetime else datetime.now()

        cur.execute(insert_sql, (
            rp,
            new_status,
            email,
            timestamp,
            timestamp
        ))
        inserted += 1

        if inserted % 50 == 0:
            print(f"  ... inserted {inserted} rows")

    conn.commit()
    print(f"\nInserted {inserted} rows into log_history_rebuild.\n")

    # Verify and show summary
    print("=== Summary ===")

    cur.execute('SELECT COUNT(*) FROM "RPO_cielo".log_history_rebuild')
    total = cur.fetchone()[0]
    print(f"Total rows: {total}")

    cur.execute('SELECT COUNT(DISTINCT requisicao) FROM "RPO_cielo".log_history_rebuild')
    unique_rps = cur.fetchone()[0]
    print(f"Unique RPs: {unique_rps}")

    cur.execute("""
        SELECT MIN(created_at), MAX(created_at)
        FROM "RPO_cielo".log_history_rebuild
    """)
    min_dt, max_dt = cur.fetchone()
    print(f"Date range: {min_dt} to {max_dt}")

    # Status distribution
    print("\nStatus distribution:")
    cur.execute("""
        SELECT status, COUNT(*) as cnt
        FROM "RPO_cielo".log_history_rebuild
        GROUP BY status
        ORDER BY cnt DESC
    """)
    for status, cnt in cur.fetchall():
        print(f"  {status}: {cnt}")

    # By person
    print("\nBy alterado_por:")
    cur.execute("""
        SELECT alterado_por, COUNT(*) as cnt
        FROM "RPO_cielo".log_history_rebuild
        GROUP BY alterado_por
        ORDER BY cnt DESC
    """)
    for person, cnt in cur.fetchall():
        print(f"  {person}: {cnt}")

    # Compare with USO_historicoVagas
    print("\n=== Comparison with USO_historicoVagas ===")
    cur.execute('SELECT COUNT(*) FROM "RPO_cielo"."USO_historicoVagas"')
    uso_count = cur.fetchone()[0]
    print(f"USO_historicoVagas rows: {uso_count}")
    print(f"log_history_rebuild rows: {total}")

    cur.close()
    conn.close()

    print("\n=== Done! ===")


if __name__ == '__main__':
    main()
