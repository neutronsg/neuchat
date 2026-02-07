<script setup>
import { ref, computed, watch, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import KBSectionCard from 'dashboard/components-next/KnowledgeBase/KBSectionCard.vue';
import KBStatusPill from 'dashboard/components-next/KnowledgeBase/KBStatusPill.vue';
import {
  isQaPairDirty,
  shouldShowQaProcessingHint,
  sortByCreatedAtDesc,
} from '../utils/editSession';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});
const emit = defineEmits(['editSessionChange']);

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const isEditMode = ref(false);
const qaDialog = ref(null);
const isEditing = ref(false);
const editingId = ref(null);
const form = ref({ question: '', answer: '' });

const localQaPairs = ref([]);
const deletedQaPairIds = ref([]);

const qaPairs = computed(() => store.getters['knowledgeBases/getQaPairs']);
const originalQaPairMap = computed(() => {
  const map = {};
  qaPairs.value.forEach(qa => {
    map[qa.id] = qa;
  });
  return map;
});
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);
const qaDocumentStatus = computed(
  () => store.getters['knowledgeBases/getQaDocumentStatus']
);
const isProcessing = computed(
  () => store.getters['knowledgeBases/isQaDocumentProcessing']
);

const canEdit = computed(() => !isProcessing.value);
const displayedQaPairs = computed(() =>
  isEditMode.value ? sortByCreatedAtDesc(localQaPairs.value) : qaPairs.value
);
const hasData = computed(() => displayedQaPairs.value.length > 0);
const showProcessingHint = computed(() =>
  shouldShowQaProcessingHint({ canEdit: canEdit.value })
);

const isDirtyQa = qa =>
  isQaPairDirty({
    qaPair: qa,
    originalQaPair: originalQaPairMap.value[qa.id],
  });

const statusLabel = computed(() => {
  const status = qaDocumentStatus.value?.display_status;
  if (!status || status === 'unknown') return '';
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return t(`KNOWLEDGE_BASE.STATUS_${status.toUpperCase()}`) || status;
});

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

const enterEditMode = () => {
  localQaPairs.value = sortByCreatedAtDesc(
    JSON.parse(JSON.stringify(qaPairs.value))
  );
  deletedQaPairIds.value = [];
  isEditMode.value = true;
};

const exitEditMode = () => {
  isEditMode.value = false;
  localQaPairs.value = [];
  deletedQaPairIds.value = [];
};

const openAddModal = () => {
  form.value = { question: '', answer: '' };
  editingId.value = null;
  isEditing.value = false;
  qaDialog.value?.open();
};

const openEditModal = qa => {
  form.value = { question: qa.question, answer: qa.answer };
  editingId.value = qa.id;
  isEditing.value = true;
  qaDialog.value?.open();
};

const closeDialog = () => {
  qaDialog.value?.close();
};

const onDialogClose = () => {
  form.value = { question: '', answer: '' };
  editingId.value = null;
  isEditing.value = false;
};

const saveQaPair = () => {
  if (editingId.value) {
    const index = localQaPairs.value.findIndex(q => q.id === editingId.value);
    if (index !== -1) {
      localQaPairs.value[index] = {
        ...localQaPairs.value[index],
        ...form.value,
        updated_at: new Date().toISOString(),
      };
    }
  } else {
    const newQa = {
      id: `temp-${Date.now()}`,
      ...form.value,
      updated_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
    };

    if (!isEditMode.value) {
      // If adding from view mode, initialize local state with current store data
      // This prevents overwriting existing data with just the new item
      localQaPairs.value = sortByCreatedAtDesc(
        JSON.parse(JSON.stringify(qaPairs.value))
      );
      deletedQaPairIds.value = [];
      isEditMode.value = true;
    }

    localQaPairs.value.unshift(newQa);
  }
  closeDialog();
};

