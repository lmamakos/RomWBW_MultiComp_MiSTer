all: forth.blk

%.blk : %.fth
	../mkblk.sh $^  > $@ 
	@[ $$(stat -f '%z'  $@) -eq 1024 ] || (echo 2>&1 Output size is not exactly 1K; exit 1)
#	 [ $$(( $$(stat -f '%z'  $@) % 1024 )) -eq 0 ] || (echo 2>&1 Output size is not 1K multiple; exit 1)

LINEEDIT = 05-lineedit.blk 06-lineedit.blk 07-lineedit.blk
EDITOR = 09-editor.blk 10-editor.blk 11-editor.blk 12-editor.blk 13-editor.blk \
   14-editor.blk 15-editor.blk 16-editor.blk 17-editor.blk \
   18-editor.blk 19-editor.blk 20-editor.blk

blks=00-start.blk 01-utils.blk 02-blocks.blk 03-blocks.blk 04-blocks.blk \
     ${LINEEDIT} 08-case.blk  ${EDITOR} 21-see.blk \
	 blank.blk  blank.blk  blank.blk  blank.blk  blank.blk \
	 blank.blk  blank.blk blank.blk \
	30-bench.blk

forth.blk: blank.blk $(blks) Makefile
	cat ${blks} > forth.blk
	( actblk=$$(echo ${blks} | wc -w); \
	  fill=$$(( 128 - $$actblk)) ; \
	  echo Add $$fill empty blocks to initial $$actblk ; \
	  for b in $$(jot $$fill $$actblk) ; do \
		printf "( %03d ) %1016s" $$b "" >> forth.blk ; \
	  done )
	
