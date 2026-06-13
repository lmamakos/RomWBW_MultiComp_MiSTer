10 REM --- isolate: does writing page 4 work after touching a high page?
20 REM step 1: write page 4 with NO high-page involved
30 OUT &HB7, 0 : OUT &HB3, 4 : POKE &HC000, &H11
40 OUT &HB7, 0 : OUT &HB3, 4 : PRINT "A pg4 =";PEEK(&HC000);" (want 17)"
50 REM step 2: now write a high page
60 OUT &HB3, &H2C : OUT &HB7, &H01 : POKE &HC000, &H99
70 OUT &HB3, &H2C : OUT &HB7, &H01
71 PRINT "B pg300=";PEEK(&HC000);" (want 153)"
80 REM step 3: re-read page 4 WITHOUT rewriting it
90 OUT &HB7, 0 : OUT &HB3, 4 : PRINT "C pg4 =";PEEK(&HC000);" (want 17)"
100 REM step 4: rewrite page 4, read again
110 OUT &HB7, 0 : OUT &HB3, 4 : POKE &HC000, &H22
120 OUT &HB7, 0 : OUT &HB3, 4 : PRINT "D pg4 =";PEEK(&HC000);" (want 34)
