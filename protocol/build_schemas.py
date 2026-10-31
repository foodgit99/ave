"""Generates the AVE hand-off protocol JSON Schemas (protocol/*.schema.json).
Every packet an agent passes to another agent or writes to Supabase jsonb
columns must validate against one of these. Run: python3 protocol/build_schemas.py
"""
import json, pathlib
OUT = pathlib.Path(__file__).parent
BASE = "https://ave.schemas/"

def S(title, props, required, desc):
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": BASE + title + ".schema.json",
            "title": title, "description": desc, "type": "object", "additionalProperties": False,
            "required": required, "properties": props}

str_ = lambda d="": {"type": "string", "description": d}
num = lambda d="": {"type": "number", "description": d}
int_ = lambda d="": {"type": "integer", "description": d}
arr = lambda items, d="": {"type": "array", "items": items, "description": d}
conf = {"type": "number", "minimum": 0, "maximum": 1, "description": "0-1 confidence"}

evidence_item = {"type": "object", "required": ["claim", "source_url", "strength"], "properties": {
    "claim": str_(), "source_url": str_("Where it was observed; 'interview' for primary research"),
    "strength": {"type": "string", "enum": ["weak", "moderate", "strong"]}, "date": str_("ISO date observed")}}
edge_fit = {"type": "object", "required": ["uses", "route_to_first_ten", "score"], "description": "How this uses the owner's edge (owner_edge). Generic ideas score low and are dropped.",
    "properties": {"uses": arr({"type": "string", "enum": ["audience", "domain", "channel", "asset", "geography", "none"]}),
                   "route_to_first_ten": str_("How the first ten customers are reached through the owner's existing audience/channels"),
                   "score": {"type": "number", "minimum": 0, "maximum": 1}, "why": str_()}}
asset_item = {"type": "object", "required": ["kind", "provider", "url_or_id", "owner_controlled"], "properties": {
    "kind": {"type": "string", "enum": ["repo", "domain", "storefront", "payment_account", "ad_account", "hosting", "email", "analytics", "other"]},
    "provider": str_(), "url_or_id": str_(), "owner_controlled": {"type": "boolean", "const": True, "description": "Always true: AVE never holds an asset"}}}
assumption_item = {"type": "object", "required": ["assumption", "risk_if_wrong", "how_to_test"], "properties": {
    "assumption": str_(), "risk_if_wrong": {"type": "string", "enum": ["low", "medium", "fatal"]}, "how_to_test": str_()}}

