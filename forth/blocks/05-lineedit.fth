( 05-lineedit ) DECIMAL   ( VT100/ANSI cursor control )
: <ARG> ( n -- ) BASE @ >R  0 <# DECIMAL #S #> TYPE  R> BASE ! ;
: <ESC>[  ( -- )   27 EMIT  91 EMIT  ;
: <UP>    <ESC>[ <ARG> ." A" ;    : <DOWN> <ESC>[ <ARG> ." B" ;
: <RIGHT>  <ESC>[ <ARG> ." C" ;   : <BACK>  <ESC>[ <ARG> ." D" ;
: <HOME>  <ESC>[ ." 0;0H" ;       : <CLS>  <ESC>[ ." 2J" ;
: <CLRLN> <ESC>[ ." K" ;          : PAGE <CLS>  <HOME> ;
: AT-XY   ( col row --)  <ESC>[ <ARG> ." ;" <ARG> ." f" ;







