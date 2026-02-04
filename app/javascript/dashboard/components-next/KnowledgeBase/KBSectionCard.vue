<script setup>
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
});
</script>

<template>
  <div class="rounded-2xl border border-n-weak bg-n-solid-2 shadow">
    <div
      class="flex items-start justify-between gap-4 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">{{ title }}</h2>
        <p v-if="description" class="mt-1 text-sm text-n-slate-11">
          {{ description }}
        </p>
      </div>
      <slot name="actions" />
    </div>
    <div class="p-6">
      <slot />
    </div>
  </div>
</template>
