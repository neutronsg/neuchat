<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  usage: { type: Object, default: null },
  loading: Boolean,
  error: Boolean,
});
defineEmits(['retry']);
const total = computed(() => props.usage?.total);
const partial = computed(
  () =>
    (total.value?.unpricedCalls || 0) +
      (total.value?.unpricedGuardrailCalls || 0) >
    0
);
const money = value =>
  value === null || value === undefined
    ? '—'
    : `${props.usage?.currency || 'USD'} ${Number(value).toLocaleString(undefined, { maximumFractionDigits: 6 })}`;
</script>

<template>
  <section
    class="rounded-xl border border-n-weak bg-n-solid-2 p-5 sm:p-6"
    aria-labelledby="cost-heading"
  >
    <h2 id="cost-heading" class="m-0 text-base font-medium text-n-slate-12">
      {{ $t('OCA_REPORT.COST_HEADING') }}
    </h2>
    <p v-if="loading" role="status" class="py-6 text-sm text-n-slate-11">
      {{ $t('OCA_REPORT.LOADING') }}
    </p>
    <div v-else-if="error" role="alert" class="py-6">
      <p>{{ $t('OCA_REPORT.USAGE_ERROR') }}</p>
      <Button :label="$t('OCA_REPORT.RETRY')" @click="$emit('retry')" />
    </div>
    <template v-else-if="usage">
      <div class="mt-5 grid grid-cols-1 gap-6 sm:grid-cols-3">
        <div>
          <p class="m-0 text-xs text-n-slate-11">
            {{
              $t(
                partial
                  ? 'OCA_REPORT.KNOWN_SUBTOTAL'
                  : 'OCA_REPORT.COMBINED_COST'
              )
            }}
          </p>
          <p
            class="mb-0 mt-2 text-2xl font-semibold tabular-nums text-n-slate-12"
          >
            {{
              money(
                usage.storage === 'long_term_metering'
                  ? total?.estimatedCombinedCostUsd
                  : total?.estimatedCostUsd
              )
            }}
          </p>
          <p v-if="partial" class="mb-0 mt-1 text-xs text-n-amber-11">
            {{ $t('OCA_REPORT.PARTIAL_COST') }}
          </p>
        </div>
        <div>
          <p class="m-0 text-xs text-n-slate-11">{{ $t('OCA_REPORT.COST') }}</p>
          <p class="mb-0 mt-2 text-lg tabular-nums">
            {{ money(total?.estimatedCostUsd) }}
          </p>
        </div>
        <div v-if="total?.guardrailCalls > 0">
          <p class="m-0 text-xs text-n-slate-11">
            {{ $t('OCA_REPORT.GUARDRAIL_COST') }}
          </p>
          <p class="mb-0 mt-2 text-lg tabular-nums">
            {{ money(total?.estimatedGuardrailCostUsd) }}
          </p>
        </div>
      </div>
      <details
        class="mt-5 border-t border-n-weak pt-4 text-xs leading-5 text-n-slate-11"
      >
        <summary
          class="w-fit cursor-pointer rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ $t('OCA_REPORT.USAGE_ABOUT') }}
        </summary>
        <p>
          {{
            $t(
              usage.storage === 'long_term_metering'
                ? 'OCA_REPORT.LONG_TERM_COST_NOTE'
                : 'OCA_REPORT.COST_NOTE'
            )
          }}
        </p>
        <p>
          {{ $t('OCA_REPORT.COVERAGE') }}
          {{ total?.usageMissingCalls ?? '—' }} /
          {{ total?.unpricedCalls ?? '—' }}
        </p>
        <p v-if="total?.guardrailCalls > 0">
          {{ $t('OCA_REPORT.GUARDRAIL_COVERAGE') }}
          {{ total?.unpricedGuardrailCalls ?? '—' }}
        </p>
        <p v-if="usage.priceSourceMode === 'maintained_table'">
          {{ $t('OCA_REPORT.MAINTAINED_PRICES') }}
        </p>
        <p v-if="usage.priceSyncStale">{{ $t('OCA_REPORT.PRICE_STALE') }}</p>
        <p
          v-if="
            usage.priceLastSyncedAt &&
            usage.priceSourceMode !== 'maintained_table'
          "
        >
          {{ $t('OCA_REPORT.PRICE_SYNC') }}
          {{ new Date(usage.priceLastSyncedAt).toLocaleString() }}
        </p>
      </details>
    </template>
  </section>
</template>
