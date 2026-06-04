# KLYCH v2 — Final Architecture Review

**Date:** 2026-05-31  
**Reviewer role:** Lead Architect  
**Scope:** `supabase/v2/*` — pre-production schema review (improve only, no redesign)

---

## 1. Executive summary

The v2 schema is **production-ready as a database foundation** after targeted hardening. The organization model, alert targeting pipeline, invite lifecycle, and reference catalogs are coherent and align with the Flutter migration plan.

This review applied **incremental improvements only**:

- Cross-organization integrity triggers (closes a pre-RLS security gap)
- Lightweight `alert_templates` table for org-specific presets
- Performance indexes on hot query paths
- `device_tokens` FCM readiness (`is_active`, globally unique token)
- Idempotent `seed_org_departments()`
- Documentation clarifications for rank, offline, RLS, and FCM

**Excluded by design (with rationale):** `users.rank`, `offline` user status — see sections 3–4.

**Remaining work before production is not schema:** Flutter v2 cutover (P0 in `migration_plan.md`), Edge Function alert resolution, RLS policies, FCM integration.

---

## 2. Critical issues found

| Severity | Issue | Resolution |
|----------|-------|------------|
| **High (pre-RLS)** | Cross-org FK references possible: user in dept A could be assigned to group in org B; alert could target another org's department | **Fixed** — 5 BEFORE INSERT/UPDATE triggers enforce same-org invariants |
| **Medium** | `seed_org_departments()` not idempotent — re-run duplicates departments | **Fixed** — `ON CONFLICT (organization_id, name) DO NOTHING` |
| **Low** | No critical blockers in FK/index/constraints after review | — |

No table renames, alert redesign, or breaking structural changes were required.

---

## 3. User model — `rank` field

**Decision: Do not add `rank`.**

| Dimension | Purpose | Covers |
|-----------|---------|--------|
| `role` | Authorization + app routing | admin / leader / member |
| `department_id` | Org structure + dept targeting | HQ, Medics, Drivers, … |
| `status` | Operational availability + status targeting | available, on_duty, … |
| `group_members` | Ad-hoc operational teams | Night Team, Rapid Response |

A `rank` field (e.g. sergeant, medic lead) would:

- Overlap semantically with `role` in many units
- Require per-organization rank catalogs or uncontrolled free text
- Not participate in current or planned targeting dimensions

**Alternative:** `display_name` for informal titles; `organizations.settings` JSONB for org-specific rank labels if needed later without schema migration.

---

## 4. User statuses — `offline`

**Decision: Do not add `offline` to `user_statuses`.**

| Concept | Mechanism | Used for |
|---------|-----------|----------|
| Operational availability | `users.status` (5 codes) | Alert targeting, leader dashboards |
| Device presence | `users.last_activity_at` (+ future FCM heartbeat) | Delivery optimization, UI indicators |

Adding `offline` would conflate **user-declared availability** with **automatic connectivity state**, causing targeting ambiguity (e.g. deployed but offline vs on_duty but offline). A future `user_presence` table or Edge Function–derived field is cleaner if presence-based targeting is needed.

---

## 5. Alert system readiness

| Target type | Schema support | Resolution path |
|-------------|----------------|-----------------|
| Organization | `alert_targets.target_type = 'organization'` | All active users in org |
| Department | `department_id` + CHECK | Users with matching `department_id` |
| Group | `group_id` + CHECK | `group_members` join |
| Status | `status_code` + CHECK | Users with matching `status` |
| Explicit users | `alert_target_users` | Direct user list |

Multiple `alert_targets` per alert = **union** semantics. Cross-org refs blocked by triggers. Indexes added for status and department resolution paths.

**Not in schema (by design):** recipient resolution Edge Function, receipt pre-population on send — documented in `migration_plan.md`.

---

## 6. Alert templates

**Decision: Add `alert_templates` (org-scoped, lightweight).**

- Unique `(organization_id, name)` per org
- `level` + `message` presets (RED ALERT, Evacuation, etc.)
- Optional `default_target_type` + default refs for compose-time hints
- Does **not** auto-send; app copies into `alerts` + `alert_targets` on send
- Example INSERTs documented in `seed.sql` (not global seed — templates are org-specific)

---

## 7. RLS readiness

**Verdict: Ready for phased RLS rollout.**

