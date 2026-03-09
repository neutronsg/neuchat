# Knowledge Base Document Chunk Settings 设计

## 目标

为当前 Knowledge Base 的 `Documents` 增加与 Dify 类似的 `chunk settings` 表单能力，但范围只限于当前 NeuChat 需要的两个场景：

- 上传新 document 前配置 chunk settings
- 编辑已上传 document 的 chunk settings

这次设计关注的是：

- 新建 document 时配置 chunk settings
- 已上传 document 的 chunk settings 查看与修改
- 修改后重新触发 Dify/NeuAI re-index
- 与当前 `Knowledge Base -> Documents` 列表页集成
- 复刻 Dify 的 chunk settings 表单布局和字段组织

这次**不**包含：

- dataset 级默认 chunk settings 管理
- Q&A document 的 chunk settings 管理
- parent-child / hierarchical chunking
- automatic mode
- retrieval model / indexing technique 编辑
- preview chunks
- estimate token / estimate cost
- retrieval model / rerank / embedding 等高级配置

---

## 现状

### 当前后端

当前 document 管理链路主要在：

- `app/controllers/api/v1/accounts/knowledge_bases/documents_controller.rb`
- `app/services/kbase/neuai_client.rb`
- `app/models/kbase/document.rb`

现状特点：

- 本地 `kbase_documents` 只存 `neuai_document_id`、`name` 和审计字段
- document 创建时，`Kbase::NeuaiClient#create_document_by_file` 会固定写入一套硬编码的 `process_rule`
- 当前默认值是：
  - `mode: custom`
  - `separator: "\n\n"`
  - `max_tokens: 1024`
  - `chunk_overlap: 50`
  - `pre_processing_rules: []`
- document 列表接口只返回状态、启停、字数、审计信息，不返回 processing rule

### 当前前端

当前 document UI 在：

- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentList.vue`
- `app/javascript/dashboard/store/modules/knowledgeBases.js`
- `app/javascript/dashboard/api/knowledgeBases.js`

现状特点：

- 只有文件上传、启用/禁用、删除
- 没有 document 详情页
- 没有 document 级配置面板
- 上传时不能自定义 chunk settings

---

## Dify 参考结论

### 1. Dify 的 document 详情会同时返回 dataset 和 document 两层 process rule

`refs/dify/api/controllers/service_api/dataset/document.py` 的 document detail 返回：

- `dataset_process_rule`
- `document_process_rule`

这意味着：

- document 没有自定义时，可以回落到 dataset 默认规则
- document 一旦做过自定义，`document_process_rule` 才是该 document 的真实生效值

### 2. Dify 可以在不重新上传文件的前提下更新 document 的 process_rule

`refs/dify/api/controllers/service_api/dataset/document.py` 的 `update-by-file` 路由支持：

- 传 `data`
- 不强制要求同时上传 `file`
- 设置 `original_document_id`
- 通过 `process_rule` 重新生成 document

这点很关键。对于 NeuChat 来说，意味着我们可以只改 chunk settings，而不要求用户重新上传原文件。

### 3. Dify 的 chunk settings 表单核心就是 `process_rule`

本期真正相关的字段只有：

```json
{
  "mode": "custom",
  "rules": {
    "pre_processing_rules": [
      { "id": "remove_extra_spaces", "enabled": true },
      { "id": "remove_urls_emails", "enabled": false }
    ],
    "segmentation": {
      "separator": "\n\n",
      "max_tokens": 1024,
      "chunk_overlap": 50
    }
  }
}
```

---

## 设计原则

### 1. Dify 是 chunk settings 的 source of truth

本期**不在本地数据库冗余保存 chunk settings**。

原因：

- 当前 `kbase_documents` 设计本来就是轻量镜像
- Dify 已经保存 document 级 process rule
- 若本地再存一份，容易出现本地和 Dify 配置不一致
- 当前 UI 没有 document detail 页，按需读取更符合 MVP

结论：

- 编辑已上传 document 时，再实时请求 Dify document detail
- 保存成功后，仍以 Dify 返回状态为准

### 2. 只支持当前 text chunking 场景

NeuChat 当前 document 上传逻辑固定使用：

- `indexing_technique: high_quality`
- `process_rule.mode: custom`
- 普通 `segmentation`

所以本期只支持：

- `mode = custom`
- `segmentation.separator`
- `segmentation.max_tokens`
- `segmentation.chunk_overlap`
- `pre_processing_rules`

不支持：

- `mode = hierarchical`
- `rules.parent_mode`
- `rules.subchunk_segmentation`
- `doc_form` 切换
- `doc_language`
- `summary_index_setting`

### 3. 分离“状态开关”和“chunk settings 更新”

当前 `PATCH /documents/:id` 只负责 enable/disable。chunk settings 更新会触发重新索引，语义完全不同。

因此不建议把两种能力揉在一个接口里。

### 4. 创建和编辑共用同一套 chunk settings 表单

用户想要的是复刻 Dify 这块表单本身，而不是拆成两套体验。

结论：

- 新建上传 document 时，使用同一套 chunk settings 表单
- 编辑已上传 document 时，复用同一套表单组件
- `Reset` 保留
- `Preview Chunks` 本期不做

---

## 方案概览

### 用户体验

`Documents` tab 里会有两条入口：

#### 1. 上传新 document

1. 用户点击 `Upload Document`
2. 打开上传 dialog
3. 选择文件
4. 在同一个 dialog 中填写 chunk settings
5. 点击上传
6. 后端调用 Dify `create-by-file`，携带 `process_rule`
7. document 进入 processing/indexing

#### 2. 编辑已上传 document

在每个 document 行上新增一个 `Chunk settings` 操作：

1. 用户点击 `Chunk settings`
2. 打开右侧 drawer 或 dialog
3. 前端请求 document 当前 chunk settings
4. 用户修改后点击保存
5. 后端调用 Dify `update-by-file`，仅提交 `name + process_rule`
6. Dify 重新进入 processing/indexing
7. 前端关闭弹窗并刷新 document 列表

### 建议交互

建议统一采用 dialog，而不是整页跳转。

原因：

- 当前 KB 页面就是 tab + 列表结构
- 没有 document detail 路由
- chunk settings 是次级操作，不值得引入新页面
- 上传和编辑都可复用同一个表单主体

---

## 支持的设置项

### MVP 支持

#### 1. Separator

- 字段：`rules.segmentation.separator`
- 默认值：`\n\n`
- 表单类型：文本输入

#### 2. Max tokens

- 字段：`rules.segmentation.max_tokens`
- 默认值：`1024`
- 表单类型：数字输入
- 校验：正整数

#### 3. Chunk overlap

- 字段：`rules.segmentation.chunk_overlap`
- 默认值：`50`
- 表单类型：数字输入
- 校验：非负整数，且不大于 `max_tokens`

#### 4. Text cleaning rules

- 字段：`rules.pre_processing_rules`
- 本期支持的 rule id：
  - `remove_extra_spaces`
  - `remove_urls_emails`
- 表单类型：checkbox group

### 表单形态

本期直接复刻 Dify 这块 chunk settings 表单的核心布局：

- 标题：`Chunk Settings`
- 右上角：`Reset`
- 表单区：
  - `Delimiter`
  - `Maximum Chunk Length`
  - `Chunk Overlap Length`
  - `Replace consecutive spaces, newlines and tabs`
  - `Delete all URLs and email addresses`

说明：

- 视觉和字段顺序尽量贴近 Dify
- 不包含 `Preview Chunks`
- 不包含分段模式切换

### 本期不支持但保留兼容

如果 Dify 返回了本期不支持的结构：

- `mode != custom`
- 存在 `subchunk_segmentation`
- 存在 `parent_mode`

则前端不允许编辑，并给出只读提示：

- `This document uses an unsupported chunking mode in NeuChat.`

这样可以避免错误覆盖 Dify 中更复杂的 document 配置。

---

## 后端设计

## 路由

在 `config/routes.rb` 的 knowledge base documents 下新增 member routes：

```ruby
resources :documents, only: [:index, :create, :update, :destroy], controller: 'knowledge_bases/documents' do
  member do
    get :chunk_settings
    patch :chunk_settings
  end
end
```

保留现有：

- `PATCH /documents/:id` 只处理启用/禁用

新增：

- `GET /documents/:id/chunk_settings`
- `PATCH /documents/:id/chunk_settings`

调整现有：

- `POST /documents` 支持上传时携带 chunk settings

## Controller 设计

文件：

- `app/controllers/api/v1/accounts/knowledge_bases/documents_controller.rb`

新增两个 action。

### `GET chunk_settings`

职责：

- 调用 `Kbase::NeuaiClient#get_document`
- 读取 `document_process_rule`，若为空则 fallback 到 `dataset_process_rule`
- 将 Dify 结构归一化为 NeuChat 前端可直接消费的 payload

