package engine

import (
	"context"
	"fmt"

	"github.com/mrtravisb/dotlocal/internal/primitive"
	"github.com/mrtravisb/dotlocal/internal/ui"
)

// Engine orchestrates check-plan-apply across all primitives.
type Engine struct {
	primitives []primitive.Primitive
	ui         *ui.UI
	dryRun     bool
	failFast   bool
}

// New creates an Engine that will process the given primitives in order.
func New(primitives []primitive.Primitive, ui *ui.UI, dryRun, failFast bool) *Engine {
	return &Engine{
		primitives: primitives,
		ui:         ui,
		dryRun:     dryRun,
		failFast:   failFast,
	}
}

// Sync runs the three-phase check-plan-apply loop across all primitives.
func (e *Engine) Sync(ctx context.Context) error {
	// Validate dependency graph before doing anything.
	if err := ValidateDeps(e.primitives); err != nil {
		return fmt.Errorf("dependency validation failed: %w", err)
	}

	total := len(e.primitives)
	current := 0
	changed := 0
	errored := 0

	// Phase 1: Check -- determine current status of every primitive.
	type checkResult struct {
		prim   primitive.Primitive
		status primitive.Status
		err    error
	}
	results := make([]checkResult, 0, total)

	for _, p := range e.primitives {
		status, err := p.Check(ctx)
		results = append(results, checkResult{prim: p, status: status, err: err})
		if err != nil {
			e.ui.Error(p.ID(), err.Error())
			errored++
			if e.failFast {
				e.ui.Summary(total, current, changed, errored)
				return fmt.Errorf("check failed for %s: %w", p.ID(), err)
			}
		} else if status == primitive.StatusCurrent {
			e.ui.OK(p.ID(), "")
			current++
		}
	}

	// Phase 2: Plan -- for non-current primitives, determine what needs to change.
	// In dry-run mode, print the plan and return.
	if e.dryRun {
		for _, r := range results {
			if r.err != nil || r.status == primitive.StatusCurrent {
				continue
			}
			action, err := r.prim.Plan(ctx, r.status)
			if err != nil {
				e.ui.Error(r.prim.ID(), fmt.Sprintf("plan failed: %s", err))
				continue
			}
			if action != nil {
				e.ui.DryRun(r.prim.ID(), action.Description)
			}
		}
		e.ui.Summary(total, current, 0, errored)
		return nil
	}

	// Phase 3: Apply -- for non-current primitives, apply changes in
	// topologically sorted order so dependencies are applied first.
	actionable := make([]primitive.Primitive, 0, len(results))
	for _, r := range results {
		if r.err != nil || r.status == primitive.StatusCurrent {
			continue
		}
		actionable = append(actionable, r.prim)
	}

	sorted, err := TopoSort(actionable)
	if err != nil {
		e.ui.Summary(total, current, changed, errored)
		return fmt.Errorf("dependency resolution failed: %w", err)
	}

	for _, p := range sorted {
		result, err := p.Apply(ctx)
		if err != nil {
			e.ui.Error(p.ID(), err.Error())
			errored++
			if e.failFast {
				e.ui.Summary(total, current, changed, errored)
				return fmt.Errorf("apply failed for %s: %w", p.ID(), err)
			}
			continue
		}

		if result.Changed {
			e.ui.Changed(p.ID(), result.Message)
			changed++
		} else {
			e.ui.OK(p.ID(), result.Message)
			current++
		}
	}

	e.ui.Summary(total, current, changed, errored)

	if errored > 0 {
		return fmt.Errorf("%d primitive(s) failed", errored)
	}
	return nil
}

// Status runs check-only mode: inspect every primitive and print its status.
// No mutations are performed.
func (e *Engine) Status(ctx context.Context) error {
	if err := ValidateDeps(e.primitives); err != nil {
		return fmt.Errorf("dependency validation failed: %w", err)
	}

	errored := 0
	for _, p := range e.primitives {
		status, err := p.Check(ctx)
		if err != nil {
			e.ui.Error(p.ID(), err.Error())
			errored++
			if e.failFast {
				return fmt.Errorf("check failed for %s: %w", p.ID(), err)
			}
			continue
		}
		e.ui.StatusLine(p.ID(), status)
	}
	if errored > 0 {
		return fmt.Errorf("%d primitive(s) failed check", errored)
	}
	return nil
}
