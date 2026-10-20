#!/usr/bin/env python3
"""Visual tokens and pure helpers for the Kindle Anki Import window."""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk
import tkinter.font as tkfont


COLORS = {
    "paper": "#E8E6DF",
    "well": "#F3F2EC",
    "ink": "#1A1916",
    "mute": "#4A4944",
    "rule": "#B8B6AE",
    "seal": "#8C2A1E",
    "seal_pressed": "#6F1F16",
    "seal_active": "#A33325",
}

COPY = {
    "window_title": "Kindle Anki 转换",
    "title": "Kindle Anki 转换",
    "tagline": "把 Anki 卡包转成本机文件，不上传。",
    "pick_apkg": "选择 Anki 卡包…",
    "no_apkg": "未选择 .apkg",
    "pack_name": "卡包名称",
    "pack_name_hint": "留空则用牌组名",
    "pick_out": "保存到…",
    "convert": "转换",
    "converting": "转换中",
    "open_folder": "打开保存文件夹",
    "ai_settings": "AI 设置",
    "ai_code_label": "AI 配对码 {code}",
    "ai_remember": "在本机记住（明文）",
    "ai_endpoint": "Endpoint",
    "ai_model": "Model",
    "ai_key": "API Key",
    "ai_prompt": "System prompt",
    "save": "保存",
    "help": "使用说明",
    "copy_ip": "复制 IP",
    "again": "再转一个",
    "copy_error": "复制错误详情",
    "empty_title": "还没有卡包。",
    "empty_body": "选一个 Anki 导出的 .apkg，正面和背面字段会列在这里。",
    "map_hint": "背面不要勾题目，翻面就不会再看到正面。",
    "map_defaults": "已按笔记类型预勾，可改。",
    "front": "正面",
    "back": "背面",
    "kind_short": "简答",
    "kind_choice": "选择",
    "kind_cloze": "填空",
    "kind_unknown": "未识别，按简答导入",
    "unsupported": "有 {n} 种笔记类型无法识别。",
    "field_unnamed": "字段 {n}",
    "sample": "例如 {text}",
    "share_on": "无线导入已开",
    "share_ip_label": "Kindle 填这个 IP",
    "share_keep_line": "端口 {port}。窗口不要关。",
    "share_how": "工具 → Kindle Anki → 从电脑导入。",
    "share_loopback_title": "没有可用的局域网 IP",
    "share_loopback_body": "Kindle 到不了这台电脑。检查 Wi-Fi，或允许传入连接。",
    "status_idle": "选择 .apkg 后会列出字段。",
    "status_inspecting": "正在读取字段…",
    "status_mapped": "已列出字段。勾选正面和背面后点转换。",
    "status_converting": "正在转换 {name}，窗口可拖，不要关。",
    "status_done": "完成，{n} 张卡片。",
    "wrote": "已写入 {name}",
    "need_apkg": "请先选择 .apkg。",
    "need_front": "每个笔记类型至少勾一个正面字段。",
    "drain_fail": "界面更新失败。可复制错误详情。",
    "inspect_fail_title": "打不开这个文件。",
    "inspect_fail_body": "确认是 Anki 导出的 .apkg，不是 .colpkg，也不是只用新格式的备份。",
    "new_format_title": "这个 .apkg 是新版 Anki 格式，转换器读不了。",
    "new_format_body": "在 Anki 里重新导出：选中牌组 → 导出 → 格式选 .apkg → 勾选「支持旧版本 Anki」"
    "（Support older Anki versions）→ 导出，再选新导出的文件。",
    "convert_fail": "转换失败。卡包没改动。",
    "no_cards": "没有可导入的卡片：{total} 张全部跳过（{reasons}）。",
    "share_fail": "无法开启无线导入：{err}",
    "ip_copied": "已复制 IP。",
    "file_dialog_apkg": "选择 Anki .apkg",
    "file_dialog_out": "选择保存位置",
}

_UI_FAMILIES = ("PingFang SC", "Hiragino Sans GB", ".AppleSystemUIFont")
_IP_FAMILIES = ("Menlo", "Courier")


