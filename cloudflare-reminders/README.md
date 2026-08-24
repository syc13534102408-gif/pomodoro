# 松果后台提醒 Worker

这个 Worker 使用 Durable Object Alarm 在番茄钟结束时发送标准 Web Push；网页继续部署在 GitHub Pages，不上传任何专注记录。

## 部署

1. `npm install`
2. `npx wrangler login`
3. `npx web-push generate-vapid-keys`
4. 设置 Secrets：
   ```sh
   npx wrangler secret put VAPID_PUBLIC_KEY
   npx wrangler secret put VAPID_PRIVATE_KEY
   npx wrangler secret put VAPID_SUBJECT
   npx wrangler secret put ALLOWED_ORIGIN
   ```
   `ALLOWED_ORIGIN` 填入 `https://syc13534102408-gif.github.io`。
5. `npm run deploy`
6. 将输出的 Worker URL 填入网页「数据与提醒 → 配置后台提醒」。

VAPID 私钥只能保存在 Cloudflare Secret，绝不能放进 GitHub Pages 或提交到 Git。
