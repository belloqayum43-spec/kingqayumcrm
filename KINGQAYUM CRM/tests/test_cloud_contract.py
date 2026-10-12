"""Static checks for security-sensitive cloud migration scaffolding."""
import unittest
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/202610110001_shared_workspace.sql").read_text(encoding="utf-8").lower()
FUNCTION = (ROOT / "supabase/functions/workspace-admin/index.ts").read_text(encoding="utf-8")
DB_TEST = (ROOT / "supabase/tests/database_security.test.sql").read_text(encoding="utf-8")


class CloudContractTests(unittest.TestCase):
    def test_workspace_tables_and_rls_are_in_migration(self):
        for table in ("workspaces", "workspace_memberships", "prospects", "interactions", "followups", "message_templates", "clients", "orders", "payments", "workspace_settings"):
            self.assertIn(f"create table public.{table}", MIGRATION)
            self.assertIn(f"alter table public.{table} enable row level security", MIGRATION)

    def test_browser_cannot_write_membership_rows(self):
        self.assertIn("revoke all on public.workspace_memberships from anon,authenticated", MIGRATION)
        self.assertNotIn("create policy membership_member_write", MIGRATION)
        self.assertIn("is_workspace_member(workspace_id)", MIGRATION)

    def test_payment_rpc_is_idempotent_and_serializes_balance(self):
        self.assertIn("create function public.record_payment", MIGRATION)
        self.assertIn("for update", MIGRATION)
        self.assertIn("idempotency key was already used", MIGRATION)
        self.assertIn("paid_total+p_amount>order_price", MIGRATION)
        self.assertIn("pg_advisory_xact_lock", MIGRATION)
        for field in ("order_id", "amount", "date", "method", "note"):
            self.assertIn(f"existing.{field} is distinct from p_", MIGRATION)

    def test_database_security_suite_has_a_matching_pgtap_plan(self):
        plan = re.search(r"select\s+plan\((\d+)\)", DB_TEST, re.IGNORECASE)
        self.assertIsNotNone(plan)
        assertions = re.findall(r"^select\s+(?:is|throws_ok)\(", DB_TEST, re.IGNORECASE | re.MULTILINE)
        self.assertEqual(int(plan.group(1)), len(assertions))
        for table in ("workspaces", "workspace_memberships", "workspace_settings", "prospects",
                      "interactions", "followups", "message_templates", "clients", "orders", "payments"):
            self.assertIn(f"public.{table}", DB_TEST)

    def test_invites_require_authenticated_workspace_admin(self):
        self.assertIn("authClient.auth.getUser()", FUNCTION)
        self.assertIn("['owner', 'admin'].includes(membership.role)", FUNCTION)
        self.assertIn("inviteUserByEmail", FUNCTION)
        self.assertIn("SUPABASE_SERVICE_ROLE_KEY", FUNCTION)
        self.assertIn("The owner role cannot be revoked here.", FUNCTION)


if __name__ == "__main__":
    unittest.main()
