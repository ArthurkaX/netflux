# Contributing to Netflux

First off, thanks for taking the time to contribute!

The following is a set of guidelines for contributing to Netflux. These are mostly guidelines, not rules. Use your best judgment, and feel free to propose changes to this document in a pull request.

## Code of Conduct

This project and everyone participating in it is governed by the [Netflux Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## How Can I Contribute?

### Reporting Bugs

This section guides you through submitting a bug report for Netflux. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

- **Use the Issue Search** to see if the problem has already been reported.
- **Check if the issue has been fixed** by trying to reproduce it using the latest `master` or development branch.
- **Collect information** about the bug:
  - Stack trace (Traceback) if applicable.
  - OS, Platform and Version (Windows, Linux, CODESYS version, TIA Portal version, etc).
  - Version of the interpreter, compiler, SDK, etc.

### Suggesting Enhancements

This section guides you through submitting an enhancement suggestion for Netflux, including completely new features and minor improvements to existing functionality.

- **Use a clear and descriptive title** for the issue to identify the suggestion.
- **Provide a step-by-step description of the suggested enhancement** in as much detail as possible.
- **Describe the current behavior** and **explain which behavior you expected to see instead** and why.

### Pull Requests

1.  Fork the repo and create your branch from `master`.
2.  If you've added code that should be tested, add tests.
3.  If you've changed APIs, update the documentation.
4.  Ensure the test suite passes.
5.  Make sure your code lints.
6.  Issue that pull request!

## Styleguides

### CODESYS (ST)
- Use PascalCase for Function Blocks and Programs.
- Use Hungarian notation where appropriate (e.g., `i_` for inputs, `o_` for outputs).
- Add comments explaining complex logic.

### Python
- Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/).
- Docstrings are encouraged for all modules, classes, and functions.

### Siemens SCL
- Follow standard Siemens coding guidelines.
- Keep variable names descriptive.

Thank you for contributing!
