#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 tree-sitter 对全部 .swift 做语法解析，报告 ERROR / MISSING 节点。"""
import os
import sys

import tree_sitter_swift as tss
from tree_sitter import Language, Parser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lang = Language(tss.language())
parser = Parser(lang)

targets = []
for base in ("App", "Shared", "Tunnel"):
    for dirpath, _, files in os.walk(os.path.join(ROOT, base)):
        for f in files:
            if f.endswith(".swift"):
                targets.append(os.path.join(dirpath, f))

bad = 0
for path in sorted(targets):
    src = open(path, "rb").read()
    tree = parser.parse(src)
    problems = []

    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            problems.append(node)
        for i in range(node.child_count):
            stack.append(node.children[i])

    rel = os.path.relpath(path, ROOT)
    if problems:
        bad += 1
        print("FAIL %s" % rel)
        for n in problems[:8]:
            row, col = n.start_point
            snippet = src[n.start_byte:min(n.end_byte, n.start_byte + 90)].decode("utf-8", "replace")
            snippet = snippet.replace("\n", "\\n")
            print("   line %d:%d  %s  %s" % (row + 1, col + 1,
                                             "MISSING" if n.is_missing else "ERROR", snippet))
    else:
        print("OK   %s" % rel)

print("\n%d/%d files parsed clean" % (len(targets) - bad, len(targets)))
sys.exit(1 if bad else 0)
