# AVE positioning (v0.2): Autonomous Venturing

This replaces the v0.1 positioning. The buyer, the boundaries and the wedge from the council reshape
are unchanged; what changes is the category we name and the language we use for control.

## The category

**Autonomous Venturing**: building and running small businesses with AI agents at a *declared level
of autonomy*, inside limits the agents cannot override, in accounts the owner keeps, on a ledger the
owner can publish.

The category is defined by five levels (`docs/FIVE_LEVELS.md`). AVE publishes the levels, runs at the
level the owner has earned, and refuses Level 5.

| | |
|---|---|
| **Word we own** | autonomous |
| **Second sentence** | the open ledger ("receipts, not screenshots") |
| **Line** | Hands off. Eyes on. Brakes always. |
| **Problem we name** | All-or-nothing AI: today you either do everything yourself with tools, or hand your money to a black box. Nothing in between, and no scale to tell them apart. |
| **Enemy** | "Passive income" automation: asleep at the wheel. |
| **From → To** | From "either I do everything or I trust a black box" → to "I choose the level; the database keeps it there." |

## The positioning statement

For operators who already have an edge (an audience, a practice, a client base) and want businesses
built for them without losing control of their money or their name, **AVE is the autonomous venturing
system** that runs the whole venture lifecycle at a level of autonomy you choose and your ledger has
earned. Unlike "AI runs your business" tools, its limits are enforced by a database rather than by the
model, everything it builds lives in your own accounts, and every dollar and every kill is on a ledger
you can publish.

## What we claim, exactly

AVE claims a **level**, never "autonomy" in general.

* **Today: Level 2 (Supervised), as built.** The system is not yet live and no ledger has been
  published. Until one is, the claim is "built for Level 2", not "proven at Level 2".
* **Level 3** is claimed per owner, only after that owner's ledger shows 3 completed ventures and 1
  published snapshot. The database refuses it before then.
* **Level 4** needs 10 completed ventures, 1 published snapshot and 1 venture whose verified revenue
  beat its cash plus intelligence cost.
* **Level 5 is not offered.** It is refused by a CHECK constraint and a trigger. We say so in public.

## The four instruments (the metaphor, used consistently)

| Instrument | What it is in the build | What we say |
|---|---|---|
| **The wheel** | Owner-gated decisions: `policies.require_owner_for`, the approvals inbox | "You stay at the wheel for launch, kill, scale and any outside commitment." |
| **The brakes** | Spend adjudication triggers, stage caps, the emergency brake (`owners.kill_switch`) | "The agents ask. The rules decide. One switch stops everything." |
| **The logbook** | `ledger`, `decisions`, `public_ledger_snapshots`, intelligence cost | "Every dollar, every decision, every kill, and the level it was run at." |
| **The road** | `owner_edge`, `edge_fit_score` | "Autonomy needs a road. Your edge is the road." |

Do not add instruments. Four is the system.

## Who it is for

| Order | Buyer | Why this category lands |
|---|---|---|
| **Lead** | Tech-literate operators, build-in-public founders, small product teams | They already think in levels of autonomy and will repeat the vocabulary. |
| **Second** | Agency principals (2 to 20 people) | They delegate for a living; a level is a delegation contract they understand. |
| **Entry story for SMEs** | Established owner-operators (the Nigerian SME base) | Category stays on the site; the conversation opens with "your second business, built from your first, at Level 2: nothing launches without your yes." |

**Not for:** people with no edge who want money while they sleep; anyone asking AVE to hold or invest
their money; anyone who wants Level 5.

## What we say and never say

| We say | We never say |
|---|---|
| "Autonomous venturing, Level 2." | "Fully autonomous", "runs itself", "set and forget" |
| "Hands off. Eyes on. Brakes always." | "Passive income", "money while you sleep" |
| "You choose the level. Your ledger earns the next one." | "Guaranteed", "returns", "ROI you can expect" |
| "The agents ask; the database decides." | "Trust our AI" |
| "Receipts, not screenshots." | Success rates, income claims, unverified testimonials |
| "Level 5 is not offered." | "Coming soon: full autonomy" |
| "Your accounts, your assets, your money." | "We deploy your capital", "revenue share" |

## Product language (dashboard and reports)

| Old label | Level language |
|---|---|
| Policy · guardrails | Autonomy level · who is at the wheel |
| Agent auto-approve limit | Agents may spend without asking, per request |
| Daily agent spend limit | Agents may spend without asking, per day |
| Default venture cap | Budget ceiling per venture |
| Max active ventures | Ventures on the road at once |
| Owner must approve | You stay at the wheel for |
| Dogfood mode | Proof mode (Levels 1 and 2) |
| Public ledger | Logbook publishing |
| Kill switch | Emergency brake |
| Approvals | Needs you · you are at the wheel for these |

Schema names are unchanged (`dogfood_mode`, `kill_switch`, and so on); only the words people read.

## Pricing (unchanged in principle, proposed tiers)

Flat subscription, never a share of revenue or capital (`docs/BOUNDARIES.md`). A proposal to test,
not a decision: one plan for Levels 1 and 2 at the $49 anchor, a higher plan from Level 3 where proof
mode is off and budgets are larger. Intelligence cost is shown per venture and passed through at cost.

## Proof before pitch

1. Go live (migrations 0001 to 0003 applied, agents on current prompts).
2. Run three proof ventures at Level 2 and publish the ledgers, kills included.
3. Publish the manifesto and the ledgers together. That is the launch.
4. Only then open founding-operator seats.

## Fallback

If by the end of the first 90 days nobody outside repeats the level language and qualified requests
are thin, lead with "AI Venture Team" and keep the levels as the control model. The build does not
change either way.
