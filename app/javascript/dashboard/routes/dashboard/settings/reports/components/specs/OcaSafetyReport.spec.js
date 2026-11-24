import { mount, flushPromises } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
import OcaSafetyReport from '../OcaSafetyReport.vue';
vi.mock('dashboard/api/reports', () => ({
  default: { getBotSafety: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));
const filters = { from: 1000, to: 2000, timezone: 'America/New_York' };
const report = {
  groups: [{ day: '2026-11-01', enforced: true, status: 'block', count: 2 }],
  comparison: { comparable: 1, disagree: 1, agree: 0, unavailable: 0 },
  current_modes: [{ name: 'Bot', mode: 'custom' }],
  events: [
    {
      attempt_id: 'test',
      created_at: '2026-11-01T06:30:00Z',
      conversation_id: 1,
      provider: 'custom',
      mode: 'aws_shadow',
      stage: 'input',
      status: 'block',
      reason: 'prompt_attack',
      enforced: false,
    },
  ],
};
const mountReport = () =>
  mount(OcaSafetyReport, {
    props: { filters },
    global: {
      directives: { 'on-clickaway': {} },
      mocks: {
        $t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
      },
      stubs: {
        BarChart: true,
        SafetyReviewRuns: true,
        RouterLink: { template: '<a><slot /></a>' },
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
describe('Safety reports', () => {
  beforeEach(() => vi.clearAllMocks());
  it('keeps historical shadow comparison visible after switching to custom mode', async () => {
    ReportsAPI.getBotSafety.mockResolvedValue({ data: report });
    const wrapper = mountReport();
    await flushPromises();
    expect(ReportsAPI.getBotSafety).toHaveBeenCalledWith(filters);
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.SHADOW');
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.MODES.custom');
    expect(wrapper.text()).toContain('1:30');
  });
  it('shows errors instead of a fabricated zero and omits empty tables and pagination', async () => {
    ReportsAPI.getBotSafety.mockRejectedValue(new Error('offline'));
    const wrapper = mountReport();
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.ERROR');
    expect(wrapper.find('dl').exists()).toBe(false);
    ReportsAPI.getBotSafety.mockResolvedValue({
      data: { groups: [], events: [], comparison: {} },
    });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.EMPTY');
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });
  it('does not let a late response overwrite the selected date range', async () => {
    let finish;
    ReportsAPI.getBotSafety.mockReturnValueOnce(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = mountReport();
    ReportsAPI.getBotSafety.mockResolvedValue({
      data: { groups: [], events: [], comparison: {} },
    });
    await wrapper.setProps({ filters: { ...filters, from: 1100 } });
    await flushPromises();
    finish({ data: report });
    await flushPromises();
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.EMPTY');
    expect(wrapper.find('table').exists()).toBe(false);
  });
  it('groups checks into one request, expands evidence and filters shadow disagreements', async () => {
    ReportsAPI.getBotSafety.mockResolvedValue({
      data: {
        ...report,
        events: [
          { ...report.events[0], message_id: 10, day: '2026-11-01' },
          {
            ...report.events[0],
            message_id: 10,
            day: '2026-11-01',
            provider: 'aws',
            enforced: true,
            status: 'allow',
          },
        ],
      },
    });
    const wrapper = mountReport();
    await flushPromises();
    expect(wrapper.vm.requests).toHaveLength(1);
    expect(wrapper.vm.blockedRequests).toBe(0);
    expect(wrapper.vm.trend.datasets.map(d => d.data)).toEqual([[1], [0]]);
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    wrapper.vm.toggleRequest(wrapper.vm.requests[0].key);
    await wrapper.vm.$nextTick();
    expect(wrapper.findAll('tbody tr')).toHaveLength(2);
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.EVIDENCE_NOTE');
    wrapper.vm.showStatusMenu = true;
    await wrapper.vm.$nextTick();
    wrapper
      .findComponent({ name: 'DropdownMenu' })
      .vm.$emit('action', { value: 'aws_only' });
    await wrapper.vm.$nextTick();
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.vm.showStatusMenu).toBe(false);
    wrapper.vm.status = 'custom_only';
    await wrapper.vm.$nextTick();
    expect(wrapper.find('table').exists()).toBe(true);
  });
  it('counts required skipped shadow checks, filters them, and explains expected omissions', async () => {
    const base = {
      ...report.events[0],
      provider: 'aws',
      enforced: true,
      status: 'allow',
      message_id: 10,
    };
    ReportsAPI.getBotSafety.mockResolvedValue({
      data: {
        ...report,
        events: [
          base,
          { ...base, provider: 'custom', enforced: false, status: 'skipped' },
          { ...base, message_id: 11, attempt_id: 'blocked', status: 'block' },
          {
            ...base,
            message_id: 11,
            attempt_id: 'blocked',
            stage: 'output',
            status: 'unavailable',
          },
        ],
      },
    });
    const wrapper = mountReport();
    await flushPromises();
    expect(wrapper.vm.issueRequests).toBe(1);
    expect(wrapper.vm.blockedRequests).toBe(1);
    wrapper.vm.status = 'unavailable';
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.rows.map(r => r.messageId)).toEqual([10]);
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.SHADOW_MISSING');
    wrapper.vm.status = 'block';
    await wrapper.vm.$nextTick();
    wrapper.vm.toggleRequest(wrapper.vm.rows[0].key);
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('OCA_REPORT.SAFETY.STATUS.not_required');
  });
});
