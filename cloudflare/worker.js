const ORIGIN = "https://your-ingest-service.example.com";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/stream/") && !url.pathname.startsWith("/download/")) {
      return fetch(request);
    }

    const originUrl = new URL(url.pathname + url.search, ORIGIN);
    const cache = caches.default;
    const cacheKey = new Request(originUrl.toString(), request);
    const cached = await cache.match(cacheKey);
    if (cached) {
      return cached;
    }

    const response = await fetch(originUrl, {
      method: request.method,
      headers: request.headers,
    });
    const headers = new Headers(response.headers);
    headers.set("Cache-Control", "public, max-age=3600, s-maxage=86400");
    headers.set("CDN-Cache-Control", "public, max-age=86400");
    headers.set("Access-Control-Allow-Origin", "*");

    const proxied = new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
    if (request.method === "GET" && response.ok) {
      ctx.waitUntil(cache.put(cacheKey, proxied.clone()));
    }
    return proxied;
  },
};
