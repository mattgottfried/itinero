"""Generates the Itinero app icon (1024x1024, opaque). Run: python3 tools/make_icon.py"""
from PIL import Image, ImageDraw
import math

S = 2048  # draw at 2x then downsample for smooth edges
img = Image.new("RGB", (S, S))
px = img.load()
c1, c2 = (26, 82, 110), (88, 86, 214)   # deep teal -> indigo, the app's brand gradient
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S - 2)
        px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

d = ImageDraw.Draw(img, "RGBA")
# dotted route curving up to the pin
pts = []
for i in range(0, 101):
    t = i / 100
    x = 330 + (1000 - 330) * t
    y = 1560 - 700 * math.sin(t * math.pi / 2) ** 1.4 - 120 * math.sin(t * math.pi)
    pts.append((x, y))
for i in range(0, len(pts) - 6, 6):
    x, y = pts[i]
    d.ellipse((x - 26, y - 26, x + 26, y + 26), fill=(255, 255, 255, 170))

# map pin
cx, cy, r = 1130, 800, 300
gold = (253, 185, 19, 255)
d.polygon([(cx - r * 0.88, cy + r * 0.48), (cx + r * 0.88, cy + r * 0.48), (cx, cy + r * 2.05)], fill=gold)
d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=gold)
d.ellipse((cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42), fill=(34, 78, 130, 255))
# start dot
d.ellipse((330 - 60, 1560 - 60, 330 + 60, 1560 + 60), fill=(255, 255, 255, 255))

img.resize((1024, 1024), Image.LANCZOS).save("Itinero/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
print("wrote icon")
