# Module 6 audio lesson

`sql-in-a-real-replication.m4b`: about 36 minutes, 11 chapters, for Apple Books
(AirDrop it to the phone, or add it to Books on the Mac and sync). It walks through the
four blocks of the real query in words, then (chapter 10) the four blocks of part 2:
re-pasted rows, exclusions, yearly sums and rows picked by label. No query is read
character by character.

- `text/NN_title.txt`: the narration, one file per chapter (first line is the chapter
  title). Edit these, then rebuild.
- `cover.png`: the title card used as the cover.
- `audio/`: per-chapter MP3s, an intermediate (gitignored).

Rebuild from the repo root:

```sh
rm -rf module-06/lesson/audio
zsh tools/quiz/narrate_sections.sh module-06/lesson/text module-06/lesson/audio
~/Desktop/sandbox/audiotext/.venv/bin/python tools/quiz/make_audiobook.py \
  module-06/lesson/audio module-06/lesson/text module-06/lesson/cover.png \
  module-06/lesson/sql-in-a-real-replication.m4b \
  "SQL in a Real Replication" "sql-industry-prep, module 6"
```
