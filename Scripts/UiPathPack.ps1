<#
.SYNOPSIS
    Pack UiPath project into a NuGet package (*.nupkg)
.DESCRIPTION
    Uses UiPath CLI (auto-downloaded from GitHub) to package the project.
#>

Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$project_path = "",

    [Parameter(Mandatory=$true)]
    [string]$destination_folder = "",

    # Library publishing (optional)
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

# ──────────────────────────────────────────────────────────────
# Logging function
# ──────────────────────────────────────────────────────────────
function WriteLog {
    param ([string]$message, [switch]$err)
    $now = Get-Date -Format "G"
    $line = "$now`t$message"
    Add-Content -Path $debugLog -Value $line -Encoding UTF8
    if ($err) { Write-Host $line -ForegroundColor Red } else { Write-Host $line }
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog   = "$scriptPath\orchestrator-package-pack.log"

# ──────────────────────────────────────────────────────────────
# CLI Setup – prefer GitHub releases (more reliable)
# ──────────────────────────────────────────────────────────────
if ($uipathCliFilePath -and (Test-Path $uipathCliFilePath -PathType Leaf)) {
    $uipathCLI = $uipathCliFilePath
    WriteLog "Using provided CLI: $uipathCLI"
} else {
    $cliVersion = if ($SpecificCLIVersion) { $SpecificCLIVersion } else { "v2.0.50" }  # update to latest from https://github.com/UiPath/uipathcli/releases
    $cliFolder  = "$scriptPath\uipathcli\$cliVersion"
    $uipathCLI  = "$cliFolder\uipcli.exe"

    if (-not (Test-Path $uipathCLI -PathType Leaf)) {
        WriteLog "Downloading UiPath CLI from GitHub ($cliVersion)..."
        New-Item -Path $cliFolder -ItemType Directory -Force | Out-Null
        $zipPath = "$cliFolder\cli.zip"
        $zipUrl  = "https://github.com/UiPath/uipathcli/releases/download/$cliVersion/uipathcli-windows-amd64.zip"

        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $cliFolder -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

            # Debug: show what was extracted
            WriteLog "Extracted files:"
            Get-ChildItem -Path $cliFolder -Recurse -File | ForEach-Object {
                WriteLog "  $($_.FullName)  (size: $($_.Length) bytes)"
            }

            # Auto-detect exe (in case it's not directly in root)
            $foundExe = Get-ChildItem -Path $cliFolder -Recurse -File -Filter "uipcli.exe" -ErrorAction SilentlyContinue |
                        Select-Object -First 1 -ExpandProperty FullName

            if ($foundExe) {
                $uipathCLI = $foundExe
                WriteLog "uipcli.exe detected at: $uipathCLI"
            } else {
                WriteLog "ERROR: uipcli.exe not found after extraction!" -err
                exit 1
            }
        }
        catch {
            WriteLog "Download or extraction failed: $($_.Exception.Message)" -err
            exit 1
        }
    } else {
        WriteLog "Using existing CLI: $uipathCLI"
    }
}

# ──────────────────────────────────────────────────────────────
# Validate & normalize project path
# ──────────────────────────────────────────────────────────────
if (-not $project_path -or -not $destination_folder) {
    WriteLog "Missing required parameters: project_path and destination_folder" -err
    exit 1
}

$resolvedProject = Resolve-Path $project_path -ErrorAction SilentlyContinue
if (-not $resolvedProject) {
    WriteLog "Invalid project_path: $project_path" -err
    exit 1
}

# If folder → look for project.json inside
if ((Get-Item $resolvedProject).PSIsContainer) {
    $projectJson = Join-Path $resolvedProject "project.json"
    if (Test-Path $projectJson) {
        $resolvedProject = $projectJson
    } else {
        WriteLog "No project.json found in folder: $resolvedProject" -err
        exit 1
    }
}

# Ensure output folder exists
New-Item -Path $destination_folder -ItemType Directory -Force | Out-Null

