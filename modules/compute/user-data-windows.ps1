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

# Create log directory
New-Item -ItemType Directory -Force -Path C:\runs-on\logs | Out-Null
$LogFile = "C:\runs-on\logs\bootstrap.log"

function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
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

# Download and run RunsOn bootstrap script
Write-Log "Downloading RunsOn bootstrap script..."
try {
    $bootstrapScript = "C:\runs-on\bootstrap.ps1"
    New-Item -ItemType Directory -Force -Path C:\runs-on | Out-Null

    aws s3 cp "s3://$env:RUNS_ON_CONFIG_BUCKET/agents/$env:RUNS_ON_BOOTSTRAP_TAG/bootstrap-windows.ps1" $bootstrapScript

    Write-Log "Running RunsOn bootstrap..."
    & $bootstrapScript *>> $LogFile

    Write-Log "RunsOn runner initialization complete"
}
catch {
    Write-Log "ERROR: Bootstrap failed - $_"
    exit 1
}

</powershell>
