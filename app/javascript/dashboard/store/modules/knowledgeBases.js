import KnowledgeBasesAPI from '../../api/knowledgeBases';
import { sortByCreatedAtDesc } from '../../routes/dashboard/knowledgeBase/utils/editSession';

const state = {
  records: [],
  currentKB: null,
  documents: [],
  qaPairs: [],
  qaSyncRequired: false,
  qaDocumentId: null,
  qaDocumentStatus: null,
  uiFlags: {
    isFetching: false,
    isFetchingDocuments: false,
    isFetchingQaPairs: false,
    isCreating: false,
    isSyncing: false,
  },
};

const getters = {
  getKnowledgeBases: $state => $state.records,
  getCurrentKB: $state => $state.currentKB,
  getDocuments: $state => $state.documents,
  getQaPairs: $state => $state.qaPairs,
  getQaSyncRequired: $state => $state.qaSyncRequired,
  getQaDocumentStatus: $state => $state.qaDocumentStatus,
  getUIFlags: $state => $state.uiFlags,
  hasProcessingDocuments: $state =>
    $state.documents.some(d =>
      ['waiting', 'parsing', 'cleaning', 'splitting', 'indexing'].includes(
        d.indexing_status
      )
    ),
  isQaDocumentProcessing: $state => {
    const status = $state.qaDocumentStatus?.indexing_status;
    return ['waiting', 'parsing', 'cleaning', 'splitting', 'indexing'].includes(
      status
    );
  },
};

const actions = {
  async fetchKnowledgeBases({ commit }, { silent = false } = {}) {
    if (!silent) {
      commit('setUIFlag', { isFetching: true });
    }
    try {
      const response = await KnowledgeBasesAPI.get();
      commit('setRecords', response.data);
    } finally {
      if (!silent) {
        commit('setUIFlag', { isFetching: false });
      }
    }
  },

  async fetchKnowledgeBase({ commit }, { id, silent = false }) {
    if (!silent) {
      commit('setUIFlag', { isFetching: true });
    }
    try {
      const response = await KnowledgeBasesAPI.show(id);
      commit('setCurrentKB', response.data);
    } finally {
      if (!silent) {
        commit('setUIFlag', { isFetching: false });
      }
    }
  },

  async fetchDocuments({ commit }, { knowledgeBaseId, silent = false }) {
    if (!silent) {
      commit('setUIFlag', { isFetchingDocuments: true });
    }
    try {
      const response = await KnowledgeBasesAPI.getDocuments(knowledgeBaseId);
      commit('setDocuments', response.data.documents);
    } finally {
      if (!silent) {
        commit('setUIFlag', { isFetchingDocuments: false });
      }
    }
  },

  async createDocument({ commit, dispatch }, { knowledgeBaseId, file, name }) {
    commit('setUIFlag', { isCreating: true });
    try {
      await KnowledgeBasesAPI.createDocument(knowledgeBaseId, file, name);
      dispatch('fetchDocuments', { knowledgeBaseId });
    } finally {
      commit('setUIFlag', { isCreating: false });
    }
  },

  async toggleDocument(_, { knowledgeBaseId, documentId, enabled }) {
    await KnowledgeBasesAPI.updateDocument(knowledgeBaseId, documentId, {
      enabled,
    });
    // No need to refetch - UI uses optimistic update via updateDocumentEnabled mutation
  },

  async deleteDocument({ dispatch }, { knowledgeBaseId, documentId }) {
    await KnowledgeBasesAPI.deleteDocument(knowledgeBaseId, documentId);
    dispatch('fetchDocuments', { knowledgeBaseId });
  },

  async fetchQaPairs({ commit }, { knowledgeBaseId, silent = false }) {
    if (!silent) {
      commit('setUIFlag', { isFetchingQaPairs: true });
    }
    try {
      const response = await KnowledgeBasesAPI.getQaPairs(knowledgeBaseId);
      commit('setQaPairs', response.data.qa_pairs);
      commit('setQaSyncRequired', response.data.sync_required);
      commit('setQaDocumentId', response.data.qa_document_id);
      commit('setQaDocumentStatus', response.data.qa_document_status);
    } finally {
      if (!silent) {
        commit('setUIFlag', { isFetchingQaPairs: false });
      }
    }
  },

  async createQaPair({ commit }, { knowledgeBaseId, data }) {
    const response = await KnowledgeBasesAPI.createQaPair(
      knowledgeBaseId,
      data
    );
    commit('addQaPair', response.data);
    commit('setQaSyncRequired', true);
  },

  async updateQaPair({ commit }, { knowledgeBaseId, qaPairId, data }) {
    const response = await KnowledgeBasesAPI.updateQaPair(
      knowledgeBaseId,
      qaPairId,
      data
    );
    commit('updateQaPair', response.data);
    commit('setQaSyncRequired', true);
  },

  async deleteQaPair({ commit }, { knowledgeBaseId, qaPairId }) {
    await KnowledgeBasesAPI.deleteQaPair(knowledgeBaseId, qaPairId);
    commit('removeQaPair', qaPairId);
    commit('setQaSyncRequired', true);
  },

  async syncQaPairs({ commit, dispatch }, knowledgeBaseId) {
    commit('setUIFlag', { isSyncing: true });
    try {
      const response = await KnowledgeBasesAPI.syncQaPairs(knowledgeBaseId);
      commit('setQaSyncRequired', false);
      commit('setQaDocumentId', response.data.qa_document_id);
      // Refresh status after sync starts
      await dispatch('fetchQaPairs', { knowledgeBaseId });
    } finally {
      commit('setUIFlag', { isSyncing: false });
    }
  },
};

const mutations = {
  setRecords($state, records) {
    $state.records = records;
  },
  setCurrentKB($state, kb) {
    $state.currentKB = kb;
  },
  setDocuments($state, documents) {
    $state.documents = sortByCreatedAtDesc(documents);
  },
  updateDocumentEnabled($state, { documentId, enabled }) {
    const doc = $state.documents.find(d => d.id === documentId);
    if (doc) {
      doc.enabled = enabled;
    }
  },
  setQaPairs($state, qaPairs) {
    $state.qaPairs = sortByCreatedAtDesc(qaPairs);
  },
  addQaPair($state, qaPair) {
    $state.qaPairs = sortByCreatedAtDesc([qaPair, ...$state.qaPairs]);
  },
  updateQaPair($state, qaPair) {
    const index = $state.qaPairs.findIndex(q => q.id === qaPair.id);
    if (index !== -1) {
      $state.qaPairs.splice(index, 1, qaPair);
      $state.qaPairs = sortByCreatedAtDesc($state.qaPairs);
    }
  },
  removeQaPair($state, qaPairId) {
    $state.qaPairs = $state.qaPairs.filter(q => q.id !== qaPairId);
  },
  setQaSyncRequired($state, value) {
    $state.qaSyncRequired = value;
  },
  setQaDocumentId($state, value) {
    $state.qaDocumentId = value;
  },
  setQaDocumentStatus($state, value) {
    $state.qaDocumentStatus = value;
  },
  resetState($state) {
    $state.documents = [];
    $state.qaPairs = [];
    $state.currentKB = null;
    $state.qaSyncRequired = false;
    $state.qaDocumentId = null;
    $state.qaDocumentStatus = null;
    $state.uiFlags = {
      isFetching: false,
      isFetchingDocuments: false,
      isFetchingQaPairs: false,
      isCreating: false,
      isSyncing: false,
    };
  },
  setUIFlag($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
