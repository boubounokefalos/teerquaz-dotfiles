#!/usr/bin/env python3
"""Generate the KvTeerquaz Kvantum theme from the stock KvGnomeDark theme.

Recolours KvGnomeDark (flat, rounded, GNOME-like) with the shell's Teerquaz
palette (~/.config/quickshell/Theme.qml) so Qt widget apps match the shell's
Settings window: #181c1f windows, #242b30 controls, turquoise #2ec4b6 selection
with dark text, light #dce4e8 text (slate turquoise). Re-run after a kvantum upgrade.

    python3 ~/.config/Kvantum/build-kvteerquaz.py
"""
import re
from pathlib import Path

SRC = Path("/usr/share/Kvantum/KvGnomeDark")
NAME = "KvTeerquaz"
OUT = Path.home() / ".config/Kvantum" / NAME

BG0_H, BG0, BG0_S, BG1, BG2, BG3 = "#121517", "#181c1f", "#1e2327", "#242b30", "#2f383e", "#3e4a51"
FG0, FG1, FG2, FG4, GREY = "#f0f4f6", "#dce4e8", "#b8c4ca", "#8b9aa2", "#7d8b93"
YELLOW_DIM, YELLOW, ORANGE, BLUE, PURPLE = "#2ec4b6", "#64dfdf", "#e9c46a", "#2ec4b6", "#a79bc4"

# stock grey value -> Teerquaz colour (piecewise-linear in between)
GREY_RAMP = [
    (0x00, "#0b0b0b"), (0x0a, "#121314"), (0x1b, BG0_H), (0x2d, BG0), (0x35, BG0_S),
    (0x3c, BG1), (0x46, BG2), (0x5a, BG3), (0x7b, GREY), (0xa5, FG4),
    (0xd2, FG2), (0xee, FG1), (0xff, FG0),
]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def ramp(v):
    for (a, ca), (b, cb) in zip(GREY_RAMP, GREY_RAMP[1:]):
        if a <= v <= b:
            t = (v - a) / (b - a) if b > a else 0
            pa, pb = rgb(ca), rgb(cb)
            return hexc(tuple(pa[i] + (pb[i] - pa[i]) * t for i in range(3)))
    return GREY_RAMP[-1][1]


def recolor(h):
    r, g, b = rgb(h)
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn) / mx if mx else 0
    if sat < 0.2:                              # greys
        return ramp((r + g + b) / 3)
    if b > r and b > g:                        # GNOME blue accents
        return YELLOW if (r + g + b) / 3 > 110 else YELLOW_DIM
    if r > g and b > g:                        # purple focus marks
        return YELLOW
    return ramp((r + g + b) / 3)               # anything else: by brightness


RADIUS = 8   # list/tree selection corner radius, like the shell's pills
ITEM_STATES = {"toggled": YELLOW_DIM, "pressed": YELLOW_DIM, "focused": BG1}


def rounded_nine(prefix, color, ox, oy, r=RADIUS, c=16):
    """Kvantum 9-slice element set with quarter-circle corners of radius r."""
    f = f'style="fill:{color}"'
    x1, x2, y1, y2 = ox + r, ox + r + c, oy + r, oy + r + c
    return "\n".join([
        f'<path id="{prefix}-topleft" {f} d="M{x1},{oy} A{r},{r} 0 0 0 {ox},{y1} L{x1},{y1} Z"/>',
        f'<rect id="{prefix}-top" {f} x="{x1}" y="{oy}" width="{c}" height="{r}"/>',
        f'<path id="{prefix}-topright" {f} d="M{x2},{oy} A{r},{r} 0 0 1 {x2 + r},{y1} L{x2},{y1} Z"/>',
        f'<rect id="{prefix}-left" {f} x="{ox}" y="{y1}" width="{r}" height="{c}"/>',
        f'<rect id="{prefix}" {f} x="{x1}" y="{y1}" width="{c}" height="{c}"/>',
        f'<rect id="{prefix}-right" {f} x="{x2}" y="{y1}" width="{r}" height="{c}"/>',
        f'<path id="{prefix}-bottomleft" {f} d="M{ox},{y2} A{r},{r} 0 0 0 {x1},{y2 + r} L{x1},{y2} Z"/>',
        f'<rect id="{prefix}-bottom" {f} x="{x1}" y="{y2}" width="{c}" height="{r}"/>',
        f'<path id="{prefix}-bottomright" {f} d="M{x2 + r},{y2} A{r},{r} 0 0 1 {x2},{y2 + r} L{x2},{y2} Z"/>',
    ])


