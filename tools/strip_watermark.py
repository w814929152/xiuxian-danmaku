# -*- coding: utf-8 -*-
"""去除 AI 生图右下角平台水印：用同图同水平带的背景像素覆盖 + 羽化融合。
背景均为近纯色深底（径向渐变），同 y 带左右像素几乎一致，覆盖后肉眼无痕。"""
from PIL import Image, ImageFilter
import sys

# 水印区（右下角「AI生成 / WORKBUDDY>」），留足余量
WX0, WY0, WX1, WY1 = 750, 915, 1014, 1020
W = WX1 - WX0  # 264

for path in sys.argv[1:]:
    im = Image.open(path).convert("RGB")
    # 源区：同一水平带、紧邻水印区左侧
    src = im.crop((WX0 - W, WY0, WX0, WY1))
    # 羽化蒙版：矩形中心全不透明，边缘 24px 渐隐
    mask = Image.new("L", (W, WY1 - WY0), 255)
    feather = mask.filter(ImageFilter.GaussianBlur(10))
    mask = Image.new("L", (W, WY1 - WY0), 0)
    mask.paste(feather, (0, 0))
    mask = mask.point(lambda v: min(255, v * 3))  # 收紧全透明边缘，保证中心完全覆盖
    im.paste(src, (WX0, WY0), mask)
    im.save(path)
    print("done:", path)
