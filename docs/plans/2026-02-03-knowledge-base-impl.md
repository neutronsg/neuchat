# Knowledge Base 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 NeuChat 添加 Knowledge Base 功能，允许用户管理知识库内容（Documents、Q&A），底层与 NeuAI (Dify) 集成。

**Architecture:** 使用 Kbase 命名空间模块，遵循现有 Captain 模块的模式。SuperAdmin 通过 Administrate 后台管理 KB 的创建/删除，普通用户通过前端 API 管理内容。NeuAI Client 封装 Dify Service API 调用。

**Tech Stack:** Rails 7, Vue 3 (Composition API), Vuex, HTTParty, Administrate, Tailwind CSS

**设计文档:** `docs/plans/2026-02-03-knowledge-base-design.md`

---

## Phase 1: 数据库与 Model 层

### Task 1: 创建数据库迁移

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_kbase_tables.rb`

**Step 1: 生成迁移文件**

Run: `rails generate migration CreateKbaseTables`

**Step 2: 编写迁移内容**

```ruby
class CreateKbaseTables < ActiveRecord::Migration[7.1]
  def change
    create_table :kbase_knowledge_bases do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :neuai_dataset_id
      t.string :qa_document_id
      t.text :description
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :kbase_knowledge_bases, [:account_id, :name], unique: true
    add_index :kbase_knowledge_bases, :neuai_dataset_id

    create_table :kbase_documents do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
      t.string :neuai_document_id, null: false
      t.string :name

      t.timestamps
    end

    add_index :kbase_documents, :neuai_document_id

    create_table :kbase_qa_pairs do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
      t.text :question, null: false
      t.text :answer, null: false
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :kbase_qa_pairs, [:knowledge_base_id, :position]
  end
