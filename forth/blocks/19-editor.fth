\ SCREEN EDITOR 9 OF 11
CREATE KEYVECTORS ]      ( EDIT COMMANDS EXECUTION VECTOR     )
  <SOL>    ( A Start of line    ) LEFT    ( B Cursor Left     )
  CLINE    ( C Copy line        ) DELETE  ( D Delete char     )
  ?EXIT    ( E Exit editor      ) RIGHT   ( F Curosr RIGHT    )
  MODE     ( G Get new mode     ) ----    ( H                 )
  ILINE    ( I Insert line      ) ----    ( J                 )
  KLINE    ( K Kill line        ) -BLK    ( L Last block      )
  NEWLINE  ( M or ENTER, CR+LF  ) DOWN    ( N Cursor Down     )
  OPEN     ( O Open text        ) UP      ( P Up cursor       )
  <HOM>    ( Q Home cursor      ) RESTORE ( R Restore screen  )
  RIGHT    ( S Right cursor     ) TRUNC   ( T Truncate line   )
  UPDATES  ( U Update to buffer ) +BLK    ( V Next block      )
  UP       ( W Up cursor        ) ?CLEAR  ( X Clear buff/scr  )
  PLINE    ( Y Pull line        ) ?EXIT   ( Z Exit          ) [
: KEYDO ( N --) 1- CELLS KEYVECTORS + @ EXECUTE ;