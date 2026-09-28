#!/usr/bin/env python3
"""生成 App 图标(1024x1024):扁平化色块风格 —— 靛蓝底 + 键位色块 + 橙色高亮「拼」键。"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024
OUT = os.path.join(ROOT, "PinyinDemo", "App", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

# 扁平配色
BG = (79, 91, 232, 255)        # 靛蓝背景
KEY_A = (255, 255, 255, 255)   # 常规键:白
KEY_B = (219, 224, 255, 255)   # 次级键:浅靛
CAND = (168, 178, 255, 255)    # 候选条:中靛
HIGHLIGHT = (255, 138, 61, 255)  # 高亮键:橙

img = Image.new("RGBA", (SIZE, SIZE), BG)
d = ImageDraw.Draw(img)


def rrect(box, radius, fill):
    d.rounded_rectangle(box, radius=radius, fill=fill)


# 顶部候选条(扁平色块)
rrect((96, 128, SIZE - 96, 232), radius=36, fill=CAND)

# 键盘区:3 行键块(10 / 9 / 7 键),行距一致
rows = [10, 9, 7]
margin, top0, key_h, gap = 96, 312, 130, 28
width = SIZE - margin * 2
for r, count in enumerate(rows):
    key_w = (width - (count - 1) * gap) / count
    y0 = top0 + r * (key_h + gap)
    for c in range(count):
        x0 = margin + c * (key_w + gap)
        color = KEY_A if (r + c) % 2 == 0 else KEY_B
        rrect((x0, y0, x0 + key_w, y0 + key_h), radius=24, fill=color)

# 高亮「拼」键:第三行正中间那颗
r = 2
count = rows[r]
key_w = (width - (count - 1) * gap) / count
y0 = top0 + r * (key_h + gap)
center_c = count // 2
x0 = margin + center_c * (key_w + gap)
rrect((x0, y0, x0 + key_w, y0 + key_h), radius=24, fill=HIGHLIGHT)
font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 74)
text = "拼"
bbox = d.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text((x0 + key_w / 2 - tw / 2 - bbox[0], y0 + key_h / 2 - th / 2 - bbox[1]),
       text, font=font, fill=(255, 255, 255, 255))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.convert("RGB").save(OUT, "PNG")
print("图标已生成:", OUT, os.path.getsize(OUT), "bytes")
