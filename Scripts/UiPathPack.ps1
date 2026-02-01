<#
.SYNOPSIS
    Pack UiPath project into NuGet package (*.nupkg)
.DESCRIPTION
    Auto-downloads uipathcli from GitHub releases and packs the project.
#>

Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$project_path = "",

    [Parameter(Mandatory=$true)]
    [string]$destination_folder = "",

    [string]$libraryOrchestratorUrl = "",
    [string]$libraryOrchestratorTenant = "",
    [string]$libraryOrchestratorAccountForApp = "",
    [string]$libraryOrchestratorApplicationId = "",
    [string]$libraryOrchestratorApplicationSecret = "",
    [string]$libraryOrchestratorApplicationScope = "",
    [string]$libraryOrchestratorUsername = "",
    [string]$libraryOrchestratorPassword = "",
    [string]$libraryOrchestratorUserKey = "",
    [string]$libraryOrchestratorAccountName = "",
    [string]$libraryOrchestratorFolder = "",

    [string]$version = "",
    [switch]$autoVersion,
    [string]$outputType = "",
    [string]$language = "",
    [string]$disableTelemetry = "",

    [string]$uipathCliFilePath = "",
    [string]$SpecificCLIVersion = ""
)

function WriteLog {
    param ([string]$message, [switch]$err)
    $now = Get-Date -Format "G"
    $line = "$now`t$message"
    Add-Content -Path $debugLog -Value $line -Encoding UTF8
    if ($err) { Write-Host $line -ForegroundColor Red } else { Write-Host $line }
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog   = "$scriptPath\orchestrator-package-pack.log"

# ─── CLI Setup ───────────────────────────────────────────────────
if ($uipathCliFilePath -and (Test-Path $uipathCliFilePath -PathType Leaf)) {
    $uipathCLI = $uipathCliFilePath
    WriteLog "Using provided CLI: $uipathCLI"
} else {
    $cliVersion = if ($SpecificCLIVersion) { $SpecificCLIVersion } else { "v2.0.50" }  # latest stable ~ late 2025; update from https://github.com/UiPath/uipathcli/releases if needed
    $cliFolder  = "$scriptPath\uipathcli\$cliVersion"
    $zipPath    = "$cliFolder\cli.zip"

    if (-not (Test-Path "$cliFolder\uipcli.exe" -PathType Leaf)) {
        WriteLog "Downloading UiPath CLI v$cliVersion from GitHub..."
        New-Item -Path $cliFolder -ItemType Directory -Force | Out-Null

        $zipUrl = "https://github.com/UiPath/uipathcli/releases/download/v$cliVersion/uipathcli-windows-amd64.zip"

        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $cliFolder -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

            # Debug: list everything extracted
            WriteLog "Extracted contents:"
            Get-ChildItem -Path $cliFolder -Recurse -File | ForEach-Object {
                WriteLog "  $($_.FullName)  (size $($_.Length) bytes)"
            }

            # Auto-find the exe (usually in root, but search to be safe)
            $foundExe = Get-ChildItem -Path $cliFolder -Recurse -File -Filter "uipcli.exe" -ErrorAction SilentlyContinue | 
                        Select-Object -First 1 -ExpandProperty FullName

            if ($foundExe) {
                $uipathCLI = $foundExe
                WriteLog "uipcli.exe located at: $uipathCLI"
            } else {
                WriteLog "ERROR: uipcli.exe NOT FOUND in $cliFolder after extraction" -err
                exit 1
            }
        }
        catch {
            WriteLog "Download/extract failed: $($_.Exception.Message)" -err
            exit 1
        }
    } else {
        $uipathCLI = "$cliFolder\uipcli.exe"
        WriteLog "Using cached CLI: $uipathCLI"
    }
}

# ─── Path Validation & Normalization ─────────────────────────────
if (-not $project_path -or -not $destination_folder) {
    WriteLog "Missing project_path or destination_folder" -err
    exit 1
}

