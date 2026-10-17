import { createRoomService } from './race-server.ts';
import { CODE_PATTERN, RACE_RULES_VERSION } from './race-rules.ts';

export interface Env { DB: D1Database }

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get('origin');
    // Native clients omit Origin. The same-origin Tencent relay replaces it
    // with this backend's origin; arbitrary browser origins remain rejected.
    if (origin && origin !== url.origin) return json({ error: '请从当前游戏发起操作。' }, 403);
    if (url.pathname === '/health' && request.method === 'GET') {
      return json({ service: 'foldlight-rooms', rulesVersion: RACE_RULES_VERSION, configured: Boolean(env.DB) });
    }
    const pathname = url.pathname.replace(/\/$/, '');
    const collection = pathname === '/api/rooms';
    const match = /^\/api\/rooms\/([^/]+)$/.exec(pathname);
    if (!collection && !match) return json({ error: '房间地址不正确。' }, 404);
    if (match && !CODE_PATTERN.test(match[1])) return json({ error: '房间码为 7 位字母或数字。' }, 400);
    if (request.method !== 'POST' && !(match && request.method === 'GET')) {
      return json({ error: '不支持此操作。' }, 405);
    }
    if (!env.DB) return json({ error: '房间服务尚未配置。' }, 503);
    // Every invocation captures its own binding. Never assign env/DB to a
    // module global: overlapping requests and test environments must isolate.
    const rooms = createRoomService(env.DB);
    if (collection) return rooms.createRoom(request);
    return request.method === 'GET'
      ? rooms.getRoom(request, match![1])
      : rooms.updateRoom(request, match![1]);
  },
};
