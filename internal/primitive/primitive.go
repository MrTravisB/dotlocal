package primitive

import "context"

// Status represents the current state of a primitive relative to its desired state.
type Status int

const (
	StatusCurrent Status = iota // desired state already matches
	StatusMissing               // does not exist at all
	StatusDrift                 // exists but differs from desired
	StatusError                 // could not determine state
)

func (s Status) String() string {
	switch s {
	case StatusCurrent:
		return "current"
	case StatusMissing:
		return "missing"
	case StatusDrift:
		return "drift"
	case StatusError:
		return "error"
	default:
		return "unknown"
	}
}

// Action describes what the engine will do to bring a primitive to desired state.
type Action struct {
	Description string   // human-readable summary
	Commands    []string // shell commands that will run (for dry-run display)
}

// Result is the outcome of applying a primitive.
type Result struct {
	Changed bool
	Message string
}

// Primitive is the core abstraction. Every managed resource implements this.
type Primitive interface {
	// ID returns a unique identifier, e.g. "symlink:shell/.zshrc", "brew_formula:bat"
	ID() string

	// Type returns the primitive type, e.g. "symlink", "brew_formula"
	Type() string

	// DependsOn returns IDs of primitives that must be applied first.
	DependsOn() []string

	// Check inspects the current system state without modifying anything.
	Check(ctx context.Context) (Status, error)

	// Plan returns the action that Apply would take, given current status.
	Plan(ctx context.Context, status Status) (*Action, error)

	// Apply makes the system match the desired state.
	Apply(ctx context.Context) (*Result, error)
}
