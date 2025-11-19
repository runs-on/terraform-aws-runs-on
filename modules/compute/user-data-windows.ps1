# user-data-windows.ps1
# User data script for RunsOn Windows runners

<powershell>

# RunsOn configuration
$env:RUNS_ON_APP_TAG = "${app_tag}"
$env:RUNS_ON_BOOTSTRAP_TAG = "${bootstrap_tag}"
$env:RUNS_ON_CONFIG_BUCKET = "${config_bucket}"
$env:RUNS_ON_CACHE_BUCKET = "${cache_bucket}"
$env:RUNS_ON_REGION = "${region}"
$env:RUNS_ON_LOG_GROUP = "${log_group}"
$env:RUNS_ON_DEBUG = "${app_debug}"
$env:RUNS_ON_RUNNER_MAX_RUNTIME = "${runner_max_runtime}"
$env:RUNS_ON_LOG_GROUP_NAME = "${log_group}"

# Optional: EFS configuration (environment variable only for Windows)
%{ if efs_file_system_id != "" ~}
$env:RUNS_ON_EFS_ID = "${efs_file_system_id}"
%{ endif ~}

# Optional: Ephemeral registry configuration
%{ if ephemeral_registry_uri != "" ~}
$env:RUNS_ON_EPHEMERAL_REGISTRY = "${ephemeral_registry_uri}"
%{ endif ~}

# Set error action preference
$ErrorActionPreference = "Stop"

# Bootstrap binary location
$BootstrapBin = "C:\runs-on\bootstrap.exe"

# Create directories
New-Item -ItemType Directory -Force -Path C:\runs-on\logs | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $BootstrapBin) | Out-Null
$LogFile = "C:\runs-on\logs\bootstrap.log"

function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

# Setup shutdown function - auto-shutdown on exit unless debug mode is enabled
function Invoke-TheEnd {
    if ($env:RUNS_ON_DEBUG -ne "true") {
        Write-Log "THE END"
        Start-Sleep -Seconds 180
        Stop-Computer -Force
    }
}

# Register shutdown handler
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Invoke-TheEnd
}

Write-Log "Starting RunsOn Windows runner initialization..."

# Install AWS CLI if not present
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Log "Installing AWS CLI..."
    $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $installerPath = "$env:TEMP\AWSCLIV2.msi"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
    Start-Process msiexec.exe -ArgumentList "/i $installerPath /quiet /norestart" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Download RunsOn bootstrap binary from GitHub releases
Write-Log "Downloading RunsOn bootstrap binary..."
try {
    if (-not (Test-Path $BootstrapBin)) {
        $arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
        $bootstrapUrl = "https://github.com/runs-on/bootstrap/releases/download/$env:RUNS_ON_BOOTSTRAP_TAG/bootstrap-$env:RUNS_ON_BOOTSTRAP_TAG-windows-$arch.exe"

        # Download with retry logic
        $maxRetries = 5
        $retryCount = 0
        $downloaded = $false

        while (-not $downloaded -and $retryCount -lt $maxRetries) {
            try {
                Invoke-WebRequest -Uri $bootstrapUrl -OutFile $BootstrapBin -TimeoutSec 15
                $downloaded = $true
            }
            catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Log "Download failed, retrying ($retryCount/$maxRetries)..."
                    Start-Sleep -Seconds 3
                }
                else {
                    throw
                }
            }
        }
    }

    Write-Log "Running RunsOn bootstrap..."
    $agentUrl = "s3://$env:RUNS_ON_CONFIG_BUCKET/agents/$env:RUNS_ON_APP_TAG/agent-windows-x86_64.exe"

    & $BootstrapBin `
        --debug=$env:RUNS_ON_DEBUG `
        --exec `
        --post-exec shutdown `
        $agentUrl `
        *>> $LogFile

    Write-Log "RunsOn runner initialization complete"
}
catch {
    Write-Log "ERROR: Bootstrap failed - $_"
    Invoke-TheEnd
    exit 1
}

</powershell>
