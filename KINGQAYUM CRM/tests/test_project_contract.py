"""Static contract checks for environments without a browser or JS runtime.

These checks verify project wiring and important guardrails; they do not execute
the browser application or substitute for interactive acceptance tests.
"""
import ast
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ProjectContractTests(unittest.TestCase):
    def test_launcher_is_valid_python(self):
        ast.parse((ROOT / "launch.py").read_text(encoding="utf-8"))

    def test_manifest_assets_exist_locally(self):
        manifest = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
        self.assertEqual(manifest["start_url"], "./index.html")
        for icon in manifest["icons"]:
            self.assertTrue((ROOT / icon["src"].removeprefix("./")).is_file())

    def test_service_worker_precaches_application_modules(self):
        sw = (ROOT / "sw.js").read_text(encoding="utf-8")
        for asset in ("index.html", "styles.css", "js/app.js", "js/db.js", "js/core.js", "js/dm-studio.js"):
            self.assertIn("./" + asset, sw)
            self.assertTrue((ROOT / asset).is_file())
        self.assertIn("kingqayum-crm-v5", sw)

    def test_requested_filters_and_order_edit_are_wired(self):
        app = (ROOT / "js/app.js").read_text(encoding="utf-8")
        for control in ("categoryFilter", "identifiedFrom", "identifiedTo", "sortProspects",
                        "financeClient", "financeFrom", "financeTo", "orderStatusFilter"):
            self.assertIn(control, app)
        self.assertIn("data-action=\"edit-order\"", app)
        self.assertIn("function orderForm(existing={})", app)

    def test_money_and_restore_guardrails_are_present(self):
        app = (ROOT / "js/app.js").read_text(encoding="utf-8")
        self.assertIn("price<paid", app)
        self.assertIn("amt>Math.max(0,+o.price-paid)", app)
        self.assertIn("contains duplicate IDs", app)
        self.assertIn("Replace all local data", app)
        self.assertIn("maps.prospects", app)
        self.assertIn("maps.orders", app)

    def test_runtime_assets_do_not_load_remote_dependencies(self):
        html = (ROOT / "index.html").read_text(encoding="utf-8")
        css = (ROOT / "styles.css").read_text(encoding="utf-8")
        self.assertNotRegex(html, r"(?:src|href)=['\"]https?://")
        self.assertNotRegex(css, r"@import\s+url\(['\"]?https?://")
        self.assertIn("type=\"module\"", html)

    def test_app_module_has_no_duplicate_function_declarations(self):
        import re
        app = (ROOT / "js/app.js").read_text(encoding="utf-8")
        names = re.findall(r"(?:async )?function\s+([A-Za-z_$][\w$]*)", app)
        duplicates = {name for name in names if names.count(name) > 1}
        self.assertFalse(duplicates, f"Duplicate module declarations: {sorted(duplicates)}")


if __name__ == "__main__":
    unittest.main()
