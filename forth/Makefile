CPMDISK=../z80pack/cpmsim/disks/drivei.dsk
CPMFORMAT=z80pack-hd
CPMDEST=4:

MULTICOMPDEST=5:
MULTICOMPDISK=../z80pack/cpmsim/disks/drivei.dsk
MULTICOMPFORMAT=z80pack-hd

camel80.bin: camel80.azm camel80d.azm camel80h.azm cameltst.azm io-multi.azm
	um80 camel80.azm -g -l camel80.prn
	ul80 -p 0 --sym  -x -o camel80.hex camel80.rel && rm camel80.rel
	objcopy -I ihex -O binary camel80.hex camel80.bin && rm camel80.hex

clean:
	rm -f  *.prn *.lst *.rel camel80.bin
	rm -f  *~

all:
	cd blocks; make

cpm: blocks/forth.blk
	@echo make sure to remove all the *.AZM and *.SUB files from the CP/M disk image
	cpmcp -t -f ${CPMFORMAT}  ${CPMDISK}  camel80.azm    ${CPMDEST}camel80.azm
	cpmcp -t -f ${CPMFORMAT}  ${CPMDISK}  camel80d.azm   ${CPMDEST}camel80d.azm
	cpmcp -t -f ${CPMFORMAT}  ${CPMDISK}  camel80h.azm   ${CPMDEST}camel80h.azm	
	cpmcp -t -f ${CPMFORMAT}  ${CPMDISK}  camel80cfg.azm ${CPMDEST}camelcfg.azm
	cpmcp -t -f ${CPMFORMAT}  ${CPMDISK}  io-cpm.azm     ${CPMDEST}io-cpm.azm
	cpmcp -t -f ${CPMFORMAT}  ${CPMDISK}  build.sub      ${CPMDEST}build.sub
	cpmcp    -f ${CPMFORMAT}  ${CPMDISK}  blocks/forth.blk   ${CPMDEST}forth.blk
	@echo "Now ^C in CP/M to login disk and then build"

install: blocks/forth.blk
	cpmcp    -f ${CPMFORMAT}  ${CPMDISK}  blocks/forth.blk   ${CPMDEST}forth.blk

fetchcpm:
	cpmcp -f ${CPMFORMAT}  ${CPMDISK}  ${CPMDEST}camel80.com zout/camel80.com
	cp blocks/forth.blk zout/

embedded:
	@echo make sure to remove all the *.AZM and *.SUB files from the CP/M disk image
	cpmcp -t -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  camel80.azm    ${MULTICOMPDEST}camel80.azm
	cpmcp -t -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  camel80d.azm   ${MULTICOMPDEST}camel80d.azm
	cpmcp -t -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  camel80h-embedded.azm   ${MULTICOMPDEST}camel80h.azm	
	cpmcp    -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  blocks/forthmon.blk   ${MULTICOMPDEST}forthmon.blk
	cpmcp -t -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  camel80cfg-embedded.azm ${MULTICOMPDEST}camelcfg.azm
	cpmcp -t -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  build-embedded.sub      ${MULTICOMPDEST}build.sub
	cpmcp    -f ${MULTICOMPFORMAT}  ${MULTICOMPDISK}  support/m80.com support/l80.com   ${MULTICOMPDEST}forthmon.blk
	@echo "Now ^C in CP/M to login disk and then build"

blocks/forth.blk: blocks
	cd blocks; make

%.blk: %.f
	./mkblk.sh $<   > $@ 

%.blk: %.fth
	./mkblk.sh $<   > $@ 
