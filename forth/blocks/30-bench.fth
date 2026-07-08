( 30-bench ) ( 8 queens benchmark )
0 VARIABLE solutions 0 VARIABLE nodes
: bits ( n -- mask ) 1 SWAP LSHIFT 1- ;
: lowBit  ( mask -- bit ) DUP NEGATE AND ;
: lowBit- ( mask -- bits ) DUP 1- AND ;
: next3 ( dl dr f files -- dl dr f dl' dr' f' )
  0= >R 2 PICK R@ AND 2* 1+  2 PICK R@ AND 2/   2 PICK R> AND ;
: try ( dl dr f -- ) DUP IF 
   1 nodes +! DUP 2OVER AND AND BEGIN ?DUP WHILE
     DUP >R lowBit next3 RECURSE R> lowBit- REPEAT
  ELSE 1 solutions +! THEN  DROP 2DROP ;
: queens ( n -- ) 0 solutions ! 0 nodes !
  -1 -1 ROT BITS try
    solutions @ . ." solutions, " nodes @ . ." nodes" ;
  
