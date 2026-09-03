( 02-blocks ) HEX   4 CONSTANT #BUFF    400 CONSTANT B/BUF 
B/BUF 2 CELLS +  CONSTANT B/REC  \ block has a 4 byte header
VARIABLE FIRST    VARIABLE LIMIT  \ block-buffer pool, set below
VARIABLE PREV               VARIABLE USE
VARIABLE LOWBLK   VARIABLE HIGHBLK   80 HIGHBLK ! 
VARIABLE BHNDL 
: ?BLOCKS   ( -- ) BHNDL @ 0= ABORT" <BLOCK file closed" ;
: MASK  ( n -- n ) 7FFF AND ;
: RBLK  ( adr blk# -- adr) SWAP DUP >R read-file R> ;
: WBLK  ( adr blk# -- )    SWAP write-file ; 
: UPDATE ( -- ) PREV @ @   8000 OR  PREV @ ! ;
: +BUF ( a -- a) B/REC + DUP LIMIT @ = IF DROP FIRST @ THEN ;
HERE FIRST ! FIRST @ B/REC #BUFF * + LIMIT !
FIRST @ DUP PREV ! USE !  B/REC #BUFF * ALLOT

