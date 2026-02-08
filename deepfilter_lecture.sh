#!/usr/bin/env bash
set -euo pipefail

# deepfilter_lecture.sh
#
# Works on EITHER:
#   - a single audio file, OR
#   - a directory of audio files (non-recursive)
#
# For each input file it:
#   1) Converts to 48kHz mono WAV
#   2) Chunks (default 10 min) to avoid OOM
#   3) DeepFilterNet denoise per chunk (CPU by default)
#   4) Re-concatenates
#   5) Compressor + loudnorm to make quiet speaker louder/clearer
#   6) Outputs MP3 next to original with _denoised suffix
#
# Usage:
#   ./deepfilter_lecture.sh "/path/to/file.mp3"
#   ./deepfilter_lecture.sh "/path/to/directory"
#
# Env knobs:
#   CHUNK_SEC=600                 # chunk length in seconds
#   USE_CPU=1                     # 1 forces CPU (recommended), 0 allows GPU
#   DF_MODEL="DeepFilterNet3"     # or "DeepFilterNet2"
#   DF_ARGS="--pf -a 12"          # denoise knobs (try "-a 6" if speech sounds thin)
#   MP3_KBPS=96                   # mp3 bitrate (speech: 64-128)
#   TARGET_I=-16                  # loudnorm integrated loudness (try -14 if still quiet)
#   LRA=11                        # loudness range (higher = less squashed)
#   TP=-1.5                       # true peak ceiling
#   COMP_THR=-20                  # compressor threshold (dB)
#   COMP_RATIO=3                  # compressor ratio
#   COMP_ATTACK=20                # ms
#   COMP_RELEASE=250              # ms
#   KEEP_TMP=0                    # keep temp dirs for debugging

command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg not found"; exit 1; }
command -v deepFilter >/dev/null 2>&1 || { echo "Error: deepFilter not found"; exit 1; }

INPUT="${1:-.}"

CHUNK_SEC="${CHUNK_SEC:-600}"
USE_CPU="${USE_CPU:-2}"
DF_MODEL="${DF_MODEL:-DeepFilterNet3}"
DF_ARGS="${DF_ARGS:-}"
MP3_KBPS="${MP3_KBPS:-96}"

TARGET_I="${TARGET_I:--12}"
LRA="${LRA:-11}"
TP="${TP:--1.5}"

COMP_THR="${COMP_THR:--20}"
COMP_RATIO="${COMP_RATIO:-3}"
COMP_ATTACK="${COMP_ATTACK:-20}"
COMP_RELEASE="${COMP_RELEASE:-250}"

KEEP_TMP="${KEEP_TMP:-0}"

FILES=()
DIR=""

if [[ -f "$INPUT" ]]; then
  FILES=("$INPUT")
  DIR="$(dirname "$INPUT")"
