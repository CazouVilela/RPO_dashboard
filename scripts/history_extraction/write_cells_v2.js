const WebSocket = require('/home/cazouvilela/projetos/RPO-V4/api_historico/node_modules/ws');
const fs = require('fs');

const PAGE_WS = process.argv[2] || 'ws://localhost:9222/devtools/page/2F720762C71188EDDF01DC8841DDD4AB';

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function createCDP(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let id = 1; const cbs = {};
    ws.on('error', reject);
    ws.on('message', d => {
      const m = JSON.parse(d);
      if (m.id && cbs[m.id]) { cbs[m.id](m); delete cbs[m.id]; }
    });
    ws.on('open', () => {
      const send = (method, params) => new Promise((res, rej) => {
        const mid = id++;
        const to = setTimeout(() => { delete cbs[mid]; rej(new Error('timeout')); }, 120000);
        cbs[mid] = m => { clearTimeout(to); m.error ? rej(new Error(m.error.message)) : res(m.result); };
        ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
      });
      resolve({ ws, send });
    });
  });
}

async function pressKey(send, key, code, vk, modifiers) {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key, code, windowsVirtualKeyCode: vk, modifiers: modifiers || 0 });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: vk, modifiers: modifiers || 0 });
}

(async () => {
  const { ws, send } = await createCDP(PAGE_WS);
  await send('Runtime.enable');
  console.log('Connected');

  // Load data
  const data = JSON.parse(fs.readFileSync('/tmp/ug_history_data.json', 'utf8'));
  console.log(`Data: ${data.length} rows x ${data[0].length} cols`);

  // Make sure we're on the 'historico de vagas' tab
  const tabClick = await send('Runtime.evaluate', {
    expression: `(function() {
      var spans = document.querySelectorAll('span');
      for (var s of spans) {
        if (s.textContent.trim() === 'historico de vagas') {
          var rect = s.getBoundingClientRect();
          if (rect.y > 800) {
            s.click();
            return 'clicked tab at y=' + Math.round(rect.y);
          }
        }
      }
      return 'tab not found';
    })()`,
    returnByValue: true
  });
  console.log('Tab:', tabClick.result.value);
  await sleep(1000);

  // Ctrl+Home to go to A1
  await pressKey(send, 'Home', 'Home', 36, 2);
  await sleep(500);

  // Select all (Ctrl+A) and delete to clear any existing data
  await pressKey(send, 'a', 'KeyA', 65, 2);
  await sleep(300);
  await pressKey(send, 'Delete', 'Delete', 46);
  await sleep(500);

  // Go back to A1
  await pressKey(send, 'Home', 'Home', 36, 2);
  await sleep(500);

  let totalCells = 0;
  const startTime = Date.now();

  for (let row = 0; row < data.length; row++) {
    for (let col = 0; col < data[row].length; col++) {
      const value = data[row][col] || '';

      if (value) {
        // Press F2 to enter edit mode
        await pressKey(send, 'F2', 'F2', 113);
        await sleep(20);

        // Use insertText to type the value
        await send('Input.insertText', { text: value });
        totalCells++;
      }

      // Press Tab to move to next cell (or Enter for last column)
      if (col < data[row].length - 1) {
        await pressKey(send, 'Tab', 'Tab', 9);
      } else {
        // End of row: press Enter
        await pressKey(send, 'Enter', 'Enter', 13);
        await sleep(30);
        // Navigate back to column A
        await pressKey(send, 'Home', 'Home', 36);
      }

      await sleep(20);
    }

    if (row % 10 === 0) {
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      const rate = (totalCells / (elapsed || 1)).toFixed(1);
      console.log(`Row ${row}/${data.length} | ${totalCells} cells | ${elapsed}s | ${rate} cells/s`);
    }
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\nDone! ${totalCells} cells written in ${elapsed}s`);

  // Take screenshot
  await sleep(2000);

  // Go back to top to see the data
  await pressKey(send, 'Home', 'Home', 36, 2);
  await sleep(1000);

  const screenshot = await send('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync('/tmp/sheet_written_v2.png', Buffer.from(screenshot.data, 'base64'));
  console.log('Screenshot saved');

  ws.close();
})();
