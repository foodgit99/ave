# The dogfood run: $100, 48 hours, one public ledger

The council's cheapest test and AVE's first job on every deployment. Build nothing new. Prove the loop
closes — discover → validate → build → distribute → measure → decide — on one small venture, with the
Treasurer logging every cent, and publish the ledger whether it won or died. A clean kill with a
published ledger is a **pass**. The test is of the engine, not of the venture.

## Preconditions

* `owner_edge` complete (`completed_at` set, `edge_statement` and at least one channel).
* `policies.dogfood_mode = true` (default). Stage caps `{"validate":4000,"build":2000,"distribute":4000}`,
  venture cap `10000` cents.
* Owner's own storefront account exists (Gumroad / Lemon Squeezy / Payhip / Paystack or Stripe payment
  link), owner's GitHub connected to the Builder, owner's hosting account (or GitHub Pages).
* `policies.public_ledger = true` if the owner intends to publish (they can flip it at the end).

## The clock

| Window | Stage | Who | Hard cap | Done when |
|---|---|---|---|---|
| H0–H6 | discover → evaluate → **validate** | Scout, Strategist, Validator | $40 | One OpportunityPacket chosen (edge_fit ≥ policy min); ExperimentSpec with a numeric threshold; the experiment is live (an offer with a real price to the owner's own audience first) |
| H6–H24 | **build** | Builder | $20 | Smallest digital product shipped to the owner's storefront; repo in owner's GitHub; `venture_assets` registered (storefront + repo at minimum) |
| H24–H44 | **distribute** | Distributor | $40 | One organic push to the owner's audience + one tiny paid tranche through the owner's own ad account via official API; funnel metrics in `metrics` |
| H44–H48 | **measure → decide → publish** | Analyst, Treasurer, Orchestrator, owner | $0 | DecisionRecord (any of scale/iterate/maintain/pause/kill); `fn_build_ledger_snapshot()` inserted into `public_ledger_snapshots`; owner publishes with one click |

Stage caps are enforced by trigger (`trg_spend_reshape_rules`); an agent that tries to exceed one gets
an error naming the cap, not a silent pending request. The validate stage may skip straight to kill if
the experiment fails its threshold — that is still a complete run.

## What the Orchestrator does at each tick in dogfood mode

1. If no dogfood venture is active: brief the Scout with `owner_edge` and the instruction *"one packet,
   digital product, reachable through the owner's own channel inside 48 hours."*
2. Advance stages strictly on packets; refuse to let a stage run past its window — if validate has not
   produced a readable result by H6, record `inconclusive` and either iterate once inside the cap or kill.
3. At H44 (or on kill), ask the Treasurer for the snapshot and file an `approvals` row of type `other`
   titled *"Publish ledger snapshot run-N"*. Write an OwnerReport whose headline is the loop status, not
   the revenue.
4. Record every run's `cost_cents` honestly. The snapshot shows intelligence cost next to cash.

## What the ledger page shows (`dashboard/ledger.html?s=<slug>`)

Portfolio totals (capital planned against, cash spent, intelligence cost, verified revenue, net);
each venture's stage, budget, spend, revenue and shape; every ledger row in order; every decision
with its rationale; the generated-at timestamp and the fixed disclaimer. No forecasts, no edits.

## Pass / fail for the *engine*

* **Pass:** every stage produced its packet inside its window and cap; all assets registered as
  owner-controlled; no guardrail had to be overridden by a human; the snapshot was published.
* **Fail:** the loop stalled (a stage never produced a packet), an agent needed a human to do its
  work, a cap was exceeded by a manual approval, or the ledger could not be reconciled.

Revenue is recorded if it happens, but it is not the pass criterion. The second dogfood run should
be cheaper in intelligence cost than the first; the Analyst reports whether it was.

## After the first published ledger

Post it where operators gather (build-in-public, indie-hacker, agency-owner and creator communities)
with one question: *"Would you pay $49/month to run this engine on your own niche?"* Five unprompted
requests for access from operators (not from people asking whether it is passive income) is the signal
to open design-partner seats. Then run the second dogfood venture before onboarding anyone.
