# -*- coding: utf-8 -*-
"""build_enemies.py —— 手绘像素妖（小妖 / 护法妖将），不经过 AI 生成。

背景：旧 enemy_*.png 是 42px 的四色「异形怪物」，识别度差；妖将更是把小妖那张
图放大 1.79 倍凑出来的（整数放大把 2px 元素糊成 4px 块，且读作「一群小妖」）。
本脚本按美术方案重画两套**原生朝左**的人形妖，四色完全同形、只换四档映射。

---------------------------------------------------------------- 敌我识别（总判据）
  「朝左、头顶双角、轮廓带刺的是妖；朝右、平顶、轮廓闭合的是我（玩家修士）。」
  玩家已是 44x36 侧身**朝右**的修士。妖一律**朝左**手绘母版 ——
  **绝对禁止把玩家图水平翻转**：玩家身前/身后的部件有语义（发髻在后脑、袍裾向后拖），
  翻转会全跑到背后；且默认光从左上，翻转后高光方向反了。所以妖的素材必须原生朝左。

---------------------------------------------------------------- 两套，各自独立重绘
  · 小妖 42x42：朝左、弓身矮壮、头身比约 1:3.5。非人特征四项（都 >=2px）：
      V 形外撇双角(GLOW) / 獠牙(CORE) / 三指兽爪(GLOW) / 赤足(DARK + GLOW 趾点)。
      不要尾巴（42px 下是碎纹理，且会与玩家蓝袍「后掠飘带」混淆）——
      改为臀部向后翘起的兽毛块(DARK)。
  · 妖将 84x84：朝左、**直立挺拔**、头身比约 1:5。**单独重绘，不复用小妖 x2**
      （那会把 2px 元素放大成 4px 糊块，且被读成「小妖群」—— 这是最大风险）。
      差异落在**姿态**（直立 vs 弓身）而不只是尺寸。兵器是唯一按属性变化的小件，
      属风味，属性识别仍只靠颜色。

---------------------------------------------------------------- 通用规则
  · 统一 1px 近黑描边 #12101A（不引入新色相）。
  · **角必须用 GLOW**（最亮档）：用 MAIN 会与躯干同亮度糊成一团，角直接「没了」。
  · 四档色与 Game.gd 的 COLOR_MAIN/GLOW/DARK/CORE 逐一对齐（顺序 RED/BLUE/WHITE/YELLOW）。

---------------------------------------------------------------- 断言（玩法第一识别维度）
  妖色 = 弹色 = 免疫袍色，颜色是玩家认色的第一载体。若为「妖感」把躯干压成大面积
  DARK，玩家在弹幕里就会认错色。所以：**单张 sprite 里 (MAIN+GLOW) 像素占不透明
  像素的比例 < 30% 就报错退出。** 分母用「不透明像素」而非整张画布 —— 图四周是透明
  的，按整张算比例永远偏低、断言失去意义；按可见躯体算才对应「身上够不够亮色」。

用法：python tools/build_enemies.py     （幂等，重跑覆盖）
"""

from __future__ import annotations

import warnings
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Pillow 新版把 getdata 标为弃用（改用 get_flattened_data），这里只是逐像素数色，
# 两种 API 行为一致；屏蔽弃用告警以免污染「脚本零告警」的可复核输出。
warnings.filterwarnings("ignore", message=".*getdata.*")

OUT_DIR = Path(r"D:\demo\xiuxian-danmaku\assets\sprites")

# Game.gd 的 COLOR_MAIN / COLOR_GLOW / COLOR_DARK / COLOR_CORE（顺序 RED/BLUE/WHITE/YELLOW）
MAIN = [(0.98, 0.24, 0.27), (0.22, 0.62, 1.00), (0.93, 0.96, 1.00), (1.00, 0.80, 0.14)]
GLOW = [(1.00, 0.56, 0.24), (0.45, 0.86, 1.00), (0.84, 0.92, 1.00), (1.00, 0.93, 0.42)]
DARK = [(0.40, 0.04, 0.09), (0.03, 0.16, 0.40), (0.28, 0.32, 0.42), (0.38, 0.26, 0.02)]
CORE = [(1.00, 0.94, 0.80), (0.90, 0.98, 1.00), (1.00, 1.00, 1.00), (1.00, 0.99, 0.82)]
NAMES = ["red", "blue", "white", "yellow"]

