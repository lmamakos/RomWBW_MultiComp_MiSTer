( 24 SEE word )
: (DOSEE) ( xt -- )
  DUP CON?   IF
    ." CONSTANT " DUP .WORD ." = " >BODY @ . CR
      EXIT THEN
  DUP CREA?  IF SEE-CREATE EXIT THEN
  DUP COLON? IF SEE-COLON EXIT THEN
  ." CODE " .WORD CR ;
: SEE  ( "name" -- )   0 SEE-ADR !   '  (DOSEE) ;
: SEEA ( "name" -- )   1 SEE-ADR !   '  (DOSEE) ;
