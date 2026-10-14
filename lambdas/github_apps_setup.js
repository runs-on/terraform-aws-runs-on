'use strict';

const crypto = require('node:crypto');

const SETUP_STATE_MAX_AGE_SECONDS = 30 * 60;

function createDefaultAws() {
  let initialized = false;
  let secrets;
  let sqs;
  let sns;
  let iam;
  let ssm;
  let GetSecretValueCommand;
  let PutSecretValueCommand;
  let SendMessageCommand;
  let ListSubscriptionsByTopicCommand;
  let GetRoleCommand;
  let CreateServiceLinkedRoleCommand;
  let GetParameterCommand;
  let ecs;
  let quotas;
  let DescribeServicesCommand;
  let GetQueueAttributesCommand;
  let GetServiceQuotaCommand;

  function init() {
    if (initialized) return;
    initialized = true;
    const secretsSdk = require('@aws-sdk/client-secrets-manager');
    const sqsSdk = require('@aws-sdk/client-sqs');
    const snsSdk = require('@aws-sdk/client-sns');
    const iamSdk = require('@aws-sdk/client-iam');
    const ssmSdk = require('@aws-sdk/client-ssm');
    const ecsSdk = require('@aws-sdk/client-ecs');
    const quotasSdk = require('@aws-sdk/client-service-quotas');

    secrets = new secretsSdk.SecretsManagerClient({});
    sqs = new sqsSdk.SQSClient({});
    sns = new snsSdk.SNSClient({});
    iam = new iamSdk.IAMClient({});
    ssm = new ssmSdk.SSMClient({});
    ecs = new ecsSdk.ECSClient({});
    quotas = new quotasSdk.ServiceQuotasClient({});
    GetSecretValueCommand = secretsSdk.GetSecretValueCommand;
    PutSecretValueCommand = secretsSdk.PutSecretValueCommand;
    SendMessageCommand = sqsSdk.SendMessageCommand;
    ListSubscriptionsByTopicCommand = snsSdk.ListSubscriptionsByTopicCommand;
    GetRoleCommand = iamSdk.GetRoleCommand;
    CreateServiceLinkedRoleCommand = iamSdk.CreateServiceLinkedRoleCommand;
    GetParameterCommand = ssmSdk.GetParameterCommand;
    DescribeServicesCommand = ecsSdk.DescribeServicesCommand;
    GetQueueAttributesCommand = sqsSdk.GetQueueAttributesCommand;
    GetServiceQuotaCommand = quotasSdk.GetServiceQuotaCommand;
  }

  return {
    async getSecret(params) {
      init();
      return secrets.send(new GetSecretValueCommand(params));
    },
    async putSecret(params) {
      init();
      return secrets.send(new PutSecretValueCommand(params));
    },
    async sendQueueMessage(params) {
      init();
      return sqs.send(new SendMessageCommand(params));
    },
    async listSubscriptionsByTopic(params) {
      init();
      return sns.send(new ListSubscriptionsByTopicCommand(params));
    },
    async getRole(params) {
      init();
      return iam.send(new GetRoleCommand(params));
    },
    async createServiceLinkedRole(params) {
      init();
      return iam.send(new CreateServiceLinkedRoleCommand(params));
    },
    async getParameter(params) {
      init();
      return ssm.send(new GetParameterCommand(params));
    },
    async describeServices(params) {
      init();
      return ecs.send(new DescribeServicesCommand(params));
    },
    async getQueueAttributes(params) {
      init();
      return sqs.send(new GetQueueAttributesCommand(params));
    },
    async getServiceQuota(params) {
      init();
      return quotas.send(new GetServiceQuotaCommand(params));
    },
  };
}

function githubEndpoints(raw) {
  // Mirror pkg/githubplatform Resolve: tolerate a terminal /api/v3 path and
  // normalize the public GitHub hosts back to the github.com platform.
  const configured = String(raw || '').trim().replace(/\/+$/, '').replace(/\/api\/v3$/i, '');
  if (!configured || /^https:\/\/(?:www\.|api\.)?github\.com(?::\d+)?$/i.test(configured)) {
    return { platform: 'github.com', webUrl: 'https://github.com/', apiUrl: 'https://api.github.com/' };
  }

  try {
    const parsed = new URL(configured);
    const match = parsed.hostname.toLowerCase().match(/^(?:api\.)?([^.]+)\.ghe\.com$/);
    if (match) {
      const webHost = `${match[1]}.ghe.com`;
      return {
        platform: 'ghe.com',
        webUrl: `${parsed.protocol}//${webHost}/`,
        apiUrl: `${parsed.protocol}//api.${webHost}/`,
      };
    }
  } catch (_error) {
    // Preserve the configured value in the setup link so the resulting error
    // points at the invalid customer input instead of github.com.
  }

  return { platform: 'ghes', webUrl: configured + '/', apiUrl: configured + '/api/v3/' };
}

function githubBaseUrl() {
  return githubEndpoints(process.env.RUNS_ON_GITHUB_ENTERPRISE_URL).webUrl;
}

function githubApiUrl() {
  return githubEndpoints(process.env.RUNS_ON_GITHUB_ENTERPRISE_URL).apiUrl;
}

function normalizedHeaders(headers) {
  return Object.fromEntries(Object.entries(headers || {}).map(([key, value]) => [String(key).toLowerCase(), value]));
}

function normalizePath(path, stage) {
  const raw = String(path || '').trim() || '/';
  if (!stage) return raw;
  const stagePrefix = '/' + String(stage).replace(/^\/+|\/+$/g, '');
  if (raw === stagePrefix) return '/';
  if (raw.startsWith(stagePrefix + '/')) return raw.slice(stagePrefix.length);
  return raw;
}

function requestFor(event) {
  const requestContext = event.requestContext || {};
  const stage = String(requestContext.stage || '').trim();
  return {
    method: String(event.httpMethod || '').trim(),
    path: normalizePath(event.path || '/', stage),
    requestId: String(requestContext.requestId || '').trim(),
    headers: normalizedHeaders(event.headers),
    queryStringParameters: event.queryStringParameters || {},
  };
}

function baseUrl() {
  const configured = String(process.env.RUNS_ON_PUBLIC_BASE_URL || '').trim();
  if (!configured) throw new Error('RUNS_ON_PUBLIC_BASE_URL is required');
  return configured.replace(/\/+$/, '');
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

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  };
}

function methodNotAllowed(allowedMethods) {
  return {
    statusCode: 405,
    headers: {
      'content-type': 'application/json',
      allow: allowedMethods.join(', '),
    },
    body: JSON.stringify({ error: 'method not allowed' }),
  };
}

function htmlResponse(body, statusCode = 200) {
  return {
    statusCode,
    headers: { 'content-type': 'text/html; charset=utf-8' },
    body,
  };
}

function redirect(location) {
  let target = String(location || '').trim();
  if (!/^https?:\/\//.test(target)) {
    target = appUrl(target);
  }
  return { statusCode: 302, headers: { location: target }, body: '' };
}

function appUrl(path) {
  const raw = String(path || '').trim();
  const normalized = raw.startsWith('/') ? raw : '/' + raw;
  const configured = String(process.env.RUNS_ON_PUBLIC_BASE_URL || '').trim();
  if (configured) {
    return configured.replace(/\/+$/, '') + normalized;
  }
  return normalized;
}

function base64UrlEncode(value) {
  return Buffer.from(value).toString('base64url');
}

function base64UrlDecode(value) {
  return Buffer.from(String(value || ''), 'base64url').toString('utf8');
}

