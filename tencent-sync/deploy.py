#!/usr/bin/env python3
"""把松果同步服务部署到腾讯云云函数 SCF。

密钥从 ~/.tencentcloud/credentials 读取，不通过命令行传入：
    TENCENTCLOUD_SECRET_ID=...
    TENCENTCLOUD_SECRET_KEY=...

用法：
    python3 deploy.py            # 部署（不存在则创建，已存在则更新代码）
    python3 deploy.py --update   # 只更新代码

云函数的 HTTP 入口使用 SCF 自带的「函数 URL」触发器，
不依赖已于 2025-06-30 停服的 API 网关。
"""

import base64
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
CRED_FILE = os.path.expanduser("~/.tencentcloud/credentials")

REGION = os.environ.get("REGION", "ap-guangzhou")
FUNCTION_NAME = os.environ.get("FUNCTION_NAME", "pine-pomodoro-sync")
COS_BUCKET = os.environ.get("COS_BUCKET", "")          # 形如 pine-sync-1258000000
ALLOWED_ORIGINS = os.environ.get(
    "ALLOWED_ORIGINS", "https://syc13534102408-gif.github.io"
)


def say(msg):
    print(f"\n\033[1m==> {msg}\033[0m")


def variable(key, value):
    """构造环境变量对象。

    本 SDK 版本的模型构造函数不接受关键字参数（只有无参 __init__ + property），
    因此必须创建后逐个赋值。写成 helper 是为了在两种 SDK 版本下都能工作。
    """
    from tencentcloud.scf.v20180416 import models

    var = models.Variable()
    var.Key = key
    var.Value = value
    return var


