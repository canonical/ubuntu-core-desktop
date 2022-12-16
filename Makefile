
EXTRA_SNAPS =
ALL_SNAPS = $(EXTRA_SNAPS) firefox gnome-calculator gnome-characters gnome-clocks gnome-font-viewer gnome-weather

all: pc.img.gz

pc.img: gdm-spike-model.model $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 8G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv img/pc.img .

# Rules to resign assertions: only enable if we have a default signing key
ifneq (,$(findstring default,$(shell snap keys)))
gdm-spike-model.model: gdm-spike-model.json
	snap sign $< > $@
endif

%.img.gz: %.img
	gzip --keep $<

.PHONY: all
