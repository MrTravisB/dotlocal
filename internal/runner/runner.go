package runner

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// Run executes a shell command and returns its combined output.
// The command is run via /bin/bash -c.
func Run(ctx context.Context, command string) (string, error) {
	cmd := exec.CommandContext(ctx, "/bin/bash", "-c", command)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	output := strings.TrimSpace(stdout.String())
	if err != nil {
		errOutput := strings.TrimSpace(stderr.String())
		if errOutput != "" {
			return output, fmt.Errorf("%w: %s", err, errOutput)
		}
		return output, err
	}
	return output, nil
}

// RunSilent executes a command and returns only whether it succeeded.
func RunSilent(ctx context.Context, command string) bool {
	cmd := exec.CommandContext(ctx, "/bin/bash", "-c", command)
	return cmd.Run() == nil
}

// CommandExists checks if a command is available in PATH.
func CommandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
