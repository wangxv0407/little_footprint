# -*- coding: utf-8 -*-
"""生成「小脚印成长记」App 图标（纯标准库 SDF 光栅化，无外部依赖）。

设计：
  底   陶土红对角渐变 #C86A42 -> #A24527（与 App 主色 clay 同源）
  主体 暖米白 #FCF7F0 两个脚印，左下小 / 右上大，沿对角线递进寓意成长
  细节 轻微径向暗角，模拟纸张受光
"""
import math
import os
import struct
import zlib

# ---------------- 基础工具 ----------------

def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def mix(c1, c2, t):
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


def write_png(path, w, h, rows, alpha=False):
    """rows: list[bytearray]，每行 RGB 或 RGBA 原始字节。"""
    color_type = 6 if alpha else 2
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    ihdr = struct.pack('>IIBBBBB', w, h, 8, color_type, 0, 0, 0)
    blob = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) +
            chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(blob)


# ---------------- SDF ----------------

def sd_roundbox(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    return (math.hypot(max(qx, 0.0), max(qy, 0.0)) +
            min(max(qx, qy), 0.0) - r)


def sd_ellipse(px, py, rx, ry):
    k = math.hypot(px / rx, py / ry)
    if k < 1e-9:
        return -min(rx, ry)
    return (k - 1.0) * min(rx, ry)


# 脚印几何（局部坐标，脚掌中心为原点，y 向上为负）
PALM = (0.000, 0.010, 0.130, 0.168)          # cx, cy, rx, ry
TOES = (                                      # x, y, r  由内至外
    (-0.090, -0.168, 0.044),
    (-0.030, -0.200, 0.036),
    (0.022, -0.200, 0.032),
    (0.068, -0.182, 0.027),
    (0.106, -0.148, 0.022),
)


def sd_foot(px, py, cx, cy, scale, rot):
    """返回世界坐标下的脚印有向距离。"""
    dx, dy = px - cx, py - cy
    c, s = math.cos(-rot), math.sin(-rot)
    lx = (dx * c - dy * s) / scale
    ly = (dx * s + dy * c) / scale

    d = sd_ellipse(lx - PALM[0], ly - PALM[1], PALM[2], PALM[3])
    for tx, ty, tr in TOES:
        d = min(d, math.hypot(lx - tx, ly - ty) - tr)
    return d * scale


# 两个脚印：小的在左下，大的在右上
BIG = (0.455, 0.430, 0.980, -0.21)
SMALL = (0.712, 0.752, 0.470, -0.21)


def foot_distance(u, v):
    return min(sd_foot(u, v, *BIG), sd_foot(u, v, *SMALL))


def foot_bbox(n=420):
    """采样求脚印图形在设计坐标系中的包围盒。"""
    minx = miny = 9.9
    maxx = maxy = -9.9
    for i in range(n):
        u = (i + 0.5) / n
        for j in range(n):
            v = (j + 0.5) / n
            if foot_distance(u, v) < 0.0:
                if u < minx: minx = u
                if u > maxx: maxx = u
                if v < miny: miny = v
                if v > maxy: maxy = v
    return minx, miny, maxx, maxy


BBOX = foot_bbox()
BBOX_CX = (BBOX[0] + BBOX[2]) / 2
BBOX_CY = (BBOX[1] + BBOX[3]) / 2
BBOX_SIDE = max(BBOX[2] - BBOX[0], BBOX[3] - BBOX[1])


def design_coord(u, v, target):
    """把画布坐标映射回设计坐标，使脚印包围盒居中且最大边占 target。"""
    scale = target / BBOX_SIDE
    return ((u - 0.5) / scale + BBOX_CX, (v - 0.5) / scale + BBOX_CY)


# ---------------- 配色 ----------------

BG_A = (0xC8, 0x6A, 0x42)   # 左上 陶土红
BG_B = (0xA2, 0x45, 0x27)   # 右下 深陶土红
FG = (0xFC, 0xF7, 0xF0)     # 暖米白
MONO = (0xFF, 0xFF, 0xFF)   # Android 13 主题图标（系统会自行染色）


def bg_at(u, v):
    """对角渐变 + 轻微暗角。"""
    t = clamp((u * 0.45 + v * 0.55))
    col = mix(BG_A, BG_B, t)
    # 径向暗角：中心亮、边缘略暗
    vig = 1.0 - 0.055 * clamp((math.hypot(u - 0.45, v - 0.42) / 0.72) ** 2)
    return tuple(c * vig for c in col)


# ---------------- 渲染 ----------------

def render(size, mode):
    """mode: 'legacy' 传统圆角方形图标 / 'fg' 自适应前景 / 'mono' 单色前景。"""
    rows = []
    inv = 1.0 / size
    aa = 0.7 * inv

    for y in range(size):
        row = bytearray()
        v = (y + 0.5) * inv
        for x in range(size):
            u = (x + 0.5) * inv

            if mode == 'legacy':
                d_box = sd_roundbox(u, v, 0.5, 0.5, 0.5, 0.5, 0.224)
                a_box = 1.0 - smoothstep(-aa, aa, d_box)
                base = bg_at(u, v)
                du, dv = design_coord(u, v, 0.680)
                col = mix(base, FG, 1.0 - smoothstep(-aa, aa, foot_distance(du, dv)))
                a = a_box
            else:
                # 自适应前景：内容居中并撑到 66dp 安全区
                du, dv = design_coord(u, v, 0.600)
                col = MONO if mode == 'mono' else FG
                a = 1.0 - smoothstep(-aa, aa, foot_distance(du, dv))

            row += bytes((
                int(clamp(col[0], 0, 255)),
                int(clamp(col[1], 0, 255)),
                int(clamp(col[2], 0, 255)),
                int(clamp(a, 0, 1) * 255),
            ))
        rows.append(row)

    return rows


# ---------------- 输出 ----------------

RES = 'android/app/src/main/res'

# 传统图标（无自适应图标的旧系统 / 启动器兜底）
LEGACY = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# 自适应图标前景 108dp
FOREGROUND = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
}

def render_bg(size):
    """自适应图标背景层：满幅对角渐变（由系统遮罩裁切）。"""
    rows = []
    inv = 1.0 / size
    for y in range(size):
        row = bytearray()
        v = (y + 0.5) * inv
        for x in range(size):
            u = (x + 0.5) * inv
            col = bg_at(u, v)
            row += bytes((int(clamp(col[0], 0, 255)),
                          int(clamp(col[1], 0, 255)),
                          int(clamp(col[2], 0, 255)), 255))
        rows.append(row)
    return rows


if __name__ == '__main__':
    for folder, size in LEGACY.items():
        write_png(f'{RES}/{folder}/ic_launcher.png', size, size,
                  render(size, 'legacy'), alpha=True)
        print('legacy', folder, size)

    for folder, size in FOREGROUND.items():
        write_png(f'{RES}/{folder}/ic_launcher_foreground.png', size, size,
                  render(size, 'fg'), alpha=True)
        write_png(f'{RES}/{folder}/ic_launcher_monochrome.png', size, size,
                  render(size, 'mono'), alpha=True)
        write_png(f'{RES}/{folder}/ic_launcher_background.png', size, size,
                  render_bg(size), alpha=True)
        print('fg/mono/bg', folder, size)

    # 商店用 512 大图
    write_png('design/app-icon-512.png', 512, 512, render(512, 'legacy'), alpha=True)
    print('store 512 done')
