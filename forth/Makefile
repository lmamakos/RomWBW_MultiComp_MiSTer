CPMDISK=../z80pack/cpmsim/disks/drivei.dsk
CPMFORMAT=z80pack-hd
CPMDEST=4:

MULTICOMPDEST=5:
MULTICOMPDISK=../z80pack/cpmsim/disks/drivei.dsk
MULTICOMPFORMAT=z80pack-hd

all:	camel80.bin camel80cpm.com

camel80.bin: camel80.azm camel80d.azm camel80h.azm cameltst.azm io-multi.azm
	um80 camel80.azm -D BOOTABLE=1 -g -o camel80.rel -l camel80.prn
	ul80 -p 0 --sym  -x -o camel80.hex camel80.rel && rm camel80.rel
	objcopy -I ihex -O binary camel80.hex camel80.bin && rm camel80.hex

# CP/M variant: same camel80.azm kernel, assembled with -D CPM so it
# INCLUDEs io-cpm.azm (BDOS file I/O) instead of io-multi.azm (embedded
# Z80 Multicomputer ROM words). Output is a flat binary with ORG 100h
# baked in by the source (CP/M's TPA entry point) -- i.e. it can be copied
# directly onto a CP/M disk image as CAMEL80.COM with no on-CP/M assembly
# step required.
camel80cpm.com: camel80.azm camel80d.azm camel80h.azm io-cpm.azm
	um80 camel80.azm -D CPM=1 -g -o camel80cpm.rel -l camel80cpm.prn
	ul80 -p 0 --sym  -x -o camel80cpm.hex camel80cpm.rel && rm camel80cpm.rel
	objcopy -I ihex -O binary camel80cpm.hex camel80cpm.com && rm camel80cpm.hex

clean:
	rm -f  *.prn *.lst *.rel *.sym camel80.bin camel80cpm.com
	rm -f  *~

all:
	cd blocks; make

install:	camel80.bin
	scp camel80.bin       mister:/media/fat/games/MultiComp/camel80.bin
	scp blocks/forth.blk  mister:/media/fat/games/MultiComp/forth.blk

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

cpminstall: blocks/forth.blk
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
