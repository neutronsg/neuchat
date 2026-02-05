# NeuChat Knowledge Base 设计文档

## 概述

为 NeuChat 添加 Knowledge Base 功能，允许用户管理知识库内容（Documents、Q&A），底层与 NeuAI (Dify) 集成。

### 核心设计决策

| 项目 | 决定 |
|-----|------|
| KB 创建/删除 | SuperAdmin 在后台 (`/super_admin`) 管理 |
| 内容管理 | Account Administrator 在前端管理 |
| Q&A 同步 | 前端提醒 + 一键同步按钮 |
| Web URLs | MVP 不实现 |
| 多租户隔离 | 命名规范 `account_{account_id}_{kb_name}` + Tag |
| Documents | 文件上传，开放列表/上传/删除/启用禁用/索引状态 |
| KB 数量 | 一个 Account 可有多个 KB |
| 文件格式 | 全部开放，由 NeuAI 决定 |
| 文件存储 | 不保存副本，直接传到 NeuAI |
| Documents 表 | 精简版（只存 neuai_document_id + name + timestamps） |
| 索引状态更新 | 懒加载 + 前端轮询（有 processing 状态时） |

---

## 数据模型

### kbase_knowledge_bases

```ruby
create_table :kbase_knowledge_bases do |t|
  t.references :account, null: false, foreign_key: true
  t.string :name, null: false
  t.string :neuai_dataset_id       # NeuAI Dataset ID
  t.string :qa_document_id         # Q&A 合并后的 NeuAI Document ID
  t.text :description
  t.integer :status, default: 0    # 0: disabled, 1: enabled
  t.timestamps
end

add_index :kbase_knowledge_bases, [:account_id, :name], unique: true
```

### kbase_documents（精简版）

```ruby
create_table :kbase_documents do |t|
  t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
  t.string :neuai_document_id, null: false
  t.string :name
  t.timestamps
end
```

### kbase_qa_pairs

```ruby
create_table :kbase_qa_pairs do |t|
  t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
  t.text :question, null: false
  t.text :answer, null: false
  t.integer :position, default: 0
  t.timestamps
end
```

---

## 后端架构

### 目录结构

```
app/models/kbase/
  ├── knowledge_base.rb
  ├── document.rb
  └── qa_pair.rb

app/controllers/api/v1/accounts/
  └── knowledge_bases_controller.rb
  └── knowledge_bases/
      ├── documents_controller.rb
      └── qa_pairs_controller.rb

app/services/kbase/
  ├── neuai_client.rb
  ├── document_sync_service.rb
  └── qa_sync_service.rb

app/controllers/super_admin/
  └── knowledge_bases_controller.rb
```

### API 端点

**普通用户 API（Account Administrator）：**

```
GET    /api/v1/accounts/:account_id/knowledge_bases
GET    /api/v1/accounts/:account_id/knowledge_bases/:id

# Documents
GET    /api/v1/accounts/:account_id/knowledge_bases/:kb_id/documents
POST   /api/v1/accounts/:account_id/knowledge_bases/:kb_id/documents
PATCH  /api/v1/accounts/:account_id/knowledge_bases/:kb_id/documents/:id
DELETE /api/v1/accounts/:account_id/knowledge_bases/:kb_id/documents/:id

# Q&A Pairs
GET    /api/v1/accounts/:account_id/knowledge_bases/:kb_id/qa_pairs
POST   /api/v1/accounts/:account_id/knowledge_bases/:kb_id/qa_pairs
PATCH  /api/v1/accounts/:account_id/knowledge_bases/:kb_id/qa_pairs/:id
DELETE /api/v1/accounts/:account_id/knowledge_bases/:kb_id/qa_pairs/:id
POST   /api/v1/accounts/:account_id/knowledge_bases/:kb_id/qa_pairs/sync
```

**SuperAdmin 后台：**

```
/super_admin/accounts/:account_id/knowledge_bases
```

---

## NeuAI 集成

### 配置架构

Dify 有两类独立的 API：
1. **Dataset API** — 用于管理知识库、文档（需要独立的 Dataset API Key）
2. **Chat/Workflow API** — 用于对话和工作流（应用级别的 API Key）

Knowledge Base 功能使用的是 **Dataset API**，这是系统级别的配置，与 Account 级别的 NeuAI Chat 集成是独立的。

### 配置来源

使用环境变量配置 Dataset API（系统级别）：

```bash
# .env
NEUAI_DATASET_URL=https://your-dify-instance.com
NEUAI_DATASET_API_KEY=dataset-xxxxxxxxxxxxxxxx
```

| 配置项 | 说明 | 层级 |
|-------|------|------|
| `NEUAI_DATASET_URL` | Dify Dataset API Base URL | 系统级 |
| `NEUAI_DATASET_API_KEY` | Dify Dataset API Key | 系统级 |
| NeuAI 集成 (Hook) | Chat/Workflow API 配置 | Account 级 |

### NeuAI Client

```ruby
module Kbase
  class NeuaiClient
    def initialize
      @base_url = ENV.fetch('NEUAI_DATASET_URL', nil)&.chomp('/')
      @api_key = ENV.fetch('NEUAI_DATASET_API_KEY', nil)

      raise ConfigurationError, 'NEUAI_DATASET_URL not configured' if @base_url.blank?
      raise ConfigurationError, 'NEUAI_DATASET_API_KEY not configured' if @api_key.blank?
    end

    # Dataset
    def create_dataset(name:, description: nil)
    def delete_dataset(dataset_id)

    # Document
    def list_documents(dataset_id)
    def create_document_by_file(dataset_id, file, name:)
    def create_document_by_text(dataset_id, name:, text:)
    def update_document_by_text(dataset_id, document_id, name:, text:)
    def delete_document(dataset_id, document_id)
    def update_document_status(dataset_id, document_ids, action:)
  end
end
```

