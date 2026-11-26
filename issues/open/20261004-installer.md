# Ubuntu core desktop needs a proper bootable installer

## Impact / Priority

Users must download a raw .img file and dd it to a drive, and there is
no user-friendly path for installing to a device like a laptop's
internal drive — a user who wanted to install on a laptop would have to
boot some kind of Linux USB drive, download the image, and dd it to the
laptop's internal drive. The majority of users are not going to go
through that hassle, so most cannot install Ubuntu Core Desktop at all.

Impact derived from the original note's symptoms.

The current Ubuntu core desktop install process is to download a drive
.img file and then use dd to write it to a drive. This is A poor user
experience for the average user.  Most importantly, there is no
user-friendly path for installing to a device like a laptop instead of
a USB drive (ubuntu core was designed for OEMs who pre-create a model
for their device, create an image, and then use their internal
production tooling to write the image to the device drive). Today, A
user who wanted to install on a laptop would have to boot some kind of
Linux USB drive and then download the image and then DD it to the
laptop internal drive. The majority of users are not going to go
through that hassle.

## goal

The user should have a simple, easy to use and reliable process for
installing Ubuntu Core Desktop.

- When installing the user should get an up-to-date system.

- The current install process for Ubuntu Core consists of a multi-boot
  process. On first boot, The root partition is created filling the
  drive and it is seeded using snaps from the seed partition. Ideally
  we would Just do a single install to the drive and everything would
  be ready. There would be no need for the second seed and reboot.
  However, this is the way Ubuntu Core was designed and it does verify
  on every device that a factory reset will work and restore it to its
  default setup. So if it's going to be too much work or too difficult
  to change this, then we can live with it.
  DECISION: live with it. This design is fundamental to how snapd
  manages recovery modes, full-disk encryption, and factory resets.

- Users are used to a process where they take some ISO image and write
  it to a USB drive using this software of choice, whether that is DD
  or something else, and then take that USB drive and boot it on their
  target install system. This process has the advantage that by
  publishing some kind of standard format images, it doesn't matter
  whether the user has Windows or an Apple or Linux because there are
  existing software to write ISO images to drives for all of these
  systems. Much of this software will also write raw images too. So we
  can use this flow if we want to.

  One consideration is that many users will want to install a laptop
  where they can't remove the physical drive. So we need to support an
  installer that boots on the device and then writes to the physical
  drive of that device. But some tool that allows users to create and
  pre-configure an Ubuntu Core desktop image. For example, a cli tool
  that Enables adding a user, setting up timezones, configuring
  accessibility, and anything else that is configurable, would be
  useful. It would also be useful for us in our development because
  our existing build.sh does a lot of these things by manipulating
  stuff.

## ideal install process for laptop

- user boots USB drive

- user installs to laptop internal drive

- laptop reboots once

## ideal install process for external USB drive

- user configures image settings from some cli/desktop tool
- tool creates/configures/writes image to selected USB drive

## questions

1. is the Regular ubuntu desktop installer A suitable base to be
   modified for ubuntu core desktop? The process it does is quite
   different - It repartitions a drive and then installs Debian
   packages onto it and then mounts the drive and creates a user and
   sets up things like the locale and timezone and debian repositories
   to install from. I suspect that modifying this might be quite
   challenging, and it would require maintaining two separate paths in
   the installer at different points which it might not have been ever
   designed to do.
   - no, the legacy installer (which provisions partitions, extracts
     .deb packages, and chroots to set up users) is not designed to do
     this.

2. Should we use Subiquity or something else?
   DECISION - yes because Subiquity already works with ubuntu core.

3. Does Ubuntu Core have anything that does what we want?
   - ubuntu-image allows you to build an image And pre-configure some
     properties (we already use this to build images).
   - ubuntu-core-desktop-installer was the path used for the
     legacy/prototype ubuntu-core-desktop.

4. Some new desktop installers For other distributions are presenting
   HTTP and HTML to the user. So basically what happens is The user
   can boot from a USB drive but then they can use their phone or
   another laptop to connect to the website of the installer and drive
   it from there. Is that something that would be useful for us?

5. https://github.com/canonical/ubuntu-core-desktop-installer exists
   but has not been updated in three years. Is it any use to us?
   MAYBE - this needs review. ubuntu-core-desktop-installer uses
   Subiquity as its backend. It handles the complex task of taking a
   live environment and provisioning Ubuntu Core's strict,
   multi-partition layout (ubuntu-seed, ubuntu-boot, ubuntu-save,
   ubuntu-data) onto a target internal drive.

## next steps

- review ubuntu-core-desktop-installer and make a recommendation on
  whether this is the right thing for us. What do we need to do to fit
  this into our existing process? If this is not the right thing, then
  what should we do? We can write something from scratch, or we can
  adopt something that other people have used.
