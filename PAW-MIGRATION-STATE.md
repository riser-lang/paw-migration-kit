# PAW Migration State

Updated: 2026-11-09 UTC
Branch: `fix/v2.6.2-final-readiness`
Final cloud-tested commit: `338b884c6024a02f459d5a2c0d1263cf93455185`
PR: #2 (Draft; #1 untouched)

## Phase

- Phase 1: repository and environment takeover — complete.
- Phase 2: P0 blockers — implemented and virtually verified.
- Phase 3: P1 adaptation — implemented and virtually verified; real hardware pending.
- Phase 4: cloud build — PASS, Run `42615204317`.
- Phase 5: expanded virtual test matrix — PASS, 79/79 reported tests.
- Phase 6: public security audit and delivery package — final documentation in progress.

## Final cloud evidence

- Run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42615204317>
- Artifact ID: `13672831707`, `paw-live-build-test-results`, 938,778,035 bytes
- Expires: 2026-11-12 12:20:59 UTC
- ISO SHA256: `5daf4c0b7af05258c7e90d8c84ba5e474b2ba8215a2cc75781c5374e4c15a4b8`
- Test totals: PAWDATA 12/12, fault injection 35/35, repair/rollback 15/15, network 17/17
- QEMU SeaBIOS/TCG: PASS, readiness BLOCKED, clone_started=false

## Verified now

- Branch checkout, static checks, ShellCheck, Python/JSON/YAML, public safety and reachable-history scan.
- Debian base signature/hash, Tailscale signed package, Xray release digest.
- ISO build, ISO SHA sidecar, Hybrid ISO/Memtest menu, QEMU boot.
- PAWDATA MBR/GPT auto-init, only-new-partition format, remount persistence.
- Memtest operator confirmation states and hardware gate.
- Rescue source identity with and without Virtio serial.
- Remote zstd stream, raw fallback, actual restored byte count, mixed data, interruption.
- Offline repair/rollback on loop ext4, Netplan e* compatibility.
- Mock Xray/Tailscale/network stage behavior.

## Not verified

- Real TF card write and read-back.
- Real ASUS motherboard/SeaBIOS boot.
- Real SSD SMART/read scan/temperature.
- Real Tencent Cloud Rescue Mode SSH.
- Real full-disk clone and real PAW migration.
- Physical Memtest86+ run and operator observation.

These remain open until the user performs them on hardware. No production VPS was accessed.

## Immediate next steps for the user

1. Download the artifact from Run `42615204317` before 2026-11-12 12:20:59 UTC.
2. Recompute ISO SHA256 on the downloaded file and compare with the sidecar.
3. Write the TF card only after reviewing the user guide and rollback guide.
4. Perform physical boot, Memtest, SSD and Rescue checks; keep results separate from cloud/virtual results.
