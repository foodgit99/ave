-- =====================================================================
-- AVE v0.1 — "Reshape" migration (council verdict, 31 Oct 2026)
--
-- What this encodes, in the database rather than in prompts:
--   1. OWNER EDGE.  AVE works for operators who already have an edge
--      (audience, domain, distribution, accounts). Discovery is refused
--      until the owner has described that edge.
--   2. NO CUSTODY, NO CARRY.  AVE never holds owner money, never takes a
--      share of venture revenue. Spend categories and keywords that look
--      like custody/investment are hard-rejected; the platform fee is a
--      flat subscription recorded outside the venture ledger.
--   3. OWNERSHIP.  Every venture's repo, storefront, payment account, ad
--      account, domain and hosting must be registered as owner-controlled
--      before the venture may launch. The owner keeps everything if they
--      churn.
--   4. WEDGE.  Digital products first; micro-SaaS only when policy allows.
--   5. DOGFOOD MODE.  A $100 venture cap with per-stage caps
--      (validate $40 / build $20 / distribute $40) for the public
--      proof-of-loop run.
--   6. COST OF INTELLIGENCE.  Token/platform cost per agent run is tracked
--      so dependency drift is visible, per venture, next to revenue.
--   7. PUBLIC LEDGER.  Owner-published snapshots readable by anon.
-- Idempotent; safe to re-run after 0001.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Owner edge profile
-- ---------------------------------------------------------------------
create table if not exists owner_edge (
  owner_id              uuid primary key references owners(id) on delete cascade,
  operator_type         text not null default 'operator'
                        check (operator_type in ('operator','agency','creator','domain_expert','founder_team')),
  audience              text,          -- who already listens to this owner, where, how many
  domain_expertise      text,          -- what they know better than a general model does
  distribution_channels text[] not null default '{}',  -- channels they can actually use today
  existing_assets       text[] not null default '{}',  -- lists, communities, products, brands
  geography             text,          -- where they can legally sell and collect money
  hours_per_week        numeric(4,1) not null default 2,
  edge_statement        text,          -- one paragraph, in the owner's words
  completed_at          timestamptz,   -- set by the owner when the profile is good enough to run on
  updated_at            timestamptz not null default now()
);

create or replace function fn_edge_completed(p_owner uuid) returns boolean language sql stable as $$
  select exists (select 1 from owner_edge e where e.owner_id = p_owner and e.completed_at is not null
                 and coalesce(e.edge_statement,'') <> '' and cardinality(e.distribution_channels) > 0);
$$;

-- Discovery cannot start until the edge profile is complete.
create or replace function trg_opportunity_requires_edge() returns trigger language plpgsql as $$
begin
  if not fn_edge_completed(new.owner_id) then
    raise exception 'AVE: owner % has not completed their edge profile; discovery is refused (fill owner_edge and set completed_at)', new.owner_id;
  end if;
  return new;
end $$;
drop trigger if exists opportunities_require_edge on opportunities;
create trigger opportunities_require_edge before insert on opportunities
  for each row execute function trg_opportunity_requires_edge();

-- ---------------------------------------------------------------------
-- 2. Policy additions: wedge, dogfood, public ledger, edge fit, no-custody
-- ---------------------------------------------------------------------
alter table policies
  add column if not exists allowed_solution_shapes text[] not null
      default array['digital_product','ai_service','productized_service','automation_tool'],
  add column if not exists min_edge_fit_score numeric(3,2) not null default 0.60
      check (min_edge_fit_score between 0 and 1),
  add column if not exists dogfood_mode boolean not null default true,
  add column if not exists dogfood_venture_cap_cents bigint not null default 10000,
  add column if not exists dogfood_stage_caps jsonb not null
      default '{"validate":4000,"build":2000,"distribute":4000}'::jsonb,
  add column if not exists public_ledger boolean not null default false;

-- Custody / investment language is always forbidden, whatever the owner set.
update policies set forbidden_keywords = (
  select array(select distinct unnest(forbidden_keywords ||
    array['custody','escrow','investment return','guaranteed return','revenue share','carry','pooled capital','crowdfund'])))