| Pattern | Tables |
|---------|--------|
| Direct `organization_id = current_setting(...)` | `organizations`, `departments`, `users`, `invites`, `operational_groups`, `alerts`, `alert_templates`, `audit_log` |
| EXISTS via parent | `alert_targets`, `alert_target_users`, `alert_receipts`, `group_members`, `invite_redemptions`, `device_tokens` |

Global catalogs (`user_statuses`, `department_templates`) — read-only for all authenticated users.

RLS remains **disabled** in bootstrap schema; enabling without policies would block all access.

---

## 8. Push notification readiness

**Verdict: Ready for FCM integration.**

| Requirement | Schema support |
|-------------|----------------|
| Multi-device per user | `(user_id, token)` unique |
| Token reassignment (device handoff) | `token` globally unique |
| Soft deactivation | `is_active` boolean |
| Edge Function lookup | Index on `user_id WHERE is_active` |
| Delivery tracking | `alert_receipts.delivered_at` |
| Org-scoped dispatch | Join `device_tokens` → `users.organization_id` |

---

## 9. Organization model growth

| Future need | Supported without redesign |
|-------------|---------------------------|
| Multiple departments | ✓ `departments` (unlimited per org) |
| Multiple leaders | ✓ `users.role = 'leader'` (many per org) |
| Operational groups | ✓ `operational_groups` + `group_members` |
| Status-based targeting | ✓ `alert_targets.status_code` |
| Archived departments | ✓ `departments.is_archived` |
| Org settings extensibility | ✓ `organizations.settings` JSONB |

---

## 10. Recommended improvements (applied)

1. Cross-org integrity triggers (5)
2. `alert_templates` table + org-scoped indexes
3. Indexes: `users(organization_id, department_id)`, `alert_targets(status_code)`, `alert_receipts(user_id, created_at DESC)`
4. `device_tokens.is_active` + global `token` uniqueness
5. Idempotent `seed_org_departments()`
6. Column/table COMMENTs for status vs presence, role vs rank
7. Updated verification, diagram, and seed documentation

---

## 11. Files modified

| File | Changes |
|------|---------|
| `supabase/v2/schema.sql` | Templates, triggers, indexes, device_tokens, comments |
| `supabase/v2/seed.sql` | Offline/rank notes, template examples |
| `supabase/v2/verification.sql` | 16-table check, trigger verification |
| `supabase/v2/schema_diagram.md` | Templates, integrity, RLS, rank/offline docs |
| `supabase/v2/architecture_review.md` | This document |

---

## 12. SQL diff summary

```sql
-- New table
CREATE TABLE alert_templates (...);  -- org-scoped presets

-- New triggers
assert_user_department_same_org()
assert_group_member_same_org()
assert_alert_target_same_org()
assert_alert_target_user_same_org()
assert_alert_template_refs_same_org()

-- New indexes
users_org_dept_idx
alert_targets_status_idx
alert_receipts_user_created_idx
alert_templates_org_idx, alert_templates_org_active_idx
device_tokens_active_idx

-- device_tokens changes
+ is_active boolean DEFAULT true
+ CONSTRAINT device_tokens_token_unique UNIQUE (token)

-- seed_org_departments()
+ ON CONFLICT (organization_id, name) DO NOTHING
```

---

## 13. Production readiness score

| Area | Score | Notes |
|------|-------|-------|
| Schema integrity | 95 | Triggers close cross-org gap |
| Index coverage | 90 | Hot paths covered; tune post-load |
| Org model | 92 | Scales to multi-dept/leader/group |
| Alert pipeline | 88 | Schema ready; Edge Function pending |
| RLS readiness | 85 | Clean patterns; policies not written |
| FCM readiness | 85 | Schema ready; Flutter/Edge pending |
| Flutter alignment | 70 | P0 migration not yet applied |

### **Overall: 87 / 100**

---

## 14. Go / No-Go recommendation

### **GO** — for database deployment (fresh Supabase project)

Deploy order:

1. `schema.sql`
2. `seed.sql`
3. `verification.sql`

### **Conditional GO** — for end-user production

Complete before general release:

1. Flutter v2 cutover (`migration_plan.md` P0–P1)
2. Alert targeting Edge Function + receipt creation
3. RLS policy migration (before multi-tenant production exposure)
4. FCM token registration + push dispatch

The schema is a solid long-term foundation. Remaining gaps are integration layers, not structural design flaws.
