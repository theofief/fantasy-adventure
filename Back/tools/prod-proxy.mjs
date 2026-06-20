import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';

const listenHost = process.env.PROD_PROXY_HOST || '0.0.0.0';
const httpPort = Number(process.env.PROD_PROXY_HTTP_PORT || 80);
const httpsPort = Number(process.env.PROD_PROXY_HTTPS_PORT || 443);
const targetHost = process.env.PROD_PROXY_TARGET_HOST || '127.0.0.1';
const targetPort = Number(process.env.PROD_PROXY_TARGET_PORT || 8081);
const certPath = process.env.PROD_PROXY_CERT || 'var/prod-certs/fantasy-adventure.crt';
const keyPath = process.env.PROD_PROXY_KEY || 'var/prod-certs/fantasy-adventure.key';

function normalizeHost(hostHeader) {
  if (!hostHeader) {
    return `${listenHost}:${httpsPort}`;
  }

  return hostHeader.replace(/:\d+$/, httpsPort === 443 ? '' : `:${httpsPort}`);
}

function proxyRequest(clientReq, clientRes) {
  const forwardedHost = clientReq.headers.host || `${listenHost}:${httpsPort}`;
  const proxyReq = http.request(
    {
      host: targetHost,
      port: targetPort,
      method: clientReq.method,
      path: clientReq.url,
      headers: {
        ...clientReq.headers,
        host: forwardedHost,
        'x-forwarded-proto': 'https',
        'x-forwarded-host': forwardedHost,
      },
    },
    (proxyRes) => {
      clientRes.writeHead(proxyRes.statusCode || 500, proxyRes.headers);
      proxyRes.pipe(clientRes);
    },
  );

  proxyReq.on('error', (error) => {
    clientRes.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    clientRes.end(`Production proxy error: ${error.message}`);
  });

  clientReq.pipe(proxyReq);
}

const httpsServer = https.createServer(
  {
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
  },
  proxyRequest,
);

const httpServer = http.createServer((req, res) => {
  const host = normalizeHost(req.headers.host);
  res.writeHead(308, {
    location: `https://${host}${req.url || '/'}`,
    'cache-control': 'no-store',
  });
  res.end();
});

httpsServer.listen(httpsPort, listenHost, () => {
  console.log(`HTTPS production proxy listening on https://${listenHost}:${httpsPort}`);
  console.log(`Proxying to http://${targetHost}:${targetPort}`);
});

httpServer.listen(httpPort, listenHost, () => {
  console.log(`HTTP redirect listening on http://${listenHost}:${httpPort}`);
});
