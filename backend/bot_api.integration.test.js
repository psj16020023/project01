const test = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const { spawn } = require('node:child_process');

test('shared immutable votes feed only the authenticated user taste profile', { timeout: 60000 }, async (t) => {
  const socket = net.createServer();
  await new Promise((resolve) => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise((resolve) => socket.close(resolve));
  // Explicit empty values prevent dotenv from loading production credentials.
  const child = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(port), MONGO_URI: '', OPENAI_API_KEY: '',
      ALLOW_IN_MEMORY_MONGO: 'true', NODE_ENV: 'test', JWT_SECRET: 'local-integration-test-only',
      RENDER_GIT_COMMIT: 'integration-revision' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Test server did not start')), 45000);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('exit', (code) => { clearTimeout(timer); reject(new Error(`Test server exited: ${code}`)); });
    child.stdout.on('data', (data) => {
      if (String(data).includes('using in-memory MongoDB')) { clearTimeout(timer); resolve(); }
    });
  });
  const base = `http://127.0.0.1:${port}`;
  const version = await fetch(base + '/api/version');
  assert.equal(version.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await version.json(), { revision: 'integration-revision' });
  async function api(path, token, body, method = 'POST') {
    const response = await fetch(base + path, {
      method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    assert.ok(response.ok, `${path}: ${response.status}`);
    return response.json();
  }
  const a = await api('/api/auth/signup', null, { username: 'test-a', nickname: '테스트 A', password: 'fixture-only' });
  const b = await api('/api/auth/signup', null, { username: 'test-b', nickname: '테스트 B', password: 'fixture-only' });
  const match = { id: 'test-battle', title: '조합 테스트', leftCustomTitle: '우유 + 쿠키', rightCustomTitle: '라면 + 치즈',
    endsAt: new Date(Date.now() + 3600000).toISOString(), leftColorValue: 1, rightColorValue: 2 };
  await api('/api/battles', a.token, match);
  const first = await api('/api/battles/test-battle/vote', a.token, { side: 'left' });
  assert.equal(first.match.leftVotes, 1);
  assert.equal(first.match.viewerId, a.user.id);
  const duplicate = await api('/api/battles/test-battle/vote', a.token, { side: 'right' });
  assert.equal(duplicate.accepted, false);
  assert.equal(duplicate.match.rightVotes, 0);
  const global = await api('/api/battles', b.token, null, 'GET');
  const shared = global.matches.find((m) => m.id === match.id);
  assert.equal(shared.leftVotes, 1);
  assert.equal(shared.viewerVoteSide, null);
  assert.equal(shared.viewerId, b.user.id);

  // Editing metadata must not replace the atomic vote that happens beside it.
  await Promise.all([
    api('/api/battles/test-battle', a.token, { ...match, title: '수정 제목' }, 'PUT'),
    api('/api/battles/test-battle/vote', b.token, { side: 'right' }),
  ]);
  const edited = (await api('/api/battles', a.token, null, 'GET')).matches.find((m) => m.id === match.id);
  assert.equal(edited.leftVotes, 1);
  assert.equal(edited.rightVotes, 1);

  const profile = await api('/api/bot/analyze', a.token, { prompt: '간식 추천', userId: b.user.id });
  assert.equal(profile.analysis.preferences.sampleCount, 1);
  assert.equal(profile.analysis.preferences.categoryWeights['달달'], 1);
  const other = await api('/api/bot/analyze', b.token, { prompt: '간식 추천', userId: a.user.id });
  assert.equal(other.analysis.preferences.categoryWeights['달달'], undefined);
  assert.equal((await api('/api/bot/reply', a.token, { prompt: '대화 테스트' })).source, 'local-fallback');
  const unauthorized = await fetch(base + '/api/bot/reply', { method: 'POST' });
  assert.equal(unauthorized.status, 401);

  await t.test('only authors receive ended results and read state persists', async () => {
    const ends = Date.now() + 2500;
    const source = (await api('/api/posts?limit=1', null, null, 'GET')).posts[0];
    for (const id of ['result-win', 'result-tie', 'result-zero']) {
      await api('/api/battles', a.token, { ...match, id,
        leftPostId: source.id, leftCustomTitle: null, endsAt: new Date(ends).toISOString() });
    }
    await api('/api/battles/result-win/vote', a.token, { side: 'left' });
    await api('/api/battles/result-win/vote', b.token, { side: 'left' });
    await api('/api/battles/result-tie/vote', a.token, { side: 'left' });
    await api('/api/battles/result-tie/vote', b.token, { side: 'right' });
    const before = await api('/api/battles/results', a.token, null, 'GET');
    assert.deepEqual(before.results, []);
    assert.ok(before.refreshAfterMs <= 2700);
    assert.deepEqual((await api('/api/battles/results/read', a.token, { matchIds: ['result-win'] })).readIds, []);
    await new Promise((resolve) => setTimeout(resolve, Math.max(0, ends - Date.now()) + 80));
    const results = (await api('/api/battles/results', a.token, null, 'GET')).results;
    assert.equal(results.length, 3);
    const win = results.find((result) => result.id === 'result-win');
    assert.equal(win.leftVotes, 2);
    assert.equal(win.rightVotes, 0);
    assert.equal(win.leftTitle, source.title);
    assert.equal(win.unread, true);
    assert.equal(win.leftVoterIds, undefined);
    const tie = results.find((result) => result.id === 'result-tie');
    assert.equal(tie.leftVotes, tie.rightVotes);
    const zero = results.find((result) => result.id === 'result-zero');
    assert.equal(zero.leftVotes + zero.rightVotes, 0);
    assert.deepEqual((await api(`/api/battles/results?authorId=${a.user.id}`, b.token, null, 'GET')).results, []);
    assert.deepEqual((await api('/api/battles/results/read', b.token, { matchIds: ['result-win'], authorId: a.user.id })).readIds, []);
    const othersFeed = await api('/api/battles', b.token, null, 'GET');
    assert.equal(othersFeed.matches.some((item) => item.id === 'result-win'), false);
    const acknowledged = await api('/api/battles/results/read', a.token, { matchIds: ['result-win', 'test-battle', 'unknown'] });
    assert.deepEqual(acknowledged.readIds, ['result-win']);
    const again = (await api('/api/battles/results', a.token, null, 'GET')).results;
    assert.equal(again.find((result) => result.id === 'result-win').unread, false);
    assert.equal(again.find((result) => result.id === 'result-tie').unread, true);
    assert.equal((await fetch(base + '/api/battles/results')).status, 401);
    assert.equal((await fetch(base + '/api/battles/results/read', { method: 'POST' })).status, 401);
    const late = await fetch(base + '/api/battles/result-zero/vote', { method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${b.token}` }, body: JSON.stringify({ side: 'right' }) });
    assert.equal(late.status, 410);
  });
});