elif [[ -d "$INPUT" ]]; then
  DIR="$INPUT"
  shopt -s nullglob
  FILES=(
    "$DIR"/*.mp3 "$DIR"/*.MP3
    "$DIR"/*.wav "$DIR"/*.WAV
    "$DIR"/*.m4a "$DIR"/*.M4A
    "$DIR"/*.flac "$DIR"/*.FLAC
    "$DIR"/*.aac "$DIR"/*.AAC
    "$DIR"/*.ogg "$DIR"/*.OGG
  )
else
  echo "Error: not a file or directory: $INPUT"
  exit 1
fi

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "No audio files found."
  exit 0
fi

echo "==> Input: $INPUT"
echo "==> Files: ${#FILES[@]}"
echo "==> Chunk seconds: $CHUNK_SEC"
echo "==> DeepFilter model: $DF_MODEL"
echo "==> DeepFilter args: ${DF_ARGS:-<none>}"
echo "==> Loudness: I=$TARGET_I, LRA=$LRA, TP=$TP"
echo "==> Compressor: thr=$COMP_THR dB, ratio=$COMP_RATIO, attack=$COMP_ATTACK ms, release=$COMP_RELEASE ms"
echo "==> Output: *_denoised.mp3 (${MP3_KBPS} kbps)"
echo

for IN in "${FILES[@]}"; do
  bn="$(basename "$IN")"
  stem="${bn%.*}"
  OUT="${DIR}/${stem}_denoised.mp3"

  if [[ -f "$OUT" ]]; then
    echo "Skipping (exists): $OUT"
    continue
  fi

  echo "------------------------------------------------------------"
  echo "Processing: $IN"
  echo "Output:     $OUT"

  TMPDIR="$(mktemp -d -t dflecture.XXXXXX)"
  WAV_IN="${TMPDIR}/input_48k_mono.wav"
  CHUNK_DIR="${TMPDIR}/chunks"
  CLEAN_DIR="${TMPDIR}/clean"
  LIST_TXT="${TMPDIR}/concat_list.txt"
  WAV_DENOISED="${TMPDIR}/denoised.wav"
  WAV_PROCESSED="${TMPDIR}/processed.wav"

  mkdir -p "$CHUNK_DIR" "$CLEAN_DIR"

  # 1) Convert to 48kHz mono PCM WAV
  ffmpeg -hide_banner -loglevel error -y \
    -i "$IN" \
    -ac 1 -ar 48000 -c:a pcm_s16le \
    "$WAV_IN"

  # 2) Split into chunks to avoid RAM spikes
  ffmpeg -hide_banner -loglevel error -y \
    -i "$WAV_IN" \
    -f segment -segment_time "$CHUNK_SEC" -reset_timestamps 1 \
    -c copy \
    "${CHUNK_DIR}/part_%05d.wav"

  # 3) Denoise each chunk
  if [[ "$USE_CPU" == "1" ]]; then
    export CUDA_VISIBLE_DEVICES=""
  fi

  mapfile -t CHUNKS < <(ls -1 "${CHUNK_DIR}"/part_*.wav 2>/dev/null | sort)
  if [[ "${#CHUNKS[@]}" -eq 0 ]]; then
    echo "Error: no chunks produced for $IN"
    [[ "$KEEP_TMP" == "1" ]] || rm -rf "$TMPDIR"
    continue
  fi

  i=0
  for f in "${CHUNKS[@]}"; do
    i=$((i+1))
    c_bn="$(basename "$f")"
    printf "  [DF %d/%d] %s\n" "$i" "${#CHUNKS[@]}" "$c_bn"

    # --no-suffix keeps outputs predictable. If unsupported in your deepFilter build,
    # remove --no-suffix; the concat step includes a fallback glob.
    deepFilter -m "$DF_MODEL" $DF_ARGS --no-suffix \
      "$f" -o "$CLEAN_DIR" >/dev/null
  done

  # 4) Concatenate cleaned chunks
  : > "$LIST_TXT"
  for f in "${CHUNKS[@]}"; do
    c_bn="$(basename "$f")"
    cleaned="${CLEAN_DIR}/${c_bn}"

    if [[ ! -f "$cleaned" ]]; then
      # Fallback: if deepFilter appends a suffix, grab newest matching
      stem2="${c_bn%.wav}"
      alt="$(ls -1t "${CLEAN_DIR}/${stem2}"*.wav 2>/dev/null | head -n 1 || true)"
      if [[ -n "$alt" && -f "$alt" ]]; then
        cleaned="$alt"
      else
        echo "Error: cleaned chunk missing for $c_bn"
        [[ "$KEEP_TMP" == "1" ]] || rm -rf "$TMPDIR"
        continue 2
      fi
    fi

    printf "file '%s'\n" "$cleaned" >> "$LIST_TXT"
  done

  ffmpeg -hide_banner -loglevel error -y \
    -f concat -safe 0 -i "$LIST_TXT" \
    -c copy \
    "$WAV_DENOISED"

  # 5) Make quiet speaker louder:
  #    compressor boosts quieter speech + loudnorm sets overall comfortable loudness
  ffmpeg -hide_banner -loglevel error -y \
    -i "$WAV_DENOISED" \
    -af "acompressor=threshold=${COMP_THR}dB:ratio=${COMP_RATIO}:attack=${COMP_ATTACK}:release=${COMP_RELEASE},loudnorm=I=${TARGET_I}:LRA=${LRA}:TP=${TP}" \
    "$WAV_PROCESSED"

  # 6) Encode MP3
  ffmpeg -hide_banner -loglevel error -y \
    -i "$WAV_PROCESSED" \
    -c:a libmp3lame -b:a "${MP3_KBPS}k" -ar 48000 -ac 1 \
    "$OUT"

  echo "Done: $OUT"

  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMPDIR"
  else
    echo "Temp kept: $TMPDIR"
  fi
done

echo
echo "All done."

