SNAP_SIGN_KEY ?= test
MODEL_ACCOUNT_KEY ?= /home/copilot/copilot-test.account-key

.PHONY: FORCE
FORCE:

all: pc.tar.gz

auto-import.assert: system-user.json
	snap sign system-user.json --chain > auto-import.assert

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

core26.img: ubuntu-core-26-amd64-dangerous.model auto-import.assert
	rm -rf dangerous/
	ubuntu-image snap -v --validation=ignore \
	  --assertion auto-import.assert \
	  --output-dir dangerous \
	  --image-size 20G \
	  $<
	mv dangerous/pc.img core26.img

pc-dangerous.img: ubuntu-core-desktop-24-amd64-dangerous.model $(MODEL_ACCOUNT_KEY)
      #	pc-desktop_26.assert
	rm -rf dangerous/
	ubuntu-image snap -v --validation=ignore \
	  --assertion $(MODEL_ACCOUNT_KEY) \
	  --output-dir dangerous \
	  --image-size 20G \
	  --assertion auto-import.assert \
	  --snap custom-core24-desktop_36.snap \
	  --snap custom-pc-desktop_26.snap \
	  --snap snapd_2.66.1+git3159.gdc0543f_amd64.snap \
	  $<
	mv dangerous/pc.img pc-dangerous.img

#	  --snap ubuntu-desktop-session_20260909+git_all.snap \
#	  --snap custom-pc-desktop_24-0.1_amd64.snap \
#	  --snap custom-pc-desktop_26.snap \
#	  --snap core26-desktop_20260908_amd64.snap \
#	  --snap core26_20260909_amd64.snap \
#	  --snap pc-desktop_24-0.1_amd64.snap \
#	  --snap snapd_2.66.1+git3159.gdc0543f_amd64.snap \
#	  --assertion auto-import.assert

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
	sudo rm -f pc*.img.xz pc*.img pc*.tar.gz ubuntu-core-desktop-*.img ubuntu-core-desktop-*.img.xz ubuntu-core-desktop-*.iso image/install-sources.yaml
