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

\ FIRST and LIMIT mark the start/end of the block-buffer pool.  Rather
\ than hard-coding an absolute address (which would have to be picked
\ by hand for every target, and could silently collide with whatever
\ else is in the dictionary), the pool is allocated dynamically -- out
\ of whatever RAM happens to be free just past the dictionary -- once,
\ near the end of this file (see "allocate the block-buffer pool",
\ below), using the ordinary HERE/ALLOT mechanism.  This works
\ unchanged whether this file is loaded on the embedded (bare-metal)
\ system, on CP/M, or (in the future) on a RomWBW/HBIOS system.
VARIABLE FIRST     ( -- a-addr : start of block-buffer pool )
VARIABLE LIMIT     ( -- a-addr : end of block-buffer pool )

DECIMAL
VARIABLE PREV                     \ set once FIRST is known, below
VARIABLE USE                      \ set once FIRST is known, below
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
: +BUF ( addr1-- addr2) B/REC + DUP LIMIT @ = IF DROP FIRST @ THEN ;

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
  FIRST @
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
  FIRST @ LIMIT @ OVER - 0 FILL
  #BUFF 0
  DO
    7FFF B/REC I * FIRST @ + !   ( store invalid [max] block number? )
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
  FIRST @ CELL+ B/BUF BL FILL
  DUP HIGHBLK !
  1+  1
  DO
      FIRST @ CELL+ I WBLK
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

\ allocate the block-buffer pool -- now that every word that refers to
\ FIRST/LIMIT (+BUF, BUFFER, BLOCK, FLUSH, EMPTY-BUFFERS, MAKE-BLOCKS)
\ has already been defined above, HERE points just past all of this
\ file's dictionary growth, so the pool can never collide with it.
HERE FIRST !
FIRST @ B/REC #BUFF * + LIMIT !
FIRST @ DUP PREV ! USE !
B/REC #BUFF * ALLOT

EMPTY-BUFFERS

