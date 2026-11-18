import { computed } from 'vue';
import { useAccount } from './useAccount';
export function useOcaReports() {
  const { currentAccount } = useAccount();
  return computed(() => currentAccount.value?.oca_bot_reports_enabled === true);
}
