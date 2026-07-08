( 23 SEE word, part 3 )
: (SEE) ( a -- a' ) CR 3 SPACES .ADR DUP @
   DUP ['] lit = IF DROP CELL+ DUP @ . CELL+ EXIT THEN
   DUP ['] (S") = IF DROP CELL+ [CHAR] S EMIT .Q SPACE COUNT
      2DUP TYPE + .Q SPACE EXIT THEN
      DUP BRAN? IF .WORD CELL+ DUP @ . CELL+ EXIT THEN
      .WORD CELL+ ;
: SEE-COLON ( xt -- ) CR ." : " DUP .WORD  DUP >BODY SWAP
  CFA>NFA NFA-END CELL - ( a end' )  BEGIN OVER OVER U<
  WHILE SWAP (SEE) SWAP REPEAT 2DROP CR ." ;" CR ;
( dump each cell of a CREATEd word's body, a..end )
: SEE-CREATE ( xt -- )
   ." CREATE " DUP .WORD  DUP >BODY SWAP CFA>NFA NFA-END
   ( a end )  BEGIN OVER OVER U< WHILE
      CR 3 SPACES OVER U. ." : " OVER @ . SWAP CELL+ SWAP
   REPEAT  2DROP CR ;
