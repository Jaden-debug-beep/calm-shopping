"""Rasterize the same shopping-bag mark used by Android for iOS AppIcon."""

import json
from pathlib import Path

from PIL import Image, ImageDraw


ICON_DIR = Path(__file__).resolve().parents[1] / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
SCALE = 2
GREEN = "#285E50"
PAPER = "#F8F7F2"


def point(x: int, y: int) -> tuple[int, int]:
    return x * SCALE, y * SCALE


def make_master() -> Image.Image:
    image = Image.new("RGB", point(1024, 1024), GREEN)
    draw = ImageDraw.Draw(image)
    draw.arc((*point(396, 210), *point(628, 530)), 180, 360, fill=PAPER, width=45 * SCALE)
    draw.polygon([point(265, 350), point(759, 350), point(721, 810), point(303, 810)], fill=PAPER)
    draw.line([point(395, 560), point(470, 635), point(645, 455)], fill=GREEN, width=49 * SCALE, joint="curve")
    draw.ellipse((*point(370, 535), *point(420, 585)), fill=GREEN)
    draw.ellipse((*point(620, 430), *point(670, 480)), fill=GREEN)
    return image


master = make_master()
contents = json.loads((ICON_DIR / "Contents.json").read_text(encoding="utf-8"))
for item in contents["images"]:
    size = round(float(item["size"].split("x")[0]) * int(item["scale"][0]))
    master.resize((size, size), Image.Resampling.LANCZOS).save(ICON_DIR / item["filename"])

print(f"Generated {len(contents['images'])} iOS icon slots")
