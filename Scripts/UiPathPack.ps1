# UiPathPack.ps1 - FINAL FIXED VERSION (Jan 2026) - no embedded quotes, absolute paths

param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$project_path = "",

    [Parameter(Mandatory=$true)]
    [string]$destination_folder = "",

    [switch]$autoVersion

    # ← add other params here later if needed (version, outputType, etc.)
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog   = "$scriptPath\pack-log.txt"

function Write-Log ($msg, [switch]$Error) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time`t$msg" | Out-File -FilePath $debugLog -Append -Encoding utf8
    if ($Error) { Write-Host $msg -ForegroundColor Red } else { Write-Host $msg }
}

# ======================== CLI LOCATION (keep your existing download logic) ========================
$cliVersion = "23.10.8753.32995"
$uipathCLI  = "$scriptPath\uipathcli\$cliVersion\tools\uipcli.exe"

if (-not (Test-Path $uipathCLI)) {
    Write-Log "Downloading UiPath CLI $cliVersion..."
    # ← paste your full download + extract code here (from your original script)
    # Example placeholder:
    # New-Item ... 
    # Invoke-WebRequest ...
    # Expand-Archive ...
    # Make sure it ends with the correct $uipathCLI path
}

# ======================== PATH NORMALIZATION - THIS IS KEY ========================
Write-Log "Raw project_path received: '$project_path'"

try {
    # Convert to absolute path + resolve project.json if folder given
    $resolvedProject = Resolve-Path $project_path -ErrorAction Stop

    if (Test-Path $resolvedProject -PathType Container) {
        # If it's a folder → append project.json (UiPath CLI accepts both folder & file)
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

# ======================== BUILD ARGUMENTS - NO QUOTES, NO ESCAPING ========================
$args = @(
    "package"
    "pack"
    $resolvedProject          # ← absolute, clean, no quotes added
    "--output"
    $destination_folder       # ← clean
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
