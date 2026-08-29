# 松果后台提醒与云端备份 Worker

这个 Worker 使用 Durable Object Alarm 在番茄钟结束时发送标准 Web Push，并使用 D1 保存用户手动上传的松果数据备份。网页继续部署在 GitHub Pages；本机数据不会因上传而删除。

## 部署

1. `npm install`
2. `npx wrangler login`
3. 创建 D1 数据库并初始化表：
   ```sh
   npx wrangler d1 create pine-pomodoro-sync
   npx wrangler d1 execute pine-pomodoro-sync --remote --file=schema.sql
   ```
   将创建命令输出的 `database_id` 填入 `wrangler.jsonc` 的 `d1_databases` 配置。
4. `npx web-push generate-vapid-keys`
5. 设置 Secrets：
   ```sh
   npx wrangler secret put VAPID_PUBLIC_KEY
   npx wrangler secret put VAPID_PRIVATE_KEY
   npx wrangler secret put VAPID_SUBJECT
   npx wrangler secret put ALLOWED_ORIGIN
   ```
   `ALLOWED_ORIGIN` 填入 `https://syc13534102408-gif.github.io`。
6. `npm run deploy`
7. 将输出的 Worker URL 填入网页「数据与提醒 → 配置后台提醒」。默认地址已内置。

VAPID 私钥只能保存在 Cloudflare Secret，绝不能放进 GitHub Pages 或提交到 Git。
