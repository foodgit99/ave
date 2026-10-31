-- Demo data for the dashboard. Run AFTER signing in once (so your owner row exists).
-- Replace the uuid below with your owner id (shown as auth.users.id in Supabase → Authentication).
\set owner '00000000-0000-0000-0000-000000000000'
insert into ledger (owner_id, kind, amount_cents, description, verified, recorded_by)
  values (:'owner','capital_in',50000,'initial allocation',true,'seed');
insert into ventures (owner_id,name,slug,thesis,stage,budget_cents,target_market)
  values (:'owner','Invoice Nudge','invoice-nudge','Freelance designers pay humans $40/mo to chase invoices; a $9/mo reminder service wins on price and reliability.','validate',40000,'Freelance designers, EU/UK/NG, 1–10 clients');
insert into opportunities (owner_id,title,problem,target_customer,confidence,status,evidence) values
 (:'owner','Invoice chasing for freelancers','Late payments; awkward to chase; time lost','Freelance designers',0.72,'evaluated',
  '[{"claim":"Fiverr gigs for invoice follow-up at $40/mo","source_url":"https://fiverr.com/...","strength":"strong"}]'),
 (:'owner','Compliance calendar for small clinics','Missed licence renewals cause fines','Clinic managers, 1–3 sites',0.55,'new','[]');
