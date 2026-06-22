# Optimization Advisory Harness

Optimization is a recommendation workflow, not an automatic edit loop.

## Trigger Conditions

Optimization analysis may run only when one of these is true:

- The user, Shogun, or Karo explicitly asks for optimization, refactoring, performance, maintainability, or simplification review.
- An inbox message has `type: optimization_requested`.
- A final audit already in progress finds a material objective issue: slow verification, repeated failures, unsafe complexity, duplicated logic causing real maintenance risk, or a release-blocking performance concern.
- The current command's acceptance criteria explicitly include optimization.

Do not start optimization because work merely looks improvable. Optional cleanup must not block completion.

## Advisory Output

When giving optimization advice, include:

- `kind`: performance | maintainability | simplification | reliability | security-adjacent
- `evidence`: exact file, report, command result, or queue entry
- `impact`: what user-visible or operator-visible problem this creates
- `risk`: why changing it now may be risky
- `recommendation`: the smallest next action
- `priority`: must_fix | should_fix | optional
- `requires_command`: true when Shogun/Karo must open normal task flow before anyone edits

## Boundaries

- Do not edit code only because an optimization was noticed.
- Do not assign Ashigaru directly from an optimization advisory.
- Do not block `done` for optional cleanup.
- Do not run broad performance experiments unless they are part of the assigned task.
- Do not override security findings: security and data-loss risks remain audit findings, not optional optimization.

## Flow

1. Identify whether optimization is actually in scope.
2. Gather only the evidence needed to justify the advisory.
3. Write the advisory into the role's normal report.
4. If edits are needed, ask Shogun or Karo to create a normal command/task.
5. Return to standby after the report or direct answer.
