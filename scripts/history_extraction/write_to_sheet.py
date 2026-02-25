#!/usr/bin/env python3
"""
Write the extracted history data to the Google Sheet as a new tab "historico de vagas".
Uses Google Sheets API v4 with cookies from the browser session.
"""

import json
import subprocess
import re

COOKIES = open('/tmp/google_cookies.txt').read().strip()
SHEET_ID = '1aW71mfAHBSbzIeS9-be9qcpfzTWjzEPf'

# Load changes
with open('/tmp/ug_changes_final.json') as f:
    changes = json.load(f)

print(f"Total entries to write: {len(changes)}")

# Sort by data_alteracao
changes.sort(key=lambda x: x.get('data_alteracao', ''))

# First, get an access token from the browser
# We'll extract a SAPISIDHASH for the Sheets API
import hashlib
import time

def get_sapisid_hash(sapisid, origin='https://docs.google.com'):
    timestamp = str(int(time.time()))
    hash_input = f"{timestamp} {sapisid} {origin}"
    hash_value = hashlib.sha1(hash_input.encode()).hexdigest()
    return f"SAPISIDHASH {timestamp}_{hash_value}"

# Extract SAPISID from cookies
sapisid = None
for part in COOKIES.split(';'):
    part = part.strip()
    if part.startswith('SAPISID='):
        sapisid = part.split('=', 1)[1]
        break

if not sapisid:
    print("ERROR: SAPISID not found in cookies")
    exit(1)

auth_header = get_sapisid_hash(sapisid)
print(f"Auth header generated")

# Step 1: Add a new sheet tab "historico de vagas"
add_sheet_payload = json.dumps({
    "requests": [
        {
            "addSheet": {
                "properties": {
                    "title": "historico de vagas",
                    "index": 4
                }
            }
        }
    ]
})

result = subprocess.run(
    ['curl', '-sL', '-w', '\n%{http_code}',
     '-X', 'POST',
     f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}:batchUpdate',
     '-H', f'Authorization: {auth_header}',
     '-H', 'Content-Type: application/json',
     '-H', 'X-Goog-AuthUser: 0',
     '-b', COOKIES,
     '-d', add_sheet_payload],
    capture_output=True, text=True, timeout=30
)

output = result.stdout
http_code = output.strip().split('\n')[-1]
body = '\n'.join(output.strip().split('\n')[:-1])

print(f"Add sheet: HTTP {http_code}")
if http_code != '200':
    print(f"Response: {body[:500]}")
    # Sheet might already exist - try to clear it
    if 'already exists' in body.lower():
        print("Sheet already exists, will clear it")
    else:
        # Try alternative approach: use internal API
        print("Trying internal API approach...")

# Get the sheet ID of "historico de vagas" tab
result2 = subprocess.run(
    ['curl', '-sL',
     f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}?fields=sheets.properties',
     '-H', f'Authorization: {auth_header}',
     '-H', 'X-Goog-AuthUser: 0',
     '-b', COOKIES],
    capture_output=True, text=True, timeout=30
)

sheets_info = json.loads(result2.stdout) if result2.stdout.strip() else {}
hist_sheet_id = None
if 'sheets' in sheets_info:
    for s in sheets_info['sheets']:
        props = s.get('properties', {})
        if props.get('title') == 'historico de vagas':
            hist_sheet_id = props.get('sheetId')
            print(f"Found 'historico de vagas' tab with sheetId={hist_sheet_id}")
            break

# Step 2: Prepare data rows
header_row = [
    'id', 'Recrutador', 'Cargo', 'Destino', 'Gestor',
    'coluna_alterada', 'data_alteracao',
    'Situacao', 'Etapa', 'Planejamento Admissao', 'alterado_por'
]

data_rows = [header_row]
for c in changes:
    data_rows.append([
        c.get('id', ''),
        c.get('Recrutador', ''),
        c.get('Cargo', ''),
        c.get('Destino', ''),
        c.get('Gestor', ''),
        c.get('coluna_alterada', ''),
        c.get('data_alteracao', ''),
        c.get('Situacao', ''),
        c.get('Etapa', ''),
        c.get('Planejamento Admissao', ''),
        c.get('alterado_por', '')
    ])

print(f"Prepared {len(data_rows)} rows (1 header + {len(data_rows)-1} data)")

# Step 3: Write data to the sheet
# Clear first, then write
range_name = f"'historico de vagas'!A1:K{len(data_rows)}"

# Clear
clear_payload = json.dumps({"range": range_name})
result3 = subprocess.run(
    ['curl', '-sL', '-w', '\n%{http_code}',
     '-X', 'POST',
     f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}/values/{range_name}:clear',
     '-H', f'Authorization: {auth_header}',
     '-H', 'Content-Type: application/json',
     '-H', 'X-Goog-AuthUser: 0',
     '-b', COOKIES,
     '-d', clear_payload],
    capture_output=True, text=True, timeout=30
)
http_code3 = result3.stdout.strip().split('\n')[-1]
print(f"Clear range: HTTP {http_code3}")

# Write data
write_payload = json.dumps({
    "range": range_name,
    "majorDimension": "ROWS",
    "values": data_rows
})

# Write in chunks if too large
CHUNK_SIZE = 50
for start in range(0, len(data_rows), CHUNK_SIZE):
    end = min(start + CHUNK_SIZE, len(data_rows))
    chunk = data_rows[start:end]
    chunk_range = f"'historico de vagas'!A{start+1}:K{end}"

    chunk_payload = json.dumps({
        "range": chunk_range,
        "majorDimension": "ROWS",
        "values": chunk
    })

    result4 = subprocess.run(
        ['curl', '-sL', '-w', '\n%{http_code}',
         '-X', 'PUT',
         f'https://sheets.googleapis.com/v4/spreadsheets/{SHEET_ID}/values/{chunk_range}?valueInputOption=RAW',
         '-H', f'Authorization: {auth_header}',
         '-H', 'Content-Type: application/json',
         '-H', 'X-Goog-AuthUser: 0',
         '-b', COOKIES,
         '-d', chunk_payload],
        capture_output=True, text=True, timeout=30
    )

    http_code4 = result4.stdout.strip().split('\n')[-1]
    if http_code4 == '200':
        print(f"  Wrote rows {start+1}-{end}: OK")
    else:
        body4 = '\n'.join(result4.stdout.strip().split('\n')[:-1])
        print(f"  Wrote rows {start+1}-{end}: HTTP {http_code4}")
        print(f"  Response: {body4[:300]}")

print("\nDone!")
