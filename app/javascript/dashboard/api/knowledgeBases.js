/* global axios */
import ApiClient from './ApiClient';

class KnowledgeBasesAPI extends ApiClient {
  constructor() {
    super('knowledge_bases', { accountScoped: true });
  }

  // Documents
  getDocuments(knowledgeBaseId) {
    return axios.get(`${this.url}/${knowledgeBaseId}/documents`);
  }

  createDocument(knowledgeBaseId, file, name, chunkSettings) {
    const formData = new FormData();
    formData.append('file', file);
    if (name) formData.append('name', name);
    if (chunkSettings) {
      formData.append('chunk_settings', JSON.stringify(chunkSettings));
    }

    return axios.post(`${this.url}/${knowledgeBaseId}/documents`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  updateDocument(knowledgeBaseId, documentId, data) {
    return axios.patch(
      `${this.url}/${knowledgeBaseId}/documents/${documentId}`,
      data
    );
  }

  deleteDocument(knowledgeBaseId, documentId) {
    return axios.delete(
      `${this.url}/${knowledgeBaseId}/documents/${documentId}`
    );
  }

  getDocumentChunkSettings(knowledgeBaseId, documentId) {
    return axios.get(
      `${this.url}/${knowledgeBaseId}/documents/${documentId}/chunk_settings`
    );
  }

  updateDocumentChunkSettings(knowledgeBaseId, documentId, chunkSettings) {
    return axios.patch(
      `${this.url}/${knowledgeBaseId}/documents/${documentId}/chunk_settings`,
      {
        chunk_settings: chunkSettings,
      }
    );
  }

  // Q&A Pairs
  getQaPairs(knowledgeBaseId) {
    return axios.get(`${this.url}/${knowledgeBaseId}/qa_pairs`);
  }

  createQaPair(knowledgeBaseId, data) {
    return axios.post(`${this.url}/${knowledgeBaseId}/qa_pairs`, {
      qa_pair: data,
    });
  }

  updateQaPair(knowledgeBaseId, qaPairId, data) {
    return axios.patch(`${this.url}/${knowledgeBaseId}/qa_pairs/${qaPairId}`, {
      qa_pair: data,
    });
  }

  deleteQaPair(knowledgeBaseId, qaPairId) {
    return axios.delete(`${this.url}/${knowledgeBaseId}/qa_pairs/${qaPairId}`);
  }

  syncQaPairs(knowledgeBaseId) {
    return axios.post(`${this.url}/${knowledgeBaseId}/qa_pairs/sync`);
  }

  importQaPairsFromDocx(knowledgeBaseId, file) {
    const formData = new FormData();
    formData.append('file', file);

    return axios.post(
      `${this.url}/${knowledgeBaseId}/qa_pairs/import_docx`,
      formData,
      {
        headers: { 'Content-Type': 'multipart/form-data' },
      }
    );
  }
}

export default new KnowledgeBasesAPI();
