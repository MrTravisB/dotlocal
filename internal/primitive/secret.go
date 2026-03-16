package primitive

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// SecretPrimitive manages environment variable secrets in ~/.secrets.
// On Check, it reads ~/.secrets to see if the variable is already defined.
// On Apply, it prompts the user for the value and appends it to ~/.secrets.
type SecretPrimitive struct {
	Name string
	Deps []string
}

func (s *SecretPrimitive) ID() string {
	return "secret:" + s.Name
}

func (s *SecretPrimitive) Type() string {
	return "secret"
}

func (s *SecretPrimitive) DependsOn() []string {
	return s.Deps
}

func (s *SecretPrimitive) Check(_ context.Context) (Status, error) {
	// First check the running environment.
	if os.Getenv(s.Name) != "" {
		return StatusCurrent, nil
	}
	// Also check ~/.secrets file directly (env may not be sourced in this process).
	if secretFileHasKey(s.Name) {
		return StatusCurrent, nil
	}
	return StatusMissing, nil
}

func (s *SecretPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	if status == StatusCurrent {
		return nil, nil
	}
	return &Action{
		Description: fmt.Sprintf("prompt for %s and write to ~/.secrets", s.Name),
	}, nil
}

func (s *SecretPrimitive) Apply(_ context.Context) (*Result, error) {
	secretsPath := secretsFilePath()

	// Ensure the file exists.
	if err := ensureSecretsFile(secretsPath); err != nil {
		return nil, fmt.Errorf("creating %s: %w", secretsPath, err)
	}

	// Prompt for value.
	fmt.Printf("  Enter value for %s (or press Enter to skip): ", s.Name)
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return &Result{Changed: false, Message: "no input"}, nil
	}
	value := strings.TrimSpace(scanner.Text())

	if value == "" {
		return &Result{Changed: false, Message: "skipped"}, nil
	}

	// Append to ~/.secrets.
	f, err := os.OpenFile(secretsPath, os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return nil, fmt.Errorf("opening %s: %w", secretsPath, err)
	}
	defer f.Close()

	line := fmt.Sprintf("export %s=\"%s\"\n", s.Name, value)
	if _, err := f.WriteString(line); err != nil {
		return nil, fmt.Errorf("writing to %s: %w", secretsPath, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("wrote %s to %s", s.Name, secretsPath),
	}, nil
}

// secretsFilePath returns the absolute path to ~/.secrets.
func secretsFilePath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return filepath.Join(os.Getenv("HOME"), ".secrets")
	}
	return filepath.Join(home, ".secrets")
}

// ensureSecretsFile creates ~/.secrets with a header if it doesn't exist.
func ensureSecretsFile(path string) error {
	if _, err := os.Stat(path); err == nil {
		return nil // already exists
	}

	header := "#!/usr/bin/env bash\n# Secrets and API keys. Sourced by ~/.zshrc.\n# This file is not tracked in git.\n\n"
	return os.WriteFile(path, []byte(header), 0600)
}

// secretFileHasKey checks if ~/.secrets contains an export line for the given key.
func secretFileHasKey(name string) bool {
	path := secretsFilePath()
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	prefix := "export " + name + "="
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, prefix) {
			// Check it's not empty: export KEY="" counts as not set.
			val := strings.TrimPrefix(trimmed, prefix)
			val = strings.Trim(val, "\"'")
			if val != "" {
				return true
			}
		}
	}
	return false
}
