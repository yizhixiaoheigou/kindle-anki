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


if __name__ == "__main__":
    unittest.main()
