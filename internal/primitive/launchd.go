package primitive

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// LaunchdPrimitive manages a launchd service by installing a plist into ~/Library/LaunchAgents
// and loading it via launchctl.
type LaunchdPrimitive struct {
	Label        string            // e.g. "com.dotlocal.sync"
	Source       string            // absolute path to plist source in repo
	Target       string            // absolute path to target in ~/Library/LaunchAgents/
	TemplateVars map[string]string // e.g. {"__HOME__": "/Users/t"}
}

func (l *LaunchdPrimitive) ID() string {
	return "launchd:" + l.Label
}

func (l *LaunchdPrimitive) Type() string {
	return "launchd"
}

func (l *LaunchdPrimitive) DependsOn() []string {
	return nil
}

func (l *LaunchdPrimitive) Check(_ context.Context) (Status, error) {
	_, err := os.Stat(l.Target)
	if os.IsNotExist(err) {
		return StatusMissing, nil
	}
	if err != nil {
		return StatusError, fmt.Errorf("stat %s: %w", l.Target, err)
	}
	return StatusCurrent, nil
}

func (l *LaunchdPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		return &Action{
			Description: fmt.Sprintf("install launchd job %s", l.Label),
			Commands: []string{
				fmt.Sprintf("cp %s %s (with template expansion)", l.Source, l.Target),
				fmt.Sprintf("launchctl load %s", l.Target),
			},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (l *LaunchdPrimitive) Apply(ctx context.Context) (*Result, error) {
	// Read the source plist.
	data, err := os.ReadFile(l.Source)
	if err != nil {
		return nil, fmt.Errorf("reading source %s: %w", l.Source, err)
	}

	// Apply template variable substitutions.
	content := string(data)
	for key, value := range l.TemplateVars {
		expanded, err := expandTilde(value)
		if err != nil {
			return nil, fmt.Errorf("expanding ~ in template value for %s: %w", key, err)
		}
		content = strings.ReplaceAll(content, key, expanded)
	}

	// Create the target parent directory.
	targetDir := filepath.Dir(l.Target)
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return nil, fmt.Errorf("creating target directory %s: %w", targetDir, err)
	}

	// Write the rendered plist to the target.
	if err := os.WriteFile(l.Target, []byte(content), 0o644); err != nil {
		return nil, fmt.Errorf("writing target %s: %w", l.Target, err)
	}

	// Unload any existing job (ignore errors; it may not be loaded).
	_, _ = runner.Run(ctx, fmt.Sprintf("launchctl unload %s", l.Target))

	// Load the job.
	if _, err := runner.Run(ctx, fmt.Sprintf("launchctl load %s", l.Target)); err != nil {
		return nil, fmt.Errorf("loading launchd job %s: %w", l.Target, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("installed and loaded launchd job %s", l.Label),
	}, nil
}

// expandTilde replaces a leading ~ with the current user's home directory.
func expandTilde(path string) (string, error) {
	if !strings.HasPrefix(path, "~") {
		return path, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, path[1:]), nil
}
