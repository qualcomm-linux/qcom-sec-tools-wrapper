# qcom-sec-tools-wrapper

Qualcomm `sectools` wrapper scripts for OEM key generation, image
signing, VIP table creation, fuse-blower generation, capsule assembly
and on-device flashing, driven from a single `Makefile` front-end.

## Quick start (Makefile)

A `Makefile` wraps the scripts behind a few targets, with all paths and
parameters kept in a local `.env` file so they only need to be set once.

```bash
# 1. Create a local config and edit it for your setup
$ make config
$ $EDITOR .env

# 2. Fetch sectools (and qdl, unless QCOM_VIP_DISABLE is set)
$ make deps

# 3. Generate keys (writes ./OEM-KEYS)
$ make generate-keys

# 4. Sign a build, and/or create the fuse-blower image
$ make sign-build
$ make gen-fuse-blower

# 5. Flash the signed build (with VIP table) to a connected device
$ make flash
```

`make sign-build` copies `QCOM_FLAT_BUILD` into `QCOM_SIGNED_BUILD`
(default `./signed-build`, leaving the originals untouched), signs the
images there, and then (unless `QCOM_VIP_DISABLE` is set) generates a
VIP (Validated Image Programming) table of digests under
`QCOM_SIGNED_BUILD/vip-tables` and signs it too, all in one step.

`make flash` then flashes `QCOM_SIGNED_BUILD` to a connected device
with `qdl`, passing the signed VIP table (`--vip-table-path`) and the
target storage type (`QCOM_STORAGE`, default `ufs`).

Run `make help` to list all targets. The `.env` keys are documented in
[`.env.sample`](.env.sample); the most important are:

| Variable | Used by | Meaning |
|---|---|---|
| `QCOM_SEC_PROFILE` | sign-build, gen-fuse-blower | path to the platform `*_security_profile.xml` |
| `QCOM_ROT_KEYS` | sign-build, gen-fuse-blower | OEM signing keys dir (default `OEM-KEYS`) |
| `QCOM_FLAT_BUILD` | sign-build | directory of images to sign |
| `QCOM_SIGNED_BUILD` | sign-build, flash | output folder for signed images and VIP tables |
| `QCOM_FMP_KEY_PASSWORD` | generate-keys | password for the FMP keys |
| `QCOM_SECTOOLS` | sectools targets | explicit sectools path; leave empty to auto-fetch |
| `QCOM_QDL` | sign-build (VIP), flash | explicit qdl binary; leave empty to clone + build |
| `QCOM_STORAGE` | flash | target storage type (`emmc`/`nand`/`nvme`/`spinor`/`ufs`) |
| `QCOM_FUSE_OEM_HW_ID`, `QCOM_FUSE_OEM_PRODUCT_ID`, `QCOM_FUSE_SEC_KEY_DERIVATION_KEY` | gen-fuse-blower | fuse parameters |

## Requirements

### External pieces (provided per-platform)

