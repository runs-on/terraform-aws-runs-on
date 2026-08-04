'use strict';

const crypto = require('node:crypto');

const WORKFLOW_RUN_ID_INDEX = 'workflow-run-id-index';

function createDefaultAws() {
  let initialized = false;
  let dynamodb;
  let secretsmanager;
  let GetItemCommand;
  let QueryCommand;
  let UpdateItemCommand;
  let GetSecretValueCommand;

  function init() {
    if (initialized) return;
    initialized = true;
    const ddb = require('@aws-sdk/client-dynamodb');
    const secrets = require('@aws-sdk/client-secrets-manager');
    dynamodb = new ddb.DynamoDBClient({});
    GetItemCommand = ddb.GetItemCommand;
    QueryCommand = ddb.QueryCommand;
    UpdateItemCommand = ddb.UpdateItemCommand;
    secretsmanager = new secrets.SecretsManagerClient({});
    GetSecretValueCommand = secrets.GetSecretValueCommand;
  }

  return {
    async getSecretValue(params) {
      init();
      return secretsmanager.send(new GetSecretValueCommand(params));
    },
    async getItem(params) {
      init();
      return dynamodb.send(new GetItemCommand(params));
    },
    async query(params) {
      init();
      return dynamodb.send(new QueryCommand(params));
    },
    async updateItem(params) {
      init();
      return dynamodb.send(new UpdateItemCommand(params));
    },
  };
}

function trim(value) {
  return String(value || '').trim();
}

function numberValue(value) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function boolValue(value) {
  return value === true || value === 'true';
}

function optionalBoolValue(value) {
  if (value === undefined || value === null || value === '') return null;
  return boolValue(value);
}

function optionalNumberValue(value) {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function optionalStringValue(value) {
  const normalized = trim(value);
  return normalized || null;
}

function parseJSON(value, label) {
  const raw = trim(value);
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`failed to parse ${label}: ${error.message}`);
  }
}

function parseJobURL(jobURL) {
  try {
    const parsed = new URL(trim(jobURL));
    const parts = parsed.pathname.split('/').filter(Boolean);
    const actionsIndex = parts.indexOf('actions');
    const runsIndex = parts.indexOf('runs');
    const jobIndex = parts.indexOf('job');
    if (parts.length >= 2 && actionsIndex === 2 && runsIndex === 3 && jobIndex === 5) {
      return {
        owner: parts[0],
        repo: parts[1],
        workflow_run_id: numberValue(parts[4]),
        workflow_job_id: numberValue(parts[6]),
      };
    }
  } catch (_) {
    // The CLI sends parsed fields too; URL parsing is only a fallback.
  }
  return {};
}

function requestFacts(event) {
  const fromURL = parseJobURL(event?.job_url);
  return {
    job_url: trim(event?.job_url),
    owner: trim(event?.owner || fromURL.owner),
    repo: trim(event?.repo || fromURL.repo),
    workflow_run_id: numberValue(event?.workflow_run_id || fromURL.workflow_run_id),
    workflow_job_id: numberValue(event?.workflow_job_id || fromURL.workflow_job_id),
    include_delivery_metadata: event?.include_delivery_metadata !== false,
  };
}

function unmarshalAttribute(value) {
  if (!value || typeof value !== 'object') return undefined;
  if (Object.prototype.hasOwnProperty.call(value, 'S')) return value.S;
  if (Object.prototype.hasOwnProperty.call(value, 'N')) return numberValue(value.N);
  if (Object.prototype.hasOwnProperty.call(value, 'BOOL')) return boolValue(value.BOOL);
  if (Object.prototype.hasOwnProperty.call(value, 'NULL')) return null;
  if (Object.prototype.hasOwnProperty.call(value, 'SS')) return value.SS || [];
  if (Object.prototype.hasOwnProperty.call(value, 'NS')) return (value.NS || []).map(numberValue);
  if (Object.prototype.hasOwnProperty.call(value, 'L')) return (value.L || []).map(unmarshalAttribute);
  if (Object.prototype.hasOwnProperty.call(value, 'M')) return unmarshalItem(value.M || {});
  return undefined;
}

function unmarshalItem(item) {
  const result = {};
  for (const [key, value] of Object.entries(item || {})) {
    const unmarshaled = unmarshalAttribute(value);
    if (unmarshaled !== undefined) result[key] = unmarshaled;
  }
  return result;
}

