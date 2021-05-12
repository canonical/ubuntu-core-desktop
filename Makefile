
EXTRA_SNAPS = core20-gdm.snap ubuntu-desktop-session.snap

all: pc.img.xz assertions.img.xz

# Patch the official PC gadget snap to use core20-gdm as a base
pc-gdm.snap:
	snap download --channel=20/stable --basename=pc pc
	rm -rf pc-gdm/
	unsquashfs -d pc-gdm pc.snap
	sed -i -e 's/^name:.*$$/name: pc-gdm/' \
	       -e 's/^base:.*$$/base: core20-gdm/' pc-gdm/meta/snap.yaml
	cat extra-gadget.yaml >> pc-gdm/meta/gadget.yaml
	cp cloud.conf pc-gdm/cloud.conf
	cp setup.sh pc-gdm/setup.sh
	snap pack --filename=$@ pc-gdm

pc.img: gdm-spike-model.model pc-gdm.snap $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 4G \
	  --snap pc-gdm.snap $(foreach snap,$(EXTRA_SNAPS),--snap $(snap)) $<
	mv img/pc.img .

# Build assertions image
assertions.img: auto-import.assert
	dd if=/dev/zero of=$@ bs=1024 count=160
	mkfs.vfat $@
	mcopy -i $@ $^ ::

# Rules to resign assertions: only enable if we have a default signing key
ifneq (,$(findstring default,$(shell snap keys)))
auto-import.assert: ubuntu-user.json
	snap sign $< > $@

gdm-spike-model.model: gdm-spike-model.json
	snap sign $< > $@
endif

%.img.xz: %.img
	xz --keep -T0 $<

.PHONY: all
