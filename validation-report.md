# CloudFormation vs Tofu Validation Report

**Generated:** 2025-11-19 17:11:11
**CloudFormation Stack:** runs-on
**Tofu Directory:** examples/complete
**AWS Region:** us-east-1

---

## Executive Summary

### CloudFormation Stack

- **Parameters:** 58
- **Resources:** 65

### Tofu Plan

- **Resource Changes:** 93

---

## CloudFormation Parameters

```json
{
  "RunnerMaxRuntime": "720",
  "VpcCidrBlock": "10.1.0.0/16",
  "VpcEndpoints": "none",
  "AppRegistry": "public.ecr.aws/c5h5o9k1/runs-on/runs-on",
  "EnableEfs": "false",
  "RunnerDefaultDiskSize": "40",
  "RunnerConfigAutoExtendsFrom": ".github-private",
  "RunnerCustomTags": "",
  "DefaultAdmins": "",
  "VpcFlowLogRetentionInDays": "7",
  "DefaultPermissionBoundaryArn": "",
  "Ipv6Enabled": "false",
  "OtelExporterEndpoint": "",
  "VpcCidrSubnetBits": "12",
  "NatGatewayAvailability": "SingleAZ",
  "SSHAllowed": "true",
  "Private": "false",
  "EnableEphemeralRegistry": "false",
  "AlertTopicSlackWebhookUrl": "****",
  "AppEc2QueueSize": "2",
  "AppDebug": "false",
  "SqsQueueOldestMessageThresholdSeconds": "0",
  "Ec2LogRetentionInDays": "7",
  "GithubOrganization": "sjysngh",
  "AppMemory": "512",
  "EmailAddress": "sujoy@wrytrsblck.com",
  "AppCPU": "256",
  "LoggerLevel": "info",
  "AppAlarmDailyMinutes": "4000",
  "EC2InstanceCustomPolicy": "",
  "VpcFlowLogFormat": "",
  "AppGithubApiStrategy": "normal",
  "AppCustomPolicy": "",
  "EnableDashboard": "false",
  "Environment": "production",
  "IntegrationStepSecurityApiKey": "",
  "ECInstanceDetailedMonitoring": "false",
  "CostReportsEnabled": "true",
  "CostAllocationTag": "stack",
  "NetworkingStack": "embedded",
  "AlertTopicSubscriptionHttpsEndpoint": "",
  "RunnerLargeVolumeThroughput": "750",
  "EncryptEbs": "false",
  "ExternalVpcId": "",
  "VpcFlowLogS3BucketArn": "",
  "ServerPassword": "****",
  "OtelExporterHeaders": "****",
  "ExternalVpcSecurityGroupId": "",
  "SpotCircuitBreaker": "2/15/30",
  "RunnerDefaultVolumeThroughput": "400",
  "S3CacheExpirationInDays": "10",
  "ExternalVpcPublicSubnetIds": "",
  "SSHCidrRange": "0.0.0.0/0",
  "NatGatewayElasticIPCount": "1",
  "RunnerLargeDiskSize": "80",
  "GithubEnterpriseUrl": "",
  "LicenseKey": "D81031FF-5DE0-466A-807C-C81A36CB5967",
  "ExternalVpcPrivateSubnetIds": ""
}
```

---

## Parameter Mapping Analysis

