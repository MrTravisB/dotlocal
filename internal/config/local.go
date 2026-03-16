package config

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

// LocalOverrides represents the local.toml file content.
// It allows machine-specific additions and removals from the main config.
type LocalOverrides struct {
	Skips    []Skip    `toml:"skip"`
	Symlinks []Symlink `toml:"symlink"`
}

// Skip defines an entry to remove from the main config.
type Skip struct {
	Type   string `toml:"type"`   // primitive type, e.g. "symlink", "app", "brew_formula"
	Source string `toml:"source"` // for symlinks: matches source field
	Name   string `toml:"name"`   // for apps/brew/macos_default/editor_extension: matches name/id field
}

// LoadLocal reads local.toml from the repo directory if it exists.
// Returns nil (no error) if the file doesn't exist.
func LoadLocal(repoDir string) (*LocalOverrides, error) {
	path := filepath.Join(repoDir, "local.toml")

	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, nil
	}

	var overrides LocalOverrides
	if _, err := toml.DecodeFile(path, &overrides); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}

	return &overrides, nil
}

// ApplyOverrides merges local overrides into the main config.
// It appends new entries and removes skipped entries.
func ApplyOverrides(cfg *Config, overrides *LocalOverrides) {
	if overrides == nil {
		return
	}

	// Append local symlinks.
	cfg.Symlinks = append(cfg.Symlinks, overrides.Symlinks...)

	// Process skips.
	for _, skip := range overrides.Skips {
		switch skip.Type {
		case "symlink":
			cfg.Symlinks = filterSymlinks(cfg.Symlinks, skip.Source)
		case "app":
			cfg.Apps = filterApps(cfg.Apps, skip.Name)
		case "brew_formula":
			cfg.BrewFormulae = filterBrewFormulae(cfg.BrewFormulae, skip.Name)
		case "brew_cask":
			cfg.BrewCasks = filterBrewCasks(cfg.BrewCasks, skip.Name)
		case "macos_default":
			cfg.MacOSDefaults = filterMacOSDefaults(cfg.MacOSDefaults, skip.Name)
		case "editor_extension":
			cfg.EditorExtensions = filterEditorExtensions(cfg.EditorExtensions, skip.Name)
		}
	}
}

func filterSymlinks(items []Symlink, source string) []Symlink {
	result := items[:0]
	for _, item := range items {
		if item.Source != source {
			result = append(result, item)
		}
	}
	return result
}

func filterApps(items []App, name string) []App {
	result := items[:0]
	for _, item := range items {
		if item.Name != name {
			result = append(result, item)
		}
	}
	return result
}

func filterBrewFormulae(items []BrewFormula, name string) []BrewFormula {
	result := items[:0]
	for _, item := range items {
		if item.Name != name {
			result = append(result, item)
		}
	}
	return result
}

func filterBrewCasks(items []BrewCask, name string) []BrewCask {
	result := items[:0]
	for _, item := range items {
		if item.Name != name {
			result = append(result, item)
		}
	}
	return result
}

func filterMacOSDefaults(items []MacOSDefault, name string) []MacOSDefault {
	result := items[:0]
	for _, item := range items {
		key := item.Domain + ":" + item.Key
		if key != name {
			result = append(result, item)
		}
	}
	return result
}

func filterEditorExtensions(items []EditorExtension, name string) []EditorExtension {
	result := items[:0]
	for _, item := range items {
		if item.ID != name {
			result = append(result, item)
		}
	}
	return result
}
