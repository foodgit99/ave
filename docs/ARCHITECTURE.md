# AVE v0 — Architecture & trust model

## Why this shape

The brief asks for an AI organisation, not a chatbot: many specialised agents, one shared memory,
hard financial guardrails, an owner who stays in control while offline. v0 maps that onto three
things that already exist and are cheap to run:

| Brief component | v0 implementation |
|---|---|
| Owner Command Center | `dashboard/index.html` (supabase-js, RLS, magic-link auth) |
| Venture Orchestrator | Hyperagent named agent on live mode; delegates to specialists |
| Opportunity Intelligence | AVE Scout |
| Evaluation & Strategy | AVE Strategist |
| Validation & Experimentation | AVE Validator |
| Venture Builder | AVE Builder (ships to the owner's GitHub + static hosting) |
| Distribution Engine | AVE Distributor (plugs into Distribution OS / Brandie later) |
| Commercial Operations | folded into Builder (maintenance) + Distributor (nurture) for v0 |
| Finance & Capital | Postgres guardrail triggers (rules layer) + AVE Treasurer (reconciliation) |
| Performance & Learning | AVE Analyst + `metrics`, `decisions`, `reports(period='learning')` |
| Portfolio Manager | AVE Analyst recommendations + `v_portfolio` + `policies.max_active_ventures` |
| Shared memory / governance | Supabase schema; `agent_runs`, `decisions`, `approvals`, `notifications`; kill switch |

## Trust boundaries

0. **AVE is never in the money path and never owns a venture asset.** The owner's capital stays in
   the owner's bank and provider accounts; the ledger is a record, not a wallet. Revenue lands in the
   owner's storefront/payment account; AVE takes no share of it and charges a flat platform fee
   outside this ledger. Every repo, domain, storefront, ad account and host is created in the owner's
   accounts and registered in `venture_assets` with `owner_controlled = true` (a CHECK constraint, not
   a convention). If the owner leaves, they keep everything and nothing breaks. `docs/BOUNDARIES.md`
   explains why this is the line that keeps AVE a software product rather than an investment scheme.

1. **LLM agents are untrusted with money.** They can only *ask*. The adjudication trigger is plain
   SQL and ignores whatever status the agent wrote. This is the "separate, rules-based risk-control
   layer that enforces spending limits independently of AI recommendations" from the brief.
2. **Owner identity = Supabase JWT.** Approvals, policy edits, capital movements and the kill switch
   check `auth.uid()`. Agents reach the database through a service connection with no JWT, so they
   cannot forge an approval even with full SQL access. (They *could* drop a trigger — v0 accepts this
   because the agents run on the owner's own Hyperagent account; the hardening step is a restricted
   `ave_agent` Postgres role with INSERT-only grants on `spend_requests`, `ledger`, `decisions`,
   `metrics`, `agent_runs`, `opportunities`, `experiments`, `reports`, `notifications` and UPDATE on a
   whitelist of columns. The schema is written so that role can be added without changes.)
3. **Facts are immutable.** `ledger` and `decisions` cannot be updated or deleted. Corrections are
   new rows (`adjustment`).
4. **Forecast ≠ actual.** Only `verified` revenue with an `external_ref` counts anywhere. The
   OwnerReport schema carries a mandatory disclaimer string.

## The owner's edge is an input, not a nice-to-have

`owner_edge` (audience, domain, channels, assets, geography, hours) is read by the Scout, Strategist,
Validator and Distributor before they do anything, and discovery is refused by trigger until it is
complete. The reason is first-principles: an opportunity a general model can surface for one owner it
can surface for all of them, so durable margin has to come from something the owner supplies.
`edge_fit_score` is on every packet and proposal and `policies.min_edge_fit_score` is a hard gate.

## Dependency risk is measured, not assumed

Each `agent_runs` row carries `model`, `tokens_in`, `tokens_out`, `cost_cents`. `v_cost_of_intelligence`
shows intelligence cost next to cash spent and verified revenue per venture. A venture that looks
profitable in cash and unprofitable all-in is reported as unprofitable; a rising cost-per-run with flat
revenue is the early signal that a model-price or platform-policy change has repriced the portfolio.

## Coordination model

Agents do not talk to each other. The Orchestrator briefs a specialist (full context, venture_id,
budget, deadline, expected packet), the specialist works, writes its packet and a `decisions` row to
Supabase, updates its `agent_runs` row, and finishes. The next Orchestrator tick reads the database
and decides what happens next. This is slower than a chat between agents but it is auditable,
restartable and cheap, and it matches how the owner reads the system (through the same tables).

## Capital arithmetic

```
available = capital_in − capital_out − expenses + verified_revenue − refunds − reserved
reserved  = Σ spend_requests in (auto_approved, approved) and not expired
```
Reserved money is counted against capital the moment a request is approved, so two agents cannot
each be approved for the last $20. Requests expire after 7 days; the Treasurer sweeps them.

## Autonomy is a level, and the level is a row

`policies.autonomy_level` (1 Assisted, 2 Supervised, 3 Conditional, 4 High) decides what agents may
do without asking. A trigger applies the level's preset to the existing policy fields, so the level
is not a second control system; it is a named, auditable way of setting the first one. Graduation is
checked against the owner's own ledger (`fn_level_evidence`): Level 3 needs 3 completed ventures and
a published snapshot; Level 4 needs 10, a published snapshot and one venture whose verified revenue
beat its cash plus intelligence cost. Level 5 is refused by constraint. See `docs/FIVE_LEVELS.md`.

## Proof before customers

`policies.dogfood_mode` (default on) caps every venture at $100 with per-stage caps and flags it
`dogfood`. The Treasurer drafts `public_ledger_snapshots` from `fn_build_ledger_snapshot()`; only the
owner can publish; `dashboard/ledger.html` renders published snapshots to anyone with the link. The
public ledger — kills included — is AVE's proof, marketing and moat at once. See `docs/DOGFOOD_RUN.md`.

## Adding the hardening later (in order)

1. `ave_agent` role + column grants (removes the "agent could drop a trigger" caveat).
2. Payment-provider webhook → `ledger` revenue rows inserted and verified by code, not by an agent.
3. Multi-owner: already supported by RLS; add owner invites and per-owner Hyperagent agent sets.
4. Operations agent when any venture has > 20 paying customers.
5. Distribution OS integration: Distributor hands `DistributionPlan` to Brandie's campaign brain —
   still running on the owner's own Meta ad account via the official Marketing API.
6. Multi-tenant platform shell (agency workspaces): flat subscription billing for AVE itself lives
   here, deliberately in a different schema from venture ledgers.
