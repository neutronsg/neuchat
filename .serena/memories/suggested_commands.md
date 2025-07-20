# Development Commands

## Setup Commands
```bash
# Initial setup
bundle install && pnpm install

# Run development server
pnpm dev
# OR
overmind start -f ./Procfile.dev

# Run tests
pnpm test                    # JavaScript tests
pnpm test:watch             # JavaScript tests in watch mode
bundle exec rspec           # Ruby tests
bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER  # Single test
```

## Code Quality
```bash
# JavaScript/Vue linting
pnpm eslint                 # Check
pnpm eslint:fix            # Fix automatically

# Ruby linting
bundle exec rubocop -a     # Check and auto-fix

# Ruby prettier formatting
pnpm ruby:prettier
```

## Build & Deploy
```bash
# Build for production
pnpm build:sdk

# Size analysis
pnpm size
```

## Development Tools
```bash
# Story development (Histoire)
pnpm story:dev
pnpm story:build
pnpm story:preview

# I18n sync
pnpm sync:i18n
```

## Process Management
```bash
# Development (recommended)
overmind start -f ./Procfile.dev

# Test environment
RAILS_ENV=test foreman start -f ./Procfile.test
```