# 口腔 / 描边：固定近黑色，不随属性走（引入新色相会污染「颜色 = 属性」语义）
MOUTH = (0x1A, 0x14, 0x20)     # #1A1420
OUTLINE = (0x12, 0x10, 0x1A)   # #12101A

# 断言阈值：不透明像素里 (MAIN+GLOW) 至少要占这么多，否则认色失败
MIN_MAIN_GLOW_RATIO = 0.30


def _rgb(t: tuple[float, float, float]) -> tuple[int, int, int]:
    return (int(round(t[0] * 255)), int(round(t[1] * 255)), int(round(t[2] * 255)))


def _new_canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _rect(d: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int,
          fill: tuple) -> None:
    """含端点矩形（几何表约定 rect(x0,y0,x1,y1) 两端都算）。
    Pillow 的 rectangle 右/下是开区间，故 +1 对齐「含端点」语义；
    越出画布的部分由 Pillow 自动裁剪（如足块底行被画布高裁掉，正好得到标注的 8x4）。"""
    d.rectangle((x0, y0, x1 + 1, y1 + 1), fill=fill)


def _outline(img: Image.Image, color: tuple[int, int, int]) -> None:
    """在透明剪影外扩 1px 描边（只落在图形外侧，不覆盖内部像素）。"""
    sil = img.getchannel("A")
    ring = ImageChops.subtract(sil.filter(ImageFilter.MaxFilter(3)), sil)
    img.paste(color + (255,), (0, 0), ring)


def _check_ratio(img: Image.Image, ci: int, tag: str) -> None:
    """断言：不透明像素里 (MAIN+GLOW) 占比 >= MIN_MAIN_GLOW_RATIO。"""
    main_t = _rgb(MAIN[ci])
    glow_t = _rgb(GLOW[ci])
    opaque = 0
    main_glow = 0
    for r, g, b, a in img.getdata():
        if a == 0:
            continue
        opaque += 1
        if (r, g, b) == main_t or (r, g, b) == glow_t:
            main_glow += 1
    ratio = main_glow / opaque if opaque else 0.0
    print(f"[ratio] {tag} ci={ci} MAIN+GLOW={main_glow}/{opaque} "
          f"= {ratio:.1%} (阈值 {MIN_MAIN_GLOW_RATIO:.0%})")
    if ratio < MIN_MAIN_GLOW_RATIO:
        raise SystemExit(
            f"[FAIL] {tag} ci={ci}: 亮色占比 {ratio:.1%} < {MIN_MAIN_GLOW_RATIO:.0%} "
            f"—— 躯干压得太暗，玩家在弹幕里会认错色。增加 MAIN 躯干或 GLOW 角/爪。")


# ==================================================================== 小妖 42x42
def build_small(ci: int) -> Image.Image:
    S = 42
    img, d = _new_canvas(S)
    main, glow, dark, core = (_rgb(MAIN[ci]), _rgb(GLOW[ci]),
                              _rgb(DARK[ci]), _rgb(CORE[ci]))

    # --- 后层（右侧 / 背侧）---
    # 角在头之后（画在头之前，头的椭圆会盖住角根，只留角尖探出头顶）
    d.polygon([(10, 8), (13, 8), (8, 1)], fill=glow)   # 左角
    d.polygon([(16, 8), (19, 8), (22, 1)], fill=glow)  # 右角
    d.line([(24, 20), (23, 28)], fill=dark, width=3)   # 后臂

    # --- 躯干主体 ---
    d.polygon([(12, 17), (25, 15), (27, 29), (15, 31)], fill=main)  # 躯干(弓背)
    d.polygon([(21, 14), (28, 15), (28, 22), (22, 21)], fill=dark)  # 背甲
    d.line([(13, 19), (6, 25)], fill=dark, width=3)    # 前臂
    _rect(d, 16, 28, 26, 34, main)                     # 腰臀
    d.line([(24, 32), (26, 37), (28, 40)], fill=dark, width=4)  # 后腿
    d.line([(18, 32), (14, 37), (11, 40)], fill=dark, width=4)  # 前腿
    _rect(d, 24, 38, 31, 42, dark)                     # 后足
    _rect(d, 8, 38, 16, 42, dark)                      # 前足
    d.polygon([(25, 29), (29, 31), (28, 35), (24, 33)], fill=dark)  # 臀兽毛

    # --- 头（盖在角根之上）---
    d.ellipse((8, 5, 20, 17), fill=main)               # 头
    _rect(d, 8, 14, 13, 16, MOUTH)                     # 口（深色口腔）
    _rect(d, 9, 13, 10, 14, core)                      # 獠牙 左
    _rect(d, 11, 13, 12, 14, core)                     # 獠牙 右
    _rect(d, 10, 10, 11, 11, core)                     # 眼

    # --- 前层亮点（爪 / 趾）---
    d.line([(6, 25), (2, 22)], fill=glow, width=2)     # 爪 1
    d.line([(6, 25), (2, 26)], fill=glow, width=2)     # 爪 2
    d.line([(6, 25), (3, 30)], fill=glow, width=2)     # 爪 3
    _rect(d, 9, 39, 10, 40, glow)                      # 趾点

    _outline(img, OUTLINE)
    return img


