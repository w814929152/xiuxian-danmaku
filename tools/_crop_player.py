"""从实机帧里裁出玩家区域并放大，核对游戏内实际观感。"""
from PIL import Image

# 帧里玩家大致位置（左上山坡处）
REGIONS = {
    r"D:\demo\_frame_a.png": (190, 305),
    r"D:\demo\_frame_b.png": (190, 305),
    r"D:\demo\_frame_c.png": (190, 305),
}

crops = []
for path, (cx, cy) in REGIONS.items():
    im = Image.open(path).convert("RGBA")
    # 找红袍主色像素质心（限定在粗定位框内），避免手动坐标偏移
    box = (max(0, cx - 120), max(0, cy - 90), cx + 120, cy + 90)
    reg = im.crop(box)
    px = reg.load()
    sx = sy = n = 0
    for y in range(reg.height):
        for x in range(reg.width):
            r, g, b, a = px[x, y]
            # 赤炎袍 MAIN: 偏红、明度中高
            if r > 140 and g < 90 and b < 100 and a > 200:
                sx += x
                sy += y
                n += 1
    if n > 30:
        cx2 = box[0] + sx // n
        cy2 = box[1] + sy // n
    else:
        cx2, cy2 = cx, cy
    half = 34
    crop = im.crop((max(0, cx2 - half), max(0, cy2 - half),
                    min(im.width, cx2 + half), min(im.height, cy2 + half)))
    crops.append((path[-6:-4], crop, (cx2, cy2)))

W = sum(c.width for _, c, _ in crops) * 6 + 40
H = max(c.height for _, c, _ in crops) * 6 + 30
canvas = Image.new("RGBA", (W, H), (18, 18, 28, 255))
x = 20
for tag, c, pos in crops:
    big = c.resize((c.width * 6, c.height * 6), Image.NEAREST)
    canvas.alpha_composite(big, (x, 10))
    x += big.width + 20
    print(tag, "centroid=", pos, "crop=", c.size)
canvas.save(r"D:\demo\_player_ingame.png")
print("OK -> D:/demo/_player_ingame.png", canvas.size)
