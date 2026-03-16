package primitive

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// PromptPrimitive handles interactive one-time setup tasks like git identity and SSH key signing.
type PromptPrimitive struct {
	PID        string        // e.g. "git_identity"
	Desc       string        // e.g. "Git user identity"
	CheckCmd   string        // command that returns 0 if already configured
	Fields     []PromptField // fields to prompt for
	ApplyCmds  []string      // commands to run with field values substituted
	ConfirmMsg string        // optional y/n confirmation message
	Handler    string        // built-in handler name (e.g. "ssh_signing") - overrides Fields/ApplyCmds
}

// PromptField defines a single interactive input field.
type PromptField struct {
	Name   string // e.g. "user.name"
	Prompt string // e.g. "Enter your full name for git"
}

func (p *PromptPrimitive) ID() string {
	return "prompt:" + p.PID
}

func (p *PromptPrimitive) Type() string {
	return "prompt"
}

func (p *PromptPrimitive) DependsOn() []string {
	return nil
}

func (p *PromptPrimitive) Check(ctx context.Context) (Status, error) {
	if runner.RunSilent(ctx, p.CheckCmd) {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (p *PromptPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		return &Action{
			Description: fmt.Sprintf("prompt for %s", p.Desc),
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (p *PromptPrimitive) Apply(ctx context.Context) (*Result, error) {
	if p.Handler == "ssh_signing" {
		return p.handleSSHSigning(ctx)
	}

	scanner := bufio.NewScanner(os.Stdin)

	// Handle optional confirmation.
	if p.ConfirmMsg != "" {
		fmt.Fprintf(os.Stderr, "%s [y/n]: ", p.ConfirmMsg)
		if !scanner.Scan() {
			return &Result{Changed: false, Message: "no input received"}, nil
		}
		answer := strings.TrimSpace(strings.ToLower(scanner.Text()))
		if answer != "y" && answer != "yes" {
			return &Result{Changed: false, Message: "user declined"}, nil
		}
	}

	// Collect field values.
	values := make(map[string]string, len(p.Fields))
	for _, f := range p.Fields {
		fmt.Fprintf(os.Stderr, "%s: ", f.Prompt)
		if !scanner.Scan() {
			return nil, fmt.Errorf("reading input for %s: unexpected end of input", f.Name)
		}
		values[f.Name] = strings.TrimSpace(scanner.Text())
	}

	// Substitute field values into apply commands and run them.
	for _, cmdTpl := range p.ApplyCmds {
		cmd := cmdTpl
		for name, val := range values {
			cmd = strings.ReplaceAll(cmd, "{"+name+"}", val)
		}
		if _, err := runner.Run(ctx, cmd); err != nil {
			return nil, fmt.Errorf("running %q: %w", cmd, err)
		}
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("configured %s", p.Desc),
	}, nil
}

// handleSSHSigning implements the built-in "ssh_signing" handler.
// It discovers SSH public keys, lets the user pick one, and configures
// git to use it for commit signing.
func (p *PromptPrimitive) handleSSHSigning(ctx context.Context) (*Result, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("getting home directory: %w", err)
	}

	sshDir := filepath.Join(home, ".ssh")
	pubKeys, err := filepath.Glob(filepath.Join(sshDir, "*.pub"))
	if err != nil {
		return nil, fmt.Errorf("listing SSH public keys: %w", err)
	}

	if len(pubKeys) == 0 {
		fmt.Fprintln(os.Stderr, "warning: no SSH public keys found in ~/.ssh/; skipping SSH signing setup")
		return &Result{Changed: false, Message: "no SSH public keys found"}, nil
	}

	var selectedKey string

	if len(pubKeys) == 1 {
		selectedKey = pubKeys[0]
		fmt.Fprintf(os.Stderr, "Using SSH key: %s\n", selectedKey)
	} else {
		fmt.Fprintln(os.Stderr, "Select an SSH key for commit signing:")
		for i, key := range pubKeys {
			fmt.Fprintf(os.Stderr, "  %d) %s\n", i+1, key)
		}
		fmt.Fprintf(os.Stderr, "Choice [1-%d]: ", len(pubKeys))

		scanner := bufio.NewScanner(os.Stdin)
		if !scanner.Scan() {
			return nil, fmt.Errorf("reading SSH key selection: unexpected end of input")
		}
		choice, err := strconv.Atoi(strings.TrimSpace(scanner.Text()))
		if err != nil || choice < 1 || choice > len(pubKeys) {
			return nil, fmt.Errorf("invalid selection: %s", scanner.Text())
		}
		selectedKey = pubKeys[choice-1]
	}

	// Configure git to use SSH signing with the selected key.
	cmds := []string{
		"git config --global gpg.format ssh",
		fmt.Sprintf("git config --global user.signingkey %s", selectedKey),
		"git config --global commit.gpgsign true",
	}
	for _, cmd := range cmds {
		if _, err := runner.Run(ctx, cmd); err != nil {
			return nil, fmt.Errorf("running %q: %w", cmd, err)
		}
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("configured SSH signing with %s", selectedKey),
	}, nil
}
