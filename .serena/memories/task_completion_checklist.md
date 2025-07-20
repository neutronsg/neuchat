# Task Completion Checklist

## Before Committing
1. **Run linting and fix issues**
   ```bash
   pnpm eslint:fix     # JavaScript/Vue
   bundle exec rubocop -a  # Ruby
   ```

2. **Run relevant tests**
   ```bash
   pnpm test          # JavaScript tests
   bundle exec rspec  # Ruby tests (or specific test files)
   ```

3. **Verify functionality**
   - Test the specific feature/fix manually
   - Check for regressions in related functionality

## Git Workflow
- Base branch: `develop` (NOT main)
- Use git-flow branching model
- Don't reference Claude in commit messages
- Create meaningful commit messages focusing on "why" not "what"

## Code Quality Checks
- Remove any dead/unused code
- Ensure proper error handling
- Validate all user inputs
- Check for security implications
- Verify accessibility requirements

## Documentation
- Update relevant documentation if API changes
- Add/update comments for complex logic
- Ensure i18n strings are properly added to en.yml/en.json

## Final Verification
- Feature works in development environment
- No console errors or warnings
- Code follows project conventions
- Tests pass
- Linting passes