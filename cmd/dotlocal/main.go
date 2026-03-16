package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/config"
	"github.com/mrtravisb/dotlocal/internal/engine"
	"github.com/mrtravisb/dotlocal/internal/primitive"
	"github.com/mrtravisb/dotlocal/internal/ui"
)

// version is set at build time via -ldflags.
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	// Global flags apply to all subcommands.
	globalFlags := flag.NewFlagSet("dotlocal", flag.ExitOnError)
	dryRun := globalFlags.Bool("dry-run", false, "show what would change without applying")
	failFast := globalFlags.Bool("fail-fast", false, "stop on first error")
	typeFilter := globalFlags.String("type", "", "comma-separated primitive types to include (e.g. symlink,brew_formula)")

	subcommand := os.Args[1]

	// Parse flags after the subcommand.
	if err := globalFlags.Parse(os.Args[2:]); err != nil {
		fmt.Fprintf(os.Stderr, "error: %s\n", err)
		os.Exit(1)
	}

	if subcommand == "version" {
		fmt.Printf("dotlocal %s\n", version)
		return
	}

	repoDir := findRepoDir()
	cfg, err := config.Load(repoDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %s\n", err)
		os.Exit(1)
	}

	// Apply local.toml overrides if present.
	overrides, err := config.LoadLocal(repoDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error loading local.toml: %s\n", err)
		os.Exit(1)
	}
	if overrides != nil {
		config.ApplyOverrides(cfg, overrides)
	}

	allPrimitives := buildPrimitives(cfg, repoDir)
	primitives := filterPrimitives(allPrimitives, *typeFilter)

	display := ui.New()

	switch subcommand {
	case "sync":
		eng := engine.New(primitives, display, *dryRun, *failFast)
		if err := eng.Sync(context.Background()); err != nil {
			fmt.Fprintf(os.Stderr, "error: %s\n", err)
			os.Exit(1)
		}
	case "status":
		eng := engine.New(primitives, display, false, *failFast)
		if err := eng.Status(context.Background()); err != nil {
			fmt.Fprintf(os.Stderr, "error: %s\n", err)
			os.Exit(1)
		}
	case "list":
		for _, p := range primitives {
			fmt.Printf("%-15s %s\n", p.Type(), p.ID())
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", subcommand)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: dotlocal <subcommand> [flags]\n\n")
	fmt.Fprintf(os.Stderr, "Subcommands:\n")
	fmt.Fprintf(os.Stderr, "  sync      apply configuration (check-plan-apply)\n")
	fmt.Fprintf(os.Stderr, "  status    check current state without making changes\n")
	fmt.Fprintf(os.Stderr, "  list      print all managed primitives\n")
	fmt.Fprintf(os.Stderr, "  version   print version\n")
	fmt.Fprintf(os.Stderr, "\nFlags:\n")
	fmt.Fprintf(os.Stderr, "  --dry-run     show what would change without applying\n")
	fmt.Fprintf(os.Stderr, "  --fail-fast   stop on first error\n")
	fmt.Fprintf(os.Stderr, "  --type=TYPES  comma-separated primitive types to include\n")
}

// findRepoDir walks up from the current working directory looking for dotlocal.toml.
// Falls back to the current directory if not found.
func findRepoDir() string {
	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: cannot determine working directory: %s\n", err)
		os.Exit(1)
	}

	for {
		if _, err := os.Stat(filepath.Join(dir, "dotlocal.toml")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached filesystem root without finding dotlocal.toml.
			// Fall back to the original working directory.
			cwd, _ := os.Getwd()
			return cwd
		}
		dir = parent
	}
}

