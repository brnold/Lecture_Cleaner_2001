#!/usr/bin/env bash
set -euo pipefail

# Directory containing MP3 files
INPUT_DIR="${1:-.}"

# Path to the Python formatter script
SCRIPT_PATH="./whisper_json_to_pdf.py"

# Whisper CLI command and model
WHISPER_BIN="${WHISPER_BIN:-whisper}"
WHISPER_MODEL="${WHISPER_MODEL:-medium}"
WHISPER_ARGS="${WHISPER_ARGS:-}"

# Timestamp interval in seconds
INTERVAL=30

# Check script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Error: $SCRIPT_PATH not found"
  exit 1
fi

shopt -s nullglob

found=0
for mp3 in "$INPUT_DIR"/*.mp3; do
  found=1
  base="$(basename "$mp3" .mp3)"
  json="$INPUT_DIR/$base.json"

  # Generate output PDF path
  pdf="$INPUT_DIR/$base.pdf"

  # Create a readable title from filename:
  #  - underscores → spaces
  #  - dashes → spaces
  #  - capitalize words
  title="$(echo "$base" \
    | sed 's/[_-]/ /g' \
    | sed 's/\b\(.\)/\u\1/g')"

  echo "Processing:"
  echo "  MP3  : $mp3"
  echo "  JSON : $json"
  echo "  PDF  : $pdf"
  echo "  Title: $title"

  if [[ ! -f "$json" ]]; then
    "$WHISPER_BIN" "$mp3" \
      --model "$WHISPER_MODEL" \
      --output_format json \
      --output_dir "$INPUT_DIR" \
      $WHISPER_ARGS
  fi

  python "$SCRIPT_PATH" "$json" \
    -o "$pdf" \
    --title "$title" \
    --interval "$INTERVAL"

  echo
done

if [[ $found -eq 0 ]]; then
  echo "No .mp3 files found in $INPUT_DIR"
fi

echo "Done."