function timingSafeEqualString(left, right) {
  const leftBuffer = Buffer.from(String(left || ''));
  const rightBuffer = Buffer.from(String(right || ''));
  if (leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function setupStateSigningKey(licenseKey) {
  const rawLicenseKey = String(licenseKey || '').trim();
  if (!rawLicenseKey) {
    throw new Error('stack config LicenseKey is required for setup state signing');
  }
  return crypto
    .createHmac('sha256', rawLicenseKey)
    .update('runs-on setup state')
    .update('\0')
    .update(configuredGitHubOrg())
    .update('\0')
    .update(baseUrl())
    .digest();
}

function signSetupState(payload, licenseKey) {
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signature = crypto
    .createHmac('sha256', setupStateSigningKey(licenseKey))
    .update(encodedPayload)
    .digest('base64url');
  return `${encodedPayload}.${signature}`;
}

function setupStatePayload(kind, idFactory, now, extra = {}) {
  return {
    v: 1,
    kind,
    org: configuredGitHubOrg(),
    base_url: baseUrl(),
    iat: Math.floor(now() / 1000),
    nonce: idFactory(),
    ...extra,
  };
}

function createSetupState(kind, licenseKey, idFactory, now, extra = {}) {
  return signSetupState(setupStatePayload(kind, idFactory, now, extra), licenseKey);
}

function verifySetupState(token, expectedKind, licenseKey, now, expected = {}) {
  const rawToken = String(token || '').trim();
  if (!rawToken) return { ok: false, message: 'The setup callback is missing its signed state.' };

  const parts = rawToken.split('.');
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    return { ok: false, message: 'The setup callback state is malformed.' };
  }

  const expectedSignature = crypto
    .createHmac('sha256', setupStateSigningKey(licenseKey))
    .update(parts[0])
    .digest('base64url');
  if (!timingSafeEqualString(parts[1], expectedSignature)) {
    return { ok: false, message: 'The setup callback state signature is invalid.' };
  }

  let payload;
  try {
    payload = JSON.parse(base64UrlDecode(parts[0]));
  } catch (_) {
    return { ok: false, message: 'The setup callback state payload is invalid.' };
  }

  const issuedAt = Number(payload?.iat || 0);
  const nowSeconds = Math.floor(now() / 1000);
  if (!Number.isFinite(issuedAt) || issuedAt <= 0 || nowSeconds - issuedAt > SETUP_STATE_MAX_AGE_SECONDS || issuedAt - nowSeconds > 60) {
    return { ok: false, message: 'The setup callback state has expired.' };
  }
  if (payload?.v !== 1 || payload?.kind !== expectedKind) {
    return { ok: false, message: 'The setup callback state does not match this setup flow.' };
  }
  if (!stringsEqualFold(payload?.org, configuredGitHubOrg()) || payload?.base_url !== baseUrl()) {
    return { ok: false, message: 'The setup callback state does not match this RunsOn stack.' };
  }
  if (expected.primaryAppId && String(payload?.primary_app_id || '') !== String(expected.primaryAppId)) {
    return { ok: false, message: 'The setup callback state does not match the current primary GitHub App.' };
  }

  return { ok: true, payload };
}

function stringsEqualFold(left, right) {
  return String(left || '').toLowerCase() === String(right || '').toLowerCase();
}

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// BEGIN AUTO-GENERATED RUNS-ON UI CSS
const RUNS_ON_UI_CSS = ":root{color-scheme:light;--ro-mono:\"IBM Plex Mono\",ui-monospace,\"SFMono-Regular\",Menlo,Consolas,\"Liberation Mono\",monospace;--ro-sans:\"IBM Plex Sans\",system-ui,-apple-system,\"Segoe UI\",Roboto,\"Helvetica Neue\",Arial,sans-serif;--ro-ink:#101010;--ro-ink-2:#484848;--ro-faint:#626262;--ro-paper:#ffffff;--ro-paper-2:#f8f8f8;--ro-paper-3:#f1f1f1;--ro-line:#e6e6e6;--ro-line-2:#d4d4d4;--ro-accent:#f0c868;--ro-accent-wash:#fbf2da;--ro-accent-ink:#866610;--ro-green:#2a7640;--ro-red:#b83a2e;--ro-code-bg:#101010;--ro-code-ink:#e8e8e8;--ro-canvas:#ece6da;--ro-grain:url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -1.1 .62'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.2'/%3E%3C/svg%3E\");--ro-frame:2px solid var(--ro-ink);--ro-radius:6px;--ro-shadow:6px 6px 0 var(--ro-ink)}.ro-canvas{margin:0;min-height:100vh;background:var(--ro-canvas) var(--ro-grain);color:var(--ro-ink);font-family:var(--ro-sans);line-height:1.6;-webkit-text-size-adjust:100%}.ro-canvas :where(*,*::before,*::after){box-sizing:border-box}.ro-canvas :where(h1,h2,h3){font-family:var(--ro-mono);font-weight:600;letter-spacing:-0.02em;line-height:1.15;color:var(--ro-ink)}.ro-canvas :where(a){color:var(--ro-ink);text-decoration:underline;text-decoration-color:var(--ro-line-2);text-underline-offset:0.2em}.ro-canvas :where(a:hover){text-decoration-color:var(--ro-ink)}.ro-canvas :where(a,button,summary,input,select,textarea,[tabindex]:not([tabindex=\"-1\"])):focus-visible{outline:2px solid var(--ro-ink);outline-offset:2px}.ro-canvas ::selection{background:var(--ro-accent);color:var(--ro-ink)}.ro-wordmark{display:inline-flex;align-items:center;font-family:var(--ro-mono);font-weight:600;font-size:20px;letter-spacing:-0.03em;line-height:1;white-space:nowrap;color:var(--ro-ink);text-decoration:none}.ro-wordmark::after{content:\"\";display:inline-block;width:0.5em;height:1em;margin-left:0.16em;background:var(--ro-accent);animation:ro-blink 1.15s steps(1) infinite}@keyframes ro-blink{50%{opacity:0}}@media (prefers-reduced-motion:reduce){.ro-wordmark::after{animation:none}}.ro-panel{position:relative;background:var(--ro-paper);border:var(--ro-frame);border-radius:var(--ro-radius);box-shadow:var(--ro-shadow)}.ro-label{font-family:var(--ro-mono);font-size:12px;font-weight:500;letter-spacing:0.08em;text-transform:uppercase;color:var(--ro-faint)}.ro-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:44px;padding:0 18px;border:2px solid var(--ro-ink);border-radius:3px;background:var(--ro-paper);color:var(--ro-ink);font-family:var(--ro-mono);font-size:15px;font-weight:600;line-height:1.2;text-decoration:none;cursor:pointer;transition:background 0.12s,transform 0.08s,box-shadow 0.08s}.ro-btn:hover{background:var(--ro-paper-2);text-decoration:none;transform:translate(-1px,-1px);box-shadow:3px 3px 0 var(--ro-ink)}.ro-btn:active{transform:translate(1px,1px);box-shadow:none}.ro-btn--primary{min-height:50px;padding:0 26px;background:var(--ro-ink);color:var(--ro-accent);font-size:16px;box-shadow:5px 5px 0 var(--ro-accent)}.ro-btn--primary:hover{background:var(--ro-ink);box-shadow:7px 7px 0 var(--ro-accent)}.ro-btn--primary:active{box-shadow:2px 2px 0 var(--ro-accent)}.ro-btn--sm{min-height:34px;padding:0 12px;border-width:1.5px;font-size:13px}.ro-btn--icon{width:40px;min-height:40px;padding:0;font-size:18px}.ro-stamp{display:inline-block;padding:3px 9px;border:2px solid currentColor;border-radius:4px;outline:1px solid currentColor;outline-offset:2px;background:var(--ro-paper);color:var(--ro-ink);font-family:var(--ro-mono);font-size:12px;font-weight:600;letter-spacing:0.06em;line-height:1.3;text-transform:uppercase;white-space:nowrap;transform:rotate(-2deg);user-select:none}.ro-stamp--ok{color:var(--ro-green)}.ro-stamp--error{color:var(--ro-red)}.ro-stamp--warn{color:var(--ro-accent-ink)}.ro-stamp--accent{background:var(--ro-accent);color:var(--ro-ink)}.ro-code{padding:1px 5px;border:1px solid var(--ro-line-2);border-radius:3px;background:var(--ro-paper-3);font-family:var(--ro-mono);font-size:0.9em;overflow-wrap:anywhere}.ro-pre{margin:0;padding:14px 16px;overflow-x:auto;border-radius:4px;background:var(--ro-code-bg);color:var(--ro-code-ink);font-family:var(--ro-mono);font-size:13px;line-height:1.6}";
// END AUTO-GENERATED RUNS-ON UI CSS

// BEGIN AUTO-GENERATED SETUP PAGE CSS
const SETUP_PAGE_CSS = ".page{max-width:920px;margin:0 auto;padding:28px 20px 64px}.top-bar{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px 24px;margin-bottom:30px}.nav-bar{display:flex;gap:22px}.nav-link{padding:6px 0;font-size:13px;font-weight:600;color:var(--ro-ink-2);text-decoration:none}.nav-link:hover,.nav-active{color:var(--ro-ink)}.nav-active{box-shadow:inset 0 -3px 0 var(--ro-accent)}.card{padding:44px 44px 30px}.card-stamp{position:absolute;top:-15px;right:28px;transform:rotate(3deg)}.title{margin:0 0 14px;font-size:34px;overflow-wrap:anywhere}.lead,.copy,.steps{max-width:680px;margin:0 0 16px;font-size:16px;color:var(--ro-ink-2)}.lead{margin-bottom:24px;font-size:17px}.hint{margin:0;font-size:13px;line-height:1.5;color:var(--ro-faint);overflow-wrap:anywhere}.steps{padding-left:22px}.steps li{margin-bottom:10px;padding-left:4px}.steps strong{color:var(--ro-ink)}.steps .hint{display:block;margin-top:3px}.actions{display:flex;flex-wrap:wrap;gap:12px;margin:28px 0 24px}.section,.notice{margin-top:34px;padding-top:24px;border-top:1px solid var(--ro-line-2)}.notice{padding-top:16px}.section h2{margin:0 0 14px;font-size:18px}.section-header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:14px}.section-header h2{margin:0}.section .ro-pre{margin-bottom:14px}.tile{display:flex;align-items:center;gap:12px 16px;padding:12px 14px;border:1px solid var(--ro-line-2);border-radius:4px;background:var(--ro-paper)}.tile-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px;margin:0;padding:0;list-style:none}.tile-body{flex:1;min-width:0}.tile-title{display:block;font-family:var(--ro-mono);font-size:13px;font-weight:600;line-height:1.3;overflow-wrap:anywhere}a.tile{height:100%;text-decoration:none}a.tile:hover{border-color:var(--ro-ink);background:var(--ro-paper-2)}a.tile svg{flex:none;width:18px;height:18px;fill:none;stroke:var(--ro-ink-2);stroke-width:1.4;stroke-linecap:round;stroke-linejoin:round}a.tile .hint{display:block}.app-list{display:grid;gap:12px}.app-card--primary{border-color:var(--ro-accent);background:var(--ro-accent-wash);box-shadow:inset 4px 0 0 var(--ro-accent)}.app-card .tile-title{display:inline;margin-right:10px;font-size:15px}.app-card .hint a{color:inherit;text-decoration:none}.app-card .hint a:hover{text-decoration:underline}.app-list + form .actions,.copy + form .actions{margin:16px 0 0}form + .hint{margin-top:20px}.status-grid{display:grid;grid-template-columns:210px minmax(0,1fr);gap:0 36px;align-items:start}.status-grid>.section{min-width:0}.status-grid .section-header{min-height:40px}.summary{margin:0;font-size:14px}.summary div{margin-bottom:12px}.summary dt{font-size:11px}.summary dd{margin:1px 0 0;overflow-wrap:anywhere}.health-group{margin:14px 0 8px}.health-grid{overflow:hidden;border:2px solid var(--ro-ink);border-radius:4px;background:var(--ro-paper)}.health-item{padding:9px 14px 10px;border-top:1px solid var(--ro-line-2)}.health-item:first-child{border-top:0}.health-item.error{background:color-mix(in srgb,var(--ro-red) 8%,var(--ro-paper));box-shadow:inset 4px 0 0 var(--ro-red)}.health-item.warning{background:var(--ro-accent-wash);box-shadow:inset 4px 0 0 var(--ro-accent)}.health-head{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:4px 12px}.health-head .tile-title{font-size:14px}.health-item .hint{margin-top:2px;color:var(--ro-ink-2)}.stamp-sm{flex:none;margin:1px 3px 3px 0;padding:1px 6px;font-size:10px}@media (max-width:760px){.status-grid{grid-template-columns:1fr}.summary{display:grid;grid-template-columns:1fr 1fr;gap:0 16px}}@media (max-width:640px){.page{padding:20px 16px 48px}.card{padding:36px 20px 22px}.card-stamp{right:14px}.title{font-size:27px}.app-card{flex-direction:column;align-items:stretch}.actions .ro-btn,.app-card>.ro-btn{flex:1 1 auto}}";
// END AUTO-GENERATED SETUP PAGE CSS

function pageCss() {
  return RUNS_ON_UI_CSS + SETUP_PAGE_CSS;
}

function toneForStatus(status) {
  if (status === 'ready' || status === 'healthy') return 'healthy';
  if (status === 'error') return 'error';
  return 'warning';
}

function renderNav(activePath) {
  if (!activePath) return '';
  const items = [
    { label: 'Status', path: '/setup/success' },
    { label: 'Apps', path: '/setup/apps' },
  ];
  const links = items.map((item) => {
    const active = item.path === activePath ? ' nav-active' : '';
    return `<a class="nav-link ro-label${active}" href="${escapeHtml(appUrl(item.path))}">${escapeHtml(item.label)}</a>`;
  }).join('');
  return `<nav class="nav-bar">${links}</nav>`;
}

const ADMIN_ROUTES_NOTICE = '<p class="notice hint">To turn these pages off, set <code class="ro-code">EnableAdminRoutes</code> to <code class="ro-code">false</code> (CloudFormation) or <code class="ro-code">enable_admin_routes = false</code> (Terraform).</p>';

function renderDocument(title, lead, body, options = {}) {
  const nav = renderNav(options.activePath);
  const notice = options.notice === false ? '' : ADMIN_ROUTES_NOTICE;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(title)}</title><style>${pageCss()}</style></head><body class="ro-canvas"><main class="page"><header class="top-bar"><a class="ro-wordmark" href="${escapeHtml(appUrl('/setup/success'))}" aria-label="RunsOn">runs-on:</a>${nav}</header><section class="card ro-panel">${options.stamp || ''}<h1 class="title">${escapeHtml(title)}</h1><p class="lead">${escapeHtml(lead)}</p>${body}${notice}</section></main></body></html>`;
}

// options: statusCode, activePath (nav), stamp (HTML), notice (false hides the admin-routes footer)
function renderPage(title, lead, body, options = {}) {
  return htmlResponse(renderDocument(title, lead, body, options), options.statusCode || 200);
}

function renderStamp(label) {
  return `<span class="ro-stamp card-stamp">${escapeHtml(label)}</span>`;
}

function configuredGitHubOrg() {
  return String(process.env.RUNS_ON_GITHUB_ORG || '').trim();
}

function appSlugFromConfig(appConfig) {
  const explicit = String(appConfig?.slug || '').trim();
  if (explicit) return explicit;

  const rawUrl = String(appConfig?.html_url || '').trim();
  if (!rawUrl) return '';

  try {
    const pathname = new URL(rawUrl).pathname.replace(/\/+$/, '');
    // GHES serves an App's public page under /github-apps/<slug>.
    const match = pathname.match(/\/(?:github-)?apps\/([^/]+)$/) || pathname.match(/\/settings\/apps\/([^/]+)$/);
    return match ? decodeURIComponent(match[1]) : '';
  } catch (_) {
    return '';
  }
}

function appPublicUrl(appConfig) {
  const rawUrl = String(appConfig?.html_url || '').trim();
  if (rawUrl) return rawUrl;

  const slug = appSlugFromConfig(appConfig);
  if (!slug) return '';
  const endpoints = githubEndpoints(process.env.RUNS_ON_GITHUB_ENTERPRISE_URL);
  return endpoints.webUrl + (endpoints.platform === 'ghes' ? 'github-apps/' : 'apps/') + encodeURIComponent(slug);
}

function appSettingsUrl(appConfig) {
  const slug = appSlugFromConfig(appConfig);
  if (!slug) return '';

  const org = configuredGitHubOrg();
  const ownerPath = org
    ? 'organizations/' + encodeURIComponent(org) + '/settings/apps/'
    : 'settings/apps/';
  return githubBaseUrl() + ownerPath + encodeURIComponent(slug);
}

function appInstallationUrl(appConfig) {
  const settingsUrl = appSettingsUrl(appConfig);
  if (settingsUrl) {
    return settingsUrl.replace(/\/+$/, '') + '/installations';
  }

  const publicUrl = appPublicUrl(appConfig);
  return publicUrl ? publicUrl.replace(/\/+$/, '') + '/installations/new' : '';
}

function appNewInstallationUrl(appConfig) {
  const publicUrl = appPublicUrl(appConfig);
  return publicUrl ? publicUrl.replace(/\/+$/, '') + '/installations/new' : '';
}

// GitHub App names are unique across all of GitHub (34 characters max), and an
// organization can run one stack per environment. Name each app after the first
// four characters of the stack environment, its registration time (base36
// seconds) and two random characters, so stacks registering in the same second
// still differ: e.g. runs-on-flex-prod-t3k2a1f4 or runs-on-flex-prod-boost-t3k2a1f4.
function generatedAppName(kind, now, idFactory) {
  const stamp = Math.floor(now() / 1000).toString(36) + String(idFactory()).replaceAll('-', '').slice(0, 2).toLowerCase();
  const env = stackEnvironment().toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+/, '').slice(0, 4).replace(/-+$/, '') || 'prod';
  return ['runs-on-flex', env, kind, stamp].filter(Boolean).join('-');
}

function stackEnvironment() {
  return String(process.env.RUNS_ON_ENV || '').trim() || 'production';
}

function manifestForPrimary(now, idFactory) {
  const url = baseUrl();
  return {
    default_events: ['workflow_run', 'workflow_job', 'meta'],
    default_permissions: {
      administration: 'write',
      single_file: 'write',
      metadata: 'read',
      members: 'read',
      actions: 'write',
      deployments: 'read',
    },
    single_file_paths: ['.github/runs-on.yml'],
    description: `RunsOn stack for ${configuredGitHubOrg()} (environment: ${stackEnvironment()}). Deploy ephemeral and cheap self-hosted runners for your GitHub Actions workflows, in your AWS account`,
    hook_attributes: { url: url + '/github/webhooks' },
    name: generatedAppName('', now, idFactory),
    public: false,
    redirect_url: url + '/setup/convert',
    setup_url: url + '/setup/success',
    setup_on_update: true,
    url: 'https://runs-on.com',
    version: 'v1',
  };
}

function manifestForBoost(now, idFactory) {
  const url = baseUrl();
  return {
    default_permissions: {
      administration: 'write',
    },
    description: `API-only RunsOn GitHub App for same-organization rate-limit expansion, for ${configuredGitHubOrg()} (environment: ${stackEnvironment()})`,
    name: generatedAppName('boost', now, idFactory),
    public: false,
    redirect_url: url + '/setup/apps/convert',
    setup_url: url + '/setup/apps',
    url: 'https://runs-on.com',
    version: 'v1',
  };
}

function buildPendingPersistedGitHubApps(appConfig, existingPersisted = null) {
  return {
    primary: {
      app_config: appConfig,
    },
    boosts: existingPersisted?.boosts && typeof existingPersisted.boosts === 'object' ? existingPersisted.boosts : {},
  };
}

function clonePersisted(persisted) {
  if (!persisted || typeof persisted !== 'object') return {};
  return JSON.parse(JSON.stringify(persisted));
}

function boostAppConfigForPersistence(appConfig) {
  const persisted = { ...appConfig };
  delete persisted.webhook_secret;
  delete persisted.webhookSecret;
  return persisted;
}

function stateForPersisted(persisted) {
  const primary = persisted?.primary || {};
  const appConfig = primary?.app_config || {};
  const state = {
    persisted: persisted && typeof persisted === 'object' ? persisted : null,
    hasPrimaryApp: !!appConfig?.id,
    appId: appConfig?.id ? String(appConfig.id) : '',
    appName: String(appConfig?.name || '').trim(),
    appUrl: appPublicUrl(appConfig),
    appHref: '',
    installationUrl: '',
    installationsUrl: '',
  };
  state.appHref = appSettingsUrl(appConfig) || state.appUrl;
  state.installationUrl = appNewInstallationUrl(appConfig);
  state.installationsUrl = appInstallationUrl(appConfig);
  return state;
}

function readyConfigFromStackConfig(config) {
  return {
    private: String(config?.Private || '').trim(),
  };
}

function githubOrgAppsSettingsUrl() {
  return githubBaseUrl() + 'organizations/' + encodeURIComponent(configuredGitHubOrg()) + '/settings/apps';
}

function renderSetupPage(licenseKey, idFactory, now) {
  const setupState = createSetupState('primary', licenseKey, idFactory, now);
  const manifest = manifestForPrimary(now, idFactory);
  const org = configuredGitHubOrg();
  const action = githubBaseUrl() + 'organizations/' + process.env.RUNS_ON_GITHUB_ORG + '/settings/apps/new';
  const steps = [
    ['Register the GitHub App.', `GitHub shows the app's name, <code class="ro-code">${escapeHtml(manifest.name)}</code>, and its permissions. Click <strong>Create GitHub App</strong>. The app is private to ${escapeHtml(org)}.`],
    ['Install it.', 'Pick all repositories, or only the ones that should run jobs on RunsOn.', 'With a selection, GitHub sends RunsOn workflow events for those repositories only, so the stack has less to process and reacts faster. You can change this later.'],
    ['Check the status page.', 'GitHub sends you back here once the app is installed.'],
  ];
  const stepsHtml = steps.map(([head, text, hint]) => `<li><strong>${head}</strong> ${text}${hint ? `<span class="hint">${hint}</span>` : ''}</li>`).join('');
  return renderPage(
    'Set up RunsOn',
    `Connect this RunsOn stack to the ${org} GitHub organization in three steps.`,
    `<ol class="steps">${stepsHtml}</ol><p class="copy">You need to be an owner or a GitHub App manager of ${escapeHtml(org)}, and signed in to GitHub in this browser.</p><form action="${escapeHtml(action)}" method="post"><input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(manifest))}"><input type="hidden" name="state" value="${escapeHtml(setupState)}"><div class="actions"><button class="ro-btn ro-btn--primary" type="submit">Register GitHub App</button></div></form><p class="hint">RunsOn is not affiliated with GitHub.</p>${renderResources()}`,
    { stamp: renderStamp('Step 1 of 3'), notice: false },
  );
}