```
  ✓ AlertTopicSlackWebhookUrl → slack_webhook_url
  ✓ AlertTopicSubscriptionHttpsEndpoint → https_endpoint
  ❌ AppAlarmDailyMinutes: MISSING in Terraform
  ✓ AppCPU → app_cpu
  ⚠️  AppCustomPolicy: No Terraform equivalent
  ✓ AppDebug → app_debug
  ✓ AppEc2QueueSize → app_ec2_queue_size
  ✓ AppGithubApiStrategy → app_github_api_strategy
  ✓ AppMemory → app_memory
  ⚠️  AppRegistry: No Terraform equivalent
  ✓ CostAllocationTag → cost_allocation_tag
  ✓ CostReportsEnabled → cost_reports_enabled
  ✓ DefaultAdmins → default_admins
  ✓ DefaultPermissionBoundaryArn → default_permission_boundary_arn
  ✓ EC2InstanceCustomPolicy → ec2_instance_custom_policy
  ✓ ECInstanceDetailedMonitoring → ec2_instance_detailed_monitoring
  ✓ Ec2LogRetentionInDays → ec2_log_retention_days
  ✓ EmailAddress → email_address
  ❌ EnableDashboard: MISSING in Terraform
  ✓ EnableEfs → enable_efs
  ✓ EnableEphemeralRegistry → enable_ecr
  ✓ EncryptEbs → ebs_kms_key_arn
  ✓ Environment → environment
  ✓ ExternalVpcId → vpc_id
  ✓ ExternalVpcPrivateSubnetIds → private_subnet_ids
  ✓ ExternalVpcPublicSubnetIds → public_subnet_ids
  ✓ ExternalVpcSecurityGroupId → security_group_ids
  ✓ GithubEnterpriseUrl → github_enterprise_url
  ✓ GithubOrganization → github_organization
  ✓ IntegrationStepSecurityApiKey → integration_step_security_api_key
  ✓ Ipv6Enabled → ipv6_enabled
  ✓ LicenseKey → license_key
  ✓ LoggerLevel → logger_level
  ⚠️  NatGatewayAvailability: No Terraform equivalent
  ⚠️  NatGatewayElasticIPCount: No Terraform equivalent
  ⚠️  NetworkingStack: No Terraform equivalent
  ✓ OtelExporterEndpoint → otel_exporter_endpoint
  ✓ OtelExporterHeaders → otel_exporter_headers
  ✓ Private → private_mode
  ✓ RunnerConfigAutoExtendsFrom → runner_config_auto_extends_from
  ✓ RunnerCustomTags → runner_custom_tags
  ✓ RunnerDefaultDiskSize → runner_default_disk_size
  ✓ RunnerDefaultVolumeThroughput → runner_default_volume_throughput
  ✓ RunnerLargeDiskSize → runner_large_disk_size
  ✓ RunnerLargeVolumeThroughput → runner_large_volume_throughput
  ✓ RunnerMaxRuntime → runner_max_runtime
  ✓ S3CacheExpirationInDays → cache_expiration_days
  ✓ SSHAllowed → ssh_allowed
  ✓ SSHCidrRange → ssh_cidr_range
  ✓ ServerPassword → server_password
  ✓ SpotCircuitBreaker → spot_circuit_breaker
  ❌ SqsQueueOldestMessageThresholdSeconds: MISSING in Terraform
  ⚠️  VpcCidrBlock: No Terraform equivalent
  ⚠️  VpcCidrSubnetBits: No Terraform equivalent
  ⚠️  VpcEndpoints: No Terraform equivalent
  ⚠️  VpcFlowLogFormat: No Terraform equivalent
  ⚠️  VpcFlowLogRetentionInDays: No Terraform equivalent
  ⚠️  VpcFlowLogS3BucketArn: No Terraform equivalent
```

---

## Default Value Comparison

### Comparison Results

```
  ⚠️  AppCPU → app_cpu: CFN default = 256, no default in TF
  ⚠️  AppMemory → app_memory: CFN default = 512, no default in TF
  ⚠️  AppDebug → app_debug: CFN default = false, no default in TF
  ⚠️  AppEc2QueueSize → app_ec2_queue_size: CFN default = 2, no default in TF
  ⚠️  AppGithubApiStrategy → app_github_api_strategy: CFN default = normal, no default in TF
  ⚠️  AppAlarmDailyMinutes → app_alarm_daily_minutes: CFN default = 4000, no default in TF
  ⚠️  CostAllocationTag → cost_allocation_tag: CFN default = stack, no default in TF
  ⚠️  CostReportsEnabled → cost_reports_enabled: CFN default = true, no default in TF
  ⚠️  DefaultAdmins → default_admins: CFN default = , no default in TF
  ⚠️  DefaultPermissionBoundaryArn → default_permission_boundary_arn: CFN default = , no default in TF
  ⚠️  EC2InstanceCustomPolicy → ec2_instance_custom_policy: CFN default = , no default in TF
  ⚠️  ECInstanceDetailedMonitoring → ec2_instance_detailed_monitoring: CFN default = false, no default in TF
  ⚠️  Ec2LogRetentionInDays → ec2_log_retention_days: CFN default = 7, no default in TF
  ⚠️  EnableDashboard → enable_dashboard: CFN default = false, no default in TF
  ⚠️  EnableEfs → enable_efs: CFN default = false, no default in TF
  ⚠️  EnableEphemeralRegistry → enable_ecr: CFN default = false, no default in TF
  ⚠️  EncryptEbs → ebs_kms_key_arn: CFN default = false, no default in TF
  ✓ Environment → environment: production
  ⚠️  GithubEnterpriseUrl → github_enterprise_url: CFN default = , no default in TF
  ⚠️  IntegrationStepSecurityApiKey → integration_step_security_api_key: CFN default = , no default in TF
  ⚠️  Ipv6Enabled → ipv6_enabled: CFN default = false, no default in TF
  ⚠️  LoggerLevel → logger_level: CFN default = info, no default in TF
  ⚠️  OtelExporterEndpoint → otel_exporter_endpoint: CFN default = , no default in TF
  ⚠️  OtelExporterHeaders → otel_exporter_headers: CFN default = , no default in TF
  ⚠️  Private → private_mode: CFN default = false, no default in TF
  ⚠️  RunnerConfigAutoExtendsFrom → runner_config_auto_extends_from: CFN default = .github-private, no default in TF
  ⚠️  RunnerCustomTags → runner_custom_tags: CFN default = [], no default in TF
  ⚠️  RunnerDefaultDiskSize → runner_default_disk_size: CFN default = 40, no default in TF
  ⚠️  RunnerDefaultVolumeThroughput → runner_default_volume_throughput: CFN default = 400, no default in TF
  ⚠️  RunnerLargeDiskSize → runner_large_disk_size: CFN default = 80, no default in TF
  ⚠️  RunnerLargeVolumeThroughput → runner_large_volume_throughput: CFN default = 750, no default in TF
  ⚠️  RunnerMaxRuntime → runner_max_runtime: CFN default = 720, no default in TF
  ⚠️  S3CacheExpirationInDays → cache_expiration_days: CFN default = 10, no default in TF
  ⚠️  ServerPassword → server_password: CFN default = , no default in TF
  ⚠️  SpotCircuitBreaker → spot_circuit_breaker: CFN default = 2/15/30, no default in TF
  ⚠️  SqsQueueOldestMessageThresholdSeconds → sqs_queue_oldest_message_threshold: CFN default = 0, no default in TF
  ✓ SSHAllowed → ssh_allowed: true
  ✓ SSHCidrRange → ssh_cidr_range: 0.0.0.0/0
  ⚠️  AlertTopicSlackWebhookUrl → slack_webhook_url: CFN default = , no default in TF
  ⚠️  AlertTopicSubscriptionHttpsEndpoint → https_endpoint: CFN default = , no default in TF
  ⚠️  ExternalVpcId → vpc_id: CFN default = , no default in TF
  ⚠️  ExternalVpcPublicSubnetIds → public_subnet_ids: CFN default = [], no default in TF
  ⚠️  ExternalVpcPrivateSubnetIds → private_subnet_ids: CFN default = [], no default in TF
  ⚠️  ExternalVpcSecurityGroupId → security_group_ids: CFN default = , no default in TF
```