schemas = {
 "OpportunityPacket": S("OpportunityPacket", {
    "title": str_(), "problem": str_("The specific pain, in the customer's words"),
    "target_customer": str_("Who exactly; role, context, where they gather online"),
    "current_alternatives": arr(str_(), "What they do today and what it costs them"),
    "why_now": str_("Trend, policy, tech or behaviour shift making this timely"),
    "evidence": arr(evidence_item), "assumptions": arr(assumption_item),
    "edge_fit": edge_fit,
    "proposed_solution_shape": {"type": "string", "enum": ["digital_product", "ai_service", "productized_service", "automation_tool", "micro_saas", "marketplace_lite"], "description": "Must be in policies.allowed_solution_shapes; digital_product first in v0.1"},
    "estimated_willingness_to_pay_usd": num("Monthly or one-off; state which in notes"), "notes": str_(), "confidence": conf,
    "scout_agent": str_(), "discovered_at": str_("ISO timestamp")},
    ["title", "problem", "target_customer", "evidence", "assumptions", "edge_fit", "proposed_solution_shape", "confidence"],
    "Output of the Scout. One real problem with evidence, reachable through the owner's edge; never a business idea without a customer."),

 "VentureProposal": S("VentureProposal", {
    "opportunity_id": str_(), "value_proposition": str_(), "promise": str_("What the customer gets"),
    "call_to_action": str_("What the customer must do to get it"),
    "business_model": {"type": "string", "enum": ["subscription", "one_off", "usage", "service_retainer", "freemium_to_paid"]},
    "price_point_usd": num(), "unit_economics": {"type": "object", "required": ["est_cac_usd", "est_ltv_usd", "gross_margin_pct"], "properties": {
        "est_cac_usd": num(), "est_ltv_usd": num(), "gross_margin_pct": num(), "payback_months": num()}},
    "scorecard": {"type": "object", "description": "Each 1-5", "required": ["demand", "accessibility", "competition", "revenue_potential", "capital_need", "feasibility", "time_to_revenue", "legal_risk", "owner_fit"],
        "properties": {k: {"type": "integer", "minimum": 1, "maximum": 5} for k in
            ["demand", "accessibility", "competition", "revenue_potential", "capital_need", "feasibility", "time_to_revenue", "legal_risk", "owner_fit"]}},
    "weighted_score": num("0-100"), "edge_fit_score": {"type": "number", "minimum": 0, "maximum": 1, "description": "Below policies.min_edge_fit_score → reject"},
    "money_route": str_("The owner's own storefront/payment provider that collects revenue; never AVE"),
    "est_intelligence_cost_cents": int_("Estimated agent-run cost to reach first revenue"),
    "capital_required_cents": int_("To reach first verified revenue"),
    "time_to_first_revenue_days": int_(), "key_risks": arr(str_()), "recommendation": {"type": "string", "enum": ["validate", "park", "reject"]},
    "rationale": str_(), "execution_plan_90d": arr(str_(), "Milestones, not tasks")},
    ["opportunity_id", "value_proposition", "promise", "call_to_action", "business_model", "price_point_usd", "unit_economics", "scorecard", "weighted_score", "edge_fit_score", "money_route", "capital_required_cents", "recommendation", "rationale"],
    "Output of the Strategist. Turns a packet into a decision-grade proposal with a scorecard."),

 "ExperimentSpec": S("ExperimentSpec", {
    "venture_id": str_(), "hypothesis": str_("'We believe <customer> will <action> because <reason>'"),
    "type": {"type": "string", "enum": ["landing_page", "preorder", "paid_pilot", "concierge", "lead_magnet", "outbound_interviews", "price_test", "ad_message_test"]},
    "design": str_("Exactly what is built/shown, to whom, where"),
    "budget_cents": int_(), "duration_days": int_(),
    "success_criteria": {"type": "object", "required": ["metric", "threshold"], "properties": {"metric": str_(), "threshold": num(), "unit": str_()}},
    "stop_conditions": {"type": "object", "required": ["max_spend_cents", "max_days"], "properties": {"max_spend_cents": int_(), "max_days": int_(), "kill_if": str_()}},
    "what_we_learn_if_pass": str_(), "what_we_learn_if_fail": str_()},
    ["venture_id", "hypothesis", "type", "design", "budget_cents", "duration_days", "success_criteria", "stop_conditions"],
    "Output of the Validator before any money moves. Hypothesis, budget, threshold, stop rule."),

 "ExperimentResult": S("ExperimentResult", {
    "experiment_id": str_(), "outcome": {"type": "string", "enum": ["passed", "failed", "inconclusive", "aborted"]},
    "spent_cents": int_(), "observed": {"type": "object", "additionalProperties": num(), "description": "metric → value"},
    "qualitative": arr(str_(), "Verbatim customer quotes, objections"), "surprises": arr(str_()),
    "recommendation": {"type": "string", "enum": ["advance", "iterate", "pivot", "kill"]}, "rationale": str_(), "confidence": conf},
    ["experiment_id", "outcome", "spent_cents", "observed", "recommendation", "rationale", "confidence"],
    "Validator's read-out. Numbers first, then what they mean."),

 "BuildSpec": S("BuildSpec", {
    "venture_id": str_(), "mvp_statement": str_("The smallest thing that delivers the promise"),
    "user_stories": arr(str_(), "Max 7 for an MVP"), "out_of_scope": arr(str_()),
    "stack": arr(str_()), "integrations": arr(str_(), "Payments, auth, email, analytics"),
    "data_model": str_(), "acceptance_tests": arr(str_()), "estimated_build_days": int_(),
    "running_cost_cents_per_month": int_(), "repo": str_("In the owner's GitHub"), "deploy_target": str_("In the owner's hosting account"),
    "assets": arr(asset_item, "Every asset the venture will use; all owner-controlled; registered in venture_assets before hand-off")},
    ["venture_id", "mvp_statement", "user_stories", "out_of_scope", "stack", "acceptance_tests", "estimated_build_days", "assets"],
    "Builder's contract with the Orchestrator. If it is not in the user stories it is not built."),

 "DistributionPlan": S("DistributionPlan", {
    "venture_id": str_(), "audience_segments": arr({"type": "object", "required": ["name", "where", "message"], "properties": {
        "name": str_(), "where": str_("Channel/community/platform"), "message": str_("Hook in their language"), "size_estimate": str_()}}),
    "positioning": str_(), "owner_channels_first": arr(str_(), "The owner's own audience/channels used before any paid reach"),
    "channels": arr({"type": "object", "required": ["channel", "mode", "budget_cents", "kpi", "account"], "properties": {
        "channel": str_(), "mode": {"type": "string", "enum": ["organic", "paid", "outbound", "partner", "creator"]},
        "account": str_("The owner's own account/API used (e.g. owner Meta ad account via Marketing API); never AVE-owned"),
        "budget_cents": int_(), "kpi": str_(), "target": num()}}),
    "funnel": arr(str_(), "Step → conversion target"), "tests_this_week": arr(str_()),
    "total_budget_cents": int_(), "cta_destination": {"type": "string", "enum": ["landing_page", "whatsapp", "call", "checkout", "calendar"]}},
    ["venture_id", "audience_segments", "positioning", "owner_channels_first", "channels", "funnel", "total_budget_cents", "cta_destination"],
    "Distributor's weekly plan. Every channel has a budget and a KPI or it is not on the list."),

 "DecisionRecord": S("DecisionRecord", {
    "venture_id": str_(), "agent": str_(), "stage": str_(),
    "decision": {"type": "string", "enum": ["advance", "iterate", "scale", "maintain", "pause", "kill", "reallocate", "park"]},
    "rationale": str_("One paragraph a non-technical owner understands"),
    "evidence": arr(evidence_item), "money": {"type": "object", "properties": {"spent_cents": int_(), "verified_revenue_cents": int_(), "requested_cents": int_()}},
    "requires_owner": {"type": "boolean"}, "owner_question": str_("If requires_owner: the exact yes/no being asked")},
    ["venture_id", "agent", "stage", "decision", "rationale", "requires_owner"],
    "Written to `decisions` at every stage gate. Immutable."),

 "OwnerReport": S("OwnerReport", {
    "period": str_(), "headline": str_("One sentence: what happened and what it means"),
    "portfolio": {"type": "object", "required": ["available_cents", "spent_cents", "verified_revenue_cents"], "properties": {
        "available_cents": int_(), "spent_cents": int_(), "verified_revenue_cents": int_(), "reserved_cents": int_(),
        "intelligence_cost_cents": int_("Estimated agent-run cost this period (v_cost_of_intelligence)")}},
    "ventures": arr({"type": "object", "required": ["name", "stage", "spent_cents", "revenue_cents", "status_line"], "properties": {
        "name": str_(), "stage": str_(), "spent_cents": int_(), "revenue_cents": int_(), "status_line": str_(), "next": str_()}}),
    "discovered": arr(str_(), "New opportunities worth a sentence each"),
    "decisions_made": arr(str_()), "needs_you": arr(str_(), "Pending approvals, each with amount and why"),
    "recommendation": str_(), "forecast_disclaimer": {"type": "string", "const": "Forecasts are estimates, not guarantees. Only verified revenue is reported as revenue. AVE holds no money and takes no share of venture revenue."}},
    ["period", "headline", "portfolio", "ventures", "decisions_made", "needs_you", "recommendation", "forecast_disclaimer"],
    "Orchestrator's daily/weekly report. Plain language; money first; asks are explicit."),
}

for name, schema in schemas.items():
    (OUT / f"{name}.schema.json").write_text(json.dumps(schema, indent=2) + "\n")
print(f"wrote {len(schemas)} schemas to {OUT}")