end
```

**Step 3: 运行迁移**

Run: `rails db:migrate`
Expected: 3 tables created successfully

**Step 4: Commit**

```bash
git add db/migrate/*_create_kbase_tables.rb db/schema.rb
git commit -m "feat(kbase): add database tables for knowledge base"
```

---

### Task 2: 创建 Kbase::KnowledgeBase Model

**Files:**
- Verify: `app/models/kbase.rb` (already exists)
- Create: `app/models/kbase/knowledge_base.rb`
- Modify: `app/models/account.rb` (add association)

**Step 1: 创建 KnowledgeBase Model**

```ruby
# app/models/kbase/knowledge_base.rb
class Kbase::KnowledgeBase < ApplicationRecord
  self.table_name = 'kbase_knowledge_bases'

  belongs_to :account
  has_many :documents, class_name: 'Kbase::Document', dependent: :destroy_async
  has_many :qa_pairs, class_name: 'Kbase::QaPair', dependent: :destroy_async

  enum :status, { disabled: 0, enabled: 1 }

  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :account_id }
  validates :account_id, presence: true

  scope :ordered, -> { order(created_at: :desc) }
end
```

**Step 2: 添加 Account 关联**

在 `app/models/account.rb` 中添加：

```ruby
has_many :knowledge_bases, class_name: 'Kbase::KnowledgeBase', dependent: :destroy_async
```

**Step 3: 验证 Model**

Run: `rails console`
```ruby
Account.first.knowledge_bases.build(name: 'Test KB')
```
Expected: 返回新的 KnowledgeBase 实例

**Step 4: Commit**

```bash
git add app/models/kbase/knowledge_base.rb app/models/account.rb
git commit -m "feat(kbase): add KnowledgeBase model"
```

---

### Task 3: 创建 Kbase::Document Model

**Files:**
- Create: `app/models/kbase/document.rb`

**Step 1: 创建 Document Model**

```ruby
# app/models/kbase/document.rb
class Kbase::Document < ApplicationRecord
  self.table_name = 'kbase_documents'

  belongs_to :knowledge_base, class_name: 'Kbase::KnowledgeBase'

  validates :neuai_document_id, presence: true
  validates :neuai_document_id, uniqueness: { scope: :knowledge_base_id }

  scope :ordered, -> { order(created_at: :desc) }

  delegate :account, to: :knowledge_base
end
```

**Step 2: Commit**

```bash
git add app/models/kbase/document.rb
git commit -m "feat(kbase): add Document model"
```

---

### Task 4: 创建 Kbase::QaPair Model

**Files:**
- Create: `app/models/kbase/qa_pair.rb`

**Step 1: 创建 QaPair Model**

```ruby
# app/models/kbase/qa_pair.rb
class Kbase::QaPair < ApplicationRecord
  self.table_name = 'kbase_qa_pairs'

  belongs_to :knowledge_base, class_name: 'Kbase::KnowledgeBase'

  validates :question, presence: true
  validates :answer, presence: true

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  delegate :account, to: :knowledge_base

  before_create :set_position

  private

  def set_position
    self.position ||= (knowledge_base.qa_pairs.maximum(:position) || 0) + 1
  end
end
```

**Step 2: Commit**

```bash
git add app/models/kbase/qa_pair.rb
git commit -m "feat(kbase): add QaPair model"
```

---

## Phase 2: NeuAI Client 服务层

### Task 5: 创建 NeuAI Client

**Files:**
- Create: `app/services/kbase/neuai_client.rb`

**Step 1: 创建 NeuaiClient 服务**

```ruby
# app/services/kbase/neuai_client.rb
class Kbase::NeuaiClient
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  # Dataset API 使用系统级 ENV 配置，不依赖 Account 的 NeuAI Hook
  def initialize
    @base_url = ENV.fetch('NEUAI_DATASET_URL', nil)&.chomp('/')
    @api_key = ENV.fetch('NEUAI_DATASET_API_KEY', nil)

    raise ConfigurationError, 'NEUAI_DATASET_URL not configured' if @base_url.blank?
    raise ConfigurationError, 'NEUAI_DATASET_API_KEY not configured' if @api_key.blank?
  end

  # Dataset APIs
  def create_dataset(name:, description: nil)
    post('/v1/datasets', {
      name: name,
      description: description,
      indexing_technique: 'high_quality',
      permission: 'all_team_members'
    })
  end

  def delete_dataset(dataset_id)
    delete("/v1/datasets/#{dataset_id}")
  end

  def list_documents(dataset_id, page: 1, limit: 100)
    get("/v1/datasets/#{dataset_id}/documents", { page: page, limit: limit })
  end

  def get_document(dataset_id, document_id)
    get("/v1/datasets/#{dataset_id}/documents/#{document_id}")
  end

  def create_document_by_file(dataset_id, file, name:)
    data = {
      indexing_technique: 'high_quality',
      process_rule: { mode: 'automatic' }
    }

    post_multipart("/v1/datasets/#{dataset_id}/document/create-by-file", file: file, data: data.to_json)
  end

  def create_document_by_text(dataset_id, name:, text:, separator: '------')
    post("/v1/datasets/#{dataset_id}/document/create-by-text", {
      name: name,
      text: text,
      indexing_technique: 'high_quality',
      process_rule: {
        mode: 'custom',
        rules: {
          pre_processing_rules: [],
          segmentation: {
            separator: separator,
            max_tokens: 1000
          }
        }
      }
    })
  end

  def update_document_by_text(dataset_id, document_id, name:, text:)
    put("/v1/datasets/#{document_id}/documents/#{document_id}/update-by-text", {
      name: name,
      text: text
    })
  end

  def delete_document(dataset_id, document_id)
    delete("/v1/datasets/#{dataset_id}/documents/#{document_id}")
  end

  def update_document_status(dataset_id, document_ids, action:)
    patch("/v1/datasets/#{dataset_id}/documents/status/#{action}", {
      document_ids: Array(document_ids)
    })
  end

  private

  def headers
    {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def get(path, params = {})
    response = HTTParty.get("#{@base_url}#{path}", headers: headers, query: params)
    handle_response(response)
  end

  def post(path, body)
    response = HTTParty.post("#{@base_url}#{path}", headers: headers, body: body.to_json)
    handle_response(response)
  end

  def put(path, body)
    response = HTTParty.put("#{@base_url}#{path}", headers: headers, body: body.to_json)
    handle_response(response)
  end

  def patch(path, body)
    response = HTTParty.patch("#{@base_url}#{path}", headers: headers, body: body.to_json)
    handle_response(response)
  end

  def delete(path)
    response = HTTParty.delete("#{@base_url}#{path}", headers: headers)
    return nil if response.code == 204

    handle_response(response)
  end

  def post_multipart(path, file:, data:)
    response = HTTParty.post(
      "#{@base_url}#{path}",
      headers: { 'Authorization' => "Bearer #{@api_key}" },
      multipart: true,
      body: {
        file: file,
        data: data
      }
    )
    handle_response(response)
  end

  def handle_response(response)
    return response.parsed_response if response.success?

    raise ApiError.new(
      response.parsed_response&.dig('message') || 'API request failed',
      status: response.code,
      body: response.parsed_response
    )
  end
end
```

**Step 2: Commit**

```bash
git add app/services/kbase/neuai_client.rb
git commit -m "feat(kbase): add NeuAI API client service"
```

---

### Task 6: 创建 Q&A 同步服务

**Files:**
- Create: `app/services/kbase/qa_sync_service.rb`

**Step 1: 创建 QaSyncService**

```ruby
# app/services/kbase/qa_sync_service.rb
class Kbase::QaSyncService
  def initialize(knowledge_base)
    @kb = knowledge_base
    @client = Kbase::NeuaiClient.new  # 系统级配置，不需要 account 参数
  end

  def sync!
    return if @kb.neuai_dataset_id.blank?
    return if @kb.qa_pairs.empty?

    text = build_qa_text

    if @kb.qa_document_id.present?
      update_existing_document(text)
    else
      create_new_document(text)
    end
  end

  def needs_sync?
    return false if @kb.qa_pairs.empty?

    last_qa_update = @kb.qa_pairs.maximum(:updated_at)
    return true if @kb.qa_document_id.blank?

    # If any Q&A was updated after the KB was last synced
    last_qa_update > @kb.updated_at
  end

  private

  def build_qa_text
    @kb.qa_pairs.ordered.map do |qa|
      "Question: #{qa.question}\nAnswer: #{qa.answer}"
    end.join("\n------\n")
  end

  def create_new_document(text)
    response = @client.create_document_by_text(
      @kb.neuai_dataset_id,
      name: "#{@kb.name} - Q&A",
      text: text,
      separator: '------'
    )

    document_id = response.dig('document', 'id')
    @kb.update!(qa_document_id: document_id)
  end

  def update_existing_document(text)
    @client.update_document_by_text(
      @kb.neuai_dataset_id,
      @kb.qa_document_id,
      name: "#{@kb.name} - Q&A",
      text: text
    )
    @kb.touch
  end
end
```

**Step 2: Commit**

```bash
git add app/services/kbase/qa_sync_service.rb
git commit -m "feat(kbase): add Q&A sync service"
```

---

## Phase 3: SuperAdmin 后台

### Task 7: 创建 SuperAdmin Controller

**Files:**
- Create: `app/controllers/super_admin/knowledge_bases_controller.rb`

**Step 1: 创建 Controller**

```ruby
# app/controllers/super_admin/knowledge_bases_controller.rb
class SuperAdmin::KnowledgeBasesController < SuperAdmin::ApplicationController
  before_action :set_account
  before_action :set_knowledge_base, only: [:show, :edit, :update, :destroy]

  def index
    @knowledge_bases = @account.knowledge_bases.ordered
  end

  def show; end

  def new
    @knowledge_base = @account.knowledge_bases.new
  end

  def create
    @knowledge_base = @account.knowledge_bases.new(knowledge_base_params)

    if params[:create_in_neuai] == '1' && @knowledge_base.neuai_dataset_id.blank?
      create_neuai_dataset
    end

    if @knowledge_base.save
      redirect_to super_admin_account_knowledge_bases_path(@account),
                  notice: 'Knowledge base was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  rescue Kbase::NeuaiClient::Error => e
    flash.now[:error] = "NeuAI Error: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @knowledge_base.update(knowledge_base_params)
      redirect_to super_admin_account_knowledge_bases_path(@account),
                  notice: 'Knowledge base was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if params[:delete_from_neuai] == '1' && @knowledge_base.neuai_dataset_id.present?
      delete_neuai_dataset
    end

    @knowledge_base.destroy
    redirect_to super_admin_account_knowledge_bases_path(@account),
                notice: 'Knowledge base was successfully deleted.'
  rescue Kbase::NeuaiClient::Error => e
    redirect_to super_admin_account_knowledge_bases_path(@account),
                alert: "Deleted locally but NeuAI error: #{e.message}"
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def set_knowledge_base
    @knowledge_base = @account.knowledge_bases.find(params[:id])
  end

  def knowledge_base_params
    params.require(:kbase_knowledge_base).permit(:name, :description, :neuai_dataset_id, :status)
  end

  def create_neuai_dataset
    client = Kbase::NeuaiClient.new
    dataset_name = "account_#{@account.id}_#{@knowledge_base.name}"
    response = client.create_dataset(name: dataset_name, description: @knowledge_base.description)
    @knowledge_base.neuai_dataset_id = response['id']
  end

  def delete_neuai_dataset
    client = Kbase::NeuaiClient.new
    client.delete_dataset(@knowledge_base.neuai_dataset_id)
  end
end
```

**Step 2: Commit**

```bash
git add app/controllers/super_admin/knowledge_bases_controller.rb
git commit -m "feat(kbase): add SuperAdmin knowledge bases controller"
```

---

### Task 8: 添加 SuperAdmin 路由

**Files:**
- Modify: `config/routes.rb`

**Step 1: 添加路由**

在 `config/routes.rb` 的 `namespace :super_admin` 块内添加：

```ruby
resources :accounts do
  resources :knowledge_bases, controller: 'knowledge_bases'
end
```

**Step 2: 验证路由**

Run: `rails routes | grep knowledge_bases`
Expected: 显示 super_admin_account_knowledge_bases 相关路由

**Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat(kbase): add SuperAdmin routes for knowledge bases"
```

---

### Task 9: 创建 SuperAdmin 视图

**Files:**
- Create: `app/views/super_admin/knowledge_bases/index.html.erb`
- Create: `app/views/super_admin/knowledge_bases/new.html.erb`
- Create: `app/views/super_admin/knowledge_bases/edit.html.erb`
- Create: `app/views/super_admin/knowledge_bases/show.html.erb`
- Create: `app/views/super_admin/knowledge_bases/_form.html.erb`

**Step 1: 创建 index 视图**

```erb
<%# app/views/super_admin/knowledge_bases/index.html.erb %>
<header class="main-content__header">
  <h1 class="main-content__page-title">Knowledge Bases for <%= @account.name %></h1>
  <div>
    <%= link_to 'Back to Account', super_admin_account_path(@account), class: 'button' %>
    <%= link_to 'New Knowledge Base', new_super_admin_account_knowledge_base_path(@account), class: 'button button--primary' %>
  </div>
</header>

<section class="main-content__body">
  <table class="collection-data">
    <thead>
      <tr>
        <th>ID</th>
        <th>Name</th>
        <th>NeuAI Dataset ID</th>
        <th>Status</th>
        <th>Documents</th>
        <th>Q&A Pairs</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <% @knowledge_bases.each do |kb| %>
        <tr>
          <td><%= kb.id %></td>
          <td><%= kb.name %></td>
          <td><%= kb.neuai_dataset_id || '-' %></td>
          <td><%= kb.status %></td>
          <td><%= kb.documents.count %></td>
          <td><%= kb.qa_pairs.count %></td>
          <td>
            <%= link_to 'Edit', edit_super_admin_account_knowledge_base_path(@account, kb) %>
            <%= link_to 'Delete', super_admin_account_knowledge_base_path(@account, kb),
                        method: :delete,
                        data: { confirm: 'Are you sure?' } %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</section>
```

**Step 2: 创建 _form partial**

```erb
<%# app/views/super_admin/knowledge_bases/_form.html.erb %>
<%= form_with model: [:super_admin, @account, @knowledge_base], local: true do |f| %>
  <% if @knowledge_base.errors.any? %>
    <div class="form-errors">
      <ul>
        <% @knowledge_base.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="field-unit">
    <%= f.label :name %>
    <%= f.text_field :name, class: 'field-unit__field', required: true %>
  </div>

  <div class="field-unit">
    <%= f.label :description %>
    <%= f.text_area :description, class: 'field-unit__field', rows: 3 %>
  </div>

  <div class="field-unit">
    <%= f.label :status %>
    <%= f.select :status, Kbase::KnowledgeBase.statuses.keys, {}, class: 'field-unit__field' %>
  </div>

  <fieldset class="field-unit">
    <legend>NeuAI Dataset</legend>

    <% if @knowledge_base.new_record? %>
      <div class="field-unit">
        <%= radio_button_tag :mode, 'create', true, id: 'mode_create' %>
        <%= label_tag :mode_create, 'Create new Dataset in NeuAI' %>
      </div>
      <div class="field-unit">
        <%= radio_button_tag :mode, 'bind', false, id: 'mode_bind' %>
        <%= label_tag :mode_bind, 'Bind to existing Dataset' %>
      </div>
      <%= hidden_field_tag :create_in_neuai, '1', id: 'create_in_neuai_field' %>
    <% end %>

    <div class="field-unit" id="dataset_id_field">
      <%= f.label :neuai_dataset_id, 'NeuAI Dataset ID' %>
      <%= f.text_field :neuai_dataset_id, class: 'field-unit__field',
                       placeholder: 'Leave empty to create new, or enter existing ID' %>
    </div>
  </fieldset>

  <div class="form-actions">
    <%= f.submit class: 'button button--primary' %>
    <%= link_to 'Cancel', super_admin_account_knowledge_bases_path(@account), class: 'button' %>
  </div>
<% end %>

<script>
  document.addEventListener('DOMContentLoaded', function() {
    const modeCreate = document.getElementById('mode_create');
    const modeBind = document.getElementById('mode_bind');
    const createField = document.getElementById('create_in_neuai_field');
    const datasetField = document.getElementById('dataset_id_field');

    if (modeCreate && modeBind) {
      modeCreate.addEventListener('change', function() {
        if (this.checked) {
          createField.value = '1';
          datasetField.style.display = 'none';
        }
      });

      modeBind.addEventListener('change', function() {
        if (this.checked) {
          createField.value = '0';
          datasetField.style.display = 'block';
        }
      });

      // Initial state
      if (modeCreate.checked) {
        datasetField.style.display = 'none';
      }
    }
  });
</script>
```

**Step 3: 创建 new 视图**

```erb
<%# app/views/super_admin/knowledge_bases/new.html.erb %>
<header class="main-content__header">
  <h1 class="main-content__page-title">New Knowledge Base for <%= @account.name %></h1>
</header>

<section class="main-content__body">
  <%= render 'form' %>
</section>
```

**Step 4: 创建 edit 视图**

```erb
<%# app/views/super_admin/knowledge_bases/edit.html.erb %>
<header class="main-content__header">
  <h1 class="main-content__page-title">Edit Knowledge Base: <%= @knowledge_base.name %></h1>
</header>

<section class="main-content__body">
  <%= render 'form' %>
</section>
```

**Step 5: 创建 show 视图**

```erb
<%# app/views/super_admin/knowledge_bases/show.html.erb %>
<header class="main-content__header">
  <h1 class="main-content__page-title">Knowledge Base: <%= @knowledge_base.name %></h1>
  <div>
    <%= link_to 'Edit', edit_super_admin_account_knowledge_base_path(@account, @knowledge_base), class: 'button' %>
    <%= link_to 'Back', super_admin_account_knowledge_bases_path(@account), class: 'button' %>
  </div>
</header>

<section class="main-content__body">
  <dl>
    <dt>Name</dt>
    <dd><%= @knowledge_base.name %></dd>

    <dt>Description</dt>
    <dd><%= @knowledge_base.description || '-' %></dd>

    <dt>Status</dt>
    <dd><%= @knowledge_base.status %></dd>

    <dt>NeuAI Dataset ID</dt>
    <dd><%= @knowledge_base.neuai_dataset_id || 'Not linked' %></dd>

    <dt>Q&A Document ID</dt>
    <dd><%= @knowledge_base.qa_document_id || 'Not created' %></dd>

    <dt>Documents Count</dt>
    <dd><%= @knowledge_base.documents.count %></dd>

    <dt>Q&A Pairs Count</dt>
    <dd><%= @knowledge_base.qa_pairs.count %></dd>
  </dl>
</section>
```

**Step 6: Commit**

```bash
git add app/views/super_admin/knowledge_bases/
git commit -m "feat(kbase): add SuperAdmin views for knowledge bases"
```

---

## Phase 4: 用户 API

### Task 10: 创建 KnowledgeBases API Controller

**Files:**
- Create: `app/controllers/api/v1/accounts/knowledge_bases_controller.rb`

**Step 1: 创建 Controller**

```ruby
# app/controllers/api/v1/accounts/knowledge_bases_controller.rb
class Api::V1::Accounts::KnowledgeBasesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base, only: [:show]

  def index
    @knowledge_bases = Current.account.knowledge_bases.enabled.ordered
  end

  def show
    render json: knowledge_base_response(@knowledge_base)
  end

  private

  def set_knowledge_base
    @knowledge_base = Current.account.knowledge_bases.find(params[:id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def knowledge_base_response(kb)
    {
      id: kb.id,
      name: kb.name,
      description: kb.description,
      status: kb.status,
      neuai_dataset_id: kb.neuai_dataset_id,
      documents_count: kb.documents.count,
      qa_pairs_count: kb.qa_pairs.count,
      created_at: kb.created_at,
      updated_at: kb.updated_at
    }
  end
end
```

**Step 2: Commit**

```bash
git add app/controllers/api/v1/accounts/knowledge_bases_controller.rb
git commit -m "feat(kbase): add KnowledgeBases API controller"
```

---

### Task 11: 创建 Documents API Controller

**Files:**
- Create: `app/controllers/api/v1/accounts/knowledge_bases/documents_controller.rb`

**Step 1: 创建 Controller**

```ruby
# app/controllers/api/v1/accounts/knowledge_bases/documents_controller.rb
class Api::V1::Accounts::KnowledgeBases::DocumentsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base
  before_action :set_document, only: [:show, :update, :destroy]

  def index
    sync_documents_from_neuai
    @documents = @knowledge_base.documents.ordered
    render json: { documents: documents_response }
  end

  def create
    return render_error('No file uploaded', :bad_request) unless params[:file].present?

    client = Kbase::NeuaiClient.new
    response = client.create_document_by_file(
      @knowledge_base.neuai_dataset_id,
      params[:file],
      name: params[:name] || params[:file].original_filename
    )

    document = @knowledge_base.documents.create!(
      neuai_document_id: response.dig('document', 'id'),
      name: params[:name] || params[:file].original_filename
    )

    render json: document_response(document, response['document']), status: :created
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  def update
    action = params[:enabled] ? 'enable' : 'disable'
    client = Kbase::NeuaiClient.new
    client.update_document_status(
      @knowledge_base.neuai_dataset_id,
      @document.neuai_document_id,
      action: action
    )

    render json: { success: true }
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  def destroy
    client = Kbase::NeuaiClient.new
    client.delete_document(@knowledge_base.neuai_dataset_id, @document.neuai_document_id)
    @document.destroy

    head :no_content
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  private

  def set_knowledge_base
    @knowledge_base = Current.account.knowledge_bases.find(params[:knowledge_base_id])
  end

  def set_document
    @document = @knowledge_base.documents.find(params[:id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def sync_documents_from_neuai
    return if @knowledge_base.neuai_dataset_id.blank?

    client = Kbase::NeuaiClient.new
    response = client.list_documents(@knowledge_base.neuai_dataset_id)
    @neuai_documents = response['data'] || []
  rescue Kbase::NeuaiClient::Error
    @neuai_documents = []
  end

  def documents_response
    @knowledge_base.documents.ordered.map do |doc|
      neuai_doc = @neuai_documents&.find { |d| d['id'] == doc.neuai_document_id }
      document_response(doc, neuai_doc)
    end
  end

  def document_response(doc, neuai_doc = nil)
    {
      id: doc.id,
      name: doc.name,
      neuai_document_id: doc.neuai_document_id,
      indexing_status: neuai_doc&.dig('indexing_status') || 'unknown',
      enabled: neuai_doc&.dig('enabled') ?? true,
      word_count: neuai_doc&.dig('word_count') || 0,
      created_at: doc.created_at
    }
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
```

**Step 2: Commit**

```bash
git add app/controllers/api/v1/accounts/knowledge_bases/documents_controller.rb
git commit -m "feat(kbase): add Documents API controller"
```

---

### Task 12: 创建 QaPairs API Controller

**Files:**
- Create: `app/controllers/api/v1/accounts/knowledge_bases/qa_pairs_controller.rb`

**Step 1: 创建 Controller**

```ruby
# app/controllers/api/v1/accounts/knowledge_bases/qa_pairs_controller.rb
class Api::V1::Accounts::KnowledgeBases::QaPairsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base
  before_action :set_qa_pair, only: [:show, :update, :destroy]

  def index
    @qa_pairs = @knowledge_base.qa_pairs.ordered
    render json: {
      qa_pairs: @qa_pairs.map { |qa| qa_pair_response(qa) },
      sync_required: sync_service.needs_sync?,
      qa_document_id: @knowledge_base.qa_document_id
    }
  end

  def create
    @qa_pair = @knowledge_base.qa_pairs.create!(qa_pair_params)
    render json: qa_pair_response(@qa_pair), status: :created
  end

  def update
    @qa_pair.update!(qa_pair_params)
    render json: qa_pair_response(@qa_pair)
  end

  def destroy
    @qa_pair.destroy
    head :no_content
  end

  def sync
    sync_service.sync!
    render json: {
      success: true,
      qa_document_id: @knowledge_base.reload.qa_document_id
    }
  rescue Kbase::NeuaiClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_knowledge_base
    @knowledge_base = Current.account.knowledge_bases.find(params[:knowledge_base_id])
  end

  def set_qa_pair
    @qa_pair = @knowledge_base.qa_pairs.find(params[:id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def qa_pair_params
    params.require(:qa_pair).permit(:question, :answer, :position)
  end

  def qa_pair_response(qa)
    {
      id: qa.id,
      question: qa.question,
      answer: qa.answer,
      position: qa.position,
      created_at: qa.created_at,
      updated_at: qa.updated_at
    }
  end

  def sync_service
    @sync_service ||= Kbase::QaSyncService.new(@knowledge_base)
  end
end
```

**Step 2: Commit**

```bash
git add app/controllers/api/v1/accounts/knowledge_bases/qa_pairs_controller.rb
git commit -m "feat(kbase): add QaPairs API controller"
```

---

### Task 13: 添加用户 API 路由

**Files:**
- Modify: `config/routes.rb`

**Step 1: 添加路由**

在 `config/routes.rb` 的 `namespace :api, defaults: { format: 'json' }` > `namespace :v1` > `resources :accounts` 块内添加：

```ruby
resources :knowledge_bases, only: [:index, :show] do
  resources :documents, only: [:index, :create, :update, :destroy], controller: 'knowledge_bases/documents'
  resources :qa_pairs, only: [:index, :create, :update, :destroy], controller: 'knowledge_bases/qa_pairs' do
    collection do
      post :sync
    end
  end
end
```

**Step 2: 验证路由**

Run: `rails routes | grep knowledge_bases | head -20`

**Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat(kbase): add user API routes for knowledge bases"
```

---

## Phase 5: 前端实现

### Task 14: 创建 API 客户端

**Files:**
- Create: `app/javascript/dashboard/api/knowledgeBases.js`

**Step 1: 创建 API 客户端**

```javascript
// app/javascript/dashboard/api/knowledgeBases.js
import ApiClient from './ApiClient';

class KnowledgeBasesAPI extends ApiClient {
  constructor() {
    super('knowledge_bases', { accountScoped: true });
  }

  // Documents
  getDocuments(knowledgeBaseId) {
    return axios.get(`${this.url}/${knowledgeBaseId}/documents`);
  }

  createDocument(knowledgeBaseId, file, name) {
    const formData = new FormData();
    formData.append('file', file);
    if (name) formData.append('name', name);

    return axios.post(`${this.url}/${knowledgeBaseId}/documents`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  updateDocument(knowledgeBaseId, documentId, data) {
    return axios.patch(`${this.url}/${knowledgeBaseId}/documents/${documentId}`, data);
  }

  deleteDocument(knowledgeBaseId, documentId) {
    return axios.delete(`${this.url}/${knowledgeBaseId}/documents/${documentId}`);
  }

  // Q&A Pairs
  getQaPairs(knowledgeBaseId) {
    return axios.get(`${this.url}/${knowledgeBaseId}/qa_pairs`);
  }

  createQaPair(knowledgeBaseId, data) {
    return axios.post(`${this.url}/${knowledgeBaseId}/qa_pairs`, { qa_pair: data });
  }

  updateQaPair(knowledgeBaseId, qaPairId, data) {
    return axios.patch(`${this.url}/${knowledgeBaseId}/qa_pairs/${qaPairId}`, { qa_pair: data });
  }

  deleteQaPair(knowledgeBaseId, qaPairId) {
    return axios.delete(`${this.url}/${knowledgeBaseId}/qa_pairs/${qaPairId}`);
  }

  syncQaPairs(knowledgeBaseId) {
    return axios.post(`${this.url}/${knowledgeBaseId}/qa_pairs/sync`);
  }
}

export default new KnowledgeBasesAPI();
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/api/knowledgeBases.js
git commit -m "feat(kbase): add frontend API client"
```

---

### Task 15: 创建 Vuex Store

**Files:**
- Create: `app/javascript/dashboard/store/modules/knowledgeBases.js`
- Modify: `app/javascript/dashboard/store/index.js`

**Step 1: 创建 Store Module**

```javascript
// app/javascript/dashboard/store/modules/knowledgeBases.js
import KnowledgeBasesAPI from '../../api/knowledgeBases';

const state = {
  records: [],
  currentKB: null,
  documents: [],
  qaPairs: [],
  qaSyncRequired: false,
  qaDocumentId: null,
  uiFlags: {
    isFetching: false,
    isFetchingDocuments: false,
    isFetchingQaPairs: false,
    isCreating: false,
    isSyncing: false,
  },
};

const getters = {
  getKnowledgeBases: $state => $state.records,
  getCurrentKB: $state => $state.currentKB,
  getDocuments: $state => $state.documents,
  getQaPairs: $state => $state.qaPairs,
  getQaSyncRequired: $state => $state.qaSyncRequired,
  getUIFlags: $state => $state.uiFlags,
  hasProcessingDocuments: $state =>
    $state.documents.some(d => ['waiting', 'indexing', 'parsing'].includes(d.indexing_status)),
};

const actions = {
  async fetchKnowledgeBases({ commit }) {
    commit('setUIFlag', { isFetching: true });
    try {
      const response = await KnowledgeBasesAPI.get();
      commit('setRecords', response.data);
    } finally {
      commit('setUIFlag', { isFetching: false });
    }
  },

  async fetchKnowledgeBase({ commit }, id) {
    commit('setUIFlag', { isFetching: true });
    try {
      const response = await KnowledgeBasesAPI.show(id);
      commit('setCurrentKB', response.data);
    } finally {
      commit('setUIFlag', { isFetching: false });
    }
  },

  async fetchDocuments({ commit }, knowledgeBaseId) {
    commit('setUIFlag', { isFetchingDocuments: true });
    try {
      const response = await KnowledgeBasesAPI.getDocuments(knowledgeBaseId);
      commit('setDocuments', response.data.documents);
    } finally {
      commit('setUIFlag', { isFetchingDocuments: false });
    }
  },

  async createDocument({ commit, dispatch }, { knowledgeBaseId, file, name }) {
    commit('setUIFlag', { isCreating: true });
    try {
      await KnowledgeBasesAPI.createDocument(knowledgeBaseId, file, name);
      dispatch('fetchDocuments', knowledgeBaseId);
    } finally {
      commit('setUIFlag', { isCreating: false });
    }
  },

  async toggleDocument({ dispatch }, { knowledgeBaseId, documentId, enabled }) {
    await KnowledgeBasesAPI.updateDocument(knowledgeBaseId, documentId, { enabled });
    dispatch('fetchDocuments', knowledgeBaseId);
  },

  async deleteDocument({ dispatch }, { knowledgeBaseId, documentId }) {
    await KnowledgeBasesAPI.deleteDocument(knowledgeBaseId, documentId);
    dispatch('fetchDocuments', knowledgeBaseId);
  },

  async fetchQaPairs({ commit }, knowledgeBaseId) {
    commit('setUIFlag', { isFetchingQaPairs: true });
    try {
      const response = await KnowledgeBasesAPI.getQaPairs(knowledgeBaseId);
      commit('setQaPairs', response.data.qa_pairs);
      commit('setQaSyncRequired', response.data.sync_required);
      commit('setQaDocumentId', response.data.qa_document_id);
    } finally {
      commit('setUIFlag', { isFetchingQaPairs: false });
    }
  },

  async createQaPair({ commit, dispatch }, { knowledgeBaseId, data }) {
    const response = await KnowledgeBasesAPI.createQaPair(knowledgeBaseId, data);
    commit('addQaPair', response.data);
    commit('setQaSyncRequired', true);
  },

  async updateQaPair({ commit }, { knowledgeBaseId, qaPairId, data }) {
    const response = await KnowledgeBasesAPI.updateQaPair(knowledgeBaseId, qaPairId, data);
    commit('updateQaPair', response.data);
    commit('setQaSyncRequired', true);
  },

  async deleteQaPair({ commit }, { knowledgeBaseId, qaPairId }) {
    await KnowledgeBasesAPI.deleteQaPair(knowledgeBaseId, qaPairId);
    commit('removeQaPair', qaPairId);
    commit('setQaSyncRequired', true);
  },

  async syncQaPairs({ commit }, knowledgeBaseId) {
    commit('setUIFlag', { isSyncing: true });
    try {
      const response = await KnowledgeBasesAPI.syncQaPairs(knowledgeBaseId);
      commit('setQaSyncRequired', false);
      commit('setQaDocumentId', response.data.qa_document_id);
    } finally {
      commit('setUIFlag', { isSyncing: false });
    }
  },
};

const mutations = {
  setRecords($state, records) {
    $state.records = records;
  },
  setCurrentKB($state, kb) {
    $state.currentKB = kb;
  },
  setDocuments($state, documents) {
    $state.documents = documents;
  },
  setQaPairs($state, qaPairs) {
    $state.qaPairs = qaPairs;
  },
  addQaPair($state, qaPair) {
    $state.qaPairs.push(qaPair);
  },
  updateQaPair($state, qaPair) {
    const index = $state.qaPairs.findIndex(q => q.id === qaPair.id);
    if (index !== -1) {
      $state.qaPairs.splice(index, 1, qaPair);
    }
  },
  removeQaPair($state, qaPairId) {
    $state.qaPairs = $state.qaPairs.filter(q => q.id !== qaPairId);
  },
  setQaSyncRequired($state, value) {
    $state.qaSyncRequired = value;
  },
  setQaDocumentId($state, value) {
    $state.qaDocumentId = value;
  },
  setUIFlag($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
```

**Step 2: 注册 Store Module**

在 `app/javascript/dashboard/store/index.js` 中添加：

```javascript
import knowledgeBases from './modules/knowledgeBases';

// 在 modules 对象中添加
modules: {
  // ... 其他 modules
  knowledgeBases,
}
```

**Step 3: Commit**

```bash
git add app/javascript/dashboard/store/modules/knowledgeBases.js app/javascript/dashboard/store/index.js
git commit -m "feat(kbase): add Vuex store module"
```

---

### Task 16: 创建前端路由

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/knowledgeBase/knowledgeBase.routes.js`
- Modify: `app/javascript/dashboard/routes/index.js`

**Step 1: 创建路由文件**

```javascript
// app/javascript/dashboard/routes/dashboard/knowledgeBase/knowledgeBase.routes.js
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
```

**Step 2: 注册路由**

在主路由文件中导入并添加这些路由。

**Step 3: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/knowledgeBase/
git commit -m "feat(kbase): add frontend routes"
```

---

### Task 17: 创建 Knowledge Base 列表页

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/knowledgeBase/Index.vue`

**Step 1: 创建 Index.vue**

```vue
<script setup>
import { computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const knowledgeBases = computed(() => store.getters['knowledgeBases/getKnowledgeBases']);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

onMounted(() => {
  store.dispatch('knowledgeBases/fetchKnowledgeBases');
});

const navigateToKB = (kb) => {
  router.push({
    name: 'knowledge_base_show',
    params: { knowledgeBaseId: kb.id },
  });
};
</script>

<template>
  <div class="flex flex-col h-full p-6">
    <header class="mb-6">
      <h1 class="text-2xl font-bold text-slate-900 dark:text-slate-100">
        {{ t('KNOWLEDGE_BASE.TITLE') }}
      </h1>
      <p class="text-sm text-slate-600 dark:text-slate-400 mt-1">
        {{ t('KNOWLEDGE_BASE.DESCRIPTION') }}
      </p>
    </header>

    <div v-if="uiFlags.isFetching" class="flex items-center justify-center py-12">
      <span class="text-slate-500">{{ t('KNOWLEDGE_BASE.LOADING') }}</span>
    </div>

    <div v-else-if="knowledgeBases.length === 0" class="flex flex-col items-center justify-center py-12">
      <p class="text-slate-500">{{ t('KNOWLEDGE_BASE.EMPTY') }}</p>
    </div>

    <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <div
        v-for="kb in knowledgeBases"
        :key="kb.id"
        class="p-4 bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 cursor-pointer hover:border-woot-500 transition-colors"
        @click="navigateToKB(kb)"
      >
        <h3 class="font-semibold text-slate-900 dark:text-slate-100">{{ kb.name }}</h3>
        <p class="text-sm text-slate-600 dark:text-slate-400 mt-1 line-clamp-2">
          {{ kb.description || t('KNOWLEDGE_BASE.NO_DESCRIPTION') }}
        </p>
        <div class="flex gap-4 mt-3 text-xs text-slate-500">
          <span>{{ kb.documents_count }} {{ t('KNOWLEDGE_BASE.DOCUMENTS') }}</span>
          <span>{{ kb.qa_pairs_count }} {{ t('KNOWLEDGE_BASE.QA_PAIRS') }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/knowledgeBase/Index.vue
git commit -m "feat(kbase): add Knowledge Base list page"
```

---

### Task 18: 创建 Knowledge Base 详情页

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/knowledgeBase/Show.vue`

**Step 1: 创建 Show.vue**

```vue
<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import DocumentList from './components/DocumentList.vue';
import QAPairList from './components/QAPairList.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const activeTab = ref('documents');
const pollInterval = ref(null);

const knowledgeBaseId = computed(() => route.params.knowledgeBaseId);
const currentKB = computed(() => store.getters['knowledgeBases/getCurrentKB']);
const hasProcessingDocuments = computed(() => store.getters['knowledgeBases/hasProcessingDocuments']);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

const tabs = [
  { key: 'documents', label: t('KNOWLEDGE_BASE.TABS.DOCUMENTS') },
  { key: 'qa', label: t('KNOWLEDGE_BASE.TABS.QA') },
];

onMounted(() => {
  store.dispatch('knowledgeBases/fetchKnowledgeBase', knowledgeBaseId.value);
  store.dispatch('knowledgeBases/fetchDocuments', knowledgeBaseId.value);
});

watch(hasProcessingDocuments, (hasProcessing) => {
  if (hasProcessing && !pollInterval.value) {
    pollInterval.value = setInterval(() => {
      store.dispatch('knowledgeBases/fetchDocuments', knowledgeBaseId.value);
    }, 5000);
  } else if (!hasProcessing && pollInterval.value) {
    clearInterval(pollInterval.value);
    pollInterval.value = null;
  }
});

watch(activeTab, (tab) => {
  if (tab === 'qa') {
    store.dispatch('knowledgeBases/fetchQaPairs', knowledgeBaseId.value);
  }
});

onUnmounted(() => {
  if (pollInterval.value) {
    clearInterval(pollInterval.value);
  }
});
</script>

<template>
  <div class="flex flex-col h-full">
    <header class="p-6 border-b border-slate-200 dark:border-slate-700">
      <h1 class="text-2xl font-bold text-slate-900 dark:text-slate-100">
        {{ currentKB?.name || t('KNOWLEDGE_BASE.LOADING') }}
      </h1>
      <p v-if="currentKB?.description" class="text-sm text-slate-600 dark:text-slate-400 mt-1">
        {{ currentKB.description }}
      </p>
    </header>

    <div class="border-b border-slate-200 dark:border-slate-700">
      <nav class="flex gap-4 px-6">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="py-3 px-1 text-sm font-medium border-b-2 transition-colors"
          :class="activeTab === tab.key
            ? 'border-woot-500 text-woot-500'
            : 'border-transparent text-slate-600 hover:text-slate-900'"
          @click="activeTab = tab.key"
        >
          {{ tab.label }}
        </button>
      </nav>
    </div>

    <div class="flex-1 overflow-auto p-6">
      <DocumentList
        v-if="activeTab === 'documents'"
        :knowledge-base-id="knowledgeBaseId"
      />
      <QAPairList
        v-else-if="activeTab === 'qa'"
        :knowledge-base-id="knowledgeBaseId"
      />
    </div>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/knowledgeBase/Show.vue
git commit -m "feat(kbase): add Knowledge Base detail page"
```

---

### Task 19: 创建 DocumentList 组件

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentList.vue`

**Step 1: 创建 DocumentList.vue**

```vue
<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();
const { showAlert } = useAlert();

const fileInput = ref(null);
const isUploading = ref(false);

const documents = computed(() => store.getters['knowledgeBases/getDocuments']);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

const statusColors = {
  completed: 'bg-green-100 text-green-800',
  indexing: 'bg-yellow-100 text-yellow-800',
  parsing: 'bg-yellow-100 text-yellow-800',
  waiting: 'bg-slate-100 text-slate-800',
  error: 'bg-red-100 text-red-800',
};

const triggerUpload = () => {
  fileInput.value?.click();
};

const handleFileSelect = async (event) => {
  const file = event.target.files[0];
  if (!file) return;

  isUploading.value = true;
  try {
    await store.dispatch('knowledgeBases/createDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      file,
      name: file.name,
    });
    showAlert(t('KNOWLEDGE_BASE.DOCUMENT_UPLOADED'));
  } catch (error) {
    showAlert(error.message || t('KNOWLEDGE_BASE.UPLOAD_FAILED'));
  } finally {
    isUploading.value = false;
    event.target.value = '';
  }
};

const toggleDocument = async (doc) => {
  try {
    await store.dispatch('knowledgeBases/toggleDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      documentId: doc.id,
      enabled: !doc.enabled,
    });
  } catch (error) {
    showAlert(error.message);
  }
};

const deleteDocument = async (doc) => {
  if (!confirm(t('KNOWLEDGE_BASE.CONFIRM_DELETE_DOCUMENT'))) return;

  try {
    await store.dispatch('knowledgeBases/deleteDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      documentId: doc.id,
    });
    showAlert(t('KNOWLEDGE_BASE.DOCUMENT_DELETED'));
  } catch (error) {
    showAlert(error.message);
  }
};
</script>

<template>
  <div>
    <div class="flex justify-between items-center mb-4">
      <h2 class="text-lg font-semibold">{{ t('KNOWLEDGE_BASE.DOCUMENTS_TITLE') }}</h2>
      <button
        class="px-4 py-2 bg-woot-500 text-white rounded-lg hover:bg-woot-600 disabled:opacity-50"
        :disabled="isUploading"
        @click="triggerUpload"
      >
        {{ isUploading ? t('KNOWLEDGE_BASE.UPLOADING') : t('KNOWLEDGE_BASE.UPLOAD_DOCUMENT') }}
      </button>
      <input
        ref="fileInput"
        type="file"
        class="hidden"
        accept=".txt,.pdf,.docx,.md,.html,.csv,.xlsx"
        @change="handleFileSelect"
      />
    </div>

    <div v-if="uiFlags.isFetchingDocuments" class="py-8 text-center text-slate-500">
      {{ t('KNOWLEDGE_BASE.LOADING') }}
    </div>

    <div v-else-if="documents.length === 0" class="py-8 text-center text-slate-500">
      {{ t('KNOWLEDGE_BASE.NO_DOCUMENTS') }}
    </div>

    <table v-else class="w-full">
      <thead>
        <tr class="text-left text-sm text-slate-600 border-b">
          <th class="pb-2">{{ t('KNOWLEDGE_BASE.NAME') }}</th>
          <th class="pb-2">{{ t('KNOWLEDGE_BASE.STATUS') }}</th>
          <th class="pb-2">{{ t('KNOWLEDGE_BASE.WORDS') }}</th>
          <th class="pb-2">{{ t('KNOWLEDGE_BASE.ENABLED') }}</th>
          <th class="pb-2">{{ t('KNOWLEDGE_BASE.ACTIONS') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="doc in documents" :key="doc.id" class="border-b border-slate-100">
          <td class="py-3">{{ doc.name }}</td>
          <td class="py-3">
            <span
              class="px-2 py-1 text-xs rounded-full"
              :class="statusColors[doc.indexing_status] || statusColors.waiting"
            >
              {{ doc.indexing_status }}
            </span>
          </td>
          <td class="py-3 text-slate-600">{{ doc.word_count }}</td>
          <td class="py-3">
            <button
              class="w-10 h-5 rounded-full transition-colors"
              :class="doc.enabled ? 'bg-woot-500' : 'bg-slate-300'"
              @click="toggleDocument(doc)"
            >
              <span
                class="block w-4 h-4 bg-white rounded-full transition-transform"
                :class="doc.enabled ? 'translate-x-5' : 'translate-x-0.5'"
              />
            </button>
          </td>
          <td class="py-3">
            <button
              class="text-red-600 hover:text-red-800"
              @click="deleteDocument(doc)"
            >
              {{ t('KNOWLEDGE_BASE.DELETE') }}
            </button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/knowledgeBase/components/DocumentList.vue
git commit -m "feat(kbase): add DocumentList component"
```

---

### Task 20: 创建 QAPairList 组件

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/knowledgeBase/components/QAPairList.vue`

**Step 1: 创建 QAPairList.vue**

```vue
<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();
const { showAlert } = useAlert();

const isEditing = ref(false);
const editingId = ref(null);
const form = ref({ question: '', answer: '' });

const qaPairs = computed(() => store.getters['knowledgeBases/getQaPairs']);
const syncRequired = computed(() => store.getters['knowledgeBases/getQaSyncRequired']);
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);

const startAdd = () => {
  form.value = { question: '', answer: '' };
  editingId.value = null;
  isEditing.value = true;
};

const startEdit = (qa) => {
  form.value = { question: qa.question, answer: qa.answer };
  editingId.value = qa.id;
  isEditing.value = true;
};

const cancelEdit = () => {
  isEditing.value = false;
  editingId.value = null;
  form.value = { question: '', answer: '' };
};

const saveQaPair = async () => {
  try {
    if (editingId.value) {
      await store.dispatch('knowledgeBases/updateQaPair', {
        knowledgeBaseId: props.knowledgeBaseId,
        qaPairId: editingId.value,
        data: form.value,
      });
    } else {
      await store.dispatch('knowledgeBases/createQaPair', {
        knowledgeBaseId: props.knowledgeBaseId,
        data: form.value,
      });
    }
    cancelEdit();
  } catch (error) {
    showAlert(error.message);
  }
};

const deleteQaPair = async (qa) => {
  if (!confirm(t('KNOWLEDGE_BASE.CONFIRM_DELETE_QA'))) return;

  try {
    await store.dispatch('knowledgeBases/deleteQaPair', {
      knowledgeBaseId: props.knowledgeBaseId,
      qaPairId: qa.id,
    });
  } catch (error) {
    showAlert(error.message);
  }
};

const syncToNeuAI = async () => {
  try {
    await store.dispatch('knowledgeBases/syncQaPairs', props.knowledgeBaseId);
    showAlert(t('KNOWLEDGE_BASE.SYNC_SUCCESS'));
  } catch (error) {
    showAlert(error.message);
  }
};
</script>

<template>
  <div>
    <!-- Sync Banner -->
    <div
      v-if="syncRequired"
      class="mb-4 p-3 bg-yellow-50 border border-yellow-200 rounded-lg flex items-center justify-between"
    >
      <span class="text-yellow-800">{{ t('KNOWLEDGE_BASE.SYNC_REQUIRED') }}</span>
      <button
        class="px-3 py-1 bg-yellow-500 text-white rounded hover:bg-yellow-600 disabled:opacity-50"
        :disabled="uiFlags.isSyncing"
        @click="syncToNeuAI"
      >
        {{ uiFlags.isSyncing ? t('KNOWLEDGE_BASE.SYNCING') : t('KNOWLEDGE_BASE.SYNC_NOW') }}
      </button>
    </div>

    <div class="flex justify-between items-center mb-4">
      <h2 class="text-lg font-semibold">{{ t('KNOWLEDGE_BASE.QA_TITLE') }}</h2>
      <button
        class="px-4 py-2 bg-woot-500 text-white rounded-lg hover:bg-woot-600"
        @click="startAdd"
      >
        {{ t('KNOWLEDGE_BASE.ADD_QA') }}
      </button>
    </div>

    <!-- Edit/Add Form -->
    <div v-if="isEditing" class="mb-4 p-4 bg-slate-50 rounded-lg">
      <div class="mb-3">
        <label class="block text-sm font-medium mb-1">{{ t('KNOWLEDGE_BASE.QUESTION') }}</label>
        <textarea
          v-model="form.question"
          class="w-full p-2 border rounded-lg"
          rows="2"
        />
      </div>
      <div class="mb-3">
        <label class="block text-sm font-medium mb-1">{{ t('KNOWLEDGE_BASE.ANSWER') }}</label>
        <textarea
          v-model="form.answer"
          class="w-full p-2 border rounded-lg"
          rows="3"
        />
      </div>
      <div class="flex gap-2">
        <button
          class="px-4 py-2 bg-woot-500 text-white rounded hover:bg-woot-600"
          @click="saveQaPair"
        >
          {{ t('KNOWLEDGE_BASE.SAVE') }}
        </button>
        <button
          class="px-4 py-2 bg-slate-200 rounded hover:bg-slate-300"
          @click="cancelEdit"
        >
          {{ t('KNOWLEDGE_BASE.CANCEL') }}
        </button>
      </div>
    </div>

    <!-- Q&A List -->
    <div v-if="uiFlags.isFetchingQaPairs" class="py-8 text-center text-slate-500">
      {{ t('KNOWLEDGE_BASE.LOADING') }}
    </div>

    <div v-else-if="qaPairs.length === 0" class="py-8 text-center text-slate-500">
      {{ t('KNOWLEDGE_BASE.NO_QA_PAIRS') }}
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="qa in qaPairs"
        :key="qa.id"
        class="p-4 bg-white border rounded-lg"
      >
        <div class="flex justify-between items-start">
          <div class="flex-1">
            <p class="font-medium text-slate-900">Q: {{ qa.question }}</p>
            <p class="mt-2 text-slate-600">A: {{ qa.answer }}</p>
          </div>
          <div class="flex gap-2 ml-4">
            <button
              class="text-slate-500 hover:text-slate-700"
              @click="startEdit(qa)"
            >
              {{ t('KNOWLEDGE_BASE.EDIT') }}
            </button>
            <button
              class="text-red-500 hover:text-red-700"
              @click="deleteQaPair(qa)"
            >
              {{ t('KNOWLEDGE_BASE.DELETE') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/knowledgeBase/components/QAPairList.vue
git commit -m "feat(kbase): add QAPairList component"
```

---

### Task 21: 添加侧边栏菜单项

**Files:**
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

**Step 1: 添加菜单项**

在 `menuItems` computed 中，找到合适位置（比如 Captain 之后）添加：

```javascript
{
  name: 'Knowledge Base',
  icon: 'i-lucide-library-big',
  label: t('SIDEBAR.KNOWLEDGE_BASE'),
  children: [
    {
      name: 'Knowledge Bases',
      label: t('SIDEBAR.KNOWLEDGE_BASES'),
      to: accountScopedRoute('knowledge_bases_index'),
    },
  ],
},
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/components-next/sidebar/Sidebar.vue
git commit -m "feat(kbase): add sidebar menu item"
```

---

### Task 22: 添加 i18n 翻译

**Files:**
- Modify: `app/javascript/dashboard/i18n/locale/en/index.js` (或相关 en.json)

**Step 1: 添加翻译**

```javascript
SIDEBAR: {
  // ... 其他项
  KNOWLEDGE_BASE: 'Knowledge Base',
  KNOWLEDGE_BASES: 'Knowledge Bases',
},
KNOWLEDGE_BASE: {
  TITLE: 'Knowledge Bases',
  DESCRIPTION: 'Manage your knowledge base content for AI assistants.',
  LOADING: 'Loading...',
  EMPTY: 'No knowledge bases available. Contact your administrator to set one up.',
  NO_DESCRIPTION: 'No description',
  DOCUMENTS: 'documents',
  QA_PAIRS: 'Q&A pairs',
  TABS: {
    DOCUMENTS: 'Documents',
    QA: 'Q&A',
  },
  DOCUMENTS_TITLE: 'Documents',
  UPLOAD_DOCUMENT: 'Upload Document',
  UPLOADING: 'Uploading...',
  DOCUMENT_UPLOADED: 'Document uploaded successfully',
  UPLOAD_FAILED: 'Failed to upload document',
  NO_DOCUMENTS: 'No documents yet. Upload your first document.',
  NAME: 'Name',
  STATUS: 'Status',
  WORDS: 'Words',
  ENABLED: 'Enabled',
  ACTIONS: 'Actions',
  DELETE: 'Delete',
  CONFIRM_DELETE_DOCUMENT: 'Are you sure you want to delete this document?',
  DOCUMENT_DELETED: 'Document deleted successfully',
  QA_TITLE: 'Q&A Pairs',
  ADD_QA: 'Add Q&A',
  QUESTION: 'Question',
  ANSWER: 'Answer',
  SAVE: 'Save',
  CANCEL: 'Cancel',
  EDIT: 'Edit',
  CONFIRM_DELETE_QA: 'Are you sure you want to delete this Q&A pair?',
  NO_QA_PAIRS: 'No Q&A pairs yet. Add your first one.',
  SYNC_REQUIRED: 'You have unsaved changes. Sync to NeuAI to apply them.',
  SYNC_NOW: 'Sync Now',
  SYNCING: 'Syncing...',
  SYNC_SUCCESS: 'Successfully synced to NeuAI',
},
```

**Step 2: Commit**

```bash
git add app/javascript/dashboard/i18n/
git commit -m "feat(kbase): add i18n translations"
```

---

## 完成

所有 22 个任务完成后，Knowledge Base 功能将完整可用：

- ✅ 数据库表和 Model
- ✅ NeuAI API 客户端
- ✅ SuperAdmin 后台管理
- ✅ 用户 API
- ✅ 前端页面和组件
- ✅ 侧边栏菜单
- ✅ i18n 翻译

**测试检查清单：**
1. SuperAdmin 可以创建/编辑/删除 Knowledge Base
2. 创建时可以选择新建或绑定 NeuAI Dataset
3. 管理员可以上传文档，查看索引状态
4. 管理员可以添加/编辑/删除 Q&A
5. Q&A 同步到 NeuAI 正常工作
6. 文档状态轮询正常工作
