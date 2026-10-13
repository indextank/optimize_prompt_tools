#!/usr/bin/env python3
"""prompt_optimizer 应用图标生成器（全部尺寸/格式的唯一来源）。

设计语言（与应用主题一致）：
- 圆角方形底：青绿品牌渐变（AppTokens.accent #009FAA 同族）+ 顶部高光
- 主形：四角内凹 Sparkle（✦，AI 优化语义，16px 下仍可辨识）
- 辅形：右上小 Sparkle，形成主次节奏
- 白色主体 + 轻投影，保证明暗任务栏均可辨识

输出：
  assets/icon/app_icon_1024.png            主图（设计母版）
  linux/runner/resources/app_icon.png       256（Linux 窗口/任务栏图标，runner 运行时加载）
  windows/runner/resources/app_icon.ico     多尺寸 ICO（16~256）
  android/app/src/main/res/mipmap-*/ic_launcher.png  48/72/96/144/192

用法：python3 tool/gen_icon.py
"""
import math
import os
import struct
import sys

from PIL import Image, ImageDraw

SS = 4  # 超采样倍数（4096 画布）
SIZE = 1024  # 设计母版边长

# 品牌渐变（与 lib/ui/theme.dart AppTokens.accent 同族）
GRAD_TOP = (23, 192, 203)     # #17C0CB 左上亮青
GRAD_BOTTOM = (0, 121, 131)   # #007983 右下深青

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient_image(size, c0, c1, angle_diag=True):
    """(0,0)->(x+y) 线性渐变。小尺寸生成后放大，梯度平滑且开销低。"""
    base = 256
    img = Image.new("RGB", (base, base))
    px = img.load()
    for y in range(base):
        for x in range(base):
            t = ((x / (base - 1)) + (y / (base - 1))) / 2 if angle_diag else y / (base - 1)
            px[x, y] = lerp(c0, c1, t)
    return img.resize((size, size), Image.LANCZOS)


def top_highlight(size):
    """顶部 45% 白色高光渐隐层（alpha）。"""
    base = 256
    img = Image.new("L", (base, base))
    px = img.load()
    for y in range(base):
        t = y / (base - 1)
        # 顶部 0.0~0.5 线性衰减 58 -> 0
        a = int(58 * max(0.0, 1.0 - t / 0.5))
        for x in range(base):
            px[x, y] = a
    return img.resize((size, size), Image.LANCZOS)


def sparkle_polygon(cx, cy, r, seg=20):
    """四角内凹 Sparkle：tip 间二次贝塞尔（控制点压向中心形成内凹）。"""
    tips = [(0, -r), (r, 0), (0, r), (-r, 0)]
    ctrl_scale = 0.16  # 越小越内凹（0=菱形，~0.25≈直边）
    pts = []
    for i in range(4):
        t0 = tips[i]
        t1 = tips[(i + 1) % 4]
        c = (t0[0] * ctrl_scale, t0[1] * ctrl_scale)  # 从上一 tip 向中心压
        for k in range(seg + 1):
            u = k / seg
            bx = (1 - u) ** 2 * t0[0] + 2 * (1 - u) * u * c[0] + u ** 2 * t1[0]
            by = (1 - u) ** 2 * t0[1] + 2 * (1 - u) * u * c[1] + u ** 2 * t1[1]
            pts.append((cx + bx, cy + by))
    return pts


def build_master(s=SIZE, ss=SS):
    S = s * ss
    # 1) 底：圆角方形 + 渐变 + 顶部高光
    # 关键：全部用 alpha_composite 合成（paste+mask 会以源替换目标，
    # 曾导致高光层覆盖渐变层使图标呈黑底），最后统一乘圆角遮罩。
    grad = gradient_image(S, GRAD_TOP, GRAD_BOTTOM).convert("RGBA")
    hi = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    hi.putalpha(top_highlight(S))

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas = Image.alpha_composite(canvas, grad)
    canvas = Image.alpha_composite(canvas, hi)

    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    radius = int(S * 0.225)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)

    from PIL import ImageChops
    canvas.putalpha(ImageChops.multiply(canvas.getchannel("A"), mask))

    # 2) 轻外描边（深色描边提升浅色任务栏可辨识度）
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.rounded_rectangle([0, 0, S - 1, S - 1], radius=radius,
                         outline=(0, 60, 66, 70), width=max(2, int(S * 0.006)))
    canvas = Image.alpha_composite(canvas, rim)

    # 3) 白色 Sparkle 主体（带柔影）
    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    # 主 Sparkle：中心偏左下，半径 0.30
    gd.polygon(sparkle_polygon(S * 0.415, S * 0.545, S * 0.300), fill=(255, 255, 255, 255))
    # 小 Sparkle：右上，半径 0.115
    gd.polygon(sparkle_polygon(S * 0.705, S * 0.285, S * 0.115), fill=(255, 255, 255, 255))

    # 柔影（轻投影，缩小后自然消隐）
    shadow = glyph.split()[3].filter(_blur(S * 0.010))
    sh = Image.new("RGBA", (S, S), (0, 50, 55, 90))
    sh.putalpha(shadow)
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -S * 0.006))
    out = Image.alpha_composite(canvas, sh)
    out = Image.alpha_composite(out, glyph)

    # 4) 下采样出母版
    return out.resize((s, s), Image.LANCZOS)


def _blur(r):
    from PIL import ImageFilter
    return ImageFilter.GaussianBlur(radius=max(1, r))


ANDROID_MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", f"{path} 不是 PNG"
    return struct.unpack(">II", head[16:24])


def main():
    os.chdir(ROOT)
    print("生成图标母版（{}×{}，超采样 {}×）...".format(SIZE, SIZE, SS))
    master = build_master()

    outputs = []

    os.makedirs("assets/icon", exist_ok=True)
    master.save("assets/icon/app_icon_1024.png")
    outputs.append("assets/icon/app_icon_1024.png")

    # Linux 窗口/任务栏图标（runner 运行时加载 256）
    os.makedirs("linux/runner/resources", exist_ok=True)
    master.resize((256, 256), Image.LANCZOS).save(
        "linux/runner/resources/app_icon.png")
    outputs.append("linux/runner/resources/app_icon.png")

    # Windows 多尺寸 ICO
    os.makedirs("windows/runner/resources", exist_ok=True)
    master.save(
        "windows/runner/resources/app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128),
               (256, 256)],
    )
    outputs.append("windows/runner/resources/app_icon.ico")

    # Android 启动器图标
    for name, size in ANDROID_MIPMAPS.items():
        p = f"android/app/src/main/res/{name}/ic_launcher.png"
        os.makedirs(os.path.dirname(p), exist_ok=True)
        master.resize((size, size), Image.LANCZOS).save(p)
        outputs.append(p)

    print("\n产出清单：")
    for p in outputs:
        if p.endswith(".png"):
            w, h = png_size(p)
            print(f"  {p}  {w}×{h}  {os.path.getsize(p):,}B")
        else:
            print(f"  {p}  {os.path.getsize(p):,}B")
    return 0


if __name__ == "__main__":
    sys.exit(main())
