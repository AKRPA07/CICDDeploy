# UiPathPack.ps1 - FINAL STABLE VERSION (Feb 2026)

param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$project_path,

    [Parameter(Mandatory=$true)]
    [string]$destination_folder,

    [switch]$autoVersion
)

$ErrorActionPreference = "Stop"

# -------------------------------------------------
# Setup
# -------------------------------------------------
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = Join-Path $scriptPath "pack-log.txt"

function Write-Log ($msg, [switch]$Error) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time`t$msg" | Out-File -FilePath $debugLog -Append -Encoding utf8
    if ($Error) { Write-Host $msg -ForegroundColor Red }
    else { Write-Host $msg }
}

Write-Log "========== UiPath Package Build Started =========="

# -------------------------------------------------
# CLI DOWNLOAD
# -------------------------------------------------
$cliRoot = Join-Path $scriptPath "uipathcli"
$cliVersion = "23.10.8753.32995"
$cliFolder = Join-Path $cliRoot $cliVersion
$zipPath = Join-Path $cliFolder "uipcli.zip"

if (!(Test-Path $cliFolder)) {
    New-Item -ItemType Directory -Path $cliFolder -Force | Out-Null
}

$uipathCLI = Get-ChildItem $cliFolder -Recurse -Filter "uipcli.exe" -ErrorAction SilentlyContinue |
             Select-Object -First 1

if (!$uipathCLI) {

    Write-Log "Downloading UiPath CLI $cliVersion"

    Invoke-WebRequest `
        -Uri "https://uipath.pkgs.visualstudio.com/Public.Feeds/_apis/packaging/feeds/UiPath/nuget/packages/uipcli/versions/$cliVersion/content" `
        -OutFile $zipPath

    Expand-Archive -Path $zipPath -DestinationPath $cliFolder -Force
    Remove-Item $zipPath -Force

    $uipathCLI = Get-ChildItem $cliFolder -Recurse -Filter "uipcli.exe" |
                 Select-Object -First 1
}

if (!$uipathCLI) {
    Write-Log "uipcli.exe not found after extraction" -Error
    exit 1
}

Write-Log "Using CLI: $($uipathCLI.FullName)"

# -------------------------------------------------
# PROJECT PATH RESOLUTION
# -------------------------------------------------
Write-Log "Raw project path: $project_path"

try {
    $resolvedProject = Resolve-Path $project_path

    if (Test-Path $resolvedProject -PathType Container) {
        $candidate = Join-Path $resolvedProject "project.json"
        if (!(Test-Path $candidate)) {
            throw "project.json not found in folder"
        }
        $resolvedProject = $candidate
    }

    Write-Log "Resolved project.json: $resolvedProject"
}
catch {
    Write-Log "Project path error: $($_.Exception.Message)" -Error
    exit 1
}

# -------------------------------------------------
# OUTPUT FOLDER
# -------------------------------------------------
if (!(Test-Path $destination_folder)) {
    New-Item -ItemType Directory -Path $destination_folder -Force | Out-Null
}

# -------------------------------------------------
# BUILD ARGUMENTS
# -------------------------------------------------
$args = @(
    "package"
    "pack"
    "$resolvedProject"
    "--output"
    "$destination_folder"
)

if ($autoVersion) {
    $args += "--autoVersion"
}

Write-Log "Command:"
Write-Log "$($uipathCLI.FullName) $($args -join ' ')"
Write-Log "------------------------------------------------"

# -------------------------------------------------
# EXECUTE
# -------------------------------------------------
& $uipathCLI.FullName $args

if ($LASTEXITCODE -eq 0) {
    Write-Log "SUCCESS: Package created"
    exit 0
}
else {
    Write-Log "FAILED: Exit code $LASTEXITCODE" -Error
    exit 1
}
