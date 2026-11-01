#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""下载最近一次构建的 build-log artifact，打印错误行。"""
import io
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import auto_build
import cloud_build as cb

OWNER = "chenjian19930720"
REPO = "proxyone-build"


def main():
    api = cb.Api(auto_build.get_token())
    run_id = sys.argv[1] if len(sys.argv) > 1 else None
    if not run_id:
        _, data, _ = api.call("GET", "/repos/%s/%s/actions/runs?per_page=5" % (OWNER, REPO))
        run_id = data["workflow_runs"][0]["id"]

    _, data, _ = api.call("GET", "/repos/%s/%s/actions/runs/%s/artifacts" % (OWNER, REPO, run_id))
    arts = data.get("artifacts", [])
    print("artifacts:", [a["name"] for a in arts])
    log_art = next((a for a in arts if a["name"] == "build-log"), None)
    if not log_art:
        print("没有 build-log artifact")
        return

    body = api.download(log_art["archive_download_url"])
    with zipfile.ZipFile(io.BytesIO(body)) as zf:
        for name in zf.namelist():
            text = zf.read(name).decode("utf-8", "replace")
            lines = text.splitlines()
            print("=== %s (%d lines) ===" % (name, len(lines)))
            hits = [l for l in lines if "error:" in l or "BUILD FAILED" in l
                    or "The following build commands failed" in l or "Undefined symbol" in l]
            if hits:
                for l in hits[:60]:
                    print(l[:400])
            else:
                print("(no error lines, tail:)" )
                for l in lines[-40:]:
                    print(l[:400])


if __name__ == "__main__":
    main()
