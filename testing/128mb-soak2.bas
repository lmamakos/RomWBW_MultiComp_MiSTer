10 REM === 128MB SDRAM soak (pages 4..8191, device boundary at 4096) ===
20 N = 0 : S = 0 : TE = 0
30 REM ---- begin pass ----
40 N = N + 1
50 FOR P = 4 TO 8191
60   PL = P AND &HFF : PH = INT(P / 256)
70   OUT &HB3, PL : OUT &HB7, PH
80   POKE &HC000, (P + S) AND &HFF
90   POKE &HC001, (P * 3 + S + &H5A) AND &HFF
100  POKE &HC002, (P * 3 + S + &HA5) AND &HFF
110  POKE &HC003, (P XOR S) AND &HFF
120 NEXT P
130 E = 0
140 FOR P = 4 TO 8191
150  PL = P AND &HFF : PH = INT(P / 256)
160  OUT &HB3, PL : OUT &HB7, PH
170  IF PEEK(&HC000) <> ((P + S) AND &HFF) THEN E = E + 1
180  IF PEEK(&HC001) <> ((P * 3 + S + &H5A) AND &HFF) THEN E = E + 1
190  IF PEEK(&HC002) <> ((P * 3 + S + &HA5) AND &HFF) THEN E = E + 1
200  IF PEEK(&HC003) <> ((P XOR S) AND &HFF) THEN E = E + 1
210 NEXT P
220 TE = TE + E
230 PRINT "pass";N;" seed";S;" err";E;" TOTAL";TE;" (32752 bytes/pass)"
240 S = (S + 23) AND &HFF
250 GOTO 30
