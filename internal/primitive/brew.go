package primitive

import (
	"context"
	"fmt"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// BrewTapPrimitive manages a Homebrew tap.
type BrewTapPrimitive struct {
	Name string
	Deps []string
}

func (b *BrewTapPrimitive) ID() string         { return "brew_tap:" + b.Name }
func (b *BrewTapPrimitive) Type() string        { return "brew_tap" }
func (b *BrewTapPrimitive) DependsOn() []string { return b.Deps }

func (b *BrewTapPrimitive) Check(ctx context.Context) (Status, error) {
	output, err := runner.Run(ctx, "brew tap")
	if err != nil {
		return StatusError, fmt.Errorf("brew tap list failed: %w", err)
	}
	for _, line := range strings.Split(output, "\n") {
		if strings.TrimSpace(line) == b.Name {
			return StatusCurrent, nil
		}
	}
	return StatusMissing, nil
}

func (b *BrewTapPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("tap %s", b.Name),
		Commands:    []string{fmt.Sprintf("brew tap %s", b.Name)},
	}, nil
}

func (b *BrewTapPrimitive) Apply(ctx context.Context) (*Result, error) {
	_, err := runner.Run(ctx, fmt.Sprintf("brew tap %s", b.Name))
	if err != nil {
		return nil, fmt.Errorf("brew tap %s failed: %w", b.Name, err)
	}
	return &Result{Changed: true, Message: fmt.Sprintf("tapped %s", b.Name)}, nil
}

// BrewFormulaPrimitive manages a Homebrew formula.
type BrewFormulaPrimitive struct {
	Name string
	Deps []string
}

func (b *BrewFormulaPrimitive) ID() string         { return "brew_formula:" + b.Name }
func (b *BrewFormulaPrimitive) Type() string        { return "brew_formula" }
func (b *BrewFormulaPrimitive) DependsOn() []string { return b.Deps }

func (b *BrewFormulaPrimitive) Check(ctx context.Context) (Status, error) {
	if runner.RunSilent(ctx, fmt.Sprintf("brew list %s", b.Name)) {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (b *BrewFormulaPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("install formula %s", b.Name),
		Commands:    []string{fmt.Sprintf("brew install %s", b.Name)},
	}, nil
}

func (b *BrewFormulaPrimitive) Apply(ctx context.Context) (*Result, error) {
	_, err := runner.Run(ctx, fmt.Sprintf("brew install %s", b.Name))
	if err != nil {
		return nil, fmt.Errorf("brew install %s failed: %w", b.Name, err)
	}
	return &Result{Changed: true, Message: fmt.Sprintf("installed %s", b.Name)}, nil
}

// BrewCaskPrimitive manages a Homebrew cask.
type BrewCaskPrimitive struct {
	Name string
	Deps []string
}

func (b *BrewCaskPrimitive) ID() string         { return "brew_cask:" + b.Name }
func (b *BrewCaskPrimitive) Type() string        { return "brew_cask" }
func (b *BrewCaskPrimitive) DependsOn() []string { return b.Deps }

func (b *BrewCaskPrimitive) Check(ctx context.Context) (Status, error) {
	if runner.RunSilent(ctx, fmt.Sprintf("brew list --cask %s", b.Name)) {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (b *BrewCaskPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("install cask %s", b.Name),
		Commands:    []string{fmt.Sprintf("brew install --cask %s", b.Name)},
	}, nil
}

func (b *BrewCaskPrimitive) Apply(ctx context.Context) (*Result, error) {
	_, err := runner.Run(ctx, fmt.Sprintf("brew install --cask %s", b.Name))
	if err != nil {
		return nil, fmt.Errorf("brew install --cask %s failed: %w", b.Name, err)
	}
	return &Result{Changed: true, Message: fmt.Sprintf("installed cask %s", b.Name)}, nil
}
