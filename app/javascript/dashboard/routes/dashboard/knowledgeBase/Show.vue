<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import KBPageLayout from 'dashboard/components-next/KnowledgeBase/KBPageLayout.vue';
import { shouldBlockEditSessionLeave } from './utils/editSession';
import DocumentList from './components/DocumentList.vue';
import QAPairList from './components/QAPairList.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const activeTab = ref('documents');
const pollInterval = ref(null);
const qaPairListRef = ref(null);
const leaveDialogRef = ref(null);
const pendingLeaveTarget = ref(null);
const isConfirmingLeave = ref(false);
const bypassRouteGuard = ref(false);
const isQaEditSessionActive = ref(false);

const knowledgeBaseId = computed(() => route.params.knowledgeBaseId);
const currentKB = computed(() => store.getters['knowledgeBases/getCurrentKB']);
const hasProcessingDocuments = computed(
  () => store.getters['knowledgeBases/hasProcessingDocuments']
);
const isQaProcessing = computed(
  () => store.getters['knowledgeBases/isQaDocumentProcessing']
);

const tabs = [
  { key: 'documents', label: 'KNOWLEDGE_BASE.TABS.DOCUMENTS' },
  { key: 'qa', label: 'KNOWLEDGE_BASE.TABS.QA' },
];

const backUrl = computed(() => ({
  name: 'knowledge_bases_index',
  params: { accountId: route.params.accountId },
}));

const shouldBlockLeave = () =>
  shouldBlockEditSessionLeave({
    isEditSessionActive: isQaEditSessionActive.value,
    activeTab: activeTab.value,
  });

const loadKB = () => {
  const kbs = store.getters['knowledgeBases/getKnowledgeBases'];
  const cachedKB = kbs.find(
    k => String(k.id) === String(knowledgeBaseId.value)
  );

  if (cachedKB) {
    store.commit('knowledgeBases/setCurrentKB', cachedKB);
  }

  store.dispatch('knowledgeBases/fetchKnowledgeBase', {
    id: knowledgeBaseId.value,
    silent: !!cachedKB,
  });
};

const loadData = () => {
  if (activeTab.value === 'documents') {
    const hasDocuments =
      store.getters['knowledgeBases/getDocuments'].length > 0;
    store.dispatch('knowledgeBases/fetchDocuments', {
      knowledgeBaseId: knowledgeBaseId.value,
      silent: hasDocuments,
    });
  } else if (activeTab.value === 'qa') {
    const hasQaPairs = store.getters['knowledgeBases/getQaPairs'].length > 0;
    store.dispatch('knowledgeBases/fetchQaPairs', {
      knowledgeBaseId: knowledgeBaseId.value,
      silent: hasQaPairs,
    });
  }
};

const openLeaveDialog = target => {
  pendingLeaveTarget.value = target;
  leaveDialogRef.value?.open();
};

const discardQaEditSession = () => {
  qaPairListRef.value?.discardEditSession?.();
  isQaEditSessionActive.value = false;
};

const applyLeaveTarget = async target => {
  if (!target) return;

  if (target.type === 'tab') {
    activeTab.value = target.tab;
    return;
  }

  if (target.type === 'route') {
    bypassRouteGuard.value = true;
    await router.push(target.to);
  }
};

const handleDiscardAndLeave = async () => {
  const target = pendingLeaveTarget.value;
  pendingLeaveTarget.value = null;

  isConfirmingLeave.value = true;
  discardQaEditSession();
  leaveDialogRef.value?.close();
  await applyLeaveTarget(target);
};

const handleStayEditing = () => {
  if (isConfirmingLeave.value) {
    isConfirmingLeave.value = false;
    return;
  }

  pendingLeaveTarget.value = null;
};

const handleTabSwitch = tabKey => {
  if (tabKey === activeTab.value) return;

  if (shouldBlockLeave()) {
    openLeaveDialog({ type: 'tab', tab: tabKey });
    return;
  }

  activeTab.value = tabKey;
};

const handleEditSessionChange = isActive => {
  isQaEditSessionActive.value = isActive;
};

