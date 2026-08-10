'use strict';

const crypto = require('node:crypto');

const WORKFLOW_JOB_GROUP_BUCKETS = 32;
const WORKFLOW_RUN_GROUP_BUCKETS = 16;

function createDefaultAws() {
  let initialized = false;
  let sqs;
  let SendMessageCommand;

  function init() {
    if (initialized) return;
    initialized = true;
    const sqsSdk = require('@aws-sdk/client-sqs');

    sqs = new sqsSdk.SQSClient({});
    SendMessageCommand = sqsSdk.SendMessageCommand;
  }

  return {
    async sendQueueMessage(params) {
      init();
      return sqs.send(new SendMessageCommand(params));
    },
  };
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
    body: event.body,
    isBase64Encoded: !!event.isBase64Encoded,
  };
}

function payloadBuffer(request) {
  const body = String(request?.body || '');
  return request?.isBase64Encoded ? Buffer.from(body, 'base64') : Buffer.from(body, 'utf8');
}

function extractJobId(payload, eventType) {
  if (eventType === 'workflow_job') return Number(payload?.workflow_job?.id || 0);
  return 0;
}

function extractRunId(payload, eventType) {
  if (eventType === 'workflow_job') return Number(payload?.workflow_job?.run_id || 0);
  if (eventType === 'workflow_run') return Number(payload?.workflow_run?.id || 0);
  return 0;
}

function webhookLogFields(payload, eventType, deliveryId) {
  const fields = {
    delivery_id: deliveryId,
    event_type: eventType,
    action: String(payload?.action || '').trim(),
    repository: String(payload?.repository?.full_name || '').trim(),
  };

  if (eventType === 'workflow_job') {
    fields.job_id = Number(payload?.workflow_job?.id || 0);
    fields.run_id = Number(payload?.workflow_job?.run_id || 0);
    fields.job_name = String(payload?.workflow_job?.name || '').trim();
    fields.workflow_name = String(payload?.workflow_job?.workflow_name || '').trim();
    fields.job_url = String(payload?.workflow_job?.html_url || payload?.workflow_job?.url || '').trim();
    fields.labels = Array.isArray(payload?.workflow_job?.labels) ? payload.workflow_job.labels : [];
    return fields;
  }

  if (eventType === 'workflow_run') {
    fields.run_id = Number(payload?.workflow_run?.id || 0);
    fields.workflow_name = String(payload?.workflow_run?.name || '').trim();
    fields.run_url = String(payload?.workflow_run?.html_url || payload?.workflow_run?.url || '').trim();
    fields.status = String(payload?.workflow_run?.status || '').trim();
    fields.conclusion = String(payload?.workflow_run?.conclusion || '').trim();
  }

  return fields;
}

// GitHub intermittently delivers workflow_job events whose job object is an
// explicit null, and an unparseable body leaves payload null here too. Either
// way there is no job id and no labels, so nothing can be scheduled from the
// event.
function isUsableWorkflowJob(payload) {
  const job = payload?.workflow_job;
  return Boolean(job) && typeof job === 'object';
}

function shouldEnqueueWebhook(payload, eventType) {
  if (eventType !== 'workflow_job') return true;
  // Drop unusable events at the door rather than forward something the
  // consumer cannot act on.
  if (!isUsableWorkflowJob(payload)) return false;
  const labels = Array.isArray(payload.workflow_job.labels) ? payload.workflow_job.labels : null;
  if (!labels) return true;
  return labels.some((label) => {
    const value = String(label || '');
    return value.includes('runs-on') || value.includes('dependabot');
  });
}

