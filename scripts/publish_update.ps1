param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [int]$VersionCode,

    [string]$Message = "A newer and improved version of friendlyhood-split is available.",
    [switch]$ForceUpdate
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$apkSource = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"
$updateJson = Join-Path $projectRoot ".app-update-release.json"
$expectedVersion = "version: $Version+$VersionCode"
$repository = "santhanamani/friendlyhood-split"
$releaseTag = "v$Version"
$apkUrl = "https://github.com/$repository/releases/download/$releaseTag/app-release.apk"

if (-not (Select-String -LiteralPath $pubspecPath -SimpleMatch $expectedVersion -Quiet)) {
    throw "Update pubspec.yaml to '$expectedVersion' before publishing."
}

Push-Location $projectRoot
try {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI is required. Install it with: winget install --id GitHub.cli"
    }
    & gh auth status --hostname github.com
    if ($LASTEXITCODE -ne 0) { throw "Run 'gh auth login' before publishing." }

    flutter build apk --release

    & gh release view $releaseTag --repo $repository *> $null
    if ($LASTEXITCODE -eq 0) {
        & gh release upload $releaseTag $apkSource --repo $repository --clobber
    } else {
        & gh release create $releaseTag $apkSource --repo $repository --title "friendlyhood-split $Version" --notes $Message --latest
    }
    if ($LASTEXITCODE -ne 0) { throw "GitHub Release upload failed." }

    $payload = [ordered]@{
        latestVersion = $Version
        latestVersionCode = $VersionCode
        apkUrl = $apkUrl
        forceUpdate = $ForceUpdate.IsPresent
        updateTitle = "New Update Available"
        updateMessage = $Message
    }
    $payload | ConvertTo-Json | Set-Content -LiteralPath $updateJson -Encoding UTF8

    & npx.cmd --yes firebase-tools@latest deploy --only database --project friends-split-up
    if ($LASTEXITCODE -ne 0) { throw "Realtime Database rules deployment failed." }

    & npx.cmd --yes firebase-tools@latest database:set /app_update $updateJson --project friends-split-up --instance friends-split-up-default-rtdb --force
    if ($LASTEXITCODE -ne 0) { throw "Realtime Database update failed." }

    Write-Host "Published friendlyhood-split $Version ($VersionCode)."
} finally {
    if (Test-Path -LiteralPath $updateJson) {
        Remove-Item -LiteralPath $updateJson -Force
    }
    Pop-Location
}
