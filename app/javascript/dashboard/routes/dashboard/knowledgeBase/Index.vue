<script setup>
import { computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import KBPageLayout from 'dashboard/components-next/KnowledgeBase/KBPageLayout.vue';
import CardLayout from 'dashboard/components-next/CardLayout.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const knowledgeBases = computed(
  () => store.getters['knowledgeBases/getKnowledgeBases']
);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

onMounted(() => {
  store.dispatch('knowledgeBases/fetchKnowledgeBases');
});

const navigateToKB = kb => {
  router.push({
    name: 'knowledge_base_show',
    params: { knowledgeBaseId: kb.id },
  });
};
</script>

<template>
  <KBPageLayout
    :title="t('KNOWLEDGE_BASE.TITLE')"
    :description="t('KNOWLEDGE_BASE.DESCRIPTION')"
  >
    <div v-if="uiFlags.isFetching" class="py-16 text-center">
      <span class="text-sm text-n-slate-11">{{
        t('KNOWLEDGE_BASE.LOADING')
      }}</span>
    </div>

    <div v-else-if="knowledgeBases.length === 0" class="py-16 text-center">
      <p class="text-sm text-n-slate-11">{{ t('KNOWLEDGE_BASE.EMPTY') }}</p>
    </div>

    <div v-else class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
      <CardLayout
        v-for="kb in knowledgeBases"
        :key="kb.id"
        class="cursor-pointer transition hover:shadow-md"
        @click="navigateToKB(kb)"
      >
        <div class="flex flex-col gap-3">
          <div>
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ kb.name }}
            </h3>
            <p class="mt-1 text-sm text-n-slate-11 line-clamp-2">
              {{ kb.description || t('KNOWLEDGE_BASE.NO_DESCRIPTION') }}
            </p>
          </div>
          <div class="flex items-center gap-4 text-xs text-n-slate-11">
            <span
              >{{ kb.documents_count }}
              {{ t('KNOWLEDGE_BASE.DOCUMENTS') }}</span
            >
            <span
              >{{ kb.qa_pairs_count }} {{ t('KNOWLEDGE_BASE.QA_PAIRS') }}</span
            >
          </div>
        </div>
      </CardLayout>
    </div>
  </KBPageLayout>
</template>
