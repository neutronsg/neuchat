import ApiClient from './ApiClient';

class ContactNotes extends ApiClient {
  constructor() {
    super('notes', { accountScoped: true });
    this.contactId = null;
  }

  get url() {
    return `${this.baseUrl()}/contacts/${this.contactId}/notes`;
  }

  get(contactId) {
    this.contactId = contactId;
    return super.get();
  }

  create(contactId, content, noteType = 'agent') {
    this.contactId = contactId;
    return super.create({ content, note_type: noteType });
  }

  delete(contactId, id) {
    this.contactId = contactId;
    return super.delete(id);
  }
}

export default new ContactNotes();