# ==================================================================== 妖将 84x84
def _weapon(d: ImageDraw.ImageDraw, ci: int) -> None:
    """兵器：柄通用（DARK），头按属性换（GLOW 为主）。属风味件，识别仍只靠颜色。"""
    glow, dark = _rgb(GLOW[ci]), _rgb(DARK[ci])
    d.line([(17, 54), (7, 40)], fill=dark, width=3)    # 兵器柄（通用）
    if ci == 0:        # 赤炎 · 阔刀
        d.polygon([(2, 22), (12, 19), (18, 33), (8, 36)], fill=glow)
    elif ci == 1:      # 玄冰 · 杖
        d.polygon([(7, 20), (12, 25), (7, 30), (2, 25)], fill=glow)
    elif ci == 2:      # 太清 · 剑（剑身 GLOW + 护手 DARK）
        d.line([(7, 21), (17, 36)], fill=glow, width=4)
        d.line([(12, 33), (19, 30)], fill=dark, width=3)
    else:              # 戊土 · 杵（杵头 GLOW + 凿点 DARK）
        _rect(d, 2, 20, 12, 30, glow)
        _rect(d, 4, 22, 10, 28, dark)


def build_general(ci: int) -> Image.Image:
    S = 84
    img, d = _new_canvas(S)
    main, glow, dark, core = (_rgb(MAIN[ci]), _rgb(GLOW[ci]),
                              _rgb(DARK[ci]), _rgb(CORE[ci]))

    # --- 后层 ---
    d.polygon([(54, 34), (72, 42), (73, 76), (50, 66)], fill=dark)  # 披风
    # 巨角在头之后（画在头之前，头盖住角根）
    d.polygon([(26, 17), (32, 17), (23, 2), (19, 2)], fill=glow)     # 左巨角
    d.polygon([(23, 12), (27, 9), (19, 3), (17, 6)], fill=glow)      # 左角分叉
    d.polygon([(48, 17), (54, 17), (65, 2), (61, 2)], fill=glow)     # 右巨角
    d.polygon([(57, 9), (61, 12), (67, 6), (65, 3)], fill=glow)      # 右角分叉
    d.line([(53, 44), (61, 58)], fill=dark, width=5)                 # 后臂

    # --- 躯干主体（直立）---
    d.polygon([(29, 36), (53, 34), (57, 62), (31, 64)], fill=main)   # 躯干
    d.polygon([(21, 34), (34, 32), (34, 47), (21, 47)], fill=dark)   # 肩吞 左
    d.polygon([(49, 32), (62, 34), (62, 47), (49, 47)], fill=dark)   # 肩吞 右
    d.line([(21, 34), (34, 32)], fill=glow, width=2)                 # 肩上沿 左
    d.line([(49, 32), (62, 34)], fill=glow, width=2)                 # 肩上沿 右
    d.line([(37, 63), (33, 73), (31, 80)], fill=dark, width=6)       # 左腿
    d.line([(49, 63), (53, 73), (55, 80)], fill=dark, width=6)       # 右腿
    _rect(d, 24, 78, 38, 84, dark)                                   # 左足
    _rect(d, 46, 78, 60, 84, dark)                                   # 右足
    _rect(d, 30, 58, 56, 64, dark)                                   # 腰带
    _rect(d, 39, 57, 47, 64, glow)                                   # 兽面扣

    # --- 前臂 / 爪（前层左侧）---
    d.line([(30, 42), (19, 52)], fill=dark, width=5)                 # 前臂
    d.line([(19, 52), (14, 50)], fill=glow, width=2)                 # 爪 1
    d.line([(19, 52), (13, 54)], fill=glow, width=2)                 # 爪 2
    d.line([(19, 52), (15, 58)], fill=glow, width=2)                 # 爪 3

    # --- 头（盖在角根之上）---
    d.ellipse((27, 13, 53, 39), fill=main)           # 头
    _rect(d, 27, 33, 38, 37, MOUTH)                  # 口
    _rect(d, 29, 31, 31, 34, core)                   # 獠牙 左
    _rect(d, 34, 31, 36, 34, core)                   # 獠牙 右
    _rect(d, 30, 24, 33, 27, core)                   # 眼

    # --- 兵器 ---
    _weapon(d, ci)

    _outline(img, OUTLINE)
    return img


