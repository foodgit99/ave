# Boundaries: what AVE will never do, and why

These are product decisions encoded in the database (migration 0002), the agent prompts and the
positioning. They are not legal advice; they are the lines that keep AVE a software tool the owner
pays for rather than something that looks like an investment scheme. Get a lawyer before changing any
of them.

## 1. No custody

AVE never holds, pools, moves or "deploys" anyone's money. The owner's capital stays in the owner's
bank and provider accounts. The `ledger` is a record of what the owner's own accounts did, not a
wallet. `capital_in` means "the owner told the system how much of their own money it may plan
against", nothing more.

*Enforced by:* `trg_spend_reshape_rules` (purposes that read like holding/moving/investing money
raise), forbidden keywords `custody`, `escrow`, `pooled capital`, `crowdfund` in every policy, and the
absence of any payment-processing code in the repo.

## 2. No carry, no revenue share, no percentage of capital

The platform is paid a **flat subscription** outside the venture ledgers. It takes no share of venture
revenue and no fee on capital "under management".

*Why:* a scheme in which someone pays money up front, a third party builds and runs the business, and
the payer expects profit from that third party's efforts is the fact pattern the U.S. SEC charged as
unregistered investment contracts in *SEC v. Todays Growth Consultant Inc. (The Income Store)* — the
company built and ran websites for investors in exchange for 50% of revenue plus a guaranteed minimum,
raised ~$75M, and was sued in 2019 (complaint: sec.gov/files/litigation/complaints/2020/comp-pr2020-10.pdf).
The guaranteed-return element made that case egregious, but the *Howey* "profits from the efforts of
others" test does not need a guarantee. In Nigeria, platforms that pool public money for investment
instruments fall under SEC Nigeria's crowdfunding rules (₦100M minimum paid-up capital, custodian
requirement). And Paystack lists "investment and other financial service businesses" and
"crowdfunding businesses" as ineligible for international payments
(support.paystack.com/en/articles/2127682) — i.e. the rail AVE's Nigerian operators would use would
refuse the business the moment it looked like this.

*Enforced by:* forbidden keywords `revenue share`, `carry`, `investment return`, `guaranteed return`;
the OwnerReport disclaimer constant; `POSITIONING.md`; and the rule that platform billing lives in a
different schema from venture ledgers.

## 3. Every asset is the owner's

Repo, domain, storefront, payment account, ad account, hosting, email, analytics — all created in the
owner's own accounts and registered in `venture_assets` with `owner_controlled = true`. The CHECK
constraint makes the alternative impossible to record; the launch gate refuses `build → distribute`
until an owner-controlled storefront/payment account and repo/hosting exist.

*Why:* (a) if AVE holds the Stripe/Paystack account it is in the money path (see 1 and 2); (b) if the
owner churns they must keep a working business; (c) ad and payment platforms suspend accounts that are
created or operated outside their official APIs, and the ban must never land on AVE's shared
infrastructure or on an owner's account because of another owner's venture.

## 4. Official APIs and the owner's verified accounts only

Paid distribution runs only through the owner's own verified ad accounts via official Marketing APIs.
No bulk-created accounts, no browser automation on ad or payment platforms, no shared AVE accounts.
Google Ads treats "circumventing systems" (including multi-account and bulk creation) as an egregious
violation with permanent suspension and related-account suspension
(support.google.com/adspolicy/answer/15938075); Meta's terms bar accounts created or operated by
automated means outside the Marketing API.

*Enforced by:* `DistributionPlan.channels[].account` is required; the Distributor prompt; the
`ad_account` asset kind in `venture_assets`.

## 5. No passive-income language

Not in reports, not in copy, not in code comments, not in AVE's own marketing. The words "passive
income", "guaranteed", "investment return" and "revenue share" are banned about AVE and its ventures.
The sector that uses them (dropshipping automation, FBA "done-for-you" stores, income-site schemes) is
where the regulators and the chargebacks live, and the buyer it attracts is the one the council's
arithmetic says will lose.

## 6. Forecast ≠ actual, and intelligence cost is a real cost

Only `verified` revenue with an external payment reference counts anywhere. Every OwnerReport carries
the disclaimer constant. Agent-run cost (`agent_runs.cost_cents`, `v_cost_of_intelligence`) is reported
next to cash, so a venture is never called profitable when its model bills exceed its sales.

## 7. The ethics list stands

No gambling, adult, weapons, speculative tokens, payday lending, MLM, deception, fake reviews, fake
scarcity, scraped personal data, impersonation or spam. Regulatory exposure (payments, health, finance,
minors, data protection) is flagged in writing before proceeding.

## What changing a boundary requires

A written legal opinion covering the jurisdictions AVE's owners sell from, a payment provider that
has approved the business category in writing, and a new migration that removes the matching
constraint with a comment linking to both. Until then the database says no.
