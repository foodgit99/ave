"""
AVE guardrail tests — runs the real migration against an embedded Postgres
(pgserver) and asserts the rules-based risk layer behaves deterministically.

    pip install pgserver psycopg2-binary   (or: pip install pgserver "psycopg[binary]")
    python3 tests/test_guardrails.py
"""
import os, sys, uuid, pathlib

import pgserver
try:
    import psycopg
    def connect(uri): return psycopg.connect(uri, autocommit=True)
except ImportError:
    import psycopg2 as psycopg
    def connect(uri):
        c = psycopg.connect(uri); c.autocommit = True; return c

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATIONS = [(ROOT / f).read_text() for f in ("supabase/migrations/0001_ave_core.sql", "supabase/migrations/0002_reshape_operator_edge.sql",
                                                    "supabase/migrations/0003_autonomy_levels.sql")]

OWNER = uuid.UUID("11111111-1111-1111-1111-111111111111")
STRANGER = uuid.UUID("22222222-2222-2222-2222-222222222222")

passed = failed = 0
def check(name, cond, detail=""):
    global passed, failed
    if cond: passed += 1; print(f"  ✓ {name}")
    else:    failed += 1; print(f"  ✗ {name}  {detail}")

def expect_error(cur, sql, params=None, needle="AVE:"):
    try:
        cur.execute(sql, params); return None
    except Exception as e:
        return str(e)

def as_owner(cur, uid=OWNER):
    cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (str(uid),))
def as_agent(cur):
    cur.execute("select set_config('request.jwt.claim.sub', '', false)")

