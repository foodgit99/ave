-- =====================================================================
-- AVE v0.2 — Autonomous Venturing: the five levels, in the database
--
-- The category AVE claims is "Autonomous Venturing", defined by levels of
-- autonomy (docs/FIVE_LEVELS.md). This migration makes a level a real,
-- enforced setting rather than a label on the dashboard:
--
--   L1 Assisted     agents research and propose; every spend asks the owner
--   L2 Supervised   small capped spends; $100 proof ventures; owner approves
--                   launch, kill, scale and outside commitments   (DEFAULT)
--   L3 Conditional  full lifecycle inside a venture budget; same owner gates
--   L4 High         agents launch and kill inside budget; owner approves
--                   scale and outside commitments only
--   L5 Full         NOT OFFERED. Refused by constraint and by trigger.
--
-- Rules encoded here:
--   * Setting a level applies that level's limits (the preset) in one step.
--   * Levels are EARNED: moving up to L3 or L4 is refused until the owner's
--     own ledger shows the evidence. Moving down is always allowed.
--   * Hand-tuning a limit keeps the level but marks it "custom".
--   * Only the authenticated owner can change a level (existing owner-only
--     trigger on policies; agents have no JWT).
-- Idempotent; safe to re-run after 0001 and 0002.
-- =====================================================================

alter table policies
  add column if not exists autonomy_level smallint not null default 2,
  add column if not exists level_custom boolean not null default false,
  add column if not exists level_changed_at timestamptz;

do $$ begin
  alter table policies add constraint policies_autonomy_level_offered check (autonomy_level between 1 and 4);
exception when duplicate_object then null; end $$;

create or replace function fn_level_name(p_level int) returns text language sql immutable as $$
  select case p_level when 1 then 'Assisted' when 2 then 'Supervised' when 3 then 'Conditional'
                      when 4 then 'High' when 5 then 'Full (not offered)' else 'Unknown' end;
$$;

-- What the owner's ledger has earned so far (used by the gate and the dashboard).
create or replace function fn_level_evidence(p_owner uuid)
returns table(completed_ventures int, published_ledgers int, profitable_ventures int, max_level_earned int)
language sql stable as $$
  with e as (
    select
      (select count(*)::int from ventures v where v.owner_id = p_owner and v.stage in ('decide','scale','killed')) as completed,
      (select count(*)::int from public_ledger_snapshots s where s.owner_id = p_owner and s.published) as published,
      (select count(*)::int from v_cost_of_intelligence c where c.owner_id = p_owner
          and c.verified_revenue_cents > c.cash_spent_cents + c.intelligence_cost_cents) as profitable)
  select completed, published, profitable,
         case when completed >= 10 and published >= 1 and profitable >= 1 then 4
              when completed >= 3 and published >= 1 then 3
              else 2 end
  from e;
$$;

create or replace function trg_policy_level() returns trigger language plpgsql as $$
declare ev record;
begin
  if new.autonomy_level is distinct from old.autonomy_level then
    if new.autonomy_level >= 5 then
      raise exception 'AVE: Level 5 (full autonomy, no owner at the wheel) is not offered';
    end if;
    if new.autonomy_level < 1 then
      raise exception 'AVE: autonomy level must be between 1 and 4';
    end if;

    -- Levels are earned. Going down is always allowed.
    if new.autonomy_level > old.autonomy_level and new.autonomy_level >= 3 then
      select * into ev from fn_level_evidence(new.owner_id);
      if new.autonomy_level > ev.max_level_earned then
        if new.autonomy_level = 3 then
          raise exception 'AVE: Level 3 is earned, not chosen: it needs 3 completed ventures (have %) and 1 published ledger (have %)',
            ev.completed_ventures, ev.published_ledgers;
        else
          raise exception 'AVE: Level 4 is earned, not chosen: it needs 10 completed ventures (have %), 1 published ledger (have %) and 1 venture whose verified revenue beat its cash plus intelligence cost (have %)',
            ev.completed_ventures, ev.published_ledgers, ev.profitable_ventures;
        end if;
      end if;
    end if;

    -- Apply the level's preset. The owner can tighten afterwards (marks it custom).
    if new.autonomy_level = 1 then
      new.auto_approve_limit_cents := 0;      new.daily_spend_limit_cents := 0;
      new.venture_budget_cap_cents := 10000;  new.max_active_ventures := 1;
      new.dogfood_mode := true;
      new.require_owner_for := array['launch','kill','scale','external_commitment']::approval_type[];
    elsif new.autonomy_level = 2 then
      new.auto_approve_limit_cents := 2500;   new.daily_spend_limit_cents := 10000;
      new.venture_budget_cap_cents := 50000;  new.max_active_ventures := 2;
      new.dogfood_mode := true;
      new.require_owner_for := array['launch','kill','scale','external_commitment']::approval_type[];
    elsif new.autonomy_level = 3 then
      new.auto_approve_limit_cents := 4000;   new.daily_spend_limit_cents := 15000;
      new.venture_budget_cap_cents := 50000;  new.max_active_ventures := 2;
      new.dogfood_mode := false;
      new.require_owner_for := array['launch','kill','scale','external_commitment']::approval_type[];
    else -- 4
      new.auto_approve_limit_cents := 10000;  new.daily_spend_limit_cents := 30000;
      new.venture_budget_cap_cents := 50000;  new.max_active_ventures := 3;
      new.dogfood_mode := false;
      new.require_owner_for := array['scale','external_commitment']::approval_type[];
    end if;
    new.level_custom := false;
    new.level_changed_at := now();

    insert into decisions (owner_id, agent, decision, rationale)
    values (new.owner_id, 'owner', format('autonomy level %s → %s (%s)', old.autonomy_level, new.autonomy_level, fn_level_name(new.autonomy_level)),
            'owner changed the autonomy level; the level preset was applied to policy');

  elsif (new.auto_approve_limit_cents, new.daily_spend_limit_cents, new.venture_budget_cap_cents,
         new.max_active_ventures, new.dogfood_mode, new.require_owner_for)
        is distinct from
        (old.auto_approve_limit_cents, old.daily_spend_limit_cents, old.venture_budget_cap_cents,
         old.max_active_ventures, old.dogfood_mode, old.require_owner_for) then
    new.level_custom := true;   -- hand-tuned inside the level
  end if;
  return new;
end $$;

-- Named to fire AFTER policies_owner_only (alphabetical), so agents are refused first.
drop trigger if exists policies_p_level on policies;
create trigger policies_p_level before update on policies
  for each row execute function trg_policy_level();

-- Published ledgers state the level the ventures were run at.
create or replace function fn_build_ledger_snapshot(p_owner uuid) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'generated_at', now(),
    'autonomy_level', (select jsonb_build_object('level', p.autonomy_level, 'name', fn_level_name(p.autonomy_level), 'custom', p.level_custom) from policies p where p.owner_id = p_owner),
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
