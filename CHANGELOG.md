# Changelog

## v0.2 — "Autonomous Venturing" (9 Nov 2026)

Names the category and makes its defining idea, levels of autonomy, a real setting.

* **Migration 0003:** `policies.autonomy_level` (1 to 4, default 2), `level_custom`, `level_changed_at`;
  `fn_level_name`, `fn_level_evidence`, `trg_policy_level`. Setting a level applies its preset; moving
  up to Level 3 (3 completed ventures, 1 published ledger) or Level 4 (10 completed, 1 published, 1
  venture that beat its all-in cost) is refused until earned; Level 5 is refused always. The level is
  stamped on ledger snapshots.
* **Dashboard:** the policy card is now "Autonomy level · who is at the wheel" with a level selector,
  graduation progress and level-language labels; "Kill switch" reads "Emergency brake"; "Dogfood mode"
  reads "Proof mode". Schema names are unchanged. The public ledger page shows the level a run used.
* **Docs:** `docs/FIVE_LEVELS.md` (manifesto and standard), `docs/POSITIONING.md` rewritten around
  Autonomous Venturing.
* **Agents:** COMMON.md and the Orchestrator read and report the level and never lobby for a higher one.

Tests: 61/61 (47 + 14 level rules).

## v0.1 — "Reshape" (31 Oct 2026)

Implements the Roast My Idea council verdict (RESHAPE, medium confidence). Four decisions, encoded
in the database, the agent prompts, the protocol and the docs:

1. **The buyer is an operator with an edge.** New `owner_edge` table; discovery refused by trigger
   until it is complete; `edge_fit` on every OpportunityPacket, `edge_fit_score` on every
   VentureProposal and venture; `policies.min_edge_fit_score` is a hard gate. Dashboard "Your edge" card.
2. **No custody, no carry.** Custody/investment language is hard-refused on spend requests;
   "custody, escrow, revenue share, carry, pooled capital, crowdfund" are forbidden keywords in every
   policy; OwnerReport disclaimer extended; `docs/BOUNDARIES.md` records the legal rationale with
   sources; `docs/POSITIONING.md` fixes the flat-subscription model.
3. **Every asset is the owner's.** New `venture_assets` registry with a CHECK that `owner_controlled`
   is true; launch gate requires an owner-controlled storefront/payment account and repo/hosting;
   `BuildSpec.assets` required; `DistributionPlan.channels[].account` required (official APIs on the
   owner's accounts only). Dashboard "Venture assets" card.
4. **Prove the loop before selling it.** `policies.dogfood_mode` (default on): $100 venture cap and
   per-stage caps (validate $40 / build $20 / distribute $40) enforced by trigger; `ventures.dogfood`
   flag; `docs/DOGFOOD_RUN.md` protocol; `public_ledger_snapshots` + `fn_build_ledger_snapshot()`;
   only the owner can publish; `dashboard/ledger.html` renders published snapshots for anyone.

Also: the wedge (`policies.allowed_solution_shapes`, digital products first, micro-SaaS opt-in);
cost-of-intelligence tracking (`agent_runs.model/tokens/cost_cents`, `v_cost_of_intelligence`,
shown next to cash in dashboard, reports and snapshots) for the council's dependency blind spot;
all eight agent prompts and COMMON.md rewritten for the above; "passive income" banned everywhere.

Tests: 47/47 (30 core + 17 reshape rules).

## v0 (31 Oct 2026)

Initial codebase: Supabase schema with rules-based spend guardrails, eight Hyperagent agent prompts,
JSON hand-off protocol, Owner Command Center dashboard, 30 guardrail tests.
