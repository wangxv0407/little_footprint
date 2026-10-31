# -*- coding: utf-8 -*-
"""校验生成的 PNG：尺寸 / 颜色 / alpha 分布 / 主体占比（纯标准库解码）。"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not png'
    pos, idat, w = 8, b'', None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + ln]
        if tag == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', payload[:10])
        elif tag == b'IDAT':
            idat += payload
        pos += 12 + ln
    ch = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * ch
    out, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out.append(bytes(line))
        prev = line
    return w, h, ch, out


def report(path):
    w, h, ch, rows = read_png(path)
    n = w * h
    colors = {}
    alpha0 = alpha_full = 0
    sum_r = sum_g = sum_b = 0
    opaque = 0
    for y in range(h):
        r = rows[y]
        for x in range(w):
            i = x * ch
            px = (r[i], r[i + 1], r[i + 2])
            a = r[i + 3] if ch == 4 else 255
            if ch == 4:
                if a == 0:
                    alpha0 += 1
                    continue
                if a == 255:
                    alpha_full += 1
            opaque += 1
            sum_r += px[0]; sum_g += px[1]; sum_b += px[2]
            colors[px] = colors.get(px, 0) + 1

    top = sorted(colors.items(), key=lambda kv: -kv[1])[:4]
    print(f'\n== {path}')
    print(f'   尺寸 {w}x{h}  通道 {ch}')
    if ch == 4:
        print(f'   透明像素 {alpha0 / n:.1%}  全不透明 {alpha_full / n:.1%}')
    print(f'   不透明像素 {opaque / n:.1%}')
    if opaque:
        print(f'   平均色 RGB({sum_r // opaque}, {sum_g // opaque}, {sum_b // opaque})')
    print(f'   颜色种类 {len(colors)}')
    for c, cnt in top:
        print(f'     主色 #{c[0]:02X}{c[1]:02X}{c[2]:02X}  {cnt / max(opaque,1):.1%}')

    if ch == 4:
        # 前景层的包围盒（非透明区域）
        minx, miny, maxx, maxy = w, h, -1, -1
        for y in range(h):
            r = rows[y]
            for x in range(w):
                if r[x * ch + 3] > 8:
                    minx = min(minx, x); maxx = max(maxx, x)
                    miny = min(miny, y); maxy = max(maxy, y)
        if maxx >= 0:
            print(f'   主体包围盒 x[{minx},{maxx}] y[{miny},{maxy}] '
                  f'→ 宽 {(maxx-minx+1)/w:.1%} 高 {(maxy-miny+1)/h:.1%}')
            print(f'   左边距 {minx/w:.1%}  右边距 {(w-1-maxx)/w:.1%} '
                  f'上边距 {miny/h:.1%}  下边距 {(h-1-maxy)/h:.1%}')


if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