// buildPrimitives converts config entries into primitive instances.
func buildPrimitives(cfg *config.Config, repoDir string) []primitive.Primitive {
	backupDir := config.ExpandPath(cfg.Settings.BackupDir)

	var prims []primitive.Primitive

	// Brew taps (auto-depend on cli:homebrew).
	for _, t := range cfg.BrewTaps {
		deps := appendIfMissing(t.DependsOn, "cli:homebrew")
		prims = append(prims, &primitive.BrewTapPrimitive{
			Name: t.Name,
			Deps: deps,
		})
	}

	// Brew formulae (auto-depend on cli:homebrew).
	for _, f := range cfg.BrewFormulae {
		deps := appendIfMissing(f.DependsOn, "cli:homebrew")
		prims = append(prims, &primitive.BrewFormulaPrimitive{
			Name: f.Name,
			Deps: deps,
		})
	}

	// Brew casks (auto-depend on cli:homebrew).
	for _, c := range cfg.BrewCasks {
		deps := appendIfMissing(c.DependsOn, "cli:homebrew")
		prims = append(prims, &primitive.BrewCaskPrimitive{
			Name: c.Name,
			Deps: deps,
		})
	}

	// Desktop apps.
	for _, a := range cfg.Apps {
		prims = append(prims, &primitive.AppPrimitive{
			Name: a.Name,
			URL:  a.URL,
			Deps: a.DependsOn,
		})
	}

	// CLI tools.
	for _, ci := range cfg.CLIs {
		prims = append(prims, &primitive.CLIPrimitive{
			Name:       ci.Name,
			CheckCmd:   ci.Check,
			InstallCmd: ci.Install,
			Deps:       ci.DependsOn,
		})
	}

	// Git repos.
	for _, gr := range cfg.GitRepos {
		prims = append(prims, &primitive.GitRepoPrimitive{
			URL:       gr.URL,
			Target:    config.ExpandPath(gr.Target),
			Shallow:   gr.Shallow,
			Method:    gr.Method,
			Install:   gr.Install,
			PostClone: gr.PostClone,
			Deps:      gr.DependsOn,
		})
	}

	// Symlinks.
	for _, s := range cfg.Symlinks {
		source := config.ExpandPath(s.Source)
		if !filepath.IsAbs(source) {
			source = filepath.Join(repoDir, source)
		}
		target := config.ExpandPath(s.Target)

		prims = append(prims, &primitive.SymlinkPrimitive{
			Source:    source,
			Target:    target,
			RepoDir:   repoDir,
			BackupDir: backupDir,
			Deps:      s.DependsOn,
		})
	}

	// Copies.
	for _, c := range cfg.Copies {
		source := config.ExpandPath(c.Source)
		if !filepath.IsAbs(source) {
			source = filepath.Join(repoDir, source)
		}
		target := config.ExpandPath(c.Target)

		patterns := []string{"*"}
		if c.Glob != "" {
			patterns = strings.Split(c.Glob, ",")
			for i := range patterns {
				patterns[i] = strings.TrimSpace(patterns[i])
			}
		}

		prims = append(prims, &primitive.CopyPrimitive{
			Source:       source,
			Target:       target,
			GlobPatterns: patterns,
			RepoDir:      repoDir,
			BackupDir:    backupDir,
			Deps:         c.DependsOn,
		})
	}

	// Editor extensions.
	editors := discoverEditors()
	for _, ext := range cfg.EditorExtensions {
		if ext.File != "" {
			// Load extension IDs from file.
			extFile := filepath.Join(repoDir, ext.File)
			ids, err := loadExtensionIDs(extFile)
			if err != nil {
				fmt.Fprintf(os.Stderr, "warning: could not load extensions from %s: %s\n", extFile, err)
				continue
			}
			for _, id := range ids {
				prims = append(prims, &primitive.EditorExtensionPrimitive{
					ExtID:   id,
					Editors: editors,
					Deps:    ext.DependsOn,
				})
			}
		} else if ext.ID != "" {
			prims = append(prims, &primitive.EditorExtensionPrimitive{
				ExtID:   ext.ID,
				Editors: editors,
				Deps:    ext.DependsOn,
			})
		}
	}

	// macOS defaults.
	for _, d := range cfg.MacOSDefaults {
		prims = append(prims, &primitive.MacOSDefaultPrimitive{
			Domain:    d.Domain,
			Key:       d.Key,
			ValueType: d.Type,
			Value:     d.Value,
			Deps:      d.DependsOn,
		})
	}

	// Launchd services.
	for _, l := range cfg.Launchds {
		source := filepath.Join(repoDir, l.Source)
		prims = append(prims, &primitive.LaunchdPrimitive{
			Label:        l.Label,
			Source:       source,
			Target:       config.ExpandPath(l.Target),
			TemplateVars: l.TemplateVars,
			Deps:         l.DependsOn,
		})
	}

	// Docker stacks.
	for _, ds := range cfg.DockerStacks {
		composeFile := filepath.Join(repoDir, ds.ComposeFile)
		startScript := ""
		if ds.StartScript != "" {
			startScript = filepath.Join(repoDir, ds.StartScript)
		}
		prims = append(prims, &primitive.DockerStackPrimitive{
			Name:        ds.Name,
			ComposeFile: composeFile,
			StartScript: startScript,
			Requires:    ds.Requires,
			Deps:        ds.DependsOn,
		})
	}

	// Secrets.
	for _, s := range cfg.Secrets {
		prims = append(prims, &primitive.SecretPrimitive{
			Name: s.Name,
			Deps: s.DependsOn,
		})
	}

	// Encrypted assets.
	for _, e := range cfg.Encrypteds {
		archive := filepath.Join(repoDir, e.Archive)
		target := e.Target
		if !filepath.IsAbs(target) {
			target = filepath.Join(repoDir, target)
		}
		prims = append(prims, &primitive.EncryptedPrimitive{
			EID:       e.ID,
			Archive:   archive,
			Target:    target,
			KeySource: e.KeySource,
			OpItem:    e.OpItem,
			KeyCache:  config.ExpandPath(e.KeyCache),
			Deps:      e.DependsOn,
		})
	}

	// Patches.
	for _, p := range cfg.Patches {
		prims = append(prims, &primitive.PatchPrimitive{
			PID:         p.ID,
			Description: p.Description,
			Target:      config.ExpandPath(p.Target),
			Requires:    p.Requires,
			CheckCmd:    p.Check,
			ApplyCmd:    p.Apply,
			Backup:      p.Backup,
			BackupDir:   backupDir,
		})
	}

	// Prompts.
	for _, pr := range cfg.Prompts {
		var fields []primitive.PromptField
		for _, f := range pr.Fields {
			fields = append(fields, primitive.PromptField{
				Name:   f.Name,
				Prompt: f.Prompt,
			})
		}
		prims = append(prims, &primitive.PromptPrimitive{
			PID:        pr.ID,
			Desc:       pr.Description,
			CheckCmd:   pr.Check,
			Fields:     fields,
			ApplyCmds:  pr.Apply,
			ConfirmMsg: pr.Confirm,
			Handler:    pr.Handler,
		})
	}

	return prims
}

