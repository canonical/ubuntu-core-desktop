# Contributing to Ubuntu Core Desktop

Thank you for contributing to Ubuntu Core Desktop, an experimental project exploring a modular desktop built on Ubuntu Core. Contributions to image integration, testing, automation, and documentation are welcome.

This repository assembles the image from independently maintained snaps. **If you only want to try Ubuntu Core Desktop**, see the [README](README.md) for the prebuilt image and VM instructions. **To build from source**, follow the [building guide](docs/building.md).

> **Development preview:** The images use a **dangerous** model and unasserted local snaps. They are not suitable for production or security-sensitive deployment and cannot receive normal Snap Store refreshes.

## Before You Start

Check existing issues and pull requests before beginning substantial work. For changes involving multiple repositories, coordinate the dependent changes and link their pull requests.

### Where to Contribute

- **This repository:** image assembly (`build.sh`), models, CI automation, and documentation for the assembled image.
- **Component repositories:** base, gadget, snapd, GNOME session, runtime, audio, and first-boot provisioning snaps. Follow the relevant component repository's contribution process. The [building guide](docs/building.md#clone-the-repositories) lists the current source repositories and branches.

## Build and Test

For prerequisites, commands, model signing, and QEMU instructions, see **[Build Ubuntu Core Desktop from source](docs/building.md)**.

Select tests according to the change:

| Change | Expected validation |
| --- | --- |
| Shell scripts | Run `bash -n build.sh` (and `bash -n build-cloud-init.sh` if changed) |
| Model, image assembly, or integration | Build an image with `build.sh`; check relevant CI and component tests |
| First-boot or graphical behaviour | Boot the image in QEMU and test the affected behaviour |
| Documentation only | Check links, commands, and Markdown for accuracy |

When reporting testing, distinguish **syntax checks**, **successful image assembly**, **boot to the welcome-language screen**, and **completed account setup with a working graphical session**. Do not claim a stage you did not test. The [building guide](docs/building.md#test-the-image-in-qemu) describes the QEMU configuration and current validation limits.

## Contribution Guidelines

- Keep changes focused and explain the problem they solve and their impact.
- Update documentation when build inputs, models, VM requirements, or first-boot behaviour change.
- Do not commit generated disk images, snaps, passwords, SSH private keys, private signing keys, or personal account-key assertions. Check `git status` before submitting.
- Include exact test commands, observed results, and any limitations or failures.
- For changes spanning multiple repositories, describe dependencies and link related pull requests.

## Pull Requests

1. Fork the repository and create a topic branch from the relevant branch (`desktop/26` for current image work).
2. Make your changes and run the relevant checks in the [building guide](docs/building.md).
3. Open a pull request describing the motivation, changes, affected components, tests, and known limitations.
4. Address review feedback and keep the pull request focused.

This repository checks the **Canonical Contributor License Agreement (CLA)** on pull requests. Contributions must pass the CLA check before merging. See the [Canonical contributor agreement](https://ubuntu.com/legal/contributors).

## Security Issues

Do not report security-sensitive vulnerabilities in public issues. Follow [Canonical's vulnerability disclosure guidance](https://canonical.com/security/vulnerability-disclosure).
