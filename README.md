# lecture_cleaner_2001

Tools to clean lecture audio and turn Whisper JSON transcripts into readable PDFs.

## What it does

- **Audio cleanup**: `deepfilter_lecture.sh` denoises and normalizes lecture audio with DeepFilterNet + ffmpeg, producing `*_denoised.mp3`.
- **Transcript PDF**: `whisper_json_to_pdf.py` formats Whisper JSON into a PDF with timestamp margin notes.
- **Batch PDF**: `whisper_dir_to_pdf.sh` converts every `*.json` in a folder to `*.pdf`.

## Requirements

System tools:
- **ffmpeg** (required by `deepfilter_lecture.sh`)
- **DeepFilterNet CLI** (`deepFilter` must be on PATH)

Python:
- **Python 3.8+**
- **reportlab** (`pip install reportlab`)

Upstream transcript generator:
- **Whisper JSON** input (produced by OpenAI Whisper or any tool that outputs the same `segments` format)

## Usage

### 1) Denoise and normalize audio

Process a single file:

```bash
./deepfilter_lecture.sh /path/to/lecture.mp3
```

Process all audio files in a directory (non-recursive):

```bash
./deepfilter_lecture.sh /path/to/lectures/
```

Outputs are written next to the originals as `*_denoised.mp3`.

#### Common knobs (env vars)

```bash
CHUNK_SEC=600 \
USE_CPU=1 \
DF_MODEL=DeepFilterNet3 \
DF_ARGS="--pf -a 12" \
MP3_KBPS=96 \
TARGET_I=-16 \
LRA=11 \
TP=-1.5 \
COMP_THR=-20 \
COMP_RATIO=3 \
COMP_ATTACK=20 \
COMP_RELEASE=250 \
./deepfilter_lecture.sh /path/to/lecture.mp3
```

Notes:
- `USE_CPU=1` forces CPU and avoids GPU/CUDA dependency.
- If speech sounds thin, try `DF_ARGS="-a 6"`.
- If output is still quiet, try `TARGET_I=-14`.

### 2) Convert a single Whisper JSON to PDF

```bash
python whisper_json_to_pdf.py lecture.json \
  -o lecture.pdf \
  --title "ECE 561 Lecture 12" \
  --interval 30
```

### 3) Convert a directory of Whisper JSON files to PDFs

```bash
./whisper_dir_to_pdf.sh /path/to/jsons/
```

Each `file.json` becomes `file.pdf` in the same folder. Titles are derived from the filename.

## Example workflow

1) Clean audio:

```bash
./deepfilter_lecture.sh ./raw_audio/
```

2) Transcribe with Whisper (example):

```bash
whisper ./raw_audio/lecture_denoised.mp3 --model medium --output_format json
```

3) Format the transcript PDF:

```bash
python whisper_json_to_pdf.py lecture_denoised.json -o lecture_denoised.pdf --title "Lecture"
```

## Files

- `deepfilter_lecture.sh` – audio cleanup pipeline
- `whisper_json_to_pdf.py` – Whisper JSON → PDF
- `whisper_dir_to_pdf.sh` – batch JSON → PDF

