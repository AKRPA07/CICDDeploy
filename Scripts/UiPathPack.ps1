<#
.SYNOPSIS
    Pack UiPath project into a NuGet package (*.nupkg)
.DESCRIPTION
    Auto-downloads UiPath CLI if needed and packs the project without quoting issues.
#>

param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$project_path = "",

    [Parameter(Mandatory=$true)]
    [string]$destination_folder = "",

    [switch]$autoVersion

    # Add other params later if needed: version, outputType, libraryOrchestratorUrl, etc.
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog   = "$scriptPath\pack-log.txt"

function Write-Log ($msg, [switch]$Error) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time`t$msg" | Out-File -FilePath $debugLog -Append -Encoding utf8
    if ($Error) { Write-Host $msg -ForegroundColor Red } else { Write-Host $msg }
}

# ──────────────────────────────────────────────────────────────
# CLI LOCATION & DOWNLOAD
# ──────────────────────────────────────────────────────────────
$cliVersion = "23.10.8753.32995"
$cliFolder  = "$scriptPath\uipathcli\$cliVersion"
$zipPath    = "$cliFolder\cli.zip"

# Try to find existing exe anywhere in the folder
$foundExe = Get-ChildItem -Path $cliFolder -Recurse -File -Filter "uipcli.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName

if ($foundExe) {
    $uipathCLI = $foundExe
    Write-Log "Existing uipcli.exe found at: $uipathCLI"
} else {
    Write-Log "Downloading UiPath CLI $cliVersion..."
    New-Item -Path $cliFolder -ItemType Directory -Force | Out-Null

    try {
        Invoke-WebRequest `
            -Uri "https://uipath.pkgs.visualstudio.com/Public.Feeds/_apis/packaging/feeds/1c781268-d43d-45ab-9dfc-0151a1c740b7/nuget/packages/UiPath.CLI.Windows/versions/$cliVersion/content" `
            -OutFile $zipPath `
            -UseBasicParsing

        Expand-Archive -Path $zipPath -DestinationPath $cliFolder -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # DEBUG: show what files were extracted
        Write-Log "=== Extracted files (recursive) ==="
        Get-ChildItem -Path $cliFolder -Recurse -File | ForEach-Object {
            Write-Log "  $($_.FullName)  -- size: $($_.Length) bytes"
        }

        # Find uipcli.exe anywhere
        $foundExe = Get-ChildItem -Path $cliFolder -Recurse -File -Filter "uipcli.exe" -ErrorAction SilentlyContinue |
                    Select-Object -First 1 -ExpandProperty FullName

        if ($foundExe) {
            $uipathCLI = $foundExe
            Write-Log "uipcli.exe detected at: $uipathCLI"
        } else {
            Write-Log "ERROR: uipcli.exe NOT FOUND after extraction" -Error
            exit 1
        }
    }
    catch {
        Write-Log "Download or extraction failed: $($_.Exception.Message)" -Error
        exit 1
    }
}

# Final check before using
if (-not (Test-Path $uipathCLI -PathType Leaf)) {
    Write-Log "CRITICAL: uipcli.exe is missing at $uipathCLI" -Error
    exit 1
}

Write-Log "uipcli location: $uipathCLI"

# ──────────────────────────────────────────────────────────────
# PATH NORMALIZATION
# ──────────────────────────────────────────────────────────────
Write-Log "Raw project_path received: '$project_path'"

try {
    $resolvedProject = Resolve-Path $project_path -ErrorAction Stop

    if (Test-Path $resolvedProject -PathType Container) {
        $projectJsonCandidate = Join-Path $resolvedProject "project.json"
        if (Test-Path $projectJsonCandidate) {
            $resolvedProject = $projectJsonCandidate
        } else {
            throw "No project.json found in folder: $resolvedProject"
        }
    } elseif (-not $resolvedProject.ToString().EndsWith("project.json", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path does not point to project.json file: $resolvedProject"
    }

    Write-Log "Resolved full project path: '$resolvedProject'"
}
catch {
    Write-Log "Path resolution failed: $($_.Exception.Message)" -Error
    exit 1
}

# Create output folder if missing
if (-not (Test-Path $destination_folder)) {
    New-Item -Path $destination_folder -ItemType Directory -Force | Out-Null
    Write-Log "Created output folder: $destination_folder"
}

# ──────────────────────────────────────────────────────────────
# BUILD ARGUMENTS (NO QUOTES, NO EMBEDDING)
# ──────────────────────────────────────────────────────────────
$args = @(
    "package"
    "pack"
    $resolvedProject
    "--output"
    $destination_folder
)

if ($autoVersion.IsPresent) {
    $args += "--autoVersion"
}

Write-Log "Executing command:"
Write-Log "$uipathCLI $($args -join ' ')"
Write-Log "-------------------------------------------------------------------------------"

# ──────────────────────────────────────────────────────────────
# EXECUTE
# ──────────────────────────────────────────────────────────────
& $uipathCLI $args

if ($LASTEXITCODE -eq 0) {
    Write-Log "Success – .nupkg should be in: $destination_folder"
    exit 0
} else {
    Write-Log "Failed – exit code $LASTEXITCODE" -Error
    exit 1
}
