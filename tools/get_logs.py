#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""拉取指定 run 的构建日志，打印失败的步骤和错误行。"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import auto_build
import cloud_build as cb

RUN_ID = sys.argv[1] if len(sys.argv) > 1 else None
OWNER = "chenjian19930720"
REPO = "proxyone-build"


def main():
    token = auto_build.get_token()
    api = cb.Api(token)
    if RUN_ID:
        run_id = RUN_ID
    else:
        _, data, _ = api.call("GET", "/repos/%s/%s/actions/runs?per_page=5" % (OWNER, REPO))
        run_id = data["workflow_runs"][0]["id"]

    _, jobs, _ = api.call("GET", "/repos/%s/%s/actions/runs/%s/jobs" % (OWNER, REPO, run_id))
    for job in jobs.get("jobs", []):
        print("=" * 70)
        print("JOB %s  %s  -> %s" % (job["id"], job["name"], job.get("conclusion")))
        for st in job.get("steps", []):
            flag = "OK " if st.get("conclusion") == "success" else ("FAIL" if st.get("conclusion") == "failure" else "----")
            print("   [%s] %s" % (flag, st["name"]))

        url = "https://api.github.com/repos/%s/%s/actions/jobs/%s/logs" % (OWNER, REPO, job["id"])
        try:
            raw = api.download(url)
            text = raw.decode("utf-8", "replace")
        except SystemExit as e:
            print("   日志下载失败:", e)
            continue

        lines = text.splitlines()
        print("   日志 %d 行，下面是错误相关片段：" % len(lines))
        keys = ("error:", "error ", "failed", "FAILED", "Command line invocation",
                "** BUILD FAILED **", "The following build commands failed", "ld: ", "clang:")
        shown = 0
        for i, ln in enumerate(lines):
            low = ln.lower()
            if any(k.lower() in low for k in keys):
                print("   %s" % ln[:400].strip())
                shown += 1
                if shown > 120:
                    print("   ...(截断)")
                    break
        if shown == 0:
            print("   (没有匹配到错误关键字，打印最后 80 行)")
            for ln in lines[-80:]:
                print("   %s" % ln[:400])


if __name__ == "__main__":
    main()
