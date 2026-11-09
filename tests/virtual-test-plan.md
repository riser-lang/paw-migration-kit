# PAW Virtual Test Matrix (v2.5)

No Linux/QEMU environment is available, so all rows remain `NOT RUN`. All disk cases must use files under `tests/virtual`; any loop devices must be backed by files in that directory. Never attach a physical disk.

| # | Test | Injection / fixture | Expected fail-closed result |
|---:|---|---|---|
| 1 | systemd auto-start | disposable Debian Live VM | preflight and network services run; clone never auto-starts |
| 2 | DHCP/DNS/ordinary HTTPS | VM network on/off and fake resolver | reports actual state; no proxy if direct tests pass |
| 3 | Xray loopback | fake/missing client config then valid test config | no listener without config; only 127.0.0.1 listeners when valid |
| 4 | Tailscale user authorization | logged-out ephemeral daemon | login URL only on console; no auth key in files/logs |
| 5 | Tailscale proxy path | local HTTP proxy plus control-plane block | join remains pending; no false `ONLINE` result |
| 6 | Exit Node unavailable | no Exit Node advertised | warning; Xray remains active |
| 7 | zstd stream round-trip | small sparse source and destination files | byte-identical output and SHA match |
| 8 | SSH interruption | terminate mocked source after N bytes | nonzero pipeline; `CLONE-INCOMPLETE` remains |
| 9 | SHA verification | flip one destination byte | verifier fails; no PASS receipt |
| 10 | destination too small | target image truncated | size preflight or write/hash fails before PASS |
| 11 | target serial mismatch | fake lsblk output/config | fails before opening target for write |
| 12 | SMART FAIL/unsupported | stub smartctl exit and output | FAIL or WARN, never PASS |
| 13 | memory error / incomplete | synthetic Memtest log | FAIL on any error; WARN when coverage/completion absent |
| 14 | read I/O timeout / SATA reset | stub badblocks/dmesg output | WARN/FAIL and clone gate closed |
| 15 | GPT grow | loop-backed GPT image | only registered loop image changes; partition geometry verified |
| 16 | ext4 grow | loop-backed ext4 partition | fsck clean and larger filesystem recorded |
| 17 | first boot | missing receipt, wrong serial, incomplete marker | gate refuses completion/reboot |
| 18 | recovery | interruption followed by re-run to new test image | incomplete prior target stays rejected; recovery receipt identifies new target |

Do not convert a successful script exit into a hardware or production result. Persist the command, stdout/stderr, fixture hashes, and expected/actual status per case when the Linux harness exists.