def wait_until_active(client, models, timeout=90):
    """函数刚创建时状态是 Creating，此时建触发器/取地址都会失败，需要等就绪。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req = models.GetFunctionRequest()
            req.FunctionName = FUNCTION_NAME
            resp = client.GetFunction(req)
            status = getattr(resp, "Status", "") or ""
            if status not in ("Creating", "Updating", ""):
                print(f"  函数状态: {status}")
                return True
        except Exception:  # noqa: BLE001
            pass
        print("  等待函数就绪…")
        time.sleep(3)
    print("  （等待超时，继续尝试）")
    return False


def env_object(vars_list):
    from tencentcloud.scf.v20180416 import models

    env = models.Environment()
    env.Variables = vars_list
    return env


def die(msg):
    print(f"\n\033[31m错误: {msg}\033[0m", file=sys.stderr)
    sys.exit(1)


def load_credentials():
    if not os.path.isfile(CRED_FILE):
        die(
            f"缺少 {CRED_FILE}\n"
            "请创建该文件并写入两行（等号两侧不要有空格）：\n"
            "  TENCENTCLOUD_SECRET_ID=你的SecretId\n"
            "  TENCENTCLOUD_SECRET_KEY=你的SecretKey\n"
            f"然后执行: chmod 600 {CRED_FILE}"
        )
    secret_id = secret_key = None
    with open(CRED_FILE, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip().strip("'\"")
            if key == "TENCENTCLOUD_SECRET_ID":
                secret_id = value
            elif key == "TENCENTCLOUD_SECRET_KEY":
                secret_key = value
    if not secret_id or not secret_key:
        die(f"{CRED_FILE} 中缺少 TENCENTCLOUD_SECRET_ID 或 TENCENTCLOUD_SECRET_KEY")
    print(f"SecretId: {secret_id[:8]}…（已读取，完整值不会显示）")
    return secret_id, secret_key


def build_zip():
    """打包函数代码。

    直接把 src/ 和 node_modules/ 写进 zip，不走暂存目录：
    本机有删除保护，清理上千个暂存文件会被拦截。
    """
    say("打包函数代码")
    zip_path = os.path.join(HERE, "function.zip")

    node_modules = os.path.join(HERE, "node_modules")
    if not os.path.isdir(node_modules):
        print("  未找到 node_modules，尝试安装依赖…")
        subprocess.run(
            ["npm", "install", "--omit=dev", "--silent"],
            cwd=HERE,
            check=False,
        )
        if not os.path.isdir(node_modules):
            die("依赖安装失败，请手动执行 npm install 后重试")

    entries = []  # (绝对路径, zip 内相对路径)
    for name in ("index.js", "package.json"):
        src = os.path.join(HERE, "src", name)
        if os.path.isfile(src):
            entries.append((src, name))
    if not any(arc == "index.js" for _, arc in entries):
        die("src/index.js 不存在")

    for root, dirs, files in os.walk(node_modules):
        dirs[:] = [d for d in dirs if d not in (".bin", "__pycache__")]
        for name in files:
            if name.endswith((".md", ".map", ".ts")):
                continue
            full = os.path.join(root, name)
            entries.append((full, os.path.relpath(full, HERE)))

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for full, arc in entries:
            archive.write(full, arc)

    size_mb = os.path.getsize(zip_path) / 1024 / 1024
    print(f"  打包完成: function.zip ({size_mb:.1f} MB, {len(entries)} 个文件)")
    return zip_path


def confirm_bucket(secret_id, secret_key):
    """确认 COS 桶已存在。桶需要在控制台创建（COS 的 API 不在此 SDK 内）。"""
    say("检查 COS 存储桶")
    if COS_BUCKET:
        print(f"  使用指定桶: {COS_BUCKET}")
        return COS_BUCKET
    try:
        from tencentcloud.sts.v20180813 import sts_client, models as sts_models
        from tencentcloud.common.profile.client_profile import ClientProfile
        from tencentcloud.common.profile.http_profile import HttpProfile

        cred = __import__(
            "tencentcloud.common.credential", fromlist=["Credential"]
        ).Credential(secret_id, secret_key)
        profile = ClientProfile()
        profile.httpProfile = HttpProfile(endpoint="sts.tencentcloudapi.com")
        client = sts_client.StsClient(cred, REGION, profile)
        resp = client.GetCallerIdentity(sts_models.GetCallerIdentityRequest())
        appid = getattr(resp, "AccountId", "") or ""
        if appid:
            print(f"  账号 AppId: {appid}")
            print(f"  建议桶名: pine-sync-{appid}")
    except Exception as exc:  # noqa: BLE001
        print(f"  （未能自动获取 AppId: {exc}）")

    print("  COS 桶请先在控制台创建（对象存储 → 存储桶列表 → 创建存储桶）")
    print("  创建后重新运行：COS_BUCKET=你的桶名 python3 deploy.py")
    if not COS_BUCKET:
        die("缺少 COS_BUCKET。请在控制台创建桶后用环境变量指定。")
    return COS_BUCKET


def detach_cls_logs(client):
    """关闭函数日志投递到 CLS。

    函数日志投递到 CLS 后，日志主题即使几乎无写入也会持续产生费用
    （分区/存储按天计费，无免费额度），本服务不需要 CLS 排障，直接关闭。
    2026-09-01 实测：UpdateFunctionConfiguration 接受顶层 ClsLogsetId /
    ClsTopicId 传空字符串来关闭投递；旧版 SDK 模型没有这两个字段，
    因此用 call_json 裸调。失败不中断部署。
    """
    try:
        client.call_json(
            "UpdateFunctionConfiguration",
            {"FunctionName": FUNCTION_NAME, "ClsLogsetId": "", "ClsTopicId": ""},
        )
        print("  ✅ 已关闭日志投递到 CLS（不再产生日志服务费用）")
    except Exception as exc:  # noqa: BLE001
        print(f"  （关闭日志投递失败，可在控制台函数配置里手动关闭: {exc}）")


def main():
    update_only = "--update" in sys.argv
    secret_id, secret_key = load_credentials()

    from tencentcloud.common.credential import Credential
    from tencentcloud.common.profile.client_profile import ClientProfile
    from tencentcloud.common.profile.http_profile import HttpProfile
    from tencentcloud.scf.v20180416 import scf_client
    from tencentcloud.scf.v20180416 import models

    bucket = confirm_bucket(secret_id, secret_key) if not update_only else COS_BUCKET

    cred = Credential(secret_id, secret_key)
    profile = ClientProfile()
    profile.httpProfile = HttpProfile(endpoint="scf.tencentcloudapi.com")
    client = scf_client.ScfClient(cred, REGION, profile)

    zip_path = build_zip()
    with open(zip_path, "rb") as handle:
        code_b64 = base64.b64encode(handle.read()).decode("utf-8")

    env_vars = [
        variable("COS_BUCKET", bucket),
        variable("COS_REGION", REGION),
        variable("ALLOWED_ORIGINS", ALLOWED_ORIGINS),
    ]
    # 注意：SCF 保留 TENCENTCLOUD_ 前缀，自定义变量必须用别的名字（函数代码读 PINE_ 前缀）。
    # 创建和更新都要带上密钥：UpdateFunctionConfiguration 是整体替换环境变量，
    # 更新时若只传 3 个业务变量会把 PINE_SECRET_* 抹掉。
    env_vars += [
        variable("PINE_SECRET_ID", secret_id),
        variable("PINE_SECRET_KEY", secret_key),
    ]

    exists = False
    try:
        req = models.GetFunctionRequest()
        req.FunctionName = FUNCTION_NAME
        resp = client.GetFunction(req)
        status = getattr(resp, "Status", "") or ""
        if status == "CreateFailed":
            # 处于失败态的函数无法更新，只能删掉重建。常见原因是未开通 CLS 日志服务。
            print(f"  函数处于 CreateFailed，删除后重建")
            for reason in getattr(resp, "StatusReasons", []) or []:
                msg = getattr(reason, "ErrorMessage", "") or ""
                if msg:
                    print(f"    原因: {msg}")
            del_req = models.DeleteFunctionRequest()
            del_req.FunctionName = FUNCTION_NAME
            client.DeleteFunction(del_req)
            time.sleep(2)
        else:
            exists = True
            print(f"  函数已存在: {FUNCTION_NAME}（{status or '未知状态'}）")
    except Exception:  # noqa: BLE001
        exists = False

    say("更新代码" if exists else "创建云函数")
    if exists:
        req = models.UpdateFunctionCodeRequest()
        req.FunctionName = FUNCTION_NAME
        req.ZipFile = code_b64
        req.Handler = "index.main_handler"
        client.UpdateFunctionCode(req)
        print("  ✅ 代码已更新")

        cfg = models.UpdateFunctionConfigurationRequest()
        cfg.FunctionName = FUNCTION_NAME
        cfg.Environment = env_object(env_vars)
        cfg.Timeout = 20
        cfg.MemorySize = 128
        try:
            client.UpdateFunctionConfiguration(cfg)
            print("  ✅ 配置已更新")
        except Exception as exc:  # noqa: BLE001
            print(f"  （配置更新跳过: {exc}）")
    else:
        req = models.CreateFunctionRequest()
        req.FunctionName = FUNCTION_NAME
        req.Runtime = "Nodejs18.15"
        req.Handler = "index.main_handler"
        req.Timeout = 20
        req.MemorySize = 128
        req.Environment = env_object(env_vars)
        req.Code = models.Code()
        req.Code.ZipFile = code_b64
        client.CreateFunction(req)
        print(f"  ✅ 函数已创建: {FUNCTION_NAME}")

    say("创建 HTTP 触发器（函数 URL）")
    has_http = False
    try:
        list_req = models.ListTriggersRequest()
        list_req.FunctionName = FUNCTION_NAME
        resp = client.ListTriggers(list_req)
        for trigger in getattr(resp, "Triggers", []) or []:
            if getattr(trigger, "Type", "") == "http":
                has_http = True
                print("  触发器已存在")
                break
    except Exception:  # noqa: BLE001
        pass

    if not has_http:
        trigger_desc = json.dumps(
            {
                "netConfig": {"enableIntranet": False, "enableExtranet": True},
                "authType": "NONE",
            }
        )
        wait_until_active(client, models)
        trig = models.CreateTriggerRequest()
        trig.FunctionName = FUNCTION_NAME
        trig.TriggerName = "pine-http"          # 必传，否则报 MissingParameter
        trig.Type = "http"
        trig.TriggerDesc = trigger_desc
        trig.Qualifier = "$DEFAULT"
        try:
            client.CreateTrigger(trig)
            print("  ✅ 触发器已创建")
            time.sleep(3)
        except Exception as exc:  # noqa: BLE001
            print(f"  自动创建失败: {exc}")
            print("  请在控制台手动添加：函数详情 → 触发管理 → 创建触发器 → HTTP 触发器")

    say("获取公网地址")
    # 注意：GetFunctionAddress 返回的是「代码包下载地址」，不是触发器公网 URL。
    # 真正的访问地址在 HTTP 触发器的 TriggerDesc.NetConfig.ExtranetUrl 里。
    wait_until_active(client, models)
    detach_cls_logs(client)
    time.sleep(3)
    url = ""
    for attempt in range(5):
        try:
            list_req = models.ListTriggersRequest()
            list_req.FunctionName = FUNCTION_NAME
            resp = client.ListTriggers(list_req)
            for trigger in resp.Triggers or []:
                if getattr(trigger, "Type", "") != "http":
                    continue
                desc = json.loads(getattr(trigger, "TriggerDesc", "") or "{}")
                url = (desc.get("NetConfig") or {}).get("ExtranetUrl", "") or ""
                if url:
                    break
            if url:
                break
        except Exception as exc:  # noqa: BLE001
            print(f"  第 {attempt + 1} 次获取失败: {exc}")
        time.sleep(3)

    if url:
        print(f"\n  \033[32m{url}\033[0m")
        with open(os.path.join(HERE, ".last-url"), "w", encoding="utf-8") as handle:
            handle.write(url)
        print(f"  已保存到 {os.path.join(HERE, '.last-url')}")
        print("\n  验证：curl " + url.rstrip("/") + "/ping")
    else:
        print("  请在控制台获取：函数详情 → 触发管理 → HTTP 触发器 → 访问路径")
        print("  拿到后执行: echo '你的URL' > " + os.path.join(HERE, ".last-url"))

    say("完成")
    print("  下一步：把该地址填进网页端和安卓端的同步服务地址。")


if __name__ == "__main__":
    main()
