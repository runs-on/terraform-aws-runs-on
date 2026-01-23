<powershell>
Get-Date -format s
$env:RUNS_ON_RUNNER_MAX_RUNTIME = "${runner_max_runtime}"
$env:RUNS_ON_LOG_GROUP_NAME = "${log_group}"
$env:RUNS_ON_DEBUG = "${app_debug}"
$env:AWS_REGION = "${region}"
%{ if efs_file_system_id != "" }$env:RUNS_ON_EFS_ID = "${efs_file_system_id}"%{ endif }
%{ if ephemeral_registry_uri != "" }$env:RUNS_ON_ECR_CACHE = "${ephemeral_registry_uri}"%{ endif }
# Enable and start SSM Agent service
try {
  Set-Service -Name "AmazonSSMAgent" -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service -Name "AmazonSSMAgent" -ErrorAction SilentlyContinue
  Write-Output "SSM Agent service enabled and started"
} catch {
  Write-Output "Warning: Failed to start SSM Agent service: $($_.Exception.Message)"
}
$bootstrapBin = "C:\runs-on\bootstrap-${bootstrap_tag}.exe"
try {
  New-Item -ItemType Directory -Force -Path (Split-Path $bootstrapBin)
  if (-not (Test-Path $bootstrapBin)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri "https://github.com/runs-on/bootstrap/releases/download/${bootstrap_tag}/bootstrap-${bootstrap_tag}-windows-$env:PROCESSOR_ARCHITECTURE.exe" -OutFile $bootstrapBin -UseBasicParsing
  }
  Add-MpPreference -ExclusionProcess $bootstrapBin
  & $bootstrapBin --debug=${app_debug} --exec --post-exec shutdown "s3://${config_bucket}/agents/${app_tag}/agent-windows-$env:PROCESSOR_ARCHITECTURE.exe"
} finally {
  if ($env:RUNS_ON_DEBUG -ne "true") {
    Write-Output "user-data: Going to shut down in a few seconds..."
    Start-Sleep -Seconds 180
    Stop-Computer -Force
  }
}
</powershell>
<detach>true</detach>
<persist>true</persist>
