'use strict';

// CloudFormation creates the IP sets with these documentation addresses and
// reapplies them on any update to the sets. Terraform creates them empty.
const PLACEHOLDER_ADDRESSES = new Set(['192.0.2.1/32', '2001:db8::1/128']);

function createDefaultAws() {
  let initialized = false;
  let wafv2;
  let GetIPSetCommand;
  let UpdateIPSetCommand;

  function init() {
    if (initialized) return;
    initialized = true;
    const wafSdk = require('@aws-sdk/client-wafv2');
    wafv2 = new wafSdk.WAFV2Client({});
    GetIPSetCommand = wafSdk.GetIPSetCommand;
    UpdateIPSetCommand = wafSdk.UpdateIPSetCommand;
  }

  return {
    async getIPSet(params) {
      init();
      return wafv2.send(new GetIPSetCommand(params));
    },
    async updateIPSet(params) {
      init();
      return wafv2.send(new UpdateIPSetCommand(params));
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

function uniqueSorted(addresses) {
  return Array.from(new Set((addresses || []).map((value) => trimString(value)).filter(Boolean))).sort();
}

function splitHookCidrs(meta) {
  const hooks = Array.isArray(meta?.hooks) ? meta.hooks : [];
  if (hooks.length === 0) {
    throw new Error('GitHub meta response did not include any webhook hook CIDRs');
  }

  const ipv4 = [];
  const ipv6 = [];
  for (const cidr of hooks) {
    const normalized = trimString(cidr);
    if (!normalized) continue;
    if (normalized.includes(':')) {
      ipv6.push(normalized);
    } else {
      ipv4.push(normalized);
    }
  }

  if (ipv4.length === 0 && ipv6.length === 0) {
    throw new Error('GitHub meta response did not include any valid webhook hook CIDRs');
  }

  return {
    ipv4: uniqueSorted(ipv4),
    ipv6: uniqueSorted(ipv6),
  };
}

function configFromEvent(event = {}, env = process.env) {
  const properties = event?.ResourceProperties || {};
  const input = event?.input && typeof event.input === 'object' ? event.input : {};

  return {
    metaUrl: trimString(properties.MetaUrl || input.meta_url || env.RUNS_ON_GITHUB_META_URL || 'https://api.github.com/meta'),
    scope: trimString(properties.Scope || input.scope || env.RUNS_ON_WAF_SCOPE || 'REGIONAL') || 'REGIONAL',
    ipv4Id: trimString(properties.IPv4IPSetId || input.ipv4_ip_set_id || env.RUNS_ON_WAF_IPV4_IP_SET_ID),
    ipv4Name: trimString(properties.IPv4IPSetName || input.ipv4_ip_set_name || env.RUNS_ON_WAF_IPV4_IP_SET_NAME),
    ipv6Id: trimString(properties.IPv6IPSetId || input.ipv6_ip_set_id || env.RUNS_ON_WAF_IPV6_IP_SET_ID),
    ipv6Name: trimString(properties.IPv6IPSetName || input.ipv6_ip_set_name || env.RUNS_ON_WAF_IPV6_IP_SET_NAME),
  };
}

async function fetchMeta(fetchImpl, metaUrl) {
  const response = await fetchImpl(metaUrl, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'runs-on-waf-sync',
    },
  });

  if (!response.ok) {
    throw new Error(`GitHub meta request failed with status ${response.status}`);
  }
  return response.json();
}

function needsSeed(addresses) {
  const normalized = uniqueSorted(addresses);
  return normalized.length === 0 || normalized.some((address) => PLACEHOLDER_ADDRESSES.has(address));
}

async function syncIPSet(aws, params, desiredAddresses) {
  const current = await aws.getIPSet({
    Id: params.id,
    Name: params.name,
    Scope: params.scope,
  });

  const nextAddresses = uniqueSorted(desiredAddresses);
  const existingAddresses = uniqueSorted(current?.IPSet?.Addresses || []);
  if (JSON.stringify(existingAddresses) === JSON.stringify(nextAddresses)) {
    return {
      updated: false,
      address_count: nextAddresses.length,
    };
  }

  await aws.updateIPSet({
    Id: params.id,
    Name: params.name,
    Scope: params.scope,
    Addresses: nextAddresses,
    LockToken: current?.LockToken,
  });

  return {
    updated: true,
    address_count: nextAddresses.length,
  };
}

async function performSync(event, options = {}) {
  const aws = options.aws || createDefaultAws();
  const fetchImpl = options.fetchImpl || fetch;
  const config = configFromEvent(event, options.env || process.env);

  if (!config.ipv4Id || !config.ipv4Name || !config.ipv6Id || !config.ipv6Name) {
    throw new Error('Both IPv4 and IPv6 WAF IP set identifiers must be configured');
  }

  const ipSets = {
    ipv4: { id: config.ipv4Id, name: config.ipv4Name, scope: config.scope },
    ipv6: { id: config.ipv6Id, name: config.ipv6Name, scope: config.scope },
  };

  // Stack deploys run the seed on every upgrade. Unauthenticated GitHub meta
  // requests from Lambda's shared egress IPs get rate limited, so a seed only
  // calls GitHub when a set still lacks the webhook ranges.
  if (options.seed) {
    const current = await Promise.all(Object.values(ipSets).map((params) => aws.getIPSet({
      Id: params.id,
      Name: params.name,
      Scope: params.scope,
    })));
    if (!current.some((response) => needsSeed(response?.IPSet?.Addresses))) {
      log('info', 'WAF IP sets already hold GitHub webhook CIDRs; the hourly sync keeps them current');
      return { skipped: true };
    }
  }

  const meta = await fetchMeta(fetchImpl, config.metaUrl);
  const hooks = splitHookCidrs(meta);

  const ipv4 = await syncIPSet(aws, ipSets.ipv4, hooks.ipv4);
  const ipv6 = await syncIPSet(aws, ipSets.ipv6, hooks.ipv6);

  const result = {
    meta_url: config.metaUrl,
    ipv4,
    ipv6,
  };
  log('info', 'Synchronized GitHub webhook CIDRs into WAF IP sets', result);
  return result;
}

async function sendCloudFormationResponse(event, status, data, reason, fetchImpl = fetch) {
  const responseUrl = trimString(event?.ResponseURL);
  if (!responseUrl) return;

  const body = JSON.stringify({
    Status: status,
    Reason: reason || `See CloudWatch Logs for details: ${trimString(event?.LogicalResourceId) || 'RunsOnGitHubWafSyncSeed'}`,
    PhysicalResourceId: trimString(event?.PhysicalResourceId) || trimString(event?.LogicalResourceId) || 'RunsOnGitHubWafSyncSeed',
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

function isCloudFormationCustomResourceEvent(event) {
  return !!event?.ResponseURL && !!event?.RequestType;
}

async function createHandler(event, options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  if (isCloudFormationCustomResourceEvent(event)) {
    if (event.RequestType === 'Delete') {
      await sendCloudFormationResponse(event, 'SUCCESS', { skipped: true }, 'Delete request acknowledged', fetchImpl);
      return { skipped: true };
    }

    try {
      const result = await performSync(event, { ...options, seed: true });
      await sendCloudFormationResponse(event, 'SUCCESS', result, undefined, fetchImpl);
      return result;
    } catch (error) {
      const message = String(error?.message || error);
      // A failed Update rolls the stack back, and the rollback runs this seed
      // again: a second failure leaves the stack in UPDATE_ROLLBACK_FAILED.
      // The hourly sync repairs the IP sets instead.
      if (event.RequestType === 'Update') {
        log('warn', 'CloudFormation GitHub WAF seed failed; the hourly sync will retry', { error: message });
        await sendCloudFormationResponse(event, 'SUCCESS', { error: message }, message, fetchImpl);
        return { error: message };
      }
      log('error', 'CloudFormation GitHub WAF seed failed', { error: message });
      await sendCloudFormationResponse(event, 'FAILED', { error: message }, message, fetchImpl);
      throw error;
    }
  }

  // Terraform's lifecycle-scoped seed invocation adds a `tf` key to its input.
  return performSync(event, { ...options, seed: !!event?.tf });
}

module.exports = {
  configFromEvent,
  createHandler,
  handler: (event) => createHandler(event),
  splitHookCidrs,
  uniqueSorted,
};
