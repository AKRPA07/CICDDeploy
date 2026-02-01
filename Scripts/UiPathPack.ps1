<#
.SYNOPSIS
    Pack project into a NuGet package (*.nupkg)
.DESCRIPTION
    Uses UiPath CLI to package the project (auto-downloads from GitHub if needed).
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

# ─── CLI Setup (GitHub – reliable in 2026) ───────────────────────
if ($uipathCliFilePath -and (Test-Path $uipathCliFilePath -PathType Leaf)) {
    $uipathCLI = $uipathCliFilePath
} else {
    $cliVersion = if ($SpecificCLIVersion) { $SpecificCLIVersion } else { "v2.0.50" }
    $cliFolder  = "$scriptPath\uipathcli\$cliVersion"
    $uipathCLI  = "$cliFolder\uipcli.exe"

    if (-not (Test-Path $uipathCLI -PathType Leaf)) {
        WriteLog "Downloading UiPath CLI v$cliVersion from GitHub..."
        New-Item -Path $cliFolder -ItemType Directory -Force | Out-Null
        $zipPath = "$cliFolder\cli.zip"
        $zipUrl  = "https://github.com/UiPath/uipathcli/releases/download/v$cliVersion/uipathcli-windows-amd64.zip"

        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $cliFolder -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

            WriteLog "Extracted files in $cliFolder:"
            Get-ChildItem -Path $cliFolder -Recurse -File | ForEach-Object {
                WriteLog "  $($_.FullName)"
            }

            $found = Get-ChildItem -Path $cliFolder -Recurse -Filter "uipcli.exe" | Select-Object -First 1 -ExpandProperty FullName
            if ($found) {
                $uipathCLI = $found
                WriteLog "uipcli.exe found at: $uipathCLI"
            } else {
                WriteLog "No uipcli.exe after extraction!" -err
                exit 1
            }
        }
        catch {
            WriteLog "Download failed: $($_.Exception.Message)" -err
            exit 1
        }
    }
}

WriteLog "uipcli location : $uipathCLI"

# ─── Validate & resolve paths ────────────────────────────────────
if (-not $project_path -or -not $destination_folder) {
    WriteLog "Missing project_path or destination_folder" -err
    exit 1
}

$resolvedProject = Resolve-Path $project_path -ErrorAction SilentlyContinue
if (-not $resolvedProject) {
    WriteLog "Cannot resolve project_path: $project_path" -err
    exit 1
}

if ((Get-Item $resolvedProject).PSIsContainer) {
    $pj = Join-Path $resolvedProject "project.json"
    if (Test-Path $pj) { $resolvedProject = $pj } else {
        WriteLog "No project.json in folder: $resolvedProject" -err
        exit 1
    }
}

New-Item -Path $destination_folder -ItemType Directory -Force | Out-Null

WriteLog "project resolved : $resolvedProject"
WriteLog "output folder    : $destination_folder"

# ─── Build args (clean – no quotes!) ─────────────────────────────
$ParamList = New-Object 'System.Collections.Generic.List[string]'

$ParamList.Add("package")
$ParamList.Add("pack")
$ParamList.Add($resolvedProject)
$ParamList.Add("--output")
$ParamList.Add($destination_folder)

if ($libraryOrchestratorUrl)              { $ParamList.Add("--libraryOrchestratorUrl")     ; $ParamList.Add($libraryOrchestratorUrl) }
if ($libraryOrchestratorTenant)           { $ParamList.Add("--libraryOrchestratorTenant")  ; $ParamList.Add($libraryOrchestratorTenant) }
if ($libraryOrchestratorAccountForApp)    { $ParamList.Add("--libraryOrchestratorAccountForApp") ; $ParamList.Add($libraryOrchestratorAccountForApp) }
if ($libraryOrchestratorApplicationId)    { $ParamList.Add("--libraryOrchestratorApplicationId") ; $ParamList.Add($libraryOrchestratorApplicationId) }
if ($libraryOrchestratorApplicationSecret){ $ParamList.Add("--libraryOrchestratorApplicationSecret") ; $ParamList.Add($libraryOrchestratorApplicationSecret) }
if ($libraryOrchestratorApplicationScope) { $ParamList.Add("--libraryOrchestratorApplicationScope") ; $ParamList.Add($libraryOrchestratorApplicationScope) }
if ($libraryOrchestratorUsername)         { $ParamList.Add("--libraryOrchestratorUsername") ; $ParamList.Add($libraryOrchestratorUsername) }
if ($libraryOrchestratorPassword)         { $ParamList.Add("--libraryOrchestratorPassword") ; $ParamList.Add($libraryOrchestratorPassword) }
if ($libraryOrchestratorUserKey)          { $ParamList.Add("--libraryOrchestratorAuthToken") ; $ParamList.Add($libraryOrchestratorUserKey) }
if ($libraryOrchestratorAccountName)      { $ParamList.Add("--libraryOrchestratorAccountName") ; $ParamList.Add($libraryOrchestratorAccountName) }
if ($libraryOrchestratorFolder)           { $ParamList.Add("--libraryOrchestratorFolder")  ; $ParamList.Add($libraryOrchestratorFolder) }
if ($language)                            { $ParamList.Add("--language")                   ; $ParamList.Add($language) }
if ($version)                             { $ParamList.Add("--version")                    ; $ParamList.Add($version) }
if ($autoVersion)                         { $ParamList.Add("--autoVersion") }
if ($outputType)                          { $ParamList.Add("--outputType")                 ; $ParamList.Add($outputType) }
if ($disableTelemetry)                    { $ParamList.Add("--disableTelemetry")          ; $ParamList.Add($disableTelemetry) }

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

# ─── Run ─────────────────────────────────────────────────────────
& $uipathCLI $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Done! Packages in $destination_folder"
    Exit 0
} else {
    WriteLog "Pack failed – exit $LASTEXITCODE" -err
    Exit 1
}
