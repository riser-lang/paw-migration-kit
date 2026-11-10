# Run 42892095324 evidence — reproducibility probe (deep)

The workflow was dispatched with `double_build=true`, so it built the ISO twice and ran
`scripts/ci/repro-probe.sh` with `PAW_PROBE_DEEP=1`. The run itself is green: payload 54/54,
repair 28/28, fault 39, PAWDATA 12, network 17, finalize 36, TTY 56, CJK 5/96 — the same
suites ran against the second build.

`iso-repro-report.txt` is the point of this folder. It narrows REPRO from "different hash"
to a concrete finding:

| Layer | Result |
|---|---|
| ISO size | identical, 953,155,584 bytes |
| ISO volume id / publisher / creation time | identical (`PAW-LIVE`, `2026110100000000`) |
| `/live/vmlinuz` | byte-identical |
| `/live/initrd.img` | byte-identical |
| `/live/filesystem.squashfs` | same size (815,972,352), **different hash** |
| squashfs compression | both `xz`, block 131072, 25595 inodes, 2092 fragments, 12 ids |
| squashfs listing (path/size/owner/mtime) | 25,600 lines each, **0 differing lines** |
| 7 sampled files inside the squashfs | 7/7 identical |
| ISO first differing byte | offset 13,977,635; 57,134,346 bytes differ |
| full `diff -rq` of both extracted rootfs | 214 entries, of which the first real content hit is **`/etc/nvme/hostid`** |

Interpretation, kept deliberately narrow: the image tree is the same size and the same
listing, ten sampled files are identical, and one concrete file that does differ is a
build-host-generated identifier (`/etc/nvme/hostid`, produced by the `nvme` package during
the chroot build). The 214 `diff` entries include noise — dangling symlinks reported as
"No such file" and `/dev` character devices (diff refuses to compare them) — so the next
probe must filter to `differ` / `Only in` lines before claiming a count.

Not claimed here: that `/etc/nvme/hostid` is the *only* difference, or that removing it makes
the build reproducible. That needs the filtered diff and then a rebuild experiment.
