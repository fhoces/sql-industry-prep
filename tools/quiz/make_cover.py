"""Draw a square title-card PNG for an audiobook cover.

Usage: python make_cover.py OUT.png "Title" "Subtitle" "Course name"

Uses PyMuPDF (installed with the audiobook tools): one 1400 x 1400 px page,
plain colours, the text centred, rendered to PNG.
"""
import sys

import pymupdf as fitz


def main():
    out, title, subtitle, course = sys.argv[1:5]
    size = 700  # points; rendered at 2x for 1400 px
    doc = fitz.open()
    page = doc.new_page(width=size, height=size)
    page.draw_rect(page.rect, color=None, fill=(0.18, 0.36, 0.31))
    page.draw_rect(fitz.Rect(50, 50, size - 50, size - 50), color=(0.98, 0.97, 0.95), width=2)
    page.insert_textbox(fitz.Rect(80, 180, size - 80, 420), title, fontsize=46,
                        fontname="helv", color=(1, 1, 1), align=1)
    page.insert_textbox(fitz.Rect(80, 430, size - 80, 540), subtitle, fontsize=22,
                        fontname="helv", color=(0.85, 0.92, 0.89), align=1)
    page.insert_textbox(fitz.Rect(80, 580, size - 80, 640), course, fontsize=18,
                        fontname="helv", color=(0.85, 0.92, 0.89), align=1)
    page.get_pixmap(dpi=144).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
