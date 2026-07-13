[CmdletBinding()]
param(
  [string]$WorkingDirectory = ".",
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [string]$NamePrefix = "tfpro-c27",
  [string]$ManifestPath = "../fixtures/release-v1.json",
  [string]$ReleaseVersion = "1.0.0"
)

# TODO: saved plan -> show -json allowlist audit -> apply saved plan -> detailed-exitcode。
throw "TODO: implement audited publish"

