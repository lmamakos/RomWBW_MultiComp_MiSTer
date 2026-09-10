( 21-see  SEE decompiler )  HEX
: CFA>NFA ( cfa -- nfa|0 ) LATEST @ BEGIN DUP WHILE
 2DUP NFA>CFA = IF NIP EXIT THEN NFA>LFA @ REPEAT NIP ;
: .WORD ( cfa -- ) CFA>NFA ?DUP IF COUNT 7F AND TYPE
 ELSE ." ???" THEN SPACE ;
: .Q 22 EMIT ;    \ emit a " (22 hex) character
\ action address in a word's code field, valid only if it
\ begins with a CALL (0CD) instruction
: >ACT ( xt -- adr ) 1+ @ ;
: CALL? ( xt -- f ) C@ 0CD = ;
: DOCOL   ['] CFA>NFA >ACT ; \ docolon action address 
: DOCON   ['] BL >ACT ;      \ docon action address
: DOCREA  ['] UINIT >ACT ;   \ docreate/dovar action address
: ACT? ( xt act -- f ) SWAP DUP
     CALL? IF >ACT = ELSE 2DROP 0 THEN ;
DECIMAL
