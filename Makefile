
BASE_SNAP = core20-gdm.snap
SESSION_SNAP = confined-desktop.snap

all: pc.img.xz assertions.img.xz

# Patch the official PC gadget snap to use core20-gdm as a base
pc-gdm.snap:
	snap download --channel=20/stable --basename=pc pc
	rm -rf pc-gdm/
	unsquashfs -d pc-gdm pc.snap
	sed -i -e 's/^name:.*$$/name: pc-gdm/' \
	       -e 's/^base:.*$$/base: core20-gdm/' pc-gdm/meta/snap.yaml
	snap pack --filename=$@ pc-gdm

pc.img: gdm-spike-model.model $(BASE_SNAP) $(SESSION_SNAP) pc-gdm.snap
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 4G \
	  --snap pc-gdm.snap --snap $(BASE_SNAP) --snap $(SESSION_SNAP) $<
	mv img/pc.img .

# Build assertions image
assertions.img: auto-import.assert
	dd if=/dev/zero of=$@ bs=1024 count=160
	mkfs.vfat $@
	mcopy -i $@ $^ ::

# Rules to resign assertions
auto-import.assert: ubuntu-user.json
	if snap keys | grep -q default; then \
	  snap sign $< > $@ \
	fi

gdm-spike-model.model: gdm-spike-model.json
	if snap keys | grep -q default; then \
	  snap sign $< > $@ \
	fi

%.img.xz: %.img
	xz --keep $<

.PHONY: all
