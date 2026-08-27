const test = require('node:test');
const assert = require('node:assert/strict');
const { imageProxy } = require('./image_proxy');

function response() {
  return { code: 200, headers: {}, status(code) { this.code = code; return this; },
    setHeader(name, value) { this.headers[name] = value; }, send(body) { this.body = body; return this; } };
}

test('image proxy negotiates Flutter-compatible images and forwards bytes', async () => {
  const res = response();
  await imageProxy(async (url, options) => {
    assert.equal(url, 'https://example.com/photo');
    assert.equal(options.headers.Accept, 'image/webp,image/jpeg,image/png,image/gif');
    return new Response(new Uint8Array([1, 2, 3]), { headers: { 'Content-Type': 'image/webp' } });
  })({ query: { url: 'https://example.com/photo' } }, res);
  assert.equal(res.code, 200);
  assert.equal(res.headers['Content-Type'], 'image/webp');
  assert.deepEqual([...res.body], [1, 2, 3]);
});

test('image proxy rejects invalid URLs and non-image upstream data', async () => {
  const invalid = response();
  await imageProxy(() => { throw new Error('must not fetch'); })({ query: { url: 'file:///tmp/test' } }, invalid);
  assert.equal(invalid.code, 400);
  const html = response();
  await imageProxy(async () => new Response('<html>', { headers: { 'Content-Type': 'text/html' } }))(
    { query: { url: 'https://example.com/photo' } }, html);
  assert.equal(html.code, 415);
  assert.equal(html.headers['Cache-Control'], undefined);
});

test('image proxy returns a non-cacheable error on a failed request', async () => {
  const res = response();
  await imageProxy(async () => { throw new Error('timeout'); })(
    { query: { url: 'https://example.com/photo' } }, res);
  assert.equal(res.code, 502);
  assert.equal(res.headers['Cache-Control'], undefined);
});
