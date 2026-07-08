( 21-see  SEE decompiler )  HEX
: CFA>NFA ( cfa -- nfa|0 ) LATEST @ BEGIN DUP WHILE
   2DUP NFA>CFA = IF NIP EXIT THEN NFA>LFA @ REPEAT NIP ;
: .WORD ( cfa -- ) CFA>NFA ?DUP IF COUNT 7F AND TYPE
   ELSE ." ???" THEN SPACE ;
: .Q [CHAR] " EMIT ;
( action address in a word's code field, valid only if it )
( begins with a CALL (0CD) instruction )
: >ACT ( xt -- adr ) 1+ @ ;
: CALL? ( xt -- f ) C@ 0CD = ;
: DOCOL   ['] CFA>NFA >ACT ;    ( docolon action address )
: DOCON   ['] BL >ACT ;         ( docon action address )
: DOCREA  ['] UINIT >ACT ;      ( docreate/dovar action address )
: ACT? ( xt act -- f ) SWAP DUP CALL? IF >ACT = ELSE 2DROP 0 THEN ;
: COLON? ( xt -- f ) DOCOL  ACT? ;
: CON?   ( xt -- f ) DOCON  ACT? ;
: CREA?  ( xt -- f ) DOCREA ACT? ;
: BRAN? ( xt -- f ) DUP ['] branch = OVER ['] ?branch = OR
   OVER ['] (loop) = OR SWAP ['] (+loop) = OR ;
( address just past nfa's definition = start of next header, )
( or HERE if nfa is the most recent word )
: NFA-END ( nfa -- addr )  >R  LATEST @
   BEGIN ( w ) DUP WHILE
      DUP NFA>LFA @  R@ = IF NFA>LFA R> DROP EXIT THEN
      NFA>LFA @  REPEAT
   DROP R> DROP HERE ;
VARIABLE SEE-ADR   ( nonzero -> show cell addresses )
: .ADR ( a -- a ) SEE-ADR @ IF DUP U. ." : " THEN ;
: (SEE) ( a -- a' ) CR 3 SPACES .ADR DUP @
   DUP ['] lit = IF DROP CELL+ DUP @ . CELL+ EXIT THEN
   DUP ['] (S") = IF DROP CELL+ [CHAR] S EMIT .Q SPACE COUNT
      2DUP TYPE + .Q SPACE EXIT THEN
   DUP BRAN? IF .WORD CELL+ DUP @ . CELL+ EXIT THEN .WORD CELL+ ;
: SEE-COLON ( xt -- )
   CR ." : " DUP .WORD  DUP >BODY SWAP CFA>NFA NFA-END CELL -
   ( a end' )  BEGIN OVER OVER U< WHILE SWAP (SEE) SWAP REPEAT
   2DROP CR ." ;" CR ;
( dump each cell of a CREATEd word's body, a..end )
: SEE-CREATE ( xt -- )
   ." CREATE " DUP .WORD  DUP >BODY SWAP CFA>NFA NFA-END
   ( a end )  BEGIN OVER OVER U< WHILE
      CR 3 SPACES OVER U. ." : " OVER @ . SWAP CELL+ SWAP
   REPEAT  2DROP CR ;
: (DOSEE) ( xt -- )
   DUP CON?   IF ." CONSTANT " DUP .WORD ." = " >BODY @ . CR EXIT THEN
   DUP CREA?  IF SEE-CREATE EXIT THEN
   DUP COLON? IF SEE-COLON EXIT THEN
   ." CODE " .WORD CR ;
: SEE  ( "name" -- )   0 SEE-ADR !   '  (DOSEE) ;
: SEEA ( "name" -- )   1 SEE-ADR !   '  (DOSEE) ;
