# Draws the 1024px app icon: a dark gradient with a relay "signal" glyph.
from PIL import Image, ImageDraw
import sys
S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(20 + 30 * t), int(24 + 20 * t), int(48 + 70 * t)))
c = (S // 2, S // 2 + 60)
for i, r in enumerate([150, 260, 370]):
    w = 46
    col = (255, 160 + i * 25, 60 + i * 40)
    d.arc([c[0] - r, c[1] - r, c[0] + r, c[1] + r], start=225, end=315, fill=col, width=w)
d.ellipse([c[0] - 60, c[1] - 60, c[0] + 60, c[1] + 60], fill=(255, 140, 50))
d.rounded_rectangle([c[0] - 22, c[1] + 40, c[0] + 22, c[1] + 300], radius=20, fill=(255, 140, 50))
img.save(sys.argv[1])
