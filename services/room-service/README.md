# FOLDLIGHT 好友无尽房间服务

独立的 Cloudflare Worker + D1 后台，供 Windows、Android 和网页使用同一组房间。仅承载房间、准备倒数、心跳和成绩；不承载游戏资源。源码不依赖 Sites、React 或 Godot，D1 绑定在每次请求内独立使用。

## 当前部署

2026-10-17 已部署到 Workers Free：

- 服务入口：<https://foldlight-room-service.foldlight-papersea-2026.workers.dev>
- 健康检查：`GET /health`；返回服务名、规则版本和 DB 绑定是否存在，不查询数据库。
- Worker 名：`foldlight-room-service`。
- D1 名：`foldlight-rooms`，绑定名为 `DB`。
- 规则版本：`endless_race_v5`，双人比赛、统一倒数 5 秒、断线 30 秒判负。

生产 D1 ID 和账户配置保留在本机忽略文件或 Cloudflare 控制台中。仓库内 `wrangler.jsonc` 的全零 ID 仅供本地开发，不是生产配置。公开 Worker 地址不代表已验证所有中国大陆运营商；面向大陆朋友的网页继续通过腾讯入口代理访问。

## 配置与转发

| 位置 | 配置项 | 值或作用 |
| --- | --- | --- |
| Worker | `DB` | 必需的 D1 数据库绑定，名称固定；不是字符串环境变量。 |
| Sites 站点 | `FOLDLIGHT_ROOM_SERVICE_URL` | 设置为上面的 Worker HTTPS origin，让 `/api/rooms` 路由使用独立后台。该值不含路径或鉴权信息。 |
| 腾讯 EdgeOne 网页工程 | `ROOM_SERVICE` | `foldlight-portable-web/lib/room-relay.mjs` 中的固定上游，设置为相同 Worker origin，并同步构建出的边缘函数。当前是源码常量，不是后台自动读取的环境变量。 |
| Wrangler 部署环境 | Cloudflare 登录会话，或 `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` | 只用于授权部署工具；不要写进源码、README、客户端或上传包。Worker 不需要这些值。 |

浏览器先访问自己网站的同源房间接口。代理必须保留 HTTP 方法、房间路径、JSON body 和 `Authorization: Bearer ...`，并把 `Origin` 设置为 Worker 自己的 origin。不要把腾讯预览签名、Cookie 或任意客户端指定的上游地址转发给 Worker。原生客户端可以不发送 `Origin`。

所有入口应指向这一个后台，才能共享房间。已有 Sites 本地房间数据库不会自动迁移；切换后台后需重新建房。

## 接口

| 方法和路径 | 用途 |
| --- | --- |
| `POST /api/rooms` | 创建房间，返回自己的令牌和房间快照。 |
| `POST /api/rooms/:code` | `join`、`ready`、`heartbeat`、`leave`。加入之外的操作需要成员令牌。 |
| `GET /api/rooms/:code` | 读取快照，需要成员令牌。 |
| `GET /health` | 无敏感信息的配置检查。 |

房间码为 7 位；响应禁止缓存。请求体限制为 4096 字节。玩家令牌只保存摘要，快照不包含对手令牌或加载实例标识。心跳规则、参数和返回结构与现有 `endless_race_v5` 客户端一致。

新增 `0002_room_rules.sql` 为每个房间保存规则版本。缺省版本的旧客户端仍创建 `v3` 房间；3.14 客户端在建房／加入时明确发送 `v5`。旧 `v3`、`v4` 房间继续通信，三种规则互相隔离，在占用名额前拒绝不匹配版本；无需修改已有数据库。

SQL 更新检查当前房间阶段，并保持生存时间、击破数和连接时间单调。结算只提交与读取时相符的双方状态；并发更新导致快照失效时重新读取，防止迟到心跳改写已经结束的比赛。

## 本地开发

需要 Node.js 24 或更新版本。在本目录执行：

```sh
npm install
npm run db:local
npm run dev
```

开发服务只监听 `127.0.0.1:5188`，使用 `.wrangler/state` 内的本地 D1。若其他工作区副本正在使用这个端口，先停止自己的旧开发进程或给 Wrangler 另选端口；不同副本的本地数据库相互独立。

```sh
npm run typecheck
npm test
npm run test:api
npm run bundle:local
```

`test:api` 默认使用 `http://127.0.0.1:5188`，也可通过 `RACE_API_BASE` 指定其他 HTTP 回环地址；脚本拒绝公开服务器。完整测试创建 4 个房间，约 36 秒，包含真实 30 秒断线场景。`bundle:local` 仅打包预览，不上传。

## 更新生产服务

保持账户使用 Workers Free，不启用付费升级。复制 `wrangler.jsonc` 为本机的 `wrangler.production.jsonc`，将 D1 ID 替换为控制台中现有 `foldlight-rooms` 的真实 ID。不要为日常发布新建数据库。

```sh
npx wrangler d1 migrations apply DB --remote --config wrangler.production.jsonc
npx wrangler deploy --config wrangler.production.jsonc
```

迁移和部署是独立的远程操作，不在本地测试脚本中自动执行。新增数据库变更应追加迁移文件，不能修改已经应用的迁移。发布后检查 `/health` 和经过实际游戏入口的房间创建、加入、准备与结算。

不提交 `node_modules`、`.wrangler`、本地 `build`、环境凭据或生产配置。Wrangler 上传源码打包结果；SQL 迁移另行应用，不上传整个工作区。

## 免费额度与验证范围

按 2026-10-17 查阅的官方说明，Workers Free 为每日 10 万请求；D1 为每日 500 万读行、10 万写行。双人各每秒一次心跳约使用每小时 7200 请求，另加建房和准备操作。这些额度由账户内服务共享，适合少量好友；D1 到达免费限额会拒绝查询，需等待额度恢复。详见 [Workers 定价](https://developers.cloudflare.com/workers/platform/pricing/)和 [D1 免费额度说明](https://developers.cloudflare.com/d1/reference/faq/)。

现有建房限额为每个服务端观察到的源 IP 每小时 20 个。通过腾讯代理的玩家可能共享代理出口 IP 和这个限额；不能直接信任客户端自报的 IP 来绕过限制。

维护时已通过类型检查、9 项入口/并发/版本隔离单元测试、54 项真实本地 D1 API 断言。4 个控制请求交错的并发测试能在原始 API 上复现失败，在当前实现上通过。覆盖来源验证、环境隔离、准备实例绑定、倒数、公平计时、平局、弃赛、断线与不可回滚终态。本地通过不替代公网、真机和大陆网络验证。
