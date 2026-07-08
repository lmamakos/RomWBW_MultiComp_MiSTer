#!/bin/sh
# magic invocation of dd to construct "block" files for Forth.  It
# is both quick and dirty and not very forgiving in its present form.
# 
# ideally, it would be wrapped in script to run on one file at a time
#

for f in $* 
do 
  dd < $f 2>/dev/null \
    obs=1024 cbs=64 ibs=64 count=16 \
    conv=block,noerror,sync,notrunc,osync fillchar=\   
done

