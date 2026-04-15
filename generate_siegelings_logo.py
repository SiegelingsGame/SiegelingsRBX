from __future__ import annotations

from collections import deque
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "siegelings_landscape_logo_v1.png"

SOURCES = {
    "earth": Path(r"D:\Meshy\88777c6c-4e62-4919-97a3-55a989df2319.png"),
    "wind": Path(r"D:\Meshy\ChatGPT Image Feb 9, 2026, 04_49_42 PM.png"),
    "ice": Path(r"D:\Meshy\ChatGPT Image Feb 9, 2026, 12_56_59 AM.png"),
    "fire": Path(r"D:\Meshy\bb91bd74-3f09-4701-ac11-ea17f9fdf457.png"),
}

FONTS = {
    "title": Path(r"C:\Windows\Fonts\impact.ttf"),
    "subtitle": Path(r"C:\Windows\Fonts\arialbd.ttf"),
}

WIDTH = 2200
HEIGHT = 1200


def load_font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS[name]), size=size)


def add_soft_orb(
    base: Image.Image,
    center: tuple[int, int],
    size: tuple[int, int],
    color: tuple[int, int, int],
    alpha: int,
    blur: int,
) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x, y = center
    w, h = size
    draw.ellipse((x - w // 2, y - h // 2, x + w // 2, y + h // 2), fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(layer)


def add_particle_field(
    base: Image.Image,
    area: tuple[int, int, int, int],
    count: int,
    colors: list[tuple[int, int, int]],
    seed: int,
) -> None:
    rng = random.Random(seed)
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x1, y1, x2, y2 = area

    for _ in range(count):
        x = rng.randint(x1, x2)
        y = rng.randint(y1, y2)
        radius = rng.randint(2, 8)
        color = rng.choice(colors)
        alpha = rng.randint(70, 180)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (alpha,))
        if rng.random() < 0.4:
            streak = rng.randint(8, 22)
            draw.line(
                (x - streak, y + streak // 2, x + streak, y - streak // 2),
                fill=color + (alpha // 2,),
                width=max(1, radius // 2),
            )

    layer = layer.filter(ImageFilter.GaussianBlur(1.3))
    base.alpha_composite(layer)


def crop_to_content(image: Image.Image, padding: int = 0) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if not bbox:
        return image
    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(image.width, bbox[2] + padding)
    bottom = min(image.height, bbox[3] + padding)
    return image.crop((left, top, right, bottom))


def remove_edge_white(image: Image.Image, threshold: int = 236, spread_limit: int = 24) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    background = Image.new("L", rgba.size, 0)
    bg_pixels = background.load()
    queue: deque[tuple[int, int]] = deque()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, _ = pixels[x, y]
        brightness = (r + g + b) // 3
        spread = max(r, g, b) - min(r, g, b)
        return brightness >= threshold and spread <= spread_limit

    for x in range(width):
        if is_bg(x, 0):
            queue.append((x, 0))
        if is_bg(x, height - 1):
            queue.append((x, height - 1))

    for y in range(height):
        if is_bg(0, y):
            queue.append((0, y))
        if is_bg(width - 1, y):
            queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if not (0 <= x < width and 0 <= y < height):
            continue
        if bg_pixels[x, y]:
            continue
        if not is_bg(x, y):
            continue
        bg_pixels[x, y] = 255
        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))

    alpha = Image.new("L", rgba.size, 255)
    alpha_pixels = alpha.load()
    for y in range(height):
        for x in range(width):
            if bg_pixels[x, y]:
                alpha_pixels[x, y] = 0

    alpha = alpha.filter(ImageFilter.GaussianBlur(2.2))
    rgba.putalpha(alpha)
    return crop_to_content(rgba, padding=12)


def resize_to_fit(image: Image.Image, max_size: tuple[int, int]) -> Image.Image:
    copy = image.copy()
    copy.thumbnail(max_size, Image.Resampling.LANCZOS)
    return copy


def knock_out_neutral_pixels(
    image: Image.Image,
    threshold: int = 238,
    spread_limit: int = 32,
) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if not a:
                continue
            brightness = (r + g + b) // 3
            spread = max(r, g, b) - min(r, g, b)
            if brightness >= threshold and spread <= spread_limit:
                pixels[x, y] = (r, g, b, 0)

    alpha = rgba.getchannel("A").filter(ImageFilter.GaussianBlur(1.3))
    rgba.putalpha(alpha)
    return crop_to_content(rgba, padding=8)


def add_glow(
    base: Image.Image,
    image: Image.Image,
    position: tuple[int, int],
    glow_color: tuple[int, int, int],
    glow_padding: int = 24,
    blur: int = 28,
    alpha: int = 150,
) -> None:
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    alpha_mask = image.getchannel("A")
    glow_mask = alpha_mask.filter(ImageFilter.GaussianBlur(blur))
    glow_layer = Image.new("RGBA", image.size, glow_color + (0,))
    glow_layer.putalpha(glow_mask.point(lambda value: min(255, value * alpha // 255)))
    x, y = position
    shadow.alpha_composite(glow_layer, (x - glow_padding, y - glow_padding))
    base.alpha_composite(shadow)


def place_element(base: Image.Image, image: Image.Image, position: tuple[int, int]) -> None:
    base.alpha_composite(image, position)


def make_soft_panel(image: Image.Image, crop_box: tuple[int, int, int, int], size: tuple[int, int]) -> Image.Image:
    panel = image.crop(crop_box).convert("RGBA").resize(size, Image.Resampling.LANCZOS)
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    inset = 18
    draw.rounded_rectangle(
        (inset, inset, size[0] - inset, size[1] - inset),
        radius=72,
        fill=255,
    )
    mask = mask.filter(ImageFilter.GaussianBlur(14))
    panel.putalpha(mask)
    return panel


def fill_vertical_gradient(size: tuple[int, int], colors: list[tuple[int, int, int]]) -> Image.Image:
    gradient = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(gradient)
    height = max(1, size[1] - 1)

    for y in range(size[1]):
        position = y / height
        if position < 0.5:
            local = position / 0.5
            start, end = colors[0], colors[1]
        else:
            local = (position - 0.5) / 0.5
            start, end = colors[1], colors[2]
        color = tuple(int(start[i] + (end[i] - start[i]) * local) for i in range(3))
        draw.line((0, y, size[0], y), fill=color + (255,))

    return gradient


def draw_center_title(base: Image.Image, title_text: str, subtitle_words: list[tuple[str, tuple[int, int, int]]]) -> None:
    title_font = load_font("title", 260)
    subtitle_font = load_font("subtitle", 74)
    measure = ImageDraw.Draw(base)
    title_box = measure.textbbox((0, 0), title_text, font=title_font, stroke_width=18)
    title_width = title_box[2] - title_box[0]
    title_height = title_box[3] - title_box[1]
    title_x = (base.width - title_width) // 2
    title_y = 420

    panel = Image.new("RGBA", base.size, (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle(
        (430, 360, base.width - 430, 840),
        radius=110,
        fill=(11, 20, 42, 118),
        outline=(255, 221, 119, 75),
        width=4,
    )
    panel = panel.filter(ImageFilter.GaussianBlur(8))
    base.alpha_composite(panel)

    shadow_mask = Image.new("L", base.size, 0)
    shadow_draw = ImageDraw.Draw(shadow_mask)
    shadow_draw.text(
        (title_x + 18, title_y + 20),
        title_text,
        font=title_font,
        fill=255,
        stroke_width=20,
        stroke_fill=255,
    )
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(18))
    shadow = Image.new("RGBA", base.size, (5, 9, 20, 160))
    shadow.putalpha(shadow_mask)
    base.alpha_composite(shadow)

    outline_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    outline_draw = ImageDraw.Draw(outline_layer)
    outline_draw.text(
        (title_x, title_y),
        title_text,
        font=title_font,
        fill=(100, 48, 9, 255),
        stroke_width=18,
        stroke_fill=(19, 34, 64, 255),
    )
    base.alpha_composite(outline_layer)

    fill_mask = Image.new("L", base.size, 0)
    fill_draw = ImageDraw.Draw(fill_mask)
    fill_draw.text((title_x, title_y), title_text, font=title_font, fill=255)

    text_gradient = fill_vertical_gradient(
        base.size,
        [
            (255, 247, 202),
            (246, 191, 71),
            (151, 82, 10),
        ],
    )
    text_gradient.putalpha(fill_mask)
    base.alpha_composite(text_gradient)

    highlight_mask = Image.new("L", base.size, 0)
    highlight_draw = ImageDraw.Draw(highlight_mask)
    highlight_draw.text((title_x, title_y - 10), title_text, font=title_font, fill=180)
    highlight_mask = highlight_mask.filter(ImageFilter.GaussianBlur(8))
    highlight = Image.new("RGBA", base.size, (255, 255, 255, 90))
    highlight.putalpha(highlight_mask)
    base.alpha_composite(highlight)

    subtitle_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    subtitle_draw = ImageDraw.Draw(subtitle_layer)
    pieces: list[tuple[str, tuple[int, int, int]]] = []
    for index, (word, color) in enumerate(subtitle_words):
        pieces.append((word, color))
        if index < len(subtitle_words) - 1:
            pieces.append((", ", (229, 225, 219)))

    total_width = 0
    for text, _ in pieces:
        box = subtitle_draw.textbbox((0, 0), text, font=subtitle_font, stroke_width=6)
        total_width += box[2] - box[0]

    cursor_x = (base.width - total_width) // 2
    subtitle_y = 772
    for text, color in pieces:
        subtitle_draw.text(
            (cursor_x, subtitle_y),
            text,
            font=subtitle_font,
            fill=color + (255,),
            stroke_width=6,
            stroke_fill=(10, 18, 38, 255),
        )
        box = subtitle_draw.textbbox((0, 0), text, font=subtitle_font, stroke_width=6)
        cursor_x += box[2] - box[0]

    glow = subtitle_layer.filter(ImageFilter.GaussianBlur(4))
    base.alpha_composite(glow)
    base.alpha_composite(subtitle_layer)


def build_background() -> Image.Image:
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), (7, 12, 26, 255))

    add_soft_orb(canvas, (250, 210), (860, 860), (113, 194, 70), 225, 76)
    add_soft_orb(canvas, (1910, 220), (760, 720), (245, 229, 193), 180, 88)
    add_soft_orb(canvas, (300, 1030), (900, 760), (74, 191, 255), 205, 92)
    add_soft_orb(canvas, (1940, 990), (920, 860), (245, 105, 47), 210, 90)
    add_soft_orb(canvas, (1100, 640), (980, 420), (18, 28, 58), 210, 72)

    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 8, 18, 65))
    draw.rounded_rectangle((120, 110, WIDTH - 120, HEIGHT - 110), radius=140, outline=(255, 255, 255, 24), width=3)
    overlay = overlay.filter(ImageFilter.GaussianBlur(4))
    canvas.alpha_composite(overlay)

    add_particle_field(canvas, (1180, 20, 2140, 420), 55, [(255, 250, 234), (205, 241, 255)], seed=7)
    add_particle_field(canvas, (0, 650, 920, 1180), 60, [(204, 247, 255), (144, 221, 255)], seed=22)
    add_particle_field(canvas, (1420, 720, 2180, 1180), 48, [(255, 166, 92), (255, 226, 126)], seed=41)
    add_particle_field(canvas, (0, 0, 760, 520), 40, [(212, 255, 151), (248, 230, 168)], seed=19)

    return canvas


def main() -> None:
    canvas = build_background()

    earth = knock_out_neutral_pixels(remove_edge_white(Image.open(SOURCES["earth"]), threshold=236, spread_limit=28), threshold=240, spread_limit=28)
    wind = remove_edge_white(Image.open(SOURCES["wind"]), threshold=232, spread_limit=28)
    ice_panel = make_soft_panel(Image.open(SOURCES["ice"]), (80, 0, 944, 760), (560, 560))
    fire_source = Image.open(SOURCES["fire"]).crop((0, 0, 1024, 1180))

    earth = resize_to_fit(earth, (700, 700))
    wind = crop_to_content(wind.crop((0, 0, wind.width, max(1, wind.height - 60))), padding=0)
    wind = resize_to_fit(wind, (620, 520))
    fire = resize_to_fit(
        knock_out_neutral_pixels(remove_edge_white(fire_source, threshold=228, spread_limit=36), threshold=235, spread_limit=36),
        (520, 560),
    )

    earth_pos = (-10, 0)
    wind_pos = (1540, 35)
    ice_pos = (30, 625)
    fire_pos = (1680, 635)

    add_glow(canvas, earth, earth_pos, (126, 232, 89), alpha=195, blur=28)
    add_glow(canvas, wind, wind_pos, (250, 238, 205), alpha=180, blur=24)
    add_glow(canvas, fire, fire_pos, (255, 120, 55), alpha=190, blur=26)

    panel_glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    add_soft_orb(panel_glow, (ice_pos[0] + 300, ice_pos[1] + 320), (700, 700), (100, 208, 255), 120, 52)
    canvas.alpha_composite(panel_glow)

    place_element(canvas, earth, earth_pos)
    place_element(canvas, wind, wind_pos)
    place_element(canvas, ice_panel, ice_pos)
    place_element(canvas, fire, fire_pos)

    frame = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (ice_pos[0] + 10, ice_pos[1] + 10, ice_pos[0] + ice_panel.width - 10, ice_pos[1] + ice_panel.height - 10),
        radius=78,
        outline=(194, 242, 255, 165),
        width=4,
    )
    frame = frame.filter(ImageFilter.GaussianBlur(0.4))
    canvas.alpha_composite(frame)

    draw_center_title(
        canvas,
        "Siegelings",
        [
            ("Earth", (150, 238, 119)),
            ("Wind", (255, 246, 214)),
            ("Ice", (149, 228, 255)),
            ("Fire", (255, 150, 84)),
        ],
    )

    canvas = canvas.filter(ImageFilter.UnsharpMask(radius=1.4, percent=110, threshold=2))
    canvas.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