def initial_pack_name(info: object) -> str:
    """Suggested pack name from an inspect report; empty when unknown."""
    if not isinstance(info, dict):
        return ""
    return str(info.get("suggested_title") or "").strip()


def choose_family(available: set[str], candidates: tuple[str, ...], fallback: str) -> str:
    for name in candidates:
        if name in available:
            return name
    return fallback


def ui_font(root: tk.Misc, size: int, *, bold: bool = False) -> tuple:
    available = set(tkfont.families(root))
    fallback = tkfont.nametofont("TkDefaultFont").actual("family")
    name = choose_family(available, _UI_FAMILIES, fallback)
    return (name, size, "bold") if bold else (name, size)


def ip_font(root: tk.Misc, size: int = 22) -> tuple:
    available = set(tkfont.families(root))
    name = choose_family(available, _IP_FAMILIES, "Courier")
    return (name, size)


def apply_style(root: tk.Tk) -> ttk.Style:
    style = ttk.Style(root)
    style.theme_use("clam")
    root.configure(bg=COLORS["paper"])
    body = ui_font(root, 13)
    root.option_add("*Font", "{%s} %d" % (body[0], body[1]))
    style.configure(".", background=COLORS["paper"], foreground=COLORS["ink"], font=body)
    style.configure("TFrame", background=COLORS["paper"])
    style.configure("Well.TFrame", background=COLORS["well"])
    style.configure("TLabel", background=COLORS["paper"], foreground=COLORS["ink"])
    style.configure("Well.TLabel", background=COLORS["well"], foreground=COLORS["ink"])
    style.configure("Mute.TLabel", foreground=COLORS["mute"], font=ui_font(root, 11))
    style.configure(
        "WellMute.TLabel",
        background=COLORS["well"],
        foreground=COLORS["mute"],
        font=ui_font(root, 11),
    )
    style.configure("Title.TLabel", font=ui_font(root, 20))
    style.configure("IP.TLabel", font=ip_font(root, 22), background=COLORS["paper"])
    style.configure(
        "TButton",
        padding=(12, 6),
        background=COLORS["paper"],
        foreground=COLORS["ink"],
        bordercolor=COLORS["rule"],
        lightcolor=COLORS["paper"],
        darkcolor=COLORS["paper"],
        relief="solid",
        borderwidth=1,
        width=0,
        focusthickness=2,
        font=body,
    )
    style.map(
        "TButton",
        background=[
            ("disabled", COLORS["paper"]),
            ("pressed", COLORS["rule"]),
            ("active", COLORS["well"]),
        ],
        foreground=[("disabled", COLORS["mute"])],
        lightcolor=[("disabled", COLORS["paper"]), ("pressed", COLORS["rule"])],
        darkcolor=[("disabled", COLORS["paper"]), ("pressed", COLORS["rule"])],
    )
    style.configure(
        "Seal.TButton",
        background=COLORS["seal"],
        foreground=COLORS["well"],
        bordercolor=COLORS["seal"],
        lightcolor=COLORS["seal"],
        darkcolor=COLORS["seal"],
        padding=(16, 8),
        relief="solid",
        borderwidth=1,
        width=0,
        focusthickness=2,
        font=ui_font(root, 14, bold=True),
    )
    style.map(
        "Seal.TButton",
        background=[
            ("disabled", COLORS["rule"]),
            ("pressed", COLORS["seal_pressed"]),
            ("active", COLORS["seal_active"]),
        ],
        foreground=[
            ("disabled", COLORS["ink"]),
            ("pressed", COLORS["well"]),
            ("active", COLORS["well"]),
        ],
        bordercolor=[
            ("disabled", COLORS["rule"]),
            ("pressed", COLORS["seal_pressed"]),
            ("active", COLORS["seal_active"]),
        ],
        lightcolor=[
            ("disabled", COLORS["rule"]),
            ("pressed", COLORS["seal_pressed"]),
            ("active", COLORS["seal_active"]),
        ],
        darkcolor=[
            ("disabled", COLORS["rule"]),
            ("pressed", COLORS["seal_pressed"]),
            ("active", COLORS["seal_active"]),
        ],
    )
    style.configure(
        "TCheckbutton",
        background=COLORS["well"],
        foreground=COLORS["ink"],
        indicatorbackground=COLORS["well"],
        indicatorforeground=COLORS["ink"],
    )
    style.configure(
        "Vertical.TScrollbar",
        background=COLORS["paper"],
        troughcolor=COLORS["well"],
        bordercolor=COLORS["paper"],
    )
    style.configure(
        "Horizontal.TProgressbar",
        troughcolor=COLORS["rule"],
        background=COLORS["ink"],
        bordercolor=COLORS["paper"],
        lightcolor=COLORS["ink"],
        darkcolor=COLORS["ink"],
    )
    return style