WriteLog "-----------------------------------------------------------------------------"
WriteLog "uipcli location : $uipathCLI"
WriteLog "project path    : $resolvedProject"
WriteLog "output folder   : $destination_folder"

# ──────────────────────────────────────────────────────────────
# Build arguments – NO manual quotes!
# ──────────────────────────────────────────────────────────────
$ParamList = New-Object 'System.Collections.Generic.List[string]'

$ParamList.Add("package")
$ParamList.Add("pack")
$ParamList.Add($resolvedProject)
$ParamList.Add("--output")
$ParamList.Add($destination_folder)

if ($libraryOrchestratorUrl)              { $ParamList.AddRange(@("--libraryOrchestratorUrl",              $libraryOrchestratorUrl)) }
if ($libraryOrchestratorTenant)           { $ParamList.AddRange(@("--libraryOrchestratorTenant",           $libraryOrchestratorTenant)) }
if ($libraryOrchestratorAccountForApp)    { $ParamList.AddRange(@("--libraryOrchestratorAccountForApp",    $libraryOrchestratorAccountForApp)) }
if ($libraryOrchestratorApplicationId)    { $ParamList.AddRange(@("--libraryOrchestratorApplicationId",    $libraryOrchestratorApplicationId)) }
if ($libraryOrchestratorApplicationSecret){ $ParamList.AddRange(@("--libraryOrchestratorApplicationSecret",$libraryOrchestratorApplicationSecret)) }
if ($libraryOrchestratorApplicationScope) { $ParamList.AddRange(@("--libraryOrchestratorApplicationScope", $libraryOrchestratorApplicationScope)) }
if ($libraryOrchestratorUsername)         { $ParamList.AddRange(@("--libraryOrchestratorUsername",         $libraryOrchestratorUsername)) }
if ($libraryOrchestratorPassword)         { $ParamList.AddRange(@("--libraryOrchestratorPassword",         $libraryOrchestratorPassword)) }
if ($libraryOrchestratorUserKey)          { $ParamList.AddRange(@("--libraryOrchestratorAuthToken",        $libraryOrchestratorUserKey)) }
if ($libraryOrchestratorAccountName)      { $ParamList.AddRange(@("--libraryOrchestratorAccountName",      $libraryOrchestratorAccountName)) }
if ($libraryOrchestratorFolder)           { $ParamList.AddRange(@("--libraryOrchestratorFolder",           $libraryOrchestratorFolder)) }
if ($language)                            { $ParamList.AddRange(@("--language",                            $language)) }
if ($version)                             { $ParamList.AddRange(@("--version",                             $version)) }
if ($autoVersion.IsPresent)               { $ParamList.Add("--autoVersion") }
if ($outputType)                          { $ParamList.AddRange(@("--outputType",                          $outputType)) }
if ($disableTelemetry)                    { $ParamList.AddRange(@("--disableTelemetry",                    $disableTelemetry)) }

# ──────────────────────────────────────────────────────────────
# Mask secrets for log only
# ──────────────────────────────────────────────────────────────
$ParamMask = $ParamList.ToArray().PSObject.Copy()

$secrets = @("--libraryOrchestratorPassword", "--libraryOrchestratorAuthToken", "--libraryOrchestratorApplicationSecret")
for ($i = 0; $i -lt $ParamMask.Count; $i++) {
    if ($secrets -contains $ParamMask[$i]) {
        $ParamMask[$i+1] = "***************"
        $i++  # skip value
    }
}

WriteLog "Executing: $uipathCLI $($ParamMask -join ' ')"
WriteLog "-----------------------------------------------------------------------------"

# ──────────────────────────────────────────────────────────────
# Execute
# ──────────────────────────────────────────────────────────────
& $uipathCLI $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Done! Package(s) destination folder is : $destination_folder"
    Exit 0
} else {
    WriteLog "Unable to Pack project. Exit code $LASTEXITCODE" -err
    Exit 1
}
