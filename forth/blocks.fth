\
\  This file is manually split into multipe 16 line screens to be built
\  into the disk image file that's generated.  These are all within the
\  the blocks directory 
\
( based on https://github.com/bfox9900/CAMEL99-ITC/blob/master/LIB.ITC/BLOCKS.FTH)
CR .( blocks.fth )
HERE
\ 34567890123456789012345678901234567890123456789012345678901234

HEX
4   CONSTANT #BUFF ( # of active buffers)
400 CONSTANT B/BUF
B/BUF 2 CELLS +  CONSTANT B/REC  \ block has a 4 byte header

( start blocks at 3FFF and work down XXX )
\ 9FFF 1-  CONSTANT LIMIT  ( end of buffer memory)
\ LIMIT B/REC #BUFF * - CONSTANT FIRST \ first buffer address
8000 CONSTANT FIRST  ( start at 8000h and work upwards )
FIRST B/REC #BUFF * + CONSTANT LIMIT

DECIMAL
VARIABLE PREV      FIRST  PREV !
VARIABLE USE       FIRST  USE  !
VARIABLE LOWBLK                   \ presumably 0
VARIABLE HIGHBLK    78 HIGHBLK !  \ default value blocks on disk
VARIABLE BHNDL                    \ block file handle

\ ===================================================
\ interface to CP/M File system
HEX
( check for block file open )
: ?BLOCKS   ( -- ) BHNDL @ 0= ABORT" <BLOCK file closed" ;
( check for error writing block )
\ : ?BLKERR   ( ? -- ) ?DUP IF BHNDL OFF  ?FILERR  THEN ;
: MASK  ( n -- n ) 7FFF AND ;
: RBLK  ( adr blk# -- adr) SWAP DUP >R read-file R> ;
: WBLK  ( adr blk# -- )    SWAP write-file ; 
\ ===================================================
: UPDATE ( -- ) PREV @ @   8000 OR  PREV @ ! ;
: +BUF ( addr1-- addr2) B/REC + DUP LIMIT = IF DROP FIRST THEN ;

: BUFFER ( n -- addr )
  USE @ DUP >R       \ get current buffer record & Rpush
  @ 0<               \ has it been updated?
  IF                 \ if true ...
    R@ CELL+        \ get buffer address
    R@ @            \ get the block number
    MASK  WBLK      \ write data to disk
  THEN R@ !          \ store this in USE record
  R@ PREV !          \ set it as previous record
  R@ +BUF USE !      \ "use" next buffer
  R> CELL+ ;         \ return the buffer address

: BLOCK   ( block# --- addr )
  ?BLOCKS
  >R
  PREV @ DUP @  R@ - MASK
  IF
    BEGIN
      +BUF DUP PREV @ =
      IF
        DROP R@ BUFFER  R@ RBLK 2 - \ CELL-
      THEN
      DUP @ R@ -  MASK
    WHILE REPEAT
    DUP PREV !
    DUP USE @ =
    IF
      DUP +BUF USE !
    THEN
  THEN
  R> DROP CELL+ ;

: FLUSH ( -- )
  ?BLOCKS
  FIRST
  #BUFF 0
  DO
    DUP @ 0<     \ is block updated?
    IF          \ yes, write to disk
      DUP @ MASK  OVER 2DUP !
      CELL+ SWAP WBLK
    THEN +BUF   \ then goto next block record
  LOOP
  DROP ;

( initialize/zap all the buffers )
: EMPTY-BUFFERS ( -- )
  FIRST LIMIT OVER - 0 FILL
  #BUFF 0
  DO
    7FFF B/REC I * FIRST + !   ( store invalid [max] block number? )
  LOOP ;

: OPEN-BLOCKS ( file$ len -- )
  2DROP
  EMPTY-BUFFERS
  open-file
  FCB$ BHNDL ! ; \ just put something in there

HEX
: CLOSE-BLOCKS ( -- )
  ?BLOCKS FLUSH
  ( BHNDL @ CLOSE-FILE ?FILERR )
  BHNDL OFF ;

\ Usage:  45 S" DSK1.MYBLOCKS" MAKE-BLOCKS
: MAKE-BLOCKS ( n file len -- )
  2DROP ( n -- )
  open-file  ( will create if not present )
  FCB$ BHNDL !
  FIRST CELL+ B/BUF BL FILL
  DUP HIGHBLK !
  1+  1
  DO
      FIRST CELL+ I WBLK
  LOOP
  CLOSE-BLOCKS ;

DECIMAL
\ added LOAD so we can compile code from BLOCKS
   VARIABLE SCR
64 CONSTANT B/L
: LINE ( n -- addr) B/L *  SCR @ BLOCK  + ;
: LOAD ( n -- )
  SCR !
  16 0 DO
     I LINES ! ( keep track of line number )
     I LINE B/L EVALUATE
  LOOP ;

: -->   ( n -- ) SCR @ 1+ LOAD ;

HERE SWAP - DECIMAL  CR .  .( bytes)
EMPTY-BUFFERS

