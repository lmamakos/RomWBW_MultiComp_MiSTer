10 REM write a marker high in device 1, wait, read back
20 P = 6000 : OUT &HB3, P AND &HFF : OUT &HB7, INT(P/256)
30 POKE &HC000, &HC3 : POKE &HC001, &H3C
40 PRINT "written. waiting..."
50 FOR T = 1 TO 20000 : NEXT T
60 OUT &HB3, P AND &HFF : OUT &HB7, INT(P/256)
70 PRINT "dev1 pg6000:";PEEK(&HC000);PEEK(&HC001);" (want 195 60)"
