# -*- coding: utf-8 -*-
"""build_danmaku.py —— 程序化烘焙「灵纹能量珠」白模弹幕（24×24）

背景：assets/sprites/danmaku.png 原为一张单纯的柔边圆球（AI 源图已随
xiuxian-level-assets_assets 目录删除，build_sprites.py 无法重烘）。
2026-09-22 用户要求「子弹模型太简单，稍微设计一下」——本脚本改为**纯程序化**
烘焙，不依赖任何源图，幂等可重跑。

设计（单一剪影，四色只靠 modulate 区分，维持既有约束）：
  · 白炽内核 r≤3.4 —— 能量核心，染色后为属性色最亮点
  · 灵纹刻线 r5.9~6.9 —— 一圈暗环，弹丸的「设计感」来源（封印灵纹）
  · 球体主体 + 左上入光明暗 —— 立体感，不是平涂
  · 高光斑（左上，沿入光方向偏移）
  · 暗缘 r9.4~10.3 —— 剪影收边，染色后为深属性色，亮/暗背景都有轮廓
  · 染色光晕 r10.3~12.0 —— modulate 后成属性色光晕

碰撞关系（不得漂移）：实心剪影半径 ≈ 10.3px（与旧版实测一致），
判定半径 9（ART_BASE_R），视觉/判定 = 1.14，脚本内置断言锁定。

用法：
    python tools/build_danmaku.py           # 烘焙到 D:/demo/_danmaku_new.png + 预览图
确认预览后手动覆盖：
    cp D:/demo/_danmaku_new.png assets/sprites/danmaku.png
（不直接写 assets：先出预览给设计确认，再落盘。）
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT_NEW = Path(r"D:/demo/_danmaku_new.png")
OUT_PREVIEW = Path(r"D:/demo/_danmaku_redesign_preview.png")
OLD = Path(r"D:/demo/xiuxian-danmaku/assets/sprites/danmaku.png")

SIZE = 24
SS = 16          # 超采样倍率（384² 浮点球体 -> LANCZOS 降采样 -> 24² 8bit）

# ------------------------------------------------ 视觉规格（单位：最终像素）
R_CORE = 3.6                  # 白炽内核
V_CORE = 1.00
R_INNER = 5.8                 # 内环亮带
V_INNER = 0.92
R_RING1 = 7.0                 # 灵纹刻线（暗环）外缘
V_RING = 0.52
R_BODY = 9.4                  # 主体外缘
V_BODY0, V_BODY1 = 0.86, 0.68 # 主体由内向外
R_RIM = 10.7                  # 暗缘外缘（名义边；AA 后实测剪影 ≈10.3，对齐旧版）
V_RIM0, V_RIM1 = 0.58, 0.30
R_GLOW = 12.0                 # 光晕外缘
V_GLOW = 0.92
A_GLOW = 96                   # 光晕峰值 alpha
LIGHT = (-0.55, -0.835)       # 左上入光方向
SHADE_K = 0.09                # 球体明暗强度
SPEC_OFF = 4.2                # 高光斑中心偏移（沿入光方向）
SPEC_R = 2.4                  # 高光斑半径
SPEC_K = 0.22                 # 高光斑强度

# ------------------------------------------------ 四属性主色（同 Game.COLOR_MAIN）
ATTR = [
    ("plasma", (0.98, 0.24, 0.27)),
    ("frost", (0.22, 0.62, 1.00)),
    ("photon", (0.93, 0.96, 1.00)),
    ("gravity", (1.00, 0.80, 0.14)),
]

LN = math.hypot(*LIGHT)
LIGHT_N = (LIGHT[0] / LN, LIGHT[1] / LN)


def profile(r: float, nx: float, ny: float) -> tuple[float, float]:
    """半径 r（最终像素）+ 单位法线 -> (灰度值 0..1, alpha 0..255)"""
    if r <= R_CORE:
        v = V_CORE
    elif r <= R_INNER:
        t = (r - R_CORE) / (R_INNER - R_CORE)
        v = V_CORE + (V_INNER - V_CORE) * t
    elif r <= R_RING1:
        v = V_RING                       # 灵纹刻线：整体压暗一圈
    elif r <= R_BODY:
        t = (r - R_RING1) / (R_BODY - R_RING1)
        v = V_BODY0 + (V_BODY1 - V_BODY0) * t
    elif r <= R_RIM:
        t = (r - R_BODY) / (R_RIM - R_BODY)
        v = V_RIM0 + (V_RIM1 - V_RIM0) * t
    else:
        v = V_GLOW

    a = 255.0
    if r > R_RIM:
        if r >= R_GLOW:
            a = 0.0
        else:
            a = A_GLOW * (1.0 - (r - R_RIM) / (R_GLOW - R_RIM)) ** 1.5

    if r < R_BODY:
        # 球体明暗：随半径渐入（核心区保持纯白，不被背光侧压暗）
        w = min(1.0, max(0.0, (r - R_CORE) / (R_INNER - R_CORE)))
        v += SHADE_K * w * (nx * LIGHT_N[0] + ny * LIGHT_N[1])
        # 高光斑：沿入光方向偏移的软亮点
        dx = nx * r - LIGHT_N[0] * SPEC_OFF
        dy = ny * r - LIGHT_N[1] * SPEC_OFF
        d = math.hypot(dx, dy)
        if d < SPEC_R:
            v += SPEC_K * (1.0 - d / SPEC_R)
        v = min(1.0, v)
    return v, a


def bake() -> Image.Image:
    n = SIZE * SS
    c = n / 2.0
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = img.load()
    for y in range(n):
        for x in range(n):
            dx = (x + 0.5 - c) / SS
            dy = (y + 0.5 - c) / SS
            r = math.hypot(dx, dy)
            if r > R_GLOW:
                continue
            nx, ny = (dx / r, dy / r) if r > 1e-6 else (0.0, -1.0)
            v, a = profile(r, nx, ny)
            g = int(round(v * 255.0))
            px[x, y] = (g, g, g, int(round(a)))
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    return out


def audit(img: Image.Image) -> list[str]:
    """碰撞关系断言：实心剪影 / 光晕范围 / 内核亮度。任何越界直接报错。"""
    px = img.load()
    solid = 0
    glow_max = 0.0
    for y in range(SIZE):
        for x in range(SIZE):
            _, _, _, a = px[x, y]
            r = math.hypot(x + 0.5 - SIZE / 2.0, y + 0.5 - SIZE / 2.0)
            if a >= 250:
                solid += 1
            if a >= 8:
                glow_max = max(glow_max, r)
    eq_r = math.sqrt(solid / math.pi)
    lines = [f"solid a>=250: n={solid}  eq_r={eq_r:.2f}px",
             f"glow a>=8 max r={glow_max:.2f}px"]
    if not (9.6 <= eq_r <= 10.9):
        raise AssertionError(f"实心剪影半径越界: {eq_r:.2f}（应在 9.6~10.9，判定 9）")
    if not (11.0 <= glow_max <= 12.2):
        raise AssertionError(f"光晕范围越界: {glow_max:.2f}（应在 11.0~12.2）")
    c = px[SIZE // 2, SIZE // 2]
    if c[0] < 240:
        raise AssertionError(f"内核中心不够亮: {c}")
    lines.append(f"center={c}")
    return lines


def dye(gray: Image.Image, rgb: tuple[float, float, float]) -> Image.Image:
    """白模 × 属性色（模拟 modulate 乘法），返回展平到不透明底的图。"""
    w, h = gray.size
    out = Image.new("RGB", (w, h))
    sp, dp = gray.load(), out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = sp[x, y]
            bg = (0.07, 0.07, 0.13)     # 游戏深蓝底
            dr = int(round((r / 255.0 * rgb[0] * a / 255.0 + bg[0] * (1 - a / 255.0)) * 255))
            dg = int(round((g / 255.0 * rgb[1] * a / 255.0 + bg[1] * (1 - a / 255.0)) * 255))
            db = int(round((b / 255.0 * rgb[2] * a / 255.0 + bg[2] * (1 - a / 255.0)) * 255))
            dp[x, y] = (dr, dg, db)
    return out


def preview(new: Image.Image) -> None:
    """新旧对比板：上排旧版 / 下排新版，各 ×4 属性色，6 倍放大。"""
    old = Image.open(OLD).convert("RGBA") if OLD.exists() else None
    Z = 6
    bw = SIZE * Z + 24
    rows = (2 if old else 1) * len(ATTR)
    bh = rows * (SIZE * Z + 34) + 60
    im = Image.new("RGB", (bw * len(ATTR) + 24, bh), (18, 18, 33))
    d = ImageDraw.Draw(im)
    y0 = 12
    if old is not None:
        d.text((12, y0), "OLD", fill=(200, 200, 200))
        for i, (_, rgb) in enumerate(ATTR):
            cell = dye(old, rgb).resize((SIZE * Z, SIZE * Z), Image.NEAREST)
            im.paste(cell, (12 + i * bw + 12, y0 + 16))
        y0 += SIZE * Z + 34
    d.text((12, y0), "NEW", fill=(120, 255, 160))
    for i, (name, rgb) in enumerate(ATTR):
        cell = dye(new, rgb).resize((SIZE * Z, SIZE * Z), Image.NEAREST)
        im.paste(cell, (12 + i * bw + 12, y0 + 16))
        d.text((12 + i * bw + 14, y0 + 16 + SIZE * Z + 2), name, fill=(160, 160, 160))
    im.save(OUT_PREVIEW)


def main() -> int:
    new = bake()
    report = audit(new)
    new.save(OUT_NEW)
    preview(new)
    print("[OK] baked ->", OUT_NEW)
    print("\n".join(report))
    print("[OK] preview ->", OUT_PREVIEW)
    return 0


if __name__ == "__main__":
    sys.exit(main())