function stringSet(values) {
  const seen = new Set();
  const result = [];
  for (const value of values || []) {
    const normalized = trim(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

// The stack and Fleet config secrets contain credentials and infrastructure
// identifiers. Keep diagnostics on an explicit allowlist instead of returning
// either secret wholesale.
function normalizeStackSettings(config = {}) {
  const source = config.DiagnosticSettings || config.diagnostic_settings || {};
  const infra = config.infra || {};
  const cache = source.cache || {};
  const stickyDisk = source.sticky_disk || {};
  const storage = source.storage || {};
  const buildkit = source.buildkit || {};
  const runner = source.runner || {};
  const scheduling = source.scheduling || {};
  const network = source.network || {};
  const runtime = source.runtime || {};
  const telemetry = source.telemetry || {};
  const integrations = source.integrations || {};
  const brokerConfigured = trim(
    config.CacheCredentialBrokerFunctionName || infra.cache_credential_broker_function_name,
  ) !== '';

  return {
    schema_version: optionalNumberValue(source.schema_version) || 1,
    app_tag: optionalStringValue(source.app_tag || config.AppTag || infra.app_tag),
    deployment_method: optionalStringValue(
      source.deployment_method || config.DeploymentMethod || infra.deployment_method,
    ),
    cache: {
      isolation_enabled: cache.isolation_enabled === undefined
        ? brokerConfigured
        : optionalBoolValue(cache.isolation_enabled),
      credential_broker_configured: brokerConfigured,
      expiration_days: optionalNumberValue(cache.expiration_days),
      bucket_versioning_enabled: optionalBoolValue(cache.bucket_versioning_enabled),
      mandatory_extras: Array.isArray(cache.mandatory_extras)
        ? stringSet(cache.mandatory_extras)
        : null,
    },
    sticky_disk: {
      isolation_enabled: optionalBoolValue(stickyDisk.isolation_enabled),
      configured_runner_count: optionalNumberValue(stickyDisk.configured_runner_count),
    },
    storage: {
      ebs_encryption_mode: optionalStringValue(storage.ebs_encryption_mode),
      efs_enabled: optionalBoolValue(storage.efs_enabled),
    },
    buildkit: {
      ephemeral_registry_enabled: optionalBoolValue(buildkit.ephemeral_registry_enabled),
      pull_through_rule_count: optionalNumberValue(buildkit.pull_through_rule_count),
      docker_hub_mirror_enabled: optionalBoolValue(buildkit.docker_hub_mirror_enabled),
    },
    runner: {
      max_runtime_minutes: optionalNumberValue(runner.max_runtime_minutes),
      config_auto_extends_enabled: optionalBoolValue(runner.config_auto_extends_enabled),
      custom_policy_count: optionalNumberValue(runner.custom_policy_count),
      custom_tags_configured: optionalBoolValue(runner.custom_tags_configured),
      bedrock_enabled: optionalBoolValue(runner.bedrock_enabled),
    },
    scheduling: {
      spot_circuit_breaker: optionalStringValue(scheduling.spot_circuit_breaker),
    },
    network: {
      private_mode: optionalStringValue(network.private_mode),
      ipv6_enabled: optionalBoolValue(network.ipv6_enabled),
      ssh_allowed: optionalBoolValue(network.ssh_allowed),
      public_subnet_count: optionalNumberValue(network.public_subnet_count),
      private_subnet_count: optionalNumberValue(network.private_subnet_count),
    },
    runtime: {
      app_size: optionalStringValue(runtime.app_size),
      capacity_provider: optionalStringValue(runtime.capacity_provider),
      maintenance_mode: optionalBoolValue(runtime.maintenance_mode),
      github_api_strategy: optionalStringValue(runtime.github_api_strategy),
    },
    telemetry: {
      exporter_configured: optionalBoolValue(telemetry.exporter_configured),
      headers_configured: optionalBoolValue(telemetry.headers_configured),
      temporality: optionalStringValue(telemetry.temporality),
      logs_enabled: optionalBoolValue(telemetry.logs_enabled),
      traces_enabled: optionalBoolValue(telemetry.traces_enabled),
      logger_level: optionalStringValue(telemetry.logger_level),
      ec2_log_group_configured: optionalBoolValue(telemetry.ec2_log_group_configured),
    },
    integrations: {
      step_security_configured: optionalBoolValue(integrations.step_security_configured),
    },
  };
}

function instanceIDFromRunnerName(runnerName) {
  const parts = trim(runnerName).split('--');
  if (parts.length < 2) return '';
  const instanceID = trim(parts[1]);
  return instanceID.startsWith('i-') ? instanceID : '';
}

function normalizeSpotInterruption(record, product) {
  const isFleet = product === 'fleet';
  const detected = boolValue(isFleet ? record?.spot_interrupted : record?.was_interrupted);
  const instanceIDs = isFleet && Array.isArray(record?.interrupted_instance_ids)
    ? stringSet(record.interrupted_instance_ids)
    : null;
  let source = '';
  if (isFleet) {
    source = record?.spot_interruption_source || (detected ? 'claim_record' : '');
  } else if (detected) {
    source = 'workflow_job_record';
  }
  return {
    detected,
    interrupted_at: isFleet ? optionalStringValue(record?.spot_interrupted_at) : null,
    source: optionalStringValue(source),
    instance_ids: instanceIDs,
  };
}

function createdAtFromLocal(record) {
  for (const key of ['created_at', 'queue_time', 'acquired_at', 'received_at']) {
    const value = trim(record?.[key]);
    if (value) return value;
  }
  const unix = numberValue(record?.created_at_unix || record?.updated_at_unix);
  if (unix > 0) return new Date(unix * 1000).toISOString();
  return '';
}

function normalizeWorkflowJob(job) {
  if (!job || typeof job !== 'object') return null;
  return {
    id: numberValue(job.id),
    run_id: numberValue(job.run_id),
    run_attempt: numberValue(job.run_attempt),
    name: trim(job.name),
    status: trim(job.status),
    conclusion: trim(job.conclusion),
    runner_name: trim(job.runner_name),
    runner_id: numberValue(job.runner_id),
    runner_group_name: trim(job.runner_group_name),
    workflow_name: trim(job.workflow_name),
    head_branch: trim(job.head_branch),
    head_sha: trim(job.head_sha),
    html_url: trim(job.html_url),
    created_at: trim(job.created_at),
    started_at: trim(job.started_at),
    completed_at: trim(job.completed_at),
    labels: Array.isArray(job.labels) ? job.labels.map(trim).filter(Boolean) : [],
  };
}

function normalizeWorkflowRun(run) {
  if (!run || typeof run !== 'object') return null;
  return {
    id: numberValue(run.id),
    run_number: numberValue(run.run_number),
    run_attempt: numberValue(run.run_attempt),
    name: trim(run.name),
    path: trim(run.path),
    event: trim(run.event),
    status: trim(run.status),
    conclusion: trim(run.conclusion),
    head_branch: trim(run.head_branch),
    head_sha: trim(run.head_sha),
    html_url: trim(run.html_url),
    created_at: trim(run.created_at),
    updated_at: trim(run.updated_at),
    run_started_at: trim(run.run_started_at),
  };
}

function normalizeFlexRecord(record) {
  if (!record) return null;
  const instanceIDs = stringSet([
    record.active_attempt?.instance_id,
    ...(Array.isArray(record.attempt_history) ? record.attempt_history.map((attempt) => attempt?.instance_id) : []),
    instanceIDFromRunnerName(record.runner_name),
  ]);
  return {
    source: 'flex_workflow_jobs',
    workflow_job_id: numberValue(record.job_id),
    workflow_run_id: numberValue(record.run_id),
    installation_id: numberValue(record.installation_id),
    runner_name: trim(record.runner_name),
    instance_ids: instanceIDs,
    status: trim(record.status),
    scheduling_state: trim(record.scheduling_state),
    spot_interruption: normalizeSpotInterruption(record, 'flex'),
    created_at: createdAtFromLocal(record),
    completed_at: trim(record.completed_at),
    record,
  };
}

function normalizeFleetClaim(record) {
  if (!record) return null;
  const scalesetJobID = trim(record.scaleset_job_id);
  const instanceIDs = stringSet([
    ...(Array.isArray(record.attempted_instance_ids) ? record.attempted_instance_ids : []),
    record.instance_id,
    instanceIDFromRunnerName(record.desired_runner_name),
  ]);
  return {
    source: 'fleet_claims',
    workflow_job_id: numberValue(record.workflow_job_id),
    workflow_run_id: numberValue(record.workflow_run_id),
    scaleset_job_id: scalesetJobID,
    runner_name: trim(record.desired_runner_name),
    instance_ids: instanceIDs,
    status: trim(record.state),
    scheduling_state: trim(record.state),
    spot_interruption: normalizeSpotInterruption(record, 'fleet'),
    created_at: createdAtFromLocal(record),
    completed_at: trim(record.completed_at),
    record,
  };
}

function claimInstallationID(claim) {
  return numberValue(claim?.installation_id);
}

function singleClaimInstallationID(claims) {
  const installationIDs = [...new Set((claims || []).map(claimInstallationID).filter((id) => id > 0))];
  if (installationIDs.length !== 1) return { installationID: 0, ambiguous: installationIDs.length > 1 };
  return { installationID: installationIDs[0], ambiguous: false };
}

function githubAPIBase(config = {}) {
  const enterpriseURL = trim(config.GithubEnterpriseUrl || config.github_enterprise_url);
  if (enterpriseURL) return enterpriseURL.replace(/\/+$/, '') + '/api/v3';
  const baseURL = trim(config.github_base_url);
  if (baseURL && !/^https:\/\/github\.com\/?$/i.test(baseURL)) return baseURL.replace(/\/+$/, '') + '/api/v3';
  return 'https://api.github.com';
}

function base64URL(value) {
  return Buffer.from(value).toString('base64url');
}

function normalizePEM(value) {
  return trim(value).replace(/\\n/g, '\n');
}

function createAppJWT(appConfig, now = () => Date.now()) {
  const appID = numberValue(appConfig?.id || appConfig?.app_id || appConfig?.github_app_id);
  const pem = normalizePEM(appConfig?.pem || appConfig?.PEM || appConfig?.private_key || appConfig?.github_private_key);
  if (!appID || !pem) throw new Error('GitHub App credentials are missing app ID or private key');
  const issuedAt = Math.floor(now() / 1000) - 60;
  const payload = {
    iat: issuedAt,
    exp: issuedAt + 10 * 60,
    iss: String(appID),
  };
  const header = base64URL(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const body = base64URL(JSON.stringify(payload));
  const signature = crypto.createSign('RSA-SHA256').update(`${header}.${body}`).sign(pem).toString('base64url');
  return `${header}.${body}.${signature}`;
}

function createGitHubClient(options) {
  const fetchImpl = options.fetch || fetch;
  const apiBase = trim(options.apiBase).replace(/\/+$/, '');

  async function request(path, auth, method = 'GET', body = null) {
    const response = await fetchImpl(apiBase + path, {
      method,
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: auth,
        'User-Agent': 'runs-on-job-diagnostics',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const text = await response.text();
    const payload = text ? parseJSON(text, `GitHub ${path} response`) : null;
    if (!response.ok) {
      const message = payload?.message || response.statusText || 'GitHub request failed';
      const error = new Error(`${message} (${response.status})`);
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  async function installationToken(credentials, owner, repo, knownInstallationID = 0) {
    if (credentials.type === 'token') return `Bearer ${credentials.token}`;
    const appAuth = `Bearer ${createAppJWT(credentials.appConfig)}`;
    let installationID = numberValue(knownInstallationID);
    if (!installationID) {
      const installation = await request(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/installation`, appAuth);
      installationID = numberValue(installation?.id);
    }
    if (!installationID) throw new Error('GitHub App installation ID could not be resolved');
    const token = await request(`/app/installations/${installationID}/access_tokens`, appAuth, 'POST', {});
    if (!trim(token?.token)) throw new Error('GitHub App installation token response did not include a token');
    return `Bearer ${token.token}`;
  }

  return {
    async getWorkflowJob(credentials, owner, repo, jobID, installationID = 0) {
      const auth = await installationToken(credentials, owner, repo, installationID);
      return request(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/actions/jobs/${jobID}`, auth);
    },
    async getWorkflowRun(credentials, owner, repo, runID, installationID = 0) {
      const auth = await installationToken(credentials, owner, repo, installationID);
      return request(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/actions/runs/${runID}`, auth);
    },
    async listAppDeliveries(credentials) {
      if (credentials.type !== 'app') return [];
      const appAuth = `Bearer ${createAppJWT(credentials.appConfig)}`;
      const payload = await request('/app/hook/deliveries?per_page=100', appAuth);
      return Array.isArray(payload) ? payload : [];
    },
  };
}

function appCredentialsFromFlexSecret(secret) {
  const appConfig = secret?.primary?.app_config;
  if (!appConfig) throw new Error('GitHub apps secret is missing primary.app_config');
  return { type: 'app', appConfig };
}

function credentialsFromFleetConfig(config) {
  const token = trim(config?.github_enterprise_pat);
  if (token) return { type: 'token', token };
  return {
    type: 'app',
    appConfig: {
      app_id: config?.github_app_id,
      pem: config?.github_private_key,
    },
  };
}

async function loadSecretJSONWithProvenance(aws, secretID, label, versionID = '') {
  if (!trim(secretID)) throw new Error(`${label} secret ARN is not configured`);
  const input = { SecretId: secretID };
  const pinnedVersionID = trim(versionID);
  if (pinnedVersionID) input.VersionId = pinnedVersionID;
  const output = await aws.getSecretValue(input);
  return {
    value: parseJSON(output?.SecretString, label),
    versionPinned: pinnedVersionID !== '',
  };
}

async function loadSecretJSON(aws, secretID, label) {
  return (await loadSecretJSONWithProvenance(aws, secretID, label)).value;
}

function attachCurrentStackSettings(response, configSecret) {
  response.stack_settings = normalizeStackSettings(configSecret.value);
  // Retained records do not carry the config version used by their worker, so
  // identify these as resolver-deployment settings instead of job-effective.
  response.stack_settings_provenance = {
    source: 'resolver_deployment_config',
    scope: 'current_stack',
    version_pinned: configSecret.versionPinned,
    job_effective: 'unknown',
  };
  response.diagnostics.push({
    level: 'info',
    code: 'stack_settings_scope_current',
    message: 'Stack settings describe the resolver deployment config; the diagnosed job-effective config version is not recorded.',
  });
}

async function getFlexRecord(aws, tableName, jobID) {
  const output = await aws.getItem({
    TableName: tableName,
    Key: {
      job_id: { N: String(jobID) },
    },
  });
  return output?.Item ? unmarshalItem(output.Item) : null;
}

async function queryFleetClaims(aws, tableName, runID) {
  const claims = [];
  let exclusiveStartKey;
  // Claim selection compares all candidates for a workflow run, so every
  // DynamoDB Query page must be included before matching or marking ambiguous.
  do {
    const output = await aws.query({
      TableName: tableName,
      IndexName: WORKFLOW_RUN_ID_INDEX,
      KeyConditionExpression: 'workflow_run_id = :run_id',
      ExpressionAttributeValues: {
        ':run_id': { N: String(runID) },
      },
      ScanIndexForward: false,
      ...(exclusiveStartKey ? { ExclusiveStartKey: exclusiveStartKey } : {}),
    });
    claims.push(...(output?.Items || []).map(unmarshalItem));
    exclusiveStartKey = output?.LastEvaluatedKey;
  } while (exclusiveStartKey);
  return claims;
}

function chooseFleetClaim(claims, workflowJob) {
  const runnerName = trim(workflowJob?.runner_name);
  const instanceID = instanceIDFromRunnerName(runnerName);
  const jobName = trim(workflowJob?.name);
  const exact = [];
  let exactBasis = '';
  for (const claim of claims) {
    if (runnerName && trim(claim.desired_runner_name) === runnerName) {
      exact.push(claim);
      exactBasis ||= 'runner_name';
      continue;
    }
    if (instanceID && trim(claim.instance_id) === instanceID) {
      exact.push(claim);
      exactBasis ||= 'instance_id';
      continue;
    }
    if (instanceID && Array.isArray(claim.attempted_instance_ids) && claim.attempted_instance_ids.map(trim).includes(instanceID)) {
      exact.push(claim);
      exactBasis ||= 'attempted_instance_id';
    }
  }
  if (exact.length === 1) return { claim: exact[0], ambiguous: false, matchBasis: exactBasis, exactMatchCount: 1 };
  if (exact.length > 1) return { claim: null, ambiguous: true, matchBasis: exactBasis, exactMatchCount: exact.length };

  if (runnerName || instanceID) {
    return { claim: null, ambiguous: false, matchBasis: 'runner_not_found', exactMatchCount: 0 };
  }

  const byName = jobName ? claims.filter((claim) => trim(claim.job_display_name) === jobName) : [];
  if (byName.length === 1) return { claim: byName[0], ambiguous: false, matchBasis: 'job_display_name', exactMatchCount: 0 };
  if (byName.length > 1) return { claim: null, ambiguous: true, matchBasis: 'job_display_name', exactMatchCount: 0 };
  if (claims.length === 1) return { claim: claims[0], ambiguous: false, matchBasis: 'single_run_claim', exactMatchCount: 0 };
  return { claim: null, ambiguous: claims.length > 1, matchBasis: claims.length > 1 ? 'workflow_run_id' : 'none', exactMatchCount: 0 };
}

function githubFetchDiagnostic(code, error, credentials, owner, repo, idLabel, idValue) {
  if (numberValue(error?.status) === 404) {
    return {
      level: 'warn',
      code: `${code}_not_accessible`,
      message: `stack GitHub ${credentials.type} credential cannot read ${owner}/${repo} ${idLabel} ${idValue}, or it does not exist (GitHub returned 404)`,
    };
  }
  return {
    level: 'warn',
    code: `${code}_failed`,
    message: String(error?.message || error),
  };
}

function appendFleetClaimDiagnostics(response) {
  const fleet = response.fleet;
  if (!fleet) return;
  response.diagnostics.push({
    level: 'info',
    code: 'fleet_claims_queried',
    message: `${fleet.claim_count} Fleet claims matched workflow run ${response.request.workflow_run_id}`,
  });
  if (fleet.match_basis) {
    response.diagnostics.push({
      level: 'info',
      code: 'fleet_claim_match_basis',
      message: `Fleet claim match basis: ${fleet.match_basis}; exact matches: ${fleet.exact_match_count}`,
    });
  }
}

async function persistFleetWorkflowJobID(aws, tableName, claim, workflowJobID, diagnostics) {
  const pk = trim(claim?.pk);
  const sk = trim(claim?.sk);
  if (!pk || !sk || !workflowJobID) return;
  try {
    await aws.updateItem({
      TableName: tableName,
      Key: {
        pk: { S: pk },
        sk: { S: sk },
      },
      UpdateExpression: 'SET workflow_job_id = if_not_exists(workflow_job_id, :workflow_job_id)',
      ExpressionAttributeValues: {
        ':workflow_job_id': { N: String(workflowJobID) },
      },
    });
  } catch (error) {
    diagnostics.push({
      level: 'warn',
      code: 'workflow_job_id_update_failed',
      message: String(error?.message || error),
    });
  }
}

function observedDeliveries(record) {
  const deliveries = Array.isArray(record?.webhook_deliveries) ? record.webhook_deliveries : [];
  return deliveries
    .map((delivery) => ({
      guid: trim(delivery?.delivery_id || delivery?.guid),
      event: trim(delivery?.event_type || delivery?.event),
      action: trim(delivery?.action),
      received_at: trim(delivery?.received_at),
    }))
    .filter((delivery) => delivery.guid);
}

async function deliveryMetadata(githubClient, credentials, observed, diagnostics) {
  if (credentials.type !== 'app') {
    diagnostics.push({ level: 'info', code: 'delivery_metadata_unavailable', message: 'GitHub delivery metadata requires GitHub App credentials' });
    return observed;
  }
  if (observed.length === 0) {
    diagnostics.push({ level: 'info', code: 'delivery_ids_unavailable', message: 'no workflow job delivery IDs were stored for this job' });
    return [];
  }

  let listed;
  try {
    listed = await githubClient.listAppDeliveries(credentials);
  } catch (error) {
    diagnostics.push({ level: 'warn', code: 'delivery_metadata_fetch_failed', message: String(error?.message || error) });
    return observed;
  }

  const byGUID = new Map((listed || []).map((delivery) => [trim(delivery.guid), delivery]));
  return observed.map((delivery) => {
    const match = byGUID.get(delivery.guid);
    if (!match) {
      return {
        ...delivery,
        status: 'not_found_in_recent_deliveries',
      };
    }
    return {
      guid: trim(match.guid || delivery.guid),
      id: numberValue(match.id),
      event: trim(match.event || delivery.event),
      action: trim(match.action || delivery.action),
      delivered_at: trim(match.delivered_at),
      status: trim(match.status),
      status_code: numberValue(match.status_code),
      duration: numberValue(match.duration),
      redelivery: boolValue(match.redelivery),
      received_at: delivery.received_at,
    };
  });
}

function baseResponse(product, facts, stackName = '') {
  return {
    status: 'not_found',
    product,
    stack_name: trim(stackName),
    request: facts,
    github: {
      workflow_job: null,
      workflow_run: null,
      deliveries: [],
    },
    local: null,
    fleet: null,
    diagnostics: [],
  };
}

async function resolveFlex(aws, facts, options) {
  const response = baseResponse('flex', facts, process.env.RUNS_ON_STACK_NAME);
  const stackConfigSecret = await loadSecretJSONWithProvenance(
    aws,
    process.env.RUNS_ON_STACK_CONFIG_SECRET_ARN,
    'stack config',
    process.env.RUNS_ON_STACK_CONFIG_SECRET_VERSION,
  );
  const stackConfig = stackConfigSecret.value;
  attachCurrentStackSettings(response, stackConfigSecret);
  const githubAppsSecretARN = trim(process.env.RUNS_ON_GITHUB_APPS_SECRET_ARN || stackConfig.GitHubAppsSecretArn);
  const tableName = trim(process.env.RUNS_ON_WORKFLOW_JOBS_TABLE || stackConfig.WorkflowJobsTable);
  if (!tableName) throw new Error('workflow jobs table is not configured');
  if (!facts.workflow_job_id) throw new Error('workflow_job_id is required');

  const record = await getFlexRecord(aws, tableName, facts.workflow_job_id);
  response.local = normalizeFlexRecord(record);

  const githubSecret = await loadSecretJSON(aws, githubAppsSecretARN, 'github apps config');
  const credentials = appCredentialsFromFlexSecret(githubSecret);
  const githubClient = createGitHubClient({
    apiBase: githubAPIBase(stackConfig),
    fetch: options.fetch,
  });

  const owner = facts.owner || response.local?.record?.org_name;
  const repo = facts.repo || response.local?.record?.repo_name;
  const installationID = response.local?.installation_id || 0;
  if (owner && repo) {
    try {
      response.github.workflow_job = normalizeWorkflowJob(
        await githubClient.getWorkflowJob(credentials, owner, repo, facts.workflow_job_id, installationID),
      );
    } catch (error) {
      response.diagnostics.push({ level: 'warn', code: 'github_workflow_job_fetch_failed', message: String(error?.message || error) });
    }
    const runID = facts.workflow_run_id || response.github.workflow_job?.run_id || response.local?.workflow_run_id;
    if (runID) {
      try {
        response.github.workflow_run = normalizeWorkflowRun(
          await githubClient.getWorkflowRun(credentials, owner, repo, runID, installationID),
        );
      } catch (error) {
        response.diagnostics.push({ level: 'warn', code: 'github_workflow_run_fetch_failed', message: String(error?.message || error) });
      }
    }
  } else {
    response.diagnostics.push({ level: 'warn', code: 'github_repo_unavailable', message: 'owner/repo could not be resolved for GitHub enrichment' });
  }

  if (facts.include_delivery_metadata) {
    response.github.deliveries = await deliveryMetadata(githubClient, credentials, observedDeliveries(record), response.diagnostics);
  }
  response.status = response.local ? 'found' : response.github.workflow_job ? 'partial' : 'not_found';
  return response;
}

async function resolveFleet(aws, facts, options) {
  const configSecret = await loadSecretJSONWithProvenance(
    aws,
    process.env.RUNS_ON_FLEET_CONFIG_SECRET_ARN,
    'fleet config',
    process.env.RUNS_ON_FLEET_CONFIG_SECRET_VERSION,
  );
  const config = configSecret.value;
  const response = baseResponse('fleet', facts, config?.infra?.stack_name);
  attachCurrentStackSettings(response, configSecret);
  const tableName = trim(process.env.RUNS_ON_CLAIMS_TABLE || config?.infra?.claim_table_name);
  if (!tableName) throw new Error('fleet claims table is not configured');
  if (!facts.workflow_job_id) throw new Error('workflow_job_id is required');
  if (!facts.workflow_run_id) throw new Error('workflow_run_id is required');
  if (!facts.owner || !facts.repo) throw new Error('owner and repo are required for Fleet diagnostics');

  const credentials = credentialsFromFleetConfig(config);
  const githubClient = createGitHubClient({
    apiBase: githubAPIBase(config),
    fetch: options.fetch,
  });

  const claims = await queryFleetClaims(aws, tableName, facts.workflow_run_id);
  const installation = singleClaimInstallationID(claims);
  if (credentials.type === 'app' && installation.ambiguous) {
    response.diagnostics.push({ level: 'warn', code: 'fleet_installation_ambiguous', message: 'multiple GitHub App installation IDs were present in Fleet claims for this workflow run' });
  }
  const installationID = credentials.type === 'app' ? installation.installationID : 0;

  try {
    response.github.workflow_job = normalizeWorkflowJob(
      await githubClient.getWorkflowJob(credentials, facts.owner, facts.repo, facts.workflow_job_id, installationID),
    );
  } catch (error) {
    response.diagnostics.push(githubFetchDiagnostic('github_workflow_job_fetch', error, credentials, facts.owner, facts.repo, 'workflow job', facts.workflow_job_id));
  }

  const { claim, ambiguous, matchBasis, exactMatchCount } = chooseFleetClaim(claims, response.github.workflow_job);
  response.fleet = {
    claim_count: claims.length,
    exact_match_count: exactMatchCount,
    match_basis: matchBasis,
    installation_id: installationID,
  };
  appendFleetClaimDiagnostics(response);
  if (ambiguous) {
    response.status = 'ambiguous';
    response.diagnostics.push({ level: 'warn', code: 'fleet_claim_ambiguous', message: `multiple Fleet claims matched workflow run ${facts.workflow_run_id}` });
  }
  if (claim) {
    response.local = normalizeFleetClaim(claim);
    await persistFleetWorkflowJobID(aws, tableName, claim, facts.workflow_job_id, response.diagnostics);
  } else if (response.github.workflow_job?.runner_name) {
    const instanceID = instanceIDFromRunnerName(response.github.workflow_job.runner_name);
    response.diagnostics.push({
      level: 'warn',
      code: 'fleet_claim_missing_for_runner',
      message: `no Fleet claim matched runner ${response.github.workflow_job.runner_name}${instanceID ? ` (${instanceID})` : ''}`,
    });
  }

  try {
    response.github.workflow_run = normalizeWorkflowRun(
      await githubClient.getWorkflowRun(credentials, facts.owner, facts.repo, facts.workflow_run_id, installationID),
    );
  } catch (error) {
    response.diagnostics.push(githubFetchDiagnostic('github_workflow_run_fetch', error, credentials, facts.owner, facts.repo, 'workflow run', facts.workflow_run_id));
  }

  response.github.deliveries = [];
  response.diagnostics.push({ level: 'info', code: 'delivery_metadata_not_applicable', message: 'Fleet does not receive GitHub webhook deliveries' });
  if (response.status !== 'ambiguous') response.status = response.local ? 'found' : response.github.workflow_job ? 'partial' : 'not_found';
  return response;
}

function createHandler(options = {}) {
  const aws = options.aws || createDefaultAws();
  return async function handler(event) {
    const product = trim(process.env.RUNS_ON_PRODUCT || event?.product).toLowerCase();
    const facts = requestFacts(event || {});
    if (product === 'fleet') return resolveFleet(aws, facts, options);
    if (product === 'flex') return resolveFlex(aws, facts, options);
    throw new Error(`unsupported RUNS_ON_PRODUCT ${product || '(empty)'}`);
  };
}

const handler = createHandler();

module.exports = {
  WORKFLOW_RUN_ID_INDEX,
  createHandler,
  createAppJWT,
  parseJobURL,
  unmarshalItem,
  normalizeFlexRecord,
  normalizeFleetClaim,
  normalizeSpotInterruption,
  normalizeStackSettings,
  handler,
};
