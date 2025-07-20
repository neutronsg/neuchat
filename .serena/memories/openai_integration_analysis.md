# OpenAI Integration Implementation Analysis

## Configuration & Setup
OpenAI integration is configured in `config/integration/apps.yml`:
- **App ID**: `openai`
- **Hook Type**: `account` (account-scoped, not inbox-specific)
- **Settings Required**: `api_key` (required), `label_suggestion` (boolean, optional)
- **Multiple Hooks**: Not allowed (single OpenAI integration per account)

## Backend Architecture

### Models
- **Integration Hook**: `app/models/integrations/hook.rb`
  - Handles OpenAI hook validation and event processing
  - Calls `Integrations::Openai::ProcessorService` for OpenAI events

### Service Classes
- **Base Service**: `lib/integrations/openai_base_service.rb`
  - Token limit: 400,000 characters (for gpt-4o-mini 128k context)
  - API URL: `https://api.openai.com/v1/chat/completions`
  - Model: `ENV['OPENAI_GPT_MODEL']` (default: `gpt-4o-mini`)
  - Caching support with Redis

- **Processor Service**: `lib/integrations/openai/processor_service.rb`
  - Handles specific OpenAI operations
  - Supports conversation context with message history
  - Operations: reply_suggestion, summarize, rephrase, fix_spelling_grammar, shorten, expand, make_friendly, make_formal, simplify

### API Flow
1. Frontend calls `/api/v1/accounts/{account_id}/integrations/hooks/{hook_id}/process_event`
2. Controller: `Api::V1::Accounts::Integrations::HooksController#process_event`
3. Hook model calls `Integrations::Openai::ProcessorService.new(hook: self, event: event).perform`
4. Service makes HTTP request to OpenAI API with conversation context
5. Response returned to frontend

## Frontend Integration

### API Client
- **File**: `app/javascript/dashboard/api/integrations/openapi.js`
- **Class**: `OpenAIAPI extends ApiClient`
- **Methods**: `processEvent({ type, content, tone, conversationId, hookId })`
- **Event Types**: 
  - **Conversation events**: `summarize`, `reply_suggestion`, `label_suggestion`
  - **Message events**: `rephrase`

### Data Flow for Reply Suggestions
1. User clicks generate button in conversation interface
2. Frontend calls `OpenAIAPI.processEvent()` with:
   - `type: 'reply_suggestion'`
   - `conversationId: conversation.display_id`
   - `hookId: openai_hook.id`
3. Backend retrieves conversation messages (incoming/outgoing, non-private)
4. Messages formatted and sent to OpenAI with system prompt from `lib/integrations/openai/openai_prompts/reply.txt`
5. OpenAI response returned to frontend

## Configuration Determination
- **OpenAI Connected**: Check if account has hook with `app_id: 'openai'` and valid `api_key` in settings
- **Feature Access**: No feature flag required (always available if configured)
- **Settings Validation**: JSON schema validates required `api_key` field

## Enterprise Features
- Enterprise version has additional OpenAI integrations in `enterprise/` namespace
- Captain AI agent uses OpenAI for advanced features
- Enhanced prompts available in `enterprise/lib/enterprise/integrations/openai_prompts/`