where not (forbidden_keywords @> array['custody']);

alter table policies alter column forbidden_keywords set default
  array['gambling','adult','weapons','crypto-token','payday-loan','mlm',
        'custody','escrow','investment return','guaranteed return','revenue share','carry','pooled capital','crowdfund'];

-- ---------------------------------------------------------------------
-- 3. Ventures: solution shape + asset registry + ownership gate
-- ---------------------------------------------------------------------
alter table ventures
  add column if not exists solution_shape text not null default 'digital_product',
  add column if not exists edge_fit_score numeric(3,2) check (edge_fit_score between 0 and 1),
  add column if not exists dogfood boolean not null default false;

create or replace function trg_venture_shape_allowed() returns trigger language plpgsql as $$
declare p policies%rowtype;
begin
  select * into p from policies where owner_id = new.owner_id;
  if not found then raise exception 'AVE: owner % has no policy row', new.owner_id; end if;
  if not (new.solution_shape = any (p.allowed_solution_shapes)) then
    raise exception 'AVE: solution shape "%" is outside the owner''s allowed wedge (%)', new.solution_shape, array_to_string(p.allowed_solution_shapes, ', ');
  end if;
  -- dogfood mode: every new venture is a dogfood venture capped at the dogfood cap
  if tg_op = 'INSERT' and p.dogfood_mode then
    new.dogfood := true;
    if new.budget_cents > p.dogfood_venture_cap_cents then
      raise exception 'AVE: dogfood mode caps venture budget at % cents (requested %)', p.dogfood_venture_cap_cents, new.budget_cents;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists ventures_shape_allowed on ventures;
create trigger ventures_shape_allowed before insert or update of solution_shape, budget_cents on ventures
  for each row execute function trg_venture_shape_allowed();

create table if not exists venture_assets (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references owners(id) on delete cascade,
  venture_id       uuid not null references ventures(id) on delete cascade,
  kind             text not null check (kind in ('repo','domain','storefront','payment_account','ad_account','hosting','email','analytics','other')),
  provider         text,            -- github, lemonsqueezy, gumroad, paystack, stripe, meta, vercel, ...
  url_or_id        text not null,
  owner_controlled boolean not null default true,
  created_by       text not null default 'builder',
  created_at       timestamptz not null default now(),
  constraint venture_assets_owner_controlled check (owner_controlled = true),  -- AVE never holds an asset
  unique (venture_id, kind, url_or_id)
);
create index if not exists venture_assets_venture_idx on venture_assets(venture_id);

create or replace function trg_asset_owner_matches() returns trigger language plpgsql as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from ventures where id = new.venture_id;
  if v_owner is null or v_owner <> new.owner_id then
    raise exception 'AVE: asset owner must match venture owner';
  end if;
  return new;
end $$;
drop trigger if exists venture_assets_owner_matches on venture_assets;
create trigger venture_assets_owner_matches before insert or update on venture_assets
  for each row execute function trg_asset_owner_matches();

-- Recreate v_ventures so the new venture columns appear (v.* is frozen at creation)
drop view if exists v_ventures;
create view v_ventures as
select v.*, fn_venture_spent(v.id) as spent_cents, fn_venture_reserved(v.id) as reserved_cents,
       (select coalesce(sum(amount_cents),0) from ledger l where l.venture_id=v.id and l.kind='revenue' and l.verified) as revenue_cents,
       (select count(*) from experiments e where e.venture_id=v.id and e.status='running') as running_experiments,
       (select max(created_at) from decisions d where d.venture_id=v.id) as last_decision_at,
       (select count(*) from venture_assets a where a.venture_id=v.id) as asset_count
from ventures v;

