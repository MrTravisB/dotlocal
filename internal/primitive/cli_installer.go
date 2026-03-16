package primitive

import (
	"context"
	"fmt"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// CLIPrimitive manages a CLI tool installed via a curl/sh script
// or similar one-liner command.
type CLIPrimitive struct {
	Name       string
	CheckCmd   string
	InstallCmd string
	Deps       []string
}

func (c *CLIPrimitive) ID() string         { return "cli:" + c.Name }
func (c *CLIPrimitive) Type() string        { return "cli" }
func (c *CLIPrimitive) DependsOn() []string { return c.Deps }

func (c *CLIPrimitive) Check(_ context.Context) (Status, error) {
	if runner.CommandExists(c.CheckCmd) {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (c *CLIPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("run: %s", c.InstallCmd),
		Commands:    []string{c.InstallCmd},
	}, nil
}

func (c *CLIPrimitive) Apply(ctx context.Context) (*Result, error) {
	_, err := runner.Run(ctx, c.InstallCmd)
	if err != nil {
		return nil, fmt.Errorf("installing %s: %w", c.Name, err)
	}
	return &Result{Changed: true, Message: fmt.Sprintf("installed %s", c.Name)}, nil
}
