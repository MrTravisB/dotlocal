package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"
)

// Config represents the complete dotlocal.toml configuration.
type Config struct {
	Settings Settings `toml:"settings"`

	BrewTaps     []BrewTap     `toml:"brew_tap"`
	BrewFormulae []BrewFormula `toml:"brew_formula"`
	BrewCasks    []BrewCask    `toml:"brew_cask"`

	Apps          []App          `toml:"app"`
	CLIInstallers []CLIInstaller `toml:"cli_installer"`

	Symlinks []Symlink `toml:"symlink"`
	Copies   []Copy    `toml:"copy"`

	GitRepos         []GitRepo         `toml:"git_repo"`
	EditorExtensions []EditorExtension `toml:"editor_extension"`
	MacOSDefaults    []MacOSDefault    `toml:"macos_default"`
	Launchds         []Launchd         `toml:"launchd"`
	DockerStacks     []DockerStack     `toml:"docker_stack"`
	Secrets          []Secret          `toml:"secret"`
	Prompts          []Prompt          `toml:"prompt"`
	Encrypteds       []Encrypted       `toml:"encrypted"`
	Patches          []Patch           `toml:"patch"`
}

// Settings contains global configuration.
type Settings struct {
	BackupDir string `toml:"backup_dir"`
	LogDir    string `toml:"log_dir"`
}

type BrewTap struct {
	Name      string   `toml:"name"`
	DependsOn []string `toml:"depends_on"`
}

type BrewFormula struct {
	Name      string   `toml:"name"`
	DependsOn []string `toml:"depends_on"`
}

type BrewCask struct {
	Name      string   `toml:"name"`
	DependsOn []string `toml:"depends_on"`
}

type App struct {
	Name      string   `toml:"name"`
	URL       string   `toml:"url"`
	DependsOn []string `toml:"depends_on"`
}

type CLIInstaller struct {
	Name      string   `toml:"name"`
	Check     string   `toml:"check"`
	Install   string   `toml:"install"`
	DependsOn []string `toml:"depends_on"`
}

type Symlink struct {
	Source    string   `toml:"source"`
	Target   string   `toml:"target"`
	DependsOn []string `toml:"depends_on"`
}

type Copy struct {
	Source    string   `toml:"source"`
	Target   string   `toml:"target"`
	Glob     string   `toml:"glob"`
	DependsOn []string `toml:"depends_on"`
}

type GitRepo struct {
	URL       string   `toml:"url"`
	Target    string   `toml:"target"`
	Shallow   bool     `toml:"shallow"`
	Method    string   `toml:"method"`
	Install   string   `toml:"install"`
	PostClone string   `toml:"post_clone"`
	DependsOn []string `toml:"depends_on"`
}

type EditorExtension struct {
	ID        string   `toml:"id"`
	File      string   `toml:"file"`
	DependsOn []string `toml:"depends_on"`
}

type MacOSDefault struct {
	Domain    string   `toml:"domain"`
	Key       string   `toml:"key"`
	Type      string   `toml:"type"`
	Value     string   `toml:"value"`
	DependsOn []string `toml:"depends_on"`
}

type Launchd struct {
	Label        string            `toml:"label"`
	Source       string            `toml:"source"`
	Target       string            `toml:"target"`
	TemplateVars map[string]string `toml:"template_vars"`
	DependsOn    []string          `toml:"depends_on"`
}

type DockerStack struct {
	Name        string   `toml:"name"`
	ComposeFile string   `toml:"compose_file"`
	StartScript string   `toml:"start_script"`
	Requires    []string `toml:"requires"`
	DependsOn   []string `toml:"depends_on"`
}

type Secret struct {
	Name      string   `toml:"name"`
	DependsOn []string `toml:"depends_on"`
}

type Prompt struct {
	ID          string        `toml:"id"`
	Description string        `toml:"description"`
	Check       string        `toml:"check"`
	Fields      []PromptField `toml:"fields"`
	Apply       []string      `toml:"apply"`
	Confirm     string        `toml:"confirm"`
	Handler     string        `toml:"handler"`
}

type PromptField struct {
	Name   string `toml:"name"`
	Prompt string `toml:"prompt"`
}

type Encrypted struct {
	ID       string   `toml:"id"`
	Archive  string   `toml:"archive"`
	Target   string   `toml:"target"`
	KeySource string  `toml:"key_source"`
	OpItem   string   `toml:"op_item"`
	KeyCache string   `toml:"key_cache"`
	DependsOn []string `toml:"depends_on"`
}

type Patch struct {
	ID          string   `toml:"id"`
	Description string   `toml:"description"`
	Target      string   `toml:"target"`
	Requires    []string `toml:"requires"`
	Check       string   `toml:"check"`
	Apply       string   `toml:"apply"`
	Backup      bool     `toml:"backup"`
}

// Load reads and parses dotlocal.toml from the given repo directory.
func Load(repoDir string) (*Config, error) {
	path := filepath.Join(repoDir, "dotlocal.toml")
	var cfg Config
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}

	// Apply defaults
	if cfg.Settings.BackupDir == "" {
		cfg.Settings.BackupDir = "~/.dotlocal-backup"
	}
	if cfg.Settings.LogDir == "" {
		cfg.Settings.LogDir = "~/Library/Logs/dotlocal"
	}

	return &cfg, nil
}

// ExpandPath resolves ~ to the user's home directory.
func ExpandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return filepath.Join(home, path[2:])
	}
	return path
}
