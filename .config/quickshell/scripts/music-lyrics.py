#!/usr/bin/env python3
"""Lyrics for one song, for Music.qml.

usage: music-lyrics.py PATH ARTIST TITLE ALBUM DURATION [--refresh]

Looks in this order and prints one JSON object
  { "synced": [[seconds, "line"], ...], "plain": "...", "source": "...", "instrumental": bool }
  1. a .lrc file next to the song (Song.lrc)
  2. lyrics embedded in the file's tags
  3. lrclib.net (free, open lyrics database; only artist/title/album/length are sent)
Online results (also "not found") are cached in ~/.cache/qs-music/lyrics;
"not found" is retried after a week.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

cache_dir = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "qs-music", "lyrics")
os.makedirs(cache_dir, exist_ok=True)
UA = "qs-music/1.0 (Quickshell music player; https://github.com/quickshell-mirror/quickshell)"
TIME = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def parse_lrc(text):
    out = []
    for line in text.splitlines():
        stamps = TIME.findall(line)
        if not stamps:
            continue
        words = TIME.sub("", line).strip()
        for m, s in stamps:
            out.append([int(m) * 60 + float(s), words])
    out.sort(key=lambda x: x[0])
    return out


def result(synced="", plain="", source="", instrumental=False):
    lines = parse_lrc(synced) if synced else []
    if not plain and lines:
        plain = "\n".join(l[1] for l in lines)
    return {"synced": lines, "plain": (plain or "").strip(), "source": source, "instrumental": bool(instrumental)}


def local(path):
    lrc = os.path.splitext(path)[0] + ".lrc"
    if os.path.exists(lrc):
        with open(lrc, encoding="utf-8", errors="replace") as f:
            t = f.read()
        return result(t, "" if TIME.search(t) else t, "file")
    try:
        out = subprocess.run(["ffprobe", "-v", "quiet", "-of", "json", "-show_format", "-show_streams", path],
                             capture_output=True, text=True, timeout=20).stdout
        info = json.loads(out or "{}")
    except Exception:
        return None
    tags = dict(info.get("format", {}).get("tags", {}))
    for s in info.get("streams", []):
        tags.update(s.get("tags", {}))
    for k, v in tags.items():
        kl = k.lower()
        if (kl.startswith("lyrics") or kl in ("unsyncedlyrics", "uslt", "syncedlyrics", "sylt")) and v.strip():
            return result(v if TIME.search(v) else "", "" if TIME.search(v) else v, "tags")
    return None


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def online(artist, title, album, duration):
    q = {"artist_name": artist, "track_name": title}
    if album:
        q["album_name"] = album
    if duration > 0:
        q["duration"] = str(round(duration))
    hit = get("https://lrclib.net/api/get?" + urllib.parse.urlencode(q))
    if not hit:
        # search is looser: any album, length within 8 s
        found = get("https://lrclib.net/api/search?" + urllib.parse.urlencode({"artist_name": artist, "track_name": title})) or []
        found = [f for f in found if not duration or abs((f.get("duration") or 0) - duration) <= 8] or found
        found.sort(key=lambda f: (not f.get("syncedLyrics"), abs((f.get("duration") or 0) - duration)))
        hit = found[0] if found else None
    if not hit:
        return None
    return result(hit.get("syncedLyrics") or "", hit.get("plainLyrics") or "", "lrclib.net", hit.get("instrumental"))


def main():
    path, artist, title, album = sys.argv[1:5]
    duration = float(sys.argv[5] or 0)
    refresh = "--refresh" in sys.argv

    r = local(path)
    if r:
        print(json.dumps(r))
        return

    key = os.path.join(cache_dir, hashlib.md5(f"{artist}\n{title}".lower().encode()).hexdigest() + ".json")
    if not refresh and os.path.exists(key):
        try:
            with open(key) as f:
                c = json.load(f)
            if c.get("source") or time.time() - os.path.getmtime(key) < 7 * 86400:
                print(json.dumps(c))
                return
        except Exception:
            pass

    if not artist or not title:
        print(json.dumps(result()))
        return
    try:
        r = online(artist, title, album, duration) or result()
    except Exception as e:
        print(json.dumps({**result(), "error": str(e)}))   # offline: don't cache
        return
    with open(key + ".tmp", "w") as f:
        json.dump(r, f)
    os.replace(key + ".tmp", key)
    print(json.dumps(r))


if __name__ == "__main__":
    main()
