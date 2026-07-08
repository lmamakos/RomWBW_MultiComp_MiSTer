( 22 SEE word part 2 )
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
