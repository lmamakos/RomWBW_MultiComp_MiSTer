#!/bin/sh
# Convert FORTH source file(s) into fixed-size "block" (screen) files.
#
# Each block is exactly 16 lines x 64 columns = 1024 bytes.  Every input
# line is space-padded (or truncated) to 64 bytes; if the file has fewer
# than 16 lines the remainder is filled with blank (all-space) lines.
# There are no newline separators in the output - it is a flat 1024-byte
# image, matching what the FORTH block layer expects.
#
# Implemented with awk for portability between BSD/macOS and Linux (the
# older BSD-only `dd conv=block ... osync fillchar=` invocation would not
# run under GNU dd).

for f in "$@"
do
  awk '
    BEGIN { cols = 64; rows = 16; blank = sprintf("%*s", cols, "") }
    {
      line = $0
      # pad or truncate this line to exactly 64 columns
      if (length(line) < cols)      line = line sprintf("%*s", cols - length(line), "")
      else if (length(line) > cols) line = substr(line, 1, cols)
      printf "%s", line
      n++
    }
    END {
      # pad out to a full 16-line screen with blank lines
      for (; n < rows; n++) printf "%s", blank
    }
  ' "$f"
done
