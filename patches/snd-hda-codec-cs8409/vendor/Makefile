# Build from this directory:  make   (or sudo make install)
# Do not run only "make -C /lib/modules/$(uname -r)/build M=..." — that skips
# CFLAGS_MODULE below and used to break the tree before patch_cs8409.h defaulted
# APPLE_CODECS. If you must call kbuild by hand, repeat the same CFLAGS_MODULE
# string as in the "all:" recipe.

snd-hda-codec-cs8409-objs :=	patch_cs8409.o patch_cs8409-tables.o
obj-$(CONFIG_SND_HDA_CODEC_CS8409) += snd-hda-codec-cs8409.o

# debug build flags
#KBUILD_EXTRA_CFLAGS = "-DCONFIG_SND_DEBUG=1 -DMYSOUNDDEBUGFULL -DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function"
# normal build flags
KBUILD_EXTRA_CFLAGS = "-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function"

ifdef KVER
KDIR := /lib/modules/$(KVER)
else
KDIR := /lib/modules/$(shell uname -r)
endif

all:
	make -C $(KDIR)/build CFLAGS_MODULE=$(KBUILD_EXTRA_CFLAGS) M=$(shell pwd) modules
clean:
	make -C $(KDIR)/build M=$(shell pwd) clean

install:
	mkdir -p $(KDIR)/updates/
	cp snd-hda-codec-cs8409.ko $(KDIR)/updates/
	depmod -a