function webhookGroupId(payload, eventType, deliveryId, requestId) {
  // Keep the webhook queue FIFO so SQS still gives us delivery deduplication
  // and in-order processing within a bucket. The important ordering boundary
  // for the hot path is the individual workflow job, not the whole workflow
  // run. Large matrix runs can emit many sibling jobs at once, and grouping all
  // of them by run artificially serializes queued-job ingestion behind a single
  // FIFO lane. Grouping workflow_job events by job ID keeps queued -> waiting ->
  // queued -> in_progress -> completed ordered for one job while letting other
  // jobs from the same run advance in parallel.
  const jobId = extractJobId(payload, eventType);
  if (jobId > 0) return 'job-' + String(jobId % WORKFLOW_JOB_GROUP_BUCKETS);

  // workflow_run events are not the hot path that triggers scheduling, so keep
  // them grouped at run granularity. That preserves a stable ordering model for
  // run-level metadata updates without coupling workflow_job throughput to it.
  const runId = extractRunId(payload, eventType);
  if (runId > 0) return 'run-' + String(runId % WORKFLOW_RUN_GROUP_BUCKETS);

  // Installation and malformed payloads do not have stable job/run identity.
  // Hash the delivery/request identity into a bounded fallback bucket so we
  // still satisfy FIFO queue requirements without creating unbounded group IDs.
  const fallback = String(deliveryId || requestId || 'fallback').trim();
  const digest = crypto.createHash('sha256').update(fallback).digest('hex');
  return 'delivery-' + digest.slice(0, 8);
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

function createHandler(options = {}) {
  const aws = options.aws || createDefaultAws();

  async function enqueueWebhook(request) {
    const headers = request.headers;
    const deliveryId = String(headers['x-github-delivery'] || '').trim();
    const eventType = String(headers['x-github-event'] || '').trim();
    const provided = String(headers['x-hub-signature-256'] || '').trim();
    const payload = payloadBuffer(request).toString('utf8');

    let parsedBody;
    let parseError = false;
    try {
      parsedBody = JSON.parse(payload);
    } catch (_) {
      parsedBody = null;
      parseError = true;
    }

    const logFields = webhookLogFields(parsedBody, eventType, deliveryId);
    log('info', 'Received GitHub webhook', logFields);
    let invalidReason = '';
    if (!deliveryId) invalidReason = 'missing_delivery_id';
    else if (!eventType) invalidReason = 'missing_event_type';
    else if (!provided) invalidReason = 'missing_signature';
    else if (parseError) invalidReason = 'invalid_json';
    else if (!parsedBody || typeof parsedBody !== 'object' || Array.isArray(parsedBody)) invalidReason = 'invalid_json_object';

    if (invalidReason) {
      log('warn', 'Dropping malformed GitHub webhook', {
        delivery_id: deliveryId,
        event_type: eventType,
        reason: invalidReason,
      });
      return jsonResponse(202, { status: 'ignored', reason: 'invalid_payload' });
    }
    if (!shouldEnqueueWebhook(parsedBody, eventType)) {
      const unusableJob = eventType === 'workflow_job' && !isUsableWorkflowJob(parsedBody);
      log(
        'info',
        unusableJob
          ? 'Skipping workflow_job webhook with no usable job object'
          : 'Skipping GitHub webhook without RunsOn labels',
        logFields,
      );
      return jsonResponse(202, { status: 'ignored' });
    }

    const groupId = webhookGroupId(parsedBody, eventType, deliveryId, request.requestId);
    // Keep deduplication tied to the GitHub delivery so a retried webhook does
    // not get re-enqueued, even though different lifecycle events for the same
    // job are intentionally free to land in the same FIFO job bucket.
    const deduplicationId = String(deliveryId || request.requestId || groupId).trim();
    log('info', 'Queueing GitHub webhook', {
      message_group_id: groupId,
      ...logFields,
    });
    await aws.sendQueueMessage({
      QueueUrl: process.env.RUNS_ON_WEBHOOKS_QUEUE_URL,
      MessageBody: JSON.stringify({
        event_type: eventType,
        delivery_id: deliveryId,
        signature_256: provided,
        payload,
      }),
      MessageDeduplicationId: deduplicationId,
      MessageGroupId: groupId,
    });
    log('info', 'Queued GitHub webhook', {
      message_group_id: groupId,
      ...logFields,
    });
    return jsonResponse(202, { status: 'accepted' });
  }

  return async function handler(event) {
    const request = requestFor(event);
    const method = request.method;
    const path = request.path;
    const requestId = request.requestId;

    log('info', 'Public ingress request received', {
      request_id: requestId,
      method,
      path,
    });

    try {
      let response;
      if (path === '/github/webhooks') {
        response = method === 'POST' ? await enqueueWebhook(request) : methodNotAllowed(['POST']);
      } else {
        response = jsonResponse(404, { error: 'not found' });
      }

      log('info', 'Public ingress request completed', {
        request_id: requestId,
        method,
        path,
        status_code: response.statusCode,
      });
      return response;
    } catch (error) {
      log('error', 'Public ingress request failed', {
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
  createHandler,
  handler: createHandler(),
};
