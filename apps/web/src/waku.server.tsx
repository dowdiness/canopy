import { fsRouter } from 'waku';
import adapter from 'waku/adapters/cloudflare';
import { createWakuRequestMiddleware } from '../server/waku/signaling-proxy.ts';

export default adapter(
  fsRouter(import.meta.glob('./pages/**/*.{tsx,ts}')),
  {
    middlewareFns: [({ app }) => createWakuRequestMiddleware({ app })],
  },
);
