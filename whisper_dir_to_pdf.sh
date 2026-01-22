#!/usr/bin/env bash
set -euo pipefail

# Directory containing Whisper JSON files
INPUT_DIR="${1:-.}"

# Path to the Python formatter script
SCRIPT_PATH="./whisper_json_to_pdf.py"

# Timestamp interval in seconds
INTERVAL=30

# Check script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Error: $SCRIPT_PATH not found"
  exit 1
fi

shopt -s nullglob

for json in "$INPUT_DIR"/*.json; do
  base="$(basename "$json" .json)"

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
  echo "  JSON : $json"
  echo "  PDF  : $pdf"
  echo "  Title: $title"

  python "$SCRIPT_PATH" "$json" \
    -o "$pdf" \
    --title "$title" \
    --interval "$INTERVAL"

  echo
done

echo "Done."

