# PAW Migration Kit

This repository contains a minimal Debian Live migration-preparation system and its isolated CI tests. It contains no PAW database, server image, production configuration, credentials, SSH keys, Tailscale authorization keys, or VLESS UUIDs.

## Run the cloud build

Open **Actions → PAW live build and isolated tests → Run workflow**. The workflow is deliberately limited to `workflow_dispatch`; it does not connect to production or run any PAW business workflow.

The job checks shell and PowerShell syntax, JSON and unit structure, and public-repository content. It verifies Debian's signed checksum manifest, obtains Tailscale from its signed Debian package repository, checks the Xray release digest, builds a minimal ISO, boots it with SeaBIOS and QEMU TCG, and runs loop-file-backed clone, repair, expansion, and failure tests. Artifacts are retained for three days.

All virtual disk tests create files under `tests/virtual` and attach only loop devices backed by those files. No runner system disk or physical disk is used as a test target. A successful QEMU run does not prove compatibility with the eventual PC or SSD.

The built Live system is a preparation tool. It never starts a real clone automatically, and remains blocked until required source, target, hardware, and operator checks have been satisfied.
