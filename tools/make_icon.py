#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App 图标：1024x1024 渐变底 + 白色闪电，写入 Assets.xcassets。"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "App", "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024

C1 = (76, 144, 255)     # #4C90FF
C2 = (139, 95, 255)     # #8B5FFF
BG_DEEP = (13, 16, 32)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    img = Image.new("RGB", (size, size), BG_DEEP)
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.62 + y / size * 0.38)
            px[x, y] = lerp(C1, C2, min(1.0, t * 1.15))
    return img


def lightning(draw, cx, cy, scale, color=(255, 255, 255, 255)):
    # 标准闪电：上宽下尖，中间 Z 形错位
    pts = [
        (0.04, -0.47), (0.33, -0.47), (0.10, -0.02),
        (0.30, -0.02), (-0.04, 0.47), (0.09, 0.04), (-0.11, 0.04),
    ]
    poly = [(cx + px * scale, cy + py * scale) for px, py in pts]
    draw.polygon(poly, fill=color)


def main():
    os.makedirs(ICONSET, exist_ok=True)

    base = gradient(SIZE).convert("RGBA")

    # 高光光斑
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-SIZE * 0.15, -SIZE * 0.55, SIZE * 0.75, SIZE * 0.35],
               fill=(255, 255, 255, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(SIZE * 0.09))
    base = Image.alpha_composite(base, glow)

    # 闪电（带柔和投影，不要圆底）
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = SIZE / 2, SIZE / 2

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    lightning(sd, cx + SIZE * 0.006, cy + SIZE * 0.014, SIZE * 0.66, (10, 12, 30, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.018))
    base = Image.alpha_composite(base, shadow)

    lightning(d, cx, cy, SIZE * 0.66, (255, 255, 255, 255))

    base = Image.alpha_composite(base, layer)

    out = base.convert("RGB")
    path = os.path.join(ICONSET, "icon-1024.png")
    out.save(path, "PNG")
    print("wrote", path, out.size)

    contents = {
        "images": [
            {"filename": "icon-1024.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1}
    }
    with open(os.path.join(ICONSET, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(contents, fh, indent=2)

    with open(os.path.join(ROOT, "App", "Assets.xcassets", "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump({"info": {"author": "xcode", "version": 1}}, fh, indent=2)

    print("assets ready")


if __name__ == "__main__":
    main()