### CloudFormation Default Values

```json
{
  "GithubEnterpriseUrl": {
    "value": "",
    "type": "String"
  },
  "NetworkingStack": {
    "value": "embedded",
    "type": "String"
  },
  "ExternalVpcId": {
    "value": "",
    "type": "String"
  },
  "ExternalVpcPublicSubnetIds": {
    "value": [],
    "type": "CommaDelimitedList"
  },
  "ExternalVpcPrivateSubnetIds": {
    "value": [],
    "type": "CommaDelimitedList"
  },
  "ExternalVpcSecurityGroupId": {
    "value": "",
    "type": "String"
  },
  "Environment": {
    "value": "production",
    "type": "String"
  },
  "AlertTopicSubscriptionHttpsEndpoint": {
    "value": "",
    "type": "String"
  },
  "AlertTopicSlackWebhookUrl": {
    "value": "",
    "type": "String"
  },
  "VpcCidrBlock": {
    "value": "10.1.0.0/16",
    "type": "String"
  },
  "VpcCidrSubnetBits": {
    "value": 12,
    "type": "Number"
  },
  "Ipv6Enabled": {
    "value": "false",
    "type": "String"
  },
  "SSHAllowed": {
    "value": "true",
    "type": "String"
  },
  "SSHCidrRange": {
    "value": "0.0.0.0/0",
    "type": "String"
  },
  "Private": {
    "value": "false",
    "type": "String"
  },
  "VpcEndpoints": {
    "value": "none",
    "type": "String"
  },
  "NatGatewayElasticIPCount": {
    "value": 1,
    "type": "Number"
  },
  "NatGatewayAvailability": {
    "value": "SingleAZ",
    "type": "String"
  },
  "VpcFlowLogFormat": {
    "value": "",
    "type": "String"
  },
  "VpcFlowLogS3BucketArn": {
    "value": "",
    "type": "String"
  },
  "VpcFlowLogRetentionInDays": {
    "value": 7,
    "type": "Number"
  },
  "DefaultPermissionBoundaryArn": {
    "value": "",
    "type": "String"
  },
  "DefaultAdmins": {
    "value": "",
    "type": "String"
  },
  "AppEc2QueueSize": {
    "value": 2,
    "type": "Number"
  },
  "AppAlarmDailyMinutes": {
    "value": 4000,
    "type": "Number"
  },
  "AppGithubApiStrategy": {
    "value": "normal",
    "type": "String"
  },
  "AppCPU": {
    "value": 256,
    "type": "Number"
  },
  "AppMemory": {
    "value": 512,
    "type": "Number"
  },
  "AppRegistry": {
    "value": "public.ecr.aws/c5h5o9k1/runs-on/runs-on",
    "type": "String"
  },
  "AppDebug": {
    "value": "false",
    "type": "String"
  },
  "LoggerLevel": {
    "value": "info",
    "type": "String"
  },
  "SpotCircuitBreaker": {
    "value": "2/15/30",
    "type": "String"
  },
  "EncryptEbs": {
    "value": "false",
    "type": "String"
  },
  "EnableEfs": {
    "value": "false",
    "type": "String"
  },
  "EnableEphemeralRegistry": {
    "value": "false",
    "type": "String"
  },
  "RunnerDefaultDiskSize": {
    "value": 40,
    "type": "Number"
  },
  "RunnerDefaultVolumeThroughput": {
    "value": 400,
    "type": "Number"
  },
  "RunnerLargeDiskSize": {
    "value": 80,
    "type": "Number"
  },
  "RunnerLargeVolumeThroughput": {
    "value": 750,
    "type": "Number"
  },
  "RunnerCustomTags": {
    "value": [],
    "type": "CommaDelimitedList"
  },
  "RunnerMaxRuntime": {
    "value": 720,
    "type": "Number"
  },
  "RunnerConfigAutoExtendsFrom": {
    "value": ".github-private",
    "type": "String"
  },
  "CostReportsEnabled": {
    "value": "true",
    "type": "String"
  },
  "EC2InstanceCustomPolicy": {
    "value": "",
    "type": "String"
  },
  "AppCustomPolicy": {
    "value": "",
    "type": "String"
  },
  "ECInstanceDetailedMonitoring": {
    "value": "false",
    "type": "String"
  },
  "Ec2LogRetentionInDays": {
    "value": 7,
    "type": "Number"
  },
  "SqsQueueOldestMessageThresholdSeconds": {
    "value": 0,
    "type": "Number"
  },
  "EnableDashboard": {
    "value": "false",
    "type": "String"
  },
  "S3CacheExpirationInDays": {
    "value": 10,
    "type": "Number"
  },
  "CostAllocationTag": {
    "value": "stack",
    "type": "String"
  },
  "IntegrationStepSecurityApiKey": {
    "value": "",
    "type": "String"
  },
  "OtelExporterEndpoint": {
    "value": "",
    "type": "String"
  },
  "OtelExporterHeaders": {
    "value": "",
    "type": "String"
  },
  "ServerPassword": {
    "value": "",
    "type": "String"
  }
}
```