const TONE_STAMPS = {
  healthy: '<span class="ro-stamp stamp-sm ro-stamp--ok">passing</span>',
  warning: '<span class="ro-stamp stamp-sm ro-stamp--warn">attention</span>',
  error: '<span class="ro-stamp stamp-sm ro-stamp--error">action needed</span>',
};

function renderHealthIndicators(indicators, checkAgeMs = null) {
  if (!Array.isArray(indicators) || indicators.length === 0) return '';
  // Checks are reused for 30 s, so say how old they are: otherwise a refresh
  // right after a fix looks like nothing changed.
  const seconds = Math.round(checkAgeMs / 1000);
  const freshness = checkAgeMs === null ? '' : `<p class="hint">Checked ${seconds < 2 ? 'just now' : `${seconds} s ago`}. Results are reused for up to 30 seconds, so a fix can take that long to show here.</p>`;
  const header = `<div class="section-header"><h2>Health checks</h2><button class="ro-btn ro-btn--icon" type="button" title="Refresh health checks" aria-label="Refresh health checks" onclick="window.location.reload()">&#8635;</button></div>`;
  const renderItem = (indicator) => {
    const tone = toneForStatus(indicator.status);
    const hint = indicator.hint ? `<p class="hint">${escapeHtml(indicator.hint)}</p>` : '';
    const command = indicator.command ? `<p class="hint"><code class="ro-code">${escapeHtml(indicator.command)}</code></p>` : '';
    const link = indicator.url ? `<p class="hint"><a href="${escapeHtml(indicator.url)}">${escapeHtml(indicator.linkLabel || 'Learn more')}</a></p>` : '';
    return `<article class="health-item ${escapeHtml(tone)}"><div><div class="health-head"><strong class="tile-title">${escapeHtml(indicator.name)}</strong>${TONE_STAMPS[tone]}</div><p class="hint">${escapeHtml(indicator.message)}</p>${hint}${command}${link}</div></article>`;
  };
  // What needs action comes first, errors before warnings, so it can be found at a glance.
  const rank = { error: 0, warning: 1, healthy: 2 };
  const sorted = [...indicators].sort((a, b) => rank[toneForStatus(a.status)] - rank[toneForStatus(b.status)]);
  const failing = sorted.filter((indicator) => toneForStatus(indicator.status) !== 'healthy');
  const passing = sorted.filter((indicator) => toneForStatus(indicator.status) === 'healthy');
  const group = (label, list) => (list.length === 0 ? '' : `<p class="health-group ro-label">${label} &middot; ${list.length}</p><div class="health-grid">${list.map(renderItem).join('')}</div>`);
  return `<section class="health section">${header}${freshness}${group('Needs action', failing)}${group('Passing', passing)}</section>`;
}

function renderResources() {
  return `<section class="section"><h2>Resources</h2>${renderLinkTiles([
    { href: 'https://runs-on.com/docs/', label: 'Documentation', service: 'runs-on.com', icon: 'book' },
    { href: 'https://github.com/runs-on/runs-on', label: 'GitHub project', service: 'Issues and discussions', icon: 'box' },
    { href: 'https://github.com/runs-on/runs-on/releases', label: 'Latest releases', service: 'Changelog', icon: 'layers' },
    { href: 'https://runs-on.com/pricing/', label: 'Pricing & license', service: 'runs-on.com', icon: 'sliders' },
  ])}</section>`;
}

function workflowLabel() {
  const environment = stackEnvironment();
  const env = environment !== 'production' ? '/env=' + environment : '';
  return 'runs-on=$' + '{{ github.run_id }}/runner=2cpu-linux-x64' + env;
}

function renderWorkflowExample() {
  const yaml = [
    'jobs:',
    '  build:',
    `    runs-on: ${workflowLabel()}`,
    '    steps:',
    '      - run: echo "Hello from RunsOn"',
  ].join('\n');
  return `<section class="section"><h2>Run your first job</h2><p class="copy">Set this <code class="ro-code">runs-on</code> label on a job in any repository the app is installed on, then push.</p><pre class="ro-pre">${escapeHtml(yaml)}</pre><p class="copy">If the job stays queued, allow repository-level self-hosted runners in <a href="${escapeHtml(githubBaseUrl() + 'organizations/' + encodeURIComponent(configuredGitHubOrg()) + '/settings/actions')}">your organization's Actions settings</a>. <a href="https://runs-on.com/docs/runners/labels/">All runner labels</a></p></section>`;
}

// installation: { installed: true | false | null, indicator }
// checkAgeMs: how old the (briefly reused) checks are; null when not known.
function renderSetupSuccessPage(state, indicators, installation = { installed: null }, stackConfig = null, checkAgeMs = null) {
  const allIndicators = installation.indicator ? [installation.indicator, ...indicators] : indicators;
  const page = { activePath: '/setup/success' };

  if (installation.installed === false) {
    const install = state.installationUrl
      ? `<div class="actions"><a class="ro-btn ro-btn--primary" href="${escapeHtml(state.installationUrl)}">Install on GitHub</a></div>`
      : '';
    return renderPage(
      'Install the GitHub App',
      `The app is registered, but RunsOn receives no jobs until it is installed on ${configuredGitHubOrg()}.`,
      `${install}${renderOverview(allIndicators, checkAgeMs, stackConfig)}${stackConfig ? renderTroubleshooting(stackConfig, state) : ''}${renderResources()}`,
      { ...page, stamp: renderStamp('Step 2 of 3') },
    );
  }

  // No summary stamp here: the title and each check's own stamp already say it.
  const allHealthy = allIndicators.every((i) => toneForStatus(i.status) === 'healthy');
  const title = allHealthy ? 'RunsOn is ready' : 'RunsOn needs attention';
  const lead = allHealthy
    ? 'Every check passed. Jobs with a RunsOn label now run on this stack.'
    : 'Fix the checks marked below, then refresh this page.';
  const example = installation.installed ? renderWorkflowExample() : '';
  return renderPage(title, lead, `${renderOverview(allIndicators, checkAgeMs, stackConfig)}${example}${stackConfig ? renderTroubleshooting(stackConfig, state) : ''}${renderResources()}`, page);
}

// The stack details beside the health checks (above them on a phone). Without
// a stack config to describe, the health checks take the full width.
function renderOverview(indicators, checkAgeMs, stackConfig) {
  const health = renderHealthIndicators(indicators, checkAgeMs);
  if (!stackConfig) return health;
  return `<div class="status-grid">${renderStackSummary(stackConfig)}${health}</div>`;
}

function boostEntries(persisted) {
  const boosts = persisted?.boosts && typeof persisted.boosts === 'object' ? persisted.boosts : {};
  return Object.entries(boosts)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([appKey, boost]) => {
      const appConfig = boost?.app_config || {};
      return {
        appKey,
        appUrl: appPublicUrl(appConfig),
        appHref: appSettingsUrl(appConfig) || appPublicUrl(appConfig),
        installationUrl: appInstallationUrl(appConfig),
        label: String(boost?.github_app_label || appConfig?.slug || appConfig?.name || appKey).trim() || appKey,
      };
    });
}

function renderAppCard(name, appHref, meta, actions, primary = false) {
  const urlHtml = appHref ? `<p class="hint"><a href="${escapeHtml(appHref)}">${escapeHtml(appHref.replace('https://', ''))}</a></p>` : '';
  const metaHtml = meta ? `<p class="hint">${meta}</p>` : '';
  const stamp = primary ? '<span class="ro-stamp ro-stamp--accent stamp-sm">Primary</span>' : '<span class="ro-stamp stamp-sm">Boost</span>';
  return `<div class="tile app-card${primary ? ' app-card--primary' : ''}"><div class="tile-body"><strong class="tile-title">${escapeHtml(name)}</strong>${stamp}${urlHtml}${metaHtml}</div>${actions.join('')}</div>`;
}

function renderAppsPage(state, idFactory, licenseKey, now) {
  const action = githubBaseUrl() + 'organizations/' + process.env.RUNS_ON_GITHUB_ORG + '/settings/apps/new';
  const setupState = createSetupState('boost', licenseKey, idFactory, now, { primary_app_id: state.appId });
  const boostManifest = manifestForBoost(now, idFactory);

  const primaryActions = [];
  if (state.installationsUrl) {
    primaryActions.push(`<a class="ro-btn ro-btn--sm" href="${escapeHtml(state.installationsUrl)}">Installations</a>`);
  }
  const primaryCard = renderAppCard(
    state.appName || 'Primary GitHub App',
    state.appHref,
    'Receives workflow events from GitHub and launches runners for this stack.',
    primaryActions,
    true,
  );

  const boosts = boostEntries(state.persisted);
  const boostCards = boosts.length === 0
    ? '<p class="copy">No API boost apps yet.</p>'
    : `<div class="app-list">${boosts.map((boost) => {
      const boostActions = boost.installationUrl
        ? [`<a class="ro-btn ro-btn--sm" href="${escapeHtml(boost.installationUrl)}">Installations</a>`]
        : [];
      return renderAppCard(
        boost.label,
        boost.appHref,
        `app key: <code class="ro-code">${escapeHtml(boost.appKey)}</code>`,
        boostActions,
      );
    }).join('')}</div>`;

  return renderPage(
    'GitHub apps',
    'The GitHub App this stack uses, and optional boost apps for extra GitHub API quota.',
    `<section class="section"><h2>Primary app</h2>${primaryCard}</section><section class="section"><h2>API boost apps</h2><p class="copy">Each boost app brings its own GitHub API quota for creating runners. Add one only if your RunsOn logs show GitHub API rate-limit errors.</p>${boostCards}<form action="${escapeHtml(action)}" method="post"><input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(boostManifest))}"><input type="hidden" name="state" value="${escapeHtml(setupState)}"><div class="actions"><button class="ro-btn ro-btn--sm" type="submit">Add Boost App</button></div></form></section>`,
    { activePath: '/setup/apps' },
  );
}

// options.restart: where the button goes ('primary' → start over at /setup, 'boost' → back to /setup/apps).
// options.appMayExist: GitHub created the app before calling back, so a retry would hit a name clash.
function renderProblemPage(title, lead, message, statusCode = 400, options = {}) {
  const restart = options.restart === 'boost'
    ? { href: '/setup/apps', label: 'Back to Apps' }
    : { href: '/setup', label: 'Start over' };
  const orphan = options.appMayExist
    ? `<p class="copy">GitHub has probably already created this app. Delete it in <a href="${escapeHtml(githubOrgAppsSettingsUrl())}">your organization's GitHub Apps settings</a> before you try again, or GitHub will refuse the app name.</p>`
    : '';
  return renderPage(
    title,
    lead,
    `<p class="copy">${escapeHtml(message)}</p>${orphan}<div class="actions"><a class="ro-btn ro-btn--primary" href="${escapeHtml(appUrl(restart.href))}">${restart.label}</a></div>`,
    { statusCode },
  );
}

function isResourceNotFound(error) {
  const code = String(error?.name || error?.Code || error?.code || '').trim();
  return code === 'ResourceNotFoundException';
}

function isAlreadyExists(error) {
  const message = String(error?.message || error || '').toLowerCase();
  return message.includes('already exists') || message.includes('invalidinput');
}

function isPendingConfirmation(value) {
  return String(value || '').includes('PendingConfirmation');
}

function parseLicenseStatus(raw) {
  const parsed = JSON.parse(String(raw || '').trim());
  if (!parsed || typeof parsed !== 'object') {
    throw new Error('license status payload must be an object');
  }
  const status = String(parsed.status || '').trim().toLowerCase();
  if (!status) {
    throw new Error('license status is required');
  }
  return {
    status,
    message: String(parsed.message || '').trim(),
    errors: Array.isArray(parsed.errors) ? parsed.errors.map((value) => String(value || '').trim()).filter(Boolean) : [],
  };
}

async function loadStackConfig(aws) {
  const arn = String(process.env.RUNS_ON_STACK_CONFIG_SECRET_ARN || '').trim();
  if (!arn) {
    log('warn', 'Stack config secret ARN is not configured');
    return {};
  }

  const params = { SecretId: arn };
  const version = String(process.env.RUNS_ON_STACK_CONFIG_SECRET_VERSION || '').trim();
  if (version) {
    params.VersionId = version;
  }

  try {
    const output = await aws.getSecret(params);
    const raw = String(output?.SecretString || '').trim();
    if (!raw) {
      return {};
    }
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      parsed = null;
    }
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (error) {
    if (isResourceNotFound(error)) {
      log('warn', 'Stack config secret not found');
      return {};
    }
    throw error;
  }
}

async function loadStackReadyConfig(aws) {
  return readyConfigFromStackConfig(await loadStackConfig(aws));
}

function licenseKeyFromStackConfig(config) {
  return String(config?.LicenseKey || '').trim();
}

function createGitHubAppJwt(appConfig, now = () => Date.now()) {
  const appID = Number(appConfig?.id || appConfig?.app_id || 0);
  const pem = String(appConfig?.pem || appConfig?.PEM || '').trim();
  if (!appID || !pem) {
    throw new Error('converted GitHub App response is missing app ID or PEM');
  }

  const issuedAt = Math.floor(now() / 1000) - 60;
  const payload = {
    iat: issuedAt,
    exp: issuedAt + 10 * 60,
    iss: String(appID),
  };
  const encodedHeader = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(`${encodedHeader}.${encodedPayload}`)
    .sign(pem)
    .toString('base64url');
  return `${encodedHeader}.${encodedPayload}.${signature}`;
}

async function buildHealthIndicators(aws) {
  const indicators = [];

  const licenseIndicator = {
    name: 'License',
    description: 'RunsOn license validation status',
    status: 'warning',
    message: 'Verifying',
  };
  const licenseStatusParameter = String(process.env.RUNS_ON_LICENSE_STATUS_SSM_PARAMETER || '').trim();
  if (licenseStatusParameter) {
    try {
      const result = await aws.getParameter({ Name: licenseStatusParameter });
      const value = String(result?.Parameter?.Value || '').trim();
      if (value) {
        const snapshot = parseLicenseStatus(value);
        if (snapshot.status === 'valid') {
          licenseIndicator.status = 'healthy';
          licenseIndicator.message = snapshot.message || 'License valid';
        } else if (snapshot.status === 'invalid') {
          licenseIndicator.status = 'error';
          licenseIndicator.message = snapshot.message || 'License invalid';
          if (snapshot.errors.length > 0) {
            licenseIndicator.hint = snapshot.errors.join('; ');
          }
          licenseIndicator.url = 'https://runs-on.com/pricing/';
        } else {
          licenseIndicator.status = 'warning';
          licenseIndicator.message = snapshot.message || 'Verifying';
        }
      }
    } catch (_) {
      licenseIndicator.status = 'warning';
      licenseIndicator.message = 'Verifying';
    }
  }
  indicators.push(licenseIndicator);

  const topicArn = String(process.env.RUNS_ON_TOPIC_ARN || '').trim();
  const emailIndicator = {
    name: 'Email notifications',
    description: 'SNS email subscription confirmation status',
    url: 'https://runs-on.com/monitoring/alerts/',
    status: 'warning',
    message: 'No email subscription found',
  };
  if (!topicArn) {
    emailIndicator.status = 'error';
    emailIndicator.message = 'SNS topic ARN is not configured';
  } else {
    try {
      const result = await aws.listSubscriptionsByTopic({ TopicArn: topicArn });
      let hasConfirmedEmail = false;
      let hasUnconfirmedEmail = false;
      for (const subscription of result?.Subscriptions || []) {
        if (subscription?.Protocol === 'email') {
          if (!isPendingConfirmation(subscription?.SubscriptionArn)) {
            hasConfirmedEmail = true;
          } else {
            hasUnconfirmedEmail = true;
          }
        }
      }
      if (hasConfirmedEmail) {
        emailIndicator.status = 'healthy';
        emailIndicator.message = 'Email subscription confirmed and active';
      } else if (hasUnconfirmedEmail) {
        emailIndicator.status = 'warning';
        emailIndicator.message = 'Email subscription pending confirmation';
        emailIndicator.hint = 'Click the link in the confirmation email from AWS Notifications.';
      } else {
        emailIndicator.hint = 'Set the stack\'s email address parameter to get alerts about this stack.';
      }
    } catch (_) {
      emailIndicator.status = 'error';
      emailIndicator.message = 'Unable to check subscription status';
    }
  }
  indicators.push(emailIndicator);

  const spotIndicator = {
    name: 'EC2 Spot Instance Service Role',
    description: 'Required role for launching spot instances',
    status: 'healthy',
    message: 'AWSServiceRoleForEC2Spot role found and active',
  };
  try {
    await aws.getRole({ RoleName: 'AWSServiceRoleForEC2Spot' });
  } catch (error) {
    try {
      await aws.createServiceLinkedRole({ AWSServiceName: 'spot.amazonaws.com' });
      spotIndicator.message = 'AWSServiceRoleForEC2Spot role created and active';
    } catch (createError) {
      if (isAlreadyExists(createError)) {
        spotIndicator.message = 'AWSServiceRoleForEC2Spot role found and active';
      } else {
        spotIndicator.status = 'error';
        spotIndicator.message = 'Failed to create AWSServiceRoleForEC2Spot role';
        spotIndicator.hint = 'Spot runners cannot launch without it. Create it once for this AWS account:';
        spotIndicator.command = 'aws iam create-service-linked-role --aws-service-name spot.amazonaws.com';
      }
    }
  }
  indicators.push(spotIndicator);

  return indicators;
}

// ── Diagnostics shown on the public status page ─────────────────────────────
// Everything here is visible to anyone who has the entrypoint URL: show
// statuses and counts, never repository names, job details, payloads or the
// AWS account ID.

const EC2_QUOTAS = [
  { code: 'L-34B43A08', label: 'Spot' },
  { code: 'L-1216C47A', label: 'On-Demand' },
];
const LOW_VCPU_QUOTA = 32;

function formatAge(ms) {
  const minutes = Math.round(ms / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 90) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `${hours} h ago`;
  return `${Math.round(hours / 24)} days ago`;
}

function webhookFailureHint(statusCode) {
  if (statusCode === 403) return 'HTTP 403 usually means the WAF blocked GitHub; check that GitHub\'s hook addresses are allowed.';
  if (statusCode === 0 || statusCode >= 500) return 'GitHub could not reach this stack or got an error back; check the ingress and the control plane.';
  return 'Open the App\'s recent deliveries on GitHub to see the response.';
}

// summarizeWebhooks turns the App's webhook config and its latest deliveries
// (newest first) into one indicator.
function summarizeWebhooks(config, deliveries, expectedUrl, nowMs) {
  const indicator = { name: 'GitHub webhooks', status: 'healthy', message: '' };
  // The App's webhook URL may be a custom domain in front of this stack, so a
  // different URL is not an error by itself: the deliveries decide.
  const configured = String(config?.url || '').replace(/\/+$/, '');
  const otherUrl = configured !== '' && configured !== expectedUrl.replace(/\/+$/, '');
  const list = Array.isArray(deliveries) ? deliveries : [];
  const failed = list.filter((delivery) => !(delivery.status_code >= 200 && delivery.status_code < 400));
  const latest = list[0];
  if (!latest) {
    indicator.status = 'warning';
    indicator.message = 'GitHub has not sent any webhook yet';
    indicator.hint = 'It sends one as soon as a workflow job with a RunsOn label is queued.';
  } else if (failed.length === 0) {
    indicator.message = `The last ${list.length} deliveries succeeded (latest ${formatAge(nowMs - Date.parse(latest.delivered_at))})`;
    if (otherUrl) indicator.message += ', through a custom webhook URL';
  } else if (failed[0] === latest) {
    indicator.status = 'error';
    indicator.message = `The latest delivery failed (HTTP ${latest.status_code}, ${formatAge(nowMs - Date.parse(latest.delivered_at))}); ${failed.length} of the last ${list.length} failed`;
    indicator.hint = webhookFailureHint(latest.status_code);
  } else {
    indicator.status = 'warning';
    indicator.message = `${failed.length} of the last ${list.length} deliveries failed (latest failure HTTP ${failed[0].status_code}); the latest succeeded ${formatAge(nowMs - Date.parse(latest.delivered_at))}`;
    indicator.hint = webhookFailureHint(failed[0].status_code);
  }
  if (otherUrl && indicator.status !== 'healthy') {
    indicator.hint += ' The App\'s webhook URL is not this stack\'s own URL: unless it is your custom domain for this stack, point it back here in the App settings.';
  }
  return indicator;
}

function summarizeControlPlane(service, appTag) {
  const indicator = { name: 'Control plane', status: 'healthy', message: '' };
  if (!service) {
    indicator.status = 'error';
    indicator.message = 'The control-plane service was not found';
    return indicator;
  }
  const running = Number(service.runningCount || 0);
  const desired = Number(service.desiredCount || 0);
  const rollout = (service.deployments || []).find((deployment) => deployment.status === 'PRIMARY')?.rolloutState;
  // ECS event messages can name IAM roles and the account ID, so they are
  // never shown here: the ECS link under Troubleshooting has them.
  const whereToLook = 'Open the control-plane service and its logs (under Troubleshooting) for the reason.';
  if (desired === 0) {
    indicator.status = 'error';
    indicator.message = 'Maintenance mode: the control plane is scaled to zero, so jobs are not picked up';
    indicator.hint = 'Set MaintenanceMode to false (CloudFormation) or maintenance_mode = false (Terraform) to resume.';
  } else if (rollout === 'FAILED') {
    indicator.status = 'error';
    indicator.message = `The latest deployment failed (${running} of ${desired} running)`;
    indicator.hint = whereToLook;
  } else if (running < desired) {
    indicator.status = 'warning';
    indicator.message = `Starting: ${running} of ${desired} running`;
    indicator.hint = `This can take a few minutes. If it lasts: ${whereToLook.toLowerCase()}`;
  } else if (rollout === 'IN_PROGRESS') {
    indicator.status = 'warning';
    indicator.message = 'A deployment is still rolling out';
    indicator.hint = 'ECS has not confirmed the new version healthy yet; this usually takes a few minutes.';
  } else {
    indicator.message = appTag ? `Running ${appTag}` : 'Running';
  }
  return indicator;
}

function summarizeEventQueue(queue, deadLetters) {
  const indicator = { name: 'Webhook event queue', status: 'healthy', message: '' };
  const waiting = Number(queue?.ApproximateNumberOfMessages || 0);
  const failed = Number(deadLetters?.ApproximateNumberOfMessages || 0);
  indicator.message = `${waiting} event${waiting === 1 ? '' : 's'} waiting`;
  if (failed > 0) {
    indicator.status = 'warning';
    indicator.message += `, ${failed} failed`;
    indicator.hint = 'Failed events stay in the dead-letter queue; the control-plane logs say why.';
  }
  if (waiting > 200) {
    indicator.status = 'warning';
    indicator.hint = 'The control plane is falling behind; check that it is running.';
  }
  return indicator;
}

function summarizeQuotas(values) {
  const indicator = { name: 'EC2 vCPU quotas', status: 'healthy', message: '' };
  const known = values.filter((quota) => Number.isFinite(quota.value));
  const unknown = values.filter((quota) => !Number.isFinite(quota.value));
  if (known.length === 0) {
    indicator.status = 'warning';
    indicator.message = 'Could not read the EC2 quotas';
    return indicator;
  }
  indicator.message = known.map((quota) => `${quota.label}: ${quota.value} vCPUs`).join(', ');
  const hints = [];
  const low = known.filter((quota) => quota.value < LOW_VCPU_QUOTA);
  if (low.length > 0) {
    hints.push(`${low.map((quota) => quota.label).join(' and ')} runners stop launching once they use that many vCPUs at once; extra jobs wait. Request an increase in Service Quotas.`);
  }
  if (unknown.length > 0) {
    hints.push(`Could not read the ${unknown.map((quota) => quota.label).join(' and ')} quota.`);
  }
  if (hints.length > 0) {
    indicator.status = 'warning';
    indicator.hint = hints.join(' ');
  }
  return indicator;
}

function consoleBase(region) {
  if (region.startsWith('cn-')) return 'https://console.amazonaws.cn';
  if (region.startsWith('us-gov-')) return 'https://console.amazonaws-us-gov.com';
  return `https://${region}.console.aws.amazon.com`;
}

function troubleshootingLinks(stackConfig, appState) {
  const region = String(process.env.AWS_REGION || stackConfig?.Region || '').trim();
  const stackName = String(stackConfig?.StackName || '').trim();
  const logGroup = String(stackConfig?.ServiceLogGroupName || '').trim();
  const cluster = String(process.env.RUNS_ON_ECS_CLUSTER || '').trim();
  const service = String(process.env.RUNS_ON_ECS_SERVICE || '').trim();
  const links = [];
  if (region) {
    const base = consoleBase(region);
    const dashboard = String(process.env.RUNS_ON_DASHBOARD_NAME || '').trim();
    if (dashboard) links.push({ href: `${base}/cloudwatch/home?region=${region}#dashboards/dashboard/${encodeURIComponent(dashboard)}`, label: 'Stack dashboard', service: 'CloudWatch, with recent errors', icon: 'chart' });
    if (logGroup) links.push({ href: `${base}/cloudwatch/home?region=${region}#logsV2:log-groups/log-group/${logGroup.replaceAll('/', '$252F')}`, label: 'Control-plane logs', service: 'CloudWatch Logs', icon: 'lines' });
    if (cluster && service) links.push({ href: `${base}/ecs/v2/clusters/${encodeURIComponent(cluster)}/services/${encodeURIComponent(service)}/health?region=${region}`, label: 'Control-plane service', service: 'ECS', icon: 'box' });
    links.push({ href: `${base}/sqs/v3/home?region=${region}#/queues`, label: 'Event queues', service: 'SQS', icon: 'queue' });
    if (stackName && stackConfig?.DeploymentMethod === 'cloudformation') {
      links.push({ href: `${base}/cloudformation/home?region=${region}#/stacks?filteringText=${encodeURIComponent(stackName)}`, label: 'Stack events', service: 'CloudFormation', icon: 'layers' });
    }
    links.push({ href: `${base}/servicequotas/home/services/ec2/quotas?region=${region}`, label: 'EC2 quotas', service: 'Service Quotas', icon: 'gauge' });
  }
  const org = configuredGitHubOrg();
  if (appState.appHref) {
    const settings = appSettingsUrl(appState.persisted?.primary?.app_config || {});
    if (settings) links.push({ href: settings + '/advanced', label: 'Webhook deliveries', service: 'GitHub App settings', icon: 'send' });
  }
  if (org) links.push({ href: githubBaseUrl() + 'organizations/' + encodeURIComponent(org) + '/settings/actions', label: 'Actions settings', service: 'GitHub organization', icon: 'sliders' });
  links.push({ href: 'https://runs-on.com/docs/maintenance/troubleshooting/', label: 'Troubleshooting guide', service: 'runs-on.com', icon: 'book' });
  return links;
}

// Small line glyphs for the troubleshooting tiles, drawn inline: the pages load
// nothing from elsewhere, and vendor logos are not ours to redraw.
const LINK_ICONS = {
  chart: 'M2 14V8M6 14V3M10 14V6M14 14v-4',
  lines: 'M3 4h10M3 8h10M3 12h6',
  box: 'M2.5 5 8 2l5.5 3v6L8 14l-5.5-3zM2.5 5 8 8l5.5-3M8 8v6',
  queue: 'M2 3.5h12v3.5H2zM2 9h12v3.5H2z',
  layers: 'M8 2 2 5l6 3 6-3zM2 8l6 3 6-3M2 11l6 3 6-3',
  gauge: 'M2.5 12a5.5 5.5 0 1 1 11 0M8 12l3-4.5',
  send: 'M2 8h9M8 4.5 11.5 8 8 11.5M14 3v10',
  sliders: 'M2 5h12M2 11h12M6 3v4M10 9v4',
  book: 'M3 2.5h8a2 2 0 0 1 2 2v9H5a2 2 0 0 1-2-2zM3 11.5a2 2 0 0 1 2-2h8',
};

function renderLinkIcon(name) {
  return `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${LINK_ICONS[name]}"/></svg>`;
}

function renderLinkTiles(links) {
  const items = links.map(({ href, label, service, icon }) => `<li><a class="tile" href="${escapeHtml(href)}">${renderLinkIcon(icon)}<span class="tile-body"><strong class="tile-title">${escapeHtml(label)}</strong><span class="hint">${escapeHtml(service)}</span></span></a></li>`).join('');
  return `<ul class="tile-grid">${items}</ul>`;
}

function renderTroubleshooting(stackConfig, appState) {
  const stackName = String(stackConfig?.StackName || '').trim() || '<stack-name>';
  const region = String(process.env.AWS_REGION || stackConfig?.Region || '').trim();
  const commands = [
    '# AWS credentials for the account this stack runs in',
    'export AWS_PROFILE=your-aws-admin-profile',
    ...(region ? [`export AWS_REGION=${region}`] : []),
    '# Check the stack and export its logs',
    `roc doctor --stack ${stackName}`,
    '# Export everything about one job, from its GitHub URL',
    `roc logs ${githubBaseUrl()}OWNER/REPO/actions/runs/RUN/job/JOB --full --stack ${stackName}`,
  ].join('\n');
  return `<section class="section"><h2>Troubleshooting</h2><p class="copy">These links need you to be signed in to AWS or GitHub. With the <a href="https://runs-on.com/docs/maintenance/troubleshooting/cli/">roc CLI</a>:</p><pre class="ro-pre">${escapeHtml(commands)}</pre>${renderLinkTiles(troubleshootingLinks(stackConfig, appState))}</section>`;
}

function renderStackSummary(stackConfig) {
  const environment = stackEnvironment();
  const privateMode = String(stackConfig?.Private || '').trim();
  const rows = [
    ['Version', String(process.env.RUNS_ON_APP_TAG || '').trim()],
    ['Environment', environment === 'production' ? 'production (default)' : `${environment} (label env=${environment})`],
    ['Region', String(process.env.AWS_REGION || stackConfig?.Region || '').trim()],
    ['App size', String(stackConfig?.AppSize || '').trim()],
    ['Runner networking', privateMode && privateMode !== 'false' ? `private (${privateMode})` : privateMode ? 'public' : ''],
    ['Deployed with', String(stackConfig?.DeploymentMethod || '').trim()],
  ].filter(([, value]) => value);
  const items = rows.map(([label, value]) => `<div><dt class="ro-label">${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd></div>`).join('');
  return `<section class="section"><div class="section-header"><h2>Stack</h2></div><dl class="summary">${items}</dl></section>`;
}

function createHandler(options = {}) {
  const aws = options.aws || createDefaultAws();
  const fetchImpl = options.fetchImpl || fetch;
  const uuid = options.uuid || (() => crypto.randomUUID());
  const now = options.now || (() => Date.now());
  const createAppJwt = options.createAppJwt || ((appConfig) => createGitHubAppJwt(appConfig, now));

  async function loadState() {
    const arn = String(process.env.RUNS_ON_GITHUB_APPS_SECRET_ARN || '').trim();
    if (!arn) {
      log('warn', 'GitHub apps setup secret ARN is not configured');
      return stateForPersisted(null);
    }

    try {
      const output = await aws.getSecret({ SecretId: arn });
      const raw = String(output?.SecretString || '').trim();
      if (!raw) {
        return stateForPersisted(null);
      }
      let parsed = null;
      try {
        parsed = JSON.parse(raw);
      } catch (_) {
        parsed = null;
      }
      const state = stateForPersisted(parsed);
      log('info', 'Loaded GitHub apps setup state', {
        has_primary_app: state.hasPrimaryApp,
        app_id: state.appId,
      });
      return state;
    } catch (error) {
      if (isResourceNotFound(error)) {
        log('warn', 'GitHub apps setup secret not found');
        return stateForPersisted(null);
      }
      throw error;
    }
  }

  async function readyz() {
    const [state, readyConfig] = await Promise.all([
      loadState(),
      loadStackReadyConfig(aws),
    ]);
    const appTag = String(process.env.RUNS_ON_APP_TAG || '').trim();
    const githubAppConfigured = state.hasPrimaryApp;
    return jsonResponse(githubAppConfigured ? 200 : 503, {
      app_tag: appTag,
      app_version: appTag,
      github_app_configured: githubAppConfigured,
      ready_config: readyConfig,
    });
  }

  async function putPersistedGitHubApps(persisted, secretVersionId) {
    return aws.putSecret({
      SecretId: process.env.RUNS_ON_GITHUB_APPS_SECRET_ARN,
      SecretString: JSON.stringify(persisted),
      ClientRequestToken: secretVersionId,
    });
  }

  async function enqueueGitHubAppsChanged(appKey, reason, secretVersionId) {
    const normalizedAppKey = String(appKey || '').trim();
    const normalizedReason = String(reason || '').trim();
    log('info', 'Queueing GitHub app lifecycle event', {
      queue_type: 'system',
      queue_event: 'github_apps_changed',
      app_key: normalizedAppKey,
      reason: normalizedReason,
    });
    return aws.sendQueueMessage({
      QueueUrl: process.env.RUNS_ON_SYSTEM_QUEUE_URL,
      MessageBody: JSON.stringify({
        event: 'github_apps_changed',
        app_key: normalizedAppKey,
        reason: normalizedReason,
      }),
      MessageDeduplicationId: secretVersionId,
      MessageGroupId: 'app-lifecycle',
    });
  }

  async function convertManifest(code, restart) {
    const response = await fetchImpl(githubApiUrl() + 'app-manifests/' + encodeURIComponent(code) + '/conversions', {
      method: 'POST',
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'runs-on-setup',
      },
    });
    if (!response.ok) {
      log('error', 'GitHub App manifest conversion failed', {
        status: response.status,
      });
      return {
        error: renderProblemPage(
          'GitHub App setup failed',
          'GitHub did not hand over the new app\'s credentials.',
          `GitHub rejected the one-time setup code (HTTP ${response.status}). The code works once and expires after an hour, so reloading this page fails.`,
          502,
          { restart, appMayExist: true },
        ),
      };
    }
    return { appConfig: await response.json() };
  }

  // githubAsApp calls GitHub's API as the App. Errors carry `credentials` when
  // the App's key could not sign, and a throttled answer starts a back-off.
  async function githubAsApp(appConfig, path) {
    let jwt;
    try {
      jwt = createAppJwt(appConfig || {});
    } catch (error) {
      throw Object.assign(error, { credentials: true });
    }
    const response = await fetchImpl(githubApiUrl() + path, {
      method: 'GET',
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${jwt}`,
        'User-Agent': 'runs-on-setup',
      },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) {
      noteGitHubBackoff(response);
      throw new Error(`GitHub ${path} returned HTTP ${response.status}`);
    }
    return response.json();
  }

  async function verifyConvertedAppOwner(appConfig) {
    let app;
    try {
      app = await githubAsApp(appConfig, 'app');
    } catch (error) {
      log('warn', 'GitHub App ownership validation failed', { error: String(error?.message || error) });
      return {
        ok: false,
        message: error.credentials
          ? 'GitHub did not return usable app credentials for ownership validation.'
          : 'GitHub App ownership could not be validated.',
      };
    }

    const ownerLogin = String(app?.owner?.login || '').trim();
    if (!ownerLogin || !stringsEqualFold(ownerLogin, configuredGitHubOrg())) {
      log('warn', 'Rejecting GitHub App owned outside configured organization', {
        configured_org: configuredGitHubOrg(),
        owner_login: ownerLogin,
      });
      return { ok: false, message: 'The converted GitHub App is not owned by the configured RunsOn GitHub organization.' };
    }
    return { ok: true, ownerLogin };
  }

  function validateSetupCallbackState(request, kind, licenseKey, expected = {}) {
    const verification = verifySetupState(request.queryStringParameters?.state || '', kind, licenseKey, now, expected);
    if (verification.ok) return null;
    log('warn', 'Rejecting GitHub App setup callback with invalid state', {
      setup_kind: kind,
      reason: verification.message,
    });
    return renderProblemPage(`${kind === 'boost' ? 'Boost app' : 'GitHub App'} setup failed`, 'RunsOn could not verify that this request came from its own setup page.', verification.message, 400, { restart: kind, appMayExist: true });
  }

  async function convertPrimary(request, currentState, licenseKey) {
    const code = request.queryStringParameters?.code || '';
    if (!code) {
      log('warn', 'Rejecting setup convert request without code');
      return renderProblemPage('GitHub App setup failed', 'This page only works as the return step from GitHub.', 'The request has no setup code from GitHub. Start the setup again from the beginning.', 400);
    }
    const stateError = validateSetupCallbackState(request, 'primary', licenseKey);
    if (stateError) return stateError;

    log('info', 'Processing primary GitHub App manifest conversion');
    const conversion = await convertManifest(code, 'primary');
    if (conversion.error) return conversion.error;

    const appConfig = conversion.appConfig;
    const ownerValidation = await verifyConvertedAppOwner(appConfig);
    if (!ownerValidation.ok) {
      return renderProblemPage('GitHub App setup failed', 'The GitHub App owner could not be validated.', ownerValidation.message, 403, { appMayExist: true });
    }

    const secretVersionId = uuid();
    const persisted = buildPendingPersistedGitHubApps(appConfig, currentState.persisted);
    await putPersistedGitHubApps(persisted, secretVersionId);
    await enqueueGitHubAppsChanged('primary', 'setup_convert', secretVersionId);
    const nextState = stateForPersisted(persisted);
    log('info', 'Stored primary GitHub App config and queued activation', {
      app_id: nextState.appId,
      installation_url: nextState.installationUrl,
    });
    return redirect(nextState.installationUrl || '/setup/success');
  }

  async function convertBoost(request, currentState, licenseKey) {
    const code = request.queryStringParameters?.code || '';
    if (!code) {
      log('warn', 'Rejecting boost convert request without code');
      return renderProblemPage('Boost app setup failed', 'This page only works as the return step from GitHub.', 'The request has no setup code from GitHub. Add the boost app again from the Apps page.', 400, { restart: 'boost' });
    }
    const stateError = validateSetupCallbackState(request, 'boost', licenseKey, { primaryAppId: currentState.appId });
    if (stateError) return stateError;

    log('info', 'Processing GitHub boost app manifest conversion');
    const conversion = await convertManifest(code, 'boost');
    if (conversion.error) return conversion.error;

    const appConfig = conversion.appConfig || {};
    const appKey = String(appConfig.slug || '').trim();
    if (!appKey) {
      return renderProblemPage('Boost app setup failed', 'GitHub did not return the app\'s short name.', 'Without it, RunsOn cannot store the app safely.', 500, { restart: 'boost', appMayExist: true });
    }
    if (appKey === 'primary') {
      return renderProblemPage('Boost app setup failed', 'The app\'s short name "primary" is reserved by RunsOn.', 'Choose a different app name and try again.', 409, { restart: 'boost', appMayExist: true });
    }

    const persisted = clonePersisted(currentState.persisted);
    persisted.boosts = persisted.boosts && typeof persisted.boosts === 'object' ? persisted.boosts : {};
    if (persisted.boosts[appKey]) {
      return renderProblemPage('Boost app already exists', 'This stack already has a boost app with the same short name.', `The app key ${appKey} is already configured for this stack.`, 409, { restart: 'boost' });
    }

    const ownerValidation = await verifyConvertedAppOwner(appConfig);
    if (!ownerValidation.ok) {
      return renderProblemPage('Boost app setup failed', 'The GitHub App owner could not be validated.', ownerValidation.message, 403, { restart: 'boost', appMayExist: true });
    }

    persisted.boosts[appKey] = {
      app_config: boostAppConfigForPersistence(appConfig),
      github_app_label: appKey,
    };

    const secretVersionId = uuid();
    await putPersistedGitHubApps(persisted, secretVersionId);
    await enqueueGitHubAppsChanged(appKey, 'boost_setup_convert', secretVersionId);
    const installationUrl = appNewInstallationUrl(appConfig);
    log('info', 'Stored boost GitHub App config and queued reconcile', {
      app_key: appKey,
      app_id: Number(appConfig.id || 0),
      installation_url: installationUrl,
    });
    return redirect(installationUrl || '/setup/apps');
  }

  // The status page is public and the installation check calls GitHub as the
  // App, whose API budget the control plane needs too. API Gateway caps the
  // setup routes; on top, each Lambda instance reuses its last answer briefly
  // and stops asking while GitHub says to back off.
  const INSTALLED_TTL_MS = 30_000;
  const UNSETTLED_TTL_MS = 5_000;
  let installationCache = null;
  let githubBackoffUntil = 0;

  async function checkInstallation(state) {
    const at = now();
    if (installationCache && installationCache.appId === state.appId
      && at - installationCache.at < (installationCache.result.installed ? INSTALLED_TTL_MS : UNSETTLED_TTL_MS)) {
      return installationCache.result;
    }
    const result = at < githubBackoffUntil
      ? unknownInstallation('GitHub asked RunsOn to slow down. Refresh in a minute.')
      : await askGitHubForInstallation(state);
    installationCache = { appId: state.appId, at, result };
    return result;
  }

  function unknownInstallation(hint) {
    return {
      installed: null,
      indicator: { name: 'GitHub App installation', status: 'warning', message: 'Could not check the installation', hint },
    };
  }

  // Remembers GitHub's Retry-After or rate-limit reset from a throttled answer.
  function noteGitHubBackoff(response) {
    if (response.status !== 403 && response.status !== 429) return;
    const headers = response.headers;
    const retryAfter = Number(headers?.get?.('retry-after'));
    const reset = Number(headers?.get?.('x-ratelimit-reset'));
    let until = now() + 60_000;
    if (Number.isFinite(retryAfter) && retryAfter > 0) until = now() + retryAfter * 1000;
    else if (headers?.get?.('x-ratelimit-remaining') === '0' && Number.isFinite(reset) && reset > 0) until = reset * 1000;
    githubBackoffUntil = Math.max(githubBackoffUntil, until);
  }

  // installed is null when GitHub could not be asked.
  async function askGitHubForInstallation(state) {
    const org = configuredGitHubOrg();
    const indicator = { name: 'GitHub App installation', status: 'warning', message: 'Could not check the installation' };
    let installations;
    try {
      installations = await githubAsApp(state.persisted?.primary?.app_config, 'app/installations?per_page=100');
    } catch (error) {
      log('warn', 'GitHub App installation check failed', { error: String(error?.message || error) });
      indicator.hint = error.credentials ? 'The stored app credentials are incomplete.' : 'GitHub did not answer. Refresh to try again.';
      return { installed: null, indicator };
    }

    const installation = (Array.isArray(installations) ? installations : [])
      .find((item) => stringsEqualFold(item?.account?.login, org));
    if (!installation) {
      indicator.status = 'error';
      // The page's primary button links to the installation; no second link here.
      indicator.message = `Not installed on ${org}`;
      return { installed: false, indicator };
    }
    if (installation.suspended_at) {
      indicator.status = 'error';
      indicator.message = `Installation on ${org} is suspended`;
      indicator.hint = 'RunsOn receives no jobs while the installation is suspended.';
    } else {
      indicator.status = 'healthy';
      indicator.message = installation.repository_selection === 'selected'
        ? `Installed on ${org} for selected repositories`
        : `Installed on ${org} for all repositories`;
      if (installation.repository_selection === 'selected') {
        indicator.hint = 'Only those repositories can run jobs on RunsOn.';
      }
    }
    if (state.installationsUrl) {
      indicator.url = state.installationsUrl;
      indicator.linkLabel = 'Installation settings';
    }
    return { installed: true, indicator };
  }

  async function checkWebhooks(state) {
    if (now() < githubBackoffUntil) {
      return { name: 'GitHub webhooks', status: 'warning', message: 'Could not check the webhooks', hint: 'GitHub asked RunsOn to slow down. Refresh in a minute.' };
    }
    try {
      const [config, deliveries] = await Promise.all([
        githubAsApp(state.persisted?.primary?.app_config, 'app/hook/config'),
        githubAsApp(state.persisted?.primary?.app_config, 'app/hook/deliveries?per_page=50'),
      ]);
      return summarizeWebhooks(config, deliveries, baseUrl() + '/github/webhooks', now());
    } catch (error) {
      log('warn', 'GitHub webhook check failed', { error: String(error?.message || error) });
      return { name: 'GitHub webhooks', status: 'warning', message: 'Could not check the webhooks', hint: 'Refresh to try again.' };
    }
  }

  async function checkControlPlane() {
    const cluster = String(process.env.RUNS_ON_ECS_CLUSTER || '').trim();
    const service = String(process.env.RUNS_ON_ECS_SERVICE || '').trim();
    if (!cluster || !service) return null;
    try {
      const output = await aws.describeServices({ cluster, services: [service] });
      return summarizeControlPlane(output?.services?.[0], String(process.env.RUNS_ON_APP_TAG || '').trim());
    } catch (error) {
      log('warn', 'Control plane check failed', { error: String(error?.message || error) });
      return { name: 'Control plane', status: 'warning', message: 'Could not check the control plane' };
    }
  }

  async function checkEventQueue() {
    const queueUrl = String(process.env.RUNS_ON_WEBHOOKS_QUEUE_URL || '').trim();
    const deadLetterUrl = String(process.env.RUNS_ON_WEBHOOKS_DLQ_URL || '').trim();
    if (!queueUrl || !deadLetterUrl) return null;
    try {
      const [queue, deadLetters] = await Promise.all([queueUrl, deadLetterUrl].map((QueueUrl) => aws.getQueueAttributes({
        QueueUrl,
        AttributeNames: ['ApproximateNumberOfMessages'],
      })));
      return summarizeEventQueue(queue?.Attributes, deadLetters?.Attributes);
    } catch (error) {
      log('warn', 'Event queue check failed', { error: String(error?.message || error) });
      return { name: 'Webhook event queue', status: 'warning', message: 'Could not check the event queue' };
    }
  }

  async function checkQuotas() {
    if (typeof aws.getServiceQuota !== 'function') return null;
    const values = await Promise.all(EC2_QUOTAS.map(async (quota) => {
      try {
        const output = await aws.getServiceQuota({ ServiceCode: 'ec2', QuotaCode: quota.code });
        return { label: quota.label, value: Number(output?.Quota?.Value) };
      } catch (error) {
        log('warn', 'EC2 quota check failed', { quota: quota.code, error: String(error?.message || error) });
        return { label: quota.label, value: NaN };
      }
    }));
    return summarizeQuotas(values);
  }

  // AWS SDK calls have no deadline of their own: a stalled one resolves to its
  // fallback here, so the page still renders well inside the Lambda's timeout.
  // (The late call keeps running; every check handles its own errors.)
  const checkDeadlineMs = options.checkDeadlineMs || 5000;
  function withDeadline(promise, fallback) {
    let timer;
    const deadline = new Promise((resolve) => { timer = setTimeout(() => resolve(fallback), checkDeadlineMs); });
    return Promise.race([promise, deadline]).finally(() => clearTimeout(timer));
  }

  // The status page's diagnostics run in parallel, and each Lambda instance
  // reuses them for 30 s (API Gateway also caps the setup routes).
  const DIAGNOSTICS_TTL_MS = 30_000;
  let diagnosticsCache = null;

  async function diagnostics(state) {
    const at = now();
    if (diagnosticsCache && diagnosticsCache.appId === state.appId && at - diagnosticsCache.at < DIAGNOSTICS_TTL_MS) {
      return diagnosticsCache.result;
    }
    const unchecked = (name) => ({ name, status: 'warning', message: `Could not check ${name} in time`, hint: 'Refresh to try again.' });
    const [stackConfig, webhooks, controlPlane, eventQueue, quotas, health] = await Promise.all([
      withDeadline(loadStackConfig(aws).catch(() => ({})), {}),
      checkWebhooks(state),
      withDeadline(checkControlPlane(), unchecked('Control plane')),
      withDeadline(checkEventQueue(), unchecked('Webhook event queue')),
      withDeadline(checkQuotas(), unchecked('EC2 vCPU quotas')),
      withDeadline(buildHealthIndicators(aws), [unchecked('License, email and Spot role')]),
    ]);
    const result = {
      stackConfig,
      checkedAt: at,
      indicators: [webhooks, controlPlane, eventQueue, ...health, quotas].filter(Boolean),
    };
    diagnosticsCache = { appId: state.appId, at, result };
    return result;
  }

  async function setupSuccess() {
    const state = await loadState();
    if (!state.hasPrimaryApp) return redirect('/setup');
    const [installation, diag] = await Promise.all([
      checkInstallation(state),
      diagnostics(state),
    ]);
    log('info', 'Rendering setup success page', {
      has_primary_app: state.hasPrimaryApp,
      app_id: state.appId,
      installed: installation.installed,
    });
    return renderSetupSuccessPage(state, diag.indicators, installation, diag.stackConfig, Math.max(0, now() - diag.checkedAt));
  }

  return async function handler(event) {
    const request = requestFor(event);
    const method = request.method;
    const path = request.path;
    const requestId = request.requestId;

    log('info', 'GitHub apps setup request received', {
      request_id: requestId,
      method,
      path,
    });

    try {
      let response;
      if (path === '/') {
        response = method === 'GET' ? redirect('/setup') : methodNotAllowed(['GET']);
      } else if (path === '/readyz') {
        response = method === 'GET' ? await readyz() : methodNotAllowed(['GET']);
      } else if (path === '/setup') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          const state = await loadState();
          if (state.hasPrimaryApp) {
            response = redirect('/setup/success');
          } else {
            const stackConfig = await loadStackConfig(aws);
            response = renderSetupPage(licenseKeyFromStackConfig(stackConfig), uuid, now);
          }
        }
      } else if (path === '/setup/convert') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          const state = await loadState();
          if (state.hasPrimaryApp) {
            response = redirect('/setup/success');
          } else {
            const stackConfig = await loadStackConfig(aws);
            response = await convertPrimary(request, state, licenseKeyFromStackConfig(stackConfig));
          }
        }
      } else if (path === '/setup/success') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          response = await setupSuccess();
        }
      } else if (path === '/setup/apps') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          const state = await loadState();
          if (!state.hasPrimaryApp) {
            response = redirect('/setup');
          } else {
            const stackConfig = await loadStackConfig(aws);
            response = renderAppsPage(state, uuid, licenseKeyFromStackConfig(stackConfig), now);
          }
        }
      } else if (path === '/setup/apps/convert') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          const state = await loadState();
          if (!state.hasPrimaryApp) {
            response = redirect('/setup');
          } else {
            const stackConfig = await loadStackConfig(aws);
            response = await convertBoost(request, state, licenseKeyFromStackConfig(stackConfig));
          }
        }
      } else {
        response = jsonResponse(404, { error: 'not found' });
      }

      log('info', 'GitHub apps setup request completed', {
        request_id: requestId,
        method,
        path,
        status_code: response.statusCode,
      });
      return response;
    } catch (error) {
      log('error', 'GitHub apps setup request failed', {
        request_id: requestId,
        method,
        path,
        error: String(error?.message || error),
      });
      if (path === '/setup' || path.startsWith('/setup/')) {
        return renderProblemPage('Something went wrong', 'RunsOn could not load this page.', `Refresh to try again. If it keeps failing, the setup Lambda logs have the details (request ${requestId || 'unknown'}).`, 500);
      }
      return jsonResponse(500, { error: 'internal server error' });
    }
  };
}

module.exports = {
  buildPendingPersistedGitHubApps,
  createHandler,
  githubEndpoints,
  handler: createHandler(),
  summarizeControlPlane,
  summarizeEventQueue,
  summarizeQuotas,
  summarizeWebhooks,
};
