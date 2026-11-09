#!/usr/bin/env bash
set -Eeuo pipefail
base="${RUNNER_TEMP:-/tmp}/paw-debian-base"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
name=debian-live-13.7.0-amd64-standard.iso
url="https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid"
expected_fpr=DF9B9C49EAA9298432589D76DA87E80D6294BE9B
mkdir -p "$base" "$out"
curl --fail --location --silent --show-error "$url/$name" -o "$base/$name"
curl --fail --location --silent --show-error "$url/SHA256SUMS" -o "$base/SHA256SUMS"
curl --fail --location --silent --show-error "$url/SHA256SUMS.sign" -o "$base/SHA256SUMS.sign"
curl --fail --location --silent --show-error "https://www.debian.org/CD/key-DA87E80D6294BE9B.txt" -o "$base/debian-cd-key.asc"
actual_fpr="$(gpg --show-keys --with-colons "$base/debian-cd-key.asc" | awk -F: '$1=="fpr" {print $10; exit}')"
[[ "$actual_fpr" == "$expected_fpr" ]] || { echo 'Debian CD key fingerprint mismatch.' >&2; exit 1; }
gpg --batch --yes --dearmor --output "$base/debian-cd-keyring.gpg" "$base/debian-cd-key.asc"
gpgv --status-fd 1 --keyring "$base/debian-cd-keyring.gpg" "$base/SHA256SUMS.sign" "$base/SHA256SUMS" >"$base/signature-status.log" 2>"$base/signature-check.log"
grep -Fq "[GNUPG:] VALIDSIG $expected_fpr " "$base/signature-status.log"
(cd "$base" && sha256sum --ignore-missing --check SHA256SUMS) >"$base/hash-check.log"
grep -F "$name: OK" "$base/hash-check.log" >/dev/null
iso_sha="$(sha256sum "$base/$name" | awk '{print $1}')"
iso_size="$(stat -c %s "$base/$name")"
{
  echo 'Debian Live base verification: PASS'
  echo "Image: $name"
  echo "Size bytes: $iso_size"
  echo "SHA256: $iso_sha"
  echo "Detached signature: PASS (Debian CD key $expected_fpr)"
  echo 'Manifest hash check: PASS'
} >"$out/debian-base-verification.txt"
rm -rf "$base"
