package primitive

import (
	"context"
	"fmt"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// Editor represents a VS Code-compatible editor binary.
type Editor struct {
	Name string // display name, e.g. "Antigravity"
	Bin  string // path to editor binary
}

// EditorExtensionPrimitive manages a VS Code / Antigravity extension.
type EditorExtensionPrimitive struct {
	ExtID   string
	Editors []Editor
	Deps    []string
}

func (e *EditorExtensionPrimitive) ID() string         { return "editor_extension:" + e.ExtID }
func (e *EditorExtensionPrimitive) Type() string        { return "editor_extension" }
func (e *EditorExtensionPrimitive) DependsOn() []string { return e.Deps }

func (e *EditorExtensionPrimitive) Check(ctx context.Context) (Status, error) {
	available, missing := e.partition(ctx)
	if len(available) == 0 {
		return StatusError, fmt.Errorf("no editors available for extension %s", e.ExtID)
	}
	if len(missing) == 0 {
		return StatusCurrent, nil
	}
	return StatusDrift, nil
}

func (e *EditorExtensionPrimitive) Plan(ctx context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	_, missing := e.partition(ctx)
	var cmds []string
	var names []string
	for _, ed := range missing {
		cmds = append(cmds, fmt.Sprintf("%s --install-extension %s", ed.Bin, e.ExtID))
		names = append(names, ed.Name)
	}
	return &Action{
		Description: fmt.Sprintf("install %s in %s", e.ExtID, strings.Join(names, ", ")),
		Commands:    cmds,
	}, nil
}

func (e *EditorExtensionPrimitive) Apply(ctx context.Context) (*Result, error) {
	_, missing := e.partition(ctx)
	if len(missing) == 0 {
		return &Result{Changed: false, Message: fmt.Sprintf("%s already installed in all editors", e.ExtID)}, nil
	}
	var installed []string
	var errs []string
	for _, ed := range missing {
		cmd := fmt.Sprintf("%s --install-extension %s", ed.Bin, e.ExtID)
		if _, err := runner.Run(ctx, cmd); err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", ed.Name, err))
			continue
		}
		installed = append(installed, ed.Name)
	}
	if len(errs) > 0 && len(installed) == 0 {
		return nil, fmt.Errorf("install %s failed: %s", e.ExtID, strings.Join(errs, "; "))
	}
	msg := fmt.Sprintf("installed %s in %s", e.ExtID, strings.Join(installed, ", "))
	if len(errs) > 0 {
		msg += fmt.Sprintf(" (failed: %s)", strings.Join(errs, "; "))
	}
	return &Result{Changed: true, Message: msg}, nil
}

// partition splits Editors into those that have the extension installed and those that don't.
// Editors whose binary is not found are silently skipped.
func (e *EditorExtensionPrimitive) partition(ctx context.Context) (available, missing []Editor) {
	extLower := strings.ToLower(e.ExtID)
	for _, ed := range e.Editors {
		if !runner.CommandExists(ed.Bin) {
			continue
		}
		output, err := runner.Run(ctx, fmt.Sprintf("%s --list-extensions", ed.Bin))
		if err != nil {
			continue
		}
		found := false
		for _, line := range strings.Split(output, "\n") {
			if strings.ToLower(strings.TrimSpace(line)) == extLower {
				found = true
				break
			}
		}
		if found {
			available = append(available, ed)
		} else {
			available = append(available, ed)
			missing = append(missing, ed)
		}
	}
	return available, missing
}
