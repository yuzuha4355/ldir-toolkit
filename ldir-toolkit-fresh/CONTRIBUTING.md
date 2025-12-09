# Contributing to LDIR-Toolkit

Thank you for your interest in contributing to LDIR-Toolkit! This document provides guidelines for contributing to the project.

## 🌟 How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:
- Clear description of the bug
- Steps to reproduce
- Expected behavior vs. actual behavior
- Environment details (Linux distribution, version, etc.)
- Relevant log excerpts

### Suggesting Enhancements

Feature requests are welcome! Please include:
- Clear description of the feature
- Use case / motivation
- Potential implementation approach (if you have ideas)

### Pull Requests

1. **Fork the repository**
   ```bash
   git clone https://github.com/yourusername/ldir-toolkit.git
   cd ldir-toolkit
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the existing code style
   - Add comments for complex logic
   - Update documentation if needed

3. **Test your changes**
   ```bash
   cd docker-test
   ./test-single.sh ubuntu  # Test on Ubuntu
   ./test-single.sh debian  # Test on Debian
   ./test-single.sh rocky   # Test on Rocky
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add support for XYZ distribution"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a Pull Request on GitHub.

## 📝 Code Style Guidelines

### Shell Script Style

- Use `#!/bin/bash` shebang
- Use 4-space indentation
- Quote variables: `"${variable}"` not `$variable`
- Use `[[ ]]` for conditionals, not `[ ]`
- Check command existence: `command -v cmd >/dev/null 2>&1`
- Use functions for reusable code
- Add comments for non-obvious logic

### Module Structure

Collection modules should follow this pattern:

```bash
#!/bin/bash

# Module: XX_module_name.sh
# Description: Brief description
# Output: /path/to/output/directory

MODULE_NAME="module_name"
OUTPUT_DIR="${OUTPUT_BASE}/${MODULE_NAME}"

collect_module_name() {
    log_info "Collecting ${MODULE_NAME} data..."
    
    # Create output directory
    mkdir -p "${OUTPUT_DIR}"
    
    # Collection logic here
    if [[ -f /path/to/artifact ]]; then
        safe_copy /path/to/artifact "${OUTPUT_DIR}/"
    fi
    
    log_info "${MODULE_NAME} collection completed"
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    collect_module_name
fi
```

### Commit Message Convention

Use conventional commits format:

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Test additions or changes
- `chore:` - Maintenance tasks

Examples:
```
feat: add support for openSUSE Tumbleweed
fix: correct path detection for Alpine Linux
docs: update README with new module documentation
```

## 🧪 Testing

### Local Testing

1. **Docker environment** (recommended):
   ```bash
   cd docker-test
   ./test-single.sh ubuntu
   ```

2. **Manual testing**:
   ```bash
   cd ldir-toolkit
   sudo ./ldir-collect.sh /tmp/test_output
   ls -la /tmp/test_output/
   ```

### Test Checklist

Before submitting a PR, verify:
- [ ] Code runs without errors on Ubuntu 22.04
- [ ] Code runs without errors on Debian 12
- [ ] Code runs without errors on Rocky Linux 9
- [ ] All modules execute successfully
- [ ] Output directory structure is correct
- [ ] manifest.txt and file_hashes.txt are generated
- [ ] execution.log contains no ERROR entries
- [ ] Documentation is updated if needed

## 🏗️ Project Structure

```
ldir-toolkit/
├── ldir-toolkit/              # Main toolkit
│   ├── ldir-collect.sh        # Main collection script
│   ├── lib/                   # Library functions
│   │   ├── common.sh
│   │   ├── detect_distro.sh
│   │   └── detect_distro_advanced.sh
│   ├── modules/               # Collection modules
│   │   ├── 10_system_info.sh
│   │   ├── 20_logs.sh
│   │   ├── ...
│   │   └── 91_cloud_metadata.sh
│   └── config/                # Configuration files
├── docker-test/               # Docker test environment
│   ├── Dockerfile.*           # Distribution-specific Dockerfiles
│   ├── docker-compose.yml
│   ├── test-single.sh
│   └── test-all-extended.sh
├── docs/                      # Documentation
├── README.md
├── LICENSE
└── CONTRIBUTING.md
```

## 🎯 Areas for Contribution

### High Priority
- [ ] Add support for more distributions (e.g., Void Linux, NixOS)
- [ ] Improve error handling and recovery
- [ ] Enhance cloud metadata collection (Oracle Cloud, DigitalOcean, etc.)
- [ ] Add result analysis scripts
- [ ] Improve documentation translations

### Medium Priority
- [ ] Add GUI interface for result viewing
- [ ] Create automated timeline generator
- [ ] Add filtering options (collect only specific modules)
- [ ] Implement incremental collection mode
- [ ] Add compression options

### Low Priority
- [ ] Windows WSL optimization
- [ ] macOS compatibility layer
- [ ] Integration with popular SIEM platforms
- [ ] Real-time monitoring mode

## 📚 Resources

- [Bash Best Practices](https://google.github.io/styleguide/shellguide.html)
- [Linux Forensics Documentation](https://www.forensicswiki.org/)
- [Docker Documentation](https://docs.docker.com/)

## 🤝 Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Respect different perspectives and experiences

## ❓ Questions?

If you have questions:
1. Check existing [Issues](https://github.com/yourusername/ldir-toolkit/issues)
2. Check [Discussions](https://github.com/yourusername/ldir-toolkit/discussions)
3. Create a new Discussion thread

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to LDIR-Toolkit! 🎉
