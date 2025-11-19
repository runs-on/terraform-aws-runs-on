#!/bin/bash
# user-data-linux.sh
# User data script for RunsOn Linux runners

set -e

# RunsOn configuration
export RUNS_ON_APP_TAG="${app_tag}"
export RUNS_ON_BOOTSTRAP_TAG="${bootstrap_tag}"
export RUNS_ON_CONFIG_BUCKET="${config_bucket}"
export RUNS_ON_CACHE_BUCKET="${cache_bucket}"
export RUNS_ON_REGION="${region}"
export RUNS_ON_LOG_GROUP="${log_group}"
export RUNS_ON_DEBUG="${app_debug}"
export RUNS_ON_RUNNER_MAX_RUNTIME="${runner_max_runtime}"
export RUNS_ON_LOG_GROUP_NAME="${log_group}"

# Optional: EFS configuration
%{ if efs_file_system_id != "" ~}
export RUNS_ON_EFS_ID="${efs_file_system_id}"
export RUNS_ON_EFS_MOUNT_POINT="/mnt/efs"
%{ endif ~}

# Optional: Ephemeral registry configuration
%{ if ephemeral_registry_uri != "" ~}
export RUNS_ON_EPHEMERAL_REGISTRY="${ephemeral_registry_uri}"
%{ endif ~}

# Bootstrap binary location
BOOTSTRAP_BIN=/usr/local/bin/runs-on-bootstrap

# Setup shutdown trap - auto-shutdown on exit unless debug mode is enabled
_the_end() {
  if [ "$RUNS_ON_DEBUG" != "true" ]; then
    echo "THE END"
    sleep 180
    shutdown -h now
  fi
}
trap _the_end EXIT INT TERM

# Update system
apt-get update -y || yum update -y

# Install CloudWatch Logs agent
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Configure CloudWatch Logs
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/runs-on.log",
            "log_group_name": "$${RUNS_ON_LOG_GROUP}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# Mount EFS if configured
%{ if efs_file_system_id != "" ~}
if [ -n "$${RUNS_ON_EFS_ID}" ]; then
    apt-get install -y nfs-common || yum install -y nfs-utils
    mkdir -p $${RUNS_ON_EFS_MOUNT_POINT}
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
        $${RUNS_ON_EFS_ID}.efs.$${RUNS_ON_REGION}.amazonaws.com:/ $${RUNS_ON_EFS_MOUNT_POINT}
    echo "$${RUNS_ON_EFS_ID}.efs.$${RUNS_ON_REGION}.amazonaws.com:/ $${RUNS_ON_EFS_MOUNT_POINT} nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >> /etc/fstab
fi
%{ endif ~}

# Download RunsOn bootstrap binary from GitHub releases
echo "Downloading RunsOn bootstrap binary..."
if [ ! -f $BOOTSTRAP_BIN ]; then
    time curl -L \
        --connect-timeout 3 \
        --max-time 15 \
        --retry 5 \
        -s "https://github.com/runs-on/bootstrap/releases/download/$${RUNS_ON_BOOTSTRAP_TAG}/bootstrap-$${RUNS_ON_BOOTSTRAP_TAG}-linux-$(uname -m)" \
        -o $BOOTSTRAP_BIN
fi

# Make bootstrap binary executable
chmod a+x $BOOTSTRAP_BIN

# Run bootstrap with proper flags
echo "Running RunsOn bootstrap..."
$BOOTSTRAP_BIN \
    --debug=$${RUNS_ON_DEBUG} \
    --exec \
    --post-exec shutdown \
    "s3://$${RUNS_ON_CONFIG_BUCKET}/agents/$${RUNS_ON_APP_TAG}/agent-linux-$(uname -m)" \
    2>&1 | tee /var/log/runs-on.log

echo "RunsOn runner initialization complete"
