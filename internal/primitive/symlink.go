package primitive

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// SymlinkPrimitive manages a symbolic link from a repo source file to a system target location.
type SymlinkPrimitive struct {
	Source    string // absolute path to source file in repo
	Target    string // absolute path to target location
	RepoDir   string // repo root directory
	BackupDir string // backup directory for existing files
}

func (s *SymlinkPrimitive) ID() string {
	rel := s.Source
	if strings.HasPrefix(rel, s.RepoDir) {
		rel = strings.TrimPrefix(rel, s.RepoDir)
		rel = strings.TrimPrefix(rel, string(filepath.Separator))
	}
	return "symlink:" + rel
}

func (s *SymlinkPrimitive) Type() string {
	return "symlink"
}

func (s *SymlinkPrimitive) DependsOn() []string {
	return nil
}

func (s *SymlinkPrimitive) Check(_ context.Context) (Status, error) {
	info, err := os.Lstat(s.Target)
	if os.IsNotExist(err) {
		return StatusMissing, nil
	}
	if err != nil {
		return StatusError, fmt.Errorf("lstat %s: %w", s.Target, err)
	}

	// Target exists. Check if it is a symlink pointing to the correct source.
	if info.Mode()&os.ModeSymlink == 0 {
		// Real file or directory, not a symlink.
		return StatusDrift, nil
	}

	dest, err := os.Readlink(s.Target)
	if err != nil {
		return StatusError, fmt.Errorf("readlink %s: %w", s.Target, err)
	}

	if dest == s.Source {
		return StatusCurrent, nil
	}

	return StatusDrift, nil
}

func (s *SymlinkPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		return &Action{
			Description: fmt.Sprintf("create symlink %s -> %s", s.Target, s.Source),
			Commands:    []string{fmt.Sprintf("ln -s %s %s", s.Source, s.Target)},
		}, nil
	case StatusDrift:
		return &Action{
			Description: fmt.Sprintf("backup %s, create symlink %s -> %s", s.Target, s.Target, s.Source),
			Commands: []string{
				fmt.Sprintf("mv %s %s/", s.Target, s.BackupDir),
				fmt.Sprintf("ln -s %s %s", s.Source, s.Target),
			},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (s *SymlinkPrimitive) Apply(_ context.Context) (*Result, error) {
	// Ensure parent directory of target exists.
	targetDir := filepath.Dir(s.Target)
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return nil, fmt.Errorf("creating target directory %s: %w", targetDir, err)
	}

	// If something already exists at the target, back it up.
	if _, err := os.Lstat(s.Target); err == nil {
		if err := s.backup(); err != nil {
			return nil, fmt.Errorf("backing up %s: %w", s.Target, err)
		}
	}

	// Create the symlink.
	if err := os.Symlink(s.Source, s.Target); err != nil {
		return nil, fmt.Errorf("creating symlink %s -> %s: %w", s.Target, s.Source, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("symlinked %s -> %s", s.Target, s.Source),
	}, nil
}

// backup moves the existing target into BackupDir, preserving its directory structure
// relative to the user's home directory.
func (s *SymlinkPrimitive) backup() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("getting home directory: %w", err)
	}

	// Compute a relative path from home so backups mirror the original layout.
	rel := s.Target
	if strings.HasPrefix(rel, home) {
		rel = strings.TrimPrefix(rel, home)
		rel = strings.TrimPrefix(rel, string(filepath.Separator))
	}

	backupPath := filepath.Join(s.BackupDir, rel)
	backupDir := filepath.Dir(backupPath)

	if err := os.MkdirAll(backupDir, 0o755); err != nil {
		return fmt.Errorf("creating backup directory %s: %w", backupDir, err)
	}

	if err := os.Rename(s.Target, backupPath); err != nil {
		return fmt.Errorf("moving %s to %s: %w", s.Target, backupPath, err)
	}

	fmt.Fprintf(os.Stderr, "backed up %s -> %s\n", s.Target, backupPath)
	return nil
}
