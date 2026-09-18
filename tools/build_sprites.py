# -*- coding: utf-8 -*-
"""build_sprites.py —— 离线批处理：源图 -> 品红去背 -> 裁包围盒 -> 缩放 -> PNG

用法（venv 内含 Pillow 即可，脚本自身零第三方依赖之外的东西）：
    python tools/build_sprites.py

特性：
  · 幂等：输入不变则输出逐字节稳定（同参数重跑覆盖同一批文件）
  · 品红去背：按 min(R,B)-G 色度差做软抠图，半透明边缘同步去品红 spill
  · 裁到实际内容包围盒后再缩放到目标尺寸，避免白边影响实际占比
  · 飞剑走 SWORDS 表：显式 (剑刃宽,高) 非等比烘焙，刃部中心对齐画布中心
  · 附带产出 _robe_test.png（玩家道袍多尺寸可辨识度对照表，供人工判定）
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

SRC_DIR = Path(r"D:\demo\xiuxian-level-assets_assets")
OUT_DIR = Path(r"D:\demo\xiuxian-danmaku\assets\sprites")

# ---------------------------------------------------------------- 抠图参数
# 品红判定：m = min(R, B) - G。纯品红底 m 很大，正常内容 m <= 0 附近。
M_OPAQUE = 40     # m <= 该值：完全不透明
M_TRANSPARENT = 110   # m >= 该值：完全透明
HUE_LO = 270.0    # 品红/粉色色相带（去 spill 用）
HUE_HI = 350.0
SPILL_SAT = 0.30  # 该饱和度以上且落在色相带内 -> 判为背景残留

# ---------------------------------------------------------------- 输出清单
# key: (源文件名前缀, 目标最长边 px；None=按背景流程处理)
SPRITES: dict[str, tuple[str, int]] = {
    # 玩家四袍（是否用于游戏内取决于可辨识度实测；先按大图导出）
    "player_red": ("7e14e999", 256),
    "player_blue": ("bfa38efe", 256),
    "player_white": ("5f4b9eeb", 256),
    "player_yellow": ("a5a7d644", 256),
    # 小妖（碰撞半径 19 -> 直径 38，图形略大 42）
    "enemy_red": ("8fe7554d", 42),
    "enemy_blue": ("de890712", 42),
    "enemy_yellow": ("80b50f1b", 42),
    "enemy_white": ("f34567b9", 42),
    # Boss（碰撞半径 56，法相图形 150）
    "boss": ("4d775633", 150),
    # 弹幕：统一为「白模弹丸」，运行期用 modulate 染属性色（用户要求四色同形）。
    # 圆形弹丸旋转对称，密集场里最不抢眼；颜色才是唯一区分维度。
    # 尺寸不是随手取的：视觉直径 = 2 * 基准半径(9) * 擦弹余量(1.33) ≈ 24px。
    #   余量 = 视觉半径 / 碰撞半径 —— 1.0 表示所见即所中（没有擦弹空间，手感很硬），
    #   越大越好躲但越「虚胖」（密集场看起来堵死）。1.33 是留一眼余地的折中。
    #   改这个数必须同步改 Danmaku.gd 里的 ART_BASE_R（基准半径，保持 1:1 烘焙）。
    "danmaku": ("b40a2b1d", 24),
    # 飞剑走 SWORDS 表（非等比烘焙，见下）
    # 特效（动态缩放，预烘焙 96）
    "fx_burst": ("519c4119", 96),
}

# ---------------------------------------------------------------- 飞剑（非等比烘焙）
# 飞剑源图是「剑柄+护手+剑刃 + 向左的三道粉色拖尾」长条（817x99，约 8:1）。
# 等比缩到 44 宽只剩 5px 高，与 34x10 碰撞盒严重不符（用户反馈「太扁」）。
# 这里改为显式 (剑刃宽, 剑刃高) 目标做非等比烘焙：
#   · 横向以「剑刃」宽度为准 —— 剑刃才是覆盖碰撞盒的部分；
#   · 纵向以「剑刃厚度锚带」为准，把刃从 ~5px 纵向加粗到 11~12px（刻意非等比，
#     不是等比放大 —— 等比放大整剑会长到 ~96px 宽，不可接受）；
#   · 剑刃中心对齐输出画布中心 —— 节点原点即碰撞盒中心，剑柄/护手/拖尾留在
#     刃部左侧、不参与居中。居中在烘焙阶段完成，运行时零偏移逻辑，
#     换图重跑本脚本不会错位（对比：写死在 Sword.gd 里的 offset 会随换图悄悄失效）。
#   · 拖尾实测只占源图宽度 ~12%（三道拖尾到 x≈110，最长一道到 x≈157），
#     不需要也不应该按比例裁左 —— 裁 35% 会切进剑柄。总宽 >34 是预期。
#   · 锚点为人工测量值，换源图必须重新测量（bake_sword 会做内容守卫）。
# key: (源前缀, 剑刃宽, 剑刃高, 剑刃x范围(源图,闭区间), 剑刃厚度锚带y(源图))
SWORDS: dict[str, tuple[str, int, int, tuple[int, int], tuple[int, int]]] = {
    "sword_player": ("a9e67593", 34, 11, (267, 816), (27, 74)),
    "sword_enemy": ("ccbb5071", 34, 12, (250, 790), (36, 121)),
}
BG_KEY = "bg_mountains"
BG_FILE = "2d2d0c2e"


def chroma_key(img: Image.Image) -> Image.Image:
    """品红软抠图 + 边缘 spill 清除。输入 RGB(A) 1024x1024，输出 RGBA。"""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            m = min(r, b) - g
            if m <= M_OPAQUE:
                continue
            if m >= M_TRANSPARENT:
                px[x, y] = (0, 0, 0, 0)
                continue
            # 线性过渡带
            alpha = int(round(255.0 * (M_TRANSPARENT - m)
                              / (M_TRANSPARENT - M_OPAQUE)))
            # spill 清除：把 R/B 朝 G 拉回，消掉粉色描边
            k = alpha / 255.0
            r2 = int(g + (r - g) * k)
            b2 = int(g + (b - g) * k)
            px[x, y] = (r2, g, b2, alpha)
    # 硬性兜底：色相落在品红带且饱和度极高 -> 直接透明（处理少量漏网）
    hsv = img.convert("RGBA").convert("HSV")
    hsv_px = hsv.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ss, vv = hsv_px[x, y]
            hue = hh * 360.0 / 255.0
            if HUE_LO <= hue <= HUE_HI and ss >= int(SPILL_SAT * 255.0):
                px[x, y] = (0, 0, 0, 0)
    return img


def autocrop(img: Image.Image, thresh: int = 8) -> Image.Image:
    """按 alpha 包围盒裁剪（阈值 thresh 以上算内容）。"""
    alpha = img.getchannel("A")
    bbox = alpha.point(lambda v: 255 if v > thresh else 0).getbbox()
    if bbox is None:
        raise ValueError("autocrop: 全透明图")
    return img.crop(bbox)


def scale_to(img: Image.Image, max_side: int) -> Image.Image:
    """等比缩放到最长边 = max_side（LANCZOS，向下缩小质量最好）。"""
    w, h = img.size
    s = max_side / float(max(w, h))
    if s >= 1.0:
        return img
    nw = max(1, int(round(w * s)))
    nh = max(1, int(round(h * s)))
    return img.resize((nw, nh), Image.LANCZOS)


def load_cut(prefix: str) -> Image.Image | None:
    """按前缀取源图并完成去背 + 裁包围盒；无唯一匹配返回 None。"""
    matches = sorted(SRC_DIR.glob(prefix + "-*.jpg"))
    if len(matches) != 1:
        return None
    return autocrop(chroma_key(Image.open(matches[0])))


def bake_sword(cut: Image.Image, blade_w: int, blade_h: int,
               blade_x: tuple[int, int], blade_y: tuple[int, int]) -> Image.Image:
    """飞剑非等比烘焙：剑刃缩放到 (blade_w, blade_h)，刃部中心对齐画布中心。

    cut        已去背裁包围盒的源图（剑尖朝右，拖尾在左）
    blade_w/h  剑刃目标宽/高（宽贴 34x10 碰撞盒；高为纵向加粗，非等比）
    blade_x    剑刃 x 范围（源图坐标，闭区间）—— 决定横向缩放比
    blade_y    剑刃厚度锚带 y 范围（源图坐标）—— 决定纵向缩放比
    画布向四周对称扩边，把刃中心推到画布中心；剑柄/拖尾留在刃部左侧，
    不参与居中，画布右半为等量透明留白（几十字节量级，换取资产自对齐）。
    """
    bx0, bx1 = blade_x
    by0, by1 = blade_y
    # 锚点守卫：源图更换后坐标失配会静默错位，这里显式失败
    if cut.getchannel("A").crop(
            (bx0, by0, bx1 + 1, by1 + 1)).getextrema()[1] <= 8:
        raise ValueError("bake_sword: 剑刃锚点区域无内容，源图可能已更换，请重新测量")
    sx = blade_w / float(bx1 - bx0 + 1)
    sy = blade_h / float(by1 - by0 + 1)
    tw = max(1, int(round(cut.width * sx)))
    th = max(1, int(round(cut.height * sy)))
    img = cut.resize((tw, th), Image.LANCZOS)
    bcx = (bx0 + bx1 + 1) / 2.0 * sx   # 刃中心 x（新图坐标）
    byc = (by0 + by1 + 1) / 2.0 * sy   # 刃中心 y（新图坐标）
    W = max(tw, int(round(2.0 * bcx)))
    H = max(th, int(round(2.0 * max(byc, th - byc))))
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.paste(img, (int(round(W / 2.0 - bcx)), int(round(H / 2.0 - byc))), img)
    return canvas


def make_bg(src: Path) -> Image.Image:
    """背景图：满画幅 16:9，中心裁剪 -> 1280x720，不去背。"""
    img = Image.open(src).convert("RGB")
    w, h = img.size
    target_ratio = 16.0 / 9.0
    if w / h > target_ratio:
        nw = int(round(h * target_ratio))
        x0 = (w - nw) // 2
        img = img.crop((x0, 0, x0 + nw, h))
    else:
        nh = int(round(w / target_ratio))
        y0 = (h - nh) // 2
        img = img.crop((0, y0, w, y0 + nh))
    return img.resize((1280, 720), Image.LANCZOS)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    report: list[str] = []
    for key, (prefix, max_side) in sorted(SPRITES.items()):
        cut = load_cut(prefix)
        if cut is None:
            report.append(f"[MISS] {key}: prefix={prefix}")
            continue
        out = scale_to(cut, max_side)
        dst = OUT_DIR / (key + ".png")
        out.save(dst)
        report.append(f"[OK] {key}.png {out.size[0]}x{out.size[1]}"
                      f"  (src {cut.size[0]}x{cut.size[1]})")
    for key, (prefix, bw, bh, bx, by) in sorted(SWORDS.items()):
        cut = load_cut(prefix)
        if cut is None:
            report.append(f"[MISS] {key}: prefix={prefix}")
            continue
        out = bake_sword(cut, bw, bh, bx, by)
        dst = OUT_DIR / (key + ".png")
        out.save(dst)
        report.append(f"[OK] {key}.png {out.size[0]}x{out.size[1]}"
                      f"  (src {cut.size[0]}x{cut.size[1]},"
                      f" 剑刃 {bw}x{bh} 居中)")
    bg_matches = sorted(SRC_DIR.glob(BG_FILE + "-*.jpg"))
    if len(bg_matches) != 1:
        report.append(f"[MISS] {BG_KEY}: matches={len(bg_matches)}")
    else:
        bg = make_bg(bg_matches[0])
        bg.save(OUT_DIR / (BG_KEY + ".png"))
        report.append(f"[OK] {BG_KEY}.png {bg.size[0]}x{bg.size[1]} (no key)")
    build_robe_test()
    print("\n".join(report))
    return 0


def build_robe_test() -> None:
    """玩家道袍多尺寸对照表：模拟游戏内 1x 渲染（最近邻），供人工判定。"""
    cells: list[tuple[str, list[Image.Image]]] = []
    for key in ("player_red", "player_blue", "player_white", "player_yellow"):
        src = OUT_DIR / (key + ".png")
        if not src.exists():
            continue
        img = Image.open(src).convert("RGBA")
        sizes = [22, 32, 44, 64, 96, 160]
        row: list[Image.Image] = []
        for s in sizes:
            # 等比：以高度为准（人形立绘竖长）
            w = max(1, int(round(img.width * s / img.height)))
            # 先 LANCZOS 缩小到 2 倍目标，再 NEAREST 到目标 —— 模拟纹理过滤
            tmp = img.resize((w * 2, s * 2), Image.LANCZOS)
            row.append(tmp.resize((w, s), Image.NEAREST))
        cells.append((key, row))
    if not cells:
        return
    sizes = [22, 32, 44, 64, 96, 160]
    pad, label = 12, 22
    row_h = max(im.height for _, row in cells for im in row) + label + pad
    col_w = [max(row[i].width for _, row in cells) + pad for i in range(len(sizes))]
    W = sum(col_w) + pad
    H = len(cells) * row_h + pad + 30
    sheet = Image.new("RGBA", (W, H), (24, 22, 34, 255))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(sheet)
    for i, s in enumerate(sizes):
        x = pad + sum(col_w[:i])
        dr.text((x, 4), f"h={s}px", fill=(255, 230, 120, 255))
    for r, (key, row) in enumerate(cells):
        y = pad + 30 + r * row_h
        dr.text((4, y + label + 2), key, fill=(180, 200, 255, 255))
        for i, im in enumerate(row):
            x = pad + sum(col_w[:i]) + (col_w[i] - pad - im.width) // 2
            sheet.paste(im, (x, y + label), im)
    sheet.convert("RGB").save(Path(r"D:\demo\_robe_test.png"))
    print(f"[OK] robe test -> D:\\demo\\_robe_test.png")


if __name__ == "__main__":
    sys.exit(main())
