package test

import (
	"fmt"
	"strings"
	"sync"
	"testing"

	ttesting "github.com/gruntwork-io/terratest/modules/testing"

	"github.com/gruntwork-io/terratest/modules/logger"
)

// terraformLogger captures terraform output, emits short phase status messages,
// and buffers error blocks to dump on test failure.
type terraformLogger struct {
	mu     sync.Mutex
	t      *testing.T
	label  string // e.g. "VPC fixture" or "root module"
	errors strings.Builder

	// Phase tracking
	phase        string
	inErrorBlock bool
	resourceNum  int
	resourceMsg  string // last "Creating...", "Modifying...", or "Destroying..." resource
}

// newTerraformLogger creates a logger for a terraform operation.
// The label identifies what's being managed (e.g. "VPC fixture", "root module").
func newTerraformLogger(t *testing.T, label string) *logger.Logger {
	tl := &terraformLogger{t: t, label: label}
	return logger.New(tl)
}

func (l *terraformLogger) Logf(t ttesting.TestingT, format string, args ...interface{}) {
	line := fmt.Sprintf(format, args...)

	l.mu.Lock()
	defer l.mu.Unlock()

	// Capture error blocks
	if l.detectError(line) {
		return
	}

	// Emit phase transitions
	l.detectPhase(line)
}

func (l *terraformLogger) detectPhase(line string) {
	switch {
	case strings.Contains(line, "Initializing the backend"):
		l.setPhase("Initializing %s...", l.label)

	case strings.Contains(line, "Initializing provider plugins"):
		// skip, part of init

	case strings.HasPrefix(line, "OpenTofu has been successfully initialized") ||
		strings.HasPrefix(line, "Terraform has been successfully initialized"):
		l.setPhase("Initialized %s", l.label)

	case strings.Contains(line, "Refreshing state"):
		l.setPhaseOnce("Refreshing state for %s...", l.label)

	case strings.HasPrefix(line, "OpenTofu used the selected") ||
		strings.HasPrefix(line, "Terraform used the selected"):
		l.setPhase("Planning %s...", l.label)

	case strings.HasPrefix(line, "Plan:"):
		l.setPhase("Plan complete for %s: %s", l.label, strings.TrimSpace(line))
		l.resourceNum = 0

	case strings.Contains(line, ": Creating..."):
		l.resourceNum++
		l.resourceMsg = "Creating"
		l.emitProgress()

	case strings.Contains(line, ": Modifying..."):
		l.resourceNum++
		l.resourceMsg = "Modifying"
		l.emitProgress()

	case strings.Contains(line, ": Destroying..."):
		l.resourceNum++
		l.resourceMsg = "Destroying"
		l.emitProgress()

	case strings.HasPrefix(line, "Apply complete!"):
		l.setPhase("%s: %s", l.label, strings.TrimSpace(line))
		l.resourceNum = 0

	case strings.HasPrefix(line, "Destroy complete!"):
		l.setPhase("%s: %s", l.label, strings.TrimSpace(line))
		l.resourceNum = 0
	}
}

func (l *terraformLogger) detectError(line string) bool {
	trimmed := strings.TrimSpace(line)

	// Start of an error block
	if strings.HasPrefix(trimmed, "Error:") || strings.HasPrefix(trimmed, "Warning:") {
		l.inErrorBlock = true
		fmt.Fprintf(&l.errors, "\n%s\n", line)
		return true
	}

	// Inside an error block — keep capturing until blank line
	if l.inErrorBlock {
		if trimmed == "" {
			l.inErrorBlock = false
			fmt.Fprintln(&l.errors)
		} else {
			fmt.Fprintf(&l.errors, "%s\n", line)
		}
		return true
	}

	return false
}

func (l *terraformLogger) setPhase(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	l.phase = msg
	l.t.Logf("=== %s", msg)
}

func (l *terraformLogger) setPhaseOnce(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	if l.phase != msg {
		l.phase = msg
		l.t.Logf("=== %s", msg)
	}
}

func (l *terraformLogger) emitProgress() {
	// Log every 10th resource and the first one
	if l.resourceNum == 1 || l.resourceNum%10 == 0 {
		l.t.Logf("=== %s %s... (%d)", l.label, l.resourceMsg, l.resourceNum)
	}
}

// DumpErrors logs captured errors if the test failed.
func (l *terraformLogger) DumpErrors(t *testing.T) {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.errors.Len() > 0 {
		t.Logf("=== Terraform errors for %s ===\n%s", l.label, l.errors.String())
	}
}

// newTerraformLoggerPair creates loggers for VPC fixture and root module,
// and returns a cleanup function to dump errors on failure.
func newTerraformLoggerPair(t *testing.T) (vpcLogger *logger.Logger, moduleLogger *logger.Logger, cleanup func()) {
	vpcTL := &terraformLogger{t: t, label: "VPC fixture"}
	modTL := &terraformLogger{t: t, label: "root module"}

	cleanup = func() {
		if t.Failed() {
			vpcTL.DumpErrors(t)
			modTL.DumpErrors(t)
		}
	}

	return logger.New(vpcTL), logger.New(modTL), cleanup
}
