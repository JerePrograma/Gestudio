# Gestudio historical steering documents

> Historical, non-authoritative guidance. The implemented system and current
> rules are defined by `AGENTS.md`, the code, Flyway migrations, and the
> operations documentation. In particular, Gestudio is currently a layered
> modular monolith; the hexagonal structure described below is aspirational.

**Purpose**: Define standards, best practices, and guidelines for consistent codebase development  
**Effective Date**: February 16, 2026  
**Owner**: Development Team  

---

## 📋 Steering Documents

### 1. [PROGRAMMING_PRACTICES.md](PROGRAMMING_PRACTICES.md)
**Focus**: Code quality, style, and fundamentals

**Key Topics**:
- ✅ KISS Principle (Keep It Simple, Stupid)
- ✅ Code Conciseness (line/method limits)
- ✅ Short Variable Names (context-based guidance)
- ✅ Short Methods (extracting helpers, early returns)
- ✅ Documented Code (JavaDoc, comments)
- ✅ Java Conventions (naming, style, best practices)
- ✅ Avoiding Warnings (compiler cleanliness)
- ✅ Always Create/Update Tests
- ✅ Hexagonal/Clean/Ports-and-Adapter Architecture
- ✅ Code Review Checklist

**When to Reference**: 
- Writing new classes or methods
- Code review of colleagues
- Refactoring legacy code
- Setting up IDE/linter rules