def main():
    db = pgserver.get_server(str(ROOT / ".pgdata"))
    con = connect(db.get_uri()); cur = con.cursor()
    cur.execute("drop schema public cascade; create schema public;")
    for m in MIGRATIONS: cur.execute(m)
    print("migrations applied (0001 core, 0002 reshape, 0003 autonomy levels)")

    # ---- bootstrap owner ($500 capital, default policy) -------------------
    as_owner(cur)
    cur.execute("select fn_bootstrap_owner('Test Owner','t@example.com')")
    # legacy sections run with dogfood mode off and micro-SaaS allowed; section 6 turns the reshape rules on
    cur.execute("update policies set dogfood_mode=false, allowed_solution_shapes=allowed_solution_shapes||'{micro_saas}' where owner_id=%s", (str(OWNER),))
    cur.execute("insert into ledger(owner_id,kind,amount_cents,description) values (%s,'capital_in',50000,'initial allocation')", (str(OWNER),))
    cur.execute("insert into ventures(owner_id,name,slug,budget_cents,stage) values (%s,'Invoice Nudge','invoice-nudge',20000,'validate') returning id", (str(OWNER),))
    V = cur.fetchone()[0]
    cur.execute("select available_cents from v_portfolio where owner_id=%s", (str(OWNER),))
    check("capital in → available 50000", cur.fetchone()[0] == 50000)

    print("\n1. spend adjudication (agent session, no JWT)")
    as_agent(cur)
    err = expect_error(cur, "insert into ledger(owner_id,kind,amount_cents,description) values (%s,'capital_in',99999,'agent tries to mint money')", (str(OWNER),))
    check("agent cannot move capital in", err and "only the authenticated owner may move capital" in err, err)

    def file_spend(amount, cat='ads', purpose='landing page test traffic', venture=V):
        cur.execute("""insert into spend_requests(owner_id,venture_id,requested_by,category,amount_cents,purpose,status)
                       values (%s,%s,'distributor',%s,%s,%s,'approved') returning id,status,decision_reason""",
                    (str(OWNER), venture, cat, amount, purpose))
        return cur.fetchone()

    sid, st, why = file_spend(2000)
    check("$20 ad spend auto-approved (caller's 'approved' ignored, trigger decides)", st == 'auto_approved', why)
    sid2, st, why = file_spend(2600)
    check("$26 → pending_owner (above $25 auto limit)", st == 'pending_owner', why)
    cur.execute("select count(*) from approvals where payload->>'spend_request_id'=%s", (str(sid2),))
    check("pending spend mirrored into approvals inbox", cur.fetchone()[0] == 1)
    _, st, why = file_spend(1000, cat='contractors')
    check("disallowed category rejected", st == 'rejected' and 'not allowed' in why, why)
    _, st, why = file_spend(1000, purpose='promote crypto-token presale')
    check("forbidden keyword rejected", st == 'rejected' and 'forbidden keyword' in why, why)
    _, st, why = file_spend(60000)
    check("more than available capital rejected", st == 'rejected' and 'insufficient' in why, why)

    # daily limit: $100/day of agent-approved spend. Already 2000 auto-approved.
    for _ in range(4): file_spend(2000)       # 10000 total
    _, st, why = file_spend(2000)
    check("daily agent spend limit → pending_owner", st == 'pending_owner' and 'daily' in why, why)

    cur.execute("select reserved_cents, available_cents from v_portfolio where owner_id=%s", (str(OWNER),))
    reserved, avail = cur.fetchone()
    check("approved-but-unspent is reserved against capital", reserved == 10000 and avail == 40000, f"{reserved} {avail}")

    print("\n2. venture budget ceiling")
    cur.execute("insert into ventures(owner_id,name,slug,budget_cents,stage) values (%s,'Tiny','tiny',1500,'validate') returning id", (str(OWNER),))
    V2 = cur.fetchone()[0]
    _, st, why = file_spend(2000, venture=V2)
    check("spend exceeding venture budget → pending_owner", st == 'pending_owner' and 'venture budget' in why, why)

    print("\n3. ledger expense rules")
    err = expect_error(cur, "insert into ledger(owner_id,venture_id,kind,amount_cents,description) values (%s,%s,'expense',500,'unreferenced')", (str(OWNER), V))
    check("expense without spend_request refused", err and "must reference" in err, err)
    err = expect_error(cur, "insert into ledger(owner_id,venture_id,spend_request_id,kind,amount_cents,description) values (%s,%s,%s,'expense',500,'spend on pending')", (str(OWNER), V, sid2))
    check("expense against pending request refused", err and "not spendable" in err, err)
    cur.execute("insert into ledger(owner_id,venture_id,spend_request_id,kind,amount_cents,description) values (%s,%s,%s,'expense',1500,'meta ads day 1')", (str(OWNER), V, sid))
    cur.execute("select status from spend_requests where id=%s", (sid,))
    check("partial expense marks request spent", cur.fetchone()[0] == 'spent')
    err = expect_error(cur, "insert into ledger(owner_id,venture_id,spend_request_id,kind,amount_cents,description) values (%s,%s,%s,'expense',600,'meta ads day 2 overspend')", (str(OWNER), V, sid))
    check("overspend beyond approved amount refused", err and "exceeds approved" in err, err)
    cur.execute("insert into ledger(owner_id,venture_id,spend_request_id,kind,amount_cents,description) values (%s,%s,%s,'expense',500,'meta ads day 2')", (str(OWNER), V, sid))
    check("remaining headroom can be spent", True)
    err = expect_error(cur, "update ledger set amount_cents=1 where spend_request_id=%s", (sid,))
    check("ledger rows immutable", err and "immutable" in err, err)
    err = expect_error(cur, "insert into ledger(owner_id,venture_id,kind,amount_cents,description,verified) values (%s,%s,'revenue',9900,'first sale',true)", (str(OWNER), V))
    check("verified revenue needs external_ref", err and "external_ref" in err, err)
    cur.execute("insert into ledger(owner_id,venture_id,kind,amount_cents,description,verified,external_ref) values (%s,%s,'revenue',9900,'first sale',true,'pi_123')", (str(OWNER), V))
    cur.execute("insert into ledger(owner_id,venture_id,kind,amount_cents,description,verified) values (%s,%s,'revenue',5000,'promised sale',false)", (str(OWNER), V))
    cur.execute("select verified_revenue_cents from v_portfolio where owner_id=%s", (str(OWNER),))
    check("only verified revenue counts", cur.fetchone()[0] == 9900)

    print("\n4. owner-only decisions")
    err = expect_error(cur, "update spend_requests set status='approved' where id=%s", (sid2,))
    check("agent cannot approve pending spend", err and "only the authenticated owner" in err, err)
    err = expect_error(cur, "update owners set kill_switch=false where id=%s", (str(OWNER),))
    check("agent cannot touch kill switch", err and "authenticated owner" in err, err)
    err = expect_error(cur, "update policies set auto_approve_limit_cents=999999 where owner_id=%s", (str(OWNER),))
    check("agent cannot loosen policy", err and "authenticated owner" in err, err)
    as_owner(cur, STRANGER)
    err = expect_error(cur, "update spend_requests set status='approved' where id=%s", (sid2,))
    check("another user cannot approve", err and "only the authenticated owner" in err, err)
    as_owner(cur)
    cur.execute("update approvals set status='approved', decision_note='ok, go' where payload->>'spend_request_id'=%s", (str(sid2),))
    cur.execute("select status, decided_by from spend_requests where id=%s", (sid2,))
    st, by = cur.fetchone()
    check("owner approval via inbox cascades to spend request", st == 'approved' and by.startswith('owner:'), f"{st} {by}")

    print("\n5. lifecycle gates")
    as_agent(cur)
    cur.execute("update ventures set stage='build' where id=%s", (V,))
    err = expect_error(cur, "update ventures set stage='distribute' where id=%s", (V,))
    check("launch without owner approval blocked", err and "launch requires" in err, err)
    cur.execute("insert into approvals(owner_id,venture_id,type,title,requested_by) values (%s,%s,'launch','Launch Invoice Nudge','orchestrator') returning id", (str(OWNER), V))
    aid = cur.fetchone()[0]
    as_owner(cur); cur.execute("update approvals set status='approved' where id=%s", (aid,)); as_agent(cur)
    err = expect_error(cur, "update ventures set stage='distribute' where id=%s", (V,))
    check("launch without owner-controlled assets blocked", err and "storefront or payment_account" in err, err)
    err = expect_error(cur, "insert into venture_assets(owner_id,venture_id,kind,provider,url_or_id,owner_controlled) values (%s,%s,'storefront','lemonsqueezy','https://x.lemonsqueezy.com',false)", (str(OWNER), V))
    check("asset AVE controls cannot be registered", err and "owner_controlled" in err, err)
    cur.execute("insert into venture_assets(owner_id,venture_id,kind,provider,url_or_id) values (%s,%s,'storefront','lemonsqueezy','https://x.lemonsqueezy.com'),(%s,%s,'repo','github','foodgit99/invoice-nudge')", (str(OWNER), V, str(OWNER), V))
    cur.execute("select set_config('ave.actor','orchestrator',false), set_config('ave.rationale','MVP passed QA; landing converts 4.1%',false)")
    cur.execute("update ventures set stage='distribute' where id=%s", (V,))
    cur.execute("select decision, rationale from decisions where venture_id=%s order by created_at desc limit 1", (V,))
    d = cur.fetchone()
    check("approved launch advances stage and logs decision", d and 'build → distribute' in d[0] and 'QA' in d[1], d)
    err = expect_error(cur, "update ventures set budget_cents=90000 where id=%s", (V,))
    check("budget raise without scale approval blocked", err and "scale" in err, err)
    err = expect_error(cur, "update ventures set stage='killed' where id=%s", (V,))
    check("kill without owner approval blocked", err and "kill requires" in err, err)
    # max_active_ventures = 2 : V (distribute) + V2 (validate) active → third blocked
    cur.execute("insert into ventures(owner_id,name,slug,budget_cents) values (%s,'Third','third',1000) returning id", (str(OWNER),))
    V3 = cur.fetchone()[0]
    err = expect_error(cur, "update ventures set stage='validate' where id=%s", (V3,))
    check("max_active_ventures enforced", err and "max_active_ventures" in err, err)

    print("\n6. reshape rules (operator edge, wedge, dogfood caps, no custody, public ledger)")
    err = expect_error(cur, "insert into opportunities(owner_id,title,status) values (%s,'Anything','new')", (str(OWNER),))
    check("discovery refused until edge profile complete", err and "edge profile" in err, err)
    as_owner(cur)
    cur.execute("update owner_edge set operator_type='agency', edge_statement='We run Meta ads for 14 Nigerian SMEs and have a 3k WhatsApp list', distribution_channels='{whatsapp_list,meta_ads,youtube}', completed_at=now() where owner_id=%s", (str(OWNER),))
    as_agent(cur)
    cur.execute("insert into opportunities(owner_id,title,problem,target_customer,status) values (%s,'Invoice templates for SME accountants','accountants rebuild invoice templates monthly','SME accountants in Lagos','new') returning id", (str(OWNER),))
    check("discovery allowed once edge is complete", cur.fetchone() is not None)
    as_owner(cur); cur.execute("update policies set dogfood_mode=true, daily_spend_limit_cents=100000, allowed_solution_shapes='{digital_product,ai_service,productized_service,automation_tool}' where owner_id=%s", (str(OWNER),)); as_agent(cur)
    err = expect_error(cur, "insert into ventures(owner_id,name,slug,budget_cents,solution_shape) values (%s,'SaaSy','saasy',5000,'micro_saas')", (str(OWNER),))
    check("micro-SaaS outside wedge refused", err and "outside the owner's allowed wedge" in err, err)
    err = expect_error(cur, "insert into ventures(owner_id,name,slug,budget_cents) values (%s,'Big','big',20000)", (str(OWNER),))
    check("dogfood mode caps venture at $100", err and "dogfood mode caps" in err, err)
    cur.execute("insert into ventures(owner_id,name,slug,budget_cents,solution_shape) values (%s,'Dogfood','dogfood',10000,'digital_product') returning id,dogfood", (str(OWNER),))
    VD, df = cur.fetchone()
    check("new venture flagged dogfood", df is True)
    # need capacity: pause V2 (validate) so VD can enter validate under max_active_ventures=2 (V in distribute)
    cur.execute("update ventures set stage='paused' where id=%s", (V2,))
    cur.execute("update ventures set stage='validate' where id=%s", (VD,))
    _, st, why = file_spend(2500, venture=VD, purpose='landing page + outreach tool')
    check("$25 validate spend ok under $40 stage cap", st == 'auto_approved', why)
    err = expect_error(cur, "insert into spend_requests(owner_id,venture_id,requested_by,category,amount_cents,purpose) values (%s,%s,'validator','ads',2000,'3 days niche traffic')", (str(OWNER), VD))
    check("validate stage cap $40 enforced ($25 + $20 refused)", err and "dogfood stage cap" in err, err)
    cur.execute("select stage_at_request from spend_requests where venture_id=%s", (VD,))
    check("stage recorded on spend request", cur.fetchone()[0] == 'validate')
    err = expect_error(cur, "insert into spend_requests(owner_id,venture_id,requested_by,category,amount_cents,purpose) values (%s,%s,'treasurer','fees',100,'hold the owner money in escrow')", (str(OWNER), VD))
    check("custody language hard-refused", err and "never hold, move or invest" in err, err)
    _, st, why = file_spend(100, venture=VD, purpose='revenue share platform cut')
    check("'revenue share' keyword rejected by policy", st == 'rejected' and 'forbidden keyword' in why, why)
    cur.execute("insert into agent_runs(owner_id,venture_id,agent,task,status,model,tokens_in,tokens_out,cost_cents) values (%s,%s,'scout','discovery','done','fable-5.1',120000,8000,42)", (str(OWNER), VD))
    cur.execute("select intelligence_cost_cents, cash_spent_cents from v_cost_of_intelligence where venture_id=%s", (VD,))
    ic, cs = cur.fetchone()
    check("cost of intelligence tracked next to cash", ic == 42 and cs == 0, f"{ic} {cs}")
    cur.execute("select fn_build_ledger_snapshot(%s)", (str(OWNER),))
    snap = cur.fetchone()[0]
    check("ledger snapshot has actuals + disclaimer", 'disclaimer' in snap and len(snap['ventures']) >= 3)
    err = expect_error(cur, "insert into public_ledger_snapshots(owner_id,slug,title,snapshot,published) values (%s,'run-1','Dogfood run 1',%s::jsonb,true)", (str(OWNER), __import__('json').dumps(snap)))
    check("agent cannot publish ledger", err and "only the authenticated owner may publish" in err, err)
    cur.execute("insert into public_ledger_snapshots(owner_id,slug,title,snapshot) values (%s,'run-1','Dogfood run 1',%s::jsonb) returning id", (str(OWNER), __import__('json').dumps(snap)))
    snap_id = cur.fetchone()[0]
    as_owner(cur)
    err = expect_error(cur, "update public_ledger_snapshots set published=true where id=%s", (snap_id,))
    check("owner must enable public_ledger policy first", err and "enable public_ledger" in err, err)
    cur.execute("update policies set public_ledger=true where owner_id=%s", (str(OWNER),))
    cur.execute("update public_ledger_snapshots set published=true where id=%s", (snap_id,))
    check("owner publishes snapshot", True)
    as_agent(cur)

    print("\n7. autonomy levels (earned, preset-applied, Level 5 refused)")
    cur.execute("select autonomy_level, level_custom from policies where owner_id=%s", (str(OWNER),))
    lvl, custom = cur.fetchone()
    check("default level is 2, marked custom after hand-tuning limits", lvl == 2 and custom is True, f"{lvl} {custom}")
    err = expect_error(cur, "update policies set autonomy_level=3 where owner_id=%s", (str(OWNER),))
    check("agent cannot change the autonomy level", err and "authenticated owner" in err, err)
    as_owner(cur)
    err = expect_error(cur, "update policies set autonomy_level=5 where owner_id=%s", (str(OWNER),))
    check("Level 5 is not offered", err and "not offered" in err, err)
    err = expect_error(cur, "update policies set autonomy_level=3 where owner_id=%s", (str(OWNER),))
    check("Level 3 refused until the ledger earns it", err and "Level 3 is earned" in err and "have 0" in err, err)
    cur.execute("update policies set autonomy_level=1 where owner_id=%s returning auto_approve_limit_cents, daily_spend_limit_cents, dogfood_mode, level_custom", (str(OWNER),))
    a, d, df, custom = cur.fetchone()
    check("Level 1 preset applied (agents may spend nothing unasked)", a == 0 and d == 0 and df is True and custom is False, f"{a} {d} {df} {custom}")
    as_agent(cur)
    cur.execute("update ventures set stage='build' where id=%s", (VD,))
    _, st, why = file_spend(100, venture=VD, purpose='domain for product page')
    check("at Level 1 even a $1 spend waits for the owner", st == 'pending_owner', why)
    as_owner(cur)
    cur.execute("update policies set autonomy_level=2 where owner_id=%s returning auto_approve_limit_cents, max_active_ventures", (str(OWNER),))
    check("Level 2 preset restores the default limits", cur.fetchone() == (2500, 2))
    cur.execute("select decision from decisions where owner_id=%s and agent='owner' order by created_at desc limit 1", (str(OWNER),))
    check("level change is logged as a decision", 'autonomy level 1 → 2' in cur.fetchone()[0])
    # earn Level 3: three completed ventures + one published ledger (published in section 6)
    for i in range(3):
        cur.execute("insert into ventures(owner_id,name,slug,budget_cents) values (%s,%s,%s,10000) returning id", (str(OWNER), f'Proof {i}', f'proof-{i}'))
        cur.execute("update ventures set stage='killed' where id=%s", (cur.fetchone()[0],))
    cur.execute("select completed_ventures, published_ledgers, max_level_earned from fn_level_evidence(%s)", (str(OWNER),))
    check("evidence: 3 completed, 1 published → Level 3 earned", cur.fetchone() == (3, 1, 3))
    cur.execute("update policies set autonomy_level=3 where owner_id=%s returning dogfood_mode, auto_approve_limit_cents, require_owner_for::text", (str(OWNER),))
    df, a, req = cur.fetchone()
    check("Level 3 granted: proof mode off, owner still gates launch and kill", df is False and a == 4000 and 'launch' in req and 'kill' in req, f"{df} {a} {req}")
    err = expect_error(cur, "update policies set autonomy_level=4 where owner_id=%s", (str(OWNER),))
    check("Level 4 refused: needs 10 completed and a venture that beat its all-in cost", err and "Level 4 is earned" in err, err)
    cur.execute("update policies set auto_approve_limit_cents=3000 where owner_id=%s returning autonomy_level, level_custom", (str(OWNER),))
    check("tightening a limit keeps the level, marks it custom", cur.fetchone() == (3, True))
    cur.execute("select fn_build_ledger_snapshot(%s)->'autonomy_level'", (str(OWNER),))
    al = cur.fetchone()[0]
    check("ledger snapshot states the level it was run at", al['level'] == 3 and al['name'] == 'Conditional' and al['custom'] is True, al)
    cur.execute("update policies set autonomy_level=2 where owner_id=%s", (str(OWNER),))
    check("stepping down is always allowed", True)
    as_agent(cur)

    print("\n8. kill switch")
    as_owner(cur); cur.execute("update owners set kill_switch=true where id=%s", (str(OWNER),)); as_agent(cur)
    _, st, why = file_spend(100)
    check("kill switch rejects all new spend", st == 'rejected' and 'kill switch' in why, why)

    print(f"\n{passed} passed, {failed} failed")
    con.close()
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
