"""生成「错题单词本」Android 图标资源。

设计：靛蓝渐变底 + 白色卡片 + 字母 A + 橙色对勾徽标（表示「已掌握/已订正」）。
输出两套：
  1. 传统方形图标 ic_launcher.png（全出血，各密度）
  2. 自适应图标前景 ic_launcher_foreground.png（透明底，主体缩到 66% 安全区）
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

S = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# 品牌色（与 AppTheme.seed = #5B7CFA 同族）
C_TOP = (74, 112, 96)      # #4A7060 浅墨绿
C_BOTTOM = (33, 66, 55)     # #214237 深墨绿
C_CARD = (255, 253, 248)    # 暖纸白
C_LETTER = (47, 90, 75)     # #2F5A4B 墨绿
C_BADGE = (181, 101, 74)    # #B5654A 陶土
C_CHECK = (255, 255, 255)

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\seguisb.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def gradient(size):
    """对角线性渐变（先算小图再放大，避免旋转产生的对角硬边）。"""
    small = 96
    stamp = Image.new("RGB", (small, small))
    px = stamp.load()
    for y in range(small):
        for x in range(small):
            # 沿左上 → 右下方向过渡
            t = (x / (small - 1) * 0.55 + y / (small - 1) * 0.45)
            t = min(max(t, 0.0), 1.0)
            px[x, y] = (
                int(C_TOP[0] + (C_BOTTOM[0] - C_TOP[0]) * t),
                int(C_TOP[1] + (C_BOTTOM[1] - C_TOP[1]) * t),
                int(C_TOP[2] + (C_BOTTOM[2] - C_TOP[2]) * t),
            )
    return stamp.resize((size, size), Image.BICUBIC)


def draw_motif(canvas_size, scale=1.0):
    """在透明画布上绘制主体，scale=1.0 时主体占满（用于方形图标）。"""
    W = canvas_size
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # —— 主体尺寸（相对画布）——
    base = W * 0.60 * scale          # 前景卡片边长
    cx, cy = W / 2, W / 2 + W * 0.012

    card_w = base
    card_h = base * 1.12
    left = cx - card_w / 2
    top = cy - card_h / 2

    # —— 背后那张卡片（斜置、半透明白）——
    back = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back)
    bl, bt = left + base * 0.04, top - base * 0.10
    bd.rounded_rectangle(
        [bl, bt, bl + card_w, bt + card_h],
        radius=int(base * 0.17),
        fill=(255, 255, 255, 66),
    )
    back = back.rotate(-9, resample=Image.BICUBIC, center=(cx, cy))
    layer = Image.alpha_composite(layer, back)

    # —— 卡片投影 ——
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = base * 0.045
    sd.rounded_rectangle(
        [left, top + off, left + card_w, top + card_h + off],
        radius=int(base * 0.17),
        fill=(23, 32, 92, 90),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=base * 0.055))
    layer = Image.alpha_composite(layer, shadow)

    # —— 前景白卡 ——
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        [left, top, left + card_w, top + card_h],
        radius=int(base * 0.17),
        fill=C_CARD + (255,),
    )

    # 卡片顶部的一条淡靛蓝装饰（模拟书脊/标签）
    d.rounded_rectangle(
        [left + card_w * 0.16, top + card_h * 0.115,
         left + card_w * 0.62, top + card_h * 0.115 + card_h * 0.035],
        radius=int(card_h * 0.02),
        fill=(47, 90, 75, 28),
    )

    # —— 字母 A ——
    font = load_font(int(card_h * 0.60))
    text = "A"
    bbox = font.getbbox(text)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    glyph_cx = cx
    # 卡片内视觉中心略微下移，抵消顶部装饰条的重量
    glyph_cy = top + card_h * 0.55
    tx = glyph_cx - tw / 2 - bbox[0]
    ty = glyph_cy - th / 2 - bbox[1]
    d.text((tx, ty), text, font=font, fill=C_LETTER + (255,))

    # —— 橙色对勾徽标 ——
    r = base * 0.175
    bx, by = left + card_w * 0.875, top + card_h * 0.875
    d.ellipse([bx - r, by - r, bx + r, by + r], fill=C_BADGE + (255,))

    cw = r * 0.95
    pts = [
        (bx - cw * 0.42, by + cw * 0.02),
        (bx - cw * 0.10, by + cw * 0.34),
        (bx + cw * 0.48, by - cw * 0.34),
    ]
    d.line(pts, fill=C_CHECK + (255,), width=int(r * 0.26), joint="curve")
    for p in (pts[0], pts[2]):
        d.ellipse(
            [p[0] - r * 0.13, p[1] - r * 0.13, p[0] + r * 0.13, p[1] + r * 0.13],
            fill=C_CHECK + (255,),
        )

    return layer


def make_full_icon():
    """方形图标：渐变底 + 主体。"""
    bg = gradient(S).convert("RGB")
    fg = draw_motif(S, scale=1.0)
    out = bg.convert("RGBA")
    out = Image.alpha_composite(out, fg)
    return out.convert("RGB")


def make_foreground():
    """自适应图标前景：透明底，主体缩到安全区（66.7%）。"""
    return draw_motif(S, scale=0.73)


def make_background():
    """自适应图标背景：纯渐变，全出血。"""
    return gradient(S).convert("RGB")


def circular_preview(bg, fg, out_path, px=512):
    """模拟启动器的圆形遮罩效果，方便肉眼确认。"""
    canvas = bg.resize((px, px), Image.LANCZOS).convert("RGBA")
    canvas = Image.alpha_composite(canvas, fg.resize((px, px), Image.LANCZOS))
    mask = Image.new("L", (px, px), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, px, px], fill=255)
    rounded = Image.new("RGBA", (px, px), (255, 255, 255, 0))
    rounded.paste(canvas, (0, 0), mask)
    rounded.save(out_path)


LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)
    print("  ", os.path.relpath(path, ROOT), f"{size}x{size}")


def main():
    full = make_full_icon()
    fg = make_foreground()
    bg = make_background()

    # 预览图（放进 assets 方便查看）
    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    full.resize((512, 512), Image.LANCZOS).save(
        os.path.join(ROOT, "assets", "app_icon_preview.png")
    )
    fg.resize((512, 512), Image.LANCZOS).save(
        os.path.join(ROOT, "assets", "app_icon_foreground.png")
    )
    circular_preview(
        bg, fg, os.path.join(ROOT, "assets", "app_icon_masked_preview.png")
    )

    print("生成方形图标：")
    for dpi, px in LEGACY.items():
        save(full, os.path.join(RES, f"mipmap-{dpi}", "ic_launcher.png"), px)

    print("生成自适应前景 / 背景：")
    for dpi, px in FOREGROUND.items():
        save(fg, os.path.join(RES, f"mipmap-{dpi}", "ic_launcher_foreground.png"), px)
        bg.resize((px, px), Image.LANCZOS).save(
            os.path.join(RES, f"mipmap-{dpi}", "ic_launcher_background.png"), "PNG"
        )

    print("完成")


if __name__ == "__main__":
    main()
