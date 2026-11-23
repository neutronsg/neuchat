import { summarizeSafety } from '../safetyReport';
const event = (overrides = {}) => ({
  conversation_id: 1,
  message_id: 10,
  attempt_id: 'a',
  created_at: '2026-11-01T06:30:00Z',
  day: '2026-11-01',
  stage: 'input',
  provider: 'aws',
  mode: 'aws_shadow',
  enforced: true,
  status: 'allow',
  reason: 'none',
  ...overrides,
});
describe('Request-level safety reporting', () => {
  it('deduplicates stages, providers and retries without losing an earlier block or error', () => {
    const { requests } = summarizeSafety([
      event({ status: 'error' }),
      event({ attempt_id: 'b', status: 'block', reason: 'violence' }),
      event({
        attempt_id: 'b',
        stage: 'output',
        status: 'block',
        reason: 'violence',
      }),
      event({ attempt_id: 'c', stage: 'output' }),
    ]);
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({
      blocked: true,
      failed: true,
      result: 'block',
      reasons: ['violence'],
      aws: 'block',
    });
    expect(requests[0].checks).toHaveLength(4);
  });
  it('does not treat shadow blocks as enforced blocks, and excludes dual mode from comparison', () => {
    const { requests, comparison } = summarizeSafety([
      event(),
      event({ provider: 'custom', enforced: false, status: 'block' }),
      event({ message_id: 11, attempt_id: 'b', mode: 'aws_custom' }),
      event({
        message_id: 11,
        attempt_id: 'b',
        mode: 'aws_custom',
        provider: 'custom',
        status: 'block',
      }),
    ]);
    expect(requests.find(r => r.messageId === 10).blocked).toBe(false);
    expect(requests.find(r => r.messageId === 11).blocked).toBe(true);
    expect(comparison).toMatchObject({
      custom_only: 1,
      aws_only: 0,
      unavailable: 0,
    });
  });
  it('never compares different attempts or stages and preserves missing evidence', () => {
    const { comparison, requests } = summarizeSafety([
      event({ status: 'block' }),
      event({ attempt_id: 'b', provider: 'custom', enforced: false }),
      event({
        stage: 'output',
        provider: 'custom',
        enforced: false,
        status: 'unavailable',
      }),
      event({ message_id: 20, status: 'unavailable' }),
    ]);
    expect(comparison.unavailable).toBe(4);
    expect(comparison.both_allow).toBe(0);
    expect(requests.find(r => r.messageId === 20).result).toBe('unavailable');
  });
  it('surfaces a shadow failure without presenting it as an enforced refusal', () => {
    const { requests } = summarizeSafety([
      event(),
      event({ provider: 'custom', enforced: false, status: 'timeout' }),
    ]);
    expect(requests[0]).toMatchObject({
      reviewFailed: true,
      failed: false,
      blocked: false,
      result: 'no_block',
    });
  });
  it.each(['skipped', 'unavailable'])(
    'counts required shadow %s as missing without claiming an enforced block',
    status => {
      const { requests, comparison } = summarizeSafety([
        event(),
        event({ provider: 'custom', enforced: false, status }),
      ]);
      expect(requests[0]).toMatchObject({
        incomplete: true,
        enforcedIncomplete: false,
        shadowMissing: true,
        blocked: false,
        result: 'no_block',
      });
      expect(comparison.unavailable).toBe(1);
    }
  );
  it('does not count downstream unavailability after an input block as a review issue', () => {
    const { requests, comparison } = summarizeSafety([
      event({ status: 'block' }),
      event({ provider: 'custom', enforced: false, status: 'block' }),
      event({ stage: 'output', status: 'unavailable' }),
      event({
        stage: 'output',
        provider: 'custom',
        enforced: false,
        status: 'unavailable',
      }),
    ]);
    expect(requests[0]).toMatchObject({
      incomplete: false,
      reviewFailed: false,
      blocked: true,
      result: 'block',
    });
    expect(requests[0].checks.filter(c => c.notRequired)).toHaveLength(2);
    expect(comparison).toMatchObject({ both_block: 1, unavailable: 1 });
  });
  it('marks only shadow output unnecessary when AWS blocks its output', () => {
    const { requests } = summarizeSafety([
      event(),
      event({ stage: 'output', status: 'block' }),
      event({
        stage: 'output',
        provider: 'custom',
        enforced: false,
        status: 'unavailable',
      }),
    ]);
    expect(requests[0]).toMatchObject({
      incomplete: false,
      blocked: true,
      custom: 'not_required',
    });
  });
  it('never lets an earlier attempt or a shadow block excuse a missing check', () => {
    const { requests } = summarizeSafety([
      event({ status: 'block' }),
      event({ attempt_id: 'retry', status: 'allow' }),
      event({ attempt_id: 'retry', stage: 'output', status: 'unavailable' }),
      event({
        message_id: 11,
        provider: 'custom',
        enforced: false,
        status: 'block',
      }),
      event({ message_id: 11 }),
      event({ message_id: 11, stage: 'output', status: 'unavailable' }),
    ]);
    expect(requests.every(r => r.incomplete)).toBe(true);
    expect(requests.flatMap(r => r.checks).some(c => c.notRequired)).toBe(
      false
    );
  });
  it('preserves actual errors and missing input even when the same attempt has a block', () => {
    const { requests } = summarizeSafety([
      event({ status: 'block' }),
      event({ provider: 'custom', enforced: false, status: 'skipped' }),
      event({
        provider: 'custom',
        enforced: false,
        stage: 'output',
        status: 'timeout',
      }),
    ]);
    expect(requests[0]).toMatchObject({ incomplete: true, reviewFailed: true });
    expect(requests[0].checks.some(c => c.notRequired)).toBe(false);
  });
  it('keeps conversations distinct and falls back to attempts for old records without message IDs', () => {
    const { requests } = summarizeSafety([
      event(),
      event({ conversation_id: 2 }),
      event({ message_id: null, attempt_id: 'old1' }),
      event({ message_id: null, attempt_id: 'old2' }),
    ]);
    expect(requests).toHaveLength(4);
  });
  it('uses the earliest in-range check day and does not infer delivery from an allow', () => {
    const { requests } = summarizeSafety([
      event({
        day: '2026-11-02',
        created_at: '2026-11-02T06:30:00Z',
        stage: 'output',
      }),
      event(),
    ]);
    expect(requests[0]).toMatchObject({
      day: '2026-11-01',
      result: 'no_block',
    });
  });
});
