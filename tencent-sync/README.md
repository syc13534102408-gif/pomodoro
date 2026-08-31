# 松果云端同步（腾讯云版）

国内网络下 `workers.dev` 不可达，因此把同步后端从 Cloudflare Workers 迁到腾讯云。

## 架构

```
网页端 / 安卓端
      ↓ HTTPS
腾讯云函数 URL      https://...scf.tencentcs.com/...   （SCF 自带 HTTP 触发器）
      ↓
云函数 SCF          Node.js 18，内存 128MB，超时 20s
      ↓
COS 对象存储        sync/{deviceCode}.json
```

> **API 网关已于 2025-06-30 停服**，本项目不使用它，改用 SCF 的「函数 URL」触发器。

接口与 Cloudflare 版**完全一致**，两端只需改同步服务地址：

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/sync/upload` | body `{deviceCode, payload, baseUpdatedAt?}` → `{updatedAt}` |
| `GET` | `/sync/download?deviceCode=` | → `{payload, updatedAt}` |
| `GET` | `/ping` | 自检，返回 `provider: tencent-scf` |

冲突处理：`baseUpdatedAt` 与云端不一致时返回 `409 {conflict:true}`，不会静默覆盖。

## 前置条件

1. 腾讯云账号并**完成实名认证**
2. 开通两项服务（控制台搜索即可，均有免费额度）：
   - 云函数 SCF
   - 对象存储 COS
3. 在控制台 **创建一个 COS 存储桶**（地域选广州，访问权限选「私有读写」）。
   桶名形如 `pine-sync-1258000000`，末尾 AppId 控制台会显示
4. 在「访问管理 → 访问密钥 → API 密钥管理」创建一对 `SecretId` / `SecretKey`

## 配置密钥

密钥**不通过命令行传入，也不经过对话**。脚本从以下文件读取：

```bash
mkdir -p ~/.tencentcloud
cat > ~/.tencentcloud/credentials <<'EOF'
TENCENTCLOUD_SECRET_ID=你的SecretId
TENCENTCLOUD_SECRET_KEY=你的SecretKey
EOF
chmod 600 ~/.tencentcloud/credentials
```

## 部署

```bash
cd tencent-sync

# 本机隔离环境里的 Python（已装好腾讯云 SDK）
PY=/Users/shuyichen/.workbuddy/binaries/python/envs/default/bin/python

COS_BUCKET=你的桶名 $PY deploy.py            # 创建并部署
COS_BUCKET=你的桶名 $PY deploy.py --update   # 只更新代码
```

脚本依次：读取密钥 → 校验身份 → 打包代码 → 创建/更新函数 → 建 HTTP 触发器 → 输出公网地址。

地址会写入 `.last-url`。部署后验证：

```bash
curl "$(cat .last-url)/ping"
# 期望 {"ok":true,"provider":"tencent-scf",...}
```

若自动创建触发器失败，在控制台手动添加：函数详情 → 触发管理 → 创建触发器 → HTTP 触发器（认证方式选「免鉴权」）。

## 接入两端

拿到地址后（去掉末尾 `/ping`）：

- **网页端**：`index.html` 中的 `DEFAULT_PUSH_WORKER_URL`
- **安卓端**：`lib/src/cloud_sync.dart` 中的 `CloudSync.defaultBaseUrl`

然后重新构建 APK（`flutter build apk --release`）并用 adb 安装，网页端推送到 GitHub Pages。

设备同步码规则不变（16–128 位），但**云端数据不互通**——需要在新服务上重新上传一次。

## 为什么不用 tccli

腾讯云官方 CLI `tccli` 依赖 `cos-python-sdk-v5`，后者依赖 `crcmod`（只有源码包，需本地编译）。本机环境下 pip 构建时清理临时目录会被删除保护拦截，报 `EEXIST` 而安装失败。

因此改用 `tencentcloud-sdk-python-scf` 直接调 API，纯 wheel 无编译步骤。代价是 **COS 桶需要在控制台手动创建**（桶管理 API 不在该 SDK 内）。

## 费用

个人使用量级（每天几十次请求、几 KB 存储）在免费额度内：

| 服务 | 免费额度 |
|---|---|
| 云函数 SCF | 每月 100 万次请求 + 40 万 GBs 资源使用量 |
| COS 存储 | 新用户 6 个月 50GB 标准存储 + 若干外网下行流量 |

额度政策由腾讯云调整，以控制台「费用中心」为准。建议设置费用告警。

## 注意事项

- **后台提醒仍走 Cloudflare**：网页端 Web Push 依赖 Durable Objects 的精确定时，腾讯云定时触发器最小粒度 1 分钟，做不到准点。手机端用本地通知 + 前台服务，本就不依赖云端。
- **数据仍以本机为准**：同步只是备份与跨设备搬运，日常读写全在本地，断网也能用。