const saveChanges = async () => {
  store.commit('knowledgeBases/setUIFlag', { isSyncing: true });
  try {
    // 1. Handle Deletions
    const deletePromises = deletedQaPairIds.value.map(id =>
      store.dispatch('knowledgeBases/deleteQaPair', {
        knowledgeBaseId: props.knowledgeBaseId,
        qaPairId: id,
      })
    );

    // 2. Handle Creations and Updates
    const updatePromises = localQaPairs.value.map(qa => {
      if (typeof qa.id === 'string' && qa.id.startsWith('temp-')) {
        // Create new
        return store.dispatch('knowledgeBases/createQaPair', {
          knowledgeBaseId: props.knowledgeBaseId,
          data: { question: qa.question, answer: qa.answer },
        });
      }
      // Update existing
      const original = qaPairs.value.find(q => q.id === qa.id);
      if (
        original &&
        (original.question !== qa.question || original.answer !== qa.answer)
      ) {
        return store.dispatch('knowledgeBases/updateQaPair', {
          knowledgeBaseId: props.knowledgeBaseId,
          qaPairId: qa.id,
          data: { question: qa.question, answer: qa.answer },
        });
      }

      return Promise.resolve();
    });

    await Promise.all([...deletePromises, ...updatePromises]);

    // 3. Sync
    await store.dispatch('knowledgeBases/syncQaPairs', props.knowledgeBaseId);

    // 4. Refresh list
    await store.dispatch('knowledgeBases/fetchQaPairs', {
      knowledgeBaseId: props.knowledgeBaseId,
    });

    showAlert(t('KNOWLEDGE_BASE.SYNC_SUCCESS'));
    exitEditMode();
  } catch (error) {
    showAlert(error.message);
  } finally {
    store.commit('knowledgeBases/setUIFlag', { isSyncing: false });
  }
};

const deleteQaPair = async qa => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('KNOWLEDGE_BASE.CONFIRM_DELETE_QA'))) return;

  if (typeof qa.id === 'string' && qa.id.startsWith('temp-')) {
    // Remove from local list if it's a temp item
    localQaPairs.value = localQaPairs.value.filter(q => q.id !== qa.id);
  } else {
    // Mark for deletion if it's a persistent item
    localQaPairs.value = localQaPairs.value.filter(q => q.id !== qa.id);
    deletedQaPairIds.value.push(qa.id);
  }
};

const discardEditSession = () => {
  exitEditMode();
};

watch(isEditMode, isEditingNow => {
  emit('editSessionChange', isEditingNow);
});

onUnmounted(() => {
  emit('editSessionChange', false);
});

defineExpose({ discardEditSession });
</script>