def round_itemview(text):
    """Replace KvGnomeDark's square list/tree selection with rounded pieces."""
    ids = r"itemview-(?:focused|pressed|toggled)(?:-(?:top|bottom|left|right|topleft|topright|bottomleft|bottomright))?"
    text = re.sub(r'id="(' + ids + r')"', r'id="orig-\1"', text)
    text = re.sub(r'href="#(' + ids + r')"', r'href="#orig-\1"', text)
    # widen the canvas and park the new pieces to the right of the stock artwork
    text = re.sub(r'<svg width="(\d+)"', lambda m: f'<svg width="{int(m.group(1)) + 120}"', text, count=1)
    width = int(re.search(r'<svg width="(\d+)"', text).group(1))
    pieces = [rounded_nine(f"itemview-{st}", col, width - 100, 20 + i * 60) for i, (st, col) in enumerate(ITEM_STATES.items())]
    return text.replace("</svg>", '<g id="kvteerquaz-rounded-itemview">\n' + "\n".join(pieces) + "\n</g>\n</svg>")


def svg():
    text = (SRC / "KvGnomeDark.svg").read_text()
    text = re.sub(r"#[0-9a-fA-F]{6}\b", lambda m: recolor(m.group(0)), text)
    return round_itemview(text)


GENERAL_COLORS = {
    "window.color": BG0, "inactive.window.color": BG0,
    "base.color": BG0, "inactive.base.color": BG0,
    "alt.base.color": BG0_S, "inactive.alt.base.color": BG0_S,
    "button.color": BG1, "light.color": BG2, "mid.light.color": "#2a3237",
    "dark.color": BG0_H, "mid.color": BG1,
    "highlight.color": YELLOW_DIM, "inactive.highlight.color": "#1b8a84",
    "text.color": FG1, "inactive.text.color": FG1 + "c8",
    "window.text.color": FG1, "inactive.window.text.color": FG1 + "78",
    "button.text.color": FG1, "disabled.text.color": "#5c6a72",
    "tooltip.text.color": FG1, "highlight.text.color": BG0,
    "link.color": BLUE, "link.visited.color": PURPLE,
    "progress.indicator.text.color": BG0,
}

# text drawn on the yellow selection / hover must be dark
ON_HIGHLIGHT = {
    ("MenuItem", "text.focus.color"), ("MenuItem", "text.toggle.color"),
    ("ItemView", "text.focus.color"), ("ItemView", "text.toggle.color"),
    ("MenuBarItem", "text.focus.color"), ("MenuBarItem", "text.toggle.color"),
    ("ProgressbarContents", "text.normal.color"), ("ProgressbarContents", "text.focus.color"),
}


def value_color(v):
    v = v.strip()
    if v.lower() == "white":
        return FG1
    if v.lower() == "black":
        return BG0
    m = re.fullmatch(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?", v)
    if not m:
        return v
    base = "#" + m.group(1)
    alpha = m.group(2) or ""
    if base.lower() == "#ffffff":
        return FG1 + alpha
    return recolor(base) + alpha


def kvconfig():
    out, section = [], ""
    for line in (SRC / "KvGnomeDark.kvconfig").read_text().splitlines():
        s = re.match(r"\[(.+)\]", line)
        if s:
            section = s.group(1)
            out.append(line)
            continue
        kv = re.match(r"([\w.]+)=(.*)", line)
        if not kv:
            out.append(line)
            continue
        key, val = kv.groups()
        if section == "GeneralColors" and key in GENERAL_COLORS:
            val = GENERAL_COLORS[key]
        elif (section, key) in ON_HIGHLIGHT:
            val = BG0
        elif key.endswith(".color") or key.endswith("color"):
            val = value_color(val)
        elif section == "ItemView" and key in ("frame.top", "frame.bottom", "frame.left", "frame.right"):
            val = str(RADIUS)
        elif section == "ItemView" and key in ("text.margin.left", "text.margin.right"):
            val = str(RADIUS)
        elif section == "%General" and key in ("author", "comment"):
            val = "generated by ~/.config/Kvantum/build-kvteerquaz.py from KvGnomeDark (Teerquaz, matches the Quickshell shell)"
        out.append(f"{key}={val}")
    return "\n".join(out) + "\n"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{NAME}.svg").write_text(svg())
    (OUT / f"{NAME}.kvconfig").write_text(kvconfig())
    conf = OUT.parent / "kvantum.kvconfig"
    conf.write_text(f"[General]\ntheme={NAME}\n")
    print(f"wrote {OUT} and selected it in {conf}")


if __name__ == "__main__":
    main()
