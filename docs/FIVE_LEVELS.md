# The Five Levels of Autonomous Venturing

*A manifesto and a standard. Version 1.0, November 2026. The designed PDF is the canonical edition;
this file is the text of record in the repo.*

**Hands off. Eyes on. Brakes always.**

## Why levels

Cars did not become self-driving with a switch. They became self-driving in levels, each one stating
what the machine does and what the human still does (SAE J3016 defines levels 0 to 5 of driving
automation). That is why people could trust the early ones.

AI that builds businesses has no such scale. Every product claims to "run your business", so buyers
can't tell a research assistant from a system with their card details. The result is all-or-nothing:
do everything yourself with tools, or trust a black box. We think that is the wrong choice to offer
anyone, and that the fix is the same one the car industry found: say the level out loud.

## What we believe

1. **Autonomy is a level, not a claim.** If a product cannot state its level, it does not have one.
2. **Limits belong outside the model.** A rule the AI can talk itself past is not a rule.
3. **The owner owns everything.** Money, accounts, code, customers. The system holds nothing.
4. **Levels are earned from a ledger.** More autonomy follows evidence, not confidence.
5. **Kills go on the record.** A ledger without losses is an advertisement.
6. **Autonomy needs a road.** Agents build on the owner's edge, or they do not build.
7. **Level 5 is not a goal.** A business with nobody at the wheel is nobody's business.

## The four instruments

| Instrument | Meaning | In AVE |
|---|---|---|
| The wheel | Decisions that always wait for the owner | `policies.require_owner_for`, approvals inbox |
| The brakes | Limits enforced by rules, plus one switch that stops everything | spend triggers, stage caps, `owners.kill_switch` |
| The logbook | A record of every dollar, decision and kill that the owner can publish | `ledger`, `decisions`, `public_ledger_snapshots` |
| The road | The owner's edge that every venture must use | `owner_edge`, `edge_fit_score` |

## The levels

| Level | Name | Agents do alone | Owner decides | AVE preset |
|---|---|---|---|---|
| 0 | Manual | Nothing. Tools answer when asked. | Everything | not AVE |
| 1 | Assisted | Research, proposals, drafts | Every spend, every stage | spend $0 unasked; proof mode on; 1 venture |
| 2 | Supervised | Experiments and builds inside small caps | Launch, kill, scale, outside commitments; any spend over the cap | $25 per spend, $100 per day; $100 proof ventures with stage caps $40/$20/$40; 2 ventures |
| 3 | Conditional | The full lifecycle inside a venture budget | Launch, kill, scale, outside commitments | $40 per spend, $150 per day; $500 per venture; proof mode off; 2 ventures |
| 4 | High | Launch and kill inside budget | Scale, outside commitments | $100 per spend, $300 per day; $500 per venture; 3 ventures |
| 5 | Full | Everything | Nothing | **not offered** |

At every level: spend status is decided by the database, not the agent; expenses need an approved
request; revenue counts only with a payment reference; assets must be registered as owner-controlled
before launch; the emergency brake rejects all new spend.

## Graduation

Levels are earned, not chosen. Stepping down is always allowed.

| To reach | The owner's own ledger must show | Enforced by |
|---|---|---|
| Level 2 | Edge profile complete | discovery trigger |
| Level 3 | 3 completed ventures (decided, scaled or killed) and 1 published ledger snapshot | `trg_policy_level` |
| Level 4 | 10 completed ventures, 1 published snapshot, and 1 venture whose verified revenue beat its cash plus intelligence cost | `trg_policy_level` |
| Level 5 | Nothing. It is refused. | CHECK constraint and trigger |

## The standard: five tests

A product is doing Autonomous Venturing only if it passes all five.

1. **Whole loop.** It runs a venture from discovery to a decision, not a single task.
2. **Declared level.** It states what it does alone and what the owner still decides.
3. **Rules outside the model.** Spending limits and gates are enforced by something the AI cannot override.
4. **Owner-owned.** Money, accounts and assets stay with the owner; the system takes no custody and no share.
5. **Open ledger.** Actuals only, kills included, cost of intelligence shown, publishable by the owner.

A product that fails a test is not worse; it is something else (a tool, a builder, a service). It is
unrated on this scale until it publishes its limits.

## AVE's declaration

* AVE is built for **Level 2**. It is not yet live and has not published a ledger. Until it has, we
  say "built for Level 2", not "proven at Level 2".
* We will publish our own ledgers, kills included, before selling a seat.
* We will never offer Level 5, never hold an owner's money, and never take a share of venture revenue.
* The rules are public: `supabase/migrations/` and `tests/test_guardrails.py` (61 checks).

Anyone may use these levels to describe their own product. State your level.
