10 REM SDRAM soak w/ diagnostics: re-read on error, show exp vs obs
20 N = 0 : S = 0
30 REM ---- begin pass ----
40 N = N + 1
50 FOR P = 16 TO 255
60 OUT &HB3, P
70 POKE &HC000, (P + S) AND &HFF
80 POKE &HC001, (P * 2 + S) AND &HFF
90 POKE &HC002, (P * 3 + S + &H55) AND &HFF
100 POKE &HC003, (P + S + &HAA) AND &HFF
110 NEXT P
120 E = 0
130 FOR P = 16 TO 255
140 OUT &HB3, P
150 A = &HC000 : X = (P + S) AND &HFF : GOSUB 1000
160 A = &HC001 : X = (P * 2 + S) AND &HFF : GOSUB 1000
170 A = &HC002 : X = (P * 3 + S + &H55) AND &HFF : GOSUB 1000
180 A = &HC003 : X = (P + S + &HAA) AND &HFF : GOSUB 1000
190 NEXT P
200 PRINT "pass";N;" seed";S;" errors";E;" (960 bytes/pass)"
210 S = (S + 17) AND &HFF
220 GOTO 30
230 REM
1000 REM --- check byte: P=page A=addr X=expected ---
1010 V = PEEK(A)
1020 IF V = X THEN RETURN
1030 E = E + 1
1040 R1 = PEEK(A) : R2 = PEEK(A) : R3 = PEEK(A)
1050 PRINT "ERR pg";P;" addr ";HEX$(A);" exp ";HEX$(X);" got ";HEX$(V);
1060 PRINT " retry ";HEX$(R1);" ";HEX$(R2);" ";HEX$(R3);
1070 IF R1=X AND R2=X AND R3=X THEN PRINT " [FLAKY-READ]" : RETURN
1080 IF R1=V AND R2=V AND R3=V THEN PRINT " [STABLE-WRONG]" : RETURN
1090 PRINT " [UNSTABLE]"
1100 RETURN
