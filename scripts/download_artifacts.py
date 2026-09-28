#!/usr/bin/env python3
"""自动下载 GitHub Actions 最新构建的 ipa 到 download/ 目录。

- 按版本号文件名保存(如 PinyinKeyboard-v1.1.0.2-unsigned.ipa)
- 增量:已下载过的 artifact(按 id 记录在 download/.downloaded.json)自动跳过
- 凭证:复用本机 git credential manager 里缓存的 GitHub 凭证

用法: python scripts/download_artifacts.py
"""
import json
import os
import subprocess
import sys
import zipfile

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import urllib.request

REPO = "adhumankind/ios27-pinyin-keyboard"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOWNLOAD_DIR = os.path.join(ROOT, "download")
STATE_FILE = os.path.join(DOWNLOAD_DIR, ".downloaded.json")
UA = {"User-Agent": "ipa-downloader"}


def github_token() -> str:
    inp = "protocol=https\nhost=github.com\n\n"
    out = subprocess.run(["git", "credential", "fill"], input=inp,
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    sys.exit("未找到 GitHub 凭证(git credential manager)")


def api(url: str, token: str):
    req = urllib.request.Request(url, headers={"Authorization": f"token {token}", **UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main():
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)
    state = {}
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding="utf-8") as f:
            state = json.load(f)
    downloaded_ids = state.setdefault("downloaded_ids", [])
    token = github_token()

    runs = api(f"https://api.github.com/repos/{REPO}/actions/runs?status=success&per_page=5", token)
    for run in runs.get("workflow_runs", []):
        arts = api(f"https://api.github.com/repos/{REPO}/actions/runs/{run['id']}/artifacts", token)
        for a in arts.get("artifacts", []):
            if not ("unsigned" in a["name"].lower() and "ipa" in a["name"].lower()):
                continue
            if str(a["id"]) in downloaded_ids:
                print(f"已是最新,无新 ipa(最近产物: {a['name']})")
                return
            # 下载 artifact zip(GitHub 会把上传的 ipa 再包一层 zip)。
            # 注意:下载地址会 302 到外部存储,重定向请求必须剥离认证头 —— 用 curl(curl 跨域重定向自动去 Authorization)
            zip_path = os.path.join(DOWNLOAD_DIR, "_artifact.zip")
            subprocess.run(
                ["curl", "-sL", "-m", "300", "-H", f"Authorization: token {token}",
                 "-o", zip_path,
                 f"https://api.github.com/repos/{REPO}/actions/artifacts/{a['id']}/zip"],
                check=True)
            with zipfile.ZipFile(zip_path) as z:
                ipas = [n for n in z.namelist() if n.endswith(".ipa")]
                if not ipas:
                    sys.exit("artifact 内未找到 ipa 文件")
                z.extract(ipas[0], DOWNLOAD_DIR)
            os.remove(zip_path)
            downloaded_ids.append(str(a["id"]))
            with open(STATE_FILE, "w", encoding="utf-8") as f:
                json.dump(state, f)
            print("已下载:", os.path.join(DOWNLOAD_DIR, os.path.basename(ipas[0])))
            return
    print("未找到任何 ipa artifact(构建可能尚未成功)")


if __name__ == "__main__":
    main()
