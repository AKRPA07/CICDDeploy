# UiPathPack.ps1 - FINAL FIXED VERSION (Jan 2026) - no embedded quotes, auto-detect CLI exe

param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$project_path = "",

    [Parameter(Mandatory=$true)]
    [string]$destination_folder = "",

    [switch]$autoVersion
    # add other params here later if needed (version, outputType, etc.)
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = "$scriptPath\pack-log.txt"

function Write-Log ($msg, [switch]$Error) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time`t$msg" | Out-File -FilePath $debugLog -Append -Encoding utf8
    if ($Error) { Write-Host $msg -ForegroundColor Red } else { Write-Host $msg }
}

# Force delete old CLI folder to ensure clean download (remove after first success if caching desired)
Remove-Item -Path "$scriptPath\uipathcli" -Recurse -Force -ErrorAction SilentlyContinue
Write-Log "Old CLI folder deleted for fresh start."

# ======================== CLI LOCATION & DOWNLOAD ========================
$cliVersion = "23.10.8753.32995"
$cliFolder = "$scriptPath\uipathcli\$cliVersion"

Write-Log "Downloading UiPath CLI $cliVersion..."
New-Item -Path $cliFolder -ItemType Directory -Force | Out-Null
$zipPath = "$cliFolder\cli.zip"

try {
    Invoke-WebRequest `
        -Uri "https://uipath.pkgs.visualstudio.com/Public.Feeds/_apis/packaging/feeds/1c781268-d43d-45ab-9dfc-0151a1c740b7/nuget/packages/UiPath.CLI.Windows/versions/$cliVersion/content" `
        -OutFile $zipPath `
        -UseBasicParsing

    Expand-Archive -Path $zipPath -DestinationPath $cliFolder -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # DEBUG: list all files
    Write-Log "=== Extracted files in $cliFolder (recursive) ==="
    Get-ChildItem -Path $cliFolder -Recurse -File | ForEach-Object {
        Write-Log "  $($_.FullName)  -- size: $($_.Length) bytes"
    }

    # Auto-detect exe
    $uipathCLI = Get-ChildItem -Path $cliFolder -Recurse -File -Filter "uipcli.exe" -ErrorAction SilentlyContinue |
                 Select-Object -First 1 -ExpandProperty FullName

    if ($uipathCLI) {
        Write-Log "uipcli.exe found at: $uipathCLI"
    } else {
        Write-Log "ERROR: uipcli.exe NOT FOUND after extraction!" -Error
        exit 1
    }
}
catch {
    Write-Log "Download/extract failed: $($_.Exception.Message)" -Error
    exit 1
}

# Final check
if (-not (Test-Path $uipathCLI -PathType Leaf)) {
    Write-Log "CRITICAL: uipcli.exe missing!" -Error
    exit 1
}

# ======================== PATH NORMALIZATION ========================
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
    Write-Log "Resolved full project path for uipcli: '$resolvedProject'"
} catch {
    Write-Log "Path resolution failed: $($_.Exception.Message)" -Error
    exit 1
}

# Ensure destination exists
if (-not (Test-Path $destination_folder)) {
    New-Item -Path $destination_folder -ItemType Directory -Force | Out-Null
    Write-Log "Created output folder: $destination_folder"
}

# ======================== BUILD ARGUMENTS ========================
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

# ======================== EXECUTE ========================
& $uipathCLI $args

if ($LASTEXITCODE -eq 0) {
    Write-Log "Success – .nupkg should be in: $destination_folder"
    exit 0
} else {
    Write-Log "Failed – exit code $LASTEXITCODE" -Error
    exit 1
}
