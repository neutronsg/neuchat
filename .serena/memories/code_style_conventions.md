# Code Style and Conventions

## Ruby Style
- Follow RuboCop rules strictly
- 150 character max line length
- Use compact `module/class` definitions; avoid nested styles
- Strong params validation in controllers
- Custom exceptions in `lib/custom_exceptions/`
- Model validations: validate presence/uniqueness, add proper indexes

## Vue.js/JavaScript Style
- **API**: Always use Composition API with `<script setup>` at the top
- **Components**: Use PascalCase for component names
- **Events**: Use camelCase
- **Linting**: ESLint with Airbnb base + Vue 3 recommended rules
- **Type Safety**: Use PropTypes in Vue
- **Imports**: Prefer components from `components-next/` for message bubbles

## Styling Rules (CRITICAL)
- **Tailwind Only**: Do not write custom CSS, scoped CSS, or inline styles
- **Always use Tailwind utility classes**
- **Colors**: Refer to `tailwind.config.js` for color definitions
- No SCSS except for legacy code

## General Guidelines
- MVP focus: least code change, happy-path only
- No unnecessary defensive programming
- Break down complex tasks into small, testable units
- Remove dead/unreachable/unused code
- Don't write multiple versions - pick the best approach
- Clear, descriptive naming with consistent casing

## Internationalization
- **No bare strings** in templates; use i18n
- **Backend i18n**: Update `en.yml` only (community handles other languages)
- **Frontend i18n**: Update `en.json` only
- Other languages handled by community via Crowdin