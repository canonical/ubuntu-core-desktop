
EXTRA_SNAPS =
ALL_SNAPS = $(EXTRA_SNAPS) evince firefox gnome-calculator gnome-characters gnome-clocks gnome-font-viewer gnome-logs gnome-system-monitor gnome-text-editor gnome-weather loupe snapd-desktop-integration snap-store ubuntu-core-desktop-init workshops

all: pc.img

bootable: ubuntu-core-desktop-22-amd64.img
bootable-dangerous: ubuntu-core-desktop-22-dangerous-amd64.img

define build_img =
rm -rf img${1}
ubuntu-image snap --output-dir img${1} --image-size ${2}G \
  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
mv img${1}/${3}.img ./$@
endef

pc.img: ubuntu-core-desktop-22-amd64.model $(EXTRA_SNAPS)
	$(call build_img,,20,pc)

pc-dangerous.img: ubuntu-core-desktop-22-amd64-dangerous.model $(EXTRA_SNAPS)
	$(call build_img,-dangerous,20,pc)

pi.img: ubuntu-core-desktop-22-pi.model $(EXTRA_SNAPS)
	$(call build_img,,12,pi)

pi-dangerous.img: ubuntu-core-desktop-22-pi-dangerous.model $(EXTRA_SNAPS)
	$(call build_img,-dangerous,12,pi)

%.img.xz: %.img
	xz -k --force --threads=0 -vv $<

.PHONY: all

define build_bootable_img =
rm -rf output/
cat image/install-sources.yaml.in |sed "s/@FILE@/$</g"|sed "s/@SIZE@/$(shell stat -c%s $<)/g" > image/install-sources.yaml
cat image/core-desktop.yaml.in |sed "s/@FILE@/$</g" | sed "s/@OUTPUT@/$@/g" > image/core-desktop.yaml
sudo ubuntu-image classic --debug -O output/ image/core-desktop.yaml
sudo chown -R $(shell id -u):$(shell id -g) output
mv output/$@ .
endef

ubuntu-core-desktop-22-amd64.img: pc.img.xz image/core-desktop.yaml.in image/install-sources.yaml.in
	$(call build_bootable_img)

ubuntu-core-desktop-22-dangerous-amd64.img: pc-dangerous.img.xz image/core-desktop.yaml.in image/install-sources.yaml.in
	$(call build_bootable_img)

clean:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image/isolinux
	sudo rm -rf dangerous
	sudo rm -rf livecd-rootfs
	sudo rm -f pc*.img.xz pc*.img pc*.tar.gz ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml

clean-bootable:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image/isolinux
	sudo rm -rf dangerous
	sudo rm -f ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml image/core-desktop.yaml