def field_name_text(name: str, index: int) -> str:
    text = (name or "").strip()
    if text:
        return text
    return COPY["field_unnamed"].format(n=index + 1)


def field_sample_text(raw: str, limit: int = 24) -> str:
    text = " ".join(str(raw).split())
    if len(text) > limit:
        text = text[:limit].rstrip()
    return COPY["sample"].format(text=text) if text else ""


def kind_label(kind: str) -> str:
    return {
        "short_answer": COPY["kind_short"],
        "choice": COPY["kind_choice"],
        "cloze": COPY["kind_cloze"],
        "unknown": COPY["kind_unknown"],
    }.get(kind, COPY["kind_unknown"])


SKIP_REASONS = {
    "unsupported_model": "笔记类型不支持",
    "non_primary_template": "非主模板",
    "missing_deck": "缺少牌组",
    "empty_front": "正面为空",
    "empty_back": "背面为空",
    "not_enough_options": "选项不足",
    "unreadable_correct_answer": "无法识别答案",
    "image_occlusion": "图片遮挡卡",
}

# What to change, for the reason that skipped the most cards. Keep in step
# with skipSummary/skipHint in plugin/kindleanki.koplugin/web/app.js.
SKIP_HINTS = {
    "unsupported_model": "认不出笔记类型。给它勾上正面和背面字段再转。",
    "non_primary_template": "每条笔记只导入第一张卡，反向卡会跳过。",
    "missing_deck": "导出文件里找不到卡片所在的牌组。在 Anki 里重新导出整个牌组。",
    "empty_front": "勾选的正面字段既没有文字也没有图片。换一个正面字段再转。",
    "empty_back": "勾选的背面字段既没有文字也没有图片（只有音频也算空）。给背面换一个有内容的字段。",
    "not_enough_options": "选择题读不出两个以上选项。检查选项字段。",
    "unreadable_correct_answer": "选择题的答案读不出来。检查答案字段。",
    "image_occlusion": "Anki 的图片遮挡卡暂不支持。",
}


def skip_summary(reasons: dict) -> str:
    return "，".join(f"{SKIP_REASONS.get(key, key)} {count}" for key, count in reasons.items())


def no_cards_text(report: dict) -> str:
    reasons = dict(report.get("skipped_reasons") or {})
    text = COPY["no_cards"].format(total=report.get("total_cards", 0), reasons=skip_summary(reasons))
    if reasons:
        top = max(reasons, key=lambda key: reasons[key])
        hint = SKIP_HINTS.get(top)
        if hint:
            text += hint
    return text


def mapping_fronts_complete(mapping: dict) -> bool:
    if not mapping:
        return False
    return all(bool((sides or {}).get("front")) for sides in mapping.values())


def share_keep_line(port: int) -> str:
    return COPY["share_keep_line"].format(port=port)


def wheel_steps(event: object) -> int:
    num = getattr(event, "num", None)
    if num == 4:
        return -1
    if num == 5:
        return 1
    delta = int(getattr(event, "delta", 0) or 0)
    if abs(delta) >= 120:
        return -delta // 120
    return -int(delta or 0)
