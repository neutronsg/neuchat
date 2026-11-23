import { shallowMount } from '@vue/test-utils';
import OcaEscalationDetails from '../OcaEscalationDetails.vue';
const mount = (timezone, at) =>
  shallowMount(OcaEscalationDetails, {
    props: {
      accountId: 1,
      report: {
        timezone,
        detail_total: 1,
        details: [
          {
            conversation_id: 1,
            escalated_at: at,
            reasons: [],
            categories: [],
            destination: 'oca_support',
            all_solved: false,
          },
        ],
      },
    },
    global: { stubs: { 'router-link': true }, mocks: { $t: key => key } },
  });
it.each([
  ['America/New_York', '2026-03-08T04:30:00Z', '07 Mar 2026, 11:30 pm'],
  ['Asia/Singapore', '2026-03-08T04:30:00Z', '08 Mar 2026, 12:30 pm'],
  ['America/New_York', '2026-03-08T06:30:00Z', '08 Mar 2026, 01:30 am'],
  ['America/New_York', '2026-03-08T07:30:00Z', '08 Mar 2026, 03:30 am'],
  ['America/New_York', '2026-11-01T05:30:00Z', '01 Nov 2026, 01:30 am'],
  ['America/New_York', '2026-11-01T06:30:00Z', '01 Nov 2026, 01:30 am'],
])('renders %s event %s in the report timezone', (zone, at, expected) => {
  const time = mount(zone, at).find('time');
  expect(time.text()).toBe(expected);
  expect(time.attributes('datetime')).toBe(at);
});
it('updates the displayed date when the report timezone changes', async () => {
  const wrapper = mount('America/New_York', '2026-03-08T04:30:00Z');
  await wrapper.setProps({
    report: { ...wrapper.props('report'), timezone: 'Asia/Singapore' },
  });
  expect(wrapper.find('time').text()).toBe('08 Mar 2026, 12:30 pm');
});
