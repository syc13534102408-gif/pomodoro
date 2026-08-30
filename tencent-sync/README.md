# 松果云端同步（腾讯云版）

国内网络下 `workers.dev` 不可达，因此把同步后端从 Cloudflare Workers 迁到腾讯云。

## 架构

```
网页端 / 安卓端
      ↓ HTTPS
腾讯云 API 网关   https://{serviceId}.gz.apigw.tencentcs.com/release
      ↓
云函数 SCF        Node.js 18，内存 128MB，超时 20s
      ↓
COS 对象存储      sync/{deviceCode}.json
```

接口与 Cloudflare 版**完全一致**，两端只需改同步服务地址：

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/sync/upload` | body `{deviceCode, payload, baseUpdatedAt?}` → `{updatedAt}` |
| `GET` | `/sync/download?deviceCode=` | → `{payload, updatedAt}` |
| `GET` | `/ping` | 自检，返回 `provider: tencent-scf` |

冲突处理：`baseUpdatedAt` 与云端不一致时返回 `409 {conflict:true}`，不会静默覆盖。

## 前置条件

1. 腾讯云账号并**完成实名认证**
2. 开通三项服务（控制台里搜名字即可，均有免费额度）：
   - 云函数 SCF
   - 对象存储 COS
   - API 网关
3. 在「访问管理 → 访问密钥 → API 密钥管理」创建一对 `SecretId` / `SecretKey`

## 配置密钥（不要让密钥出现在聊天里）

```bash
mkdir -p ~/.tencentcloud
cat > ~/.tencentcloud/credentials <<'EOF'
TENCENTCLOUD_SECRET_ID=你的SecretId
TENCENTCLOUD_SECRET_KEY=你的SecretKey
EOF
chmod 600 ~/.tencentcloud/credentials
```

部署脚本会从该文件读取，密钥不会出现在命令行历史或对话中。

## 部署

```bash
cd tencent-sync
./deploy.sh             # 首次：建桶 + 建函数 + 建网关并发布
./deploy.sh --update    # 之后：只更新函数代码
```

脚本会自动安装 `tccli`（腾讯云官方 CLI）。部署完成后输出形如：

```
https://service-xxxx.gz.apigw.tencentcs.com/release/ping
```

去掉末尾 `/ping`，就是同步服务地址。

## 接入两端

- **网页端**：设置 → 后台提醒设置弹窗里的「Worker 地址」，或让 `index.html` 中的 `DEFAULT_PUSH_WORKER_URL` 改为该地址
- **安卓端**：设置 → 云端同步 → 同步服务地址

两端的设备同步码是同一套规则（16–128 位），迁移后原有同步码仍可继续使用，但**云端数据不互通**——需要在新服务上重新上传一次。

## 费用

个人使用量级（每天几十次请求、几 KB 存储）在免费额度内：

| 服务 | 免费额度 |
|---|---|
| 云函数 SCF | 每月 100 万次请求 + 40 万 GBs 资源使用量 |
| COS 存储 | 新用户 6 个月 50GB 标准存储 + 若干外网下行流量 |
| API 网关 | 每月 100 万次调用 |

额度政策由腾讯云调整，以控制台「费用中心」为准。建议设置一个费用告警。

## 注意事项

- **后台提醒仍走 Cloudflare**：网页端的 Web Push 依赖 Cloudflare Durable Objects 的精确定时，腾讯云函数的定时触发器最小粒度是 1 分钟，做不到准点。手机端用本地通知 + 前台服务，本来就不依赖云端。
- **数据仍以本机为准**：同步只是备份与跨设备搬运，日常读写全在本地，断网也能用。
- COS 桶名形如 `pine-sync-{AppId}`，脚本会自动生成，不要手动改。
