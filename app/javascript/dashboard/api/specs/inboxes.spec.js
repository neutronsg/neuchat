import inboxesAPI from '../inboxes';
import ApiClient from '../ApiClient';

describe('#InboxesAPI', () => {
  it('creates correct instance', () => {
    expect(inboxesAPI).toBeInstanceOf(ApiClient);
    expect(inboxesAPI).toHaveProperty('get');
    expect(inboxesAPI).toHaveProperty('show');
    expect(inboxesAPI).toHaveProperty('create');
    expect(inboxesAPI).toHaveProperty('update');
    expect(inboxesAPI).toHaveProperty('delete');
    expect(inboxesAPI).toHaveProperty('getCampaigns');
    expect(inboxesAPI).toHaveProperty('getAgentBot');
    expect(inboxesAPI).toHaveProperty('setAgentBot');
  });

  describe('image settings cache compatibility', () => {
    beforeEach(() => {
      vi.spyOn(inboxesAPI.dataManager, 'initDb').mockResolvedValue();
      vi.spyOn(inboxesAPI.dataManager, 'getCacheKey').mockResolvedValue(
        'same-key'
      );
    });

    afterEach(() => vi.restoreAllMocks());

    it('invalidates cached WhatsApp records without the new settings', async () => {
      vi.spyOn(inboxesAPI.dataManager, 'get').mockResolvedValue([
        { id: 2, channel_type: 'Channel::Whatsapp' },
      ]);
      expect(await inboxesAPI.validateCacheKey('same-key')).toBe(false);
    });

    it('accepts current image settings and other channel types', async () => {
      vi.spyOn(inboxesAPI.dataManager, 'get').mockResolvedValue([
        { id: 1, channel_type: 'Channel::WebWidget' },
        {
          id: 2,
          channel_type: 'Channel::Whatsapp',
          image_messages_enabled: false,
          image_unavailable_message: 'Please send text.',
          default_image_unavailable_message: 'Please send text.',
        },
      ]);
      expect(await inboxesAPI.validateCacheKey('same-key')).toBe(true);
      expect(await inboxesAPI.validateCacheKey('changed-key')).toBe(false);
    });
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getCampaigns', () => {
      inboxesAPI.getCampaigns(2);
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/inboxes/2/campaigns');
    });

    it('#deleteInboxAvatar', () => {
      inboxesAPI.deleteInboxAvatar(2);
      expect(axiosMock.delete).toHaveBeenCalledWith('/api/v1/inboxes/2/avatar');
    });
  });
});
