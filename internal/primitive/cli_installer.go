package primitive

import (
	"context"
	"fmt"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// CLIInstallerPrimitive manages a CLI tool installed via a curl/sh script
// or similar one-liner command.
type CLIInstallerPrimitive struct {
	Name       string // display name, e.g. "bun"
	CheckCmd   string // command to check existence, e.g. "bun"
	InstallCmd string // install command, e.g. "curl -fsSL https://bun.sh/install | bash"
}

func (c *CLIInstallerPrimitive) ID() string        { return "cli_installer:" + c.Name }
func (c *CLIInstallerPrimitive) Type() string       { return "cli_installer" }
func (c *CLIInstallerPrimitive) DependsOn() []string { return nil }

func (c *CLIInstallerPrimitive) Check(_ context.Context) (Status, error) {
	if runner.CommandExists(c.CheckCmd) {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (c *CLIInstallerPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("run: %s", c.InstallCmd),
		Commands:    []string{c.InstallCmd},
	}, nil
}

func (c *CLIInstallerPrimitive) Apply(ctx context.Context) (*Result, error) {
	_, err := runner.Run(ctx, c.InstallCmd)
	if err != nil {
		return nil, fmt.Errorf("installing %s: %w", c.Name, err)
	}
	return &Result{Changed: true, Message: fmt.Sprintf("installed %s", c.Name)}, nil
}
