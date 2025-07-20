# Chatwoot 集成架构与开发指南

## 目录

1. [集成架构概述](#集成架构概述)
2. [核心组件](#核心组件)
3. [集成类型](#集成类型)
4. [如何添加新集成](#如何添加新集成)
5. [最佳实践](#最佳实践)
6. [故障排查](#故障排查)

## 集成架构概述

Chatwoot 基于模块化架构设计了一套完整的集成系统，支持多种类型的第三方服务集成：

- **消息渠道集成** - WhatsApp、Telegram、Facebook Messenger 等
- **业务工具集成** - Slack、Linear、Notion、Shopify 等
- **AI 服务集成** - OpenAI、Dialogflow、Google Translate 等
- **CRM 集成** - LeadSquared 等
- **Webhook 集成** - 自定义 webhook 事件

## 核心组件

### 1. 集成应用模型 (`Integrations::App`)

**文件位置**: `app/models/integrations/app.rb`

集成应用是所有集成的基础抽象类，提供：
- 统一的配置管理
- 多语言支持
- OAuth 认证流程
- 状态管理

```ruby
class Integrations::App
  attr_accessor :params
  
  def name
    I18n.t("integration_apps.#{params[:i18n_key]}.name")
  end
  
  def active?(account)
    # 检查集成是否在当前账户激活
  end
  
  def enabled?(account)
    # 检查集成是否已启用
  end
end
```

### 2. 集成钩子模型 (`Integrations::Hook`)

**文件位置**: `app/models/integrations/hook.rb`

集成钩子管理具体的集成实例：

```ruby
class Integrations::Hook < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true
  
  enum hook_type: { account: 0, inbox: 1 }
  enum status: { disabled: 0, enabled: 1 }
  
  validates :account_id, presence: true
  validates :app_id, presence: true
  validate :validate_settings_json_schema
end
```

**核心字段**:
- `app_id`: 集成应用标识符
- `hook_type`: 集成级别（账户级或收件箱级）
- `settings`: JSON 配置数据
- `access_token`: OAuth 访问令牌
- `status`: 集成状态

### 3. 集成配置 (`config/integration/apps.yml`)

**文件位置**: `config/integration/apps.yml`

集中管理所有集成的配置：

```yaml
openai:
  id: openai
  logo: openai.png
  i18n_key: openai
  action: /openai
  hook_type: account
  allow_multiple_hooks: false
  settings_json_schema:
    type: 'object'
    properties:
      api_key: { type: 'string' }
      label_suggestion: { type: 'boolean' }
    required: ['api_key']
  settings_form_schema:
    - label: 'API Key'
      type: 'text'
      name: 'api_key'
      validation: 'required'
```

**配置字段说明**:
- `id`: 集成唯一标识符
- `logo`: 图标文件名（存放在 `/public/dashboard/images/integrations/`）
- `i18n_key`: 国际化键名
- `action`: 外部重定向 URL 或内部路径
- `hook_type`: `account`（账户级）或 `inbox`（收件箱级）
- `allow_multiple_hooks`: 是否允许多个钩子实例
- `settings_json_schema`: JSON Schema 验证规则
- `settings_form_schema`: 前端表单配置

## 集成类型

### 1. 业务工具集成

**特点**:
- 账户级集成 (`hook_type: account`)
- 支持 OAuth 认证
- 配置复杂度中等
- 通常不允许多个实例

**示例**: Slack、Linear、Notion

**实现模式**:
```ruby
# OAuth 回调控制器
class Linear::CallbacksController < ApplicationController
  def create
    # 处理 OAuth 回调
    # 创建或更新 Integration::Hook
  end
end

# 服务类
class Linear::ProcessorService
  def initialize(hook:, event:)
    @hook = hook
    @event = event
  end
  
  def perform
    # 处理业务逻辑
  end
end
```

### 2. AI 服务集成

**特点**:
- 账户级集成
- API 密钥认证
- 配置相对简单
- 单一实例

**示例**: OpenAI、Google Translate、Dialogflow

**实现模式**:
```ruby
class Integrations::Openai::ProcessorService
  def initialize(hook:, event:)
    @hook = hook
    @event = event
  end
  
  def perform
    case @event[:name]
    when 'message_created'
      process_message_created
    end
  end
  
  private
  
  def process_message_created
    # 调用 OpenAI API
    # 处理响应
  end
end
```

### 3. 消息渠道集成

**特点**:
- 收件箱级集成
- Webhook 驱动
- 复杂的消息处理逻辑
- 支持多实例

**示例**: WhatsApp、Telegram、Facebook Messenger

**实现模式**:
```ruby
# 渠道模型
class Channel::Telegram < ApplicationRecord
  include Channelable
  
  validates :bot_token, presence: true
  
  def name
    'Telegram'
  end
end

# Webhook 控制器
class Webhooks::TelegramController < ActionController::API
  def process_payload
    Webhooks::TelegramEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end
end

# 消息处理作业
class Webhooks::TelegramEventsJob < ApplicationJob
  def perform(params)
    # 查找渠道
    # 验证请求
    # 处理消息
  end
end
```

### 4. Webhook 集成

**特点**:
- 账户级集成
- 事件订阅机制
- 支持多个 webhook URL
- 灵活的事件过滤

**配置**:
```ruby
class Webhook < ApplicationRecord
  ALLOWED_WEBHOOK_EVENTS = %w[
    conversation_status_changed
    conversation_updated
    conversation_created
    contact_created
    contact_updated
    message_created
    message_updated
  ].freeze
end
```

## 如何添加新集成

### 步骤 1: 确定集成类型

首先确定您要添加的集成类型：

- **业务工具集成**: 如项目管理、CRM、通信工具
- **AI 服务集成**: 如翻译、情感分析、智能客服
- **消息渠道集成**: 如新的即时通讯平台
- **自定义 Webhook 集成**: 如自定义事件通知

### 步骤 2: 配置集成应用

在 `config/integration/apps.yml` 中添加配置：

```yaml
your_integration:
  id: your_integration
  logo: your_integration.png
  i18n_key: your_integration
  action: /your_integration  # 或外部 OAuth URL
  hook_type: account  # 或 inbox
  allow_multiple_hooks: false
  feature_flag: your_integration_enabled  # 可选
  settings_json_schema:
    type: 'object'
    properties:
      api_key: { type: 'string' }
      webhook_url: { type: 'string' }
    required: ['api_key']
  settings_form_schema:
    - label: 'API Key'
      type: 'text'
      name: 'api_key'
      validation: 'required'
    - label: 'Webhook URL'
      type: 'text'
      name: 'webhook_url'
      validation: 'url'
  visible_properties: ['api_key', 'webhook_url']
```

### 步骤 3: 添加多语言支持

在 `config/locales/en.yml` 中添加翻译：

```yaml
en:
  integration_apps:
    your_integration:
      name: "Your Integration"
      description: "Connect your service with Chatwoot"
      short_description: "Sync data automatically"
```

### 步骤 4: 添加集成图标

将集成图标放置在 `/public/dashboard/images/integrations/your_integration.png`

### 步骤 5: 实现处理服务

创建处理服务类：

```ruby
# app/services/your_integration/processor_service.rb
class YourIntegration::ProcessorService
  def initialize(hook:, event:)
    @hook = hook
    @event = event
    @settings = @hook.settings
  end
  
  def perform
    case @event[:name]
    when 'conversation_created'
      handle_conversation_created
    when 'message_created'
      handle_message_created
    end
  end
  
  private
  
  def handle_conversation_created
    # 实现对话创建事件处理
    api_client.create_ticket(
      title: @event.dig(:data, :conversation, :display_id),
      description: build_description
    )
  end
  
  def handle_message_created
    # 实现消息创建事件处理
  end
  
  def api_client
    @api_client ||= YourIntegration::ApiClient.new(
      api_key: @settings['api_key'],
      webhook_url: @settings['webhook_url']
    )
  end
end
```

### 步骤 6: 更新集成钩子处理

在 `app/models/integrations/hook.rb` 中添加事件处理：

```ruby
def process_event(event)
  case app_id
  when 'openai'
    Integrations::Openai::ProcessorService.new(hook: self, event: event).perform
  when 'your_integration'
    YourIntegration::ProcessorService.new(hook: self, event: event).perform
  else
    { error: 'No processor found' }
  end
end
```

### 步骤 7: 添加 OAuth 支持（如需要）

如果集成需要 OAuth 认证：

1. **添加回调控制器**:
```ruby
# app/controllers/your_integration/callbacks_controller.rb
class YourIntegration::CallbacksController < ApplicationController
  def create
    # 处理 OAuth 回调
    access_token = exchange_code_for_token(params[:code])
    
    hook = Current.account.hooks.find_or_create_by(app_id: 'your_integration')
    hook.update!(
      access_token: access_token,
      status: 'enabled'
    )
    
    redirect_to integrations_path, notice: 'Integration connected successfully'
  end
  
  private
  
  def exchange_code_for_token(code)
    # 实现 OAuth 令牌交换
  end
end
```

2. **添加路由**:
```ruby
# config/routes.rb
namespace :your_integration do
  resource :callbacks, only: [:create]
end
```

3. **更新集成应用模型**:
```ruby
# app/models/integrations/app.rb
def action
  case params[:id]
  when 'your_integration'
    build_oauth_url
  else
    params[:action]
  end
end

private

def build_oauth_url
  client_id = GlobalConfigService.load('YOUR_INTEGRATION_CLIENT_ID')
  redirect_uri = "#{ENV['FRONTEND_URL']}/your_integration/callback"
  
  "https://api.yourservice.com/oauth/authorize?client_id=#{client_id}&redirect_uri=#{redirect_uri}&scope=read,write"
end
```

### 步骤 8: 添加 API 客户端

创建 API 客户端类：

```ruby
# lib/your_integration/api_client.rb
class YourIntegration::ApiClient
  def initialize(api_key:, webhook_url: nil)
    @api_key = api_key
    @webhook_url = webhook_url
    @base_url = 'https://api.yourservice.com'
  end
  
  def create_ticket(title:, description:)
    response = HTTParty.post(
      "#{@base_url}/tickets",
      headers: headers,
      body: {
        title: title,
        description: description
      }.to_json
    )
    
    handle_response(response)
  end
  
  private
  
  def headers
    {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    }
  end
  
  def handle_response(response)
    if response.success?
      JSON.parse(response.body)
    else
      raise "API Error: #{response.code} - #{response.body}"
    end
  end
end
```

### 步骤 9: 添加后台作业（如需要）

对于需要异步处理的集成：

```ruby
# app/jobs/your_integration/sync_job.rb
class YourIntegration::SyncJob < ApplicationJob
  def perform(hook_id, data)
    hook = Integrations::Hook.find(hook_id)
    service = YourIntegration::ProcessorService.new(hook: hook, event: data)
    service.perform
  rescue StandardError => e
    Rails.logger.error "YourIntegration sync failed: #{e.message}"
    # 可选：重试逻辑或错误通知
  end
end
```

### 步骤 10: 添加功能开关（可选）

如果集成需要功能开关：

1. **在配置中添加 feature_flag**:
```yaml
your_integration:
  feature_flag: your_integration_enabled
```

2. **在 `config/features.yml` 中定义**:
```yaml
your_integration_enabled:
  description: "Enable Your Integration"
  default: false
```

### 步骤 11: 测试集成

1. **单元测试**:
```ruby
# spec/services/your_integration/processor_service_spec.rb
RSpec.describe YourIntegration::ProcessorService do
  let(:hook) { create(:integrations_hook, app_id: 'your_integration') }
  let(:event) { { name: 'conversation_created', data: { conversation: conversation } } }
  let(:service) { described_class.new(hook: hook, event: event) }
  
  describe '#perform' do
    it 'processes conversation created event' do
      expect(service.perform).to be_successful
    end
  end
end
```

2. **集成测试**:
```ruby
# spec/controllers/your_integration/callbacks_controller_spec.rb
RSpec.describe YourIntegration::CallbacksController do
  describe 'POST #create' do
    it 'creates integration hook' do
      post :create, params: { code: 'oauth_code' }
      expect(response).to redirect_to(integrations_path)
    end
  end
end
```

## 最佳实践

### 1. 错误处理

- **优雅降级**: 集成失败不应影响核心功能
- **重试机制**: 对暂时性错误实现指数退避重试
- **错误日志**: 详细记录错误信息便于调试

```ruby
def perform
  retry_count = 0
  begin
    api_client.sync_data
  rescue Net::TimeoutError, Net::ConnectTimeError => e
    retry_count += 1
    if retry_count < 3
      sleep(2 ** retry_count)
      retry
    else
      Rails.logger.error "Integration failed after 3 retries: #{e.message}"
    end
  end
end
```

### 2. 安全最佳实践

- **令牌加密**: 敏感数据使用 Rails 加密存储
- **权限控制**: 验证用户权限和账户访问
- **输入验证**: 严格验证所有输入数据
- **Webhook 验证**: 验证 webhook 签名确保来源可信

```ruby
class Integrations::Hook < ApplicationRecord
  encrypts :access_token
  
  validates :settings, presence: true
  validate :validate_settings_json_schema
  
  before_save :sanitize_settings
  
  private
  
  def sanitize_settings
    self.settings = settings.deep_transform_keys(&:to_s)
  end
end
```

### 3. 性能优化

- **异步处理**: Webhook 事件使用后台作业处理
- **批量操作**: 支持批量数据同步
- **缓存策略**: 缓存频繁访问的数据
- **限流**: 实现 API 调用限流

```ruby
class YourIntegration::ProcessorService
  include Redis::Objects
  
  counter :api_calls, expiration: 1.hour
  
  def perform
    return if rate_limited?
    
    api_calls.increment
    # 处理业务逻辑
  end
  
  private
  
  def rate_limited?
    api_calls.value >= 1000  # 每小时 1000 次调用限制
  end
end
```

### 4. 监控和可观测性

- **指标收集**: 记录成功率、响应时间等指标
- **健康检查**: 定期检查集成状态
- **告警机制**: 异常情况及时通知

```ruby
class YourIntegration::HealthCheckService
  def self.check
    hooks = Integrations::Hook.where(app_id: 'your_integration', status: 'enabled')
    
    hooks.map do |hook|
      {
        id: hook.id,
        status: check_hook_health(hook),
        last_sync: hook.updated_at
      }
    end
  end
  
  def self.check_hook_health(hook)
    api_client = YourIntegration::ApiClient.new(api_key: hook.settings['api_key'])
    api_client.health_check
    'healthy'
  rescue StandardError
    'unhealthy'
  end
end
```

## 故障排查

### 常见问题

1. **集成不显示**
   - 检查 `config/integration/apps.yml` 配置
   - 确认 `feature_flag` 已启用
   - 验证图标文件存在

2. **OAuth 认证失败**
   - 检查客户端 ID 和密钥配置
   - 验证回调 URL 设置
   - 确认权限范围正确

3. **Webhook 事件丢失**
   - 检查 Sidekiq 队列状态
   - 验证事件订阅配置
   - 确认 webhook URL 可访问

4. **API 调用失败**
   - 检查 API 密钥有效性
   - 验证网络连接
   - 确认 API 限流设置

### 调试工具

1. **日志查看**:
```bash
# 查看集成相关日志
tail -f log/development.log | grep "YourIntegration"

# 查看 Sidekiq 作业
bundle exec sidekiq -e development
```

2. **Rails 控制台调试**:
```ruby
# 查找集成钩子
hook = Integrations::Hook.find_by(app_id: 'your_integration')

# 测试 API 调用
api_client = YourIntegration::ApiClient.new(api_key: hook.settings['api_key'])
api_client.health_check

# 手动触发事件处理
event = { name: 'conversation_created', data: { conversation: conversation } }
service = YourIntegration::ProcessorService.new(hook: hook, event: event)
service.perform
```

3. **监控面板**:
- Sidekiq Web UI: `/sidekiq`
- 集成状态: `/app/accounts/{account_id}/settings/integrations`

---

通过遵循这个指南，您可以成功地在 Chatwoot 中添加新的集成。记住始终遵循现有的代码模式和最佳实践，确保集成的安全性、性能和可维护性。