-- Launch gate: build → distribute additionally requires an owner-controlled
-- storefront or payment account AND a repo/hosting record, so there is never
-- a venture whose money or code lives in AVE's hands.
create or replace function trg_launch_requires_assets() returns trigger language plpgsql as $$
begin
  if old.stage = 'build' and new.stage = 'distribute' then
    if not exists (select 1 from venture_assets a where a.venture_id = new.id and a.kind in ('storefront','payment_account')) then
      raise exception 'AVE: launch requires an owner-controlled storefront or payment_account asset registered for the venture';
    end if;
    if not exists (select 1 from venture_assets a where a.venture_id = new.id and a.kind in ('repo','hosting')) then
      raise exception 'AVE: launch requires an owner-controlled repo or hosting asset registered for the venture';
    end if;
  end if;
  return new;
end $$;
-- Named to fire BEFORE ventures_stage (alphabetical): "ventures_0_assets".
drop trigger if exists ventures_0_assets on ventures;
create trigger ventures_0_assets before update of stage on ventures
  for each row execute function trg_launch_requires_assets();

-- ---------------------------------------------------------------------
-- 4. Spend: custody categories + dogfood stage caps (fires before adjudication)
-- ---------------------------------------------------------------------
alter table spend_requests add column if not exists stage_at_request venture_stage;

create or replace function fn_venture_stage_spent(p_venture uuid, p_stage venture_stage) returns bigint language sql stable as $$
  select coalesce(sum(s.amount_cents),0) from spend_requests s
  where s.venture_id = p_venture and s.stage_at_request = p_stage
    and s.status in ('auto_approved','approved','spent');
$$;


create or replace function trg_spend_reshape_rules() returns trigger language plpgsql as $$
declare p policies%rowtype; v ventures%rowtype; cap bigint; key text;
begin
  select * into p from policies where owner_id = new.owner_id;
  if not found then return new; end if;  -- adjudicator raises the proper error

  -- 'contractors' spend is allowed only as a pass-through the owner approves; never 'other' for money movement
  if new.purpose ~* '(hold|move|transfer|invest|pool)\s+(the\s+)?(owner|customer|user)s?''?\s*(money|funds|capital)' then
    raise exception 'AVE: agents never hold, move or invest anyone''s money (purpose: %)', new.purpose;
  end if;

  if new.venture_id is not null then
    select * into v from ventures where id = new.venture_id;
    new.stage_at_request := v.stage;
    if v.dogfood then
      key := v.stage::text;
      if p.dogfood_stage_caps ? key then
        cap := (p.dogfood_stage_caps ->> key)::bigint;
        if fn_venture_stage_spent(v.id, v.stage) + new.amount_cents > cap then
          raise exception 'AVE: dogfood stage cap for % is % cents (% already committed, % requested)',
            key, cap, fn_venture_stage_spent(v.id, v.stage), new.amount_cents;
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists spend_requests_0_reshape on spend_requests;
create trigger spend_requests_0_reshape before insert on spend_requests
  for each row execute function trg_spend_reshape_rules();

-- ---------------------------------------------------------------------
-- 5. Cost of intelligence (dependency blind spot)
-- ---------------------------------------------------------------------
alter table agent_runs
  add column if not exists model text,
  add column if not exists tokens_in bigint not null default 0,
  add column if not exists tokens_out bigint not null default 0,
  add column if not exists cost_cents bigint not null default 0;   -- platform/model cost of this run, estimated

create or replace view v_cost_of_intelligence as
select v.id as venture_id, v.owner_id, v.name, v.stage,
       coalesce(sum(r.cost_cents),0)                                   as intelligence_cost_cents,
       fn_venture_spent(v.id)                                          as cash_spent_cents,
       (select coalesce(sum(l.amount_cents),0) from ledger l
         where l.venture_id = v.id and l.kind='revenue' and l.verified) as verified_revenue_cents,
       count(r.id)                                                     as runs
from ventures v left join agent_runs r on r.venture_id = v.id
group by v.id;

