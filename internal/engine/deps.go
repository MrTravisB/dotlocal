package engine

import (
	"fmt"
	"strings"

	"github.com/mrtravisb/dotlocal/internal/primitive"
)

// TopoSort takes a slice of primitives and returns them sorted so that
// dependencies come before dependents. If a primitive depends on an ID
// that doesn't exist in the slice, the dependency is silently ignored
// (it may be handled externally or is optional).
// Returns an error if a cycle is detected.
func TopoSort(prims []primitive.Primitive) ([]primitive.Primitive, error) {
	if len(prims) <= 1 {
		return prims, nil
	}

	// Build ID -> primitive lookup and ID -> index for stable ordering.
	byID := make(map[string]primitive.Primitive, len(prims))
	for _, p := range prims {
		byID[p.ID()] = p
	}

	// Build in-degree counts and reverse adjacency list (dependency -> dependents).
	// Only count edges where both ends are present in the input slice.
	inDegree := make(map[string]int, len(prims))
	dependents := make(map[string][]string, len(prims))

	for _, p := range prims {
		id := p.ID()
		if _, ok := inDegree[id]; !ok {
			inDegree[id] = 0
		}
		for _, dep := range p.DependsOn() {
			if _, exists := byID[dep]; !exists {
				continue // external/optional dependency, skip
			}
			inDegree[id]++
			dependents[dep] = append(dependents[dep], id)
		}
	}

	// Seed the queue with zero in-degree nodes, in their original order
	// to keep output deterministic when the graph allows flexibility.
	queue := make([]string, 0, len(prims))
	for _, p := range prims {
		if inDegree[p.ID()] == 0 {
			queue = append(queue, p.ID())
		}
	}

	sorted := make([]primitive.Primitive, 0, len(prims))
	for len(queue) > 0 {
		id := queue[0]
		queue = queue[1:]
		sorted = append(sorted, byID[id])

		for _, depID := range dependents[id] {
			inDegree[depID]--
			if inDegree[depID] == 0 {
				queue = append(queue, depID)
			}
		}
	}

	if len(sorted) != len(prims) {
		// Cycle detected: collect the primitives that were not emitted.
		emitted := make(map[string]bool, len(sorted))
		for _, p := range sorted {
			emitted[p.ID()] = true
		}
		var cycleIDs []string
		for _, p := range prims {
			if !emitted[p.ID()] {
				cycleIDs = append(cycleIDs, p.ID())
			}
		}
		return nil, fmt.Errorf("dependency cycle detected among primitives: %s", strings.Join(cycleIDs, ", "))
	}

	return sorted, nil
}
