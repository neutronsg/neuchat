<script>
import { mapGetters } from 'vuex';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  emits: ['assignTeam', 'close'],

  data() {
    return {
      query: '',
      selectedteams: [],
    };
  },
  computed: {
    ...mapGetters({ teams: 'teams/getTeams' }),
    filteredTeams() {
      return [
        { name: 'None', id: 0 },
        ...this.teams.filter(team =>
          team.name.toLowerCase().includes(this.query.toLowerCase())
        ),
      ];
    },
  },
  methods: {
    assignTeam(key) {
      this.$emit('assignTeam', key);
    },
    onClose() {
      this.$emit('close');
    },
  },
};
</script>

<template>
  <div v-on-clickaway="onClose" class="bulk-action__teams">
    <div class="triangle">
      <svg height="12" viewBox="0 0 24 12" width="24">
        <path d="M20 12l-8-8-12 12" fill-rule="evenodd" stroke-width="1px" />
      </svg>
    </div>
    <div class="flex items-center justify-between header">
      <span>{{ $t('BULK_ACTION.TEAMS.TEAM_SELECT_LABEL') }}</span>
      <NextButton ghost xs slate icon="i-lucide-x" @click="onClose" />
    </div>
    <div class="container">
      <div class="team__list-container">
        <ul>
          <li class="search-container">
            <div
              class="flex items-center justify-between h-8 gap-2 agent-list-search"
            >
              <fluent-icon icon="search" class="search-icon" size="16" />
              <input
                v-model="query"
                type="search"
                :placeholder="$t('BULK_ACTION.SEARCH_INPUT_PLACEHOLDER')"
                class="reset-base !outline-0 !text-sm agent--search_input"
              />
            </div>
          </li>
          <template v-if="filteredTeams.length">
            <li v-for="team in filteredTeams" :key="team.id">
              <div class="team__list-item" @click="assignTeam(team)">
                <span class="my-0 ltr:ml-2 rtl:mr-2 text-n-slate-12">
                  {{ team.name }}
                </span>
              </div>
            </li>
          </template>
          <li v-else>
            <div class="team__list-item">
              <span class="my-0 ltr:ml-2 rtl:mr-2 text-n-slate-12">
                {{ $t('BULK_ACTION.TEAMS.NO_TEAMS_AVAILABLE') }}
              </span>
            </div>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.bulk-action__teams {
  @apply max-w-[75%] absolute ltr:right-2 rtl:left-2 top-12 origin-top-right w-auto z-20 min-w-[15rem] bg-n-alpha-3 backdrop-blur-[100px] border-n-weak rounded-lg border border-solid shadow-md;
  .header {
    @apply p-2.5;

    span {
      @apply text-sm font-medium;
    }
  }

  .container {
    @apply overflow-y-auto max-h-[15rem];
    .team__list-container {
      @apply h-full;
    }
    .agent-list-search {
      @apply py-0 px-2.5 bg-n-alpha-black2 border border-solid border-n-strong rounded-md;
      .search-icon {
        @apply text-n-slate-10;
      }

      .agent--search_input {
        @apply border-0 text-xs m-0 dark:bg-transparent bg-transparent w-full h-[unset];
      }
    }
  }
  .triangle {
    @apply block z-10 absolute text-left -top-3 ltr:right-[--triangle-position] rtl:left-[--triangle-position];

    svg path {
      @apply fill-n-alpha-3 backdrop-blur-[100px]  stroke-n-weak;
    }
  }
}
ul {
  @apply m-0 list-none;

  li {
    &:last-child {
      .agent-list-item {
        @apply last:rounded-b-lg;
      }
    }
  }
}

.team__list-item {
  @apply flex items-center p-2.5 cursor-pointer hover:bg-n-slate-3 dark:hover:bg-n-solid-3;
  span {
    @apply text-sm;
  }
}

.search-container {
  @apply py-0 px-2.5 sticky top-0 z-20 bg-n-alpha-3 backdrop-blur-[100px];
}
</style>
