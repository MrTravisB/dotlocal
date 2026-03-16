package primitive

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// CopyPrimitive copies files matching glob patterns from a source directory to a target directory.
type CopyPrimitive struct {
	Source       string   // absolute path to source dir in repo
	Target       string   // absolute path to target dir
	GlobPatterns []string // e.g. ["*.ttf", "*.otf"]
	RepoDir      string
	BackupDir    string
}

func (c *CopyPrimitive) ID() string {
	rel := c.Source
	if strings.HasPrefix(rel, c.RepoDir) {
		rel = strings.TrimPrefix(rel, c.RepoDir)
		rel = strings.TrimPrefix(rel, string(filepath.Separator))
	}
	return "copy:" + rel
}

func (c *CopyPrimitive) Type() string {
	return "copy"
}

func (c *CopyPrimitive) DependsOn() []string {
	return nil
}

func (c *CopyPrimitive) Check(_ context.Context) (Status, error) {
	matches, err := c.sourceFiles()
	if err != nil {
		return StatusError, err
	}
	if len(matches) == 0 {
		return StatusCurrent, nil
	}

	anyExist := false
	allMatch := true

	for _, src := range matches {
		name := filepath.Base(src)
		dst := filepath.Join(c.Target, name)

		equal, err := filesEqual(src, dst)
		if err != nil {
			if os.IsNotExist(err) {
				allMatch = false
				continue
			}
			return StatusError, fmt.Errorf("comparing %s and %s: %w", src, dst, err)
		}

		anyExist = true
		if !equal {
			allMatch = false
		}
	}

	if allMatch && anyExist {
		return StatusCurrent, nil
	}
	if !anyExist {
		return StatusMissing, nil
	}
	return StatusDrift, nil
}

func (c *CopyPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing, StatusDrift:
		matches, err := c.sourceFiles()
		if err != nil {
			return nil, err
		}

		files := make([]string, 0, len(matches))
		for _, m := range matches {
			files = append(files, filepath.Base(m))
		}

		return &Action{
			Description: fmt.Sprintf("copy %d file(s) to %s: %s", len(files), c.Target, strings.Join(files, ", ")),
			Commands:    []string{fmt.Sprintf("cp %s/* %s/", c.Source, c.Target)},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (c *CopyPrimitive) Apply(_ context.Context) (*Result, error) {
	matches, err := c.sourceFiles()
	if err != nil {
		return nil, err
	}

	if err := os.MkdirAll(c.Target, 0o755); err != nil {
		return nil, fmt.Errorf("creating target directory %s: %w", c.Target, err)
	}

	copied := 0
	for _, src := range matches {
		name := filepath.Base(src)
		dst := filepath.Join(c.Target, name)

		// Skip if contents already match.
		equal, err := filesEqual(src, dst)
		if err == nil && equal {
			continue
		}

		if err := copyFile(src, dst); err != nil {
			return nil, fmt.Errorf("copying %s to %s: %w", src, dst, err)
		}
		copied++
	}

	if copied == 0 {
		return &Result{Changed: false, Message: "all files already up to date"}, nil
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("copied %d file(s) to %s", copied, c.Target),
	}, nil
}

// sourceFiles returns all files in Source that match any of the GlobPatterns.
func (c *CopyPrimitive) sourceFiles() ([]string, error) {
	var results []string
	seen := make(map[string]bool)

	for _, pattern := range c.GlobPatterns {
		matches, err := filepath.Glob(filepath.Join(c.Source, pattern))
		if err != nil {
			return nil, fmt.Errorf("glob %s: %w", pattern, err)
		}
		for _, m := range matches {
			if !seen[m] {
				seen[m] = true
				results = append(results, m)
			}
		}
	}

	return results, nil
}

// filesEqual does a binary comparison of two files. Returns an error if either file
// cannot be read (including os.IsNotExist for the destination).
func filesEqual(a, b string) (bool, error) {
	dataA, err := os.ReadFile(a)
	if err != nil {
		return false, err
	}
	dataB, err := os.ReadFile(b)
	if err != nil {
		return false, err
	}
	return bytes.Equal(dataA, dataB), nil
}

// copyFile copies a single file from src to dst, preserving permissions.
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	info, err := in.Stat()
	if err != nil {
		return err
	}

	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, info.Mode())
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		return err
	}

	return out.Close()
}
