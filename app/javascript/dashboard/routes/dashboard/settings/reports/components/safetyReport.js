const failures = new Set(['error', 'timeout', 'indeterminate', 'unsupported']);
const missing = new Set(['unavailable', 'skipped']);
const severity = [
  'block',
  'error',
  'timeout',
  'indeterminate',
  'unsupported',
  'unavailable',
  'skipped',
  'masked',
  'allow',
];

export function summarizeProvider(events, provider) {
  const providerChecks = events.filter(event => event.provider === provider);
  const checks = providerChecks.filter(check => !check.notRequired);
  return (
    severity.find(status => checks.some(check => check.status === status)) ||
    (providerChecks.length ? 'not_required' : 'not_recorded')
  );
}

// A message may have several attempts, providers and stages. Keep all evidence,
// but never count those checks as separate user requests.
function dimensionStatus(checks, dimension) {
  const values = checks
    .filter(check => check.enforced)
    .flatMap(check => {
      if (check.notRequired) return [];
      if (dimension === 'basic' && check.scope === 'basic')
        return [check.status];
      if (check.scope !== 'split') return [];
      if (
        dimension === 'basic' &&
        ['hybrid', 'hybrid_shadow'].includes(check.mode)
      )
        return [];
      return [check[`${dimension}_status`] || check.status];
    });
  if (!values.length) {
    if (
      dimension === 'business' &&
      checks.some(check => check.scope === 'basic') &&
      !checks.some(check => check.provider === 'custom' && check.enforced)
    )
      return 'not_enabled';
    if (checks.some(check => !check.scope || check.scope === 'legacy'))
      return 'legacy';
    return checks.some(
      check =>
        check.enforced && check.stage === 'input' && check.status === 'block'
    )
      ? 'not_required'
      : 'not_recorded';
  }
  return severity.find(status => values.includes(status)) || 'unavailable';
}

export function summarizeSafety(events = []) {
  const grouped = new Map();
  events.forEach(event => {
    const key = JSON.stringify([
      event.conversation_id,
      event.message_id ?? `attempt:${event.attempt_id}`,
    ]);
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(event);
  });
  const requests = [...grouped.entries()]
    .map(([key, records]) => {
      // Only an enforced block from the same attempt makes downstream review
      // unnecessary. A shadow suggestion or an older retry cannot excuse it.
      const inputBlocks = new Set(
        records
          .filter(
            check =>
              check.enforced &&
              check.stage === 'input' &&
              check.status === 'block'
          )
          .map(check => check.attempt_id)
      );
      const awsOutputBlocks = new Set(
        records
          .filter(
            check =>
              check.enforced &&
              check.provider === 'aws' &&
              check.stage === 'output' &&
              check.status === 'block'
          )
          .map(check => check.attempt_id)
      );
      const checks = records.map(check => ({
        ...check,
        notRequired:
          missing.has(check.status) &&
          check.stage === 'output' &&
          (inputBlocks.has(check.attempt_id) ||
            (['aws_shadow', 'hybrid_shadow'].includes(check.mode) &&
              check.provider === 'custom' &&
              !check.enforced &&
              awsOutputBlocks.has(check.attempt_id))),
      }));
      checks.sort((a, b) => a.created_at.localeCompare(b.created_at));
      const enforced = checks.filter(check => check.enforced);
      const blocked = enforced.some(check => check.status === 'block');
      const failed = enforced.some(check => failures.has(check.status));
      const isMissing = check =>
        missing.has(check.status) && !check.notRequired;
      const enforcedIncomplete = !enforced.length || enforced.some(isMissing);
      const incomplete = enforcedIncomplete || checks.some(isMissing);
      const pairs = new Map();
      checks
        .filter(check => ['aws_shadow', 'hybrid_shadow'].includes(check.mode))
        .forEach(check => {
          const pairKey = `${check.attempt_id}:${check.stage}`;
          if (!pairs.has(pairKey)) pairs.set(pairKey, []);
          pairs.get(pairKey).push(check);
        });
      const comparisons = [...pairs.values()].map(pair => {
        const aws = pair.find(check => check.provider === 'aws');
        const rawCustom = pair.find(check => check.provider === 'custom');
        const custom =
          rawCustom?.scope === 'split'
            ? { ...rawCustom, status: rawCustom.basic_status }
            : rawCustom;
        if (
          !aws ||
          !custom ||
          (custom.scope === 'split' &&
            (!aws.evidence_hash ||
              aws.evidence_hash !== custom.evidence_hash)) ||
          ![aws.status, custom.status].every(status =>
            ['allow', 'block'].includes(status)
          )
        )
          return 'unavailable';
        if (aws.status === custom.status)
          return aws.status === 'allow' ? 'both_allow' : 'both_block';
        return aws.status === 'block' ? 'aws_only' : 'custom_only';
      });
      return {
        key,
        checks,
        comparisons,
        blocked,
        failed,
        reviewFailed: checks.some(
          check =>
            failures.has(check.status) ||
            (check.mode === 'hybrid_shadow' && failures.has(check.basic_status))
        ),
        incomplete,
        enforcedIncomplete,
        shadowMissing: checks.some(
          check => !check.enforced && isMissing(check)
        ),
        conversationId: checks[0].conversation_id,
        messageId: checks[0].message_id,
        createdAt: checks[0].created_at,
        day: checks[0].day,
        modes: [...new Set(checks.map(check => check.mode))],
        reasons: [
          ...new Set(
            enforced
              .filter(check => check.status === 'block')
              .map(check => check.reason)
          ),
        ],
        result:
          [
            ['block', blocked],
            ['error', failed],
            ['unavailable', enforcedIncomplete],
          ].find(([, matches]) => matches)?.[0] || 'no_block',
        basic: dimensionStatus(checks, 'basic'),
        business: dimensionStatus(checks, 'business'),
        legacy: checks.some(check => !check.scope || check.scope === 'legacy'),
        legacyBlocked: checks.some(
          check =>
            (!check.scope || check.scope === 'legacy') &&
            check.enforced &&
            check.status === 'block'
        ),
        comparisonScope: checks.some(check => check.scope === 'basic')
          ? 'basic'
          : 'legacy',
        aws: summarizeProvider(checks, 'aws'),
        custom: summarizeProvider(checks, 'custom'),
      };
    })
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  const comparison = Object.fromEntries(
    ['both_allow', 'both_block', 'aws_only', 'custom_only', 'unavailable'].map(
      key => [key, 0]
    )
  );
  requests.forEach(request =>
    request.comparisons.forEach(key => {
      comparison[key] += 1;
    })
  );
  return { requests, comparison };
}