# ==================================================================== 预览
def build_preview() -> None:
    """对照图：小妖 / 妖将 各四色，1x 与放大并排，供人工核对敌我识别与四色区分。"""
    Z_SMALL, Z_GENERAL = 4, 3
    pad, gap = 12, 26
    small = [Image.open(OUT_DIR / f"enemy_{n}.png").convert("RGBA") for n in NAMES]
    general = [Image.open(OUT_DIR / f"elite_{n}.png").convert("RGBA") for n in NAMES]

    s1 = small[0].size[0]
    g1 = general[0].size[0]
    row_w_small = (s1 * Z_SMALL + pad) * 4
    row_w_general = (g1 * Z_GENERAL + pad) * 4
    width = pad * 2 + max(row_w_small, row_w_general)
    # 标题 + 小妖(1x/放大) + 妖将(1x/放大)
    height = (pad + 16 + s1 + 14 + s1 * Z_SMALL + 30
              + 16 + g1 + 14 + g1 * Z_GENERAL + pad)
    bg = (28, 30, 46)
    sh = Image.new("RGB", (width, height), bg)
    d = ImageDraw.Draw(sh)
    y = pad

    def _row(imgs, scale: int, labels: bool) -> int:
        nonlocal y
        x = pad
        for im, nm in zip(imgs, NAMES):
            big = im if scale == 1 else im.resize(
                (im.size[0] * scale, im.size[1] * scale), Image.NEAREST)
            sh.paste(big, (x, y), big)
            if labels:
                d.text((x + 3, y + big.height + 4), nm.upper(),
                       fill=(210, 220, 245))
            x += big.size[0] + pad
        return x

    d.text((pad, y), "小妖 42x42 · 1x (朝左，敌我识别：朝左带角=妖)",
           fill=(210, 220, 245))
    y += 16
    _row(small, 1, labels=False)
    y += s1 + 14
    d.text((pad, y), f"小妖 {Z_SMALL}x (NEAREST)", fill=(210, 220, 245))
    y += 16
    _row(small, Z_SMALL, labels=True)
    y += s1 * Z_SMALL + 30

    d.text((pad, y), "妖将 84x84 · 1x (朝左，直立挺拔，独立重绘)",
           fill=(210, 220, 245))
    y += 16
    _row(general, 1, labels=False)
    y += g1 + 14
    d.text((pad, y), f"妖将 {Z_GENERAL}x (NEAREST)", fill=(210, 220, 245))
    y += 16
    _row(general, Z_GENERAL, labels=True)

    sh.save(r"D:\demo\_enemy_preview.png")
    print("[OK] preview -> D:\\demo\\_enemy_preview.png")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for i, name in enumerate(NAMES):
        small = build_small(i)
        _check_ratio(small, i, "enemy")
        small.save(OUT_DIR / f"enemy_{name}.png")
        print(f"[OK] enemy_{name}.png {small.size[0]}x{small.size[1]}")
    for i, name in enumerate(NAMES):
        general = build_general(i)
        _check_ratio(general, i, "elite")
        general.save(OUT_DIR / f"elite_{name}.png")
        print(f"[OK] elite_{name}.png {general.size[0]}x{general.size[1]}")
    build_preview()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
