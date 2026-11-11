# Memtest86+ BIOS binary provenance

- Project: Memtest86+ <https://www.memtest.org/>
- Version: 7.20 (`Memtest86+ v7.20`, build string `7.20.unknown.x64`)
- Binary: `memtest86+x64.bin` (BIOS/x86-64 multiboot image, 155,992 bytes)
- Package origin: Debian `memtest86+` 7.20, installed in the Debian 13
  (trixie) live-build chroot used for the candidate ISO.
- SHA256: `487bfe56b84f2016b12f393641f1acb765ef0b648c71ea9a2e3d42b62411f71f`
- License: GPL-2.0-or-later (Memtest86+ is free software).
- Why vendored: the Ubuntu 24.04 build host only offers 7.00.  Copying
  `/boot/memtest86+x64.bin` from the host therefore produced an ISO whose
  menu entry and binary version could silently diverge.  This pinned file is
  the one the ISO ships; `scripts/build-debian-live.sh` verifies its digest and
  version before copying it.

The file is loaded by ISOLINUX with the `linux` directive.  It is a bzImage,
not a chain-loadable boot sector and not an ELF multiboot image requiring
`mboot.c32`.
