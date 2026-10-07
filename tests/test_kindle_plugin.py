#!/usr/bin/env python3
"""Static contract checks for the KOReader plugin shipped in this route."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "plugin" / "kindleanki.koplugin"


class KindlePluginContractTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (PLUGIN / name).read_text(encoding="utf-8")

    def test_plugin_has_expected_ko_reader_entrypoints(self) -> None:
        self.assertTrue((PLUGIN / "main.lua").is_file())
        self.assertTrue((PLUGIN / "_meta.lua").is_file())
        main = self.read("main.lua")
        self.assertIn('WidgetContainer:extend', main)
        self.assertIn('registerToMainMenu', main)
        self.assertIn('TextViewer:new', main)
        self.assertIn('InputDialog:new', main)

    def test_review_contract_covers_both_card_families(self) -> None:
        main = self.read("main.lua")
        for token in ("short_answer", "choice", "Type answer", "Show back", "Again", "Hard", "Good", "Easy"):
            self.assertIn(token, main)
        self.assertIn('card.mode == "single"', main)
        self.assertIn('card.mode == "multiple"', main)
        self.assertIn("self:show_answer({ [option_index] = true })", main)
        self.assertNotIn("self:show_answer({ option_index })", main)

    def test_ui_uses_the_bundled_simplified_chinese_catalog(self) -> None:
        i18n = self.read("i18n.lua")
        main = self.read("main.lua")
        ai = self.read("ai.lua")
        self.assertIn('locale = "zh_CN"', i18n)
        for token in ("AI 设置", "显示背面", "输入答案", "正确答案：", "正在请求 AI…", "你："):
            self.assertIn(token, i18n)
        self.assertIn('local _ = I18N.t', main)
        self.assertIn('local _ = require("i18n").t', ai)

    def test_ai_is_direct_text_post_with_bounded_history(self) -> None:
        ai = self.read("ai.lua")
        for token in ("socket.http", "ssl.https", 'method = "POST"', "stream = false", "MAX_HISTORY_MESSAGES", "chat/completions"):
            self.assertIn(token, ai)
        self.assertIn("dismissableRunInSubprocess", self.read("main.lua"))
        self.assertNotIn('text = _("Asking AI…"), timeout = 0', self.read("main.lua"))
        self.assertNotIn("HTTPClient:new()", ai)
        self.assertNotIn("voice_server", ai)
        self.assertNotIn("/stt", ai)
        self.assertNotIn("/tts", ai)

    def test_ai_handles_multiturn_shapes_and_kindle_unsafe_symbols(self) -> None:
        ai = self.read("ai.lua")
        for token in ("strip_thinking", "SKIP_CONTENT_TYPES", "choice.text", "payload.response", "kindle_safe_text", "[图标]", "card_context(card, true)"):
            self.assertIn(token, ai)
        self.assertIn("never put it in the visible answer", ai)
        self.assertIn("max_tokens = 4096", ai)
        # Formal product: fixed card-context prefix before history for caching.
        self.assertIn("Formal order for prompt-prefix caching", ai)
        self.assertIn('content = trim(question)', ai)

    def test_ai_transcript_does_not_shadow_translation_function(self) -> None:
        main = self.read("main.lua")
        self.assertNotIn("for _, message in ipairs(self.ai_history", main)
        self.assertIn("for message_index, message in ipairs(history", main)

    def test_ai_conversation_and_question_layouts_handle_long_text(self) -> None:
        main = self.read("main.lua")
        self.assertIn('text = _("Previous page")', main)
        self.assertIn('text = _("Next page")', main)
        self.assertIn('fullscreen = false', main)
        self.assertNotIn('description = self:ai_transcript()', main)
        self.assertIn('saveSetting("keyboard_layout", "zh_CN")', main)

    def test_card_images_sit_below_text_and_rating_choices_are_visible(self) -> None:
        main = self.read("main.lua")
        for token in (
            'require("device").screen',
            "front_images",
            "back_images",
            "card_image_html",
            "IMAGE_MAX_WIDTH_RATIO",
            "IMAGE_MAX_HEIGHT_RATIO",
            'text_format = "html"',
            'file = self.pack._path .. ".kindle-card.html"',
            'local source = media_dir .. "/" .. name',
            'html_wants_field(fields, "front_images")',
            'html_wants_field(fields, "back_images")',
            'card_image_html(card, { "front_images" })',
            'card_image_html(card, { "back_images" })',
            "if include_back then",
            'text-align:center',
            'rating_label("Hard"',
            'rating_label("Easy"',
        ):
            self.assertIn(token, main)
        self.assertNotIn("IMAGE_RIGHT_COLUMN_RATIO", main)
        # KOReader before v2026.07 cannot render HTML in TextViewer.
        for token in (
            "TextViewer.html_text_formats",
            "if not textviewer_renders_html() then",
            "card_text_blocks",
            'card_images_button(card, "front_images")',
            'card_images_button(card, "back_images")',
            'require("ui/widget/imageviewer")',
        ):
            self.assertIn(token, main)
        self.assertNotIn("<td style=", main)
        self.assertEqual(main.count("function KindleAnki:show_answer"), 1)

    def test_ai_request_includes_complete_card_images_and_answer(self) -> None:
        main = self.read("main.lua")
        ai = self.read("ai.lua")
        for token in ("card_image_paths", "image_paths", "front_images", "back_images"):
            self.assertIn(token, main)
        for token in (
            'require("mime")',
            "Card back:",
            "image_url",
            "data:",
            "MAX_IMAGE_BYTES",
            "MAX_IMAGE_TOTAL_BYTES",
        ):
            self.assertIn(token, ai)
        self.assertNotIn("The learner has not revealed the answer", ai)

    def test_existing_ai_history_opens_conversation_before_new_question(self) -> None:
        main = self.read("main.lua")
        self.assertIn('if #(self.ai_history or {}) > 0 then', main)
        self.assertIn('self:show_ai_conversation(card, revealed)', main)
        self.assertIn('self:open_ai_input(card, revealed)', main)
        self.assertIn('getCharPageTopLineNumber', main)
        # Old KOReader has scroll_text_w and no onScrollOrNavigate.
        self.assertIn('viewer.scroll_text_w', main)
        self.assertIn('scroll_viewer_page(viewer, 1)', main)
        self.assertNotIn('viewer:onScrollOrNavigate(1)', main)
        self.assertIn('scrollToRatio(ratio, true)', main)

    def test_pack_key_and_local_override_are_supported(self) -> None:
        store = self.read("store.lua")
        main = self.read("main.lua")
        self.assertIn("/mnt/us/kindle-anki/packs", store)
        self.assertIn("/mnt/us/folo-anki/packs", store)
        self.assertIn("/mnt/us/kindle-anki/ai", store)
        self.assertIn("/mnt/us/folo-anki/ai", store)
        self.assertIn("kindle_anki.lua", store)
        self.assertIn("folo_anki.lua", store)
        self.assertIn("listed_match", store)
        self.assertIn(".import-tmp", store)
        self.assertIn("pack.ai.api_key", store)
        self.assertIn("Import AI settings from computer", main)
        self.assertIn("fetch_ai_settings", main)
        self.assertIn("fetch_ai_settings", store)
        self.assertIn("/ai-settings", store)
        self.assertIn("present(saved.endpoint) and present(saved.api_key)", main)
        self.assertIn("present(pack_ai.endpoint) and present(pack_ai.api_key)", main)
        self.assertIn("cross_source", main)
        self.assertIn("_ai_cross_consent", main)
        self.assertIn("Your local API key will be sent to that server", main)
        self.assertIn("Configure an API key in the pack or Kindle Anki", main)
        self.assertNotIn("Folo Anki Kindle", main)
        self.assertNotIn("Folo Anki Kindle", self.read("i18n.lua"))
        self.assertIn('text = _("Kindle Anki")', main)
        self.assertIn("/mnt/us/kindle-anki/packs", main)
        self.assertIn("kindle_anki.lua", main)
        self.assertIn("folo_anki.lua", main)

    def test_formal_srs_and_session_modes_exist(self) -> None:
        self.assertTrue((PLUGIN / "schedule.lua").is_file())
        store = self.read("store.lua")
        main = self.read("main.lua")
        i18n = self.read("i18n.lua")
        for token in ("build_session", "record_review", "as_extra", "daily_new_for", "set_daily_new"):
            self.assertIn(token, store)
        for token in ("Start studying", "Browse cards", "How many cards per day?", "How many more cards today?"):
            self.assertIn(token, main)
            self.assertIn(token, i18n)
        self.assertNotIn("Study today", main)
        self.assertNotIn("Learn more today", main)
        self.assertIn("start_studying", main)
        self.assertIn("display_deck_name", main)
        self.assertIn('leaf:match("^(第%d+章)")', main)
        self.assertIn("study_title(self.pack, self.deck)", main)
        self.assertNotIn('self.pack.title .. " · " .. self.deck.name', main)
        self.assertIn("Starred cards", main)
        self.assertIn("Retry missed", main)
        self.assertNotIn("Reverse cards", main)
        self.assertNotIn("Filter: all", main)
        self.assertIn("AGAIN_SECONDS", self.read("schedule.lua"))
        self.assertIn("due_at", self.read("schedule.lua"))
        self.assertIn("preview_days", main)
        self.assertIn("每天学多少张", i18n)
        self.assertIn("Import pack", main)
        self.assertIn("Import from computer", main)
        self.assertIn("Open packs", main)
        self.assertIn("Manage packs", main)
        self.assertIn("delete_pack", self.read("store.lua"))
        self.assertIn("sub_item_table", main)
        self.assertIn("import_from_path", self.read("store.lua"))
        self.assertIn("import_from_computer", self.read("store.lua"))
        self.assertIn('http://%s:%d/packs/%d', self.read("store.lua"))
        self.assertIn("list_computer_packs", self.read("store.lua"))
        self.assertIn("导入卡包", i18n)
        self.assertIn("从电脑导入", i18n)

    def test_ai_persistence_clear_and_space_cleanup(self) -> None:
        store = self.read("store.lua")
        main = self.read("main.lua")
        for token in ("/mnt/us/folo-anki/ai", "save_ai_history", "clear_ai_history", "cleanup_ai_space"):
            self.assertIn(token, store)
        self.assertIn("Restart chat", main)
        self.assertIn("Clean AI storage", main)
        self.assertNotIn("Delete message", main)


class BrowserImportContractTests(unittest.TestCase):
    """The Kindle opens a LAN page; the browser converts; the Kindle imports."""

    def setUp(self) -> None:
        self.webserver = (PLUGIN / "webserver.lua").read_text(encoding="utf-8")
        self.main = (PLUGIN / "main.lua").read_text(encoding="utf-8")
        self.store = (PLUGIN / "store.lua").read_text(encoding="utf-8")
        self.i18n = (PLUGIN / "i18n.lua").read_text(encoding="utf-8")

    def test_web_assets_ship_with_the_plugin(self) -> None:
        web = PLUGIN / "web"
        for name in ("index.html", "apkg.js", "convert.js", "app.js"):
            self.assertTrue((web / name).is_file(), name)
        page = (web / "index.html").read_text(encoding="utf-8")
        for token in ("apkg.js", "convert.js", "app.js", ".apkg"):
            self.assertIn(token, page)
        app = (web / "app.js").read_text(encoding="utf-8")
        for token in ("/api/info", "/api/packs", ".apkg"):
            self.assertIn(token, app)
        # The pack conversion itself still carries no credentials; the AI
        # key only ever travels to /api/ai-settings, never into a pack.
        self.assertIn("ai: {}", app)
        self.assertNotIn("XMLHttpRequest", app)
        convert = (web / "convert.js").read_text(encoding="utf-8")
        self.assertNotIn("fetch(", convert)
        self.assertNotIn("XMLHttpRequest", convert)
        apkg = (web / "apkg.js").read_text(encoding="utf-8")
        self.assertIn("DecompressionStream", apkg)

    def test_webserver_binds_home_wifi_port_and_serves_the_page(self) -> None:
        self.assertIn("DEFAULT_PORT = 8767", self.webserver)
        self.assertIn("socket.tcp4", self.webserver)  # IPv4 first for phone browsers
        self.assertIn('bind("*", self.port)', self.webserver)
        self.assertIn("UIManager:scheduleIn", self.webserver)  # non-blocking pump
        # The dialog must never offer the USBNetwork address (192.168.15.x):
        # phones cannot reach it, and usb0 often sorts before wlan0.
        self.assertIn('"192.168.15."', self.webserver)
        self.assertIn('block.name:sub(1, 4) == "wlan"', self.webserver)
        # Phone browsers open several parallel connections; a one-connection
        # server starves them all behind an idle preconnect.
        self.assertIn("MAX_CONNECTIONS = 8", self.webserver)
        self.assertIn("HEAD_TIMEOUT = 15", self.webserver)
        self.assertIn("socket.select(read_set, write_set, 0)", self.webserver)
        self.assertIn("self.upload_conn ~= nil and self.upload_conn ~= conn", self.webserver)
        # luasocket send() returns the LAST byte index sent; resuming with
        # "offset + sent" respliced HTTP headers into script bodies over Wi-Fi.
        self.assertIn("offset = sent + 1", self.webserver)
        self.assertNotIn("offset = offset + sent", self.webserver)
        for token in ("/api/info", "/api/packs", "index.html", "apkg.js", "convert.js", "app.js"):
            self.assertIn(token, self.webserver)

    def test_pack_management_from_the_page_reuses_store_guards(self) -> None:
        self.assertIn('method == "DELETE" and request.path == "/api/packs"', self.webserver)
        self.assertIn("handle_delete_pack", self.webserver)
        # The name must resolve to a pack the store itself lists, and it must
        # be a bare JSON filename; traversal attempts never reach the store.
        self.assertIn("basename(pack._path or \"\") == name", self.webserver)
        self.assertIn('not name:lower():match("%.json$")', self.webserver)
        self.assertIn("on_delete_pack", self.main)
        self.assertIn("store:delete_pack(pack)", self.main)
        app = (PLUGIN / "web" / "app.js").read_text(encoding="utf-8")
        self.assertIn('method: "DELETE"', app)
        self.assertIn("学习进度和 AI 对话会一起删除", app)
        # Field mapping mirrors the desktop converter: every checkbox carries
        # a muted "例如 …" snippet of that field's own first-note content.
        self.assertIn("fieldSample", app)
        self.assertIn("例如 ", app)
        # Mapping is strictly manual: nothing is pre-ticked from detection,
        # and converting refuses until every note type has front and back.
        self.assertNotIn("suggested_front", app)
        self.assertNotIn("suggested_back", app)
        self.assertNotIn("kindLabel", app)
        self.assertIn("incompleteModel", app)
        self.assertIn("每项至少一个", app)

    def test_ai_settings_from_the_page_are_code_gated_and_write_only(self) -> None:
        # Same guard as the computer flow: a 4-digit code, and the key can be
        # written to the Kindle but never read back through the page.
        self.assertIn('request.path == "/api/ai-settings"', self.webserver)
        self.assertIn("ai_code", self.webserver)
        self.assertIn("pairing code mismatch", self.webserver)
        self.assertIn("on_web_ai_settings", self.main)
        self.assertIn("generate_pairing_code", self.main)
        self.assertIn("Pairing code (for AI settings): %s", self.main)
        self.assertIn("AI endpoint must be an http:// or https:// URL", self.main)
        self.assertIn("配对码（网页里保存 AI 设置用）：%s", self.i18n)
        app = (PLUGIN / "web" / "app.js").read_text(encoding="utf-8")
        self.assertIn("/api/ai-settings?code=", app)
        self.assertIn("ai-key", app)
        # A 4-digit code only holds with a lockout and an unpredictable seed.
        self.assertIn("MAX_AI_ATTEMPTS = 5", self.webserver)
        self.assertIn("/dev/urandom", self.main)
        self.assertIn('"Content-Type": "application/json"', app)

    def test_import_page_survives_plugin_instances(self) -> None:
        # KOReader makes a new plugin instance per file browser / book; the
        # running server must be shared and re-attached, not per-instance, or
        # it keeps port 8767 while "Stop now" and fresh callbacks are lost.
        self.assertNotIn("self.webserver", self.main)
        self.assertIn("WebServer.active = server", self.main)
        self.assertIn("self:attach_webserver(WebServer.active)", self.main)
        init = self.main.split("function KindleAnki:init()", 1)[1].split("\nend", 1)[0]
        self.assertIn("attach_webserver", init)

    def test_webserver_never_unpacks_anki_files(self) -> None:
        # Red line: only a finished kindle-anki zip reaches the store; the
        # server refuses .apkg uploads and points them back at the page.
        self.assertIn("import_from_path", self.webserver)
        self.assertIn("%.apkg$", self.webserver)
        self.assertIn("the Kindle only accepts converted .kindle-anki.zip packs", self.webserver)
        self.assertNotIn("collection.anki2", self.webserver)
        self.assertNotIn("unzip", self.webserver)
        self.assertIn("MAX_UPLOAD_BYTES = 512 * 1024 * 1024", self.webserver)

    def test_upload_goes_through_the_store_temp_path(self) -> None:
        self.assertIn("pack_dir", self.store)
        self.assertIn(".upload.kindle-anki.zip", self.main)
        main = self.main
        self.assertIn("open_browser_import", main)
        self.assertIn("Import via browser", main)
        self.assertIn("on_web_import_result", main)
        self.assertIn("Keep it running", main)
        self.assertIn("Stop now", main)
        self.assertIn("The page keeps working until you tap Stop here or quit KOReader.", main)
        self.assertIn('readSetting("web_port", WebServer.DEFAULT_PORT)', main)
        self.assertIn("runWhenOnline", main)

    def test_browser_import_strings_are_translated(self) -> None:
        for token in (
            "手机/电脑导入",
            "在手机或电脑浏览器（同一 Wi-Fi）里打开这个地址：",
            "保持开启",
            "导入网页已关闭。",
            "无法打开导入网页：%s",
        ):
            self.assertIn(token, self.i18n)


if __name__ == "__main__":
    unittest.main()
