"""临时工具：把源图目录拼成一张联络表（带编号），用于人工核对映射。"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path(r"D:\demo\xiuxian-level-assets_assets")
OUT = Path(r"D:\demo\_contact.png")

files = sorted(SRC.glob("*.jpg"))
cols = 5
cell = 300
lab = 26
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * (cell + lab)), (18, 18, 24))
dr = ImageDraw.Draw(sheet)

for i, f in enumerate(files):
    im = Image.open(f).convert("RGB")
    im.thumbnail((cell - 8, cell - 8))
    r, c = divmod(i, cols)
    x = c * cell + (cell - im.width) // 2
    y = r * (cell + lab) + lab + (cell - lab - im.height) // 2
    sheet.paste(im, (x, y))
    dr.text((c * cell + 6, r * (cell + lab) + 6), f"[{i:02d}] {f.name[:22]}", fill=(255, 230, 120))

sheet.save(OUT)
print(f"files={len(files)} -> {OUT}")
for i, f in enumerate(files):
    print(f"{i:02d}\t{f.name}")
