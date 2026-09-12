#!/usr/bin/env python3
# DeviceToolbox AppIcon v2: 表盘改扇区仪表, 去锁芯感, 加内阴影
from PIL import Image, ImageDraw
import math

SS = 4
S = 1024 * SS
OUT = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

C_TOP = (255, 179, 64)
C_BOT = (255, 94, 0)
img = Image.new("RGB", (S, S))
px = img.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = lerp(C_TOP, C_BOT, t)

d = ImageDraw.Draw(img)
WHITE = (255, 255, 255)
ORANGE_D = (255, 94, 0)
ORANGE_L = (255, 179, 64)
CX = S // 2

# ---- 提手白弧 ----
HANDLE_R, HANDLE_W = 190 * SS, 78 * SS
box_top = 500 * SS
bbox = (CX - HANDLE_R, box_top - HANDLE_R, CX + HANDLE_R, box_top + HANDLE_R)
d.arc(bbox, start=180, end=360, fill=WHITE, width=HANDLE_W)

# ---- 箱体 ----
body = (226 * SS, 496 * SS, 798 * SS, 806 * SS)
d.rounded_rectangle(body, radius=64 * SS, fill=WHITE)

# 底部内阴影: 从箱底向上渐变 淡橙 -> 白
sh_h = 56 * SS
for i in range(sh_h):
    t = i / sh_h
    col = lerp((255, 224, 178), WHITE, t)
    d.line([(230 * SS, 806 * SS - i), (794 * SS, 806 * SS - i)], fill=col)

# 顶部封条(浅橙)
d.rounded_rectangle((240 * SS, 518 * SS, 784 * SS, 534 * SS), radius=8 * SS, fill=ORANGE_L)

# ---- 诊断表盘(扇区仪表) ----
dial_c = (CX, 650 * SS)
dial_r = 104 * SS
d.ellipse((dial_c[0]-dial_r, dial_c[1]-dial_r, dial_c[0]+dial_r, dial_c[1]+dial_r), fill=WHITE)
# 外环
d.ellipse((dial_c[0]-dial_r, dial_c[1]-dial_r, dial_c[0]+dial_r, dial_c[1]+dial_r),
          outline=ORANGE_D, width=16 * SS)
# 扇区扫掠: 从 -45°(右上) 顺时针扫 240°? 用 pie 画橙色扇区, 稍小于整环
# 表盘读数 70%: 起点 -135°(左上) 扫 252° 顺时针 -> 表示电量70%
start_deg = -135
sweep = 252
d.pieslice((dial_c[0]-dial_r+24*SS, dial_c[1]-dial_r+24*SS,
            dial_c[0]+dial_r-24*SS, dial_c[1]+dial_r-24*SS),
           start=start_deg, end=start_deg + sweep, fill=ORANGE_L)
# 白色指针叠在扇区上, 指向 sweep 终点
end_deg = math.radians(start_deg + sweep)
pl = dial_r - 40 * SS
p2 = (dial_c[0] + pl * math.cos(end_deg), dial_c[1] + pl * math.sin(end_deg))
d.line([dial_c, p2], fill=WHITE, width=26 * SS)
# 中心轴 白心橙环
axr = 22 * SS
d.ellipse((dial_c[0]-axr, dial_c[1]-axr, dial_c[0]+axr, dial_c[1]+axr), fill=ORANGE_D)
axr2 = 10 * SS
d.ellipse((dial_c[0]-axr2, dial_c[1]-axr2, dial_c[0]+axr2, dial_c[1]+axr2), fill=WHITE)

# ---- 搭扣 ----
for side_x in (286 * SS, 738 * SS):
    rr = 19 * SS
    d.ellipse((side_x - rr, 646 * SS - rr, side_x + rr, 646 * SS + rr), fill=ORANGE_L)
    # 搭扣中心小坑
    rr2 = 8 * SS
    d.ellipse((side_x - rr2, 646 * SS - rr2, side_x + rr2, 646 * SS + rr2), fill=ORANGE_D)

out = img.resize((OUT, OUT), Image.LANCZOS)
out.save("/tmp/dt_icon_1024.png")
print("v2 saved")
