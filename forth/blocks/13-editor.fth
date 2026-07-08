\ SCREEN EDITOR 3A OF 11
: -TRAILING ( addr len -- addr len')
  BEGIN DUP 0 <> WHILE
    2DUP + 1- C@ BL <> IF EXIT THEN 1-
  REPEAT ;

( LIKE <CXY> BUT WORKS FROM 0,0 AND TAKES XY FROM STACK)
: @XY ( Y X --) SWAP .ESC[ DUP 10 / 48 + EMIT 10 MOD 48 + EMIT
     59 EMIT               DUP 10 / 48 + EMIT 10 MOD 48 + EMIT
     72 EMIT ;

: SLINE ( Y -- ) 1 @XY 64 0 DO 45 EMIT LOOP ;
: STAT .GREEN 1 SLINE 18 SLINE 18 5 @XY ."  BLK:" SCR @ .
  18 20 @XY I/R @ IF ."  INSERT " ELSE ."  OVER --" THEN
  18 50 @XY MODIFIED @ IF ."  MODIFIED "
                     ELSE ." ----------" THEN .PLAIN <CXY> ;