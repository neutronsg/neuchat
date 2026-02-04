<script setup>
import { computed } from 'vue';

const props = defineProps({
  status: { type: String, required: true },
  label: { type: String, required: true },
});

const statusClasses = computed(() => {
  const map = {
    available: 'bg-n-teal-9/10 text-n-teal-11',
    indexing: 'bg-n-amber-9/10 text-n-amber-11',
    parsing: 'bg-n-amber-9/10 text-n-amber-11',
    waiting: 'bg-n-slate-9/10 text-n-slate-12',
    error: 'bg-n-ruby-9/10 text-n-ruby-11',
    unknown: 'bg-n-slate-9/10 text-n-slate-12',
  };

  return map[props.status] || map.unknown;
});
</script>

<template>
  <span
    class="inline-flex items-center px-2.5 py-1 text-xs font-medium rounded-full"
    :class="statusClasses"
  >
    {{ label }}
  </span>
</template>
