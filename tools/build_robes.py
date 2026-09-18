# -*- coding: utf-8 -*-
"""build_robes.py —— 手绘像素道袍（玩家 in-game sprite），不经过 AI 生成。

为什么手写而不是把 1024px 立绘缩小：
  立绘是「细节丰富的插画」，缩到 20~36px 高时所有细节平均成糊团（实测过：
  h=22 不可辨，h≈30 是临界，h≥44 才清晰）。而游戏内玩家只有 40x22 上下，
  靠放大尺寸去迁就立绘会破坏已调好的手感。所以反过来：为这个尺寸重新设计。

姿态：**侧面（朝右）的修士人形**。
  改过三版，顺序记下来免得再绕：
  1. 水平飞行抽象体（沿袭旧矢量）—— 读作「一个头拖着一条尾巴」，不是人。
  2. 正面站立人形 —— 是人了，但正面与横版飞行朝向不符，且看不出髻位和袍裾走势。
  3. 侧面（当前）—— 与前两版的结构差异：
       · 脸：前半脸 + **鼻梁凸起 1px** + 一只眼（正脸是整张脸 + 两只眼）
       · 发髻：**后脑上方**，不是头顶正中（这才是侧视的髻位）
       · 手臂：**近侧单臂前抬**（施法/御剑姿态），不是对称双袖
       · 袍裾：**向后（左）拖曳**，与飞行方向一致，不是左右对称展开
  > 教训：姿态错了，堆再多服饰元素也救不回来（第 1 版五样元素全加仍不像人）。
  > 「水平飞行」是从旧矢量沿袭的约束，我没有质疑它，而它恰是「像人」的对立面。

设计约束（改图前先读）：
  · 画布 44x36，节点原点 = 画布中心 (22,18)。侧面人形**不左右对称**（袍裾向后拖、
    手臂前抬），所以包围盒中心 ≠ 画布中心 —— 判定点落在**腹部**即可，别去居中它。
    对齐靠烘焙保证，运行时零 offset（同 tools/build_sprites.py 里飞剑的做法）。
  · 越出剪影的内部元素一律与袍身掩膜求交（ImageChops.darker）；
    但**前抬的手臂是向外伸出的，不能求交** —— 求交只会剩下与躯干重叠的部分。
  · 四件道袍**共用同一基础剪影**。剪影改过三版才「像人」，绝不再逐件重画；
    差异化全部走**外挂部件**（见 EXTRAS 一节），且一律挂在轮廓外围。

「看得出是修仙道袍」靠这五个元素，删任何一个辨识度都会掉一档：
  1. 交领（CORE 亮内襟 + DARK 深边）—— 汉服/道袍最强识别点，一条斜线就够
  2. 广袖（SHADE 色块 + 1px DARK 袖缘，近侧单臂前抬）
  3. 腰带（GLOW 横带，分出上下身）
  4. 袍裾（向后拖曳，下端 4 行压暗）
  5. 发髻 + 冠（修仙身份）
鼻梁那 1px 凸起是侧视的关键 —— 没有它，侧面头就是个圆。

---------------------------------------------------------------- 差异化部件（EXTRAS）
只换配色时，玩家切换后余光扫过并不总能立刻判断「我现在穿的是哪件」。
所以四件各挂 1~2 个**形状层面**的身份部件，对应「攻 / 速 / 守 / 术」四种气质：

  赤炎（火行·攻）：手前**双剑** —— 剑诀自生双影；矢量全部朝前 = 攻
  玄冰（水行·速）：**后掠飘带** + 袍角薄霜 —— 步履生风，矢量朝后 = 速
  太清（无行·守）：**罡气罩** + 护肩 —— 加厚体积、轮廓闭合无尖角 = 守
  戊土（土行·术）：冠上符片 + 手前**悬符** —— 悬挂物而非刺出物 = 术

四条纪律（改部件前先读）：
  1. **颜色是属性识别的第一载体**（颜色 = 免疫什么），所以部件只用本袍的
     CORE/GLOW/DARK 或中性灰，绝不引入新色相 —— 给玄冰加青、给赤炎加紫
     都会污染「颜色 = 属性」这套语义。
  2. 部件只挂**轮廓外围**（头顶 / 身后 / 手前 / 袍角），不碰脸（x22..30,y7..15）、
     不碰躯干中央 —— 中央留给交领和腰带。
  3. **双剑必须有竖直护手**：弹幕射击里身前两道水平亮条会先被读成「子弹」
     而不是剑。靠「护手 + 上下对称两刃」的十字结构破义。
  4. 护肩要**先画（在头部之前绘制）**：护肩 y13..17 与下巴重叠，先画就会被后画的
     脸盖住 —— 正好是「肩在下巴之后」的正确层序；若画在头之后，护肩会盖住下巴，
     变成糊脸的色块。

用法：python tools/build_robes.py     （幂等，重跑覆盖）
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT_DIR = Path(r"D:\demo\xiuxian-danmaku\assets\sprites")

W, H = 44, 36
CX, CY = 22, 18

# Game.gd 的 COLOR_MAIN / COLOR_GLOW / COLOR_DARK / COLOR_CORE（顺序 RED/BLUE/WHITE/YELLOW）
MAIN = [(0.98, 0.24, 0.27), (0.22, 0.62, 1.00), (0.93, 0.96, 1.00), (1.00, 0.80, 0.14)]
GLOW = [(1.00, 0.56, 0.24), (0.45, 0.86, 1.00), (0.84, 0.92, 1.00), (1.00, 0.93, 0.42)]
DARK = [(0.40, 0.04, 0.09), (0.03, 0.16, 0.40), (0.28, 0.32, 0.42), (0.38, 0.26, 0.02)]
CORE = [(1.00, 0.94, 0.80), (0.90, 0.98, 1.00), (1.00, 1.00, 1.00), (1.00, 0.99, 0.82)]
NAMES = ["red", "blue", "white", "yellow"]

# ---------------------------------------------------------------- 形状（画布坐标）
# 袍身（侧视，朝右）：颈(y15) -> 胸前 -> 前摆 -> 裾(y34) -> 向后拖 -> 背
BODY = [(19, 15), (26, 15), (28, 18), (29, 23), (30, 30), (28, 34),
        (9, 34), (13, 28), (16, 22), (16, 16)]
# 广袖：近侧单臂自肩前抬（施法/御剑）。向外伸出，不求交。
SLEEVE = [(24, 16), (31, 17), (35, 21), (31, 25), (23, 22)]
SASH = (15, 24, 29, 25)         # 腰带（横带）
COLLAR = [(21, 16), (27, 21), (27, 24)]   # 交领：自后颈斜下过胸
HEAD = (23, 10, 5)              # 头（发）圆心 + 半径
KNOT = (20, 5, 3)               # 发髻：侧视在后脑上方，不是头顶正中
CROWN = (18, 3, 22, 4)          # 冠：发髻上的亮色横带
FACE = (25, 11, 3, 4)           # 前半脸（侧视只露前脸）
NOSE = [(28, 11), (29, 11)]     # 鼻梁：向前的 1px 凸起，侧视关键
EYE = [(26, 10), (26, 11)]      # 单眼（侧视）

## 脸是**固定肤色**，不随袍色走：白袍的 MAIN 是 (0.93,0.96,1.00) 近乎纯白，
## 若脸也按袍色推导就会和袍身糊成一片，头直接「没了」—— 这个尺寸下头部是唯一
## 能读出「人」的信息，必须保证它在四色袍上都跳出来。（深色发环同理恒为 DARK。）
SKIN = (1.00, 0.87, 0.72)

# ---------------------------------------------------------------- 差异化部件
## 霜 / 罡气 / 金属这类「无色」材质用中性灰，四袍通用且不引入新色相。
NEUTRAL = (0.74, 0.78, 0.86)

# 赤炎剑袍 · 火行·攻 —— 手前双剑（竖直护手 + 上下对称两刃）+ 火尖冠
SWORD_GUARD = (35, 16, 36, 25)     # 护手：竖直、中性灰金属色 —— 破「水平亮条 = 弹幕」
SWORD_BLADE_TOP = (37, 16, 40, 17)
SWORD_BLADE_BOT = (37, 24, 40, 25)
SWORD_TIP_TOP = [(40, 16), (42, 17), (40, 17)]   # 刃尖收锋：楔形才读作「刃」
SWORD_TIP_BOT = [(40, 24), (42, 25), (40, 25)]
FLAME_CROWN = [(18, 5), (22, 5), (21, 1), (19, 1)]

# 玄冰遁袍 · 水行·速 —— 后掠飘带 + 袍角薄霜
RIBBON = [(17, 4), (19, 6), (7, 10), (5, 8)]
FROST = [(12, 32), (18, 33)]       # 霜晶中心（压在袍裾末端，不悬空）
FROST_R = 2

# 太清罡袍 · 无行·守 —— 身前罡气罩（三段，留白让它是「悬浮的罩」不是「又一个袖子」）
WARD_SEGS = [(36, 15, 37, 19), (38, 20, 39, 25), (36, 26, 37, 30)]
PAULDRON = [(16, 13), (26, 14), (27, 17), (16, 16)]   # 护肩：加厚体积 = 守

# 戊土符袍 · 土行·术 —— 冠上符片 + 手前悬符（纸 = CORE，框与符文 = DARK）
# 符片只压发髻上半，下半的髻要留着 —— 发髻是「修仙身份」的识别点，不能被符纸吃掉。
TALI_CROWN = (19, 1, 23, 4)
TALI_CROWN_IN = (20, 2, 22, 3)
TALI_HAND = (36, 18, 40, 25)
TALI_HAND_IN = (37, 19, 39, 24)
TALI_GLYPHS = [(37, 20, 39, 20), (37, 22, 39, 22)]

HEM_SHADE_ROW = 31  # 袍裾 >= 该行压暗（下端 4 行）
## 暗部用 MAIN/DARK 的中间色而不是纯 DARK —— 纯 DARK 对红袍是 (102,10,23)，
## 在深色夜空底上几乎等于隐形，实测会让袍裾下端直接消失。
SHADE_MIX = 0.55    # 0=MAIN，1=DARK


def _mask(draw_fn) -> Image.Image:
    """在空白 L 图上执行 draw_fn，返回该形状的掩膜。"""
    m = Image.new("L", (W, H), 0)
    draw_fn(ImageDraw.Draw(m), 255)
    return m


def _poly_mask(pts) -> Image.Image:
    return _mask(lambda d, fill: d.polygon(pts, fill=fill))


def _ellipse_mask(bbox) -> Image.Image:
    return _mask(lambda d, fill: d.ellipse(bbox, fill=fill))


def _band(lo: int, hi: int) -> Image.Image:
    return _mask(lambda d, fill: d.rectangle((0, lo, W - 1, hi), fill=fill))


def _rect_mask(r: tuple[int, int, int, int]) -> Image.Image:
    return _mask(lambda d, fill: d.rectangle(r, fill=fill))


def _talisman(dark, paper, outer, inner, glyphs) -> list[tuple]:
    """符箓：DARK 外框 + CORE 纸面 + DARK 符文，返回 [(色, 掩膜)] 供 put 依次画。"""
    return ([(dark, _rect_mask(outer)), (paper, _rect_mask(inner))]
            + [(dark, _rect_mask(g)) for g in glyphs])


def _inside(shape: Image.Image, region: Image.Image) -> Image.Image:
    """形状 ∩ 区域（裁掉越出剪影的部分）。"""
    return ImageChops.darker(shape, region)


def build_robe(ci: int) -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def rgb(t: tuple[float, float, float]) -> tuple[int, int, int, int]:
        return (int(round(t[0] * 255)), int(round(t[1] * 255)),
                int(round(t[2] * 255)), 255)

    main, glow, dark, core = MAIN[ci], GLOW[ci], DARK[ci], CORE[ci]
    outline = tuple(dark[i] * 0.55 for i in range(3))
    shade = tuple(main[i] * (1.0 - SHADE_MIX) + dark[i] * SHADE_MIX for i in range(3))

    def put(color, mask: Image.Image) -> None:
        if mask.getextrema()[1] == 0:
            raise ValueError("build_robe: 空掩膜，形状参数可能失配")
        img.paste(rgb(color), (0, 0), mask)

    body = _poly_mask(BODY)

    # 1) 袍身；下端压暗
    put(main, body)
    put(shade, _inside(body, _band(HEM_SHADE_ROW, H - 1)))

    # 2) 腰带（分出上下身）
    put(glow, _inside(_mask(lambda d, f: d.rectangle(SASH, fill=f)), body))

    # 3) 广袖（近侧单臂前抬）+ 1px 袖缘
    #    袖缘不是装饰：袖子与袍身只差一级明度，没有勾边就会糊成一团阴影。
    put(shade, _poly_mask(SLEEVE))
    put(dark, _mask(lambda d, f: d.polygon(SLEEVE, outline=f)))

    # 3.5) 太清罡袍的护肩：加厚体积 = 「守」。必须画在交领与头**之前** ——
    #      护肩 y13..17 与下巴、领口重叠，先画就会被后画者盖住，得到正确的层序；
    #      若画在后面，它会盖住下巴变成一块糊在脸上的色块。
    if ci == 2:
        put(NEUTRAL, _poly_mask(PAULDRON))
        put(dark, _mask(lambda d, f: d.polygon(PAULDRON, outline=f)))

    # 4) 交领：先 DARK 粗边再 CORE 细芯，深浅并排 —— 白袍靠深边、其余靠亮芯，
    #    保证四色袍上领口都看得见
    collar = _mask(lambda d, f: d.line(COLLAR, fill=f, width=3, joint="curve"))
    put(dark, _inside(collar, body))
    put(core, _inside(_mask(
        lambda d, f: d.line(COLLAR, fill=f, width=1, joint="curve")), body))

    # 5) 头：发 -> 前脸 -> 鼻梁 -> 眼 -> 发髻 -> 冠
    hx, hy, hr = HEAD
    put(dark, _ellipse_mask((hx - hr, hy - hr, hx + hr, hy + hr)))
    fx, fy, frx, fry = FACE
    put(SKIN, _ellipse_mask((fx - frx, fy - fry, fx + frx, fy + fry)))
    put(SKIN, _mask(lambda d, f: [d.point((nx, ny), fill=f) for nx, ny in NOSE]))
    put(dark, _mask(lambda d, f: [d.point((ex, ey), fill=f) for ex, ey in EYE]))
    kx, ky, kr = KNOT
    knot = _ellipse_mask((kx - kr, ky - kr, kx + kr, ky + kr))
    put(dark, knot)
    put(glow, _inside(_mask(lambda d, f: d.rectangle(CROWN, fill=f)), knot))

    # 6) 差异化部件（按袍性）：只挂轮廓外围，不碰脸与躯干中央
    if ci == 0:      # 赤炎剑袍 · 火行·攻 —— 双剑（护手 = 十字结构的关键）+ 火尖冠
        put(NEUTRAL, _rect_mask(SWORD_GUARD))
        put(core, _rect_mask(SWORD_BLADE_TOP))
        put(core, _rect_mask(SWORD_BLADE_BOT))
        put(core, _poly_mask(SWORD_TIP_TOP))
        put(core, _poly_mask(SWORD_TIP_BOT))
        put(glow, _poly_mask(FLAME_CROWN))
    elif ci == 1:    # 玄冰遁袍 · 水行·速 —— 后掠飘带 + 袍角凝霜
        put(glow, _poly_mask(RIBBON))
        for fx0, fy0 in FROST:
            put(NEUTRAL, _poly_mask([(fx0, fy0 - FROST_R), (fx0 + FROST_R, fy0),
                                     (fx0, fy0 + FROST_R), (fx0 - FROST_R, fy0)]))
    elif ci == 2:    # 太清罡袍 · 无行·守 —— 身前罡气罩（护肩已在 3.5 画过）
        for seg in WARD_SEGS:
            put(NEUTRAL, _rect_mask(seg))
    else:            # 戊土符袍 · 土行·术 —— 冠上符片 + 手前悬符
        for col, msk in _talisman(dark, core, TALI_CROWN, TALI_CROWN_IN, []):
            put(col, msk)
        # 冠符太小放不下符文，用一竖笔代替（符箓的中锋）
        put(dark, _rect_mask((21, 2, 21, 3)))
        for col, msk in _talisman(dark, core, TALI_HAND, TALI_HAND_IN, TALI_GLYPHS):
            put(col, msk)

    # 描边：剪影外扩 1px（画在最后，只落在图形外侧，不会覆盖内部像素）
    sil = img.getchannel("A")
    out = ImageChops.subtract(sil.filter(ImageFilter.MaxFilter(3)), sil)
    img.paste(rgb(outline), (0, 0), out)
    return img


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for i, name in enumerate(NAMES):
        img = build_robe(i)
        img.save(OUT_DIR / f"robe_{name}.png")
        print(f"[OK] robe_{name}.png {img.size[0]}x{img.size[1]}")
    build_preview()
    return 0


def build_preview() -> None:
    """对照图：1x 实际尺寸 / 6x 放大 / 与弹幕的尺度对比。"""
    from PIL import ImageDraw
    Z = 6
    bullet_p = OUT_DIR / "danmaku.png"
    bullet = Image.open(bullet_p).convert("RGBA") if bullet_p.exists() else None
    bg = (28, 30, 46)
    pad = 10
    W2 = pad + (W * Z + pad) * 4
    H2 = pad + 14 + H + 14 + 14 + H * Z + 22 + 14 + H + pad
    sh = Image.new("RGB", (W2, H2), bg)
    d = ImageDraw.Draw(sh)
    imgs = [Image.open(OUT_DIR / f"robe_{n}.png").convert("RGBA") for n in NAMES]

    d.text((pad, pad), f"1x  ({W}x{H}, in-game)", fill=(210, 220, 245))
    y1 = pad + 14
    for i, im in enumerate(imgs):
        sh.paste(im, (pad + i * (W + pad), y1), im)

    d.text((pad, y1 + H + 14), "6x  (NEAREST)", fill=(210, 220, 245))
    y2 = y1 + H + 28
    for i, im in enumerate(imgs):
        big = im.resize((W * Z, H * Z), Image.NEAREST)
        sh.paste(big, (pad + i * (W * Z + pad), y2), big)
        d.text((pad + i * (W * Z + pad) + 4, y2 + H * Z + 6), NAMES[i].upper(),
               fill=(210, 220, 245))

    y3 = y2 + H * Z + 22
    d.text((pad, y3), "scale: player vs bullet (1x)", fill=(210, 220, 245))
    y4 = y3 + 14
    sh.paste(imgs[0], (pad, y4), imgs[0])
    if bullet is not None:
        bt = Image.new("RGBA", bullet.size)
        bt.paste(Image.new("RGB", bullet.size, (255, 60, 50)), (0, 0), bullet)
        sh.paste(bt, (pad + W + 24, y4 + (H - bullet.height) // 2), bt)
    sh.save(r"D:\demo\_robe_preview.png")
    print(r"[OK] preview -> D:\demo\_robe_preview.png")


if __name__ == "__main__":
    raise SystemExit(main())
