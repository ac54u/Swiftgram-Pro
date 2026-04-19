#!/bin/bash
INPUT_FILE="$1"
FILENAME="${INPUT_FILE%.*}"
EXTENSION="MOV"
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
DURATION=${DURATION%.*}
FILESIZE=$(wc -c <"$INPUT_FILE")
TARGET_SIZE=$((1024 * 1024 * 1800))
if [ "$FILESIZE" -le "$TARGET_SIZE" ]; then exit 0; fi
RATIO=$(echo "scale=4; $TARGET_SIZE / $FILESIZE" | bc)
SEGMENT_TIME=$(echo "scale=0; $DURATION * $RATIO / 1" | bc)
ffmpeg -i "$INPUT_FILE" -c copy -map 0 -ignore_unknown -copy_unknown -f segment -segment_time "$SEGMENT_TIME" -reset_timestamps 1 "${FILENAME}_part_%03d.${EXTENSION}"
