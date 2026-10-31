# The eight-stage lifecycle as the Orchestrator runs it

Budget splits assume a venture budget B (default cap $500; **$100 in dogfood mode**, where the stage
caps are fixed at validate $40 / build $20 / distribute $40 and enforced by trigger). Percentages are
ceilings, not targets.

**Stage 0 — Edge.** Nothing starts until `owner_edge` is complete (the database refuses discovery).
The Orchestrator's first report to a new owner is a request to fill it in.

| # | Stage | Who | Entry gate | Exit packet | Money |
|---|---|---|---|---|---|
| 1 | discover | Scout | `owner_edge` complete; portfolio has capacity (`max_active_ventures`, available capital) | 3–5 OpportunityPackets with `edge_fit`, ranked | $0 |
| 2 | evaluate | Strategist | packet has ≥3 evidence items, ≥1 primary, `edge_fit.score` ≥ policy minimum | VentureProposal with `edge_fit_score` and `money_route` (owner's storefront), recommendation ∈ {validate, park, reject} | $0 |
| 3 | validate | Validator (+Distributor for traffic) | proposal says validate; Orchestrator creates `ventures` row with budget B | ExperimentResult, recommendation ∈ {advance, iterate, pivot, kill} | ≤ 15% B |
| 4 | build | Builder | result says advance; BuildSpec (with owner-controlled `assets`) approved by Orchestrator | deployed MVP in the owner's accounts, `venture_assets` registered, acceptance tests green, hand-off note | ≤ 25% B |
| 5 | distribute | Distributor | **owner approval of type `launch`** AND storefront/payment + repo/hosting assets registered as owner-controlled (trigger) | DistributionPlan (owner channels first, official APIs only); weekly channel read-outs | ≤ 40% B in first 30 days |
| 6 | measure | Analyst + Treasurer | 14 days of distribution or first 10 customers | metrics, reconciled ledger | $0 |
| 7 | decide | Orchestrator (Analyst recommends) | measure complete | DecisionRecord ∈ {scale, iterate, maintain, pause, kill}; `scale` and `kill` need owner approval | — |
| 8 | repeat | all | — | learning log updated; Scout re-briefed with what was learned; in dogfood mode the Treasurer drafts a `public_ledger_snapshots` row for the owner to publish | — |

## Hard rules the Orchestrator applies

* No venture below `policies.min_edge_fit_score`, however good the market looks.
* No solution shape outside `policies.allowed_solution_shapes` (digital products first).
* One iterate per stage. A second miss is a kill recommendation.
* Never start build before a validation result says advance with confidence ≥ 0.6.
* Never raise a venture budget without the Analyst's DecisionRecord *and* the owner's `scale` approval.
* Pause beats kill when the cause is external and dated (platform outage, seasonal).
* Kill when: validation fails twice; CAC > 60% of first-year LTV after 3 channel tests; the owner
  asks; or the venture needs something the owner cannot legally or financially provide.
* Report every tick; notify only on: approval needed, first verified revenue, kill recommendation,
  guardrail rejections ≥ 3 in a day, or burn > 2× plan.

## The dogfood run comes first

Before the $500 example below is allowed, the owner runs at least one `docs/DOGFOOD_RUN.md` cycle:
one $100 digital-product venture, 48-hour target, public ledger published. A clean kill with a
published ledger is a pass; the point is to prove the loop closes and to have receipts.

## A worked $500 example (dogfood mode off)

Owner allocates $500, default policy. Tick 1: Scout returns five packets; Strategist recommends
validating "invoice-chasing reminders for freelance designers" (people already pay humans $40/mo on
Fiverr for it). Orchestrator creates the venture with B = $400 (keeps $100 reserve) — the owner is a design agency with 2,000 freelance-designer newsletter subscribers, so `edge_fit_score` is 0.8 and the first message goes to that list for free. Validator files
a $24 spend request for a landing page + 3 days of niche traffic → auto-approved; 212 visitors,
11 pre-orders at $9/mo with card details → **passed**. Builder spends $0 (free tiers), ships a
Lemon Squeezy-storefront MVP in 2 days, in the owner's GitHub and Lemon Squeezy account, and registers
both in `venture_assets`. Orchestrator files a `launch` approval with the numbers; owner approves
from the dashboard. Distributor runs $20/day tranches on the owner's own Meta ad account via the Marketing API (each
auto-approved); Treasurer verifies the first 6 Lemon Squeezy payments as revenue in the owner's account. Analyst recommends iterate on pricing after 14 days; Orchestrator
agrees. Report to owner: spent $186 cash + $23 intelligence cost, verified revenue $54 (in the owner's
account), 6 paying customers, CAC $31, next step and a single question. Nothing above was guaranteed, and the owner could have stopped it at any
point with one click.
