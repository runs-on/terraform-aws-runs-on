# CloudFormation vs Tofu Validation Report

**Generated:** 2025-11-19 16:23:05
**CloudFormation Stack:** runs-on
**Tofu Directory:** ./examples/complete
**AWS Region:** us-east-1

---

## Executive Summary

### CloudFormation Stack

- **Parameters:** 58
- **Resources:** 65

### Tofu Plan

- **Resource Changes:** 96

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
  ❌ AppDebug: MISSING in Terraform
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
  ✓ Private → private_networking_enabled
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

- CloudFormation state: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-x7vS2g/cfn-stack.json`
- CloudFormation parameters: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-x7vS2g/cfn-parameters.json`
- CloudFormation resources: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-x7vS2g/cfn-resources.json`
- Tofu plan: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-x7vS2g/tofu-plan.json`
- Tofu variables: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-x7vS2g/tofu-variables.json`
- Tofu changes: `/var/folders/sl/1z9qf23d0pz18zpxzq5vcq6r0000gn/T/validate-cfn-x7vS2g/tofu-changes.json`

---

*Report generated by validate-against-cfn.sh v0.1.0*
