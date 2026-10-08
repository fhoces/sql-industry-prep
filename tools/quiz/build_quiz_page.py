#!/usr/bin/env python3
"""Build <quiz dir>/listen.html from listen.template.html + quiz.json.

Usage: python tools/quiz/build_quiz_page.py module-06/quiz

Copied from book-summaries/tools/build_quiz_page.py (courses are
self-contained, so tools are copied, not shared). The page itself is
unchanged except for the optional "code" field (see listen.template.html).
"""
import json, sys
from pathlib import Path
quiz = Path(sys.argv[1])
data = json.dumps(json.loads((quiz / "quiz.json").read_text()), ensure_ascii=False).replace("</", "<\\/")
tpl = (quiz / "listen.template.html").read_text()
(quiz / "listen.html").write_text(tpl.replace("__DATA__", data))
print("wrote", quiz / "listen.html")
