"""侧身道袍结构自检：ASCII 转储 + 关键区域取色。
不依赖眼睛看图，用字符画和包围盒确认「剪画像不像一个人」。
"""
from PIL import Image

P = r"D:\demo\xiuxian-danmaku\assets\sprites\robe_red.png"
im = Image.open(P).convert("RGBA")
W, H = im.size
px = im.load()

# 字符映射：按像素在调色板里的角色分类
SKIN = (255, 222, 184)
HAIR = (26, 26, 38)


def cls(p):
    r, g, b, a = p
    if a < 40:
        return "."
    if abs(r - SKIN[0]) < 12 and abs(g - SKIN[1]) < 12 and abs(b - SKIN[2]) < 12:
        return "F"          # 脸/肤
    if abs(r - HAIR[0]) < 14 and abs(g - HAIR[1]) < 14 and abs(b - HAIR[2]) < 14:
        return "K"          # 发
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum > 235:
        return "o"          # 高光/ crown
    if lum > 150:
        return "G"          # 亮部（MAIN / GLOW）
    if lum > 60:
        return "M"          # 中间调（DARK / 阴影）
    return "#"              # 描边


print("== ASCII %dx%d ==" % (W, H))
for y in range(H):
    row = "".join(cls(px[x, y]) for x in range(W))
    print("%2d %s" % (y, row))


def bbox(pred):
    xs, ys = [], []
    for y in range(H):
        for x in range(W):
            if pred(px[x, y]):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


op = lambda p: p[3] > 40
print("\n== 包围盒 ==")
print("不透明整体   :", bbox(op))
print("肤色 F       :", bbox(lambda p: cls(p) == "F"))
print("发色 K       :", bbox(lambda p: cls(p) == "K"))
print("高光 o       :", bbox(lambda p: cls(p) == "o"))