### Terraform Default Values

```json
{
  "aws_region": {
    "value": "us-east-1",
    "type": "string"
  },
  "stack_name": {
    "value": "runs-on-tofu-test",
    "type": "string"
  },
  "environment": {
    "value": "production",
    "type": "string"
  },
  "vpc_cidr": {
    "value": "10.1.0.0/16",
    "type": "string"
  },
  "public_subnet_cidrs": {
    "value": [
      "10.1.1.0/24",
      "10.1.2.0/24",
      "10.1.3.0/24"
    ],
    "type": "list"
  },
  "private_subnet_cidrs": {
    "value": [
      "10.1.11.0/24",
      "10.1.12.0/24",
      "10.1.13.0/24"
    ],
    "type": "list"
  },
  "email": {
    "value": "",
    "type": "string"
  },
  "enable_efs": {
    "value": false,
    "type": "bool"
  },
  "enable_ecr": {
    "value": false,
    "type": "bool"
  },
  "ssh_allowed": {
    "value": true,
    "type": "bool"
  },
  "ssh_cidr_range": {
    "value": "0.0.0.0/0",
    "type": "string"
  }
}
```

---

## Known Gaps (from previous analysis)

### CRITICAL
1. ❌ Private networking only supports boolean (not "always"/"only" modes)
2. ❌ `AppDebug` parameter missing
3. ❌ `AppAlarmDailyMinutes` missing
4. ❌ Bootstrap script execution logic different
5. ❌ Missing userdata environment variables
6. ❌ No CloudWatch alarms created

### MAJOR
1. ❌ VPC Endpoints not configurable
2. ❌ Slack Lambda webhook not implemented
3. ❌ Dashboard creation not implemented

---

## Files Generated

- CloudFormation state: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-gR0shi/cfn-stack.json`
- CloudFormation parameters: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-gR0shi/cfn-parameters.json`
- CloudFormation resources: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-gR0shi/cfn-resources.json`
- Tofu plan: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-gR0shi/tofu-plan.json`
- Tofu variables: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-gR0shi/tofu-variables.json`
- Tofu changes: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-gR0shi/tofu-changes.json`

---

*Report generated by validate-against-cfn.sh v0.1.0*
