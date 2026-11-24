import { mount, flushPromises } from '@vue/test-utils';
import API from 'dashboard/api/botSafetyReviews';
import SafetyReviewRuns from '../SafetyReviewRuns.vue';
vi.mock('dashboard/api/botSafetyReviews', () => ({
  default: {
    get: vi.fn(),
    profiles: vi.fn(),
    create: vi.fn(),
    items: vi.fn(),
    action: vi.fn(),
  },
}));
const render = () =>
  mount(SafetyReviewRuns, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
describe('Safety review batches', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    API.get.mockResolvedValue({ data: [] });
    API.profiles.mockResolvedValue({ data: { profiles: [] } });
  });
  it('defaults to zero model calls and reuses the batch key after an uncertain create response', async () => {
    const wrapper = render();
    await flushPromises();
    API.create.mockRejectedValue(new Error('lost response'));
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    const first = API.create.mock.calls[0][0];
    expect(first.max_calls).toBe(0);
    expect(first.dry_run).toBe(true);
    expect(first.timezone).toBeTruthy();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    API.create.mockResolvedValue({ data: { id: 1 } });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(API.create.mock.calls[1][0].idempotency_key).toBe(
      first.idempotency_key
    );
  });
  it('keeps failures visible rather than showing an empty completed batch', async () => {
    API.get.mockRejectedValue(new Error('no access'));
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(API.profiles).not.toHaveBeenCalled();
  });
});
