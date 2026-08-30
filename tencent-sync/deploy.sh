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
  say "创建 API 网关"
  SERVICE_ID=$(tccli apigw DescribeServicesStatus --Region "$REGION" --Limit 100 --output json 2>/dev/null \
    | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for s in d.get('ServiceSet',[]):
        if s.get('ServiceName')=='$SERVICE_NAME':
            print(s.get('ServiceId','')); break
except Exception: pass
" 2>/dev/null || echo "")

  if [ -z "$SERVICE_ID" ]; then
    SERVICE_ID=$(tccli apigw CreateService --Region "$REGION" \
      --ServiceName "$SERVICE_NAME" \
      --Protocol "http&https" --ServiceDesc "松果番茄钟同步" \
      --output json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('ServiceId',''))" 2>/dev/null || echo "")
    echo "已创建服务: $SERVICE_ID"
  else
    echo "服务已存在: $SERVICE_ID"
  fi

  if [ -n "$SERVICE_ID" ]; then
    for API in "/sync/upload:POST" "/sync/download:GET" "/ping:GET"; do
      P="${API%%:*}"; M="${API##*:}"
      tccli apigw CreateApi --Region "$REGION" --ServiceId "$SERVICE_ID" \
        --ApiName "sync${P//\//_}" --ApiType NORMAL --ApiBusinessType NORMAL \
        --AuthType NONE --Protocol HTTP --RequestConfig "{\"Path\":\"$P\",\"Method\":\"$M\"}" \
        --ServiceType SCF --ServiceTimeout 20 \
        --ServiceScfFunctionName "$FUNCTION_NAME" \
        --ServiceScfFunctionNamespace default --ServiceScfFunctionQualifier '$DEFAULT' \
        >/dev/null 2>&1 && echo "  接口已注册: $M $P" || echo "  接口可能已存在: $M $P"
    done

    tccli apigw ReleaseService --Region "$REGION" \
      --ServiceId "$SERVICE_ID" --EnvironmentName release --ReleaseDesc "首次发布" \
      >/dev/null 2>&1 && echo "✅ 网关已发布" || echo "发布可能已完成"

    echo
    echo "访问地址（发布后约 1 分钟生效）："
    echo "  https://${SERVICE_ID}.gz.apigw.tencentcs.com/release/ping"
  fi
fi

say "完成"
echo "下一步：把上面 /ping 的地址（去掉 /ping）填进网页端和安卓端的同步服务地址。"
