#!/bin/bash -ex
date -u
BOOTSTRAP_BIN=/usr/local/bin/runs-on-bootstrap-${bootstrap_tag}
export RUNS_ON_RUNNER_MAX_RUNTIME="${runner_max_runtime}"
export RUNS_ON_LOG_GROUP_NAME="${log_group}"
export RUNS_ON_DEBUG="${app_debug}"
export AWS_REGION="${region}"
%{ if efs_file_system_id != "" }export RUNS_ON_EFS_ID="${efs_file_system_id}"%{ endif }
%{ if ephemeral_registry_uri != "" }export RUNS_ON_ECR_CACHE="${ephemeral_registry_uri}"%{ endif }
_the_end() { if [ "$RUNS_ON_DEBUG" != "true" ] ; then echo "THE END" ; sleep 180 ; shutdown -h now ; fi ; } ; trap _the_end EXIT INT TERM
test -f $BOOTSTRAP_BIN || time curl -L --connect-timeout 3 --max-time 15 --retry 5 -s https://github.com/runs-on/bootstrap/releases/download/${bootstrap_tag}/bootstrap-${bootstrap_tag}-linux-$(uname -m) -o $BOOTSTRAP_BIN
chmod a+x $BOOTSTRAP_BIN && $BOOTSTRAP_BIN --debug=${app_debug} --exec --post-exec shutdown "s3://${config_bucket}/agents/${app_tag}/agent-linux-$(uname -m)"