const handleBeforeUnload = event => {
  if (!shouldBlockLeave()) return;

  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.returnValue = '';
};

onMounted(() => {
  loadKB();
  loadData();
  window.addEventListener('beforeunload', handleBeforeUnload);
});

watch(knowledgeBaseId, (newId, oldId) => {
  if (newId && newId !== oldId) {
    store.commit('knowledgeBases/resetState');

    // We can't rely on caching here effectively because cache might be stale or not contain new ID
    // But we can still try to find it in the list if available
    const kbs = store.getters['knowledgeBases/getKnowledgeBases'];
    const cachedKB = kbs.find(k => String(k.id) === String(newId));
    if (cachedKB) {
      store.commit('knowledgeBases/setCurrentKB', cachedKB);
    }

    store.dispatch('knowledgeBases/fetchKnowledgeBase', {
      id: newId,
      silent: !!cachedKB,
    });

    // Force non-silent fetch for sub-resources when switching KB (as state is reset)
    if (activeTab.value === 'documents') {
      store.dispatch('knowledgeBases/fetchDocuments', {
        knowledgeBaseId: newId,
      });
    } else if (activeTab.value === 'qa') {
      store.dispatch('knowledgeBases/fetchQaPairs', {
        knowledgeBaseId: newId,
      });
    }
  }
});

const shouldPoll = computed(
  () => hasProcessingDocuments.value || isQaProcessing.value
);

watch(shouldPoll, needsPoll => {
  if (needsPoll && !pollInterval.value) {
    pollInterval.value = setInterval(() => {
      store.dispatch('knowledgeBases/fetchDocuments', {
        knowledgeBaseId: knowledgeBaseId.value,
        silent: true,
      });
      if (activeTab.value === 'qa' || isQaProcessing.value) {
        store.dispatch('knowledgeBases/fetchQaPairs', {
          knowledgeBaseId: knowledgeBaseId.value,
          silent: true,
        });
      }
    }, 5000);
  } else if (!needsPoll && pollInterval.value) {
    clearInterval(pollInterval.value);
    pollInterval.value = null;
  }
});

watch(activeTab, () => {
  loadData();
});

onBeforeRouteLeave(to => {
  if (bypassRouteGuard.value) {
    bypassRouteGuard.value = false;
    return true;
  }

  if (shouldBlockLeave()) {
    openLeaveDialog({ type: 'route', to });
    return false;
  }

  return true;
});

onUnmounted(() => {
  if (pollInterval.value) {
    clearInterval(pollInterval.value);
  }
  window.removeEventListener('beforeunload', handleBeforeUnload);
  store.commit('knowledgeBases/resetState');
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
        @click="handleTabSwitch(tab.key)"
      >
        {{ t(tab.label) }}
        <span
          v-if="tab.key === 'qa' && isQaEditSessionActive"
          class="ml-2 text-xs font-semibold text-n-amber-12"
        >
          {{ t('KNOWLEDGE_BASE.EDIT_MODE_ACTIVE') }}
        </span>
      </button>
    </div>

    <div class="mt-6">
      <DocumentList
        v-if="activeTab === 'documents'"
        :knowledge-base-id="knowledgeBaseId"
      />
      <QAPairList
        v-else-if="activeTab === 'qa'"
        ref="qaPairListRef"
        :knowledge-base-id="knowledgeBaseId"
        @edit-session-change="handleEditSessionChange"
      />
    </div>
  </KBPageLayout>

  <Dialog
    ref="leaveDialogRef"
    type="alert"
    :title="t('KNOWLEDGE_BASE.LEAVE_EDIT_MODE_TITLE')"
    :description="t('KNOWLEDGE_BASE.LEAVE_EDIT_MODE_MESSAGE')"
    :confirm-button-label="t('KNOWLEDGE_BASE.DISCARD_CHANGES')"
    :cancel-button-label="t('KNOWLEDGE_BASE.CONTINUE_EDITING')"
    @confirm="handleDiscardAndLeave"
    @close="handleStayEditing"
  />
</template>
