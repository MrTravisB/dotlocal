package primitive

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/mrtravisb/dotlocal/internal/runner"
)

// EncryptedPrimitive manages age-encrypted archives that require a key from 1Password.
type EncryptedPrimitive struct {
	EID       string   // e.g. "fonts"
	Archive   string   // absolute path to .age file
	Target    string   // absolute path to extract target
	KeySource string   // "1password"
	OpItem    string   // 1password item path
	KeyCache  string   // absolute path to cached key file
	Deps      []string
}

func (e *EncryptedPrimitive) ID() string {
	return "encrypted:" + e.EID
}

func (e *EncryptedPrimitive) Type() string {
	return "encrypted"
}

func (e *EncryptedPrimitive) DependsOn() []string {
	return e.Deps
}

func (e *EncryptedPrimitive) Check(_ context.Context) (Status, error) {
	if !runner.CommandExists("op") {
		return StatusError, fmt.Errorf("1Password CLI (op) not found")
	}

	// Archive must exist.
	if _, err := os.Stat(e.Archive); os.IsNotExist(err) {
		return StatusError, fmt.Errorf("archive not found: %s", e.Archive)
	}

	// If the key cache exists, we have already decrypted at least once.
	if _, err := os.Stat(e.KeyCache); err == nil {
		return StatusCurrent, nil
	}

	return StatusMissing, nil
}

func (e *EncryptedPrimitive) Plan(_ context.Context, status Status) (*Action, error) {
	switch status {
	case StatusCurrent:
		return nil, nil
	case StatusMissing:
		return &Action{
			Description: fmt.Sprintf("decrypt %s using key from 1Password", e.EID),
			Commands: []string{
				fmt.Sprintf("op read %q > %s", e.OpItem, e.KeyCache),
				fmt.Sprintf("age -d -i %s < %s | tar xzf - -C %s", e.KeyCache, e.Archive, e.Target),
			},
		}, nil
	default:
		return nil, fmt.Errorf("unexpected status: %s", status)
	}
}

func (e *EncryptedPrimitive) Apply(ctx context.Context) (*Result, error) {
	// Verify 1Password sign-in by listing accounts.
	if !runner.RunSilent(ctx, "op account list") {
		return nil, fmt.Errorf("not signed into 1Password; run 'eval $(op signin)' first")
	}

	// Fetch the decryption key from 1Password.
	cmd := fmt.Sprintf("op read %q", e.OpItem)
	key, err := runner.Run(ctx, cmd)
	if err != nil {
		return nil, fmt.Errorf("reading key from 1Password: %w", err)
	}

	// Ensure the key cache directory exists and write the key.
	cacheDir := filepath.Dir(e.KeyCache)
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return nil, fmt.Errorf("creating key cache directory %s: %w", cacheDir, err)
	}
	if err := os.WriteFile(e.KeyCache, []byte(key), 0o600); err != nil {
		return nil, fmt.Errorf("writing key cache %s: %w", e.KeyCache, err)
	}

	// Ensure the extraction target directory exists.
	if err := os.MkdirAll(e.Target, 0o755); err != nil {
		return nil, fmt.Errorf("creating target directory %s: %w", e.Target, err)
	}

	// Decrypt and extract.
	decrypt := fmt.Sprintf("age -d -i %s < %s | tar xzf - -C %s", e.KeyCache, e.Archive, e.Target)
	if _, err := runner.Run(ctx, decrypt); err != nil {
		return nil, fmt.Errorf("decrypting %s: %w", e.EID, err)
	}

	return &Result{
		Changed: true,
		Message: fmt.Sprintf("decrypted and extracted %s to %s", e.EID, e.Target),
	}, nil
}