* [Qualcomm Security Tools (sectools)](https://softwarecenter.qualcomm.com/catalog/item/Qualcomm_Security_Tools) --
  fetched automatically into `./.sectools/<version>/` by `make deps`
  (or set `QCOM_SECTOOLS` to an existing binary to skip the download).
* [Hardware boot binaries (tech package)](https://softwarecenter.qualcomm.com/nexus/generic/product/chip/tech-package/) --
  the per-SoC boot artefacts the platform image build depends on.
* **Hardware security profile** -- the platform-specific
  `*_security_profile.xml` (for example `kodiak_security_profile.xml`)
  that ships with the Qualcomm platform SDK and declares the IMAGE-IDs,
  HW versions and signing parameters used by sectools.  Point
  `QCOM_SEC_PROFILE` at it.
* **Image files** -- the flat build directory produced by your image
  build (typically the Yocto `deploy/images/<machine>.qcomflash/`
  folder) containing the `.mbn`, `.elf`, `rawprogram*.xml`,
  `patch*.xml`, `prog_firehose_*.elf` and partition `.bin`/`.img`
  files.  Point `QCOM_FLAT_BUILD` at it.

### Host tooling

* `openssl` >= 1.1.1
* `hexdump`
* `dtc`
* `python3` >= 3.10
* `udisksctl` (udisks2)
* `sbsign` (only for UEFI secure boot)
* `unzip` plus `curl` or `wget` (only when `make deps` downloads sectools)
* `git`, `meson`, `ninja`, `pkg-config` plus the `libusb-1.0`,
  `libxml-2.0` and `libzip` development packages (only when `make deps`
  builds qdl from source)

## Targets

`make help` lists every target.  In normal order of use:

* `make config` -- create `.env` from `.env.sample` if missing.
* `make deps` -- ensure `sectools` (always) and `qdl` (unless
  `QCOM_VIP_DISABLE` is set) are available locally; both are fetched
  on demand into `./.sectools/<version>/` and `./.qdl/<ref>/`.
* `make generate-keys` -- run `genkeys.sh` to produce the OEM root,
  attestation CA and FMP key tree under `./OEM-KEYS/`.
* `make sign-build` -- stage `QCOM_FLAT_BUILD` into `QCOM_SIGNED_BUILD`,
  sign the images there, then (unless `QCOM_VIP_DISABLE`) generate and
  sign a VIP digest table under `QCOM_SIGNED_BUILD/vip-tables/`.
* `make flash` -- program `QCOM_SIGNED_BUILD` to a connected device
  with `qdl`, passing the signed VIP table and `QCOM_STORAGE`.
* `make gen-fuse-blower` -- generate the signed `sec.elf` used to blow
  the secure-boot fuses on the device.

  > **WARNING:** blowing fuses is irreversible.  Only signed images
  > can boot afterwards, so do not run this on development devices.

* `make gen-capsule` -- assemble a UEFI capsule for runtime firmware
  updates.  Requires the `cbsp-boot-utilities` submodule; populate it
  with `git submodule update --init --recursive`.
* `make clean` -- remove the on-demand `./.sectools/` and `./.qdl/`
  downloads.  Does not touch keys, `signed-build/` or `vip-tables/`.

## Fuse identifiers

`gen-fuse-blower` requires three fuse parameters:

* `QCOM_FUSE_OEM_HW_ID` and `QCOM_FUSE_OEM_PRODUCT_ID` are per-product
  identifiers assigned by Qualcomm; they are published in the
  Programming Application Note / Security Application Note for the
  target SoC and product.
* `QCOM_FUSE_SEC_KEY_DERIVATION_KEY` is an OEM-chosen secret hex value
  burned into the device's fuses to seed key derivation.  Treat it
  like a key (and pick something other than the `0x00` placeholder for
  production devices).

## Securing the hardware

After `make gen-fuse-blower` writes `sec.elf` into the output folder,
plug it into the relevant `rawprogram*.xml` so it becomes the
`secdata` payload during programming:

```bash
$ sed -i '/secdata/s/filename=""/filename="sec.elf"/g' \
    $QCOM_SIGNED_BUILD/rawprogram4.xml
```

Then `make flash` programs the device.  After flashing, reboot; the
SoC will boot using the OEM secure-boot chain established by the
signed artefacts and the fuses you set.

## Running the scripts directly

The Makefile is the recommended interface, but each script remains
usable on its own; run `<script> --help` for the full flag list:

* `./genkeys.sh --help`
* `./signimages.sh --help`
* `./secure.sh --help`
* `./gencapsule.sh --help`

A Dockerfile is provided to run `genkeys.sh` without installing
OpenSSL locally:

```bash
$ docker build -t genkeys:latest .
$ docker run --rm -it -v $(pwd)/OEM-KEYS:/src/OEM-KEYS genkeys:latest
```

## License

This project is licensed under [The Clear BSD License](LICENSE).
See [LICENSE](LICENSE) for the full text.