-- ---------------------------------------------------------------------
-- 6. Public ledger snapshots (owner publishes; anon may read published rows)
-- ---------------------------------------------------------------------
create table if not exists public_ledger_snapshots (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references owners(id) on delete cascade,
  slug          text not null,                     -- /ledger.html?s=<slug>
  title         text not null,
  snapshot      jsonb not null,                    -- {portfolio, ventures:[{name,stage,spent,revenue,decisions:[...]}], generated_at}
  published     boolean not null default false,
  generated_by  text not null default 'treasurer',
  created_at    timestamptz not null default now(),
  unique (owner_id, slug)
);

-- Only the owner can flip published; the Treasurer may insert unpublished snapshots.
create or replace function trg_snapshot_publish_owner_only() returns trigger language plpgsql as $$
begin
  if new.published and (tg_op = 'INSERT' or new.published is distinct from old.published) then
    if auth.uid() is null or auth.uid() <> new.owner_id then
      raise exception 'AVE: only the authenticated owner may publish a ledger snapshot';
    end if;
    if not exists (select 1 from policies p where p.owner_id = new.owner_id and p.public_ledger) then
      raise exception 'AVE: enable public_ledger in policy before publishing';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists public_ledger_publish on public_ledger_snapshots;
create trigger public_ledger_publish before insert or update on public_ledger_snapshots
  for each row execute function trg_snapshot_publish_owner_only();

-- Treasurer helper: builds the snapshot JSON (actuals only, no forecasts).
create or replace function fn_build_ledger_snapshot(p_owner uuid) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'generated_at', now(),
    'disclaimer', 'Actuals only. Verified revenue requires a payment reference. Nothing here is a forecast or a guarantee.',
    'portfolio', (select to_jsonb(pf) - 'owner_id' from v_portfolio pf where pf.owner_id = p_owner),
    'ventures', (select coalesce(jsonb_agg(jsonb_build_object(
        'name', vv.name, 'stage', vv.stage, 'solution_shape', vv.solution_shape, 'dogfood', vv.dogfood,
        'budget_cents', vv.budget_cents, 'spent_cents', vv.spent_cents, 'revenue_cents', vv.revenue_cents,
        'intelligence_cost_cents', (select intelligence_cost_cents from v_cost_of_intelligence c where c.venture_id = vv.id),
        'ledger', (select coalesce(jsonb_agg(jsonb_build_object('at', l.created_at, 'kind', l.kind, 'amount_cents', l.amount_cents,
                      'description', l.description, 'verified', l.verified) order by l.created_at), '[]'::jsonb)
                   from ledger l where l.venture_id = vv.id),
        'decisions', (select coalesce(jsonb_agg(jsonb_build_object('at', d.created_at, 'agent', d.agent, 'stage', d.stage,
                      'decision', d.decision, 'rationale', d.rationale) order by d.created_at), '[]'::jsonb)
                      from decisions d where d.venture_id = vv.id)
      ) order by vv.created_at), '[]'::jsonb) from v_ventures vv where vv.owner_id = p_owner)
  );
$$;

-- ---------------------------------------------------------------------
-- 7. RLS for the new tables
-- ---------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['owner_edge','venture_assets','public_ledger_snapshots'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I_owner_select on %I', t, t);
    execute format('drop policy if exists %I_owner_write on %I', t, t);
    execute format('create policy %I_owner_select on %I for select using (owner_id = auth.uid())', t, t);
    execute format('create policy %I_owner_write on %I for all using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t, t);
  end loop;
end $$;
drop policy if exists public_ledger_anon_read on public_ledger_snapshots;
create policy public_ledger_anon_read on public_ledger_snapshots for select using (published = true);

-- Bootstrap: owners created after this migration get an empty edge row to fill.
create or replace function fn_bootstrap_owner(p_name text, p_email text default null, p_currency text default 'USD')
returns uuid language plpgsql security definer as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'AVE: sign in first'; end if;
  insert into owners (id, display_name, email, currency) values (uid, p_name, p_email, p_currency)
    on conflict (id) do nothing;
  insert into policies (owner_id) values (uid) on conflict (owner_id) do nothing;
  insert into owner_edge (owner_id) values (uid) on conflict (owner_id) do nothing;
  return uid;
end $$;
