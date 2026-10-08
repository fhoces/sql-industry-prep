"""Join per-section MP3s into a chaptered .m4b audiobook for Apple Books.

Usage: python make_audiobook.py AUDIO_DIR TEXT_DIR COVER.png OUT.m4b TITLE AUTHOR

Copied from book-summaries/tools/tts/make_audiobook.py, with two changes:
the cover is a PNG image (make_cover.py draws a title card) instead of page
1 of a PDF, and section text files may be named NN.txt or NN_title.txt.
Chapter names come from the first line of each text file; chapter
boundaries from each MP3's decoded duration.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import imageio_ffmpeg

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def duration_ms(path):
    """Decode fully and read the final timestamp (exact, unlike header estimates)."""
    err = subprocess.run([FFMPEG, "-i", str(path), "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    h, m, s = re.findall(r"time=(\d+):(\d+):([\d.]+)", err)[-1]
    return round((int(h) * 3600 + int(m) * 60 + float(s)) * 1000)


def esc(s):
    return re.sub(r"([=;#\\\n])", r"\\\1", s)


def main():
    audio_dir, text_dir, cover, out, title, author = sys.argv[1:7]
    mp3s = sorted(Path(audio_dir).glob("[0-9][0-9]_*.mp3"))
    texts = {p.name[:2]: p for p in Path(text_dir).glob("[0-9][0-9]*.txt")}
    if not mp3s or sorted(texts) != [p.name[:2] for p in mp3s]:
        sys.exit(f"sections and MP3s do not match: {sorted(texts)} vs {[p.name for p in mp3s]}")
    tmp = Path(tempfile.mkdtemp())

    meta = [";FFMETADATA1", f"title={esc(title)}", f"album={esc(title)}",
            f"artist={esc(author)}", f"album_artist={esc(author)}",
            "genre=Audiobook", "comment=Narrated with edge-tts (en-US-AndrewNeural)"]
    start = 0
    for mp3 in mp3s:
        name = texts[mp3.name[:2]].read_text().splitlines()[0].rstrip(".")
        end = start + duration_ms(mp3)
        meta += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={start}", f"END={end}",
                 f"title={esc(name)}"]
        print(f"{start / 60000:6.2f} min  {name}")
        start = end
    (tmp / "meta.txt").write_text("\n".join(meta) + "\n")
    (tmp / "list.txt").write_text("".join(f"file '{p.resolve()}'\n" for p in mp3s))

    subprocess.run([FFMPEG, "-y", "-loglevel", "error",
                    "-f", "concat", "-safe", "0", "-i", tmp / "list.txt",
                    "-i", tmp / "meta.txt", "-i", cover,
                    "-map", "0:a", "-map", "2:v", "-map_metadata", "1", "-map_chapters", "1",
                    "-c:a", "aac", "-b:a", "64k", "-c:v", "mjpeg",
                    "-disposition:v", "attached_pic",
                    "-f", "ipod", "-movflags", "+faststart", out], check=True)
    print(f"total {start / 60000:.2f} min -> {out}")


if __name__ == "__main__":
    main()
