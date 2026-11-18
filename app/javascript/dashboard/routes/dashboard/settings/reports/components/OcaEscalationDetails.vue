<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  report: { type: Object, required: true },
  loading: Boolean,
  reason: { type: String, default: '' },
  page: { type: Number, default: 1 },
  accountId: { type: [String, Number], required: true },
});
const emit = defineEmits(['filter', 'page']);
const dateTime = value =>
  new Date(value).toLocaleString('en-SG', {
    timeZone: 'Asia/Singapore',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    year: 'numeric',
  });
const range = computed(() => ({
  start: props.report.detail_total ? (props.page - 1) * 25 + 1 : 0,
  end: Math.min(props.page * 25, props.report.detail_total),
  total: props.report.detail_total,
}));
</script>

<template>
  <section
    class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-2"
    aria-labelledby="escalation-heading"
    :aria-busy="loading"
  >
    <div
      class="flex flex-col justify-between gap-4 p-5 sm:flex-row sm:items-center sm:p-6"
    >
      <div>
        <h2
          id="escalation-heading"
          class="m-0 text-base font-medium text-n-slate-12"
        >
          {{ $t('OCA_REPORT.DETAILS') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ $t('OCA_REPORT.DETAILS_HELP') }}
        </p>
      </div>
      <label
        class="flex min-w-0 flex-col gap-1.5 text-sm text-n-slate-11 sm:w-64"
      >
        {{ $t('OCA_REPORT.REASON') }}
        <select
          :value="reason"
          class="!m-0 !h-10 !w-full !rounded-lg !border !border-n-weak !bg-n-solid-2 !py-2 !pl-3 !pr-8 !text-sm !text-n-slate-12 focus:!border-n-brand focus:!ring-1 focus:!ring-n-brand"
          @change="emit('filter', $event.target.value)"
        >
          <option value="">{{ $t('OCA_REPORT.ALL_REASONS') }}</option>
          <option
            v-for="key in [
              'user_requested_support',
              'no_answer_found',
              'requires_other_person',
            ]"
            :key="key"
            :value="key"
          >
            {{ $t(`OCA_REPORT.REASONS.${key}`) }}
          </option>
        </select>
      </label>
    </div>
    <p
      v-if="loading"
      role="status"
      class="m-0 border-t border-n-weak p-8 text-center text-sm text-n-slate-11"
    >
      {{ $t('OCA_REPORT.LOADING') }}
    </p>
    <div
      v-else-if="!report.details.length"
      class="flex flex-col items-center gap-3 border-t border-n-weak px-6 py-12"
    >
      <p class="m-0 text-sm font-medium text-n-slate-12">
        {{ $t(reason ? 'OCA_REPORT.NO_MATCHES' : 'OCA_REPORT.EMPTY') }}
      </p>
      <Button
        v-if="reason"
        size="sm"
        color="slate"
        variant="outline"
        :label="$t('OCA_REPORT.CLEAR_FILTER')"
        @click="emit('filter', '')"
      />
    </div>
    <div
      v-else
      class="overflow-x-auto"
      tabindex="0"
      :aria-label="$t('OCA_REPORT.DETAILS')"
    >
      <table class="m-0 w-full min-w-[760px] border-collapse text-left text-sm">
        <thead class="border-y border-n-weak bg-n-alpha-black2 text-n-slate-11">
          <tr>
            <th
              v-for="key in [
                'CONVERSATION',
                'REASON',
                'DESTINATION',
                'CATEGORIES',
                'OUTCOME',
              ]"
              :key="key"
              scope="col"
              class="px-5 py-3 text-xs font-medium"
            >
              {{ $t(`OCA_REPORT.${key}`) }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="row in report.details"
            :key="row.conversation_id"
            class="align-top hover:bg-n-alpha-black2"
          >
            <td class="px-5 py-4">
              <router-link
                :to="`/app/accounts/${accountId}/conversations/${row.conversation_id}`"
                class="inline-flex items-center gap-1 rounded font-medium text-n-blue-text hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                :aria-label="
                  $t('OCA_REPORT.OPEN_CONVERSATION', {
                    id: row.conversation_id,
                  })
                "
              >
                {{
                  $t('OCA_REPORT.CONVERSATION_NUMBER', {
                    id: row.conversation_id,
                  })
                }}<span
                  class="i-lucide-arrow-up-right size-3.5"
                  aria-hidden="true"
                />
              </router-link>
              <time
                :datetime="row.escalated_at"
                class="mt-1 block whitespace-nowrap text-xs text-n-slate-11"
                >{{ dateTime(row.escalated_at) }}</time
              >
            </td>
            <td class="max-w-56 px-5 py-4 leading-5 text-n-slate-12">
              {{
                row.reasons.map(r => $t(`OCA_REPORT.REASONS.${r}`)).join(', ')
              }}
            </td>
            <td class="max-w-44 px-5 py-4 leading-5 text-n-slate-12">
              {{ $t(`OCA_REPORT.DESTINATIONS.${row.destination}`) }}
            </td>
            <td class="max-w-64 px-5 py-4">
              <div class="flex flex-wrap gap-1.5">
                <span
                  v-for="category in row.categories"
                  :key="category"
                  class="rounded-md bg-n-alpha-black2 px-2 py-1 text-xs text-n-slate-12"
                  >{{ category }}</span
                ><span v-if="!row.categories.length" class="text-n-slate-11">{{
                  $t('OCA_REPORT.UNCLASSIFIED')
                }}</span>
              </div>
            </td>
            <td class="px-5 py-4">
              <span
                class="inline-flex whitespace-nowrap rounded-md px-2 py-1 text-xs font-medium"
                :class="
                  row.all_solved
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-alpha-black2 text-n-slate-11'
                "
                >{{
                  $t(
                    row.all_solved
                      ? 'OCA_REPORT.SOLVED_STATUS'
                      : 'OCA_REPORT.UNRESOLVED_STATUS'
                  )
                }}</span
              >
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <footer
      v-if="report.detail_total && !loading"
      class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-5 py-3 text-sm text-n-slate-11"
    >
      <span class="tabular-nums">{{ $t('OCA_REPORT.ROWS', range) }}</span>
      <div class="flex gap-2">
        <Button
          size="sm"
          variant="ghost"
          color="slate"
          :disabled="page <= 1"
          :label="$t('OCA_REPORT.PREVIOUS')"
          @click="emit('page', page - 1)"
        /><Button
          size="sm"
          variant="ghost"
          color="slate"
          :disabled="page * 25 >= report.detail_total"
          :label="$t('OCA_REPORT.NEXT')"
          @click="emit('page', page + 1)"
        />
      </div>
    </footer>
  </section>
</template>
