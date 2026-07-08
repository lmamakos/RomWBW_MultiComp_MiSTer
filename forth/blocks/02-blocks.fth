( 02-blocks ) HEX   4 CONSTANT #BUFF    400 CONSTANT B/BUF 
B/BUF 2 CELLS +  CONSTANT B/REC  \ block has a 4 byte header
8000 CONSTANT FIRST  FIRST B/REC #BUFF * + CONSTANT LIMIT
VARIABLE PREV   FIRST  PREV !   VARIABLE USE   FIRST  USE  !
VARIABLE LOWBLK   VARIABLE HIGHBLK   80 HIGHBLK ! 
VARIABLE BHNDL 
: ?BLOCKS   ( -- ) BHNDL @ 0= ABORT" <BLOCK file closed" ;
: MASK  ( n -- n ) 7FFF AND ;
: RBLK  ( adr blk# -- adr) SWAP DUP >R read-file R> ;
: WBLK  ( adr blk# -- )    SWAP write-file ; 
: UPDATE ( -- ) PREV @ @   8000 OR  PREV @ ! ;
: +BUF ( addr1-- addr2) B/REC + DUP LIMIT = IF DROP FIRST THEN ;



