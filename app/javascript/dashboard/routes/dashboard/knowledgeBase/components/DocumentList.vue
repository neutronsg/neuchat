<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import KBSectionCard from 'dashboard/components-next/KnowledgeBase/KBSectionCard.vue';
import KBStatusPill from 'dashboard/components-next/KnowledgeBase/KBStatusPill.vue';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const fileInput = ref(null);
const isUploading = ref(false);

const documents = computed(() => store.getters['knowledgeBases/getDocuments']);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

const normalizeStatus = status =>
  status === 'completed' ? 'available' : status;
const getStatusLabel = status => {
  const normalized = normalizeStatus(status);
  if (normalized === 'available') {
    return t('KNOWLEDGE_BASE.STATUS_AVAILABLE');
  }
  return normalized || 'unknown';
};

const formatDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

const triggerUpload = () => {
  fileInput.value?.click();
};

const handleFileSelect = async event => {
  const file = event.target.files[0];
  if (!file) return;

  isUploading.value = true;
  try {
    await store.dispatch('knowledgeBases/createDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      file,
      name: file.name,
    });
    showAlert(t('KNOWLEDGE_BASE.DOCUMENT_UPLOADED'));
  } catch (error) {
    showAlert(error.message || t('KNOWLEDGE_BASE.UPLOAD_FAILED'));
  } finally {
    isUploading.value = false;
    event.target.value = '';
  }
};

const toggleDocument = async doc => {
  // Optimistic update - toggle immediately in UI
  const originalEnabled = doc.enabled;
  store.commit('knowledgeBases/updateDocumentEnabled', {
    documentId: doc.id,
    enabled: !originalEnabled,
  });

  try {
    await store.dispatch('knowledgeBases/toggleDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      documentId: doc.id,
      enabled: !originalEnabled,
    });
  } catch (error) {
    // Rollback on error
    store.commit('knowledgeBases/updateDocumentEnabled', {
      documentId: doc.id,
      enabled: originalEnabled,
    });
    showAlert(error.message);
  }
};

const deleteDocument = async doc => {
  if (!window.confirm(t('KNOWLEDGE_BASE.CONFIRM_DELETE_DOCUMENT'))) return;

  try {
    await store.dispatch('knowledgeBases/deleteDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      documentId: doc.id,
    });
    showAlert(t('KNOWLEDGE_BASE.DOCUMENT_DELETED'));
  } catch (error) {
    showAlert(error.message);
  }
};
</script>

<template>
  <KBSectionCard :title="t('KNOWLEDGE_BASE.DOCUMENTS_TITLE')">
    <template #actions>
      <Button
        :label="
          isUploading
            ? t('KNOWLEDGE_BASE.UPLOADING')
            : t('KNOWLEDGE_BASE.UPLOAD_DOCUMENT')
        "
        :is-loading="isUploading"
        @click="triggerUpload"
      />
      <input
        ref="fileInput"
        type="file"
        class="hidden"
        accept=".txt,.pdf,.docx,.md,.html,.csv,.xlsx"
        @change="handleFileSelect"
      />
    </template>

    <div v-if="uiFlags.isFetchingDocuments" class="py-6 text-center">
      <span class="text-sm text-n-slate-11">{{
        t('KNOWLEDGE_BASE.LOADING')
      }}</span>
    </div>

    <div v-else-if="documents.length === 0" class="py-6 text-center">
      <p class="text-sm text-n-slate-11">
        {{ t('KNOWLEDGE_BASE.NO_DOCUMENTS') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-3">
      <div
        v-for="doc in documents"
        :key="doc.id"
        class="rounded-xl border border-n-weak bg-n-background px-4 py-4"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="text-sm font-semibold text-n-slate-12 truncate">
              {{ doc.name }}
            </p>
            <div
              class="mt-2 flex flex-wrap items-center gap-3 text-xs text-n-slate-11"
            >
              <span>{{ doc.word_count }} {{ t('KNOWLEDGE_BASE.WORDS') }}</span>
              <KBStatusPill
                :status="normalizeStatus(doc.indexing_status)"
                :label="getStatusLabel(doc.indexing_status)"
              />
              <span class="flex items-center gap-1">
                {{ t('KNOWLEDGE_BASE.UPDATED_AT') }}
                {{ formatDateTime(doc.updated_at) }}
                <span
                  v-if="doc.updated_by"
                  class="text-n-slate-12"
                  :title="doc.updated_by.email"
                >
                  {{ t('KNOWLEDGE_BASE.BY') }} {{ doc.updated_by.name }}
                </span>
              </span>
            </div>
          </div>
          <div class="flex items-center gap-4 shrink-0">
            <button
              class="relative w-11 h-6 rounded-full transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-n-brand focus:ring-offset-2"
              :class="doc.enabled ? 'bg-n-brand' : 'bg-n-slate-5'"
              role="switch"
              :aria-checked="doc.enabled"
              @click="toggleDocument(doc)"
            >
              <span
                class="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow-sm transition-transform duration-200"
                :class="doc.enabled ? 'translate-x-5' : 'translate-x-0'"
              />
            </button>
            <Button
              :label="t('KNOWLEDGE_BASE.DELETE')"
              variant="link"
              color="ruby"
              @click="deleteDocument(doc)"
            />
          </div>
        </div>
      </div>
    </div>
  </KBSectionCard>
</template>
