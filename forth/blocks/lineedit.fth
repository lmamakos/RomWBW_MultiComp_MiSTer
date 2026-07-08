\ Line editor Short commands

\ L  ( -- )  Re-list currect block
\ >>  ( -- )  List next block
\ <<  ( -- )  List previous block
\ P   ( l# -- <text>) Put <text> into line# ( 5 P This goes to line 5 )
\ DL  ( l# -- ) Delete line#
\ CP  ( l1 l2 -- ) Copy line1 to line2
\ M   ( l1 l2 -- ) Move line1 to line2. erase line1
\ O   ( <dsk?.path ) Open a block file
\ RO  ( -- )  RE-open a block file that has aborted
\ EB  ( blk# -- ) erase block

\ Line editor Word Commands

\ LIST ( n -- ) list block n
\ UNDO   empty all buffers and reload current block
\ EACH  ( blk1 blk2 XT ) Apply XT to each block in the range
\ INDEX ( blk1 blk2) show top line of blocks in the range given
\ LOAD  ( blk --) Load the given block
\ THRU  ( blk1 blk2) LOAD the blocks in the given range
\ CLEANTHRU ( blk1 blk2) Erase the blocks in the given range
\ COPY  ( src dst -- ) copy src block to dst block
\ PASTE  Accept 16 lines of text into the current block
\ HELP   Show the short commands block

DECIMAL   ( VT100/ANSI cursor control )
\ type un-signed number, base 10, with no space and restore previous radix
: <ARG>   ( n -- ) BASE @ >R   0 <# DECIMAL #S #> TYPE   R> BASE ! ;
\ markup language for terminal control codes
: <ESC>[  ( -- )   27 EMIT  91 EMIT  ;
: <UP>    ( n -- ) <ESC>[ <ARG> ." A" ;
: <DOWN>  ( n -- ) <ESC>[ <ARG> ." B" ;
: <RIGHT> ( n -- ) <ESC>[ <ARG> ." C" ;
: <BACK>  ( n -- ) <ESC>[ <ARG> ." D" ;
: <HOME>  ( -- )   <ESC>[ ." 0;0H" ;
: <CLS>   ( n -- ) <ESC>[ ." 2J" ;
: <CLRLN> ( -- )   <ESC>[ ." K" ;
\ redefine Forth words using markup words
: AT-XY   ( col row --)  <ESC>[ <ARG> ." ;" <ARG> ." f" ;
: PAGE ( -- ) <CLS>  <HOME> ;
CR .( PAGE, AT-XY set for VT100)


( simple line editor, assumes blocks loaded )            DECIMAL
: ?BLK    DEPTH 0= ABORT" Block# expected" ;
: ROW   ( l# -- l#') DUP LINE B/L -TRAILING TYPE 1+ ;
: .LINE   ( l# -- l#') DUP 2 .R  ." | " ROW CR ;
: 4LINES  ( l# -- l#') .LINE .LINE .LINE .LINE ;
: 16LINES ( -- )  0 4LINES 4LINES 4LINES 4LINES DROP ;
: (CP)    ( L1 L2 -- ) LINE SWAP LINE SWAP B/L CMOVE ;
: .HEAD   ( n -- )   ." SCR#" 4 .R CR ;
: .NDX    ( blk# --)  BLOCK CR  0 .LINE ;

\ editor commands
\ : USE ( <path> )  BL PARSE-WORD  OPEN-BLOCKS ;
: LIST ( n -- ) PAGE DUP SCR ! .HEAD  16LINES ;
: L    SCR @ LIST  ;
: >>  ( -- )  1 SCR +! L ;
: <<  ( -- )  SCR @ 1- 0 MAX  SCR ! L ;
: P   ( l# -- ) 1 PARSE ROT LINE SWAP CMOVE UPDATE  L ;

\ : ED  ( l# )
\  CR VROW 2@  DUP .LINE
\  AT-XY DUP LINE B/L ACCEPT DROP
\  UPDATE ;

: DL  ( l# -- ) LINE B/L BLANK UPDATE L ;
: CP  ( L1 L2 -- ) (CP) UPDATE  L ;
: MV  ( L1 L2 -- ) OVER >R (CP) R> DL ;
\ : O   ( <TEXT> )  PARSE-NAME OPEN-BLOCKS ;
: EB  ( blk --) ?BLK  BLOCK B/BUF BLANK UPDATE ;
: UNDO ( -- ) EMPTY-BUFFERS L ;

\ Higher order function maps function onto each line
: EACH ( n1 n2 XT --) ( MAP xt to range of blocks )
      ROT ROT 1+ SWAP
      2DUP > IF
        DO
          I OVER EXECUTE
          KEY? ABORT" Map halted"
        LOOP
      ELSE 2DROP
      THEN
      DROP ;

: INDEX     ( n1 n2 --)  ['] .NDX EACH ;
: THRU      ( n1 n2 --)  ['] LOAD EACH ;
: CLEANTHRU ( n1 n2 --)  ['] EB   EACH ;

\ COPY PASTE HELP

: COPY   ( src dst -- ) FLUSH  SWAP  BLOCK 2- !  UPDATE ;

: PASTE  ( -- ) \ for pasting text into a block
      16 0
      DO
         I LINE B/L ACCEPT UPDATE
      LOOP
      FLUSH ;

: HELP   1 LIST ;