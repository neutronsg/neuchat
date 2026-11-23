import { mount } from '@vue/test-utils';
import {
  browserRange,
  browserPreset,
  browserTimezone,
} from '../ocaReportDates';
import OcaReportDateFilter from '../OcaReportDateFilter.vue';

describe('Browser calendar report dates', () => {
  it('uses browser midnight and next calendar midnight, with a named timezone', () => {
    const result = browserRange([
      new Date(2026, 10, 19),
      new Date(2026, 10, 19),
    ]);
    expect(result).toEqual({
      from: new Date(2026, 10, 19).getTime() / 1000,
      to: new Date(2026, 10, 20).getTime() / 1000,
      timezone: browserTimezone(),
    });
    expect(browserPreset(6).timezone).toBe(browserTimezone());
  });
  it('covers complete spring/fall transition days, rather than adding 86400 seconds', () => {
    const spring = browserRange([new Date(2026, 2, 8), new Date(2026, 2, 8)]);
    const fall = browserRange([new Date(2026, 10, 1), new Date(2026, 10, 1)]);
    expect(spring.to).toBe(new Date(2026, 2, 9).getTime() / 1000);
    expect(fall.to).toBe(new Date(2026, 10, 2).getTime() / 1000);
    if (browserTimezone() === 'America/New_York') {
      expect(spring.to - spring.from).toBe(23 * 3600);
      expect(fall.to - fall.from).toBe(25 * 3600);
    }
  });
  it('accepts annual ranges and rejects reversed or invalid dates', () => {
    expect(
      browserRange([new Date(2026, 0, 1), new Date(2026, 11, 31)]).to
    ).toBe(new Date(2027, 0, 1).getTime() / 1000);
    [
      [new Date(2026, 1, 2), new Date(2026, 1, 1)],
      [new Date('bad'), new Date()],
      [],
      null,
    ].forEach(dates => expect(() => browserRange(dates)).toThrow(RangeError));
  });
  it('uses the SLA picker and forwards timezone with dates', async () => {
    const wrapper = mount(OcaReportDateFilter, {
      global: { stubs: { DatePicker: true }, mocks: { $t: key => key } },
    });
    const picker = wrapper.findComponent({ name: 'DatePicker' });
    picker.vm.$emit('dateRangeChanged', [
      new Date(2026, 0, 1),
      new Date(2026, 11, 31),
    ]);
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('filterChange').at(-1)[0].timezone).toBe(
      browserTimezone()
    );
    picker.vm.$emit('dateRangeChanged', []);
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });
});
