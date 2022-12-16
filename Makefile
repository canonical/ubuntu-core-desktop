
EXTRA_SNAPS =
ALL_SNAPS = $(EXTRA_SNAPS) firefox gnome-calculator gnome-characters gnome-clocks gnome-font-viewer gnome-weather

all: pc.img.gz

# Patch the official PC gadget snap to use core20-desktop as a base
pc-desktop.snap:
	snap download --channel=20/stable --basename=pc pc
	rm -rf pc-desktop/
	unsquashfs -d pc-desktop pc.snap
	sed -i -e 's/^name:.*$$/name: pc-desktop/' \
	       -e 's/^base:.*$$/base: core22-desktop/' pc-desktop/meta/snap.yaml
	sed -i -e '/role: system-seed/,/size:/ s/size:.*$$/size: 3500M/' \
	       pc-desktop/meta/gadget.yaml
	cat extra-gadget.yaml >> pc-desktop/meta/gadget.yaml
	#cp cloud.conf pc-desktop/cloud.conf
	#cp setup.sh pc-desktop/setup.sh
	snap pack --filename=$@ pc-desktop

pc.img: gdm-spike-model.model pc-desktop.snap $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 8G \
	  --snap pc-desktop.snap $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv img/pc.img .

# Rules to resign assertions: only enable if we have a default signing key
ifneq (,$(findstring default,$(shell snap keys)))
gdm-spike-model.model: gdm-spike-model.json
	snap sign $< > $@
endif

%.img.gz: %.img
	gzip --keep $<

.PHONY: all
