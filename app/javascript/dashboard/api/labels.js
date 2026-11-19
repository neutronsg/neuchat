import CacheEnabledApiClient from './CacheEnabledApiClient';

class LabelsAPI extends CacheEnabledApiClient {
  constructor() {
    super('labels', { accountScoped: true });
  }

  async getFromCache() {
    const response = await super.getFromCache();
    const legacy = response.data.payload.some(
      label =>
        typeof label.ai_category !== 'boolean' ||
        !Object.hasOwn(label, 'ai_category_name')
    );
    // Pre-upgrade IndexedDB records have the same server cache key, but lack AI fields.
    return legacy ? this.refetchAndCommit() : response;
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'label';
  }
}

export default new LabelsAPI();
