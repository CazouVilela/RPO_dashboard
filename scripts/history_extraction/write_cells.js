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

(async () => {
  const { ws, send } = await createCDP(PAGE_WS);
  await send('Runtime.enable');
  console.log('Connected');

  // Load data
  const data = JSON.parse(fs.readFileSync('/tmp/ug_history_data.json', 'utf8'));
  console.log(`Data: ${data.length} rows x ${data[0].length} cols`);

  // Make sure we're on the 'historico de vagas' tab - click on it
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

  // Navigate to cell A1
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Home', code: 'Home', windowsVirtualKeyCode: 36, modifiers: 2 });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Home', code: 'Home', windowsVirtualKeyCode: 36, modifiers: 2 });
  await sleep(300);

  // Click on cell A1
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 97, y: 175, button: 'left', clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 97, y: 175, button: 'left' });
  await sleep(300);

  let totalCells = 0;
  const startTime = Date.now();

  for (let row = 0; row < data.length; row++) {
    for (let col = 0; col < data[row].length; col++) {
      const value = data[row][col] || '';

      if (value) {
        // Type the value
        await send('Input.insertText', { text: value });
        totalCells++;
      }

      // Press Tab to move to next cell (or Enter for last column to go to next row)
      if (col < data[row].length - 1) {
        await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 });
        await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 });
      } else {
        // End of row: press Enter to go to next row
        await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 });
        await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 });
        await sleep(50);

        // Navigate back to column A
        await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Home', code: 'Home', windowsVirtualKeyCode: 36 });
        await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Home', code: 'Home', windowsVirtualKeyCode: 36 });
      }

      await sleep(30); // Small delay between cells
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
  const screenshot = await send('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync('/tmp/sheet_written.png', Buffer.from(screenshot.data, 'base64'));
  console.log('Screenshot saved');

  ws.close();
})();
