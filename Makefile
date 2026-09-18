SNAP_SIGN_KEY ?= test
MODEL_ACCOUNT_KEY ?= /home/copilot/copilot-test.account-key

.PHONY: FORCE
FORCE:

all: pc.tar.gz

pc-desktop_26.assert:
	tmpdir=$$(mktemp -d); \
	snap download pc-desktop --revision=26 --target-directory "$$tmpdir" >/dev/null; \
	mv "$$tmpdir/pc-desktop_26.assert" "$@"; \
	rm -rf "$$tmpdir"

%.model: %.json FORCE
	snap sign -k $(SNAP_SIGN_KEY) --update-timestamp $< > $@

pc.img: ubuntu-core-desktop-24-amd64.model $(EXTRA_SNAPS)
	rm -rf img/
	ubuntu-image snap -v --validation=enforce --output-dir img --image-size 20G \
	$(foreach s,$(SNAPS),--snap $(s)) $<
	mv img/pc.img .

core26.img: ubuntu-core-26-amd64-dangerous.model
	rm -rf dangerous/
	ubuntu-image snap -v --validation=ignore \
	  --output-dir dangerous \
	  --image-size 20G \
	  $<
	mv dangerous/pc.img core26.img


24.img: ubuntu-core-desktop-24-amd64-dangerous.model $(MODEL_ACCOUNT_KEY) FORCE
	rm -rf 24/
	ubuntu-image snap -v \
	  --assertion $(MODEL_ACCOUNT_KEY) \
	  --validation=ignore \
	  --output-dir 24 \
	  --image-size 20G \
	  --snap custom-core.snap \
	  --snap gadget.snap \
	  --snap snapd_2.66.1+git3159.gdc0543f_amd64.snap \
	  --snap ubuntu-desktop-session.snap \
	  $<
	mv 24/pc.img $@

# test is seeded at run time by go-cloud-init's NoCloud seed.iso
# (attached by go-run-desktop26), not by any assertion baked into the
# image. NOUSER=1 just drops a 26.img.nouser marker next to the image;
# go-run-desktop26 checks for it and skips attaching seed.iso, so the
# image has no existing user at first boot and ubuntu-desktop-init's
# first-boot wizard runs instead (see go-build-desktop26 --nouser).
26.img: ubuntu-core-desktop-26-amd64-dangerous.model $(MODEL_ACCOUNT_KEY) FORCE
	rm -rf 26/
	ubuntu-image snap -v \
	  --assertion $(MODEL_ACCOUNT_KEY) \
	  --validation=ignore \
	  --output-dir 26 \
	  --image-size 20G \
	  --snap custom-core.snap \
	  --snap gadget.snap \
	  --snap snapd26.snap \
	  --snap ubuntu-desktop-session.snap \
	  --snap ubuntu-desktop-init.snap \
	  $<
	mv 26/pc.img $@
	$(if $(NOUSER),touch 26.img.nouser,rm -f 26.img.nouser)

pi.img: ubuntu-core-desktop-22-pi.model $(EXTRA_SNAPS)
	rm -rf dangerous/
	ubuntu-image snap -v --validation=enforce --output-dir img --image-size 12G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv img/pi.img pi.img
pi-dangerous.img: ubuntu-core-desktop-22-pi-dangerous.model $(EXTRA_SNAPS)
	rm -rf dangerous/
	ubuntu-image snap -v --validation=ignore --output-dir dangerous --image-size 12G \
	  $(foreach snap,$(ALL_SNAPS),--snap $(snap)) $<
	mv dangerous/pi.img pi-dangerous.img

%.tar.gz: %.img
	tar czSf $@ $<

.PHONY: all

clean:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image
	sudo rm -f pc*.img.xz pc*.img pc*.tar.gz ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml 26.img.nouser
