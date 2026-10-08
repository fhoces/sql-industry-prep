# Module 6 walking quiz

**Quiz page:** https://claude.ai/artifact/HRQfx89mVuNM8puPenTE8R (claude.ai Artifact,
capabilities `db` + `user`, private to the owner).

An adaptive, read-aloud multiple-choice quiz on module 6: 18 concepts, each at three
levels (Warm-up, Core, Deep), 54 questions. Concepts 1 to 12 cover part 1 (`01_rtb_ca.sql`);
concepts 13 to 18, added with part 2, cover re-pasted rows and `ROW_NUMBER`, what counts as a
copy, NULLs in groups versus `=`, `NOT IN` in a CTE, yearly sums with `COALESCE` and
`COUNT(*)`, and picking rows by label. It is built for walking with the phone in a
pocket:

- every question and option is read aloud in the audiobook voice (edge-tts,
  `en-US-AndrewNeural`, default rate, volume and pitch);
- tap an answer while the question is still being read, tap the question to hear it
  again, and the next question starts on its own (Hands-free);
- you start at Core. Two right in a row moves you up a level, a miss moves you down
  one, a missed concept returns three questions later one level easier, and a concept
  is mastered when its Deep question is right.

Half of the questions are about a piece of code. Those show the code in a grey box and
the audio starts with "Look at the code on the screen." The code itself is never read
aloud. Within each concept, code and spoken-only questions alternate, so the quiz
never asks three code questions about one concept in a row.

Progress is saved in the page's database (`state/progress`), and every answer is logged
in `attempts` (concept, level, choice, right or wrong, time). Claude can read both with
the ArtifactData tool to update `progress.md`.

## Files

| File | What it is |
|---|---|
| `quiz.json` | the question bank, the single source for everything else (schema of book-summaries' `quiz.json`, plus an optional `code` and `lang` per question) |
| `questions.md` | readable version with the answer key, generated; do not edit |
| `listen.template.html` | the page template (from book-summaries, with the code box added) |
| `listen.html` | the built page that is published |
| `audio/clips.json`, `audio/*.mp3` | 378 clips: per question a stem, four options, a "correct" and a "not quite" explanation |
| `progress.md` | your results, pulled from the page's database |

## Rebuild

From the repo root:

```sh
python tools/quiz/make_clips.py module-06/quiz          # questions.md, audio/clips.json, balance report
python tools/quiz/build_quiz_page.py module-06/quiz     # listen.html
~/Desktop/sandbox/audiotext/.venv/bin/python tools/quiz/make_quiz_audio.py module-06/quiz/audio/clips.json
```

`make_quiz_audio.py` skips clips that already exist, so after changing any question,
option or explanation, delete the MP3s whose text changed before running it. Then
republish `listen.html` to the same URL with the MP3s in the Artifact tool's `files`
(at most 255 per publish).

`make_clips.py` also prints the balance checks: the right answer is the longest option
in 13 of 54 questions, and right answers sit at A 14, B 13, C 13 and D 14 times.
