function imageProxy(fetchImage = fetch) {
  return async (req, res) => {
    const rawUrl = String(req.query.url || '').trim();
    if (!/^https?:\/\//i.test(rawUrl)) return res.status(400).send('Invalid image URL');
    try {
      const upstream = await fetchImage(rawUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36',
          // CanvasKit cannot decode all formats negotiated by desktop browsers.
          Accept: 'image/webp,image/jpeg,image/png,image/gif',
        },
        signal: AbortSignal.timeout(8000),
      });
      if (!upstream.ok) return res.status(502).send('Image upstream error');
      const contentType = upstream.headers.get('content-type') || 'image/jpeg';
      if (!contentType.toLowerCase().startsWith('image/')) {
        return res.status(415).send('URL is not an image');
      }
      const buffer = Buffer.from(await upstream.arrayBuffer());
      res.setHeader('Content-Type', contentType);
      res.setHeader('Cache-Control', 'public, max-age=86400');
      res.setHeader('Access-Control-Allow-Origin', '*');
      return res.send(buffer);
    } catch (_) {
      return res.status(502).send('Image proxy failed');
    }
  };
}

module.exports = { imageProxy };
