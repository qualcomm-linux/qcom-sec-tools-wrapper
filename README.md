# qcom-sec-tools-wrapper

Qualcomm `sectools` wrapper scripts for OEM key generation, image
signing, VIP table creation, fuse-blower generation, capsule assembly
and flashing, driven from a single `Makefile`.

## Quick start

```bash
make config          # create .env from .env.sample, then edit it
make deps            # fetch sectools, the security profile and qdl
make generate-keys   # write ./OEM-KEYS
make sign-build      # stage, sign and VIP-sign QCOM_FLAT_BUILD
make flash           # flash the signed build with qdl
```

`make sign-build` copies `QCOM_FLAT_BUILD` into `QCOM_SIGNED_BUILD`
(default `./signed-build`), signs the copies, then generates and signs
a VIP (Validated Image Programming) digest table under
`QCOM_SIGNED_BUILD/vip-tables` unless `QCOM_VIP_DISABLE` is set.
`make flash` programs that folder with `qdl`, passing the VIP table
and `QCOM_STORAGE` (default `ufs`).

`make help` lists all targets. All `.env` keys are documented in
[`.env.sample`](.env.sample); the most important:

| Variable | Used by | Meaning |
|---|---|---|
| `QCOM_SEC_PROFILE` | sign-build, gen-fuse-blower | profile filename (fetched) or path to a `*_security_profile.xml` |
| `QCOM_ROT_KEYS` | sign-build, gen-fuse-blower | OEM signing keys dir (default `OEM-KEYS`) |
| `QCOM_FLAT_BUILD` | sign-build | directory of images to sign |
| `QCOM_SIGNED_BUILD` | sign-build, flash | output folder for signed images and VIP tables |
| `QCOM_FMP_KEY_PASSWORD` | generate-keys | password for the FMP keys |
| `QCOM_SECTOOLS` | all signing targets | sectools binary; leave empty to auto-fetch |
| `QCOM_QDL` | sign-build (VIP), flash | qdl binary; leave empty to clone and build |
| `QCOM_STORAGE` | flash | `emmc`, `nand`, `nvme`, `spinor` or `ufs` |
| `QCOM_FUSE_OEM_HW_ID`, `QCOM_FUSE_OEM_PRODUCT_ID`, `QCOM_FUSE_SEC_KEY_DERIVATION_KEY` | gen-fuse-blower | fuse parameters |

## Requirements

### External pieces

* [Qualcomm Security Tools (sectools) v2](https://softwarecenter.qualcomm.com/catalog/item/Qualcomm_Security_Tools):
  `make deps` downloads version `QCOM_SECTOOLS_VERSION` (default
  1.50.0) into `./.sectools/`, picking the `Linux` or `Linux_aarch64`
  build for the host. Set `QCOM_SECTOOLS` to an existing binary to
  skip the download.
* [Security profiles](https://github.com/qualcomm/security-profiles):
  the per-chipset `*_security_profile.xml` consumed by sectools
  (`kodiak`, `lemans`, `monaco`, `talos`, ...). Set
  `QCOM_SEC_PROFILE` to a bare filename to fetch it from that
  repository, or to a path of your own copy.
* [Hardware boot binaries](https://softwarecenter.qualcomm.com/nexus/generic/product/chip/tech-package/):
  the per-SoC boot artefacts the platform image build depends on.
* Image files: the flat build directory produced by your image build
  (typically Yocto's `deploy/images/<machine>.qcomflash/`) with the
  `.mbn`/`.elf` images, `rawprogram*.xml`, `patch*.xml` and
  `prog_firehose_*.elf`. Set `QCOM_FLAT_BUILD` to it.

### Host tooling

* `openssl` >= 1.1.1, `hexdump`, `dtc`, `python3` >= 3.10
* `udisksctl` (udisks2)
* `sbsign` (UEFI secure boot only)
* `git`, `unzip` and `curl` or `wget` (fetching sectools and profiles)
* `meson`, `ninja`, `pkg-config`, `libusb-1.0`, `libxml-2.0` and
  `libzip` development packages (building qdl)

## Targets

* `make config`: create `.env` from `.env.sample` if missing.
* `make deps`: fetch `sectools`, the security profile and (unless
  `QCOM_VIP_DISABLE`) `qdl` into `./.sectools/`, `./.security-profiles/`
  and `./.qdl/`.
* `make generate-keys`: run `genkeys.sh` to produce the OEM root,
  attestation CA and FMP keys under `./OEM-KEYS/`.
* `make sign-build`: stage, sign and VIP-sign `QCOM_FLAT_BUILD`.
* `make sign-build-with-fuse-blower`: `sign-build` plus
  `gen-fuse-blower`, with `sec.elf` wired into `rawprogram*.xml` before
  the VIP table is generated so the table covers it.
* `make flash`: program `QCOM_SIGNED_BUILD` with `qdl`.
* `make gen-fuse-blower`: generate the signed `sec.elf` that blows the
  secure-boot fuses.

  > **WARNING:** blowing fuses is irreversible. Only signed images
  > boot afterwards, so do not run this on development devices.

* `make gen-capsule`: assemble a UEFI capsule. Needs the
  `cbsp-boot-utilities` submodule (`git submodule update --init`).
* `make clean`: remove `signed-build/` and the VIP tables.
* `make deps-clean`: remove the fetched tools and profiles.
* `make test`: run the test suite under `tests/`.

## Fuse identifiers

`gen-fuse-blower` needs three values:

* `QCOM_FUSE_OEM_HW_ID` and `QCOM_FUSE_OEM_PRODUCT_ID` are assigned by
  Qualcomm and published in the Security Application Note for the SoC.
* `QCOM_FUSE_SEC_KEY_DERIVATION_KEY` is an OEM-chosen secret burned
  into the fuses. Treat it like a key and never ship the `0x00`
  placeholder.

## Securing the hardware

```bash
make sign-build-with-fuse-blower
make flash
```

After flashing, reboot: the SoC boots the OEM secure-boot chain
established by the signed images and the fuses.

## Running the scripts directly

Each script also works on its own; see `<script> --help`:
`genkeys.sh`, `signimages.sh`, `secure.sh`, `gencapsule.sh`,
`fetch-sectools.sh`, `fetch-security-profile.sh`, `fetch-qdl.sh`.

A Dockerfile runs `genkeys.sh` without a local OpenSSL:

```bash
docker build -t genkeys:latest .
docker run --rm -it -v $(pwd)/OEM-KEYS:/src/OEM-KEYS genkeys:latest
```

## License

This project is licensed under [The Clear BSD License](LICENSE).
