
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

ubuntu-core-desktop-22-amd64.img: pc.img
	rm -rf output/
	cat image/install-sources.yaml.in |sed "s/@FILE@/$</g"|sed "s/@SIZE@/$(shell stat -c%s $<)/g" > image/install-sources.yaml
#	rm -f image/installer-data.tar.bz2
#	rm -rf livecd-rootfs
#	git clone --branch ubuntu/master --single-branch git://git.launchpad.net/livecd-rootfs
#	tar cjvf image/installer-data.tar.bz2 -C livecd-rootfs/live-build/ubuntu-server/includes.chroot.ubuntu-server-minimal.ubuntu-server.installer .
	sudo ubuntu-image classic --debug -O output/ image/core-desktop.yaml
	sudo chown -R $(shell id -u):$(shell id -g) output
	mv output/ubuntu-core-desktop-22-amd64.img .


clean:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image/isolinux
	sudo rm -rf dangerous
	sudo rm -rf livecd-rootfs
	sudo rm -f pc*.img.xz pc*.img pc*.tar.gz ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml

clean_bootable:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image/isolinux
	sudo rm -rf dangerous
	sudo rm -f ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml
