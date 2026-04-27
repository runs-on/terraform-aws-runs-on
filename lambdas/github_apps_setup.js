'use strict';

const crypto = require('node:crypto');

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

  function init() {
    if (initialized) return;
    initialized = true;
    const secretsSdk = require('@aws-sdk/client-secrets-manager');
    const sqsSdk = require('@aws-sdk/client-sqs');
    const snsSdk = require('@aws-sdk/client-sns');
    const iamSdk = require('@aws-sdk/client-iam');
    const ssmSdk = require('@aws-sdk/client-ssm');

    secrets = new secretsSdk.SecretsManagerClient({});
    sqs = new sqsSdk.SQSClient({});
    sns = new snsSdk.SNSClient({});
    iam = new iamSdk.IAMClient({});
    ssm = new ssmSdk.SSMClient({});
    GetSecretValueCommand = secretsSdk.GetSecretValueCommand;
    PutSecretValueCommand = secretsSdk.PutSecretValueCommand;
    SendMessageCommand = sqsSdk.SendMessageCommand;
    ListSubscriptionsByTopicCommand = snsSdk.ListSubscriptionsByTopicCommand;
    GetRoleCommand = iamSdk.GetRoleCommand;
    CreateServiceLinkedRoleCommand = iamSdk.CreateServiceLinkedRoleCommand;
    GetParameterCommand = ssmSdk.GetParameterCommand;
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
  };
}

function githubBaseUrl() {
  const enterprise = String(process.env.RUNS_ON_GITHUB_ENTERPRISE_URL || '').trim();
  return enterprise ? enterprise.replace(/\/+$/, '') + '/' : 'https://github.com/';
}

function githubApiUrl() {
  const enterprise = String(process.env.RUNS_ON_GITHUB_ENTERPRISE_URL || '').trim();
  return enterprise ? enterprise.replace(/\/+$/, '') + '/api/v3/' : 'https://api.github.com/';
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

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function pageCss() {
  return `:root{color-scheme:light;--page-bg:#0f1117;--page-bg-accent:#0f1117;--panel:#fff;--panel-muted:#f8fafc;--line:#e5e7eb;--line-strong:#23272f;--text:#111827;--muted:#4b5563;--accent:#7540bf;--accent-hover:#5a2d99;--accent-soft:#f5f0ff;--healthy:#166534;--healthy-soft:#ecfdf5;--warning:#92400e;--warning-soft:#fffbeb;--error:#b91c1c;--error-soft:#fef2f2}*{box-sizing:border-box}body{margin:0;min-height:100vh;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:linear-gradient(180deg,var(--page-bg) 0%,var(--page-bg-accent) 24%,#eef2f7 24%,#eef2f7 100%);color:var(--text)}a{color:var(--accent);text-decoration:underline;text-decoration-color:rgba(117,64,191,.4);text-underline-offset:0.18em}a:hover{text-decoration-color:var(--accent)}.page{max-width:980px;margin:0 auto;padding:28px 20px 56px}.top-bar{display:flex;align-items:flex-end;justify-content:space-between;gap:18px;padding:0 0 24px;border-bottom:1px solid rgba(255,255,255,.14)}.top-bar-brand{display:flex;align-items:center;gap:12px;text-decoration:none}.top-bar-brand:hover{text-decoration:none}.logo{width:42px;height:42px;display:block}.brand-name{margin:0;font-size:18px;font-weight:800;letter-spacing:-0.01em;color:#fff}.nav-bar{display:flex;flex-wrap:wrap;gap:18px}.nav-link{display:inline-flex;align-items:center;padding:10px 0 8px;border-bottom:2px solid transparent;font-size:14px;font-weight:600;color:#8b92a1;text-decoration:none;transition:border-color .15s,color .15s}.nav-link:hover{color:#e2e5eb;text-decoration:none}.nav-link.nav-active{border-bottom-color:#c9afe4;color:#c9afe4}.card{background:var(--panel);border:1px solid var(--line-strong);padding:36px 34px 32px}.title{margin:0 0 12px;font-size:38px;line-height:1.02;letter-spacing:-0.04em}.lead{max-width:720px;margin:0 0 24px;font-size:17px;line-height:1.7;color:var(--muted)}.actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:20px}.button,.icon-button{display:inline-flex;align-items:center;justify-content:center;border:1px solid var(--accent);background:var(--accent);color:#fff;font:inherit;font-weight:700;cursor:pointer;text-decoration:none;transition:background .15s,color .15s,border-color .15s}.button{min-height:44px;padding:0 16px}.button:hover,.icon-button:hover{background:var(--accent-hover);border-color:var(--accent-hover);color:#fff;text-decoration:none}.button.secondary,.button.ghost,.icon-button.secondary{background:#fff;color:var(--accent);border-color:#d7caef}.button.secondary:hover,.button.ghost:hover,.icon-button.secondary:hover{background:var(--accent-soft);border-color:var(--accent)}.section{margin-top:30px;padding-top:22px;border-top:1px solid var(--line)}.section-header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:0 0 14px}.section h2,.section-header h2{margin:0 0 14px;font-size:20px;font-weight:700;letter-spacing:0;color:var(--text)}.section-header h2{margin:0}.icon-button{width:40px;height:40px;padding:0;font-size:18px;line-height:1}.app-list{display:grid;gap:10px}.app-card{padding:16px 20px;border:1px solid var(--line);background:var(--panel-muted)}.app-row{display:flex;align-items:center;gap:16px;justify-content:space-between}.app-identity{flex:1;min-width:0}.app-header{display:flex;align-items:center;gap:8px;margin:0 0 4px;flex-wrap:wrap}.app-name{margin:0;font-size:15px;font-weight:700;letter-spacing:-0.02em}.app-url{font-size:12px;color:var(--muted);text-decoration:none;display:block;margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.app-url:hover{color:var(--accent);text-decoration:none}.app-tag{display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border-radius:999px;font-size:11px;font-weight:700;flex-shrink:0}.app-tag::before{content:'';display:inline-block;width:6px;height:6px;border-radius:50%;flex:0 0 auto}.app-tag.healthy{background:var(--healthy-soft);color:var(--healthy)}.app-tag.healthy::before{background:#22c55e}.app-actions{flex-shrink:0}.section-desc{margin:0 0 14px;font-size:14px;color:var(--muted);line-height:1.6}.app-meta{margin:0;color:var(--muted);font-size:13px;line-height:1.5}.code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;background:#eef2f7;padding:2px 6px}.muted{color:var(--muted)}.status-badge{display:inline-flex;align-items:center;gap:7px;padding:5px 12px 5px 10px;border-radius:6px;font-size:13px;font-weight:700;letter-spacing:.01em;margin-bottom:18px}.status-badge::before{content:'';display:inline-block;width:8px;height:8px;border-radius:50%;flex:0 0 auto}.status-badge.healthy{background:var(--healthy-soft);color:var(--healthy)}.status-badge.healthy::before{background:#22c55e}.status-badge.warning{background:var(--warning-soft);color:var(--warning)}.status-badge.warning::before{background:#f59e0b}.status-badge.error{background:var(--error-soft);color:var(--error)}.status-badge.error::before{background:#ef4444}.resource-list{margin:0;padding:0;list-style:none;display:grid;gap:2px}.resource-link{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;border-radius:8px;font-size:14px;font-weight:500;color:var(--text);text-decoration:none;border:1px solid transparent;transition:background .12s,border-color .12s,color .12s}.resource-link:hover{background:var(--accent-soft);border-color:#ddd0f7;color:var(--accent);text-decoration:none}.resource-arrow{color:var(--accent);opacity:.5;font-size:14px;transition:opacity .12s}.resource-link:hover .resource-arrow{opacity:1}.notice{margin:24px 0 0;padding:11px 16px;border-left:3px solid var(--accent);background:var(--accent-soft);font-size:13px;color:#5a3d8a;line-height:1.6}.health{margin-top:30px}.health-grid{display:grid;gap:12px}.health-item{display:grid;grid-template-columns:12px minmax(0,1fr);gap:14px;align-items:flex-start;padding:16px 18px;border:1px solid var(--line);border-left-width:4px;background:var(--panel-muted)}.health-dot{width:10px;height:10px;margin-top:5px;background:#9ca3af;flex:0 0 auto}.health-item.healthy{border-left-color:#22c55e;background:var(--healthy-soft)}.health-item.healthy .health-dot{background:#22c55e}.health-item.warning{border-left-color:#f59e0b;background:var(--warning-soft)}.health-item.warning .health-dot{background:#f59e0b}.health-item.error{border-left-color:#ef4444;background:var(--error-soft)}.health-item.error .health-dot{background:#ef4444}.health-name{margin:0 0 4px;font-size:15px;font-weight:800;letter-spacing:-0.02em}.health-message,.health-hint{margin:0;font-size:14px;line-height:1.6;color:#6b7280}.health-hint{margin-top:6px}@media (max-width:640px){body{background:linear-gradient(180deg,var(--page-bg) 0%,var(--page-bg-accent) 18%,#eef2f7 18%,#eef2f7 100%)}.page{padding:18px 14px 40px}.top-bar{flex-direction:column;align-items:flex-start;padding-bottom:18px}.nav-bar{gap:14px}.card{padding:26px 22px 24px}.title{font-size:30px}.lead{font-size:16px}.section-header{align-items:center}.app-row{flex-direction:column;align-items:flex-start}.app-actions{width:100%}}`;
}

function toneForStatus(status) {
  if (status === 'ready' || status === 'healthy') return 'healthy';
  if (status === 'error') return 'error';
  return 'warning';
}

function renderNav(activePath) {
  if (!activePath) return '';
  const items = [
    { label: 'Apps', path: '/setup/apps' },
    { label: 'Status', path: '/setup/success' },
  ];
  const links = items.map((item) => {
    const active = item.path === activePath ? ' nav-active' : '';
    return `<a class="nav-link${active}" href="${escapeHtml(appUrl(item.path))}">${escapeHtml(item.label)}</a>`;
  }).join('');
  return `<nav class="nav-bar">${links}</nav>`;
}

function renderDocument(title, lead, body, activePath, preTitle) {
  const nav = renderNav(activePath);
  const preTitleHtml = preTitle || '';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(title)}</title><style>${pageCss()}</style></head><body><main class="page"><header class="top-bar"><a class="top-bar-brand" href="${escapeHtml(appUrl('/setup/apps'))}"><img class="logo" src="https://runs-on.com/logo.png" alt="RunsOn logo"><span class="brand-name">RunsOn</span></a>${nav}</header><section class="card">${preTitleHtml}<h1 class="title">${escapeHtml(title)}</h1><p class="lead">${escapeHtml(lead)}</p>${body}</section></main></body></html>`;
}

function renderPage(title, lead, body, statusCode = 200, activePath = null, preTitle = '') {
  return htmlResponse(renderDocument(title, lead, body, activePath, preTitle), statusCode);
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
    const match = pathname.match(/\/apps\/([^/]+)$/) || pathname.match(/\/settings\/apps\/([^/]+)$/);
    return match ? decodeURIComponent(match[1]) : '';
  } catch (_) {
    return '';
  }
}

function appPublicUrl(appConfig) {
  const rawUrl = String(appConfig?.html_url || '').trim();
  if (rawUrl) return rawUrl;

  const slug = appSlugFromConfig(appConfig);
  return slug ? githubBaseUrl() + 'apps/' + encodeURIComponent(slug) : '';
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

function manifestForPrimary() {
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
    description: 'Deploy ephemeral and cheap self-hosted runners for your GitHub Actions workflows, in your AWS account',
    hook_attributes: { url: url + '/github/webhooks' },
    name: `RunsOn [${process.env.RUNS_ON_GITHUB_ORG}]`,
    public: false,
    redirect_url: url + '/setup/convert',
    setup_url: url + '/setup/success',
    setup_on_update: true,
    url: 'https://runs-on.com',
    version: 'v1',
  };
}

function manifestForBoost(idFactory) {
  const url = baseUrl();
  const suffix = String(idFactory()).replaceAll('-', '').slice(0, 8);
  return {
    default_permissions: {
      administration: 'write',
    },
    description: 'API-only RunsOn GitHub App for same-organization rate-limit expansion',
    name: `RunsOn API Boost [${process.env.RUNS_ON_GITHUB_ORG}] ${suffix}`,
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

function renderSetupPage() {
  const manifest = manifestForPrimary();
  const action = githubBaseUrl() + 'organizations/' + process.env.RUNS_ON_GITHUB_ORG + '/settings/apps/new';
  return renderPage(
    'Welcome to RunsOn',
    'Register a GitHub App for your organization to start receiving workflow webhooks and launching runners.',
    `<form action="${escapeHtml(action)}" method="post"><input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(manifest))}"><div class="actions"><button class="button" type="submit">Register GitHub App</button></div></form>`,
  );
}

function renderHealthIndicators(indicators) {
  if (!Array.isArray(indicators) || indicators.length === 0) return '';
  const header = `<div class="section-header"><h2>Health checks</h2><button class="icon-button secondary" type="button" title="Refresh health checks" aria-label="Refresh health checks" onclick="window.location.reload()">&#8635;</button></div>`;
  const items = indicators.map((indicator) => {
    const tone = toneForStatus(indicator.status);
    const hint = indicator.hint ? `<p class="health-hint">${escapeHtml(indicator.hint)}</p>` : '';
    const link = indicator.url ? `<p class="health-hint"><a href="${escapeHtml(indicator.url)}">Learn more</a></p>` : '';
    return `<article class="health-item ${escapeHtml(tone)}"><div class="health-dot"></div><div><p class="health-name">${escapeHtml(indicator.name)}</p><p class="health-message">${escapeHtml(indicator.message)}</p>${hint}${link}</div></article>`;
  }).join('');
  return `<section class="health section">${header}<div class="health-grid">${items}</div></section>`;
}

function renderResources() {
  const links = [
    { href: 'https://runs-on.com/docs/', label: 'Documentation' },
    { href: 'https://github.com/runs-on/runs-on', label: 'GitHub project' },
    { href: 'https://github.com/runs-on/runs-on/releases', label: 'Latest releases' },
    { href: 'https://runs-on.com/pricing/', label: 'Pricing &amp; license' },
  ];
  const items = links.map(({ href, label }) => `<li><a class="resource-link" href="${escapeHtml(href)}">${label}<span class="resource-arrow">&#8594;</span></a></li>`).join('');
  return `<section class="section"><div class="section-header"><h2>Resources</h2></div><ul class="resource-list">${items}</ul></section>`;
}

function renderSetupSuccessPage(state, indicators) {
  const title = state.hasPrimaryApp ? 'RunsOn setup complete' : 'RunsOn setup';
  const summary = state.hasPrimaryApp
    ? 'GitHub App configuration is stored for this stack.'
    : 'GitHub App setup is still in progress.';

  let preTitle = '';
  if (state.hasPrimaryApp && Array.isArray(indicators) && indicators.length > 0) {
    const allHealthy = indicators.every((i) => toneForStatus(i.status) === 'healthy');
    const hasError = indicators.some((i) => toneForStatus(i.status) === 'error');
    const tone = allHealthy ? 'healthy' : hasError ? 'error' : 'warning';
    const label = allHealthy ? 'All checks passed' : hasError ? 'Issues detected' : 'Attention needed';
    preTitle = `<div class="status-badge ${escapeHtml(tone)}">${escapeHtml(label)}</div>`;
  }

  const notice = `<p class="notice">These setup pages can be disabled by setting the <span class="code">EnableAdminRoutes</span> stack parameter to <span class="code">false</span>.</p>`;
  return renderPage(title, summary, `${renderHealthIndicators(indicators)}${renderResources()}${notice}`, 200, '/setup/success', preTitle);
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

function renderAppCard(name, appHref, meta, actions, tag) {
  const tagHtml = tag ? `<span class="app-tag ${escapeHtml(tag.tone)}">${escapeHtml(tag.label)}</span>` : '';
  const urlHtml = appHref ? `<a class="app-url" href="${escapeHtml(appHref)}">${escapeHtml(appHref.replace('https://', ''))}</a>` : '';
  const metaHtml = meta ? `<p class="app-meta">${meta}</p>` : '';
  const actionsHtml = actions.length > 0 ? `<div class="app-actions">${actions.join('')}</div>` : '';
  return `<div class="app-card"><div class="app-row"><div class="app-identity"><div class="app-header"><span class="app-name">${escapeHtml(name)}</span>${tagHtml}</div>${urlHtml}${metaHtml}</div>${actionsHtml}</div></div>`;
}

function renderAppsPage(state, idFactory) {
  const action = githubBaseUrl() + 'organizations/' + process.env.RUNS_ON_GITHUB_ORG + '/settings/apps/new';
  const boostManifest = manifestForBoost(idFactory);

  const primaryActions = [];
  if (state.installationsUrl) {
    primaryActions.push(`<a class="button ghost" href="${escapeHtml(state.installationsUrl)}">Open Installations</a>`);
  }
  const primaryCard = renderAppCard(
    state.appName || 'Primary GitHub App',
    state.appHref,
    'Manages workflow webhook intake for this stack.',
    primaryActions,
    { tone: 'healthy', label: 'Connected' },
  );

  const boosts = boostEntries(state.persisted);
  const boostCards = boosts.length === 0
    ? '<p class="muted">No API boost apps configured yet.</p>'
    : `<div class="app-list">${boosts.map((boost) => {
      const boostActions = boost.installationUrl
        ? [`<a class="button secondary" href="${escapeHtml(boost.installationUrl)}">Open Installations</a>`]
        : [];
      return renderAppCard(
        boost.label,
        boost.appHref,
        `app key: <span class="code">${escapeHtml(boost.appKey)}</span>`,
        boostActions,
        { tone: 'healthy', label: 'Connected' },
      );
    }).join('')}</div>`;

  return renderPage(
    'GitHub apps',
    'Manage the control-plane GitHub App and add same-organization API boost apps.',
    `<section class="section"><h2>Primary app</h2>${primaryCard}</section><section class="section"><h2>API boost apps</h2><p class="section-desc">Only add extra GitHub Apps to this organization after your logs show GitHub rate-limit issues while RunsOn is generating runner JIT tokens.</p>${boostCards}<form action="${escapeHtml(action)}" method="post"><input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(boostManifest))}"><div class="actions" style="margin-top:20px"><button class="button" type="submit">Add Boost App</button></div></form></section>`,
    200,
    '/setup/apps',
  );
}

function renderProblemPage(title, lead, message, statusCode = 400) {
  return renderPage(
    title,
    lead,
    `<p class="muted">${escapeHtml(message)}</p><div class="actions"><a class="button secondary" href="${escapeHtml(appUrl('/setup/apps'))}">Back to Apps</a></div>`,
    statusCode,
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

async function loadStackReadyConfig(aws) {
  const arn = String(process.env.RUNS_ON_STACK_CONFIG_SECRET_ARN || '').trim();
  if (!arn) {
    log('warn', 'Stack config secret ARN is not configured');
    return readyConfigFromStackConfig(null);
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
      return readyConfigFromStackConfig(null);
    }
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      parsed = null;
    }
    return readyConfigFromStackConfig(parsed);
  } catch (error) {
    if (isResourceNotFound(error)) {
      log('warn', 'Stack config secret not found');
      return readyConfigFromStackConfig(null);
    }
    throw error;
  }
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
    hint: 'Check your email inbox for a confirmation email from AWS',
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
      }
    }
  }
  indicators.push(spotIndicator);

  return indicators;
}

function createHandler(options = {}) {
  const aws = options.aws || createDefaultAws();
  const fetchImpl = options.fetchImpl || fetch;
  const uuid = options.uuid || (() => crypto.randomUUID());

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

  async function convertManifest(code) {
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
      return { error: jsonResponse(500, { error: 'app manifest conversion failed', status: response.status }) };
    }
    return { appConfig: await response.json() };
  }

  async function convertPrimary(request, currentState) {
    const code = request.queryStringParameters?.code || '';
    if (!code) {
      log('warn', 'Rejecting setup convert request without code');
      return jsonResponse(400, { error: 'missing code parameter' });
    }

    log('info', 'Processing primary GitHub App manifest conversion');
    const conversion = await convertManifest(code);
    if (conversion.error) return conversion.error;

    const appConfig = conversion.appConfig;
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

  async function convertBoost(request, currentState) {
    const code = request.queryStringParameters?.code || '';
    if (!code) {
      log('warn', 'Rejecting boost convert request without code');
      return jsonResponse(400, { error: 'missing code parameter' });
    }

    log('info', 'Processing GitHub boost app manifest conversion');
    const conversion = await convertManifest(code);
    if (conversion.error) return conversion.error;

    const appConfig = conversion.appConfig || {};
    const appKey = String(appConfig.slug || '').trim();
    if (!appKey) {
      return renderProblemPage('Boost app setup failed', 'GitHub did not return a stable app slug.', 'The GitHub manifest conversion response did not contain a slug, so the app could not be stored safely.', 500);
    }
    if (appKey === 'primary') {
      return renderProblemPage('Boost app setup failed', 'The generated GitHub app slug is reserved.', 'Choose a different app name and try again.', 409);
    }

    const persisted = clonePersisted(currentState.persisted);
    persisted.boosts = persisted.boosts && typeof persisted.boosts === 'object' ? persisted.boosts : {};
    if (persisted.boosts[appKey]) {
      return renderProblemPage('Boost app already exists', 'A boost app with this GitHub slug is already configured for the stack.', `The app key ${appKey} is already present in the shared GitHub apps secret.`, 409);
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

  async function setupSuccess() {
    const state = await loadState();
    if (!state.hasPrimaryApp) return redirect('/setup');
    const indicators = await buildHealthIndicators(aws);
    log('info', 'Rendering setup success page', {
      has_primary_app: state.hasPrimaryApp,
      app_id: state.appId,
    });
    return renderSetupSuccessPage(state, indicators);
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
          response = state.hasPrimaryApp ? redirect('/setup/apps') : renderSetupPage();
        }
      } else if (path === '/setup/convert') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          const state = await loadState();
          response = state.hasPrimaryApp ? redirect('/setup/apps') : await convertPrimary(request, state);
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
          response = state.hasPrimaryApp ? renderAppsPage(state, uuid) : redirect('/setup');
        }
      } else if (path === '/setup/apps/convert') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          const state = await loadState();
          response = state.hasPrimaryApp ? await convertBoost(request, state) : redirect('/setup');
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
      return jsonResponse(500, { error: 'internal server error' });
    }
  };
}

module.exports = {
  buildPendingPersistedGitHubApps,
  createHandler,
  handler: createHandler(),
  renderSetupSuccessPage,
};
