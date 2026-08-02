( L0                                                           )
HEX 47 CONSTANT fpleds
: delay 200 0 DO I I DROP DROP LOOP ;
: counter 100 0 DO I fpleds PC! delay LOOP ;
DECIMAL
: times ( xt n -- )  0 DO DUP EXECUTE LOOP DROP ;
: 5count ['] counter 5 times ;
( L7                                                           )
( L8                                                           )
( L9                                                           )
( L10                                                          )
( L11                                                          )
( L12                                                          )
( L13                                                          )
( L14                                                          )
