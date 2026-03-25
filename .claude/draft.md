# TAREFA PENDENTE: Coluna Divulgacao - Appian (via CDP/Chromium)

## Status: PRONTO PARA EXECUTAR (abrir sessao no terminal direto)

## Problema anterior
- Sessao Claude Code rodando em terminal no browser -> sem acesso ao DISPLAY X
- Chrome precisa do display X para abrir Google Sheets com interface grafica
- Solucao: abrir Claude Code direto no terminal do sistema (com DISPLAY=:0)

## O que ja esta pronto

### 1. Script de parsing (VALIDADO - 15/39 registros com divulgacao)
- Arquivo: `scripts/appian_divulgacao.py`
- Ja baixa o xlsx, parseia historicos e identifica datas - mas NAO usar para upload
- Usar apenas como referencia dos dados parseados

### 2. Dados de divulgacao confirmados (dry-run OK)
| ID | Data | Trecho |
|----|------|--------|
| 8 | 20/08 | Vaga divulgada |
| 9 | 03/11 | Vaga publicada hoje, divulgacao interna e externa ate 07/11 |
| 10 | 26/08 | Vaga divulgada |
| 11 | 02/09 | liberaram a divulgacao da vaga... Vaga em divulgacao na Gupy e LinkedIn |
| 12 | 22/09 | Vaga divulgada, processo seletivo iniciado |
| 13 | 17/10 | Vaga publicada (divulgacao de 17/10 a 23/10) |
| 16 | 30/09 | Vaga publicada, inicio da divulgacao |
| 20 | 13/01 | Vaga publicada na Gupy em 13/01 |
| 21 | 13/01 | Vaga publicada na Gupy em 13/01 |
| 22 | 13/01 | Vaga publicada na Gupy em 13/01 |
| 25 | 07/01 | Descricao de cargo aprovada e vaga divulgada |
| 36 | 03/11 | Vaga publicada hoje, divulgacao interna e externa ate 07/11 |
| 37 | 03/11 | Vaga publicada hoje, divulgacao interna e externa ate 07/11 |
| 43 | 07/01 | Processo seletivo iniciado e vaga divulgada |
| 48 | 10/02/26 | Descricao de cargo enviada para validacao e vaga divulgada |

### 3. Estrutura da planilha (ja mapeada)
- Planilha: .xlsx no Drive (NAO e Google Sheets nativo)
- File ID: `1aW71mfAHBSbzIeS9-be9qcpfzTWjzEPf`
- GID aba: `744894324`
- Aba ativa: `Acompanhamento`
- Colunas relevantes:
  - Col 1 (A): id
  - Col 13 (M): Divulgacao (JA EXISTE, esta vazia)
  - Col 18 (R): Historico
- 39 registros com dados (linhas 2-40, pois max_row=1000 mas so 39+1 tem dados)

## O que fazer na proxima sessao

### Passo 1: Iniciar Chrome com remote debugging
```bash
DISPLAY=:0 /home/cazouvilela/.cache/puppeteer/chrome/linux-146.0.7680.31/chrome-linux64/chrome \
  --remote-debugging-port=9222 \
  --no-first-run \
  --user-data-dir=/tmp/chrome-cdp-appian \
  "https://docs.google.com/spreadsheets/d/1aW71mfAHBSbzIeS9-be9qcpfzTWjzEPf/edit?gid=744894324#gid=744894324" &
```

### Passo 2: Verificar conexao CDP
```bash
curl -s http://localhost:9222/json | python3 -m json.tool
```

### Passo 3: Criar e executar script CDP (Node.js)
O script deve:
1. Conectar via WebSocket ao CDP
2. Navegar ate a celula M2 (coluna Divulgacao, primeira linha de dados)
3. Para cada ID com divulgacao:
   - Usar Name Box (caixa de celulas) para ir ate M[row] -> digitar a data
   - Formatar celula em VERMELHO (fonte)
   - Ir ate R[row] (Historico) -> selecionar o trecho de divulgacao -> formatar em VERMELHO
4. Tirar screenshot de confirmacao

### Referencia: script CDP existente
- `/home/cazouvilela/projetos/RPO_dashboard/scripts/history_extraction/write_cells_v2.js`
- Usa: ws module em `/home/cazouvilela/projetos/RPO/api_historico/node_modules/ws`
- Padrao: createCDP -> pressKey -> Input.insertText

### Mapeamento linha planilha por ID
A coluna ID esta na col A. Os IDs NAO sao sequenciais (comecam em 2, 3, 4...).
Precisa mapear: para cada ID da tabela acima, encontrar a linha correta na planilha.
Abordagem: usar Ctrl+Home, depois Ctrl+G ou Name Box para navegar direto para M[row].
OU: ler os IDs da col A para montar o mapeamento id->row.

## Correcoes do pg_cron (JA FEITAS - nao refazer)
- Job 123 (Appian): porta corrigida + colunas atualizadas
- Jobs 28, 30, 31, 106-122: porta 15432 adicionada
- .pgpass atualizado (5432 -> 15432)

## Conexao PostgreSQL (para referencia)
- Host: /tmp (unix socket), porta 15432, banco HUB, user cazouvilela
- Comando: `/usr/pgsql-17/bin/psql -h /tmp -p 15432 -d HUB`
- Schema: RPO_Appian, tabela: acompanhamento
