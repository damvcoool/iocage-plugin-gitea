# Contributing to iocage-plugin-gitea

Thank you for your interest in contributing to the Gitea TrueNAS plugin! This document provides guidelines and instructions for contributing.

## Development Setup

1. Fork the repository
2. Clone your fork locally
3. Create a new branch for your feature or fix
4. Make your changes
5. Test your changes in a TrueNAS environment

## Testing

Before submitting a pull request:

1. Test installation on a fresh TrueNAS Core 13 system
2. Verify all scripts run without errors using `shellcheck`
3. Test upgrade scenarios if modifying `post_upgrade.sh`
4. Verify the health check script runs successfully
5. Test backup and restore functionality

### Running ShellCheck

```bash
shellcheck post_install.sh post_upgrade.sh health-check.sh gitea-backup.sh pluginget pluginset
```

## Code Style

- Use consistent indentation (tabs or 4 spaces)
- Follow POSIX shell script standards when possible
- Add comments for complex logic
- Use meaningful variable names
- Keep functions focused and single-purpose

## Shell Script Best Practices

1. Always use `set -e` at the beginning of scripts to exit on errors
2. Quote variables to prevent word splitting: `"$variable"`
3. Use `shellcheck` to validate scripts before committing
4. Provide helpful error messages
5. Log important operations for debugging
6. Make scripts idempotent when possible

## Commit Messages

- Use clear, descriptive commit messages
- Start with a verb in present tense (Add, Fix, Update, etc.)
- Keep the first line under 72 characters
- Add detailed explanation in the body if needed

Examples:
```
Add backup and restore functionality
Fix database connection issue in health check
Update README with troubleshooting section
```

## Pull Request Process

1. Update the README.md with details of changes if applicable
2. Ensure all scripts pass shellcheck validation
3. Test in a TrueNAS environment if possible
4. Update documentation for new features
5. Request review from maintainers

## Feature Requests and Bug Reports

- Use GitHub Issues for bug reports and feature requests
- Provide detailed information about your environment
- Include steps to reproduce for bugs
- For feature requests, explain the use case and benefits

## Questions?

Feel free to open an issue for questions or clarifications about contributing.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
