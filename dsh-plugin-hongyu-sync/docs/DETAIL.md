# 鸿语同步桥

把鸿语 HarmonyOS App 里的文字对话同步到 DeepSeek Harness，并把 DSH 当前对话导出到手机。

## 使用

1. 保持电脑与手机在同一个局域网。
2. 在 DSH 对话框中让助手调用 `hongyu_sync`：
   - `action: "status"`：返回电脑局域网地址、端口和配对码；
   - `action: "export_current"`：把当前 DSH 对话导出到同步库；
   - `action: "list"`：列出同步库中的对话；
   - `action: "read"`：读取某个同步对话的全文。
3. 在鸿语 App 的「设置 → DSH 同步」中填写电脑 IP、端口 `17860` 和配对码，点「测试连接」，再点「立即同步」。
4. 手机上的对话会推送到插件；在 DSH 中导出的对话会在手机同步时拉取。

## 工作方式

- 插件在本机启动一个局域网 HTTP 服务，默认 `0.0.0.0:17860`。
- 首次启动时在 `~/.dsh/hongyu-sync/token.txt` 生成随机配对码；也可用环境变量覆盖：
  - `HONGYU_SYNC_HOST`（默认 `0.0.0.0`）
  - `HONGYU_SYNC_PORT`（默认 `17860`）
  - `HONGYU_SYNC_TOKEN`（默认读取/生成 token 文件）
  - `HONGYU_SYNC_DIR`（默认 `~/.dsh/hongyu-sync`）
- 同步库保存在 `conversations.json`，同时为每个对话生成 Markdown 到 `exports/` 目录，方便直接查看。
- 只同步文字。手机图片不会上传；DSH 侧图片以 `[图片]` 占位。

## 安全

- 除 `/health` 外的接口都要求 `Authorization: Bearer <配对码>`。
- 默认监听局域网所有网卡，配对码随机生成。请只在可信任的 Wi-Fi 使用，并为端口配置防火墙规则。
- 如果不需要时，可在 DSH 插件设置中停用本插件，HTTP 服务会随插件卸载关闭。

## 限制

- 不镜像 DSH 原生 Session，手机拉取到的是同步库中的对话副本。
- 不做公网穿透、账号体系、多人协作或图片/文件传输。
- 局域网 IP、防火墙和路由器隔离可能阻止连接，此时请检查网络或手动放行 TCP 17860。
