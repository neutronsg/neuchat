# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- MVP focus: Least code change, happy-path only
- No unnecessary defensive programming
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Don't reference Claude in commit messages
- when you use a library, first check the docs with context7

## Project-Specific

- **Translations**:
  - Only update `en.yml` and `en.json`
  - Other languages are handled by the community
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## 集成开发参考

本项目包含完整的集成架构文档，位于 `docs/INTEGRATIONS.md`，包含：

- **集成架构概述和核心组件** - `Integrations::App`、`Integrations::Hook`、配置管理
- **4种集成类型的详细实现模式** - 业务工具、AI服务、消息渠道、Webhook集成
- **添加新集成的完整指南** - 从配置到测试的11步详细流程
- **安全、性能、监控最佳实践** - 错误处理、令牌管理、限流、健康检查
- **常见问题故障排查指南** - OAuth认证失败、Webhook丢失、API调用问题等

在开发集成相关功能时，请参考此文档确保遵循项目架构模式。集成系统支持：
- 消息渠道：WhatsApp、Telegram、Facebook Messenger 等
- 业务工具：Slack、Linear、Notion、Shopify 等  
- AI服务：OpenAI、Dialogflow、Google Translate 等
- CRM系统：LeadSquared 等

### OpenAI 集成深度分析

项目还包含 OpenAI 集成的详细实现分析，位于 `docs/OPENAI_INTEGRATION_ANALYSIS.md`，深度解析：

- **连接状态检测机制** - 前后端如何判断 OpenAI 是否已连接配置
- **完整功能列表和使用场景** - Reply Suggestion、消息重写、对话摘要等
- **后端代理架构模式** - 安全的 API 调用流程和数据处理
- **Reply Suggestion 完整流程** - 从用户点击到 AI 响应的 10 步详细流程
- **性能优化和安全机制** - 缓存策略、令牌限制、权限控制

开发 AI 相关功能时请参考此分析文档了解具体实现细节和最佳实践。

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md
