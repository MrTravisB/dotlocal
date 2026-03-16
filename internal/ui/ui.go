package ui

import (
	"fmt"
	"os"

	"github.com/mrtravisb/dotlocal/internal/primitive"
)

const (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorCyan   = "\033[36m"
	colorDim    = "\033[2m"
	colorBold   = "\033[1m"
)

// UI handles terminal output formatting.
type UI struct {
	color bool
}

// New creates a UI instance. Color is enabled if stdout is a terminal.
func New() *UI {
	info, _ := os.Stdout.Stat()
	isTerminal := (info.Mode() & os.ModeCharDevice) != 0
	return &UI{color: isTerminal}
}

func (u *UI) c(code, msg string) string {
	if !u.color {
		return msg
	}
	return code + msg + colorReset
}

// OK prints a success message.
func (u *UI) OK(id string, msg string) {
	fmt.Printf("  %s %s %s\n", u.c(colorGreen, "[OK]"), u.c(colorDim, id), msg)
}

// Changed prints a change message.
func (u *UI) Changed(id string, msg string) {
	fmt.Printf("  %s %s %s\n", u.c(colorYellow, "[CHANGED]"), id, msg)
}

// Skip prints a skip message.
func (u *UI) Skip(id string, msg string) {
	fmt.Printf("  %s %s %s\n", u.c(colorDim, "[SKIP]"), u.c(colorDim, id), u.c(colorDim, msg))
}

// Error prints an error message.
func (u *UI) Error(id string, msg string) {
	fmt.Fprintf(os.Stderr, "  %s %s %s\n", u.c(colorRed, "[ERROR]"), id, msg)
}

// Warn prints a warning message.
func (u *UI) Warn(msg string) {
	fmt.Fprintf(os.Stderr, "  %s %s\n", u.c(colorYellow, "[WARN]"), msg)
}

// DryRun prints a dry-run action.
func (u *UI) DryRun(id string, msg string) {
	fmt.Printf("  %s %s %s\n", u.c(colorCyan, "[DRY-RUN]"), id, msg)
}

// Header prints a section header.
func (u *UI) Header(msg string) {
	fmt.Printf("\n%s\n", u.c(colorBold, msg))
}

// Summary prints a final summary line.
func (u *UI) Summary(total, current, changed, errored int) {
	fmt.Printf("\n%s %d total, %s current, %s changed, %s errors\n",
		u.c(colorBold, "Summary:"),
		total,
		u.c(colorGreen, fmt.Sprintf("%d", current)),
		u.c(colorYellow, fmt.Sprintf("%d", changed)),
		u.c(colorRed, fmt.Sprintf("%d", errored)),
	)
}

// StatusLine prints a primitive's check result.
func (u *UI) StatusLine(id string, status primitive.Status) {
	switch status {
	case primitive.StatusCurrent:
		u.OK(id, "")
	case primitive.StatusMissing:
		fmt.Printf("  %s %s\n", u.c(colorYellow, "[MISSING]"), id)
	case primitive.StatusDrift:
		fmt.Printf("  %s %s\n", u.c(colorYellow, "[DRIFT]"), id)
	case primitive.StatusError:
		fmt.Printf("  %s %s\n", u.c(colorRed, "[ERROR]"), id)
	}
}
