"""Static DM Studio contracts; browser/provider integration remains manual."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "js" / "dm-studio.js").read_text(encoding="utf-8")
APP = (ROOT / "js" / "app.js").read_text(encoding="utf-8")


class DMStudioContractTests(unittest.TestCase):
    def test_offline_generator_covers_requested_message_paths(self):
        for token in ("Cold outreach", "Follow-up", "Reply assistant", "No response",
                      "Requested pricing", "Polite rejection", "generateOffline"):
            self.assertIn(token, SOURCE)

    def test_safe_missing_details_and_rejection_handling_are_present(self):
        for token in ("your business", "design support", "hasStopStatus",
                      "Rejected", "Not interested"):
            self.assertIn(token, SOURCE)

    def test_drafts_are_not_automatically_recorded(self):
        self.assertIn("Record this only if you actually sent", SOURCE)
        self.assertIn("Temporary details are never saved automatically", SOURCE)
        self.assertIn("dm-record", APP)

    def test_provider_contract_handles_failure_modes(self):
        for token in ("createOnlineProvider", "timeoutMs", "rate limit", "invalid response",
                      "Online provider timed out"):
            self.assertIn(token, SOURCE)

    def test_module_avoids_lookbehind_that_can_stop_older_webviews(self):
        self.assertNotIn("(?<=", SOURCE)

    def test_stylesheet_has_no_empty_import(self):
        css = (ROOT / "styles.css").read_text(encoding="utf-8")
        self.assertNotIn("@import url('')", css)

    def test_existing_indexeddb_store_list_is_not_changed_for_dm_studio(self):
        db = (ROOT / "js" / "db.js").read_text(encoding="utf-8")
        self.assertNotIn("dmStudio", db)
        self.assertIn("templates", db)
        self.assertIn("interactions", db)


if __name__ == "__main__":
    unittest.main()
