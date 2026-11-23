import { downloadReport } from '../reportDownload';
vi.mock('../reportDownload', async original => ({
  ...(await original()),
  downloadReport: vi.fn(),
}));
import { shallowMount, flushPromises } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
import OcaCostEstimate from '../OcaCostEstimate.vue';
import OcaBotReports from '../OcaBotReports.vue';
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));
vi.mock('dashboard/api/reports', () => ({
  default: {
    getBotOutcomes: vi.fn(),
    getBotMetrics: vi.fn(),
    getBotUsage: vi.fn(),
    getBotOutcomesCSV: vi.fn(),
  },
}));
const data = {
  days: [],
  categories: {},
  details: [],
  resolution_rate: 0,
  escalation_rate: 0,
  detail_total: 0,
  tracking_started_at: null,
};
function mount() {
  return shallowMount(OcaBotReports, {
    props: { filters: { from: 1000, to: 2000 } },
    global: { stubs: { 'router-link': true }, mocks: { $t: key => key } },
  });
}
describe('OCA Bot reports', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ReportsAPI.getBotOutcomes.mockResolvedValue({ data });
    ReportsAPI.getBotMetrics.mockResolvedValue({
      data: { conversation_count: 0, message_count: 0 },
    });
    ReportsAPI.getBotUsage.mockResolvedValue({
      data: { days: [], total: null, currency: 'USD' },
    });
  });
  it('shows an empty report with zero rates and no fabricated cost', async () => {
    const wrapper = mount();
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.NO_CONVERSATIONS');
    expect(wrapper.text()).toContain('—');
    expect(
      wrapper.findAllComponents({ name: 'ReportMetricCard' })[2].props('value')
    ).toBe('0%');
  });
  it('shows separate costs and incomplete/stale estimates without pretending missing Guardrails usage is free', async () => {
    ReportsAPI.getBotUsage.mockResolvedValue({
      data: {
        storage: 'long_term_metering',
        days: [],
        currency: 'USD',
        priceSyncStale: true,
        total: {
          estimatedCostUsd: 1.2,
          estimatedGuardrailCostUsd: null,
          estimatedCombinedCostUsd: 1.2,
          unpricedCalls: 0,
          unpricedGuardrailCalls: 2,
          guardrailCalls: 2,
        },
      },
    });
    const wrapper = mount();
    await flushPromises();
    const costs = shallowMount(OcaCostEstimate, {
      props: { usage: wrapper.findComponent(OcaCostEstimate).props('usage') },
      global: { mocks: { $t: key => key } },
    });
    expect(costs.text()).toContain('OCA_REPORT.GUARDRAIL_COST');
    expect(costs.text()).toContain('OCA_REPORT.KNOWN_SUBTOTAL');
    expect(costs.text()).toContain('OCA_REPORT.PARTIAL_COST');
    expect(costs.text()).toContain('OCA_REPORT.PRICE_STALE');
    expect(costs.text()).toContain('OCA_REPORT.LONG_TERM_COST_NOTE');
    expect(costs.text()).toContain('—');
    expect(wrapper.text()).not.toContain('OCA_REPORT.GUARDRAIL_COST');
  });
  it('shows usage failure independently from successful conversation reporting', async () => {
    ReportsAPI.getBotUsage.mockRejectedValue(new Error('unavailable'));
    const wrapper = mount();
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.USAGE_ERROR');
    expect(
      wrapper.findComponent({ name: 'OcaEscalationDetails' }).exists()
    ).toBe(true);
  });
  it('ignores an obsolete report response after changing filters', async () => {
    let finish;
    ReportsAPI.getBotOutcomes.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount();
    await wrapper.setProps({ filters: { from: 2000, to: 3000 } });
    await flushPromises();
    finish({ data: { ...data, resolution_rate: 99 } });
    await flushPromises();
    expect(
      wrapper.findAllComponents({ name: 'ReportMetricCard' })[2].props('value')
    ).toBe('0%');
  });
  it('resets pagination when changing reasons and ignores stale usage after a date round trip', async () => {
    let finish;
    ReportsAPI.getBotUsage.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount();
    await flushPromises();
    wrapper.findComponent({ name: 'OcaEscalationDetails' }).vm.$emit('page', 2);
    await flushPromises();
    wrapper
      .findComponent({ name: 'OcaEscalationDetails' })
      .vm.$emit('filter', 'no_answer_found');
    await flushPromises();
    expect(ReportsAPI.getBotOutcomes).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 1, reason: 'no_answer_found' })
    );
    await wrapper.setProps({ filters: { from: 2000, to: 3000 } });
    await wrapper.setProps({ filters: { from: 1000, to: 2000 } });
    await flushPromises();
    finish({
      data: { days: [], total: { inputTokens: 999999 }, currency: 'USD' },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('999,999');
  });
});

