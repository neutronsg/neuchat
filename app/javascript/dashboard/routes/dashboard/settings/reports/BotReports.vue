<script>
import { useOcaReports } from 'dashboard/composables/useOcaReports';
import { useAlert, useTrack } from 'dashboard/composables';
import OcaReportDateFilter from './components/OcaReportDateFilter.vue';
import OcaBotReports from './components/OcaBotReports.vue';
import OcaReportDownload from './components/OcaReportDownload.vue';
import BotMetrics from './components/BotMetrics.vue';
import ReportFilterSelector from './components/FilterSelector.vue';
import { GROUP_BY_FILTER } from './constants';
import ReportContainer from './ReportContainer.vue';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import ReportHeader from './components/ReportHeader.vue';

export default {
  name: 'BotReports',
  components: {
    BotMetrics,
    OcaBotReports,
    OcaReportDownload,
    OcaReportDateFilter,
    ReportHeader,
    ReportFilterSelector,
    ReportContainer,
  },
  setup() {
    return { ocaEnabled: useOcaReports() };
  },
  data() {
    return {
      from: 0,
      to: 0,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      groupBy: GROUP_BY_FILTER[1],
      reportKeys: {
        BOT_RESOLUTION_COUNT: 'bot_resolutions_count',
        BOT_HANDOFF_COUNT: 'bot_handoffs_count',
      },
      businessHours: false,
    };
  },
  computed: {
    requestPayload() {
      return {
        from: this.from,
        to: this.to,
        timezone: this.timezone,
      };
    },
  },
  methods: {
    fetchAllData() {
      this.fetchBotSummary();
      this.fetchChartData();
    },
    fetchBotSummary() {
      try {
        this.$store.dispatch('fetchBotSummary', this.getRequestPayload());
      } catch {
        useAlert(this.$t('REPORT.SUMMARY_FETCHING_FAILED'));
      }
    },
    fetchChartData() {
      Object.keys(this.reportKeys).forEach(async key => {
        try {
          await this.$store.dispatch('fetchAccountReport', {
            metric: this.reportKeys[key],
            ...this.getRequestPayload(),
          });
        } catch {
          useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
        }
      });
    },
    getRequestPayload() {
      const { from, to, groupBy, businessHours } = this;

      return {
        from,
        to,
        groupBy: groupBy?.period,
        businessHours,
      };
    },
    onFilterChange({ from, to, timezone, groupBy, businessHours }) {
      this.from = from;
      this.to = to;
      if (timezone) this.timezone = timezone;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
      if (!this.ocaEnabled) this.fetchAllData();

      useTrack(REPORTS_EVENTS.FILTER_REPORT, {
        filterValue: { from, to, groupBy, businessHours },
        reportType: 'bots',
      });
    },
  },
};
</script>

<template>
  <ReportHeader :header-title="$t('BOT_REPORTS.HEADER')">
    <OcaReportDownload v-if="ocaEnabled" :filters="requestPayload" />
  </ReportHeader>
  <div class="flex flex-col gap-4">
    <OcaReportDateFilter v-if="ocaEnabled" @filter-change="onFilterChange" />
    <ReportFilterSelector
      v-else
      :show-agents-filter="false"
      :show-group-by-filter="!ocaEnabled"
      :show-business-hours-switch="false"
      @filter-change="onFilterChange"
    />

    <BotMetrics v-if="!ocaEnabled" :filters="requestPayload" />
    <OcaBotReports v-if="ocaEnabled" :filters="requestPayload" />
    <ReportContainer
      v-if="!ocaEnabled"
      account-summary-key="getBotSummary"
      summary-fetching-key="getBotSummaryFetchingStatus"
      :group-by="groupBy"
      :report-keys="reportKeys"
    />
  </div>
</template>
