package primitive

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"path"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// GitRepoPrimitive clones a git repo if missing, pulls if it exists.
type GitRepoPrimitive struct {
	URL       string   // git URL
	Target    string   // absolute path to clone target
	Shallow   bool     // --depth=1 on clone
	Method    string   // "installer" means use Install command instead of git clone
	Install   string   // installer command (only if Method == "installer")
	PostClone string   // command to run after initial clone
	Deps      []string // dependency IDs
}

func (g *GitRepoPrimitive) ID() string {
	name := repoName(g.URL)
	return "git_repo:" + name
}

func (g *GitRepoPrimitive) Type() string {
	return "git_repo"
}

func (g *GitRepoPrimitive) DependsOn() []string {
	return g.Deps
}

func (g *GitRepoPrimitive) Check(_ context.Context) (Status, error) {
	info, err := os.Stat(g.Target)
	if os.IsNotExist(err) {
		return StatusMissing, nil
	}
	if err != nil {
		return StatusError, fmt.Errorf("stat %s: %w", g.Target, err)
	}
	if !info.IsDir() {
		return StatusError, fmt.Errorf("%s exists but is not a directory", g.Target)
	}

	// Check for .git subdirectory to confirm this is a repo.
	gitDir := g.Target + "/.git"
	if _, err := os.Stat(gitDir); os.IsNotExist(err) {
		// Directory exists but is not a git repo.
		return StatusDrift, nil
	}

	// Repo exists. Return StatusDrift so the engine triggers a pull.
	return StatusDrift, nil
}

func (g *GitRepoPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	id := repoName(g.URL)

	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		if g.Method == "installer" {
			return &Action{
				Description: fmt.Sprintf("run installer for %s", id),
				Commands:    []string{g.Install},
			}, nil
		}
		cmd := g.cloneCommand()
		return &Action{
			Description: fmt.Sprintf("git clone %s -> %s", g.URL, g.Target),
			Commands:    []string{cmd},
		}, nil
	case StatusDrift:
		return &Action{
			Description: fmt.Sprintf("git pull in %s", g.Target),
			Commands:    []string{fmt.Sprintf("git -C %s pull", g.Target)},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (g *GitRepoPrimitive) Apply(ctx context.Context) (*Result, error) {
	status, err := g.Check(ctx)
	if err != nil {
		return nil, err
	}

	switch status {
	case StatusMissing:
		return g.applyClone(ctx)
	case StatusDrift:
		return g.applyPull(ctx)
	default:
		return &Result{Changed: false, Message: "already current"}, nil
	}
}

func (g *GitRepoPrimitive) applyClone(ctx context.Context) (*Result, error) {
	if g.Method == "installer" {
		if _, err := runner.Run(ctx, g.Install); err != nil {
			return nil, fmt.Errorf("running installer for %s: %w", g.URL, err)
		}
		return &Result{Changed: true, Message: fmt.Sprintf("installed %s via installer", repoName(g.URL))}, nil
	}

	cmd := g.cloneCommand()
	if _, err := runner.Run(ctx, cmd); err != nil {
		return nil, fmt.Errorf("cloning %s: %w", g.URL, err)
	}

	if g.PostClone != "" {
		if _, err := runner.Run(ctx, g.PostClone); err != nil {
			return nil, fmt.Errorf("running post-clone for %s: %w", g.URL, err)
		}
	}

	return &Result{Changed: true, Message: fmt.Sprintf("cloned %s -> %s", g.URL, g.Target)}, nil
}

func (g *GitRepoPrimitive) applyPull(ctx context.Context) (*Result, error) {
	cmd := fmt.Sprintf("git -C %s pull", g.Target)
	if _, err := runner.Run(ctx, cmd); err != nil {
		return nil, fmt.Errorf("pulling %s: %w", g.Target, err)
	}
	return &Result{Changed: true, Message: fmt.Sprintf("pulled %s", g.Target)}, nil
}

func (g *GitRepoPrimitive) cloneCommand() string {
	if g.Shallow {
		return fmt.Sprintf("git clone --depth=1 %s %s", g.URL, g.Target)
	}
	return fmt.Sprintf("git clone %s %s", g.URL, g.Target)
}

// repoName extracts the last path segment from a git URL, stripping any .git suffix.
// For example, "https://github.com/ohmyzsh/ohmyzsh.git" returns "ohmyzsh".
func repoName(rawURL string) string {
	// Try parsing as a URL first.
	if u, err := url.Parse(rawURL); err == nil && u.Path != "" {
		base := path.Base(u.Path)
		return strings.TrimSuffix(base, ".git")
	}
	// Fallback: treat as a plain path-like string.
	base := path.Base(rawURL)
	return strings.TrimSuffix(base, ".git")
}
