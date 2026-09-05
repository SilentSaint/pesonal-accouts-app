# Financial goals and contribution projections

`FinancialGoal` is a user-defined target, not a claim on every account balance. A goal stores the
target amount and date, priority, lifecycle, an optional contribution rule, explicitly assigned
`GoalAllocation`s, and observed `GoalContribution`s. An allocation has a user-provided reference;
the application use case rejects a reference already assigned to a different goal.

Goals are persisted as `PK = USER#<verified-principal>`, `SK = GOAL#<goal-id>` records in
`ExpenseTrackerData`. Allocation claim records use `GOAL_ALLOCATION#<reference>` and are
conditionally transacted with the goal record, preserving the no-double-claim invariant under
concurrent writes. The principal comes exclusively from API Gateway's verified JWT claims.

## Projection contract

`ManageFinancialGoalUseCase.project` returns a prediction with formula
`financial-goal-projection:1.0.0`. It reports:

- amount remaining and calendar months through the target month;
- required monthly contribution;
- observed net monthly contribution rate from recorded evidence;
- projected completion date and monthly shortfall or surplus;
- source count, contribution evidence references, assumptions, confidence, warnings, and `asOf`.

Only contributions at or before `asOf` count. Zero or negative net observed progress does not
produce a completion date unless a positive contribution rule is configured. A positive required
contribution is tested against the cash-flow forecast's pre-contribution minimum balance; falling
below the user's preferred minimum produces `PREFERRED_MINIMUM_BALANCE_BREACH`.

## Cash-flow integration

The goal HTTP handler deliberately does not accept cash-flow numbers from a client. Until the
cash-flow forecast slice supplies `GoalCashFlowImpact` from authoritative server state, projections
state that missing forecast in their assumptions rather than asserting a balance risk. The `/v2/financial-goals`
route and corresponding Terraform Lambda/API Gateway route must be provisioned by the infrastructure
owner before this handler can be deployed or reached by the production Flutter client.