it('hides non-applicable Guardrails and distinguishes no data from zero cost', () => {
  const wrapper = shallowMount(OcaCostEstimate, {
    props: {
      usage: {
        storage: 'long_term_metering',
        total: {
          guardrailCalls: 0,
          estimatedCostUsd: 0,
          estimatedCombinedCostUsd: 0,
        },
        priceSourceMode: 'maintained_table',
      },
    },
    global: { mocks: { $t: key => key } },
  });
  expect(wrapper.text()).not.toContain('OCA_REPORT.GUARDRAIL_COST');
  expect(wrapper.text()).toContain('USD 0');
  expect(wrapper.text()).toContain('OCA_REPORT.MAINTAINED_PRICES');
});

it.each([undefined, 'long_term_metering'])(
  'uses the actual retention and cost scope for storage %s, preserving unknown costs',
  storage => {
    const wrapper = shallowMount(OcaCostEstimate, {
      props: {
        usage: {
          storage,
          total: {
            estimatedCostUsd: null,
            estimatedCombinedCostUsd: null,
            unpricedCalls: 1,
          },
        },
      },
      global: { mocks: { $t: key => key } },
    });
    const text = wrapper.text();
    expect(text).toContain(
      storage ? 'OCA_REPORT.LONG_TERM_COST_NOTE' : 'OCA_REPORT.COST_NOTE'
    );
    expect(text).not.toContain(
      storage ? 'OCA_REPORT.COST_NOTE' : 'OCA_REPORT.LONG_TERM_COST_NOTE'
    );
    expect(text).toContain('OCA_REPORT.PARTIAL_COST');
    expect(text).not.toContain('USD 0');
    expect(text).toContain('—');
  }
);

it('exports usage CSV with the selected timezone and local date filename', async () => {
  ReportsAPI.getBotUsage.mockResolvedValue({
    data: {
      timezone: 'America/New_York',
      days: [{ group: '2026-03-08', calls: 1, inputTokens: 100 }],
      total: { calls: 1 },
    },
  });
  const wrapper = mount();
  await wrapper.setProps({
    filters: {
      from: Date.parse('2026-03-08T05:00Z') / 1000,
      to: Date.parse('2026-03-09T04:00Z') / 1000,
      timezone: 'America/New_York',
    },
  });
  await flushPromises();
  wrapper.vm.exportUsage();
  expect(downloadReport).toHaveBeenCalledWith(
    expect.stringContaining('2026-03-08,America/New_York,1,100'),
    'usage-report-2026-03-08.csv'
  );
  expect(ReportsAPI.getBotUsage).toHaveBeenLastCalledWith(
    expect.objectContaining({ timezone: 'America/New_York' })
  );
});

it('shows the smaller-range prompt when untracked history exceeds the metrics limit', async () => {
  ReportsAPI.getBotOutcomes.mockResolvedValue({ data });
  ReportsAPI.getBotUsage.mockResolvedValue({ data: { days: [], total: null } });
  ReportsAPI.getBotMetrics.mockReset();
  ReportsAPI.getBotMetrics.mockRejectedValueOnce({
    response: { data: { error: 'report_too_large' } },
  });
  const wrapper = mount();
  await flushPromises();
  expect(wrapper.text()).toContain('OCA_REPORT.TOO_LARGE');
  expect(wrapper.text()).not.toContain('OCA_REPORT.METRICS_ERROR');
});
