100 OUT &HB3, &H2C : OUT &HB7, &H01 : REM page 300 (high byte set)
110 OUT &HB3, 5                     : REM low-byte-only write
120 REM frame3 should now be page 5, NOT page 0x0105=261
130 POKE &HC000, &H77
140 OUT &HB3, 5 : OUT &HB7, 0       : REM explicit page 5
150 PRINT "pg5: ";PEEK(&HC000);" (want 119)"
