package primitive

import (
	"context"
	"fmt"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// DockerStackPrimitive manages a Docker Compose stack.
type DockerStackPrimitive struct {
	Name        string   // e.g. "langfuse"
	ComposeFile string   // absolute path to docker-compose.yml
	StartScript string   // absolute path to start.sh (optional, used instead of compose if set)
	Requires    []string // commands that must exist, e.g. ["docker"]
}

func (d *DockerStackPrimitive) ID() string {
	return "docker_stack:" + d.Name
}

func (d *DockerStackPrimitive) Type() string {
	return "docker_stack"
}

func (d *DockerStackPrimitive) DependsOn() []string {
	return nil
}

func (d *DockerStackPrimitive) Check(ctx context.Context) (Status, error) {
	// Verify all required commands exist.
	for _, req := range d.Requires {
		if !runner.CommandExists(req) {
			return StatusError, fmt.Errorf("required command %q not found", req)
		}
	}

	// Check if containers are running.
	cmd := fmt.Sprintf("docker compose -f %s ps -q", d.ComposeFile)
	output, err := runner.Run(ctx, cmd)
	if err != nil {
		return StatusError, fmt.Errorf("checking docker stack %s: %w", d.Name, err)
	}

	if strings.TrimSpace(output) != "" {
		return StatusCurrent, nil
	}

	return StatusMissing, nil
}

func (d *DockerStackPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		cmd := d.upCommand()
		return &Action{
			Description: fmt.Sprintf("start docker stack %s", d.Name),
			Commands:    []string{cmd},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (d *DockerStackPrimitive) Apply(ctx context.Context) (*Result, error) {
	cmd := d.upCommand()
	if _, err := runner.Run(ctx, cmd); err != nil {
		return nil, fmt.Errorf("starting docker stack %s: %w", d.Name, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("started docker stack %s", d.Name),
	}, nil
}

// upCommand returns the shell command to bring the stack up.
// If StartScript is set, it takes precedence over docker compose.
func (d *DockerStackPrimitive) upCommand() string {
	if d.StartScript != "" {
		return fmt.Sprintf("bash %s", d.StartScript)
	}
	return fmt.Sprintf("docker compose -f %s up -d", d.ComposeFile)
}
