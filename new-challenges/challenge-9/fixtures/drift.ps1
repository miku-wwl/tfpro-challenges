param(
    [string]$WorkDir = ".grade-work"
)

$ErrorActionPreference = "Stop"
$path = Join-Path $WorkDir "generated/service-manifest.json"
if (-not (Test-Path -LiteralPath $path)) {
    throw "Manifest not found: $path"
}

Set-Content -LiteralPath $path -NoNewline -Value '{"services":{"shadow":{"owner":"unknown","port":1,"tier":"critical"}}}'
Write-Host "Injected out-of-band drift into $path"