返回示例：

```json
{
  "chunk_settings": {
    "source": "document",
    "mode": "custom",
    "separator": "\n\n",
    "max_tokens": 1024,
    "chunk_overlap": 50,
    "pre_processing_rules": {
      "remove_extra_spaces": false,
      "remove_urls_emails": false
    },
    "editable": true
  }
}
```

如果 document 当前模式不是本期支持的 `custom`：

```json
{
  "chunk_settings": {
    "source": "document",
    "mode": "hierarchical",
    "editable": false,
    "reason": "unsupported_mode"
  }
}
```

### `PATCH chunk_settings`

职责：

- 校验入参
- 检查当前 document 是否正在 processing
- 将前端 payload 转成 Dify `process_rule`
- 调用 `Kbase::NeuaiClient#update_document_by_file`
- 不上传 file，只传 `data`
- 更新本地 `updated_by_id`

### `POST create`

当前 `POST /documents` 只上传 `file + name`。需要扩展为：

- `file`
- `name`
- `chunk_settings` 或直接传 `process_rule`

推荐保持前端请求语义统一，controller 接收：

```json
{
  "chunk_settings": {
    "separator": "\n\n",
    "max_tokens": 1024,
    "chunk_overlap": 128,
    "pre_processing_rules": {
      "remove_extra_spaces": true,
      "remove_urls_emails": false
    }
  }
}
```

controller 内部再转换为 Dify `process_rule`，然后调用：

- `Kbase::NeuaiClient#create_document_by_file`

请求示例：

```json
{
  "chunk_settings": {
    "separator": "\n\n",
    "max_tokens": 1200,
    "chunk_overlap": 100,
    "pre_processing_rules": {
      "remove_extra_spaces": true,
      "remove_urls_emails": true
    }
  }
}
```

保存成功返回：

```json
{
  "success": true,
  "indexing_status": "waiting"
}
```

### 状态限制

建议仅允许以下状态修改 chunk settings：

- `completed`
- `error`
- `paused`
- `disabled`

以下状态禁止修改：

- `waiting`
- `parsing`
- `cleaning`
- `splitting`
- `indexing`

原因：

- 避免并发 re-index
- 避免用户误以为保存立即生效，但旧任务仍在跑

## Service / Value Object 设计

建议新增一个轻量对象，统一做 Dify process rule 的解析和生成：

- `app/services/kbase/document_chunk_settings.rb`

职责：

- 从 `document_process_rule` / `dataset_process_rule` 提取前端可用结构
- 生成 Dify `process_rule`
- 做支持模式判断
- 提供默认值
- 生成创建表单的默认值

建议接口：

```ruby
class Kbase::DocumentChunkSettings
  DEFAULT_SEPARATOR = "\n\n"
  DEFAULT_MAX_TOKENS = 1024
  DEFAULT_CHUNK_OVERLAP = 50
  SUPPORTED_RULE_IDS = %w[
    remove_extra_spaces
    remove_urls_emails
  ].freeze

  def self.from_dify(document_process_rule:, dataset_process_rule:)
  end

  def initialize(separator:, max_tokens:, chunk_overlap:, pre_processing_rules:)
  end

  def to_process_rule
  end

  def editable?
  end
end
```

这个对象的价值在于把 controller 从 Dify 结构细节中解耦出来，后面如果要支持 hierarchical，也只需要扩展这里。

## NeuaiClient 改造

文件：

- `app/services/kbase/neuai_client.rb`

### 保留现有能力

- `list_documents`
- `get_document`
- `create_document_by_file`
- `update_document_by_file`

### 需要改造的点

当前 `create_document_by_file` / `update_document_by_file` 内部直接硬编码 `process_rule`。应改为：

- 支持显式传入 `process_rule`
- 未传时回落到默认 `custom` 规则

建议签名：

```ruby
def create_document_by_file(dataset_id, file, name:, process_rule: nil, upload_filename: nil)
end

def update_document_by_file(dataset_id, document_id, file = nil, name:, process_rule: nil)
end
```

`update_document_by_file` 的关键点：

- `file` 允许为 `nil`
- `data` 始终写入 `name` 和 `process_rule`
- 有 `file` 时附带上传
- 没有 `file` 时只更新配置

这样不只服务 chunk settings，本身也让 `NeuaiClient` 更接近 Dify service API 的真实能力。

---

## 前端设计

## API 层

