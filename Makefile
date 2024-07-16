
EXTRA_SNAPS =
ALL_SNAPS = $(EXTRA_SNAPS) firefox
all: bootable-iso

bootable-iso: ubuntu-core-desktop-24-amd64.iso
bootable-iso-dangerous: ubuntu-core-desktop-24-dangerous-amd64.iso

define build_img =
rm -rf img${1}
ubuntu-image snap --output-dir img${1} --image-size ${2}G \
  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
mv img${1}/${3}.img ./$@
endef

pc.img: ubuntu-core-desktop-24-amd64.model $(EXTRA_SNAPS)
	$(call build_img,,20,pc)

pc-dangerous.img: ubuntu-core-desktop-24-amd64-dangerous.model $(EXTRA_SNAPS)
	$(call build_img,-dangerous,20,pc)

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

%.img.xz: %.img
	xz -k --force --threads=0 -vv $<

.PHONY: all

define build_bootable_img =
rm -rf output/
mkdir -p image
cat image_data/install-sources.yaml.in |sed "s/@FILE@/$</g"|sed "s/@SIZE@/$(shell stat -c%s $<)/g" > image/install-sources.yaml
cat image_data/core-desktop.yaml.in |sed "s/@FILE@/$</g" | sed "s/@OUTPUT@/$@/g" > image/core-desktop.yaml
sudo ubuntu-image classic --debug -O output/ image/core-desktop.yaml
sudo chown -R $(shell id -u):$(shell id -g) output
mv output/$@ .
endef

ubuntu-core-desktop-24-amd64.img: pc.img.xz image_data/core-desktop.yaml.in image_data/install-sources.yaml.in
	$(call build_bootable_img)

ubuntu-core-desktop-24-dangerous-amd64.img: pc-dangerous.img.xz image_data/core-desktop.yaml.in image_data/install-sources.yaml.in
	$(call build_bootable_img)

ubuntu-core-desktop-24-%.iso: ubuntu-core-desktop-24-%.img
	./create_iso.sh $<

clean:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image
	sudo rm -rf image2
	sudo rm -rf img-dangerous
	sudo rm -rf livecd-rootfs
	sudo rm -f pc*.img.xz pc*.img pc*.tar.gz ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml

clean-bootable:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image
	sudo rm -rf image2
	sudo rm -rf img-dangerous
	sudo rm -f ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml image/core-desktop.yaml
