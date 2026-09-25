SNAP_SIGN_KEY ?= test
MODEL_ACCOUNT_KEY ?= /home/copilot/copilot-test.account-key

.PHONY: FORCE
FORCE:

all: 26.tar.gz

pc-desktop_26.assert:
	tmpdir=$$(mktemp -d); \
	snap download pc-desktop --revision=26 --target-directory "$$tmpdir" >/dev/null; \
	mv "$$tmpdir/pc-desktop_26.assert" "$@"; \
	rm -rf "$$tmpdir"

%.model: %.json FORCE
	snap sign -k $(SNAP_SIGN_KEY) --update-timestamp $< > $@

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

%.tar.gz: %.img
	tar czSf $@ $<

.PHONY: all

clean:
	sudo rm -rf img
	sudo rm -rf output
	sudo rm -rf image
	sudo rm -f pc*.img.xz pc*.img pc*.tar.gz ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml 26.img.nouser