文件：

- `app/javascript/dashboard/api/knowledgeBases.js`

新增：

```javascript
getDocumentChunkSettings(knowledgeBaseId, documentId)
updateDocumentChunkSettings(knowledgeBaseId, documentId, data)
```

调整：

```javascript
createDocument(knowledgeBaseId, file, name, chunkSettings)
```

## Store 层

文件：

- `app/javascript/dashboard/store/modules/knowledgeBases.js`

新增 state：

```javascript
documentChunkSettings: null,
documentChunkSettingsUI: {
  isFetching: false,
  isSaving: false,
}
```

新增 actions：

- `fetchDocumentChunkSettings`
- `updateDocumentChunkSettings`

新增 mutations：

- `setDocumentChunkSettings`
- `setDocumentChunkSettingsUI`
- `resetDocumentChunkSettings`

说明：

- chunk settings 是单 document 的临时编辑态，不需要并入 document 列表 records
- 打开弹窗时加载，关闭弹窗时清空
- 上传 dialog 内部的 chunk settings 建议作为组件本地 state，不放 Vuex

## 组件设计

建议新增组件：

- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentChunkSettingsDialog.vue`
- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentUploadDialog.vue`
- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/ChunkSettingsForm.vue`

`DocumentList.vue` 中新增：

- 上传按钮改为打开 `DocumentUploadDialog`
- 每个 document 一项 `Chunk settings` 按钮
- 上传和编辑都复用 `ChunkSettingsForm`

### 上传弹窗内容

表单项：

- 文件选择
- 文档名称
- Chunk settings 表单

页脚按钮：

- `Cancel`
- `Upload`

### 编辑弹窗内容

表单项：

- `Separator`
- `Max tokens`
- `Chunk overlap`
- `Text cleaning`
  - Remove extra spaces
  - Remove URLs and emails

页脚按钮：

- `Cancel`
- `Save`

右上角：

- `Reset`

### 交互细节

#### 1. 上传默认值

- 新建上传时默认加载系统默认 chunk settings
- 点击 `Reset` 恢复到默认值：
  - `separator: "\n\n"`
  - `max_tokens: 1024`
  - `chunk_overlap: 50`
  - `remove_extra_spaces: false`
  - `remove_urls_emails: false`

#### 2. 编辑时懒加载

- 点击按钮后请求 `GET chunk_settings`
- 加载中展示 skeleton / loading 文案

#### 3. unsupported 模式只读

若 `editable = false`：

- 展示当前 mode
- 显示提示
- 不渲染保存按钮

#### 4. 保存后自动刷新 document 列表

因为更新 chunk settings 会触发重新索引，所以保存成功后要：

- 关闭弹窗
- 重新拉取 documents
- 让现有轮询逻辑自动接管 processing 状态

#### 5. processing 中禁用编辑入口

若 document 当前 `display_status = processing`：

- 按钮置灰
- tooltip 提示 “Document is processing”

这样可以和后端状态限制保持一致。

---

## 入参与返回结构

## 创建时前端请求结构

上传使用 `multipart/form-data`：

- `file`
- `name`
- `chunk_settings` JSON string

示例：

```json
{
  "chunk_settings": {
    "separator": "\n\n",
    "max_tokens": 1024,
    "chunk_overlap": 128,
    "pre_processing_rules": {
      "remove_extra_spaces": true,
      "remove_urls_emails": false
    }
  }
}
```

## 编辑时前端请求结构

```json
{
  "chunk_settings": {
    "separator": "\n\n",
    "max_tokens": 1024,
    "chunk_overlap": 50,
    "pre_processing_rules": {
      "remove_extra_spaces": true,
      "remove_urls_emails": false
    }
  }
}
```

## 后端转 Dify 结构

```json
{
  "name": "Original File Name.pdf",
  "process_rule": {
    "mode": "custom",
    "rules": {
      "pre_processing_rules": [
        { "id": "remove_extra_spaces", "enabled": true },
        { "id": "remove_urls_emails", "enabled": false }
      ],
      "segmentation": {
        "separator": "\n\n",
        "max_tokens": 1024,
        "chunk_overlap": 50
      }
    }
  }
}
```

---

## 校验规则

后端做最终兜底校验：

- `separator` 必填，字符串
- `max_tokens` 必填，整数，`> 0`
- `chunk_overlap` 必填，整数，`>= 0`
- `chunk_overlap <= max_tokens`
- `pre_processing_rules` 只允许 2 个受支持 key

前端同步校验：

- 空值校验
- 数字范围校验
- `chunk_overlap > max_tokens` 时禁止提交

上传时额外校验：

- 必须先选择文件
- chunk settings 校验通过后才允许提交

---

## 为什么不改数据库

本期不建议给 `kbase_documents` 新增 JSON 字段保存 chunk settings，原因如下：

### 1. 没有必要引入第二份真相

实际执行索引的是 Dify，最终生效规则也在 Dify。

### 2. 当前 UI 是按需编辑，不需要列表批量展示复杂配置

只在打开设置时请求 detail 即可。

### 3. 减少同步问题

如果未来有人直接在 Dify 后台改了 document setting，本地 JSON 会立刻过期。

只有在未来出现以下需求时，再考虑本地冗余：

- 列表页需要直接显示 chunk settings 摘要
- 审计日志需要展示历史配置 diff
- 批量更新/批量回滚配置

---

## 与现有 Q&A 的关系

Q&A 当前通过 `Kbase::QaSyncService` 合成单个 text document，并调用 `update_document_by_text`。

本期**不把 chunk settings 能力扩展到 Q&A**，原因：

- Q&A document 不是用户直接上传的文件
- 它的 separator 其实承载了 Q&A 合并协议
- 如果开放给用户改 separator，可能直接破坏 Q&A 的切分结果

结论：

- chunk settings 仅对 `Documents` 生效
- `qa_document_id` 对应文档继续使用系统内部固定规则

---

## 实现步骤建议

### Phase 1

- 提取默认 process rule 常量
- 改造 `Kbase::NeuaiClient#update_document_by_file` 支持无文件更新
- 改造 `Kbase::NeuaiClient#create_document_by_file` 支持外部传入 `process_rule`
- 新增 `Kbase::DocumentChunkSettings`

