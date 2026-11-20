/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  async validateCacheKey(newKey) {
    if (!(await super.validateCacheKey(newKey))) return false;

    // Existing sessions can retain pre-release inbox records under the same server key.
    const records = await this.dataManager.get({
      modelName: this.cacheModelName,
    });
    return records.every(
      inbox =>
        inbox.channel_type !== 'Channel::Whatsapp' ||
        (typeof inbox.image_messages_enabled === 'boolean' &&
          typeof inbox.image_unavailable_message === 'string' &&
          typeof inbox.default_image_unavailable_message === 'string')
    );
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }
}

export default new Inboxes();
