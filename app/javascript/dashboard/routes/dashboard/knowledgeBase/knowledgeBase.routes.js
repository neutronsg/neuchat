import { frontendURL } from '../../../helper/URLHelper';

const KnowledgeBaseIndex = () => import('./Index.vue');
const KnowledgeBaseShow = () => import('./Show.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/knowledge-bases'),
    name: 'knowledge_bases_index',
    component: KnowledgeBaseIndex,
    meta: {
      permissions: ['administrator'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/knowledge-bases/:knowledgeBaseId'),
    name: 'knowledge_base_show',
    component: KnowledgeBaseShow,
    meta: {
      permissions: ['administrator'],
    },
  },
];
