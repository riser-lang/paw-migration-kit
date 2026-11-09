#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
out="$PAW_REPORT_DIR/memory-test.json"
evidence="${PAW_MEMTEST_ATTESTATION:-$PAW_STATE_DIR/memtest-attestation.json}"

# A text transcript alone is mutable and cannot establish that Memtest86+ really ran.
# Until a hardware-specific, independently verifiable capture path exists, it is never PASS.
if [[ ! -s "$evidence" ]]; then
  write_status WARN 'No independently verifiable Memtest86+ capture attestation; plain or hand-written logs are not accepted.' "$out"
  log WARN 'Memtest result is WARN; no manual log can produce PASS.'
  exit 2
fi
write_status WARN 'Memtest attestation was present but no trusted signature verifier is configured; physical memory health remains unverified.' "$out"
log WARN 'Memtest attestation was not accepted without a trusted verifier.'
exit 2
