import { shallowMount, flushPromises } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
import OcaReportDownload from '../OcaReportDownload.vue';
import { downloadReport, reportFilename } from '../reportDownload';
vi.mock('dashboard/api/reports', () => ({
  default: { getBotWorkbook: vi.fn() },
}));
vi.mock('../reportDownload', async original => ({
  ...(await original()),
  downloadReport: vi.fn(),
}));
const filters = {
  timezone: 'Asia/Singapore',
  from: Date.parse('2026-11-01T16:00:00Z') / 1000,
  to: Date.parse('2026-11-02T16:00:00Z') / 1000,
};
const mount = () =>
  shallowMount(OcaReportDownload, {
    props: { filters },
    global: { mocks: { $t: key => key } },
  });
beforeEach(() => vi.clearAllMocks());
it('downloads a dated Excel file and prevents concurrent clicks', async () => {
  let finish;
  ReportsAPI.getBotWorkbook.mockImplementation(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = mount();
  const button = wrapper.findComponent({ name: 'Button' });
  button.vm.$emit('click');
  button.vm.$emit('click');
  await flushPromises();
  expect(ReportsAPI.getBotWorkbook).toHaveBeenCalledTimes(1);
  expect(ReportsAPI.getBotWorkbook).toHaveBeenCalledWith(filters);
  finish({ data: 'xlsx' });
  await flushPromises();
  expect(downloadReport).toHaveBeenCalledWith(
    'xlsx',
    'bot-report-2026-11-02.xlsx',
    expect.stringContaining('spreadsheetml')
  );
  expect(button.props('isLoading')).toBe(false);
});
it('shows a failure, permits retry, and discards downloads after changing dates', async () => {
  ReportsAPI.getBotWorkbook.mockRejectedValueOnce(new Error('offline'));
  const wrapper = mount();
  const button = wrapper.findComponent({ name: 'Button' });
  button.vm.$emit('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').text()).toBe('OCA_REPORT.EXPORT_ERROR');
  let finish;
  ReportsAPI.getBotWorkbook.mockImplementation(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  button.vm.$emit('click');
  await wrapper.setProps({ filters: { ...filters, to: filters.to + 86400 } });
  finish({ data: 'old' });
  await flushPromises();
  expect(downloadReport).not.toHaveBeenCalled();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
});
it('names usage exports using Singapore dates, including both selected dates', () => {
  expect(reportFilename('usage', filters, 'csv')).toBe(
    'usage-report-2026-11-02.csv'
  );
  expect(
    reportFilename('usage', { ...filters, to: filters.to + 86400 }, 'csv')
  ).toBe('usage-report-2026-11-02-to-2026-11-03.csv');
});
it('shows an actionable size error from a binary download response without saving a partial file', async () => {
  const body = new Blob();
  body.text = async () => JSON.stringify({ error: 'report_too_large' });
  ReportsAPI.getBotWorkbook.mockRejectedValueOnce({ response: { data: body } });
  const wrapper = mount();
  wrapper.findComponent({ name: 'Button' }).vm.$emit('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').text()).toBe('OCA_REPORT.TOO_LARGE');
  expect(downloadReport).not.toHaveBeenCalled();
});

it('names exports in the requested timezone across a DST day', () => {
  const range = {
    from: Date.parse('2026-03-08T05:00:00Z') / 1000,
    to: Date.parse('2026-03-09T04:00:00Z') / 1000,
    timezone: 'America/New_York',
  };
  expect(reportFilename('bot', range, 'xlsx')).toBe(
    'bot-report-2026-03-08.xlsx'
  );
  expect(
    reportFilename('bot', { ...range, timezone: 'Asia/Singapore' }, 'xlsx')
  ).toBe('bot-report-2026-03-08-to-2026-03-09.xlsx');
});