**Quick Links**:
- [KISS Principle Rules](PROGRAMMING_PRACTICES.md#1-kiss-principle-keep-it-simple-stupid)
- [Conciseness Guidelines](PROGRAMMING_PRACTICES.md#2-code-conciseness)
- [Short Variable Names](PROGRAMMING_PRACTICES.md#3-short-variable-names)
- [Short Methods](PROGRAMMING_PRACTICES.md#4-short-methods)
- [Java Conventions](PROGRAMMING_PRACTICES.md#6-follow-java-conventions)

---

### 2. [ARCHITECTURE.md](ARCHITECTURE.md)
**Focus**: System design, layering, and architectural patterns

**Key Topics**:
- ✅ Hexagonal Architecture Overview
- ✅ Layering Rules (Domain, Ports, Services, Infrastructure, Controllers)
- ✅ Dependency Flow Rules
- ✅ Design Patterns (Service, Repository, Factory, Builder, Strategy, Adapter, Domain Event)
- ✅ Package Organization
- ✅ Domain-Driven Design (DDD) Principles
- ✅ SOLID Principles Application
- ✅ Exception Handling Strategy
- ✅ Data Flow & DTOs
- ✅ Transaction & Concurrency
- ✅ Configuration Management
- ✅ Architecture Decision Log (ADL)

**When to Reference**:
- Designing new features
- Planning service/repository structure
- Understanding system boundaries
- Making architectural decisions
- Code review for architecture fit

**Quick Links**:
- [Layer Responsibilities](ARCHITECTURE.md#2-layering-rules)
- [Package Structure](ARCHITECTURE.md#4-package-organization)
- [Design Patterns Guide](ARCHITECTURE.md#3-design-patterns--when-to-use)
- [SOLID Principles](ARCHITECTURE.md#6-solid-principles-application)
- [Exception Strategy](ARCHITECTURE.md#7-exception-handling-strategy)

---

### 3. [TESTING_STANDARDS.md](TESTING_STANDARDS.md)
**Focus**: Test creation, coverage, and quality standards

**Key Topics**:
- ✅ Testing Mandate (non-negotiable rules)
- ✅ Test Types (Unit, Integration, Controller, Repository, Adapter)
- ✅ Test Coverage Requirements (by layer and project)
- ✅ Test Naming Conventions
- ✅ Mocking & Test Doubles
- ✅ Parameterized Tests
- ✅ Test Organization (AAA pattern)
- ✅ Testing Anti-Patterns
- ✅ CI/CD Testing Integration
- ✅ Test Maintenance
- ✅ Code Review Checklist

**When to Reference**:
- Writing tests for new features
- Verifying test coverage
- Code review of tests
- Fixing flaky tests
- Setting up CI/CD

**Quick Links**:
- [Testing Mandate](TESTING_STANDARDS.md#1-testing-mandate)
- [Test Types & Examples](TESTING_STANDARDS.md#2-test-types--where-to-write-them)
- [Coverage Requirements](TESTING_STANDARDS.md#3-test-coverage-requirements)
- [Naming Convention](TESTING_STANDARDS.md#4-test-naming-convention)
- [Test Anti-Patterns](TESTING_STANDARDS.md#8-testing-anti-patterns)

---

## 🎯 Usage Guide

### Getting Started

1. **New Developer**: Read all three documents in order
   - PROGRAMMING_PRACTICES.md (foundation)
   - ARCHITECTURE.md (system design)
   - TESTING_STANDARDS.md (quality assurance)

2. **Writing Code**: Reference PROGRAMMING_PRACTICES.md
   - Keep methods short
   - Use clear naming
   - Document with JavaDoc
   - Follow Java conventions

3. **Designing Features**: Reference ARCHITECTURE.md
   - Understand layering
   - Choose appropriate patterns
   - Apply SOLID principles
   - Plan exception handling

4. **Writing Tests**: Reference TESTING_STANDARDS.md
   - Determine test type
   - Follow naming conventions
   - Use AAA pattern
   - Meet coverage requirements

### Quick Decision Tree

```
"How should I structure this feature?"
├─ Check ARCHITECTURE.md: Layering Rules
└─ Check ARCHITECTURE.md: Package Organization

"Is my code following standards?"
├─ Check PROGRAMMING_PRACTICES.md: Code Review Checklist
└─ Check IDE warnings and compilation

"What tests do I need to write?"
├─ Check TESTING_STANDARDS.md: Test Types
└─ Check TESTING_STANDARDS.md: Coverage Requirements

"How do I name this method?"
├─ Check PROGRAMMING_PRACTICES.md: Java Conventions
└─ Check TESTING_STANDARDS.md: Test Naming (if test)

"Should I use a Pattern here?"
├─ Check ARCHITECTURE.md: Design Patterns
└─ Check if it solves actual problem
```

---

## 📊 Key Statistics & Thresholds

### Code Metrics

| Metric | Limit | Standard |
|--------|-------|----------|
| Method Length | 50 lines | 10-20 lines |
| Class Length | 500 lines | 200-300 lines |
| Line Length | 120 chars | 80-100 chars |
| Method Parameters | 5 | 2-3 preferred |
| Nesting Depth | 3 levels | 2 preferred |

### Test Coverage

| Layer | Minimum | Target |
|-------|---------|--------|
| Domain/Business | 85% | 95%+ |
| Services | 70% | 85%+ |
| Repositories | 70% | 80%+ |
| Controllers | 60% | 75%+ |
| Overall | 50% | 70%+ |

### Code Review Time Targets

- Small PR (< 100 lines): 15-30 minutes
- Medium PR (100-500 lines): 45-90 minutes
- Large PR (> 500 lines): Schedule separate meeting

---

## ✅ Enforcement Mechanisms

### Pre-Commit (Local)

```bash
#!/bin/bash
cd backend
mvn clean compile -q        # Must compile without warnings
mvn test -q                 # All tests must pass
```

### Pre-Push (GitHub)

- PR must have at least 1 approval
- All CI checks must pass
- Coverage cannot decrease
- No commented-out code

### CI/CD (Automated)

```bash
mvn clean compile       # Fail on warnings
mvn test               # All tests pass
mvn jacoco:report      # Coverage report
```

---

## 🔍 Self-Assessment

### For Individual Contributors

Use this checklist weekly:

- [ ] Code compiles without warnings
- [ ] All tests passing locally
- [ ] Methods average < 20 lines
- [ ] Classes average < 300 lines
- [ ] JavaDoc on all public APIs
- [ ] No TODO/FIXME comments without issues
- [ ] Following SOLID principles

### For Team Leads

Use this checklist quarterly:

- [ ] Team awareness of steering docs (>80%)
- [ ] Overall coverage increasing
- [ ] Methods staying within limits
- [ ] Architecture consistency
- [ ] Test quality high (low flakiness)
- [ ] Onboarding time decreasing

---

## 📚 Document Hierarchy

```
.kiro/steering/                          ← You are here
├── PROGRAMMING_PRACTICES.md   (Fundamentals)
├── ARCHITECTURE.md            (Design)
├── TESTING_STANDARDS.md       (Quality)
└── INDEX.md                   (This file)

Related Files:
├── TESTING.md                 (Project test progress)
├── TESTING_QUICKSTART.md      (Quick reference)
└── README.md                  (Project overview)
```

---

## 🔄 Versioning & Updates

**Current Version**: 1.0  
**Effective Date**: February 16, 2026  
**Last Updated**: February 16, 2026

### How to Propose Changes

1. **Create Issue**: Describe what should change and why
2. **Discussion**: Team discusses on GitHub issue
3. **Update Document**: Make changes in branch
4. **Review**: At least 2 approvals required
5. **Merge**: Document takes effect immediately
6. **Announce**: Post update in team channel

### Common Update Scenarios

- **Adding Pattern**: If pattern appears 3+ times, add to ARCHITECTURE.md
- **Changing Limit**: If tools suggest new limits, update metrics section
- **New Tool**: If new linting tool adopted, add to enforcement section

---

## 📞 Questions & Support

### Clarifications

If a steering document is unclear:
1. Post question in #code-standards channel
2. Create issue with "documentation" label
3. Maintainer will clarify or update

### Exceptions

To make an exception to steering documents:
1. Document reason in code comments
2. Create issue with "exception-request" label
3. Team lead approval required
4. Record in Architecture Decision Log

### Tool Recommendations

- **IDE Setup**: Use IntelliJ IDEA defaults for Java code style
- **Linting**: Configure SonarLint with project rules
- **Git Hooks**: Use provided pre-commit hooks (ask team lead)
- **CI/CD**: Integrated into GitHub Actions

---

## 🌟 Success Metrics

### Team Health Indicators

✅ **Green** (target state):
- Coverage >= 70%
- Avg method length <= 20 lines
- Code review time <= 1 hour
- Flaky tests < 1% of suite
- Zero compiler warnings

🟡 **Yellow** (attention needed):
- Coverage 50-70%
- Avg method length 20-30 lines
- Code review time 1-2 hours
- Flaky tests 1-5% of suite
- Few compiler warnings

🔴 **Red** (action required):
- Coverage < 50%
- Avg method length > 30 lines
- Code review time > 2 hours
- Flaky tests > 5% of suite
- Many compiler warnings

---

## 📖 Related Resources

### External References

- [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)
- [Clean Code by Robert Martin](https://www.oreilly.com/library/view/clean-code-a/9780136083238/)
- [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
- [JUnit 5 Guide](https://junit.org/junit5/docs/current/user-guide/)

### Internal Documentation

- [TESTING.md](../../TESTING.md) - Progress report
- [TESTING_QUICKSTART.md](../../TESTING_QUICKSTART.md) - Quick reference
- [README.md](../../README.md) - Project overview

---

## 🎓 Onboarding Checklist

New team members should:

- [ ] Read PROGRAMMING_PRACTICES.md
- [ ] Read ARCHITECTURE.md
- [ ] Read TESTING_STANDARDS.md
- [ ] Set up IDE with project code style
- [ ] Run first test locally
- [ ] Make a small PR following standards
- [ ] Ask questions in team channel
- [ ] Attend architecture review (if available)

**Expected Time**: 2-4 hours  
**Mentor Assignment**: First manager or senior dev

---

**Document Status**: ✅ Active  
**Maintainer**: Development Team  
**Last Review**: February 16, 2026

---

*Use these historical notes only when they agree with Gestudio's current source of truth.*
