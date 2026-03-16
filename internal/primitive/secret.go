package primitive

import (
	"context"
	"fmt"
	"os"
)

// SecretPrimitive checks whether a required environment variable is set.
// Secrets are never auto-generated; Apply only warns the user.
type SecretPrimitive struct {
	Name     string // env var name, e.g. "GITHUB_TOKEN"
	Required bool
	Template string // path to .secrets.example template
}

func (s *SecretPrimitive) ID() string {
	return "secret:" + s.Name
}

func (s *SecretPrimitive) Type() string {
	return "secret"
}

func (s *SecretPrimitive) DependsOn() []string {
	return nil
}

func (s *SecretPrimitive) Check(_ context.Context) (Status, error) {
	if os.Getenv(s.Name) != "" {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (s *SecretPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		label := "optional"
		if s.Required {
			label = "required"
		}
		return &Action{
			Description: fmt.Sprintf("set %s in ~/.secrets (%s)", s.Name, label),
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (s *SecretPrimitive) Apply(_ context.Context) (*Result, error) {
	label := "optional"
	if s.Required {
		label = "required"
	}
	fmt.Fprintf(os.Stderr, "warning: %s secret %s is not set; add it to ~/.secrets\n", label, s.Name)

	return &Result{
		Changed: false,
		Message: fmt.Sprintf("%s is not set", s.Name),
	}, nil
}
