import { mount, flushPromises } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
import OcaSafetyReport from '../OcaSafetyReport.vue';
vi.mock('dashboard/api/reports', () => ({
  default: { getBotSafety: vi.fn() },
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
      mocks: {
        $t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
      },
      stubs: {
        BarChart: true,
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
});
