package primitive

import (
	"context"
	"fmt"
)

// ReminderPrimitive prints a manual action reminder during sync.
// It always reports as StatusMissing so it prints every time.
// Apply just prints the reminder, it never changes anything.
type ReminderPrimitive struct {
	Name string
	Msg  string
}

func (r *ReminderPrimitive) ID() string         { return "reminder:" + r.Name }
func (r *ReminderPrimitive) Type() string        { return "reminder" }
func (r *ReminderPrimitive) DependsOn() []string { return nil }

func (r *ReminderPrimitive) Check(_ context.Context) (Status, error) {
	// Always show as missing so the reminder prints.
	return StatusMissing, nil
}

func (r *ReminderPrimitive) Plan(_ context.Context, _ Status) (*Action, error) {
	return &Action{
		Description: r.Msg,
	}, nil
}

func (r *ReminderPrimitive) Apply(_ context.Context) (*Result, error) {
	fmt.Printf("  [REMINDER] %s\n", r.Msg)
	return &Result{Changed: false, Message: r.Msg}, nil
}
