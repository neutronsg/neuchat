<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import KBSectionCard from 'dashboard/components-next/KnowledgeBase/KBSectionCard.vue';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const isEditing = ref(false);
const editingId = ref(null);
const form = ref({ question: '', answer: '' });

const qaPairs = computed(() => store.getters['knowledgeBases/getQaPairs']);
const syncRequired = computed(
  () => store.getters['knowledgeBases/getQaSyncRequired']
);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

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

const startAdd = () => {
  form.value = { question: '', answer: '' };
  editingId.value = null;
  isEditing.value = true;
};

const startEdit = qa => {
  form.value = { question: qa.question, answer: qa.answer };
  editingId.value = qa.id;
  isEditing.value = true;
};

const cancelEdit = () => {
  isEditing.value = false;
  editingId.value = null;
  form.value = { question: '', answer: '' };
};

const saveQaPair = async () => {
  try {
    if (editingId.value) {
      await store.dispatch('knowledgeBases/updateQaPair', {
        knowledgeBaseId: props.knowledgeBaseId,
        qaPairId: editingId.value,
        data: form.value,
      });
    } else {
      await store.dispatch('knowledgeBases/createQaPair', {
        knowledgeBaseId: props.knowledgeBaseId,
        data: form.value,
      });
    }
    cancelEdit();
  } catch (error) {
    showAlert(error.message);
  }
};

const deleteQaPair = async qa => {
  if (!window.confirm(t('KNOWLEDGE_BASE.CONFIRM_DELETE_QA'))) return;

  try {
    await store.dispatch('knowledgeBases/deleteQaPair', {
      knowledgeBaseId: props.knowledgeBaseId,
      qaPairId: qa.id,
    });
  } catch (error) {
    showAlert(error.message);
  }
};

const syncToNeuAI = async () => {
  try {
    await store.dispatch('knowledgeBases/syncQaPairs', props.knowledgeBaseId);
    showAlert(t('KNOWLEDGE_BASE.SYNC_SUCCESS'));
  } catch (error) {
    showAlert(error.message);
  }
};
</script>

<template>
  <KBSectionCard :title="t('KNOWLEDGE_BASE.QA_TITLE')">
    <template #actions>
      <Button :label="t('KNOWLEDGE_BASE.ADD_QA')" @click="startAdd" />
    </template>

    <div
      v-if="syncRequired"
      class="mb-4 flex items-center justify-between gap-4 rounded-xl border border-n-amber-6 bg-n-amber-3 px-4 py-3"
    >
      <span class="text-sm text-n-amber-11">{{
        t('KNOWLEDGE_BASE.SYNC_REQUIRED')
      }}</span>
      <Button
        :label="
          uiFlags.isSyncing
            ? t('KNOWLEDGE_BASE.SYNCING')
            : t('KNOWLEDGE_BASE.SYNC_NOW')
        "
        color="amber"
        :is-loading="uiFlags.isSyncing"
        @click="syncToNeuAI"
      />
    </div>

    <div
      v-if="isEditing"
      class="mb-4 rounded-xl border border-n-weak bg-n-slate-1 p-4"
    >
      <div class="mb-3">
        <label class="block text-sm font-medium text-n-slate-12 mb-1">{{
          t('KNOWLEDGE_BASE.QUESTION')
        }}</label>
        <textarea
          v-model="form.question"
          class="w-full rounded-lg border border-n-weak bg-n-background p-2 text-sm text-n-slate-12"
          rows="2"
        />
      </div>
      <div class="mb-3">
        <label class="block text-sm font-medium text-n-slate-12 mb-1">{{
          t('KNOWLEDGE_BASE.ANSWER')
        }}</label>
        <textarea
          v-model="form.answer"
          class="w-full rounded-lg border border-n-weak bg-n-background p-2 text-sm text-n-slate-12"
          rows="3"
        />
      </div>
      <div class="flex gap-2">
        <Button :label="t('KNOWLEDGE_BASE.SAVE')" @click="saveQaPair" />
        <Button
          :label="t('KNOWLEDGE_BASE.CANCEL')"
          variant="outline"
          color="slate"
          @click="cancelEdit"
        />
      </div>
    </div>

    <div v-if="uiFlags.isFetchingQaPairs" class="py-6 text-center">
      <span class="text-sm text-n-slate-11">{{
        t('KNOWLEDGE_BASE.LOADING')
      }}</span>
    </div>

    <div v-else-if="qaPairs.length === 0" class="py-6 text-center">
      <p class="text-sm text-n-slate-11">
        {{ t('KNOWLEDGE_BASE.NO_QA_PAIRS') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-3">
      <div
        v-for="qa in qaPairs"
        :key="qa.id"
        class="rounded-xl border border-n-weak bg-n-background px-4 py-4"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
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
          <div class="flex items-center gap-2">
            <Button
              :label="t('KNOWLEDGE_BASE.EDIT')"
              variant="ghost"
              color="slate"
              @click="startEdit(qa)"
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
</template>
