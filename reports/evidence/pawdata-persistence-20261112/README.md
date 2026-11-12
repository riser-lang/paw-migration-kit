# PAWDATA two-boot persistence evidence (2026-11-12)

Media: `lab/tf32.img`, 32,000,000,000 bytes, DOS hybrid MBR, serial `PAW-MEDIA-123456`.
Boot 1 created only `/dev/sdc3` and token; boot 2 reused the same image and the same token.

| Check | Boot 1 | Boot 2 |
|---|---|---|
| New partition | `/dev/sdc3`, start=2004992, size=60495008 | unchanged geometry |
| Token SHA256 | `b7a649...914290` | same value, reused |
| Prompt | serial suffix typed once | no prompt, already initialized |
| Health | PASS | PASS |
| Stage log | `boot1/pawdata-stages.log` complete | no reformat; `boot2/*paw-data-prepare*.log` |

Key boot-2 line: `PAWDATA is already mounted and healthy; no partition change was made.`
Machine comparison: `boot2/persistence-compare.json`.

The full console evidence is outside the repo at
`~/final-20261112/evidence/pawdata-special/`; this bundle contains the small text artifacts.
