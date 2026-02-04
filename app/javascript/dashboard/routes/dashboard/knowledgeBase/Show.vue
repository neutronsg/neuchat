<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import KBPageLayout from 'dashboard/components-next/KnowledgeBase/KBPageLayout.vue';
import DocumentList from './components/DocumentList.vue';
import QAPairList from './components/QAPairList.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const activeTab = ref('documents');
const pollInterval = ref(null);

const knowledgeBaseId = computed(() => route.params.knowledgeBaseId);
const currentKB = computed(() => store.getters['knowledgeBases/getCurrentKB']);
const hasProcessingDocuments = computed(
  () => store.getters['knowledgeBases/hasProcessingDocuments']
);

const tabs = [
  { key: 'documents', label: 'KNOWLEDGE_BASE.TABS.DOCUMENTS' },
  { key: 'qa', label: 'KNOWLEDGE_BASE.TABS.QA' },
];

const backUrl = computed(() => ({
  name: 'knowledge_bases_index',
  params: { accountId: route.params.accountId },
}));

onMounted(() => {
  store.dispatch('knowledgeBases/fetchKnowledgeBase', knowledgeBaseId.value);
  store.dispatch('knowledgeBases/fetchDocuments', knowledgeBaseId.value);
});

watch(hasProcessingDocuments, hasProcessing => {
  if (hasProcessing && !pollInterval.value) {
    pollInterval.value = setInterval(() => {
      store.dispatch('knowledgeBases/fetchDocuments', knowledgeBaseId.value);
    }, 5000);
  } else if (!hasProcessing && pollInterval.value) {
    clearInterval(pollInterval.value);
    pollInterval.value = null;
  }
});

watch(activeTab, tab => {
  if (tab === 'qa') {
    store.dispatch('knowledgeBases/fetchQaPairs', knowledgeBaseId.value);
  }
});

onUnmounted(() => {
  if (pollInterval.value) {
    clearInterval(pollInterval.value);
  }
});
</script>

<template>
  <KBPageLayout
    :title="currentKB?.name || t('KNOWLEDGE_BASE.LOADING')"
    :description="currentKB?.description || ''"
    :back-button-url="backUrl"
  >
    <div class="flex items-center gap-2 border-b border-n-weak pb-3">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        class="px-3 py-2 text-sm font-medium rounded-lg transition"
        :class="
          activeTab === tab.key
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="activeTab = tab.key"
      >
        {{ t(tab.label) }}
      </button>
    </div>

    <div class="mt-6">
      <DocumentList
        v-if="activeTab === 'documents'"
        :knowledge-base-id="knowledgeBaseId"
      />
      <QAPairList
        v-else-if="activeTab === 'qa'"
        :knowledge-base-id="knowledgeBaseId"
      />
    </div>
  </KBPageLayout>
</template>
