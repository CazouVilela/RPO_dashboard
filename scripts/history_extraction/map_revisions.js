const WebSocket = require('/home/cazouvilela/projetos/RPO-V4/api_historico/node_modules/ws');
const fs = require('fs');

const PAGE_WS = process.argv[2] || 'ws://localhost:9222/devtools/page/2F720762C71188EDDF01DC8841DDD4AB';

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function createCDP(url) {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);
    let id = 1; const cbs = {};
    const events = [];
    ws.on('message', d => {
      const m = JSON.parse(d);
      if (m.id && cbs[m.id]) { cbs[m.id](m); delete cbs[m.id]; }
      else if (m.method) { events.push(m); }
    });
    ws.on('open', () => {
      const send = (method, params) => new Promise((res, rej) => {
        const mid = id++;
        const to = setTimeout(() => { delete cbs[mid]; rej(new Error('timeout')); }, 120000);
        cbs[mid] = m => { clearTimeout(to); m.error ? rej(new Error(m.error.message)) : res(m.result); };
        ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
      });
      resolve({ ws, send, events });
    });
  });
}

async function evalJS(send, code) {
  const r = await send('Runtime.evaluate', { expression: code, returnByValue: true });
  return r.result.value;
}

// Get all version textareas with their positions
const JS_GET_ALL_CARDS = `(function() {
  var results = [];
  var textareas = document.querySelectorAll("textarea");
  for (var i = 0; i < textareas.length; i++) {
    var ta = textareas[i];
    var text = (ta.value || ta.textContent || "").trim();
    if (!text.match(/\\d{1,2} de \\w+/)) continue;
    var card = ta.parentElement;
    for (var j = 0; j < 5; j++) { if (card.parentElement) card = card.parentElement; }
    var ct = card.textContent;

    // Extract authors
    var authors = [];
    if (ct.indexOf("Paula Veloso") >= 0) authors.push("Paula Veloso");
    if (ct.indexOf("Cazou Vilela") >= 0) authors.push("Cazou Vilela");
    if (ct.indexOf("Breno") >= 0) authors.push("Breno");
    if (ct.indexOf("anônimos") >= 0) authors.push("anônimos");

    var isImported = ct.indexOf(".xlsx importado") >= 0;

    results.push({
      idx: results.length,
      date: text,
      authors: authors,
      isImported: isImported
    });
  }
  return JSON.stringify(results);
})()`;

function jsScrollToCard(idx) {
  return `(function() {
    var textareas = document.querySelectorAll("textarea");
    var count = 0;
    for (var i = 0; i < textareas.length; i++) {
      var ta = textareas[i];
      var text = (ta.value || ta.textContent || "").trim();
      if (!text.match(/\\d{1,2} de \\w+/)) continue;
      if (count === ${idx}) {
        ta.scrollIntoView({ block: "center" });
        var rect = ta.getBoundingClientRect();
        return JSON.stringify({x: Math.round(rect.x + rect.width/2), y: Math.round(rect.y + rect.height/2), date: text});
      }
      count++;
    }
    return JSON.stringify({x: 0, y: 0});
  })()`;
}

(async () => {
  const { ws, send, events } = await createCDP(PAGE_WS);
  await send('Runtime.enable');
  await send('Network.enable');
  console.log('Connected to version history page');

  // Get all version cards
  const allCards = JSON.parse(await evalJS(send, JS_GET_ALL_CARDS));
  console.log('Total versions found: ' + allCards.length);

  const revisionMap = [];

  for (let vi = 0; vi < allCards.length; vi++) {
    const targetCard = allCards[vi];
    events.length = 0;

    // Scroll card into view and get position
    const pos = JSON.parse(await evalJS(send, jsScrollToCard(targetCard.idx)));
    if (pos.x === 0) {
      console.log('  [' + targetCard.idx + '] Could not find');
      continue;
    }

    await sleep(200);

    // Click
    await send('Input.dispatchMouseEvent', {
      type: 'mousePressed', x: pos.x, y: pos.y, button: 'left', clickCount: 1
    });
    await send('Input.dispatchMouseEvent', {
      type: 'mouseReleased', x: pos.x, y: pos.y, button: 'left'
    });

    await sleep(1500);

    // Find revision ID from network requests
    const revRequests = events
      .filter(e => e.method === 'Network.requestWillBeSent')
      .map(e => e.params.request.url)
      .filter(u => u.includes('revisions/show') || u.includes('rev=') || u.includes('revision'));

    if (revRequests.length > 0) {
      const url = revRequests[0];
      const revMatch = url.match(/rev=(\d+)/);
      const fromRevMatch = url.match(/fromRev=(\d+)/);
      const rev = revMatch ? parseInt(revMatch[1]) : null;
      const fromRev = fromRevMatch ? parseInt(fromRevMatch[1]) : null;

      revisionMap.push({
        idx: targetCard.idx,
        date: targetCard.date,
        authors: targetCard.authors,
        isImported: targetCard.isImported,
        rev: rev,
        fromRev: fromRev,
        url: url.substring(0, 200)
      });

      console.log('  [' + targetCard.idx + '] ' + targetCard.date +
                   ' rev=' + rev + ' | ' + targetCard.authors.join(', '));
    } else {
      if (vi === 0) {
        revisionMap.push({
          idx: targetCard.idx,
          date: targetCard.date,
          authors: targetCard.authors,
          isImported: targetCard.isImported,
          rev: null,
          fromRev: null,
          note: 'current version'
        });
        console.log('  [' + targetCard.idx + '] ' + targetCard.date + ' (current version)');
      } else {
        console.log('  [' + targetCard.idx + '] ' + targetCard.date + ' -> no request captured');
        revisionMap.push({
          idx: targetCard.idx,
          date: targetCard.date,
          authors: targetCard.authors,
          isImported: targetCard.isImported,
          rev: null,
          fromRev: null,
          note: 'no request'
        });
      }
    }

    // Save progress periodically
    if (vi % 20 === 19) {
      fs.writeFileSync('/tmp/ug_revision_map_progress.json', JSON.stringify(revisionMap, null, 2));
      console.log('  ... saved progress (' + revisionMap.length + ' entries)');
    }
  }

  // Save final map
  fs.writeFileSync('/tmp/ug_revision_map.json', JSON.stringify(revisionMap, null, 2));
  console.log('\nDone! Saved ' + revisionMap.length + ' entries to /tmp/ug_revision_map.json');

  // Summary
  const withRev = revisionMap.filter(r => r.rev !== null);
  console.log('Entries with revision ID: ' + withRev.length);
  if (withRev.length > 0) {
    const revNums = withRev.map(r => r.rev).sort((a, b) => a - b);
    console.log('Revision range: ' + revNums[0] + ' - ' + revNums[revNums.length - 1]);
  }

  ws.close();
})();
