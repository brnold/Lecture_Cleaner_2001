#!/usr/bin/env python3
"""
whisper_json_to_pdf.py

Convert Whisper JSON transcript to a readable PDF with:
- Light text cleanup (conservative)
- ~30s timestamp "margin notes"
- Book-like typography and spacing

Usage:
  python whisper_json_to_pdf.py lecture.json -o lecture.pdf --title "ECE 561 Lecture 12" --interval 30
"""

from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass
from typing import List, Optional, Tuple

from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
)
from reportlab.lib import colors


# ----------------------------
# Helpers: time + text cleanup
# ----------------------------

def fmt_time(seconds: float) -> str:
    s = int(seconds + 0.5)
    h = s // 3600
    m = (s % 3600) // 60
    sec = s % 60
    if h > 0:
        return f"{h:02d}:{m:02d}:{sec:02d}"
    return f"{m:02d}:{sec:02d}"


FILLER_WORDS = [
    r"\bum+\b",
    r"\buh+\b",
    r"\ber+\b",
    r"\bah+\b",
    r"\blike\b",        # conservative: removes standalone "like"
    r"\byou know\b",
    r"\bkind of\b",
    r"\bsort of\b",
    r"\bI mean\b",
]

FILLER_RE = re.compile(
    r"(?i)(?:"
    + "|".join(FILLER_WORDS)
    + r")"
)

def light_cleanup(text: str) -> str:
    """
    Conservative cleanup:
    - normalize whitespace
    - remove common filler words/phrases (light touch)
    - remove immediate repeated words ("the the")
    - fix spacing around punctuation
    - add period if the block looks like a sentence without terminal punctuation
    """
    t = text.strip()

    # Normalize whitespace
    t = re.sub(r"\s+", " ", t)

    # Remove filler (only when it appears as a standalone phrase/word)
    # Keep it conservative by removing with surrounding optional commas/spaces.
    t = re.sub(r"(?i)(^|[ ,;:])(" + "|".join(FILLER_WORDS) + r")([ ,;:]|$)", r"\1\3", t)
    t = re.sub(r"\s+", " ", t).strip()

    # De-stutter: repeated words (case-insensitive), e.g. "the the", "we we"
    t = re.sub(r"(?i)\b(\w+)\s+\1\b", r"\1", t)

    # Fix spacing before punctuation
    t = re.sub(r"\s+([,.;:!?])", r"\1", t)

    # Ensure space after punctuation when followed by a letter
    t = re.sub(r"([,.;:!?])([A-Za-z])", r"\1 \2", t)

    # Clean double punctuation like ".." or ",,"
    t = re.sub(r"([,.;:!?])\1+", r"\1", t)

    # If it looks like a sentence chunk and lacks terminal punctuation, add a period.
    if t and not re.search(r"[.!?]\s*$", t):
        # Avoid adding periods after headings or short fragments
        if len(t) > 40:
            t += "."

    return t


# ----------------------------
# Data structures
# ----------------------------

@dataclass
class Segment:
    start: float
    end: float
    text: str


@dataclass
class Block:
    start: float
    end: float
    text: str


def load_whisper_json(path: str) -> List[Segment]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "segments" not in data or not isinstance(data["segments"], list):
        raise ValueError("JSON does not look like Whisper output: missing 'segments' list.")

    segs: List[Segment] = []
    for s in data["segments"]:
        segs.append(Segment(
            start=float(s.get("start", 0.0)),
            end=float(s.get("end", 0.0)),
            text=str(s.get("text", "")).strip(),
        ))
    return segs


def build_blocks(segments: List[Segment], interval_s: int = 30) -> List[Block]:
    """
    Group Whisper segments into ~interval_s blocks by time.
    Each block becomes one "margin timestamp" row in the PDF.
    """
    if not segments:
        return []

    # Determine transcript start/end
    t_start = segments[0].start
    t_end = max(s.end for s in segments)

    # Align bins to the floor of the first segment start
    bin0 = math.floor(t_start / interval_s) * interval_s
    nbins = int(math.ceil((t_end - bin0) / interval_s))

    blocks: List[Block] = []
    seg_idx = 0

    for i in range(nbins):
        b_start = bin0 + i * interval_s
        b_end = b_start + interval_s

        texts = []
        # collect segments overlapping this bin
        while seg_idx < len(segments) and segments[seg_idx].end <= b_start:
            seg_idx += 1

        j = seg_idx
        while j < len(segments) and segments[j].start < b_end:
            if segments[j].text:
                texts.append(segments[j].text)
            j += 1

        if texts:
            raw = " ".join(texts)
            cleaned = light_cleanup(raw)
            if cleaned:
                blocks.append(Block(start=b_start, end=b_end, text=cleaned))

    return blocks


# ----------------------------
# PDF generation (margin timestamps)
# ----------------------------

def make_pdf(
    blocks: List[Block],
    out_pdf: str,
    title: str,
    subtitle: Optional[str] = None,
    pagesize=letter,
) -> None:
    doc = SimpleDocTemplate(
        out_pdf,
        pagesize=pagesize,
        leftMargin=0.85 * inch,
        rightMargin=0.85 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
        title=title,
        author="Whisper Transcript Formatter",
    )

    styles = getSampleStyleSheet()
    style_title = ParagraphStyle(
        "Title",
        parent=styles["Title"],
        fontName="Helvetica-Bold",
        fontSize=18,
        leading=22,
        spaceAfter=10,
        alignment=TA_LEFT,
    )
    style_subtitle = ParagraphStyle(
        "Subtitle",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=10.5,
        leading=14,
        textColor=colors.grey,
        spaceAfter=18,
    )
    style_ts = ParagraphStyle(
        "Timestamp",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=9,
        leading=12,
        textColor=colors.grey,
    )
    style_body = ParagraphStyle(
        "Body",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=11,
        leading=15,
        spaceAfter=6,
    )

    story = []
    story.append(Paragraph(title, style_title))
    if subtitle:
        story.append(Paragraph(subtitle, style_subtitle))

    # Table approach: two columns per block:
    # left = timestamp, right = text
    rows = []
    for b in blocks:
        ts = fmt_time(b.start)
        rows.append([
            Paragraph(f"<b>{ts}</b>", style_ts),
            Paragraph(b.text, style_body),
        ])

    # Column widths: timestamp margin + main text
    # Adjust if you want a wider margin
    table = Table(
        rows,
        colWidths=[0.9 * inch, doc.width - 0.9 * inch],
        hAlign="LEFT",
    )
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        # subtle row separators (optional)
        ("LINEBELOW", (0, 0), (-1, -1), 0.25, colors.whitesmoke),
    ]))

    story.append(table)
    doc.build(story)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("whisper_json", help="Whisper JSON file (from whisper --output_format json)")
    ap.add_argument("-o", "--out", default="transcript.pdf", help="Output PDF filename")
    ap.add_argument("--title", default="Lecture Transcript", help="PDF title")
    ap.add_argument("--subtitle", default=None, help="Optional subtitle (course/date/etc.)")
    ap.add_argument("--interval", type=int, default=30, help="Timestamp interval in seconds (default 30)")

    args = ap.parse_args()

    segments = load_whisper_json(args.whisper_json)
    blocks = build_blocks(segments, interval_s=args.interval)

    if not blocks:
        raise SystemExit("No transcript text found in JSON segments.")

    make_pdf(blocks, out_pdf=args.out, title=args.title, subtitle=args.subtitle)
    print(f"Wrote: {args.out}  ({len(blocks)} timestamp blocks, ~{args.interval}s each)")


if __name__ == "__main__":
    main()

