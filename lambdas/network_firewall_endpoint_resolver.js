'use strict';

function createDefaultAws() {
  let initialized = false;
  let client;
  let DescribeFirewallCommand;

  function init() {
    if (initialized) return;
    initialized = true;
    const networkFirewall = require('@aws-sdk/client-network-firewall');
    client = new networkFirewall.NetworkFirewallClient({});
    DescribeFirewallCommand = networkFirewall.DescribeFirewallCommand;
  }

  return {
    async describeFirewall(params) {
      init();
      return client.send(new DescribeFirewallCommand(params));
    },
  };
}

function log(level, message, fields = {}) {
  const entry = {
    level,
    message,
    ...fields,
  };
  const rendered = JSON.stringify(entry);
  if (level === 'error') {
    console.error(rendered);
    return;
  }
  if (level === 'warn') {
    console.warn(rendered);
    return;
  }
  console.log(rendered);
}

function trimString(value) {
  return String(value || '').trim();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isCloudFormationCustomResourceEvent(event) {
  return !!event?.ResponseURL && !!event?.RequestType;
}

function configFromEvent(event = {}) {
  const properties = event?.ResourceProperties || {};
  const subnetIds = properties.SubnetIds && typeof properties.SubnetIds === 'object'
    ? properties.SubnetIds
    : {};

  return {
    firewallArn: trimString(properties.FirewallArn),
    subnetIds: Object.fromEntries(
      Object.entries(subnetIds)
        .map(([name, subnetId]) => [trimString(name), trimString(subnetId)])
        .filter(([name, subnetId]) => name && subnetId),
    ),
  };
}

function endpointMappings(firewallStatus = {}) {
  const syncStates = firewallStatus.SyncStates || {};
  const states = Array.isArray(syncStates) ? syncStates : Object.values(syncStates);
  const mappings = new Map();

  for (const state of states) {
    const attachment = state?.Attachment || {};
    const subnetId = trimString(attachment.SubnetId);
    const endpointId = trimString(attachment.EndpointId);
    const status = trimString(attachment.Status);
    if (!subnetId) continue;

    mappings.set(subnetId, {
      endpointId,
      status,
    });
  }

  return mappings;
}

function resolvedEndpointData(firewallStatus, subnetIds) {
  const mappings = endpointMappings(firewallStatus);
  const data = {};
  const pending = [];

  for (const [name, subnetId] of Object.entries(subnetIds)) {
    const mapping = mappings.get(subnetId);
    if (!mapping?.endpointId) {
      pending.push(`${name} (${subnetId}) has no endpoint yet`);
      continue;
    }
    if (mapping.status && mapping.status !== 'READY') {
      pending.push(`${name} (${subnetId}) endpoint ${mapping.endpointId} is ${mapping.status}`);
      continue;
    }
    data[`${name}EndpointId`] = mapping.endpointId;
  }

  return {
    data,
    pending,
  };
}

async function resolveEndpointIds(event, options = {}) {
  const aws = options.aws || createDefaultAws();
  const config = configFromEvent(event);
  const maxAttempts = options.maxAttempts || 60;
  const pollDelayMs = options.pollDelayMs || 5000;
  const sleepImpl = options.sleepImpl || sleep;

  if (!config.firewallArn) {
    throw new Error('FirewallArn is required');
  }
  if (Object.keys(config.subnetIds).length === 0) {
    throw new Error('At least one subnet ID is required');
  }

  let lastPending = [];
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const response = await aws.describeFirewall({
      FirewallArn: config.firewallArn,
    });

    const result = resolvedEndpointData(response?.FirewallStatus, config.subnetIds);
    if (result.pending.length === 0) {
      log('info', 'Resolved Network Firewall endpoint IDs', {
        firewall_arn: config.firewallArn,
        attempt,
        endpoint_count: Object.keys(result.data).length,
      });
      return result.data;
    }

    lastPending = result.pending;
    log('info', 'Waiting for Network Firewall endpoint IDs', {
      firewall_arn: config.firewallArn,
      attempt,
      pending: result.pending,
    });

    if (attempt < maxAttempts) {
      await sleepImpl(pollDelayMs);
    }
  }

  throw new Error(`Network Firewall endpoints were not ready: ${lastPending.join('; ')}`);
}

async function sendCloudFormationResponse(event, status, data, reason, fetchImpl = fetch) {
  const responseUrl = trimString(event?.ResponseURL);
  if (!responseUrl) return;

  const physicalResourceId = trimString(event?.PhysicalResourceId)
    || trimString(event?.LogicalResourceId)
    || 'RunsOnNetworkFirewallEndpointResolver';
  const body = JSON.stringify({
    Status: status,
    Reason: reason || `See CloudWatch Logs for details: ${trimString(event?.LogicalResourceId) || 'RunsOnNetworkFirewallEndpointResolver'}`,
    PhysicalResourceId: physicalResourceId,
    StackId: trimString(event?.StackId),
    RequestId: trimString(event?.RequestId),
    LogicalResourceId: trimString(event?.LogicalResourceId),
    Data: data || {},
  });

  await fetchImpl(responseUrl, {
    method: 'PUT',
    headers: {
      'content-type': '',
      'content-length': String(Buffer.byteLength(body)),
    },
    body,
  });
}

async function createHandler(event, options = {}) {
  if (isCloudFormationCustomResourceEvent(event)) {
    if (event.RequestType === 'Delete') {
      await sendCloudFormationResponse(event, 'SUCCESS', { skipped: true }, 'Delete request acknowledged', options.fetchImpl || fetch);
      return { skipped: true };
    }

    try {
      const data = await resolveEndpointIds(event, options);
      await sendCloudFormationResponse(event, 'SUCCESS', data, undefined, options.fetchImpl || fetch);
      return data;
    } catch (error) {
      const message = String(error?.message || error);
      log('error', 'CloudFormation Network Firewall endpoint resolution failed', { error: message });
      await sendCloudFormationResponse(event, 'FAILED', { error: message }, message, options.fetchImpl || fetch);
      throw error;
    }
  }

  return resolveEndpointIds(event, options);
}

module.exports = {
  configFromEvent,
  createHandler,
  endpointMappings,
  handler: (event) => createHandler(event),
  resolvedEndpointData,
  resolveEndpointIds,
};
