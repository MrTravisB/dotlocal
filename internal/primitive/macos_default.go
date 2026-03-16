package primitive

import (
	"context"
	"fmt"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// MacOSDefaultPrimitive reads and writes macOS system preferences via the defaults command.
type MacOSDefaultPrimitive struct {
	Domain    string
	Key       string
	ValueType string
	Value     string
	Deps      []string
}

func (d *MacOSDefaultPrimitive) ID() string {
	return "macos_default:" + d.Domain + ":" + d.Key
}

func (d *MacOSDefaultPrimitive) Type() string {
	return "macos_default"
}

func (d *MacOSDefaultPrimitive) DependsOn() []string {
	return d.Deps
}

func (d *MacOSDefaultPrimitive) Check(ctx context.Context) (Status, error) {
	cmd := fmt.Sprintf("defaults read %s %s", d.Domain, d.Key)
	output, err := runner.Run(ctx, cmd)
	if err != nil {
		// Command failure means the key is not set.
		return StatusMissing, nil
	}

	if d.matches(strings.TrimSpace(output)) {
		return StatusCurrent, nil
	}

	return StatusDrift, nil
}

func (d *MacOSDefaultPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing, StatusDrift:
		cmd := d.writeCommand()
		return &Action{
			Description: cmd,
			Commands:    []string{cmd},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (d *MacOSDefaultPrimitive) Apply(ctx context.Context) (*Result, error) {
	cmd := d.writeCommand()
	if _, err := runner.Run(ctx, cmd); err != nil {
		return nil, fmt.Errorf("running %q: %w", cmd, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("set %s %s to %s", d.Domain, d.Key, d.Value),
	}, nil
}

// matches compares the output from `defaults read` to the desired Value,
// normalizing for the bool type where defaults returns "1"/"0".
func (d *MacOSDefaultPrimitive) matches(output string) bool {
	if d.ValueType == "bool" {
		expected := d.Value
		switch strings.ToLower(expected) {
		case "true":
			expected = "1"
		case "false":
			expected = "0"
		}
		return output == expected
	}
	return output == d.Value
}

// writeCommand builds the `defaults write` invocation.
func (d *MacOSDefaultPrimitive) writeCommand() string {
	return fmt.Sprintf("defaults write %s %s -%s %s", d.Domain, d.Key, d.valueTypeFlag(), d.Value)
}

// valueTypeFlag maps the ValueType field to the defaults command flag.
func (d *MacOSDefaultPrimitive) valueTypeFlag() string {
	switch d.ValueType {
	case "bool":
		return "bool"
	case "int":
		return "int"
	case "float":
		return "float"
	case "string":
		return "string"
	default:
		return "string"
	}
}
