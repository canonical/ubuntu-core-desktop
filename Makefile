
EXTRA_SNAPS =
ALL_SNAPS = $(EXTRA_SNAPS) eog evince firefox gnome-calculator gnome-characters gnome-clocks gnome-font-viewer gnome-logs gnome-text-editor gnome-weather

all: pc.tar.gz

pc.img: ubuntu-core-desktop-22-amd64.model $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 12G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv img/pc.img .

pc-dangerous.img: ubuntu-core-desktop-22-amd64-dangerous.model $(EXTRA_SNAPS)
	rm -rf dangerous/
	ubuntu-image snap --output-dir dangerous --image-size 12G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv dangerous/pc.img pc-dangerous.img

%.tar.gz: %.img
	tar czSf $@ $<

.PHONY: all
