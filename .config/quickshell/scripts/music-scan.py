#!/usr/bin/env python3
"""Music library index for Music.qml.

Walks the music folder, reads tags + length with ffprobe and pulls the
embedded cover (or a cover.jpg / folder.jpg next to the file) into
~/.cache/qs-music/art. Results are cached by path + mtime, so only new or
changed files are probed again. Prints one JSON array on stdout.
"""
import hashlib
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

EXTS = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".aac", ".wma", ".alac", ".ape", ".mka", ".webm"}
COVERS = ("cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "album.jpg")

cache_dir = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "qs-music")
art_dir = os.path.join(cache_dir, "art")
index_path = os.path.join(cache_dir, "index.json")
os.makedirs(art_dir, exist_ok=True)


def tag(tags, *names):
    low = {k.lower(): v for k, v in tags.items()}
    for n in names:
        if low.get(n):
            return low[n].strip()
    return ""


def probe(path, mtime):
    item = {"path": path, "mtime": mtime, "title": "", "artist": "", "album": "", "duration": 0, "art": ""}
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "quiet", "-of", "json", "-show_format", "-show_streams", path],
            capture_output=True, text=True, timeout=20).stdout
        info = json.loads(out or "{}")
    except Exception:
        info = {}
    fmt = info.get("format", {})
    tags = dict(fmt.get("tags", {}))
    for s in info.get("streams", []):          # ogg/opus keep tags on the stream
        if s.get("codec_type") == "audio":
            for k, v in s.get("tags", {}).items():
                tags.setdefault(k, v)
    item["title"] = tag(tags, "title")
    item["artist"] = tag(tags, "artist", "album_artist", "albumartist")
    item["album"] = tag(tags, "album")
    try:
        item["duration"] = float(fmt.get("duration") or 0)
    except ValueError:
        pass

    # A file named "Artist - Title.mp3" wins over the tags: downloaded files
    # often carry the uploader as artist and "(Official Video)" in the title.
    # "01 - Title.flac" is a track number, not an artist, so tags stay then.
    stem = os.path.splitext(os.path.basename(path))[0]
    left, sep, right = stem.partition(" - ")
    if sep and left.strip() and right.strip() and not left.strip().isdigit():
        item["artist"], item["title"] = left.strip(), right.strip()
    elif not item["title"]:
        item["title"] = stem

    has_pic = any(s.get("codec_type") == "video" for s in info.get("streams", []))
    art = os.path.join(art_dir, hashlib.md5(path.encode()).hexdigest() + ".jpg")
    if has_pic:
        r = subprocess.run(
            ["ffmpeg", "-v", "quiet", "-y", "-i", path, "-an", "-frames:v", "1",
             "-vf", "scale=512:512:force_original_aspect_ratio=increase,crop=512:512", art],
            timeout=30)
        if r.returncode == 0 and os.path.exists(art):
            item["art"] = art
    if not item["art"]:
        d = os.path.dirname(path)
        for c in COVERS:
            for name in (c, c.capitalize()):
                p = os.path.join(d, name)
                if os.path.exists(p):
                    item["art"] = p
                    break
            if item["art"]:
                break
    return item


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Music")
    try:
        with open(index_path) as f:
            old = {t["path"]: t for t in json.load(f)}
    except Exception:
        old = {}

    files = []
    for d, dirs, names in os.walk(root, followlinks=True):
        dirs[:] = [x for x in dirs if not x.startswith(".")]
        for n in names:
            if os.path.splitext(n)[1].lower() in EXTS:
                p = os.path.join(d, n)
                try:
                    files.append((p, os.stat(p).st_mtime))
                except OSError:
                    pass

    keep, todo = [], []
    for p, m in files:
        t = old.get(p)
        if t and t.get("mtime") == m and (not t.get("art") or os.path.exists(t["art"])):
            keep.append(t)
        else:
            todo.append((p, m))
    with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as ex:
        keep += list(ex.map(lambda a: probe(*a), todo))

    keep.sort(key=lambda t: t["path"].lower())
    with open(index_path + ".tmp", "w") as f:
        json.dump(keep, f)
    os.replace(index_path + ".tmp", index_path)
    json.dump(keep, sys.stdout)


if __name__ == "__main__":
    main()
