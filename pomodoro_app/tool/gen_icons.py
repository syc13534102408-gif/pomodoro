#!/usr/bin/env python3
"""生成「扁平积木」方案的安卓 Adaptive Icon 资源。

- drawable/ic_launcher_background.xml  背景层：番茄红纯色块
- drawable/ic_launcher_foreground.xml  前景层：点阵锥形松果（墨色）
- drawable/ic_launcher_monochrome.xml  单色层：Android 13 主题图标
- mipmap-anydpi-v26/ic_launcher.xml    合成：背景 + 前景
- mipmap-anydpi-v33/ic_launcher.xml    合成：背景 + 前景 + 单色
- mipmap-*/ic_launcher.png             低版本回退位图（API < 26）
"""
import os

from PIL import Image, ImageDraw

RES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'android', 'app', 'src', 'main', 'res')

# 画布统一 108x108dp，安全区居中 66x66。
VIEWPORT = 108.0
CANVAS = '#FFFFF6E5'
INK = '#FF1A1A1A'
TOMATO = '#FFFF765D'

# 点阵松果：减少点数、放大果鳞，并用米黄填充 + 墨色描边形成清晰轮廓。
STEM = (51.0, 75.0, 57.0, 86.0)
DOT_R = 5.5
DOT_ROWS = [
    (36.0, [54.0]),
    (50.0, [45.0, 63.0]),
    (64.0, [36.0, 54.0, 72.0]),
    (78.0, [45.0, 63.0]),
]
DOT_FILL = '#FFFFF6E5'
DOT_STROKE = '#FF1A1A1A'
DOT_STROKE_WIDTH = 2.5

HEADER = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
'''
FOOTER = '</vector>\n'


def circle_path(cx: float, cy: float, r: float) -> str:
    """用两段半圆画出闭合圆。"""
    return (f'M{cx:g},{cy - r:g}'
            f'a{r:g},{r:g} 0 1 0 0,{2 * r:g}'
            f'a{r:g},{r:g} 0 1 0 0,{-2 * r:g}')


def pinecone_paths(color: str, outlined: bool = False) -> str:
    parts = []
    x0, y0, x1, y1 = STEM
    stem_color = INK if outlined else color
    parts.append(f'        <path android:fillColor="{stem_color}"\n'
                 f'            android:pathData="M{x0:g},{y0:g}'
                 f'h{x1 - x0:g}v{y1 - y0:g}h{x0 - x1:g}z" />')
    for cy, xs in DOT_ROWS:
        for cx in xs:
            stroke = DOT_STROKE if outlined else '#00000000'
            parts.append(f'        <path android:fillColor="{color}"\n'
                         f'            android:strokeColor="{stroke}"\n'
                         f'            android:strokeWidth="{DOT_STROKE_WIDTH:g}"\n'
                         f'            android:pathData="{circle_path(cx, cy, DOT_R)}" />')
    return '\n'.join(parts)


def write(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(content)
    print('written', os.path.relpath(path, RES))


def write_vectors() -> None:
    write(os.path.join(RES, 'drawable', 'ic_launcher_background.xml'),
          HEADER
          + f'    <path android:fillColor="{TOMATO}"\n'
            '        android:pathData="M0,0h108v108h-108z" />\n'
          + FOOTER)

    write(os.path.join(RES, 'drawable', 'ic_launcher_foreground.xml'),
          HEADER + pinecone_paths(DOT_FILL, outlined=True) + '\n' + FOOTER)

    # 单色层：形状一致，颜色交给系统着色（Android 13 主题图标）。
    write(os.path.join(RES, 'drawable', 'ic_launcher_monochrome.xml'),
          HEADER + pinecone_paths('#FF1A1A1A') + '\n' + FOOTER)

    write(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <background android:drawable="@drawable/ic_launcher_background" />\n'
          '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
          '</adaptive-icon>\n')

    write(os.path.join(RES, 'mipmap-anydpi-v33', 'ic_launcher.xml'),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <background android:drawable="@drawable/ic_launcher_background" />\n'
          '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
          '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
          '</adaptive-icon>\n')


def argb(color: str) -> tuple:
    """Android 色值 #AARRGGBB → PIL 的 RGBA 元组。"""
    value = color.lstrip('#')
    return (int(value[2:4], 16), int(value[4:6], 16),
            int(value[6:8], 16), int(value[0:2], 16))


def write_pngs() -> None:
    sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96,
             'xxhdpi': 144, 'xxxhdpi': 192}
    for folder, size in sizes.items():
        scale = size / VIEWPORT
        factor = 4
        px = scale * factor
        image = Image.new('RGBA', (size * factor, size * factor), argb(TOMATO))
        draw = ImageDraw.Draw(image)
        x0, y0, x1, y1 = STEM
        draw.rounded_rectangle(
            [x0 * px, y0 * px, x1 * px, y1 * px],
            radius=1.5 * px,
            fill=argb(INK),
        )
        for cy, xs in DOT_ROWS:
            for cx in xs:
                r = DOT_R * px
                stroke = max(1, round(DOT_STROKE_WIDTH * px))
                draw.ellipse(
                    [cx * px - r, cy * px - r, cx * px + r, cy * px + r],
                    fill=argb(DOT_FILL),
                    outline=argb(DOT_STROKE),
                    width=stroke,
                )
        image = image.resize((size, size), Image.Resampling.LANCZOS)
        out = os.path.join(RES, f'mipmap-{folder}', 'ic_launcher.png')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        image.save(out)
        print('written', os.path.relpath(out, RES))


if __name__ == '__main__':
    write_vectors()
    write_pngs()
