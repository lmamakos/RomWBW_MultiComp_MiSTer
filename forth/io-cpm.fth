( Low-level I/O words for CP/M Systems to do block I/O )

( FCB definitions - field offsets )
DECIMAL
 0 CONSTANT F$DISK    ( drive 0=default, 1=A, 2=B, etc (1)
 1 CONSTANT F$NAME    ( file name (8 bytes)
   8 CONSTANT F$NAMELEN
 9 CONSTANT F$TYP     ( file type/extension (3 bytes)
   3 CONSTANT F$TYPLEN
12 CONSTANT F$EXTENT  ( extent number (1)
15 CONSTANT F$RECUSED ( records used in this extent (1)
16 CONSTANT F$ABUSED  ( allocation blocks used (16)
( 32 CONSTANT F$SEQREC  ( sequential rec to read/write (1)
33 CONSTANT F$RANREC  ( random rec to read/write (2)
35 CONSTANT F$RANRECO ( random rec overflow byte - most sig (1)
36 CONSTANT F$length  ( total length of FCB )

( BDOS Function code )
15 CONSTANT B$OPEN      ( open file )
( 16 CONSTANT B$CLOSE      close file )
22 CONSTANT B$CREATE    ( create file )
26 CONSTANT B$SETDMA    ( set DMA (I/O transfer address )
33 CONSTANT B$READRAN   ( read random )
( 34 CONSTANT B$WRITERAN   write random )
( 36 CONSTANT B$SETRANREC  set random record number )
40 CONSTANT B$WRITERANZ ( write random with zero-fill )
44 CONSTANT B$SETMSCNT  ( set multi-sector count )


HEX
8000         CONSTANT dmabuf
dmabuf 400 + CONSTANT F$ ;

: init-fcb (  -- )
  F$ F$length 0 FILL ( zero out the whole FCB)
  ( set name and type to all blanks )
  [ F$ F$NAME + ] LITERAL 
    [ F$NAMELEN F$TYPLEN + ] LITERAL
    BL FILL ;

: open-file ( -- )
    init-fcb
     ( 12345678901 exactly 11 characters )
    S" FORTHMONBLK" F$  F$NAME + SWAP CMOVE 
    F$ B$OPEN BDOS IF
      ." open: Creating empty file.."
      F$ B$CREATE BDOS  IF
        ." Can't create blocks file"   ABORT
      THEN
      F$ B$OPEN   BDOS  IF
        ." Can't open new blocks file" ABORT
      THEN
    THEN ;

: file-io ( operation block buffer -- )
    ( buffer ) B$SETDMA BDOS DROP
    8 B$SETMSCNT BDOS IF
      ." Couldn't set multi-sector count"
      ABORT
    THEN
    3 LSHIFT   ( *8 convert from 1024 sized blocks to CP/M 128 byte records)
    0 F$ F$RANRECO + C!     ( store extension )
    ( rec) F$ F$RANREC + !  ( store random record number )
    F$ SWAP BDOS IF
      ." Random I/O failed"
      ABORT
    THEN ;

: read-file ( block buffer )
  B$READRAN ROT ROT file-io ;

: write-file ( block buffer -- )
  B$WRITERANZ ROT ROT file-io ;
