#!/usr/bin/env bash
# 松果同步服务部署到腾讯云（SCF 云函数 + COS 对象存储 + API 网关）
#
# 密钥不通过命令行传入，而是读取 ~/.tencentcloud/credentials：
#   TENCENTCLOUD_SECRET_ID=AKIDxxxxxxxx
#   TENCENTCLOUD_SECRET_KEY=xxxxxxxx
#
# 用法：
#   ./deploy.sh              # 首次部署（建桶 + 建函数 + 建网关）
#   ./deploy.sh --update     # 只更新函数代码

set -euo pipefail

REGION="${REGION:-ap-guangzhou}"
FUNCTION_NAME="${FUNCTION_NAME:-pine-pomodoro-sync}"
SERVICE_NAME="${SERVICE_NAME:-pine-pomodoro-sync}"
COS_BUCKET="${COS_BUCKET:-}"
MODE="${1:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
CRED_FILE="$HOME/.tencentcloud/credentials"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m错误: %s\033[0m\n' "$1" >&2; exit 1; }

say "检查密钥文件"
[ -f "$CRED_FILE" ] || die "缺少 $CRED_FILE
请创建该文件并写入两行（不要有空格）：
  TENCENTCLOUD_SECRET_ID=你的SecretId
  TENCENTCLOUD_SECRET_KEY=你的SecretKey
然后执行: chmod 600 $CRED_FILE"

set -a; . "$CRED_FILE"; set +a
[ -n "${TENCENTCLOUD_SECRET_ID:-}" ] || die "$CRED_FILE 中缺少 TENCENTCLOUD_SECRET_ID"
[ -n "${TENCENTCLOUD_SECRET_KEY:-}" ] || die "$CRED_FILE 中缺少 TENCENTCLOUD_SECRET_KEY"
echo "SecretId: ${TENCENTCLOUD_SECRET_ID:0:8}…（已读取，完整值不会显示）"

say "检查 tccli"
if ! command -v tccli >/dev/null 2>&1; then
  echo "未找到 tccli，尝试安装…"
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install --user tccli 2>&1 | tail -3
    export PATH="$PATH:$HOME/Library/Python/3.9/bin:$HOME/.local/bin"
  else
    die "请手动安装 tccli: pip3 install tccli"
  fi
fi
command -v tccli >/dev/null 2>&1 || die "tccli 安装失败"

export TENCENTCLOUD_SECRET_ID TENCENTCLOUD_SECRET_KEY
tccli configure set secretId "$TENCENTCLOUD_SECRET_ID" region "$REGION" >/dev/null 2>&1
tccli configure set secretKey "$TENCENTCLOUD_SECRET_KEY" region "$REGION" >/dev/null 2>&1

say "验证密钥"
APPID=$(tccli sts GetCallerIdentity --output json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('AccountId',''))" 2>/dev/null || echo "")
[ -n "$APPID" ] || die "密钥无效或无权限，请到腾讯云控制台确认已启用"
echo "账号 AppId: $APPID"

if [ -z "$COS_BUCKET" ]; then
  COS_BUCKET="pine-sync-${APPID}"
fi
echo "存储桶: $COS_BUCKET"

if [ "$MODE" != "--update" ]; then
  say "创建 COS 存储桶"
  if tccli cos HeadBucket --Bucket "$COS_BUCKET" --Region "$REGION" >/dev/null 2>&1; then
    echo "桶已存在，跳过"
  else
    tccli cos PutBucket --Bucket "$COS_BUCKET" --Region "$REGION" >/dev/null 2>&1 \
      && echo "已创建" || echo "创建返回非成功（可能已存在），继续"
  fi
fi

say "打包函数代码"
cd "$HERE"
rm -rf .deploy && mkdir -p .deploy
npm install --omit=dev --silent 2>&1 | tail -3 || true
cp -r src/* node_modules .deploy/ 2>/dev/null || true
cd .deploy && zip -qr ../function.zip . && cd ..
SIZE=$(du -h function.zip | awk '{print $1}')
echo "打包完成: function.zip ($SIZE)"

say "部署云函数"
if [ "$MODE" == "--update" ]; then
  tccli scf UpdateFunctionCode \
    --Region "$REGION" \
    --FunctionName "$FUNCTION_NAME" \
    --ZipFile "fileb://$HERE/function.zip" >/dev/null 2>&1 \
    && echo "✅ 代码已更新" || echo "更新失败，函数可能还不存在，请先完整部署"
else
  tccli scf CreateFunction \
    --Region "$REGION" \
    --FunctionName "$FUNCTION_NAME" \
    --Runtime "Nodejs18.15" \
    --Handler "index.main_handler" \
    --Timeout 20 \
    --MemorySize 128 \
    --ZipFile "fileb://$HERE/function.zip" \
    --Environment "{\"Variables\":[{\"Key\":\"COS_BUCKET\",\"Value\":\"$COS_BUCKET\"},{\"Key\":\"COS_REGION\",\"Value\":\"$REGION\"},{\"Key\":\"ALLOWED_ORIGINS\",\"Value\":\"https://syc13534102408-gif.github.io\"}]}" \
    >/dev/null 2>&1 \
    && echo "✅ 函数已创建" || echo "函数可能已存在，尝试更新代码"

  tccli scf UpdateFunctionConfiguration \
    --Region "$REGION" \
    --FunctionName "$FUNCTION_NAME" \
    --Environment "{\"Variables\":[{\"Key\":\"COS_BUCKET\",\"Value\":\"$COS_BUCKET\"},{\"Key\":\"COS_REGION\",\"Value\":\"$REGION\"},{\"Key\":\"ALLOWED_ORIGINS\",\"Value\":\"https://syc13534102408-gif.github.io\"}]}" \
    >/dev/null 2>&1 || true
fi

if [ "$MODE" != "--update" ]; then
  say "创建 HTTP 触发器（函数 URL）"
  echo "注意：腾讯云 API 网关已于 2025-06-30 停服，改用 SCF 自带的函数 URL。"

  # 先查是否已有 http 触发器
  EXISTING=$(tccli scf ListTriggers --Region "$REGION" --FunctionName "$FUNCTION_NAME" --output json 2>/dev/null \
    | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for t in d.get('Triggers',[]):
        if t.get('Type')=='http':
            print(t.get('TriggerName',''))
except Exception: pass
" 2>/dev/null || echo "")

  if [ -z "$EXISTING" ]; then
    tccli scf CreateTrigger \
      --Region "$REGION" \
      --FunctionName "$FUNCTION_NAME" \
      --Type http \
      --Qualifier '$DEFAULT' \
      --TriggerDesc '{"netConfig":{"enableIntranet":false,"enableExtranet":true},"authType":"NONE"}' \
      --output json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print('  ✅ 触发器已创建:', d.get('TriggerInfo',{}).get('TriggerName','ok'))
except Exception:
    print('  触发器创建返回无法解析，请在控制台确认')
" || echo "  自动创建失败，请改用控制台手动添加"
  else
    echo "  触发器已存在: $EXISTING"
  fi

  say "获取公网地址"
  URL=$(tccli scf GetFunctionAddress --Region "$REGION" --FunctionName "$FUNCTION_NAME" --Qualifier '$DEFAULT' --output json 2>/dev/null \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('Url',''))" 2>/dev/null || echo "")

  if [ -n "$URL" ]; then
    echo "  $URL"
    echo "$URL" > "$HERE/.last-url"
  else
    echo "  自动获取失败。请在控制台获取："
    echo "    云函数 → $FUNCTION_NAME → 触发管理 → HTTP 触发器"
    echo "    复制「访问路径」后执行："
    echo "      echo '你的URL' > $HERE/.last-url"
  fi
fi

say "完成"
if [ -f "$HERE/.last-url" ]; then
  echo "同步服务地址：$(cat "$HERE/.last-url")"
  echo "（已保存到 $HERE/.last-url）"
fi
echo "下一步：把该地址填进网页端和安卓端的同步服务地址，然后验证 /ping 返回 provider=tencent-scf。"
