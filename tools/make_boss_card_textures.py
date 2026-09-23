"""把 AI 生成的五张 Boss 模型图裁成关卡选择卡面贴图（184x104 @2x = 368x208）。

处理三步：
  1) 中心裁到 1.769 宽高比（1018/... = 184/104），再 LANCZOS 缩到 368x208
  2) 四边羽化 alpha（高斯模糊遮罩）—— 贴图融进卡底，不出现硬边矩形
  3) 锁态版 = 灰度去色 + 亮度 x0.72（§I.3「去色即锁」，与卡面其余锁态一致）

幂等：重复运行覆盖同名文件，结果一致。
"""

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import os

OUT = r"D:/demo/xiuxian-danmaku/assets/sprites"
SRC = {
    1: r"D:/demo/_boss_l1_ai_v2.png",
    2: r"D:/demo/_boss_l2_ai_v2.png",
    3: r"D:/demo/_boss_l3_ai_v2.png",
    4: r"D:/demo/_boss_l4_ai_v2.png",
    5: r"D:/demo/_boss_l5_ai_v2.png",
}

TW, TH = 368, 208          # 目标（卡面 184x104 的 2 倍超采样）
RATIO = 184.0 / 104.0      # 1.769


def feather(w: int, h: int) -> Image.Image:
    """四边内缩后高斯模糊 = 边缘 alpha 渐隐"""
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rectangle([30, 16, w - 30, h - 16], fill=255)
    return m.filter(ImageFilter.GaussianBlur(16))


def main() -> None:
    mask = feather(TW, TH)
    for n, path in SRC.items():
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(round(w / RATIO))
        top = max(0, (h - th) // 2)
        im = im.crop((0, top, w, top + th)).resize((TW, TH), Image.LANCZOS)
        im.putalpha(mask)
        im.save(os.path.join(OUT, "boss_card_l%d.png" % n))

        gray = im.convert("RGB").convert("L").convert("RGB")
        gray = ImageEnhance.Brightness(gray).enhance(0.72)
        gray.putalpha(mask)
        gray.save(os.path.join(OUT, "boss_card_l%d_lock.png" % n))
        print("ok l%d  crop %dx%d -> %dx%d" % (n, w, th, TW, TH))


if __name__ == "__main__":
    main()
