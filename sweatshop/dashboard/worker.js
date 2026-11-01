// The sweatshop dashboard: one page and one write API over a D1 table (schema.sql).
// The driver POSTs each lane's whole snapshot to /api/lane, at stage start and end, at
// exit, and every ~2 min during a stage as the heartbeat:
//   { project, lane, pc, foreman, session, driver: 'running|finished|stopped|crashed',
//     current: null | { id, title, stage, model, startedAt: '<UTC ISO>', limitMin },
//     tickets: [{ id, title, state, note }], needsHuman: [{ id, title, state, note }],
//     events: [{ at: '<ISO>', text }], pr: '<url>' | null, costToday: '$1.234' | '≥$1.234',
//     updatedAt: '<ISO>' }
// Two secrets: WRITE_TOKEN (the driver's bearer token) and READ_PASSWORD (HTTP Basic for
// the page and its poll; any user name). Either one unset refuses its side.

const MAX_BODY = 64 * 1024;
const WEEK = 7 * 24 * 3600e3;
const UPSERT = 'INSERT INTO lanes (key, json, receivedAt) VALUES (?1, ?2, ?3) ' +
  'ON CONFLICT(key) DO UPDATE SET json = excluded.json, receivedAt = excluded.receivedAt';

export default {
  async fetch(req, env) {
    const { pathname } = new URL(req.url);
    if (pathname === '/api/lane' && req.method === 'POST') return write(req, env);
    if (req.method !== 'GET' || (pathname !== '/' && pathname !== '/api/lanes')) return new Response('not found', { status: 404 });
    if (!readAllowed(req, env)) {
      return new Response('password required', { status: 401, headers: { 'www-authenticate': 'Basic realm="sweatshop", charset="UTF-8"' } });
    }
    if (pathname === '/') return new Response(PAGE, { headers: { 'content-type': 'text/html; charset=utf-8' } });
    const now = Date.now();
    const { results } = await env.DB.prepare('SELECT json, receivedAt FROM lanes WHERE receivedAt > ?')
      .bind(now - WEEK).all();
    const lanes = results.map(r => ({ ...JSON.parse(r.json), receivedAt: r.receivedAt }));
    return Response.json({ now, lanes }, { headers: { 'cache-control': 'no-store' } });
  },
};

function same(a, b) {
  const enc = new TextEncoder(), x = enc.encode(a), y = enc.encode(b);
  return x.byteLength === y.byteLength && crypto.subtle.timingSafeEqual(x, y);
}

function readAllowed(req, env) {
  const m = /^Basic (.+)$/.exec(req.headers.get('authorization') || '');
  if (!env.READ_PASSWORD || !m) return false;
  let pair;
  try { pair = new TextDecoder().decode(Uint8Array.from(atob(m[1]), c => c.charCodeAt(0))); } catch { return false; }
  return same(pair.slice(pair.indexOf(':') + 1), env.READ_PASSWORD);
}

async function write(req, env) {
  if (!env.WRITE_TOKEN || !same(req.headers.get('authorization') || '', 'Bearer ' + env.WRITE_TOKEN)) {
    return new Response('unauthorized', { status: 401 });
  }
  const body = await req.text();
  if (body.length > MAX_BODY) return new Response('snapshot too large', { status: 413 });
  let s;
  try { s = JSON.parse(body); } catch { return new Response('not JSON', { status: 400 }); }
  const name = v => typeof v === 'string' && v.length > 0 && v.length <= 100;
  if (!s || !name(s.project) || !name(s.lane)) return new Response('project and lane must be strings', { status: 400 });
  await env.DB.prepare(UPSERT).bind(`${s.project}/${s.lane}`, body, Date.now()).run();
  return new Response(null, { status: 204 });
}

