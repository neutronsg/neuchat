<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  categories: { type: Object, required: true },
  accountId: { type: [String, Number], required: true },
});
const expanded = ref(false);
const sorted = computed(() =>
  Object.entries(props.categories).sort(
    (a, b) => b[1] - a[1] || a[0].localeCompare(b[0])
  )
);
const rows = computed(() =>
  expanded.value ? sorted.value : sorted.value.slice(0, 8)
);
const maximum = computed(() => Math.max(1, ...sorted.value.map(row => row[1])));
</script>

<template>
  <section
    class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-5 sm:p-6"
    aria-labelledby="category-heading"
  >
    <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2
          id="category-heading"
          class="m-0 text-base font-medium text-n-slate-12"
        >
          {{ $t('OCA_REPORT.CATEGORIES') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ $t('OCA_REPORT.CATEGORIES_HELP') }}
        </p>
      </div>
      <router-link
        :to="`/app/accounts/${accountId}/reports/labels_overview`"
        class="rounded text-sm font-medium text-n-blue-text hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        {{ $t('OCA_REPORT.VIEW_LABELS') }}
      </router-link>
    </div>
    <p v-if="!rows.length" class="py-8 text-center text-sm text-n-slate-11">
      {{ $t('OCA_REPORT.NO_CATEGORIES') }}
    </p>
    <ol v-else class="m-0 flex list-none flex-col gap-4 p-0">
      <li
        v-for="[name, count] in rows"
        :key="name"
        class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1.5"
      >
        <span class="break-words text-sm text-n-slate-12">{{ name }}</span>
        <span class="text-sm font-medium tabular-nums text-n-slate-12">{{
          count.toLocaleString()
        }}</span>
        <svg
          class="col-span-2 h-2 w-full overflow-hidden rounded-sm text-n-brand"
          viewBox="0 0 100 8"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <rect width="100" height="8" class="fill-n-alpha-black2" />
          <rect
            :width="(count / maximum) * 100"
            height="8"
            fill="currentColor"
          />
        </svg>
      </li>
    </ol>
    <Button
      v-if="sorted.length > 8"
      class="mt-5"
      variant="ghost"
      color="slate"
      size="sm"
      :aria-expanded="expanded"
      :label="
        expanded
          ? $t('OCA_REPORT.SHOW_LESS')
          : $t('OCA_REPORT.SHOW_ALL', { count: sorted.length })
      "
      @click="expanded = !expanded"
    />
  </section>
</template>
