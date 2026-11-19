import { mount } from '@vue/test-utils';
import OcaCategoryBreakdown from '../OcaCategoryBreakdown.vue';
import OcaEscalationDetails from '../OcaEscalationDetails.vue';
const global = {
  stubs: {
    'router-link': true,
    'fluent-icon': true,
    Button: {
      props: ['label', 'disabled'],
      template: '<button :disabled="disabled">{{ label }}</button>',
    },
  },
  mocks: { $t: key => key },
};
describe('OCA report sections', () => {
  it('ranks categories, keeps names readable, and progressively reveals all 20', async () => {
    const categories = Object.fromEntries(
      Array.from({ length: 20 }, (_, i) => [
        `Long enquiry category ${i}`,
        i + 1,
      ])
    );
    const wrapper = mount(OcaCategoryBreakdown, {
      props: { categories, accountId: '1' },
      global,
    });
    expect(wrapper.findAll('li')).toHaveLength(8);
    expect(wrapper.find('li').text()).toContain('Long enquiry category 19');
    expect(wrapper.find('button[aria-label]').attributes('aria-label')).toBe(
      'OCA_REPORT.CATEGORIES_HELP'
    );
    expect(wrapper.find('p').exists()).toBe(false);
    await wrapper.find('button[aria-expanded]').trigger('click');
    expect(wrapper.findAll('li')).toHaveLength(20);
    expect(
      wrapper.find('button[aria-expanded]').attributes('aria-expanded')
    ).toBe('true');
  });
  it('offers a clear filter action rather than an empty table or invalid pagination', async () => {
    const wrapper = mount(OcaEscalationDetails, {
      props: {
        report: { details: [], detail_total: 0 },
        accountId: 1,
        reason: 'no_answer_found',
      },
      global,
    });
    expect(wrapper.text()).toContain('OCA_REPORT.NO_MATCHES');
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.find('footer').exists()).toBe(false);
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('filter')[0]).toEqual(['']);
  });
  it('exposes loading instead of stale detail rows and emits selected filters', async () => {
    const wrapper = mount(OcaEscalationDetails, {
      props: {
        report: { details: [], detail_total: 0 },
        accountId: 1,
        loading: true,
      },
      global,
    });
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
    await wrapper.find('select').setValue('requires_other_person');
    expect(wrapper.emitted('filter')[0]).toEqual(['requires_other_person']);
  });
});