<template>
  <div
    :class="isEditMode ? 'rounded-2xl ring-2 ring-n-amber-9 ring-offset-2' : ''"
  >
    <KBSectionCard :title="t('KNOWLEDGE_BASE.QA_TITLE')">
      <template #status>
        <KBStatusPill
          v-if="qaDocumentStatus?.display_status"
          :status="qaDocumentStatus.display_status"
          :label="statusLabel"
        />
        <span
          v-if="isEditMode"
          class="inline-flex items-center rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-semibold text-n-amber-12"
        >
          {{ t('KNOWLEDGE_BASE.EDIT_MODE_ACTIVE') }}
        </span>
      </template>
      <template #actions>
        <div class="flex items-center gap-3">
          <template v-if="isEditMode">
            <div class="flex items-center gap-2">
              <span
                class="inline-flex items-center rounded-md bg-n-amber-3 px-2 py-1 text-xs font-semibold text-n-amber-12"
              >
                {{ t('KNOWLEDGE_BASE.UNSAVED_SESSION') }}
              </span>
              <Button
                :label="t('KNOWLEDGE_BASE.SAVE_CHANGES')"
                :is-loading="uiFlags.isSyncing"
                color="amber"
                @click="saveChanges"
              />
            </div>
            <Button
              :label="t('KNOWLEDGE_BASE.CANCEL_EDIT')"
              variant="outline"
              color="slate"
              @click="exitEditMode"
            />
          </template>
          <template v-else>
            <Button
              v-if="hasData"
              :label="t('KNOWLEDGE_BASE.EDIT')"
              :disabled="!canEdit"
              :title="!canEdit ? t('KNOWLEDGE_BASE.PROCESSING_HINT') : ''"
              @click="enterEditMode"
            />
            <Button
              :label="t('KNOWLEDGE_BASE.ADD_QA')"
              :disabled="!canEdit"
              :title="!canEdit ? t('KNOWLEDGE_BASE.PROCESSING_HINT') : ''"
              @click="openAddModal"
            />
          </template>
        </div>
      </template>

      <p
        v-if="showProcessingHint"
        class="mt-2 rounded-md bg-n-amber-3 px-3 py-2 text-xs font-semibold text-n-amber-12"
      >
        {{ t('KNOWLEDGE_BASE.PROCESSING_HINT') }}
      </p>

      <!-- 编辑模式：列表上方的新增按钮 -->
      <div v-if="isEditMode" class="mb-4">
        <p class="mb-2 text-xs font-medium text-n-amber-12">
          {{ t('KNOWLEDGE_BASE.EDIT_SESSION_HINT') }}
        </p>
        <Button :label="t('KNOWLEDGE_BASE.ADD_QA')" @click="openAddModal" />
      </div>

      <!-- 弹窗 -->
      <Dialog
        ref="qaDialog"
        :title="
          isEditing ? t('KNOWLEDGE_BASE.EDIT_QA') : t('KNOWLEDGE_BASE.ADD_QA')
        "
        :confirm-button-label="t('KNOWLEDGE_BASE.CONFIRM')"
        :cancel-button-label="t('KNOWLEDGE_BASE.CANCEL')"
        :disable-confirm-button="!form.question.trim() || !form.answer.trim()"
        @confirm="saveQaPair"
        @close="onDialogClose"
      >
        <div class="flex flex-col gap-4">
          <div>
            <label class="mb-1 block text-sm font-medium text-n-slate-12">
              {{ t('KNOWLEDGE_BASE.QUESTION') }}
            </label>
            <textarea
              v-model="form.question"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 p-3 text-sm text-n-slate-12"
              rows="3"
              :placeholder="t('KNOWLEDGE_BASE.QUESTION_PLACEHOLDER')"
            />
          </div>
          <div>
            <label class="mb-1 block text-sm font-medium text-n-slate-12">
              {{ t('KNOWLEDGE_BASE.ANSWER') }}
            </label>
            <textarea
              v-model="form.answer"
              class="w-full rounded-lg border border-n-weak bg-n-surface-1 p-3 text-sm text-n-slate-12"
              rows="5"
              :placeholder="t('KNOWLEDGE_BASE.ANSWER_PLACEHOLDER')"
            />
          </div>
        </div>
      </Dialog>

      <div
        v-if="uiFlags.isFetchingQaPairs && !hasData"
        class="py-6 text-center"
      >
        <span class="text-sm text-n-slate-11">{{
          t('KNOWLEDGE_BASE.LOADING')
        }}</span>
      </div>

      <div v-else-if="!hasData" class="py-6 text-center">
        <p class="text-sm text-n-slate-11">
          {{ t('KNOWLEDGE_BASE.NO_QA_PAIRS') }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-3">
        <div
          v-for="qa in displayedQaPairs"
          :key="qa.id"
          class="rounded-xl border px-4 py-4"
          :class="
            isEditMode && isDirtyQa(qa)
              ? 'border-n-amber-8 bg-n-amber-2'
              : 'border-n-weak bg-n-background'
          "
        >
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0 flex-1">
              <div class="mb-1 flex items-center gap-2">
                <span
                  v-if="isEditMode && isDirtyQa(qa)"
                  class="inline-flex items-center rounded-md bg-n-amber-4 px-2 py-0.5 text-[11px] font-semibold text-n-amber-12"
                >
                  {{ t('KNOWLEDGE_BASE.DIRTY_ITEM') }}
                </span>
              </div>
              <p class="text-sm font-semibold text-n-slate-12">
                {{ t('KNOWLEDGE_BASE.QUESTION_PREFIX') }} {{ qa.question }}
              </p>
              <p class="mt-2 text-sm text-n-slate-11">
                {{ t('KNOWLEDGE_BASE.ANSWER_PREFIX') }} {{ qa.answer }}
              </p>
              <div class="mt-3 flex items-center gap-1 text-xs text-n-slate-11">
                {{ t('KNOWLEDGE_BASE.UPDATED_AT') }}
                {{ formatDateTime(qa.updated_at) }}
                <span
                  v-if="qa.updated_by"
                  class="text-n-slate-12"
                  :title="qa.updated_by.email"
                >
                  {{ t('KNOWLEDGE_BASE.BY') }} {{ qa.updated_by.name }}
                </span>
              </div>
            </div>
            <div v-if="isEditMode" class="flex items-center gap-2 shrink-0">
              <Button
                :label="t('KNOWLEDGE_BASE.EDIT')"
                variant="ghost"
                color="slate"
                @click="openEditModal(qa)"
              />
              <Button
                :label="t('KNOWLEDGE_BASE.DELETE')"
                variant="ghost"
                color="ruby"
                @click="deleteQaPair(qa)"
              />
            </div>
          </div>
        </div>
      </div>
    </KBSectionCard>
  </div>
</template>
