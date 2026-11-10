# Verifies the PAW delivery folder on Windows PowerShell 5.1.
#
#   powershell -ExecutionPolicy Bypass -File .\verify-delivery.ps1
#   powershell -ExecutionPolicy Bypass -File .\verify-delivery.ps1 -WriteSums
#
# -WriteSums regenerates SHA256SUMS.txt from the current folder contents (the ISO line is
# skipped because it is covered by paw-live-amd64.iso.sha256).

[CmdletBinding()]
param(
    [switch]$WriteSums,
    [string]$Path
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location -LiteralPath $Path

$isoName = 'paw-live-amd64.iso'
$sidecarName = 'paw-live-amd64.iso.sha256'
$sumsName = 'SHA256SUMS.txt'
$expectedIsoBytes = 930086912

function Get-Sha256 {
    param([string]$File)
    (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
}

$failures = New-Object System.Collections.Generic.List[string]
$checks = 0

if (-not (Test-Path -LiteralPath $isoName)) {
    $failures.Add("ISO missing: $isoName")
} else {
    $checks++
    $size = (Get-Item -LiteralPath $isoName).Length
    if ($size -ne $expectedIsoBytes) {
        $failures.Add("ISO size $size != $expectedIsoBytes")
    } else {
        Write-Host ("OK   ISO size {0} bytes" -f $size)
    }

    if (-not (Test-Path -LiteralPath $sidecarName)) {
        $failures.Add("sidecar missing: $sidecarName")
    } else {
        $checks++
        $expected = ((Get-Content -LiteralPath $sidecarName -TotalCount 1) -split '\s+')[0].ToLowerInvariant()
        $actual = Get-Sha256 $isoName
        if ($expected -ne $actual) {
            $failures.Add("ISO SHA256 $actual != sidecar $expected")
        } else {
            Write-Host ("OK   ISO SHA256 {0}" -f $actual)
        }
    }
}

if ($WriteSums) {
    $lines = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $Path -File | Sort-Object Name | ForEach-Object {
        if ($_.Name -eq $sumsName -or $_.Name -eq $isoName) { return }
        $lines.Add((Get-Sha256 $_.FullName) + '  ' + $_.Name)
    }
    [System.IO.File]::WriteAllLines((Join-Path $Path $sumsName), $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("WROTE {0} ({1} entries)" -f $sumsName, $lines.Count)
} elseif (Test-Path -LiteralPath $sumsName) {
    $entries = 0
    foreach ($line in Get-Content -LiteralPath $sumsName) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\s+', 2
        $want = $parts[0].ToLowerInvariant()
        $name = $parts[1].Trim()
        if (-not (Test-Path -LiteralPath $name)) {
            $failures.Add("listed file missing: $name")
            continue
        }
        $checks++
        $entries++
        $got = Get-Sha256 $name
        if ($got -ne $want) {
            $failures.Add("hash mismatch: $name")
        }
    }
    Write-Host ("OK   {0} files match {1}" -f $entries, $sumsName)
} else {
    $failures.Add("$sumsName missing; run with -WriteSums first")
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host ("DELIVERY=PASS ({0} checks)" -f $checks)
    exit 0
}

Write-Host ("DELIVERY=FAIL ({0} checks, {1} problems)" -f $checks, $failures.Count)
foreach ($item in $failures) { Write-Host (" - " + $item) }
exit 1
