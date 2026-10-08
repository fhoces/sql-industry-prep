#!/bin/zsh
# Narrate every TEXT_DIR/NN_title.txt section with edge-tts, one call per section
# in parallel (each call streams at roughly real time), retrying failures once.
# Copied from book-summaries/tools/tts/narrate_sections.sh; the only change is
# that section files may be named NN.txt or NN_title.txt.
# Usage: narrate_sections.sh TEXT_DIR AUDIO_DIR [VOICE]
set -u
TEXT_DIR=${1:?text dir}; AUDIO_DIR=${2:?audio dir}; VOICE=${3:-en-US-AndrewNeural}
EDGE=${EDGE_TTS:-$HOME/Desktop/sandbox/audiotext/.venv/bin/edge-tts}
mkdir -p "$AUDIO_DIR"

name_for() {  # 03_null_semantics.txt -> 03_NULL_Semantics.mp3 (title from line 1)
  local f=$1 n title
  n=$(basename "$f" .txt | cut -c1-2)
  title=$(head -1 "$f" | sed -E 's/[^A-Za-z0-9 ]//g; s/ +/_/g' | cut -c1-60)
  print -r -- "$AUDIO_DIR/${n}_${title}.mp3"
}

run_all() {
  for f in "$TEXT_DIR"/[0-9][0-9]*.txt; do
    out=$(name_for "$f")
    [[ -s $out ]] && continue
    ( "$EDGE" --voice "$VOICE" --file "$f" --write-media "$out.part" \
        && mv "$out.part" "$out" || { rm -f "$out.part"; echo "FAIL $f"; } ) &
  done
  wait
}

run_all
run_all   # second pass only redoes sections still missing
missing=0
for f in "$TEXT_DIR"/[0-9][0-9]*.txt; do
  [[ -s $(name_for "$f") ]] || { echo "STILL MISSING: $f"; missing=1; }
done
exit $missing
