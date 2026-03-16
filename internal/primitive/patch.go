package primitive

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// PatchPrimitive applies a custom patch to a file on disk using a shell command.
type PatchPrimitive struct {
	PID         string   // e.g. "vscode_insiders_openvsx"
	Description string
	Target      string   // absolute path to file to patch
	Requires    []string // commands that must exist
	CheckCmd    string   // command that returns 0 if patch is applied
	ApplyCmd    string   // command to apply the patch
	Backup      bool     // backup target before patching
	BackupDir   string
}

func (p *PatchPrimitive) ID() string {
	return "patch:" + p.PID
}

func (p *PatchPrimitive) Type() string {
	return "patch"
}

func (p *PatchPrimitive) DependsOn() []string {
	return nil
}

func (p *PatchPrimitive) Check(ctx context.Context) (Status, error) {
	// Target file must exist.
	if _, err := os.Stat(p.Target); os.IsNotExist(err) {
		return StatusError, fmt.Errorf("target file not found: %s", p.Target)
	}

	// Verify all required commands exist.
	for _, req := range p.Requires {
		if !runner.CommandExists(req) {
			return StatusError, fmt.Errorf("required command %q not found", req)
		}
	}

	// Run the check command to see if the patch is already applied.
	if runner.RunSilent(ctx, p.CheckCmd) {
		return StatusCurrent, nil
	}

	return StatusDrift, nil
}

func (p *PatchPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusDrift:
		desc := p.Description
		if desc == "" {
			desc = fmt.Sprintf("apply patch %s to %s", p.PID, p.Target)
		}
		cmds := []string{}
		if p.Backup {
			cmds = append(cmds, fmt.Sprintf("cp %s %s/", p.Target, p.BackupDir))
		}
		cmds = append(cmds, p.ApplyCmd)
		return &Action{
			Description: desc,
			Commands:    cmds,
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (p *PatchPrimitive) Apply(ctx context.Context) (*Result, error) {
	// Back up the target file if requested.
	if p.Backup {
		if err := p.backupTarget(); err != nil {
			return nil, fmt.Errorf("backing up %s: %w", p.Target, err)
		}
	}

	// Apply the patch.
	if _, err := runner.Run(ctx, p.ApplyCmd); err != nil {
		return nil, fmt.Errorf("applying patch %s: %w", p.PID, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("applied patch %s to %s", p.PID, p.Target),
	}, nil
}

// backupTarget copies the target file into BackupDir, preserving its directory
// structure relative to the user's home directory.
func (p *PatchPrimitive) backupTarget() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("getting home directory: %w", err)
	}

	rel := p.Target
	if strings.HasPrefix(rel, home) {
		rel = strings.TrimPrefix(rel, home)
		rel = strings.TrimPrefix(rel, string(filepath.Separator))
	}

	backupPath := filepath.Join(p.BackupDir, rel)
	backupDir := filepath.Dir(backupPath)

	if err := os.MkdirAll(backupDir, 0o755); err != nil {
		return fmt.Errorf("creating backup directory %s: %w", backupDir, err)
	}

	src, err := os.ReadFile(p.Target)
	if err != nil {
		return fmt.Errorf("reading %s: %w", p.Target, err)
	}

	info, err := os.Stat(p.Target)
	if err != nil {
		return fmt.Errorf("stat %s: %w", p.Target, err)
	}

	if err := os.WriteFile(backupPath, src, info.Mode()); err != nil {
		return fmt.Errorf("writing backup %s: %w", backupPath, err)
	}

	fmt.Fprintf(os.Stderr, "backed up %s -> %s\n", p.Target, backupPath)
	return nil
}
