# qcom-sec-tools-wrapper

Qualcomm `sectools` wrapper scripts to support key generation, signing images, blowing fuses and generating capsules for production devices.

## Requirements

* [Qualcomm Security Tools - sectools](https://softwarecenter.qualcomm.com/catalog/item/Qualcomm_Security_Tools)
* [Hardware boot binaries](https://softwarecenter.qualcomm.com/nexus/generic/product/chip/tech-package/)
* Hardware Security Profile - tbd
* Image files - tbd
* Host tooling:
  * openssl >= 1.1.1
  * hexdump
  * dtc
  * python3
  * udisksctl (udisks2)
  * sbsign (only for UEFI secure boot)

## Preparation

* Download and extract all required packages:

```bash
$ mkdir qcom-secure && cd qcom-secure
$ export WORKDIR=${PWD}

# sectools
$ wget https://softwarecenter.qualcomm.com/api/download/software/tools/Qualcomm_Security_Tools/All/1.50.0/1.50.zip
$ unzip 1.50.zip -d sectools-public
$ chmod +x sectools-public/1.50/Linux/sectools

# qcom-sec-tools-wrapper
$ git clone --recurse-submodules git@github.com:qualcomm-linux/qcom-sec-tools-wrapper.git
```

* Download the image files, boot binaries and hardware security profile to the working directory:

[Hardware boot binaries](https://softwarecenter.qualcomm.com/nexus/generic/product/chip/tech-package/)
Hardware Security Profile* - tbd

* Set the environment:

```bash
$ export SECTOOL=${WORKDIR}/sectools-public/1.50/Linux/sectools
$ export SECTOOL_SCRIPTS=${WORKDIR}/qcom-sec-tools-wrapper
$ export SEC_PROFILE=${WORKDIR}/<hardware>_security_profile.xml
```

## Usage

Choose the script for your task:

| Task | Script | Instructions |
| --- | --- | --- |
| Create OEM signing keys and certificates | `genkeys.sh` | [Generating Keys](#generating-keys) |
| Sign existing firmware images | `signimages.sh` | [Signing Images](#signing-images) |
| Generate a fuse image from individual selections | `genfuses.sh` | [Generating Selected Fuse Images](#generating-selected-fuse-images) |
| Generate the predefined secure-boot fuse images or prepare UEFI enrollment | `secure.sh` | [Securing the Hardware](#securing-the-hardware) |

### Generating Keys

Run the `genkeys.sh` script in the working directory, providing the Firmware Management Protocol (FMP) key password.
This generates the `OEM-KEYS` folder with the new certs.

```bash
$ ${SECTOOL_SCRIPTS}/genkeys.sh \
    --fmp-key-password <fmp-key-password>

$ export KEYS_PATH=${WORKDIR}/OEM-KEYS/
$ export FMP_PATH=${WORKDIR}/OEM-KEYS/demoCA
```

> **TIP**: A Dockerfile is available to allow running `genkeys.sh` without installing OpenSSL locally:
>
> ```bash
> $ docker build -t genkeys:latest .
> $ docker run --rm -it -v $(pwd)/OEM-KEYS:/src/OEM-KEYS genkeys:latest
> ```

### Signing Images

Run the `signimages.sh` script in the working directory, providing the `--uefi-keys-path` to a folder containing `DB.key` and `DB.crt` used for signing.
It recursively looks into `--out-dir` (default to `${PWD}`) for `.mbn`/`.elf` files to sign.

```bash
$ ${SECTOOL_SCRIPTS}/signimages.sh \
    --keys-path ${KEYS_PATH} \
    --sectoolv2 ${SECTOOL} \
    --security-profile ${SEC_PROFILE} \
    --uefi-keys-path ${WORKDIR}/lmp-manifest/conf/keys/uefi/ \
    --out-dir ${WORKDIR}/<image-files>
```

TODO avoid lmp mentions

### Generating Selected Fuse Images

Use `genfuses.sh` when you need a signed `sec.elf` containing only selected
individual fuse options. For the predefined secure-boot fuse set, use
[`secure.sh`](#securing-the-hardware). Generating an image does not program a
device; loading and provisioning follow the platform's workflow.

Follow [Preparation](#preparation) for `SECTOOL`, `SECTOOL_SCRIPTS` and
`SEC_PROFILE`, and reuse `KEYS_PATH` from [Generating Keys](#generating-keys).
The wrapper uses the supplied SecTools executable and target profile, with
`LOCAL` signing and the default single-root signing bundle. Existing OEM keys
can also be used with the filenames listed by `genfuses.sh --help`. For the
RSA bundle, pass `--keys-root-hash-filename sha256_roots_hash.txt`.

List the wrapper options and the individual fuses supported by the profile:

```bash
$ "${SECTOOL_SCRIPTS}/genfuses.sh" --help
$ "${SECTOOL}" fuse-blower --security-profile "${SEC_PROFILE}" --help
```

For SHK-only provisioning on Lemans with OP-TEE:

```bash
$ "${SECTOOL_SCRIPTS}/genfuses.sh" \
    --sectoolv2 "${SECTOOL}" \
    --security-profile "${SEC_PROFILE}" \
    --keys-path "${KEYS_PATH}" \
    --out-dir "${WORKDIR}/shk-fuses" \
    --fuse-sec-key-derivation-key 0x00
```

Here `0x00` requests five SHK rows with operation `BLOW`. OP-TEE generates the
actual key on the device and ignores the supplied key values. Use a literal
placeholder for this flow: SecTools' `RANDOM` requests `BLOW_RANDOM`, which the
OP-TEE SHK handler does not select. Other firmware may handle SHK differently.

To select an OEM-spare field with a fixed value, when supported by the profile:

```bash
$ "${SECTOOL_SCRIPTS}/genfuses.sh" \
    --sectoolv2 "${SECTOOL}" \
    --security-profile "${SEC_PROFILE}" \
    --keys-path "${KEYS_PATH}" \
    --out-dir "${WORKDIR}/oem-spare-fuses" \
    --fuse-oem-spare-28=0x01
```

To combine selections, pass both fuse options in one invocation. Both
`--fuse-NAME VALUE` and `--fuse-NAME=VALUE` are accepted; boolean fuse options
take no value. SecTools validates names and values against the target profile.
Fuse groups and recommended-fuse presets are not accepted. Permission locks,
FEC enables, root-hash fuses and secure-boot settings must be selected explicitly
when required by the provisioning plan.

The wrapper verifies the signing root before publishing `OUT_DIR/sec.elf` and
preserves existing output unless `--force` is supplied. No `sudo` is needed.
Inspect the complete fuse list and signing identity before provisioning; for
the SHK example:

```bash
$ "${SECTOOL}" fuse-blower "${WORKDIR}/shk-fuses/sec.elf" \
    --security-profile "${SEC_PROFILE}" --inspect
```

See the [OP-TEE QFPROM provisioning documentation](https://optee.readthedocs.io/en/latest/architecture/platforms/qualcomm/qfprom_provisioning.html)
for input loading, device-generated keys, validation and boot outcomes.

### Securing the Hardware

Run the `secure.sh` script in the working directory.
This generates a signed `sec.elf` image used to blow the fuses and secure the hardware.

> **WARNING:** Blowing fuses is an irreversible step and can only be performed once.
> Only signed images can boot after securing the hardware, so it is not recommended to blow the fuses on development devices.
> Proceed with caution.

```bash
$ sudo ${SECTOOL_SCRIPTS}/secure.sh \
    --keys-path ${KEYS_PATH} \
    --fmp-path ${FMP_PATH} \
    --sectoolv2 ${SECTOOL} \
    --security-profile ${SEC_PROFILE} \
    --create-sec-elf --fuse-oem-hw-id 0x<HWID> --fuse-oem-product-id 0x<PID> \
    --uefi-keys-path ${WORKDIR}/lmp-manifest/conf/keys/uefi/
```

TODO get links for hwid and pid

Provide the `sec.elf` to the program file:

```bash
$ sed -i '/secdata/s/filename=""/filename="sec.elf"/g' rawprogram4.xml 
```

TODO steps to boot

### Generating Capsule

TODO gencapsule.sh

## License

This project is licensed under [The Clear BSD License](LICENSE).
See [LICENSE](LICENSE) for the full text.

