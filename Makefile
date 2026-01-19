# ApexTrace Makefile
# Provides convenient commands for installation, testing, and maintenance

# Define a path to a dummy package.xml needed for destructive deploys.
# This file is used when only deleting components.
# You need to create this file yourself. It can be just:
# <?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>59.0</version></Package>
EMPTY_PACKAGE_XML = manifest/package-empty.xml

.PHONY: install uninstall reinstall test test-trace test-traceflow test-tracehistory test-traceexception test-all coverage help

# Default target - show help
.DEFAULT_GOAL := help

# help: Display available commands
help:
	@echo "ApexTrace - Available Commands:"
	@echo ""
	@echo "  make install      - Deploy ApexTrace to the org"
	@echo "  make uninstall    - Remove ApexTrace from the org"
	@echo "  make reinstall    - Uninstall and reinstall ApexTrace"
	@echo "  make test         - Run all ApexTrace tests"
	@echo "  make test-trace   - Run Trace tests only"
	@echo "  make test-traceflow - Run TraceFlow tests only"
	@echo "  make test-tracehistory - Run TraceHistory tests only"
	@echo "  make test-traceexception - Run TraceException tests only"
	@echo "  make test-all     - Run all tests with detailed output"
	@echo "  make coverage     - Show code coverage report"
	@echo "  make help         - Show this help message"
	@echo ""

# install: Deploys all ApexTrace classes to the org
install:
	@echo "Deploying ApexTrace to the org..."
	@sf project deploy start --source-dir . --wait 10 || exit 1
	@echo "✅ ApexTrace installed successfully!"

# uninstall: Removes all ApexTrace classes from the org
uninstall:
	@echo "Removing ApexTrace from the org..."
	@echo "Using destructive manifest: manifest/uninstall.xml"
	@sf project deploy start \
		--manifest $(EMPTY_PACKAGE_XML) \
		--post-destructive-changes manifest/uninstall.xml \
		--wait 10 || echo "Destructive deployment finished (some errors may be ignored)."
	@echo "✅ ApexTrace uninstalled!"

# reinstall: Uninstall and then install ApexTrace
reinstall: uninstall install
	@echo "✅ ApexTrace reinstalled successfully!"

# test: Run all ApexTrace tests
test: install
	@echo "Running all ApexTrace tests..."
	@sf apex run test \
		--class-names TraceTest \
		--class-names TraceFlowTest \
		--class-names TraceExceptionTest \
		--class-names TraceHistoryTest \
		--code-coverage \
		--wait 10 \
		--result-format human

# test-trace: Run Trace tests only
test-trace: install
	@echo "Running Trace tests..."
	@sf apex run test --test-level RunSpecifiedTests --class-names TraceTest --code-coverage --synchronous

# test-traceflow: Run TraceFlow tests only
test-traceflow: install
	@echo "Running TraceFlow tests..."
	@sf apex run test --test-level RunSpecifiedTests --class-names TraceFlowTest --code-coverage --synchronous

# test-tracehistory: Run TraceHistory tests only
test-tracehistory: install
	@echo "Running TraceHistory tests..."
	@sf apex run test --test-level RunSpecifiedTests --class-names TraceHistoryTest --code-coverage --synchronous

# test-traceexception: Run TraceException tests only
test-traceexception: install
	@echo "Running TraceException tests..."
	@sf apex run test --test-level RunSpecifiedTests --class-names TraceExceptionTest --code-coverage --synchronous

# test-all: Run all tests with detailed output and coverage
test-all: install
	@echo "Running all ApexTrace tests with detailed output..."
	@sf apex run test \
		--class-names TraceTest \
		--class-names TraceFlowTest \
		--class-names TraceExceptionTest \
		--class-names TraceHistoryTest \
		--code-coverage \
		--wait 10 \
		--result-format human \
		--output-dir test-results
	@echo "✅ Test results saved to test-results/"

# coverage: Display code coverage summary
coverage:
	@echo "Code Coverage Summary:"
	@echo "======================"
	@sf apex get test --test-run-id $(shell sf apex run test --class-names TraceTest --class-names TraceFlowTest --class-names TraceExceptionTest --class-names TraceHistoryTest --code-coverage --wait 10 --json | jq -r '.result.summary.testRunId') --code-coverage
