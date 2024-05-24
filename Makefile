
EXTRA_SNAPS =
ALL_SNAPS = $(EXTRA_SNAPS) evince firefox gnome-calculator gnome-characters gnome-clocks gnome-font-viewer gnome-logs gnome-system-monitor gnome-text-editor gnome-weather loupe snapd-desktop-integration snap-store ubuntu-core-desktop-init workshops
all: pc.tar.gz

pc.img: ubuntu-core-desktop-22-amd64.model $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap --output-dir img --image-size 20G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv img/pc.img .

pc-dangerous.img: ubuntu-core-desktop-22-amd64-dangerous.model $(EXTRA_SNAPS)
	rm -rf dangerous/
	ubuntu-image snap --output-dir dangerous --image-size 20G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv dangerous/pc.img pc-dangerous.img

pi.img: ubuntu-core-desktop-22-pi.model $(EXTRA_SNAPS)
	rm -rf dangerous/
	ubuntu-image snap --output-dir img --image-size 12G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv img/pi.img pi.img
pi-dangerous.img: ubuntu-core-desktop-22-pi-dangerous.model $(EXTRA_SNAPS)
	rm -rf dangerous/
	ubuntu-image snap --output-dir dangerous --image-size 12G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv dangerous/pi.img pi-dangerous.img

%.tar.gz: %.img
	tar czSf $@ $<

.PHONY: all

clean:
	sudo rm -rf img
	sudo rm -rf image2
	sudo rm -rf output
	sudo rm -f pc.img.xz pc.tar.gz pc-dangerous.img.xz pc-dangerous.tar.gz ubuntu-core-desktop-*-amd64.img ubuntu-core-desktop-*-amd64.img.xz ubuntu-core-desktop-*-amd64.iso
