param([string]$Root = (Join-Path $env:USERPROFILE 'PAW-Migration'))
$ErrorActionPreference = 'Stop'
$required = @('paw-live-preflight.sh','paw-hardware-preflight.sh','paw-ssd-smart-check.sh','paw-ssd-read-scan.sh','paw-memory-test-report.sh','paw-source-discovery.sh','paw-stream-clone.sh','paw-stream-verify.sh','paw-offline-repair.sh','paw-gpt-expand.sh','paw-firstboot-check.sh','paw-rescue-key-prepare.sh','paw-target-discovery.sh','paw-final-confirm.sh','paw-prepare-data-partition.sh','paw-data-check.sh','paw-network-phase-select.sh','paw-xray-client-configure.sh')
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root "scripts\$_")) })
$psErrors = @()
Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors){$psErrors += $errors}
}
$badblocks = @(Get-ChildItem (Join-Path $Root 'scripts') -Filter '*.sh' -File | Select-String -Pattern 'badblocks\s+.*(?:-w|-n)')
$format = @(Get-ChildItem (Join-Path $Root 'scripts') -Filter '*.sh' -File | Select-String -Pattern '\bmkfs(?:\.[a-z0-9]+)?\s+-|format-disk|Clear-Disk')
$approvedDataFormat = @($format | Where-Object { $_.Path -eq (Join-Path $Root 'scripts\paw-prepare-data-partition.sh') -and $_.Line -match '^\s*mkfs\.ext4\s+-F\s+-L\s+PAWDATA\s+"\$existing"\s+>/dev/null\s*$' })
$format = @($format | Where-Object { $_ -notin $approvedDataFormat })
if($missing.Count -or $psErrors.Count -or $badblocks.Count -or $format.Count){ throw 'Static safety check failed.' }
Write-Output "ENTRYPOINTS=$($required.Count) MISSING=0 POWERSHELL_PARSE_ERRORS=0 BADBLOCKS_WRITE_FLAGS=0 FORMAT_COMMANDS=0"
