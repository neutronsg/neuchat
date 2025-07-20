# Codebase Structure

## Backend Structure (Ruby on Rails)
```
app/
├── controllers/api/v1/               # API controllers
│   └── accounts/integrations/        # Integration endpoints
├── models/integrations/              # Integration models
├── services/                         # Business logic services
└── jobs/                            # Background jobs

lib/integrations/                     # Integration processors
├── openai/                          # OpenAI integration
├── slack/                           # Slack integration
└── dialogflow/                      # Dialogflow integration

enterprise/                          # Enterprise-only features
├── app/services/captain/            # AI features
└── lib/captain/                     # Captain AI agent

config/
├── routes.rb                        # Route definitions
└── integration/apps.yml             # Integration app configurations
```

## Frontend Structure (Vue.js)
```
app/javascript/
├── dashboard/                       # Main dashboard app
│   ├── api/                        # API clients
│   │   └── integrations/           # Integration API clients
│   ├── components/                 # Vue components
│   ├── store/                      # Vuex store modules
│   └── routes/                     # Vue Router definitions
├── shared/                         # Shared utilities
└── v3/                            # New version components
```

## Key Directories
- `spec/` - Test files (RSpec + Vitest)
- `public/` - Static assets
- `db/` - Database migrations and schema
- `docs/` - Documentation
- `.github/` - GitHub workflows and templates