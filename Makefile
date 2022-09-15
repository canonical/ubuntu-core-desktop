
EXTRA_SNAPS = core22-desktop.snap ubuntu-desktop-session.snap
ALL_SNAPS = $(EXTRA_SNAPS)

all: pc.img.gz assertions.img.gz

# Patch the official PC gadget snap to use core20-desktop as a base
pc-desktop.snap:
	snap download --channel=20/stable --basename=pc pc
	rm -rf pc-desktop/
	unsquashfs -d pc-desktop pc.snap
	sed -i -e 's/^name:.*$$/name: pc-desktop/' \
	       -e 's/^base:.*$$/base: core22-desktop/' pc-desktop/meta/snap.yaml
	sed -i -e '/role: system-seed/,/size:/ s/size:.*$$/size: 2500M/' \
	       pc-desktop/meta/gadget.yaml
	cat extra-gadget.yaml >> pc-desktop/meta/gadget.yaml
	cp cloud.conf pc-desktop/cloud.conf
	cp setup.sh pc-desktop/setup.sh
	snap pack --filename=$@ pc-desktop

pc.img: gdm-spike-model.model pc-desktop.snap $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 8G \
	  --snap pc-desktop.snap $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
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

%.img.gz: %.img
	gzip --keep $<

.PHONY: all
