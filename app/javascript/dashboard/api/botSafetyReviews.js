/* global axios */
import ApiClient from './ApiClient';
class BotSafetyReviewsAPI extends ApiClient {
  constructor() {
    super('bot_safety_reviews', { accountScoped: true });
  }

  importResults(file) {
    const data = new FormData();
    data.append('file', file);
    return axios.post(`${this.url}/import_results`, data);
  }

  profiles() {
    return axios.get(`${this.url}/profiles`);
  }

  action(id, action, data = {}) {
    return axios.post(`${this.url}/${id}/${action}`, data);
  }

  download(id) {
    return axios.get(`${this.url}/${id}/download`, { responseType: 'blob' });
  }

  items(id, after = 0, findings = false) {
    return axios.get(`${this.url}/${id}`, { params: { after, findings } });
  }
}
export default new BotSafetyReviewsAPI();
