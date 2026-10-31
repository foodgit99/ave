-- =====================================================================
-- Autonomous Venture Engine (AVE) — core schema, ledger and guardrails
-- v0.1  ·  Postgres 15+ / Supabase
--
-- Design rules
--   1. Agents never hold money. They file spend_requests; a deterministic
--      trigger (not an LLM) decides auto-approve / pending-owner / reject.
--   2. An expense can only land in the ledger if it references an approved
--      spend_request with headroom. Revenue must be verified before it
--      counts toward available capital.
--   3. Only an authenticated owner (auth.uid()) can approve a pending request,
--      lift the kill switch, or change policy. Service-role / MCP sessions
--      have no auth.uid() and are refused by the triggers.
--   4. Every stage transition and every money decision writes a decision
--      record. The dashboard reads; it never computes.
-- =====================================================================

-- gen_random_uuid() is built in since Postgres 13; no extension needed.

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
do $$ begin
  create type venture_stage as enum
    ('discover','evaluate','validate','build','distribute','measure','decide','scale','paused','killed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type opportunity_status as enum
    ('new','evaluated','validating','accepted','rejected','parked');
exception when duplicate_object then null; end $$;

do $$ begin
  create type experiment_status as enum
    ('planned','running','passed','failed','aborted');
exception when duplicate_object then null; end $$;

do $$ begin
  create type spend_category as enum
    ('ads','tools','infrastructure','contractors','fees','content','data','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type spend_status as enum
    ('auto_approved','pending_owner','approved','rejected','spent','cancelled','expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type ledger_kind as enum
    ('capital_in','capital_out','expense','revenue','refund','adjustment');
exception when duplicate_object then null; end $$;

do $$ begin
  create type approval_type as enum
    ('spend','launch','kill','scale','policy_exception','external_commitment','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type approval_status as enum ('pending','approved','rejected','expired');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- Owners & policy (the guardrail parameters)
-- ---------------------------------------------------------------------
create table if not exists owners (
  id            uuid primary key,               -- = auth.users.id on Supabase
  display_name  text not null,
  email         text,
  currency      text not null default 'USD',
  kill_switch   boolean not null default false, -- true = every new spend is rejected
  created_at    timestamptz not null default now()
);

create table if not exists policies (
  owner_id                 uuid primary key references owners(id) on delete cascade,
  risk_tolerance           text not null default 'medium' check (risk_tolerance in ('low','medium','high')),
  auto_approve_limit_cents bigint not null default 2500,     -- single spend an agent may self-approve ($25)
  daily_spend_limit_cents  bigint not null default 10000,    -- across all ventures, agent-approved only ($100)
  venture_budget_cap_cents bigint not null default 50000,    -- default max per venture ($500)
  max_active_ventures      int    not null default 2,
  allowed_categories       spend_category[] not null default array['ads','tools','infrastructure','fees','content','data']::spend_category[],
  forbidden_keywords       text[] not null default array['gambling','adult','weapons','crypto-token','payday-loan','mlm'],
  require_owner_for        approval_type[] not null default array['launch','kill','scale','external_commitment']::approval_type[],
  updated_at               timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Ventures, opportunities, experiments
-- ---------------------------------------------------------------------
create table if not exists ventures (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references owners(id) on delete cascade,
  name          text not null,
  slug          text not null,
  thesis        text,                                   -- one-paragraph "why this, why now"
  stage         venture_stage not null default 'discover',
  budget_cents  bigint not null default 0,              -- owner-approved ceiling for this venture
  target_market text,
  offer         jsonb,                                  -- {promise, cta, price, unit}
  links         jsonb not null default '{}'::jsonb,     -- {landing, repo, stripe, analytics, ...}
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id, slug)
);

create table if not exists opportunities (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references owners(id) on delete cascade,
  venture_id      uuid references ventures(id) on delete set null,
  title           text not null,
  problem         text not null,
  target_customer text not null,
  evidence        jsonb not null default '[]'::jsonb,   -- [{claim, source_url, strength}]
  assumptions     jsonb not null default '[]'::jsonb,   -- [{assumption, risk, how_to_test}]
  confidence      numeric(3,2) check (confidence between 0 and 1),
  evaluation      jsonb,                                -- VentureProposal scorecard (protocol/venture_proposal.schema.json)
  status          opportunity_status not null default 'new',
  source_agent    text not null default 'scout',
  created_at      timestamptz not null default now()
);

create table if not exists experiments (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references owners(id) on delete cascade,
  venture_id       uuid not null references ventures(id) on delete cascade,
  opportunity_id   uuid references opportunities(id) on delete set null,
  hypothesis       text not null,
  design           text not null,                      -- what we will do, where, for how long
  budget_cents     bigint not null default 0,
  success_criteria jsonb not null,                      -- {metric, threshold, window_days}
  stop_conditions  jsonb not null,                      -- {max_spend_cents, max_days, kill_if}
  status           experiment_status not null default 'planned',
  result           jsonb,                               -- ExperimentResult
  started_at       timestamptz,
  ended_at         timestamptz,
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Money: spend requests (intent) and ledger (fact)
-- ---------------------------------------------------------------------
create table if not exists spend_requests (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references owners(id) on delete cascade,
  venture_id    uuid references ventures(id) on delete cascade,
  experiment_id uuid references experiments(id) on delete set null,
  requested_by  text not null,                          -- agent name, e.g. 'distributor'
  category      spend_category not null,
  amount_cents  bigint not null check (amount_cents > 0),
  purpose       text not null,
  status        spend_status not null default 'pending_owner',
  decision_reason text,                                 -- written by the guardrail trigger
  decided_at    timestamptz,
  decided_by    text,                                   -- 'guardrail' | 'owner:<uuid>'
  expires_at    timestamptz not null default now() + interval '7 days',
  created_at    timestamptz not null default now()
);

create table if not exists ledger (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references owners(id) on delete cascade,
  venture_id       uuid references ventures(id) on delete set null,
  spend_request_id uuid references spend_requests(id),
  kind             ledger_kind not null,
  category         spend_category,
  amount_cents     bigint not null check (amount_cents > 0),
  description      text not null,
  external_ref     text,                                -- Stripe charge id, invoice no., ad account txn
  verified         boolean not null default false,      -- revenue counts only when verified
  recorded_by      text not null default 'agent',
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Governance: approvals, decisions, runs, metrics, reports, notifications
-- ---------------------------------------------------------------------
create table if not exists approvals (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references owners(id) on delete cascade,
  venture_id   uuid references ventures(id) on delete cascade,
  type         approval_type not null,
  title        text not null,
  payload      jsonb not null default '{}'::jsonb,     -- what exactly is being asked
  requested_by text not null,
  status       approval_status not null default 'pending',
  decision_note text,
  decided_at   timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists decisions (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references owners(id) on delete cascade,
  venture_id uuid references ventures(id) on delete cascade,
  agent      text not null,
  stage      venture_stage,
  decision   text not null,                            -- 'advance to validate', 'kill', 'scale budget +$200'
  rationale  text not null,
  evidence   jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists agent_runs (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references owners(id) on delete cascade,
  venture_id  uuid references ventures(id) on delete set null,
  agent       text not null,
  task        text not null,
  thread_url  text,
  status      text not null default 'running' check (status in ('running','done','failed','blocked')),
  summary     text,
  started_at  timestamptz not null default now(),
  finished_at timestamptz
);

create table if not exists metrics (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references owners(id) on delete cascade,
  venture_id   uuid not null references ventures(id) on delete cascade,
  metric       text not null,                          -- 'visitors','leads','signups','paid','cac_cents','conv_rate'
  value        numeric not null,
  period_start date not null,
  period_end   date not null,
  source       text,
  created_at   timestamptz not null default now()
);

create table if not exists reports (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references owners(id) on delete cascade,
  venture_id uuid references ventures(id) on delete cascade,
  period     text not null,                            -- 'daily 2026-11-01', 'weekly W45'
  body_md    text not null,
  created_at timestamptz not null default now()
);

create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references owners(id) on delete cascade,
  venture_id uuid references ventures(id) on delete cascade,
  level      text not null default 'info' check (level in ('info','action','warning','critical')),
  title      text not null,
  body       text,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists ledger_owner_kind_idx on ledger(owner_id, kind);
create index if not exists ledger_venture_idx on ledger(venture_id);
create index if not exists spend_owner_status_idx on spend_requests(owner_id, status);
create index if not exists decisions_venture_idx on decisions(venture_id, created_at desc);

-- ---------------------------------------------------------------------
-- Capital arithmetic (pure functions; the dashboard and agents read these)
-- ---------------------------------------------------------------------
create or replace function fn_owner_capital(p_owner uuid)
returns table (
  capital_in_cents bigint, capital_out_cents bigint, expense_cents bigint,
  verified_revenue_cents bigint, refund_cents bigint, reserved_cents bigint,
  available_cents bigint
) language sql stable as $$
  with l as (
    select
      coalesce(sum(amount_cents) filter (where kind='capital_in'),0)                 as cin,
      coalesce(sum(amount_cents) filter (where kind='capital_out'),0)                as cout,
      coalesce(sum(amount_cents) filter (where kind='expense'),0)                    as exp,
      coalesce(sum(amount_cents) filter (where kind='revenue' and verified),0)       as rev,
      coalesce(sum(amount_cents) filter (where kind='refund'),0)                     as ref,
      coalesce(sum(case when kind='adjustment' then amount_cents end),0)             as adj
    from ledger where owner_id = p_owner
  ),
  r as (
    select coalesce(sum(amount_cents),0) as reserved
    from spend_requests
    where owner_id = p_owner and status in ('auto_approved','approved') and expires_at > now()
  )
  select cin, cout, exp, rev, ref, reserved,
         (cin - cout - exp + rev - ref - reserved) as available
  from l, r;
$$;

create or replace function fn_venture_spent(p_venture uuid)
returns bigint language sql stable as $$
  select coalesce(sum(amount_cents),0) from ledger
  where venture_id = p_venture and kind = 'expense';
$$;

create or replace function fn_venture_reserved(p_venture uuid)
returns bigint language sql stable as $$
  select coalesce(sum(amount_cents),0) from spend_requests
  where venture_id = p_venture and status in ('auto_approved','approved') and expires_at > now();
$$;

create or replace function fn_agent_spend_today(p_owner uuid)
returns bigint language sql stable as $$
  select coalesce(sum(amount_cents),0) from spend_requests
  where owner_id = p_owner
    and status in ('auto_approved','spent')
    and decided_by = 'guardrail'
    and created_at >= date_trunc('day', now());
$$;

-- ---------------------------------------------------------------------
-- GUARDRAIL 1 — spend request adjudication (deterministic, on insert)
-- The caller's requested status is ignored; the trigger decides.
-- ---------------------------------------------------------------------
create or replace function trg_adjudicate_spend()
returns trigger language plpgsql as $$
declare
  o          owners%rowtype;
  p          policies%rowtype;
  v          ventures%rowtype;
  cap        record;
  reason     text;
  kw         text;
begin
  select * into o from owners where id = new.owner_id;
  if not found then raise exception 'AVE: unknown owner %', new.owner_id; end if;
  select * into p from policies where owner_id = new.owner_id;
  if not found then raise exception 'AVE: owner % has no policy row', new.owner_id; end if;

  new.decided_at := now();
  new.decided_by := 'guardrail';

  -- Hard rejections ---------------------------------------------------
  if o.kill_switch then
    new.status := 'rejected'; new.decision_reason := 'kill switch is on'; return new;
  end if;

  if not (new.category = any (p.allowed_categories)) then
    new.status := 'rejected'; new.decision_reason := format('category %s not allowed by policy', new.category); return new;
  end if;

  foreach kw in array p.forbidden_keywords loop
    if position(lower(kw) in lower(new.purpose)) > 0 then
      new.status := 'rejected'; new.decision_reason := format('purpose matches forbidden keyword "%s"', kw); return new;
    end if;
  end loop;

  if new.venture_id is not null then
    select * into v from ventures where id = new.venture_id;
    if v.owner_id <> new.owner_id then
      raise exception 'AVE: venture % does not belong to owner %', new.venture_id, new.owner_id;
    end if;
    if v.stage in ('paused','killed') then
      new.status := 'rejected'; new.decision_reason := format('venture is %s', v.stage); return new;
    end if;
  end if;

  select * into cap from fn_owner_capital(new.owner_id);
  if new.amount_cents > cap.available_cents then
    new.status := 'rejected';
    new.decision_reason := format('insufficient available capital (%s available, %s requested)', cap.available_cents, new.amount_cents);
    return new;
  end if;

  -- Escalations to the owner -----------------------------------------
  if new.venture_id is not null
     and fn_venture_spent(new.venture_id) + fn_venture_reserved(new.venture_id) + new.amount_cents > v.budget_cents then
    new.status := 'pending_owner';
    new.decision_reason := format('would exceed venture budget (%s spent+reserved of %s)',
                                  fn_venture_spent(new.venture_id) + fn_venture_reserved(new.venture_id), v.budget_cents);
    return new;
  end if;

  if new.amount_cents > p.auto_approve_limit_cents then
    new.status := 'pending_owner';
    new.decision_reason := format('above agent auto-approve limit (%s)', p.auto_approve_limit_cents);
    return new;
  end if;

  if fn_agent_spend_today(new.owner_id) + new.amount_cents > p.daily_spend_limit_cents then
    new.status := 'pending_owner';
    new.decision_reason := format('would exceed daily agent spend limit (%s)', p.daily_spend_limit_cents);
    return new;
  end if;

  -- Within authority --------------------------------------------------
  new.status := 'auto_approved';
  new.decision_reason := 'within policy limits';
  return new;
end $$;

drop trigger if exists spend_requests_adjudicate on spend_requests;
create trigger spend_requests_adjudicate
  before insert on spend_requests
  for each row execute function trg_adjudicate_spend();

-- Mirror pending requests into the approvals inbox + a notification
create or replace function trg_spend_to_inbox()
returns trigger language plpgsql as $$
begin
  if new.status = 'pending_owner' then
    insert into approvals (owner_id, venture_id, type, title, payload, requested_by)
    values (new.owner_id, new.venture_id, 'spend',
            format('Approve %s spend: %s', new.category, new.purpose),
            jsonb_build_object('spend_request_id', new.id, 'amount_cents', new.amount_cents,
                               'reason', new.decision_reason),
            new.requested_by);
    insert into notifications (owner_id, venture_id, level, title, body)
    values (new.owner_id, new.venture_id, 'action',
            format('Spend approval needed: %s', new.purpose), new.decision_reason);
  elsif new.status = 'rejected' then
    insert into notifications (owner_id, venture_id, level, title, body)
    values (new.owner_id, new.venture_id, 'warning',
            format('Spend rejected by guardrail: %s', new.purpose), new.decision_reason);
  end if;
  return new;
end $$;

drop trigger if exists spend_requests_inbox on spend_requests;
create trigger spend_requests_inbox
  after insert on spend_requests
  for each row execute function trg_spend_to_inbox();

-- ---------------------------------------------------------------------
-- GUARDRAIL 2 — only an authenticated owner can approve / reject
-- auth.uid() is Supabase's JWT subject. MCP / service-role sessions return
-- null and are refused. Locally, tests stub auth.uid().
-- ---------------------------------------------------------------------
create schema if not exists auth;
do $$ begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='auth' and p.proname='uid') then
    create function auth.uid() returns uuid language sql stable as
      $f$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $f$;
  end if;
end $$;

create or replace function trg_spend_status_transition()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status then
    -- pending → approved/rejected : owner only
    if old.status = 'pending_owner' and new.status in ('approved','rejected') then
      if auth.uid() is null or auth.uid() <> old.owner_id then
        raise exception 'AVE: only the authenticated owner may decide a pending spend request';
      end if;
      new.decided_at := now();
      new.decided_by := 'owner:' || auth.uid()::text;
    -- approved/auto_approved → spent : set by the ledger trigger only
    elsif old.status in ('approved','auto_approved') and new.status = 'spent' then
      if current_setting('ave.internal', true) is distinct from 'ledger' then
        raise exception 'AVE: spend requests become "spent" only via a ledger expense';
      end if;
    -- anything live → cancelled/expired : allowed (agents may withdraw)
    elsif new.status in ('cancelled','expired') and old.status in ('pending_owner','approved','auto_approved') then
      null;
    else
      raise exception 'AVE: illegal spend status transition % → %', old.status, new.status;
    end if;
  end if;
  -- amounts and ownership are immutable after filing
  if new.amount_cents <> old.amount_cents or new.owner_id <> old.owner_id or new.venture_id is distinct from old.venture_id then
    raise exception 'AVE: spend request amount/owner/venture are immutable';
  end if;
  return new;
end $$;

drop trigger if exists spend_requests_transition on spend_requests;
create trigger spend_requests_transition
  before update on spend_requests
  for each row execute function trg_spend_status_transition();

-- approvals inbox: same owner-only rule, and spend approvals cascade
create or replace function trg_approval_decided()
returns trigger language plpgsql as $$
declare sr uuid;
begin
  if new.status is distinct from old.status and old.status = 'pending' then
    if auth.uid() is null or auth.uid() <> old.owner_id then
      raise exception 'AVE: only the authenticated owner may decide an approval';
    end if;
    new.decided_at := now();
    if new.type = 'spend' then
      sr := (new.payload->>'spend_request_id')::uuid;
      update spend_requests set status = case when new.status='approved' then 'approved'::spend_status else 'rejected'::spend_status end
       where id = sr and status = 'pending_owner';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists approvals_decided on approvals;
create trigger approvals_decided
  before update on approvals
  for each row execute function trg_approval_decided();

-- ---------------------------------------------------------------------
-- GUARDRAIL 3 — expenses must reference an approved request with headroom
-- ---------------------------------------------------------------------
create or replace function trg_ledger_guard()
returns trigger language plpgsql as $$
declare sr spend_requests%rowtype; already bigint;
begin
  if new.kind = 'expense' then
    if new.spend_request_id is null then
      raise exception 'AVE: an expense must reference a spend_request';
    end if;
    select * into sr from spend_requests where id = new.spend_request_id for update;
    if not found then raise exception 'AVE: spend_request % not found', new.spend_request_id; end if;
    if sr.owner_id <> new.owner_id then raise exception 'AVE: spend_request belongs to another owner'; end if;
    if sr.status not in ('approved','auto_approved','spent') then
      raise exception 'AVE: spend_request % is % — not spendable', sr.id, sr.status;
    end if;
    if sr.expires_at < now() and sr.status <> 'spent' then
      raise exception 'AVE: spend_request % expired', sr.id;
    end if;
    select coalesce(sum(amount_cents),0) into already from ledger
      where spend_request_id = sr.id and kind = 'expense';
    if already + new.amount_cents > sr.amount_cents then
      raise exception 'AVE: expense % exceeds approved amount % (already spent %)', new.amount_cents, sr.amount_cents, already;
    end if;
    new.venture_id := coalesce(new.venture_id, sr.venture_id);
    new.category   := coalesce(new.category, sr.category);
    -- mark spent (internal flag lets the transition trigger through)
    perform set_config('ave.internal', 'ledger', true);
    update spend_requests set status = 'spent' where id = sr.id and status <> 'spent';
    perform set_config('ave.internal', '', true);
  elsif new.kind in ('capital_in','capital_out') then
    -- capital movements are owner actions
    if auth.uid() is null or auth.uid() <> new.owner_id then
      raise exception 'AVE: only the authenticated owner may move capital in or out';
    end if;
    new.verified := true;
    new.recorded_by := 'owner:' || auth.uid()::text;
  elsif new.kind = 'revenue' then
    -- agents may record revenue, but it only counts once verified against an external_ref
    if new.verified and (new.external_ref is null or new.external_ref = '') then
      raise exception 'AVE: verified revenue needs an external_ref (payment id)';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists ledger_guard on ledger;
create trigger ledger_guard
  before insert on ledger
  for each row execute function trg_ledger_guard();

-- ledger rows are immutable facts
create or replace function trg_immutable() returns trigger language plpgsql as $$
begin raise exception 'AVE: % rows are immutable', tg_table_name; end $$;
drop trigger if exists ledger_immutable on ledger;
create trigger ledger_immutable before update or delete on ledger for each row execute function trg_immutable();
drop trigger if exists decisions_immutable on decisions;
create trigger decisions_immutable before update or delete on decisions for each row execute function trg_immutable();

-- ---------------------------------------------------------------------
-- GUARDRAIL 4 — stage transitions & owner-gated lifecycle events
-- ---------------------------------------------------------------------
create or replace function trg_venture_stage()
returns trigger language plpgsql as $$
declare p policies%rowtype; active int;
begin
  new.updated_at := now();
  select * into p from policies where owner_id = new.owner_id;
  if not found then raise exception 'AVE: owner % has no policy row', new.owner_id; end if;
  if new.owner_id <> old.owner_id then raise exception 'AVE: venture owner is immutable'; end if;
  if new.stage is distinct from old.stage then

    -- build→distribute is "launch"; any→killed is "kill"; budget increase is "scale"
    if old.stage = 'build' and new.stage = 'distribute' and 'launch' = any(p.require_owner_for)
       and (auth.uid() is null or auth.uid() <> new.owner_id)
       and not exists (select 1 from approvals where venture_id = new.id and type='launch' and status='approved') then
      raise exception 'AVE: launch requires an approved "launch" approval from the owner';
    end if;

    if new.stage = 'killed' and 'kill' = any(p.require_owner_for)
       and (auth.uid() is null or auth.uid() <> new.owner_id)
       and not exists (select 1 from approvals where venture_id = new.id and type='kill' and status='approved') then
      raise exception 'AVE: kill requires an approved "kill" approval from the owner';
    end if;

    -- cap on concurrently active ventures when leaving discover/evaluate
    if old.stage in ('discover','evaluate') and new.stage not in ('discover','evaluate','paused','killed') then
      select count(*) into active from ventures
        where owner_id = new.owner_id and id <> new.id
          and stage in ('validate','build','distribute','measure','decide','scale');
      if active >= p.max_active_ventures then
        raise exception 'AVE: max_active_ventures (%) reached', p.max_active_ventures;
      end if;
    end if;

    insert into decisions (owner_id, venture_id, agent, stage, decision, rationale)
    values (new.owner_id, new.id, coalesce(current_setting('ave.actor', true), 'system'),
            new.stage, format('stage %s → %s', old.stage, new.stage),
            coalesce(current_setting('ave.rationale', true), 'no rationale supplied'));
  end if;

  if new.budget_cents > old.budget_cents and 'scale' = any(p.require_owner_for)
     and (auth.uid() is null or auth.uid() <> new.owner_id)
     and not exists (select 1 from approvals where venture_id = new.id and type='scale' and status='approved'
                     and (payload->>'new_budget_cents')::bigint >= new.budget_cents) then
    raise exception 'AVE: raising a venture budget requires an approved "scale" approval';
  end if;
  return new;
end $$;

drop trigger if exists ventures_stage on ventures;
create trigger ventures_stage before update on ventures for each row execute function trg_venture_stage();

-- Policy & kill switch: owner only
create or replace function trg_owner_only() returns trigger language plpgsql as $$
declare oid uuid;
begin
  -- to_jsonb avoids plpgsql resolving both record fields at plan time
  oid := coalesce((to_jsonb(new)->>'owner_id')::uuid, (to_jsonb(new)->>'id')::uuid);
  if auth.uid() is null or auth.uid() <> oid then
    raise exception 'AVE: % may only be changed by the authenticated owner', tg_table_name;
  end if;
  if tg_table_name = 'policies' then new.updated_at := now(); end if;
  return new;
end $$;
drop trigger if exists policies_owner_only on policies;
create trigger policies_owner_only before update on policies for each row execute function trg_owner_only();
drop trigger if exists owners_owner_only on owners;
create trigger owners_owner_only before update on owners for each row execute function trg_owner_only();

-- ---------------------------------------------------------------------
-- Views for the Owner Command Center
-- ---------------------------------------------------------------------
create or replace view v_portfolio as
select o.id as owner_id, o.display_name, o.currency, o.kill_switch,
       c.capital_in_cents, c.capital_out_cents, c.expense_cents, c.verified_revenue_cents,
       c.reserved_cents, c.available_cents,
       (c.verified_revenue_cents - c.expense_cents) as net_cents,
       (select count(*) from ventures v where v.owner_id=o.id and v.stage not in ('paused','killed')) as active_ventures,
       (select count(*) from approvals a where a.owner_id=o.id and a.status='pending') as pending_approvals
from owners o cross join lateral fn_owner_capital(o.id) c;

create or replace view v_ventures as
select v.*, fn_venture_spent(v.id) as spent_cents, fn_venture_reserved(v.id) as reserved_cents,
       (select coalesce(sum(amount_cents),0) from ledger l where l.venture_id=v.id and l.kind='revenue' and l.verified) as revenue_cents,
       (select count(*) from experiments e where e.venture_id=v.id and e.status='running') as running_experiments,
       (select max(created_at) from decisions d where d.venture_id=v.id) as last_decision_at
from ventures v;

-- ---------------------------------------------------------------------
-- Row-level security: owners see only their rows (dashboard, anon key + JWT)
-- Service-role (agents via MCP) bypasses RLS but is still bound by triggers.
-- ---------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['owners','policies','ventures','opportunities','experiments','spend_requests',
                           'ledger','approvals','decisions','agent_runs','metrics','reports','notifications'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I_owner_select on %I', t, t);
    execute format('drop policy if exists %I_owner_write on %I', t, t);
    if t = 'owners' then
      execute 'create policy owners_owner_select on owners for select using (id = auth.uid())';
      execute 'create policy owners_owner_write on owners for all using (id = auth.uid()) with check (id = auth.uid())';
    else
      execute format('create policy %I_owner_select on %I for select using (owner_id = auth.uid())', t, t);
      execute format('create policy %I_owner_write on %I for all using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t, t);
    end if;
  end loop;
end $$;

-- Bootstrap: an authenticated user creates their own owner + default policy
create or replace function fn_bootstrap_owner(p_name text, p_email text default null, p_currency text default 'USD')
returns uuid language plpgsql security definer as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'AVE: sign in first'; end if;
  insert into owners (id, display_name, email, currency) values (uid, p_name, p_email, p_currency)
    on conflict (id) do nothing;
  insert into policies (owner_id) values (uid) on conflict (owner_id) do nothing;
  return uid;
end $$;
