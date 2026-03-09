<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import KBSectionCard from 'dashboard/components-next/KnowledgeBase/KBSectionCard.vue';
import KBStatusPill from 'dashboard/components-next/KnowledgeBase/KBStatusPill.vue';
import DocumentUploadDialog from './DocumentUploadDialog.vue';
import DocumentChunkSettingsDialog from './DocumentChunkSettingsDialog.vue';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const uploadDialogRef = ref(null);
const chunkSettingsDialogRef = ref(null);

const KB_DOCUMENT_MAX_SIZE_MB = 100;
const KB_DOCUMENT_ALLOWED_EXTENSIONS = [
  'txt',
  'markdown',
  'md',
  'mdx',
  'pdf',
  'html',
  'htm',
  'xlsx',
  'xls',
  'vtt',
  'properties',
  'doc',
  'docx',
  'csv',
  'eml',
  'msg',
  'pptx',
  'xml',
  'epub',
];

const acceptedFileTypes = computed(() =>
  KB_DOCUMENT_ALLOWED_EXTENSIONS.map(ext => `.${ext}`).join(',')
);

const allowedFileTypesLabel = computed(() =>
  KB_DOCUMENT_ALLOWED_EXTENSIONS.map(ext => `.${ext}`).join(', ')
);

const documentUploadDescription = computed(() =>
  t('KNOWLEDGE_BASE.DOCUMENT_UPLOAD_LIMITS', {
    maxSize: KB_DOCUMENT_MAX_SIZE_MB,
    fileTypes: allowedFileTypesLabel.value,
  })
);

const documents = computed(() => store.getters['knowledgeBases/getDocuments']);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

const getStatusLabel = displayStatus => {
  if (!displayStatus || displayStatus === 'unknown') return 'unknown';
  return (
    t(`KNOWLEDGE_BASE.STATUS_${displayStatus.toUpperCase()}`) || displayStatus
  );
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

const triggerUpload = () => uploadDialogRef.value?.open();

const openChunkSettings = doc => {
  if (doc.display_status === 'processing') {
    showAlert(t('KNOWLEDGE_BASE.CHUNK_SETTINGS_DISABLED_PROCESSING'));
    return;
  }

  chunkSettingsDialogRef.value?.open(doc);
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
  <KBSectionCard
    :title="t('KNOWLEDGE_BASE.DOCUMENTS_TITLE')"
    :description="documentUploadDescription"
  >
    <template #actions>
      <div class="shrink-0">
        <Button
          :label="
            uiFlags.isCreating
              ? t('KNOWLEDGE_BASE.UPLOADING')
              : t('KNOWLEDGE_BASE.UPLOAD_DOCUMENT')
          "
          :is-loading="uiFlags.isCreating"
          @click="triggerUpload"
        />
      </div>
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
        <div class="flex items-center justify-between gap-4">
          <div class="min-w-0">
            <div class="flex items-center gap-2 mb-4">
              <div class="text-sm font-semibold text-n-slate-12 truncate">
                {{ doc.name }}
              </div>
              <KBStatusPill
                :status="doc.display_status || 'unknown'"
                :label="getStatusLabel(doc.display_status)"
              />
            </div>
            <div
              class="flex flex-wrap items-center gap-3 text-xs text-n-slate-11"
            >
              <span>{{ doc.word_count }} {{ t('KNOWLEDGE_BASE.WORDS') }}</span>
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
          <div class="flex items-center gap-8 shrink-0">
            <Button
              :label="t('KNOWLEDGE_BASE.CHUNK_SETTINGS_BUTTON')"
              variant="link"
              color="slate"
              :disabled="doc.display_status === 'processing'"
              @click="openChunkSettings(doc)"
            />
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

  <DocumentUploadDialog
    ref="uploadDialogRef"
    :knowledge-base-id="knowledgeBaseId"
    :accepted-file-types="acceptedFileTypes"
    :max-file-size-mb="KB_DOCUMENT_MAX_SIZE_MB"
  />

  <DocumentChunkSettingsDialog
    ref="chunkSettingsDialogRef"
    :knowledge-base-id="knowledgeBaseId"
  />
</template>