### Phase 2

- 新增 `GET/PATCH chunk_settings` 接口
- 扩展 `POST /documents` 支持上传时自定义 chunk settings
- 补 controller request spec

### Phase 3

- 前端新增上传 dialog 和编辑 dialog
- 抽取共享 `ChunkSettingsForm`
- 接入 documents 列表
- 复用现有轮询逻辑处理 re-index 状态

---

## 最小改动文件清单

后端：

- `config/routes.rb`
- `app/controllers/api/v1/accounts/knowledge_bases/documents_controller.rb`
- `app/services/kbase/neuai_client.rb`
- `app/services/kbase/document_chunk_settings.rb`
- `spec/controllers/api/v1/accounts/knowledge_bases/documents_controller_spec.rb`

前端：

- `app/javascript/dashboard/api/knowledgeBases.js`
- `app/javascript/dashboard/store/modules/knowledgeBases.js`
- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentList.vue`
- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentUploadDialog.vue`
- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentChunkSettingsDialog.vue`
- `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/ChunkSettingsForm.vue`
- `app/javascript/dashboard/i18n/locale/en/knowledgeBase.json`

---

## 风险与边界

### 1. Dify document 当前若是非 custom 模式

处理方式：

- 只读展示
- 本期不覆盖

### 2. 更新 settings 后 document id 是否变化

按 Dify `update-by-file` 语义，更新的是原 document，NeuChat 继续使用原 `neuai_document_id`。实现时仍应以实际 API 返回验证一次。

### 3. Dify detail 返回结构与 service API 部分版本差异

处理方式：

- `Kbase::DocumentChunkSettings.from_dify` 做容错
- `document_process_rule` 为空时 fallback `dataset_process_rule`

### 4. 用户在 processing 中重复提交

处理方式：

- 前后端双重限制
- 保存按钮 loading 态

---

## 结论

这次新增 `document chunk settings` 最合理的做法是：

- 不改数据库
- 以 Dify document detail 返回的 process rule 为准
- 在现有 `Documents` 列表上增加两个入口：
  - 上传前配置 chunk settings
  - 已上传后编辑 chunk settings
- 前端表单形态尽量复刻 Dify 的 chunk settings 区块
- 仅支持 `custom` 模式下的 `separator / max_tokens / chunk_overlap / pre_processing_rules`
- 创建时调用 Dify `create-by-file` 并携带 `process_rule`
- 编辑时调用 Dify `update-by-file`，不重新上传文件，只更新 `process_rule`

这是和当前 NeuChat KB 架构最一致、改动最小、后续也最好继续扩展到更复杂 chunking 模式的方案。
