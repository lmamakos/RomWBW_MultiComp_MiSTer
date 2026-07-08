( 06-lineedit simple line editor blocks loaded ) DECIMAL
: ?BLK    DEPTH 0= ABORT" Block# expected" ;
: ROW   ( l# -- l#') DUP LINE B/L -TRAILING TYPE 1+ ;
: .LINE   ( l# -- l#') DUP 2 .R  ." | " ROW CR ;
: 4LINES  ( l# -- l#') .LINE .LINE .LINE .LINE ;
: 16LINES ( -- )  0 4LINES 4LINES 4LINES 4LINES DROP ;
: (CP)    ( L1 L2 -- ) LINE SWAP LINE SWAP B/L CMOVE ;
: .HEAD   ( n -- )   ." SCR#" 4 .R CR ;
: .NDX ( blk# --) DUP 2 .R [CHAR] : EMIT SCR !  0 .LINE DROP ;

: LIST ( n -- ) PAGE DUP SCR ! .HEAD  16LINES ;
: L    SCR @ LIST  ;
: >>  ( -- )  1 SCR +! L ;
: <<  ( -- )  SCR @ 1- 0 MAX  SCR ! L ;
: P   ( l# -- ) 1 PARSE ROT LINE SWAP CMOVE UPDATE  L ;
