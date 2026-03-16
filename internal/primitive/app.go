package primitive

import (
	"bufio"
	"context"
	"fmt"
	"os"
)

// AppPrimitive manages a desktop application installed in /Applications/.
// It checks for the presence of the .app bundle and interactively prompts
// the user to install missing applications.
type AppPrimitive struct {
	Name string
	URL  string
	Deps []string
}

func (a *AppPrimitive) ID() string         { return "app:" + a.Name }
func (a *AppPrimitive) Type() string        { return "app" }
func (a *AppPrimitive) DependsOn() []string { return a.Deps }

func (a *AppPrimitive) Check(_ context.Context) (Status, error) {
	appPath := fmt.Sprintf("/Applications/%s.app", a.Name)
	if _, err := os.Stat(appPath); err == nil {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (a *AppPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("install %s from %s", a.Name, a.URL),
	}, nil
}

func (a *AppPrimitive) Apply(_ context.Context) (*Result, error) {
	appPath := fmt.Sprintf("/Applications/%s.app", a.Name)
	scanner := bufio.NewScanner(os.Stdin)

	for {
		fmt.Fprintf(os.Stderr, "  %s is not installed.\n", a.Name)
		fmt.Fprintf(os.Stderr, "  Download: %s\n", a.URL)
		fmt.Fprintf(os.Stderr, "  Press Enter after installing, or type 'skip' to continue.\n")

		if !scanner.Scan() {
			return nil, fmt.Errorf("reading stdin: %w", scanner.Err())
		}

		input := scanner.Text()
		if input == "skip" {
			return &Result{Changed: false, Message: "skipped"}, nil
		}

		if _, err := os.Stat(appPath); err == nil {
			return &Result{Changed: true, Message: fmt.Sprintf("installed %s", a.Name)}, nil
		}
	}
}
