import labels from '../labels';
import ApiClient from '../ApiClient';
import CacheEnabledApiClient from '../CacheEnabledApiClient';

describe('#LabelsAPI', () => {
  it('creates correct instance', () => {
    expect(labels).toBeInstanceOf(ApiClient);
    expect(labels).toHaveProperty('get');
    expect(labels).toHaveProperty('show');
    expect(labels).toHaveProperty('create');
    expect(labels).toHaveProperty('update');
    expect(labels).toHaveProperty('delete');
    expect(labels.url).toBe('/api/v1/labels');
  });
});

describe('AI label cache upgrade', () => {
  afterEach(() => vi.restoreAllMocks());

  it('refetches legacy records instead of presenting an enabled AI category as disabled', async () => {
    vi.spyOn(CacheEnabledApiClient.prototype, 'getFromCache').mockResolvedValue(
      { data: { payload: [{ id: 1, title: 'others' }] } }
    );
    const fresh = {
      data: {
        payload: [
          {
            id: 1,
            title: 'others',
            ai_category: true,
            ai_category_name: 'Others',
          },
        ],
      },
    };
    const refresh = vi
      .spyOn(labels, 'refetchAndCommit')
      .mockResolvedValue(fresh);
    expect(await labels.get(true)).toEqual(fresh);
    expect(refresh).toHaveBeenCalledOnce();
  });

  it('preserves valid disabled categories and ordinary labels in the cache', async () => {
    const cached = {
      data: {
        payload: [
          { id: 1, ai_category: false, ai_category_name: 'Retired' },
          { id: 2, ai_category: false, ai_category_name: null },
        ],
      },
    };
    vi.spyOn(CacheEnabledApiClient.prototype, 'getFromCache').mockResolvedValue(
      cached
    );
    const refresh = vi.spyOn(labels, 'refetchAndCommit');
    expect(await labels.get(true)).toEqual(cached);
    expect(refresh).not.toHaveBeenCalled();
  });
});