// discoverEditors finds installed editors that support --install-extension.
func discoverEditors() []primitive.Editor {
	candidates := []primitive.Editor{
		{Name: "Antigravity", Bin: config.ExpandPath("~/.antigravity/antigravity/bin/antigravity")},
		{Name: "VS Code Insiders", Bin: "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"},
	}
	var found []primitive.Editor
	for _, e := range candidates {
		if _, err := os.Stat(e.Bin); err == nil {
			found = append(found, e)
		}
	}
	return found
}

// loadExtensionIDs reads a newline-delimited file of extension IDs, skipping comments and blanks.
func loadExtensionIDs(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		ids = append(ids, line)
	}
	return ids, nil
}

// filterPrimitives returns only primitives whose Type matches one of the
// comma-separated types. If typeFilter is empty, all primitives are returned.
func filterPrimitives(prims []primitive.Primitive, typeFilter string) []primitive.Primitive {
	if typeFilter == "" {
		return prims
	}

	allowed := make(map[string]bool)
	for _, t := range strings.Split(typeFilter, ",") {
		t = strings.TrimSpace(t)
		if t != "" {
			allowed[t] = true
		}
	}

	var filtered []primitive.Primitive
	for _, p := range prims {
		if allowed[p.Type()] {
			filtered = append(filtered, p)
		}
	}
	return filtered
}

// appendIfMissing returns a copy of deps with val appended if not already present.
func appendIfMissing(deps []string, val string) []string {
	for _, d := range deps {
		if d == val {
			return deps
		}
	}
	result := make([]string, len(deps), len(deps)+1)
	copy(result, deps)
	return append(result, val)
}
