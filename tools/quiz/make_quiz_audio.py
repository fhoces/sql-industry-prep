#!/usr/bin/env python3
"""Generate quiz audio clips in the audiobook voice (edge-tts, en-US-AndrewNeural).

Usage: python tools/quiz/make_quiz_audio.py module-06/quiz/audio/clips.json

clips.json is a list of {"file": "q01-stem.mp3", "text": "..."}. Clips are written
next to clips.json. Runs one call at a time with retries (parallel calls can fail
silently), skips clips that already exist, and never leaves 0-byte files.
"""
import json, sys, time
from pathlib import Path
import edge_tts

VOICE = "en-US-AndrewNeural"  # rate/volume/pitch left at defaults, as in the audiobooks

manifest = Path(sys.argv[1])
outdir = manifest.parent
clips = json.loads(manifest.read_text())
failed = []
for c in clips:
    out = outdir / c["file"]
    if out.exists() and out.stat().st_size > 0:
        continue
    for attempt in range(5):
        try:
            edge_tts.Communicate(c["text"], VOICE).save_sync(str(out))
            if out.stat().st_size > 0:
                print("ok  ", c["file"])
                break
        except Exception as e:
            print("retry", c["file"], type(e).__name__)
        out.unlink(missing_ok=True)
        time.sleep(2 * (attempt + 1))
    else:
        failed.append(c["file"])
print(f"\n{len(clips) - len(failed)}/{len(clips)} clips present.")
if failed:
    print("FAILED:", *failed, sep="\n  ")
    sys.exit(1)
