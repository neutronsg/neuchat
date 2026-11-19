import { shallowMount, flushPromises } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
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
        },
      },
    });
    const wrapper = mount();
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.GUARDRAIL_COST');
    expect(wrapper.text()).toContain('OCA_REPORT.COMBINED_COST');
    expect(wrapper.text()).toContain('OCA_REPORT.PARTIAL_COST');
    expect(wrapper.text()).toContain('OCA_REPORT.PRICE_STALE');
    expect(wrapper.text()).toContain('OCA_REPORT.LONG_TERM_COST_NOTE');
    expect(wrapper.text()).toContain('USD —');
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
  it('retains visible report data after an export failure and permits a retry', async () => {
    ReportsAPI.getBotOutcomesCSV.mockRejectedValue(new Error('network'));
    const wrapper = mount();
    await flushPromises();
    const button = wrapper
      .findAllComponents({ name: 'Button' })
      .find(b => b.props('label') === 'OCA_REPORT.DOWNLOAD');
    button.vm.$emit('click');
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.EXPORT_ERROR');
    expect(
      wrapper.findComponent({ name: 'OcaEscalationDetails' }).exists()
    ).toBe(true);
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