### Q&A 同步服务

```ruby
module Kbase
  class QaSyncService
    def initialize(knowledge_base)
      @kb = knowledge_base
      @client = Kbase::NeuaiClient.new  # 不再需要 account 参数
    end

    def sync!
      text = build_qa_text

      if @kb.qa_document_id.present?
        @client.update_document_by_text(...)
      else
        response = @client.create_document_by_text(...)
        @kb.update!(qa_document_id: response['document']['id'])
      end
    end

    private

    def build_qa_text
      @kb.qa_pairs.order(:position).map do |qa|
        "Question: #{qa.question}\nAnswer: #{qa.answer}"
      end.join("\n------\n")
    end
  end
end
```

### 多租户隔离

由于 Dataset API Key 是系统级别共享的，多租户隔离通过以下方式实现：
- **命名规范**：Dataset 名称格式 `account_{account_id}_{kb_name}`
- **Tag 标记**：为 Dataset 添加 Tag `account:{account_id}`
- **数据库关联**：`kbase_knowledge_bases.account_id` 确保查询隔离

**前置条件：**
- 系统管理员需要在 `.env` 中配置 `NEUAI_DATASET_URL` 和 `NEUAI_DATASET_API_KEY`
- 前端可检查配置是否存在（通过 API），未配置时显示提示

---

## 前端架构

### 路由

```javascript
{
  path: frontendURL('accounts/:accountId/knowledge-bases'),
  component: KnowledgeBaseWrapper,
  children: [
    { path: '', name: 'knowledge_bases_index', component: Index },
    { path: ':knowledgeBaseId', name: 'knowledge_base_show', component: Show },
    { path: ':knowledgeBaseId/documents', name: 'knowledge_base_documents', component: Documents },
    { path: ':knowledgeBaseId/qa', name: 'knowledge_base_qa', component: QAPairs }
  ],
  meta: { permissions: ['administrator'] }
}
```

### 侧边栏

```javascript
{
  name: 'Knowledge Base',
  label: t('SIDEBAR.KNOWLEDGE_BASE'),
  icon: 'i-lucide-library-big',
  children: [
    {
      name: 'Knowledge Bases',
      label: t('SIDEBAR.KNOWLEDGE_BASES'),
      to: accountScopedRoute('knowledge_bases_index')
    }
  ]
}
```

### 组件结构

```
views/knowledge_base/
├── Index.vue
├── Show.vue
├── components/
│   ├── KnowledgeBaseCard.vue
│   ├── DocumentList.vue
│   ├── DocumentUploader.vue
│   ├── QAPairList.vue
│   ├── QAPairEditor.vue
│   └── SyncStatusBanner.vue
```

### Store

```javascript
state: {
  records: [],
  currentKB: null,
  documents: [],
  qaPairs: [],
  qaSyncRequired: false,
  uiFlags: { ... }
}
```

### 关键交互

**Documents 页面：**
1. 进入页面 → 调 API 获取文档列表（后端刷新 NeuAI 状态）
2. 有 `waiting/indexing` 状态 → 启动前端轮询（每 5-10 秒）
3. 所有文档 `completed/error` → 停止轮询

**Q&A 页面：**
1. 增删改 Q&A → 本地更新 + 标记 `qaSyncRequired: true`
2. 显示提示条："有未同步的更改" + [同步到 NeuAI] 按钮
3. 点击同步 → 合并 Q&A → 更新 NeuAI Document

---

## SuperAdmin 后台

### 路由

```ruby
namespace :super_admin do
  resources :accounts do
    resources :knowledge_bases
  end
end
```

### 创建 KB 表单

两种模式：
1. **新建模式**：输入名称，勾选"同时在 NeuAI 创建 Dataset"
2. **绑定模式**：输入名称 + 已存在的 `neuai_dataset_id`

创建时自动：
- 命名规范：`account_{account_id}_{kb_name}`
- 添加 Tag：`account:{account_id}`

---

## 权限模型

| 操作 | SuperAdmin | Account Administrator | Agent |
|------|------------|----------------------|-------|
| 创建/删除 KB | ✅ | ❌ | ❌ |
| 绑定/解绑 NeuAI Dataset | ✅ | ❌ | ❌ |
| 管理 Documents | ✅ | ✅ | ❌ |
| 管理 Q&A | ✅ | ✅ | ❌ |

---

## 实现步骤

### Phase 1: 基础架构

1. 数据库迁移（3 张表）
2. Model 层（Kbase::KnowledgeBase, Document, QaPair）
3. NeuAI Client（HTTP 封装 + API 方法）

### Phase 2: SuperAdmin 后台

4. Administrate Dashboard 配置
5. Controller 实现（新建/绑定模式）
6. 路由配置

### Phase 3: 普通用户 API

7. Controllers（KB、Documents、QaPairs）
8. Services（DocumentSyncService、QaSyncService）

### Phase 4: 前端

9. 路由 + Vuex Store
10. 页面组件（列表、详情、文档、Q&A）
11. 侧边栏菜单 + i18n

### 依赖关系

```
Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4
                            │
                            └──► 可并行开发前端
```

---

## 待定事项

- **Web URLs**：MVP 不实现，后续迭代
- **文件预览**：如需要可调 NeuAI API 获取分段内容
