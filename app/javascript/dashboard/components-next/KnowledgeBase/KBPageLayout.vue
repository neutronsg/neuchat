<script setup>
import BackButton from 'dashboard/components/widgets/BackButton.vue';

defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  backButtonUrl: { type: [String, Object], default: '' },
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header class="sticky top-0 z-10 px-6 pb-3">
      <div class="w-full max-w-6xl mx-auto">
        <div class="flex items-start justify-between gap-4 pt-4 pb-2">
          <div>
            <div class="flex items-center gap-2">
              <BackButton
                v-if="backButtonUrl"
                :back-url="backButtonUrl"
                class="!p-0 !text-n-slate-11 hover:!text-n-slate-12"
              />
              <h1 class="text-xl font-semibold text-n-slate-12">{{ title }}</h1>
            </div>
            <p v-if="description" class="mt-1 text-sm text-n-slate-11">
              {{ description }}
            </p>
          </div>
          <slot name="header-actions" />
        </div>
      </div>
    </header>
    <main class="flex-1 overflow-y-auto px-6">
      <div class="w-full max-w-6xl mx-auto pb-10 mt-2">
        <slot />
      </div>
    </main>
  </section>
</template>
