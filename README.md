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
$ wget https://softwarecenter.qualcomm.com/api/download/software/tools/Qualcomm_Security_Tools/All/1.45.0/1.45.zip
$ unzip 1.45.zip -d sectoolsv2_1.45
$ chmod +x sectoolsv2_1.45/Linux/sectools

# qcom-sec-tools-wrapper
$ git clone --recurse-submodules git@github.com:qualcomm-linux/qcom-sec-tools-wrapper.git
```

* Download the image files, boot binaries and hardware security profile to the working directory:

[Hardware boot binaries](https://softwarecenter.qualcomm.com/nexus/generic/product/chip/tech-package/)
Hardware Security Profile* - tbd

* Set the environment:

```bash
$ export SECTOOL=${WORKDIR}/sectoolsv2_1.45/Linux/sectools
$ export SECTOOL_SCRIPTS=${WORKDIR}/qcom-sec-tools-wrapper
$ export SEC_PROFILE=${WORKDIR}/<hardware>_security_profile.xml
```

## Usage

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

