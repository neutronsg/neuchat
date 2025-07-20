# Chatwoot Project Overview

## Purpose
Chatwoot is a modern, open-source customer support platform designed as an alternative to Intercom, Zendesk, and Salesforce Service Cloud. It centralizes customer conversations across multiple channels (live chat, email, social media, messaging platforms) into a unified inbox.

## Tech Stack
- **Backend**: Ruby on Rails 7.1 (Ruby 3.4.4)
- **Frontend**: Vue.js 3 with Composition API, Vuex store, Vue Router
- **Styling**: Tailwind CSS (exclusively - no custom CSS/SCSS allowed)
- **Build Tools**: Vite, pnpm, Webpack alternative
- **Database**: PostgreSQL (implied from Rails setup)
- **Testing**: RSpec (Ruby), Vitest (JavaScript)
- **Process Management**: Overmind for development

## Key Features
- Omnichannel support (chat, email, social media, messaging)
- AI Agent (Captain) for automated responses
- Help center portal
- Team collaboration tools
- Integrations with Slack, Dialogflow, Linear, Shopify, etc.
- Real-time messaging with ActionCable
- Multi-language support

## Architecture
- Monolithic Rails application with Vue.js frontend
- WebSocket integration for real-time features
- RESTful API design
- Service-oriented architecture within Rails app
- Enterprise features in separate namespace