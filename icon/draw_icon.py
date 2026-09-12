#!/usr/bin/env python3
"""DeviceToolbox AppIcon 生成器
概念: 设备工具箱 —— 橙渐变底 + 白色 iPhone + 屏内 2×2 工具格 + 灵动岛
绘制在 4x 画布超采样, LANCZOS 缩到 1024 保证边缘平滑。
用法: python3 draw_icon.py [输出路径]
"""
from PIL import Image, ImageDraw, ImageOps

S = 1024          # 最终尺寸
SS = S * 4        # 超采样画布

# ── 颜色 ──────────────────────────────────────────────
# 背景渐变: 左上亮橙 → 右下深橙
BG_TOP    = (255, 169, 64)    # #FFA940
BG_BOTTOM = (255, 90, 0)      # #FF5A00
# 屏幕渐变(比背景深两档, 形成内凹 OLED 屏感): 同方向更深
SCR_TOP    = (214, 69, 0)     # #D64500
SCR_BOTTOM = (153, 46, 0)     # #992E00
WHITE = (255, 255, 255)

def diag_gradient(size, top, bottom):
    """对角渐变: 左上 top → 右下 bottom"""
    g = Image.linear_gradient('L').resize((size, size), Image.BICUBIC)  # 顶黑(0)底白(255)
    g = ImageOps.colorize(g, black=top, white=bottom)                    # 顶=top
    g = g.rotate(45, expand=True, resample=Image.BICUBIC)                # 视觉逆时针: top → 左上
    # expand 后居中裁剪回 size×size
    w, h = g.size
    left = (w - size) // 2
    g = g.crop((left, left, left + size, left + size))
    return g

def rr(d, xy, r, fill):
    d.rounded_rectangle(xy, radius=r, fill=fill)

def main(out_path):
    # 1. 背景对角渐变
    bg = diag_gradient(SS, BG_TOP, BG_BOTTOM)
    d = ImageDraw.Draw(bg, 'RGBA')

    k = SS / S  # 4x 换算

    # 2. 白色 iPhone 壳 (500×770, 圆角 112)
    shell = (262 * k, 127 * k, 762 * k, 897 * k)
    rr(d, shell, 112 * k, WHITE)

    # 3. 屏幕(壳内缩 40, 深橙渐变, 圆角 96)
    scr = (302 * k, 167 * k, 722 * k, 857 * k)
    scr_w, scr_h = int(420 * k), int(690 * k)
    scr_img = diag_gradient(max(scr_w, scr_h), SCR_TOP, SCR_BOTTOM).resize((scr_w, scr_h), Image.BICUBIC)
    # 用壳同款圆角矩形 mask 裁剪屏幕渐变
    mask = Image.new('L', (int(420 * k), int(690 * k)), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, int(420 * k), int(690 * k)), radius=96 * k, fill=255)
    bg.paste(scr_img, (int(302 * k), int(167 * k)), mask)
    d = ImageDraw.Draw(bg, 'RGBA')

    # 4. 灵动岛: 白色胶囊 128×44 (顶部居中)
    island = (512 * k - 64 * k, 213 * k, 512 * k + 64 * k, 257 * k)
    rr(d, island, 22 * k, WHITE)

    # 5. 屏内 2×2 白色工具格 (每格 148, 圆角 44, 间距 40), 中心略偏下
    cell, gap, r = 148 * k, 40 * k, 44 * k
    gx0 = 512 * k - cell - gap / 2          # 左列左缘
    gy0 = 545 * k - cell - gap / 2          # 上行上缘
    for row in range(2):
        for col in range(2):
            x0 = gx0 + col * (cell + gap)
            y0 = gy0 + row * (cell + gap)
            rr(d, (x0, y0, x0 + cell, y0 + cell), r, WHITE)

    # 6. 缩小到 1024
    icon = bg.resize((S, S), Image.LANCZOS)
    icon.save(out_path, 'PNG')
    print(f'已生成: {out_path}  ({S}x{S})')

if __name__ == '__main__':
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else 'DeviceToolbox-icon-master.png')