try {
    $resolvedProject = Resolve-Path $project_path
    if ((Get-Item $resolvedProject).PSIsContainer) {
        $pj = Join-Path $resolvedProject "project.json"
        if (Test-Path $pj) { $resolvedProject = $pj } else { throw "No project.json in folder" }
    }
    WriteLog "Resolved project path: $resolvedProject"
} catch {
    WriteLog "Path error: $($_.Exception.Message)" -err
    exit 1
}

New-Item -Path $destination_folder -ItemType Directory -Force | Out-Null

# ─── Build clean arguments ───────────────────────────────────────
$ParamList = New-Object 'System.Collections.Generic.List[string]'

$ParamList.Add("package")
$ParamList.Add("pack")
$ParamList.Add($resolvedProject)
$ParamList.Add("--output")
$ParamList.Add($destination_folder)

# Optional params (clean addition)
if ($libraryOrchestratorUrl)              { $ParamList.Add("--libraryOrchestratorUrl");              $ParamList.Add($libraryOrchestratorUrl) }
if ($libraryOrchestratorTenant)           { $ParamList.Add("--libraryOrchestratorTenant");           $ParamList.Add($libraryOrchestratorTenant) }
if ($libraryOrchestratorAccountForApp)    { $ParamList.Add("--libraryOrchestratorAccountForApp");    $ParamList.Add($libraryOrchestratorAccountForApp) }
if ($libraryOrchestratorApplicationId)    { $ParamList.Add("--libraryOrchestratorApplicationId");    $ParamList.Add($libraryOrchestratorApplicationId) }
if ($libraryOrchestratorApplicationSecret){ $ParamList.Add("--libraryOrchestratorApplicationSecret");$ParamList.Add($libraryOrchestratorApplicationSecret) }
if ($libraryOrchestratorApplicationScope) { $ParamList.Add("--libraryOrchestratorApplicationScope"); $ParamList.Add($libraryOrchestratorApplicationScope) }
if ($libraryOrchestratorUsername)         { $ParamList.Add("--libraryOrchestratorUsername");         $ParamList.Add($libraryOrchestratorUsername) }
if ($libraryOrchestratorPassword)         { $ParamList.Add("--libraryOrchestratorPassword");         $ParamList.Add($libraryOrchestratorPassword) }
if ($libraryOrchestratorUserKey)          { $ParamList.Add("--libraryOrchestratorAuthToken");        $ParamList.Add($libraryOrchestratorUserKey) }
if ($libraryOrchestratorAccountName)      { $ParamList.Add("--libraryOrchestratorAccountName");      $ParamList.Add($libraryOrchestratorAccountName) }
if ($libraryOrchestratorFolder)           { $ParamList.Add("--libraryOrchestratorFolder");           $ParamList.Add($libraryOrchestratorFolder) }
if ($language)                            { $ParamList.Add("--language");                            $ParamList.Add($language) }
if ($version)                             { $ParamList.Add("--version");                             $ParamList.Add($version) }
if ($autoVersion)                         { $ParamList.Add("--autoVersion") }
if ($outputType)                          { $ParamList.Add("--outputType");                          $ParamList.Add($outputType) }
if ($disableTelemetry)                    { $ParamList.Add("--disableTelemetry");                    $ParamList.Add($disableTelemetry) }

# ─── Masking for log ─────────────────────────────────────────────
$ParamMask = $ParamList.ToArray().PSObject.Copy()
$secrets = @("--libraryOrchestratorPassword", "--libraryOrchestratorAuthToken", "--libraryOrchestratorApplicationSecret")
for ($i = 0; $i -lt $ParamMask.Count; $i++) {
    if ($secrets -contains $ParamMask[$i]) {
        $ParamMask[$i+1] = "********"
        $i++
    }
}

WriteLog "Executing: $uipathCLI $($ParamMask -join ' ')"
WriteLog "-----------------------------------------------------------------------------"

# Final existence check before run
if (-not (Test-Path $uipathCLI -PathType Leaf)) {
    WriteLog "CRITICAL: uipcli.exe missing at $uipathCLI" -err
    exit 1
}

# ─── Execute ─────────────────────────────────────────────────────
& $uipathCLI $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Success – check $destination_folder for .nupkg"
    Exit 0
} else {
    WriteLog "Failed – exit code $LASTEXITCODE" -err
    Exit 1
}
