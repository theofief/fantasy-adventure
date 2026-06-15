import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';

const listenHost = process.env.HTTPS_PROXY_HOST || '0.0.0.0';
const listenPort = Number(process.env.HTTPS_PROXY_PORT || 8000);
const targetHost = process.env.HTTPS_PROXY_TARGET_HOST || '127.0.0.1';
const targetPort = Number(process.env.HTTPS_PROXY_TARGET_PORT || 8001);
const certPath = process.env.HTTPS_PROXY_CERT || 'var/dev-certs/fantasy-adventure.crt';
const keyPath = process.env.HTTPS_PROXY_KEY || 'var/dev-certs/fantasy-adventure.key';

const server = https.createServer(
  {
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
  },
  (clientReq, clientRes) => {
    const proxyReq = http.request(
      {
        host: targetHost,
        port: targetPort,
        method: clientReq.method,
        path: clientReq.url,
        headers: {
          ...clientReq.headers,
          host: `${targetHost}:${targetPort}`,
          'x-forwarded-proto': 'https',
          'x-forwarded-host': clientReq.headers.host || `${listenHost}:${listenPort}`,
        },
      },
      (proxyRes) => {
        clientRes.writeHead(proxyRes.statusCode || 500, proxyRes.headers);
        proxyRes.pipe(clientRes);
      },
    );

    proxyReq.on('error', (error) => {
      clientRes.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
      clientRes.end(`HTTPS proxy error: ${error.message}`);
    });

    clientReq.pipe(proxyReq);
  },
);

server.listen(listenPort, listenHost, () => {
  console.log(`HTTPS proxy listening on https://${listenHost}:${listenPort}`);
  console.log(`Proxying to http://${targetHost}:${targetPort}`);
});
