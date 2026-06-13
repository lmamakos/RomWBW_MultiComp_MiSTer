10 REM === Full-range SDRAM soak (pages 4..2047, full 32MB region) ===
20 REM Cumulative error tally across all passes. Ctrl-C to stop.
30 N = 0 : S = 0
40 TE = 0 : REM total errors across all passes
50 REM ---- begin pass ----
60 N = N + 1
70 REM --- write phase ---
80 FOR P = 4 TO 2047
90   PL = P AND &HFF : PH = INT(P / 256)
100  OUT &HB3, PL : OUT &HB7, PH
110  POKE &HC000, (P + S) AND &HFF
120  POKE &HC001, (P * 3 + S + &H5A) AND &HFF
130  POKE &HC002, (P * 7 + S + &HA5) AND &HFF
140  POKE &HC003, (P XOR S) AND &HFF
150 NEXT P
160 REM --- read/verify phase ---
170 E = 0
180 FOR P = 4 TO 2047
190  PL = P AND &HFF : PH = INT(P / 256)
200  OUT &HB3, PL : OUT &HB7, PH
210  IF PEEK(&HC000) <> ((P + S) AND &HFF) THEN E = E + 1
220  IF PEEK(&HC001) <> ((P * 3 + S + &H5A) AND &HFF) THEN E = E + 1
230  IF PEEK(&HC002) <> ((P * 7 + S + &HA5) AND &HFF) THEN E = E + 1
240  IF PEEK(&HC003) <> ((P XOR S) AND &HFF) THEN E = E + 1
250 NEXT P
260 TE = TE + E
270 PRINT "pass";N;" seed";S;" err";E;" TOTAL";TE;" (8176 bytes/pass)"
280 S = (S + 23) AND &HFF
290 GOTO 50
