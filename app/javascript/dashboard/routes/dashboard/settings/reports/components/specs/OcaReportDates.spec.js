import { mount } from '@vue/test-utils';
import { singaporeRange, singaporeToday } from '../ocaReportDates';
import OcaReportDateFilter from '../OcaReportDateFilter.vue';
import DateRange from '../Filters/DateRange.vue';

describe('Singapore calendar report dates', () => {
  it('uses midnight in Singapore and the next exclusive midnight, including fractional seconds', () => {
    const result = singaporeRange([
      new Date(2026, 10, 19),
      new Date(2026, 10, 19),
    ]);
    expect(new Date(result.from * 1000).toISOString()).toBe(
      '2026-11-18T16:00:00.000Z'
    );
    expect(new Date(result.to * 1000).toISOString()).toBe(
      '2026-11-19T16:00:00.000Z'
    );
    expect(Date.parse('2026-11-19T15:59:59.999Z') / 1000).toBeLessThan(
      result.to
    );
    const today = singaporeToday(new Date('2026-11-18T17:00:00Z'));
    expect([today.getFullYear(), today.getMonth(), today.getDate()]).toEqual([
      2026, 10, 19,
    ]);
  });
  it('accepts exactly 93 days across the year boundary; rejects 94, reversed and invalid dates', () => {
    expect(
      singaporeRange([new Date(2025, 11, 1), new Date(2026, 2, 3)]).to
    ).toBe(Date.parse('2026-03-03T16:00Z') / 1000);
    [
      [new Date(2025, 11, 1), new Date(2026, 2, 4)],
      [new Date(2026, 1, 2), new Date(2026, 1, 1)],
      [new Date('bad'), new Date()],
    ].forEach(dates => {
      expect(() => singaporeRange(dates)).toThrow(RangeError);
    });
  });
  it('does not request an oversized custom range, shows an error, and recovers on valid input', async () => {
    const wrapper = mount(OcaReportDateFilter, {
      global: {
        stubs: { ReportsFiltersDateRange: true, WootDateRangePicker: true },
        mocks: { $t: key => key },
      },
    });
    wrapper
      .findComponent({ name: 'ReportsFiltersDateRange' })
      .vm.$emit('onRangeChange', { offset: null });
    await wrapper.vm.$nextTick();
    const picker = wrapper.findComponent({ name: 'WootDateRangePicker' });
    const before = wrapper.emitted('filterChange').length;
    picker.vm.$emit('change', [new Date(2026, 0, 1), new Date(2026, 5, 1)]);
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('filterChange')).toHaveLength(before);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    picker.vm.$emit('change', [new Date(2026, 0, 1), new Date(2026, 0, 1)]);
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.emitted('filterChange')).toHaveLength(before + 1);
  });
  it('hides six-month and annual presets only for constrained reports', () => {
    const global = {
      stubs: {
        multiselect: {
          name: 'multiselect',
          props: ['options'],
          template: '<div />',
        },
      },
    };
    const limited = mount(DateRange, { props: { maxDays: 93 }, global });
    expect(
      limited
        .findComponent({ name: 'multiselect' })
        .props('options')
        .map(o => o.id)
    ).toEqual([
      'LAST_7_DAYS',
      'LAST_30_DAYS',
      'LAST_3_MONTHS',
      'CUSTOM_DATE_RANGE',
    ]);
    const legacy = mount(DateRange, { global });
    expect(
      legacy.findComponent({ name: 'multiselect' }).props('options')
    ).toHaveLength(6);
  });
});
