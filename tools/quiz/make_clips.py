#!/usr/bin/env python3
"""Write audio/clips.json and questions.md from a quiz.json, and check balance.

Usage: python tools/quiz/make_clips.py module-06/quiz

quiz.json has the schema of book-summaries/books/<slug>/quiz.json
({"book", "levels", "concepts": [{"id", "title", "levels": {"1": {q, opts,
answer, why}, ...}}]}) plus one optional field per question: "code" (a
string, shown on the page above the options) and its "lang" ("sql" or
"python").

Clip rules (7 per question: stem, four options, right, wrong):
  * A question without code is read as "<concept title>. <q>", as in the
    book quizzes.
  * A question with code is read from its "q" text only, which must start
    with "Look at the code on the screen." The code is never sent to TTS.
  * Options are read as "Option A. <text>."; feedback as "Correct. <why>"
    or "Not quite. The answer is C. <why>".

Checks printed at the end: how often the right answer is the longest
option, the spread of right answers over A to D, option lengths (at most
about 20 words), runs of code questions within a concept, and any
em-dash or code-looking text in what will be spoken.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

L = "ABCD"
CODE_LEAD = "Look at the code on the screen."


def spoken(item):
    return [item["q"], *item["opts"], item["why"]]


def main(quiz_dir):
    quiz_dir = Path(quiz_dir)
    quiz = json.loads((quiz_dir / "quiz.json").read_text())
    clips, md, problems = [], [], []
    longest, positions, n_q, n_code = 0, Counter(), 0, 0
    md += [f"# Quiz questions: {quiz['book']}", "",
           "Generated from `quiz.json` by `tools/quiz/make_clips.py`; do not edit by hand. "
           "Each concept has three levels: Warm-up (1), Core (2) and Deep (3). "
           "Questions marked (code) show a code block on the quiz page; the audio says "
           "\"Look at the code on the screen\" instead of reading it. The answer key is at the bottom.", ""]
    key = []
    for n, c in enumerate(quiz["concepts"], 1):
        md += [f"## {n}. {c['title']}"]
        kinds = []
        for lv in ("1", "2", "3"):
            it = c["levels"][lv]
            n_q += 1
            k = f"{c['id']}-L{lv}"
            has_code = bool(it.get("code"))
            kinds.append(has_code)
            if has_code:
                n_code += 1
                if not it["q"].startswith(CODE_LEAD):
                    problems.append(f"{k}: code question must start with '{CODE_LEAD}'")
                if it.get("lang") not in ("sql", "python"):
                    problems.append(f"{k}: lang must be sql or python")
                if len(it["code"].splitlines()) > 13:
                    problems.append(f"{k}: code has {len(it['code'].splitlines())} lines")
                stem = it["q"]
            else:
                if it["q"].startswith(CODE_LEAD):
                    problems.append(f"{k}: says 'look at the code' but has no code")
                stem = f"{c['title']}. {it['q']}"
            if len(it["opts"]) != 4 or it["answer"] not in range(4):
                problems.append(f"{k}: needs 4 options and an answer 0-3")
            lens = [len(o) for o in it["opts"]]
            if lens[it["answer"]] == max(lens):
                longest += 1
            positions[L[it["answer"]]] += 1
            for j, o in enumerate(it["opts"]):
                if len(o.split()) > 22:
                    problems.append(f"{k} option {L[j]}: {len(o.split())} words")
            for text in spoken(it):
                if "\u2014" in text:
                    problems.append(f"{k}: em-dash in spoken text")
                if re.search(r"[;{}]|\bSELECT\b.*\bFROM\b|\(\)\s*$|==", text):
                    problems.append(f"{k}: spoken text looks like code: {text[:60]!r}")
            clips.append({"file": f"{k}-stem.mp3", "text": stem})
            for j, o in enumerate(it["opts"]):
                clips.append({"file": f"{k}-opt{L[j]}.mp3", "text": f"Option {L[j]}. {o.rstrip('.')}."})
            clips.append({"file": f"{k}-right.mp3", "text": f"Correct. {it['why']}"})
            clips.append({"file": f"{k}-wrong.mp3",
                          "text": f"Not quite. The answer is {L[it['answer']]}. {it['why']}"})
            label = quiz["levels"][lv]
            md += [f"**{label}.**{' (code)' if has_code else ''} {it['q']}"]
            if has_code:
                md += ["", f"```{it['lang']}", it["code"], "```", ""]
            md += [f"- {L[j]}) {o}" for j, o in enumerate(it["opts"])] + [""]
            key.append(f"- {n}.{lv} {c['title']}, {label}: **{L[it['answer']]}**. {it['why']}")
        if all(kinds):
            problems.append(f"{c['id']}: three code questions in a row")
    md += ["## Answer key", ""] + key + [""]
    audio = quiz_dir / "audio"
    audio.mkdir(exist_ok=True)
    (audio / "clips.json").write_text(json.dumps(clips, indent=1, ensure_ascii=False) + "\n")
    (quiz_dir / "questions.md").write_text("\n".join(md))
    print(f"{n_q} questions ({n_code} with code), {len(clips)} clips -> {audio / 'clips.json'}")
    print(f"right answer is the longest option in {longest} of {n_q} questions")
    print("right-answer positions: " + ", ".join(f"{p} {positions[p]}" for p in L))
    if problems:
        print("PROBLEMS:", *problems, sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