// The page builds every node from text (textContent, never innerHTML): ticket titles and
// notes come from repos, not from this code. No backticks or dollar-braces below: it sits
// in a template literal.
const PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sweatshop</title>
<style>
  :root { --bg: #f6f6f4; --card: #fff; --ink: #1d1d1b; --dim: #6b6b66; --line: #e2e2dd;
          --ok: #1f7a3a; --bad: #b3261e; --warn: #9a5b00; --off: #6b6b66; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #161615; --card: #20201e; --ink: #ececea; --dim: #9b9b95; --line: #33332f;
            --ok: #5cc27a; --bad: #ff7b72; --warn: #e3a33b; --off: #9b9b95; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px; background: var(--bg); color: var(--ink);
         font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
  a { color: inherit; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .top { font-size: 16px; margin: 0 0 20px; color: var(--dim); }
  .top b { color: var(--ink); }
  .err { border: 1px solid var(--bad); color: var(--bad); padding: 8px 12px; border-radius: 6px; margin-bottom: 16px; }
  .projects { display: grid; gap: 8px; max-width: 640px; }
  .project { display: flex; justify-content: space-between; gap: 12px; padding: 12px 16px; background: var(--card);
             border: 1px solid var(--line); border-radius: 8px; text-decoration: none; }
  .project:hover, .project:focus-visible { border-color: var(--dim); }
  .cards { display: grid; gap: 12px; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; }
  .head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 10px; margin-bottom: 8px; }
  .lane { font-weight: 600; font-size: 15px; }
  .tag { font-size: 12px; color: var(--dim); border: 1px solid var(--line); border-radius: 4px; padding: 0 6px; }
  .state { font-size: 12px; font-weight: 600; }
  .running { color: var(--ok); } .bad { color: var(--bad); } .ended { color: var(--off); } .need { color: var(--warn); }
  .dim { color: var(--dim); }
  h3 { font-size: 12px; text-transform: uppercase; letter-spacing: .04em; color: var(--dim); margin: 12px 0 4px; }
  ul { margin: 0; padding-left: 18px; }
  li { margin: 1px 0; }
  .foot { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 12px; color: var(--dim); font-size: 13px; }
</style>
</head>
<body>
<main id="app"><p class="dim">Loading…</p></main>
<script>
var NO_HEARTBEAT_MS = 10 * 60 * 1000;
var data = null, error = '';

function el(tag, cls) {
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  [].slice.call(arguments, 2).flat().forEach(function (k) {
    if (k !== null && k !== undefined && k !== false) e.append(k instanceof Node ? k : String(k));
  });
  return e;
}
function stateOf(l) {
  if (l.driver === 'running') return data.now - l.receivedAt > NO_HEARTBEAT_MS ? 'no heartbeat' : 'running';
  return l.driver || 'unknown';
}
function stateClass(s) { return s === 'running' ? 'running' : (s === 'no heartbeat' || s === 'crashed') ? 'bad' : 'ended'; }
function needs(l) { return (l.needsHuman || []).length; }
function mins(ms) { return Math.max(0, Math.round(ms / 60000)) + 'm'; }
function hhmm(iso) { var d = new Date(iso); return isNaN(d) ? '' : d.toTimeString().slice(0, 5); }
function summary(lanes) {
  var run = lanes.filter(function (l) { return stateOf(l) === 'running'; }).length;
  var need = lanes.reduce(function (n, l) { return n + needs(l); }, 0);
  return el('p', 'top', el('b', null, run), ' running, ', el('b', need ? 'need' : null, need), ' need you');
}
function byProject() {
  var groups = {};
  data.lanes.forEach(function (l) { (groups[l.project] = groups[l.project] || []).push(l); });
  return groups;
}
function ticketItem(t) {
  return el('li', null, el('b', null, t.id), ' ', el('span', 'dim', t.state), ' ', t.title, t.note ? el('span', 'dim', ' — ' + t.note) : null);
}

function card(l) {
  var s = stateOf(l), c = l.current;
  var box = el('section', 'card',
    el('div', 'head', el('span', 'lane', l.lane), el('span', 'state ' + stateClass(s), s),
       el('span', 'tag', l.foreman || 'manual'), el('span', 'dim', l.pc)));
  if (c) {
    box.append(el('div', null, el('b', null, c.id), ' ', c.title),
               el('div', 'dim', [c.stage, c.model, mins(data.now - Date.parse(c.startedAt)) + ' of ' + c.limitMin + 'm'].join(' · ')));
  }
  if (needs(l)) box.append(el('h3', 'need', 'Needs you'), el('ul', null, l.needsHuman.map(ticketItem)));
  if ((l.tickets || []).length) box.append(el('h3', null, 'Tickets'), el('ul', null, l.tickets.map(ticketItem)));
  if ((l.events || []).length) {
    box.append(el('h3', null, 'Events'),
      el('ul', null, l.events.slice(-8).map(function (e) { return el('li', null, el('span', 'dim', hhmm(e.at)), ' ', e.text); })));
  }
  var pr = /^https:\\/\\//.test(l.pr || '') ? el('a', null, 'PR') : null;
  if (pr) pr.href = l.pr;
  box.append(el('div', 'foot', pr, l.costToday ? 'today ' + l.costToday : null, 'updated ' + mins(data.now - l.receivedAt) + ' ago'));
  return box;
}

function render() {
  var app = document.getElementById('app');
  app.replaceChildren();
  if (error) app.append(el('div', 'err', error));
  if (!data) return;
  var groups = byProject(), project = decodeURIComponent(location.hash.slice(1));
  if (project && groups[project]) {
    var back = el('a', null, '← all projects'); back.href = '#';
    var lanes = groups[project].slice().sort(function (a, b) { return a.lane.localeCompare(b.lane); });
    app.append(back, el('h1', null, project), summary(lanes), el('div', 'cards', lanes.map(card)));
    document.title = project + ' · Sweatshop';
    return;
  }
  var list = el('div', 'projects');
  Object.keys(groups).sort().forEach(function (p) {
    var ls = groups[p], bad = ls.filter(function (l) { return stateClass(stateOf(l)) === 'bad'; }).length;
    var run = ls.filter(function (l) { return stateOf(l) === 'running'; }).length;
    var need = ls.reduce(function (n, l) { return n + needs(l); }, 0);
    var a = el('a', 'project', el('b', null, p),
      el('span', null, el('span', 'dim', ls.length + (ls.length === 1 ? ' lane · ' : ' lanes · ')), run + ' running',
         need ? el('span', 'need', ' · ' + need + ' need you') : null,
         bad ? el('span', 'bad', ' · ' + bad + ' down') : null));
    a.href = '#' + encodeURIComponent(p);
    list.append(a);
  });
  app.append(el('h1', null, 'Sweatshop'), summary(data.lanes),
             data.lanes.length ? list : el('p', 'dim', 'No lanes reported in the last 7 days.'));
  document.title = 'Sweatshop';
}

async function load() {
  try {
    // The origin, not a relative URL: a page opened as https://user:pass@host cannot fetch a URL with credentials.
    var r = await fetch(location.origin + '/api/lanes', { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    data = await r.json(); error = '';
  } catch (e) {
    error = 'Cannot reach the dashboard API (' + e.message + '). Reload the page; it asks for the password again if needed.';
  }
  render();
}
load();
setInterval(load, 15000);
addEventListener('hashchange', render);
</script>
</body>
</html>`;
