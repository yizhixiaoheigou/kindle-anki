#!/usr/bin/env python3
"""Desktop converter for Kindle Anki packs. Double-click the macOS .app."""

from __future__ import annotations

from pathlib import Path
import json
import queue
import random
import sys
import threading
import traceback
import webbrowser

from kindle_import_ui import (
    COLORS,
    COPY,
    apply_style,
    field_name_text,
    field_sample_text,
    initial_pack_name,
    kind_label,
    mapping_fronts_complete,
    share_keep_line,
    wheel_steps,
)


def repo_root() -> Path:
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            return Path(meipass)
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


ROOT = repo_root()
sys.path.insert(0, str(ROOT / "tools"))

from kindle_anki_importer import import_apkg, inspect_apkg  # noqa: E402
from kindle_bundle import write_kindle_bundle  # noqa: E402
from kindle_pack_server import PACK_PORT, is_lan_ip, lan_ip, start_pack_server  # noqa: E402

try:
    import tkinter as tk
    from tkinter import filedialog, ttk
except ImportError as exc:  # pragma: no cover - host without Tk
    raise SystemExit(
        "This converter needs Tkinter. On macOS use the packaged .app."
    ) from exc


def _hairline(parent: tk.Misc) -> tk.Frame:
    line = tk.Frame(parent, height=1, bg=COLORS["rule"], highlightthickness=0, bd=0)
    return line


class ConverterApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(COPY["window_title"])
        self.geometry("760x680")
        self.minsize(700, 600)
        apply_style(self)
        self.apkg_path: Path | None = None
        self.output_dir = Path.home() / "Desktop"
        self.ai_code = f"{random.randint(0, 9999):04d}"
        self.ai_config = self._load_ai_config()
        self.inspect = None
        self.pack_httpd = None
        self.pack_holder: dict | None = None
        self.field_vars: dict[str, dict[str, list[tk.BooleanVar]]] = {}
        self._busy = False
        self._alive = True
        self._ui_queue: queue.Queue = queue.Queue()
        self._last_traceback = ""
        self._well_window_id = None
        self._mapping_widgets: list[tk.Misc] = []
        self._build()
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self._bind_keys()
        self._bind_wheel()
        self._drain_job = self.after(50, self._drain)
        self.start_share()

    def _build(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        masthead = ttk.Frame(self)
        masthead.grid(row=0, column=0, sticky="ew", padx=20, pady=(20, 8))
        masthead.columnconfigure(0, weight=1)
        ttk.Label(masthead, text=COPY["title"], style="Title.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(masthead, text=COPY["tagline"], style="Mute.TLabel").grid(row=1, column=0, sticky="w")
        self.help_btn = ttk.Button(masthead, text=COPY["help"], command=self.open_guide)
        self.help_btn.grid(row=0, column=1, rowspan=2, sticky="e")

        source = ttk.Frame(self)
        source.grid(row=1, column=0, sticky="ew", padx=20, pady=(0, 8))
        source.columnconfigure(1, weight=1)
        ttk.Button(source, text=COPY["pick_apkg"], command=self.pick_apkg).grid(row=0, column=0, sticky="w")
        self.apkg_var = tk.StringVar(value=COPY["no_apkg"])
        ttk.Label(source, textvariable=self.apkg_var).grid(row=0, column=1, sticky="w", padx=8)
        ttk.Label(source, text=COPY["pack_name"]).grid(row=1, column=0, sticky="w", pady=(8, 0))
        self.name_var = tk.StringVar(value="")
        self.name_entry = ttk.Entry(source, textvariable=self.name_var)
        self.name_entry.grid(row=1, column=1, sticky="ew", padx=8, pady=(8, 0))
        ttk.Button(source, text=COPY["pick_out"], command=self.pick_output).grid(row=2, column=0, sticky="w", pady=(8, 0))
        self.out_var = tk.StringVar(value=str(self.output_dir))
        ttk.Label(source, textvariable=self.out_var, style="Mute.TLabel").grid(
            row=2, column=1, sticky="ew", padx=8, pady=(8, 0)
        )
        self.map_hint = ttk.Label(source, text=COPY["pack_name_hint"], style="Mute.TLabel")
        self.map_hint.grid(row=3, column=0, columnspan=2, sticky="w", pady=(8, 0))

        well_host = ttk.Frame(self, style="Well.TFrame")
        well_host.grid(row=2, column=0, sticky="nsew", padx=20)
        well_host.columnconfigure(0, weight=1)
        well_host.rowconfigure(1, weight=1)
        _hairline(well_host).grid(row=0, column=0, columnspan=2, sticky="ew")
        self._canvas = tk.Canvas(
            well_host, bg=COLORS["well"], highlightthickness=0, bd=0
        )
        scroll = ttk.Scrollbar(well_host, orient="vertical", command=self._canvas.yview)
        self.mapping_host = ttk.Frame(self._canvas, style="Well.TFrame")
        self.mapping_host.bind(
            "<Configure>",
            lambda e: self._canvas.configure(scrollregion=self._canvas.bbox("all")),
        )
        self._well_window_id = self._canvas.create_window((0, 0), window=self.mapping_host, anchor="nw")
        self._canvas.configure(yscrollcommand=scroll.set)
        self._canvas.grid(row=1, column=0, sticky="nsew")
        scroll.grid(row=1, column=1, sticky="ns")
        self._canvas.bind("<Configure>", self._on_canvas_width)

        dock = ttk.Frame(self)
        dock.grid(row=3, column=0, sticky="ew", padx=20, pady=(0, 20))
        dock.columnconfigure(0, weight=1)
        _hairline(dock).grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 12))
        left = ttk.Frame(dock)
        left.grid(row=1, column=0, sticky="nw")
        right = ttk.Frame(dock)
        right.grid(row=1, column=1, sticky="ne")
        right.configure(width=260)
        right.grid_propagate(False)

        actions = ttk.Frame(left)
        actions.pack(anchor="w")
        self.convert_btn = ttk.Button(actions, text=COPY["convert"], command=self.convert)
        self.convert_btn.pack(side="left")
        self.again_btn = ttk.Button(actions, text=COPY["again"], command=self.reset_well)
        self.open_btn = ttk.Button(actions, text=COPY["open_folder"], command=self.open_output)
        self.open_btn.pack(side="left", padx=(8, 0))
        self.ai_btn = ttk.Button(actions, text=COPY["ai_settings"], command=self.open_ai_settings_dialog)
        self.ai_btn.pack(side="left", padx=(8, 0))
        self.copy_error_btn = ttk.Button(actions, text=COPY["copy_error"], command=self.copy_error)
        self.progress = ttk.Progressbar(left, mode="indeterminate")
        self.status = tk.StringVar(value=COPY["status_idle"])
        ttk.Label(left, textvariable=self.status, wraplength=400).pack(anchor="w", pady=(8, 0))
        self.wrote_var = tk.StringVar(value="")
        ttk.Label(left, textvariable=self.wrote_var, style="Mute.TLabel").pack(anchor="w")

        self.share_tick = tk.Frame(right, width=8, height=8, bg=COLORS["ink"], highlightthickness=0, bd=0)
        self.share_headline = ttk.Label(right, text="")
        self.share_headline.pack(anchor="e")
        self.ai_code_label = ttk.Label(
            right, text=COPY["ai_code_label"].format(code=self.ai_code), style="Mute.TLabel"
        )
        self.ai_code_label.pack(anchor="e")
        self.share_ip_label = ttk.Label(right, text=COPY["share_ip_label"], style="Mute.TLabel")
        self.share_ip_var = tk.StringVar(value="")
        self.share_ip = ttk.Label(right, textvariable=self.share_ip_var, style="IP.TLabel")
        self.share_how = ttk.Label(right, text=COPY["share_how"], style="Mute.TLabel")
        self.share_keep = ttk.Label(right, text=share_keep_line(PACK_PORT), style="Mute.TLabel")
        self.share_body = ttk.Label(right, text="", style="Mute.TLabel", wraplength=240)
        self.copy_ip_btn = ttk.Button(right, text=COPY["copy_ip"], command=self.copy_ip)

        self._show_empty_well()
        self._set_convert_enabled(False)

    def _on_canvas_width(self, event: tk.Event) -> None:
        if self._well_window_id is not None:
            self._canvas.itemconfigure(self._well_window_id, width=event.width)

    def _set_convert_enabled(self, enabled: bool) -> None:
        if enabled:
            self.convert_btn.configure(state=["!disabled"], style="Seal.TButton", text=COPY["convert"])
        else:
            self.convert_btn.configure(state=["disabled"], style="TButton", text=COPY["convert"])

    def _set_status(self, text: str) -> None:
        self.status.set(text)

    def _set_busy(self, busy: bool, label: str | None = None) -> None:
        self._busy = busy
        state = ["disabled"] if busy else ["!disabled"]
        for widget in self._mapping_widgets:
            try:
                widget.configure(state=state)
            except tk.TclError:
                pass
        mapped = bool(self.field_vars)
        if busy:
            self.convert_btn.configure(state=["disabled"], style="TButton", text=label or COPY["converting"])
            self.progress.pack(anchor="w", fill="x", pady=(8, 0))
            self.progress.start(12)
            self.open_btn.configure(state=["disabled"])
            self.again_btn.configure(state=["disabled"])
        else:
            self.progress.stop()
            self.progress.pack_forget()
            self.open_btn.configure(state=["!disabled"])
            self._set_convert_enabled(mapped)
            if mapped:
                if not self.again_btn.winfo_ismapped():
                    pass
            self.convert_btn.configure(text=COPY["convert"])

    def _show_empty_well(self) -> None:
        for child in self.mapping_host.winfo_children():
            child.destroy()
        self._mapping_widgets = []
        ttk.Label(self.mapping_host, text=COPY["empty_title"], style="Well.TLabel").pack(
            anchor="w", padx=16, pady=(24, 4)
        )
        ttk.Label(self.mapping_host, text=COPY["empty_body"], style="WellMute.TLabel", wraplength=640).pack(
            anchor="w", padx=16
        )
        self.map_hint.configure(text="")

    def _show_inspect_error(self, detail: str) -> None:
        for child in self.mapping_host.winfo_children():
            child.destroy()
        self._mapping_widgets = []
        ttk.Label(self.mapping_host, text=COPY["inspect_fail_title"], style="Well.TLabel").pack(
            anchor="w", padx=16, pady=(24, 4)
        )
        ttk.Label(self.mapping_host, text=COPY["inspect_fail_body"], style="WellMute.TLabel", wraplength=640).pack(
            anchor="w", padx=16
        )
        if detail:
            ttk.Label(self.mapping_host, text=detail, style="WellMute.TLabel", wraplength=640).pack(
                anchor="w", padx=16, pady=(8, 0)
            )

    def render_mapping(self) -> None:
        for child in self.mapping_host.winfo_children():
            child.destroy()
        self.field_vars = {}
        self._mapping_widgets = []
        if not self.inspect:
            self._show_empty_well()
            return
        self.map_hint.configure(text=COPY["map_hint"] + " " + COPY["map_defaults"])
        models = self.inspect.get("models") or []
        for model in models:
            box = ttk.Frame(self.mapping_host, style="Well.TFrame")
            box.pack(fill="x", padx=16, pady=10)
            box.columnconfigure(0, weight=1)
            box.columnconfigure(1, weight=1)
            header = ttk.Frame(box, style="Well.TFrame")
            header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 6))
            ttk.Label(header, text=str(model.get("name", "")), style="Well.TLabel").pack(side="left")
            ttk.Label(header, text="  " + kind_label(str(model.get("kind") or "unknown")), style="WellMute.TLabel").pack(
                side="left"
            )
            tk.Frame(box, height=1, bg=COLORS["rule"], highlightthickness=0, bd=0).grid(
                row=1, column=0, columnspan=2, sticky="ew", pady=(0, 6)
            )
            ttk.Label(box, text=COPY["front"], style="WellMute.TLabel").grid(row=2, column=0, sticky="w")
            ttk.Label(box, text=COPY["back"], style="WellMute.TLabel").grid(row=2, column=1, sticky="w")
            mid = str(model["id"])
            self.field_vars[mid] = {"front": [], "back": []}
            fields = model.get("fields") or []
            sample = model.get("sample") or []
            suggested_front = set(model.get("suggested_front") or [])
            suggested_back = set(model.get("suggested_back") or [])
            for index, name in enumerate(fields):
                for col, side, suggested in ((0, "front", suggested_front), (1, "back", suggested_back)):
                    var = tk.BooleanVar(value=index in suggested)
                    self.field_vars[mid][side].append(var)
                    cell = ttk.Frame(box, style="Well.TFrame")
                    cell.grid(row=3 + index, column=col, sticky="ew", pady=2, padx=(0, 12))
                    cb = ttk.Checkbutton(cell, text="", variable=var, takefocus=1)
                    cb.grid(row=0, column=0, sticky="nw")
                    label = ttk.Label(cell, text=field_name_text(str(name), index), style="Well.TLabel")
                    label.grid(row=0, column=1, sticky="w")
                    label.bind("<Button-1>", lambda e, v=var: v.set(not v.get()))
                    sample_text = field_sample_text(sample[index] if index < len(sample) else "")
                    if sample_text:
                        ttk.Label(cell, text=sample_text, style="WellMute.TLabel").grid(
                            row=1, column=1, sticky="w"
                        )
                    self._mapping_widgets.append(cb)
                    cell.bind(
                        "<Configure>",
                        lambda e, lab=label: lab.configure(wraplength=max(80, e.width - 28)),
                    )
        unsupported = self.inspect.get("unsupported_models") or []
        if unsupported:
            ttk.Label(
                self.mapping_host,
                text=COPY["unsupported"].format(n=len(unsupported)),
                style="WellMute.TLabel",
            ).pack(anchor="w", padx=16, pady=(0, 16))

    def collect_mapping(self) -> dict:
        mapping = {}
        for mid, sides in self.field_vars.items():
            mapping[mid] = {
                "front": [index for index, var in enumerate(sides["front"]) if var.get()],
                "back": [index for index, var in enumerate(sides["back"]) if var.get()],
            }
        return mapping

    def _drain(self) -> None:
        if not self._alive:
            return
        try:
            while True:
                job = self._ui_queue.get_nowait()
                if not self._alive:
                    continue
                try:
                    job()
                except Exception:
                    self._last_traceback = traceback.format_exc()
                    if self._alive:
                        self._set_status(COPY["drain_fail"])
        except queue.Empty:
            pass
        except Exception:
            self._last_traceback = traceback.format_exc()
        if self._alive:
            self._drain_job = self.after(50, self._drain)

    def _on_well_wheel(self, event: tk.Event) -> str:
        steps = wheel_steps(event)
        if steps:
            self._canvas.yview_scroll(steps, "units")
        return "break"

    def _bind_wheel(self) -> None:
        self._canvas.bind_all("<MouseWheel>", self._on_well_wheel)
        self._canvas.bind_all("<Button-4>", self._on_well_wheel)
        self._canvas.bind_all("<Button-5>", self._on_well_wheel)

    def _unbind_wheel(self) -> None:
        self._canvas.unbind_all("<MouseWheel>")
        self._canvas.unbind_all("<Button-4>")
        self._canvas.unbind_all("<Button-5>")

    def _with_dialog(self, fn):
        self._unbind_wheel()
        try:
            return fn()
        finally:
            if self._alive:
                self._bind_wheel()

    def _bind_keys(self) -> None:
        self.bind("<Command-o>", lambda e: self.pick_apkg())
        self.bind("<Command-O>", lambda e: self.pick_apkg())
        self.bind("<Command-Shift-S>", lambda e: self.pick_output())
        self.bind("<Command-Return>", lambda e: self.convert())
        self.bind("<Return>", lambda e: None if self.focus_get() is getattr(self, "name_entry", None) else self.convert())
        self.bind("<Command-l>", lambda e: self.copy_ip())
        self.bind("<Command-L>", lambda e: self.copy_ip())
        self.bind("<Command-slash>", lambda e: self.open_guide())
        self.bind("<F1>", lambda e: self.open_guide())

    def _on_close(self) -> None:
        self._alive = False
        self._unbind_wheel()
        job = getattr(self, "_drain_job", None)
        if job is not None:
            try:
                self.after_cancel(job)
            except tk.TclError:
                pass
        self.destroy()

    def pick_apkg(self) -> None:
        if self._busy or not self._alive:
            return
        path = self._with_dialog(
            lambda: filedialog.askopenfilename(
                title=COPY["file_dialog_apkg"],
                filetypes=[("Anki package", "*.apkg"), ("All files", "*.*")],
            )
        )
        if not path:
            return
        self.apkg_path = Path(path)
        self.apkg_var.set(self.apkg_path.name)
        self._set_status(COPY["status_inspecting"])
        self._busy = True
        self._set_convert_enabled(False)
        apkg = self.apkg_path
        threading.Thread(target=self._inspect_worker, args=(apkg,), daemon=True).start()

    def _inspect_worker(self, apkg: Path) -> None:
        try:
            info = inspect_apkg(apkg)
        except Exception as exc:  # noqa: BLE001
            tb = traceback.format_exc()
            self._ui_queue.put(lambda exc=exc, tb=tb: self._on_inspect_fail(exc, tb))
            return
        self._ui_queue.put(lambda info=info: self._on_inspect_ok(info))

    def _on_inspect_ok(self, info: dict) -> None:
        if not self._alive:
            return
        self._busy = False
        self.inspect = info
        self.name_var.set(initial_pack_name(info))
        self.render_mapping()
        self._set_convert_enabled(True)
        self.again_btn.pack_forget()
        self.copy_error_btn.pack_forget()
        self.wrote_var.set("")
        self._set_status(COPY["status_mapped"])

    def _on_inspect_fail(self, exc: Exception, tb: str) -> None:
        if not self._alive:
            return
        self._busy = False
        self.inspect = None
        self.field_vars = {}
        self.name_var.set("")
        self._last_traceback = tb
        self._set_convert_enabled(False)
        self._show_inspect_error(str(exc))
        self._set_status(COPY["inspect_fail_title"])

    def pick_output(self) -> None:
        if self._busy or not self._alive:
            return
        path = self._with_dialog(
            lambda: filedialog.askdirectory(
                title=COPY["file_dialog_out"], initialdir=str(self.output_dir)
            )
        )
        if not path:
            return
        self.output_dir = Path(path)
        self.out_var.set(str(self.output_dir))
        self.start_share()

    def convert(self) -> None:
        if self._busy or not self._alive:
            return
        if not self.apkg_path:
            self._set_status(COPY["need_apkg"])
            return
        mapping = self.collect_mapping()
        if not mapping_fronts_complete(mapping):
            self._set_status(COPY["need_front"])
            return
        apkg, out = self.apkg_path, self.output_dir
        pack_name = self.name_var.get().strip()
        self._set_busy(True, label=COPY["converting"])
        self._set_status(COPY["status_converting"].format(name=apkg.name))
        threading.Thread(
            target=self._convert_worker, args=(apkg, out, mapping, pack_name), daemon=True
        ).start()

    def _convert_worker(self, apkg: Path, out: Path, mapping: dict, pack_name: str) -> None:
        try:
            package = import_apkg(apkg, None, mapping, title=pack_name or None)
            result = write_kindle_bundle(package, apkg, out)
        except Exception as exc:  # noqa: BLE001
            tb = traceback.format_exc()
            self._ui_queue.put(lambda exc=exc, tb=tb: self._on_convert_fail(exc, tb))
            return
        self._ui_queue.put(lambda: self._on_convert_ok(package, result))

    def _on_convert_ok(self, package: dict, result: dict) -> None:
        if not self._alive:
            return
        self._set_busy(False)
        cards = len(package.get("cards", []))
        self._set_status(COPY["status_done"].format(n=cards))
        self.wrote_var.set(COPY["wrote"].format(name=result["zip"].name))
        if not self.again_btn.winfo_ismapped():
            self.again_btn.pack(side="left", padx=(8, 0), after=self.convert_btn)
        self.copy_error_btn.pack_forget()
        self.start_share()

    def _on_convert_fail(self, exc: Exception, tb: str) -> None:
        if not self._alive:
            return
        self._set_busy(False)
        self._last_traceback = tb
        self._set_status(COPY["convert_fail"])
        self.wrote_var.set(str(exc))
        if not self.copy_error_btn.winfo_ismapped():
            self.copy_error_btn.pack(side="left", padx=(8, 0), after=self.convert_btn)

    def reset_well(self) -> None:
        if self._busy or not self._alive:
            return
        self.apkg_path = None
        self.inspect = None
        self.field_vars = {}
        self.apkg_var.set(COPY["no_apkg"])
        self.name_var.set("")
        self.wrote_var.set("")
        self.again_btn.pack_forget()
        self.copy_error_btn.pack_forget()
        self._show_empty_well()
        self._set_convert_enabled(False)
        self._set_status(COPY["status_idle"])

    def copy_error(self) -> None:
        text = self._last_traceback or self.wrote_var.get()
        if not text:
            return
        self.clipboard_clear()
        self.clipboard_append(text)
        self.update_idletasks()

    def copy_ip(self) -> None:
        ip = lan_ip()
        if not ip:
            return
        self.clipboard_clear()
        self.clipboard_append(ip)
        self.update_idletasks()
        self._set_status(COPY["ip_copied"])

    def start_share(self) -> None:
        self.output_dir.mkdir(parents=True, exist_ok=True)
        if self.pack_httpd is None:
            try:
                self.pack_httpd, self.pack_holder = start_pack_server(self.output_dir)
                self.pack_holder["ai_code"] = self.ai_code
                self.pack_holder["ai_config"] = self.ai_config or None
                threading.Thread(target=self.pack_httpd.serve_forever, daemon=True).start()
            except OSError as exc:
                self.pack_httpd = None
                self.pack_holder = None
                self._render_share_error(COPY["share_fail"].format(err=exc))
                return
        if self.pack_holder is not None:
            self.pack_holder["root"] = self.output_dir
        ip = lan_ip()
        if is_lan_ip(ip):
            self._render_share_lan(ip)
        else:
            self._render_share_loopback(ip)

    def _clear_share(self) -> None:
        self.share_tick.pack_forget()
        self.share_ip_label.pack_forget()
        self.share_ip.pack_forget()
        self.share_how.pack_forget()
        self.share_keep.pack_forget()
        self.share_body.pack_forget()
        self.copy_ip_btn.pack_forget()

    def _render_share_error(self, text: str) -> None:
        self._clear_share()
        self.share_headline.configure(text=text)
        self.share_body.configure(text="")
        self.share_body.pack(anchor="e")

    def _render_share_lan(self, ip: str) -> None:
        self._clear_share()
        self.share_tick.pack(anchor="e", pady=(0, 4))
        self.share_headline.configure(text=COPY["share_on"])
        self.share_ip_label.pack(anchor="e")
        self.share_ip_var.set(ip)
        self.share_ip.pack(anchor="e")
        self.share_how.pack(anchor="e")
        self.share_keep.configure(text=share_keep_line(PACK_PORT))
        self.share_keep.pack(anchor="e")
        self.copy_ip_btn.pack(anchor="e", pady=(8, 0))

    def _render_share_loopback(self, ip: str) -> None:
        self._clear_share()
        self.share_headline.configure(text=COPY["share_loopback_title"])
        self.share_ip_var.set(ip or "127.0.0.1")
        self.share_ip.pack(anchor="e")
        self.share_body.configure(text=COPY["share_loopback_body"])
        self.share_body.pack(anchor="e")

    def open_output(self) -> None:
        path = self.output_dir if self.output_dir.is_dir() else Path.home()
        webbrowser.open(path.as_uri())

    def open_guide(self) -> None:
        guide = repo_root() / "docs" / "USER_GUIDE.zh_CN.md"
        if not guide.is_file():
            guide = repo_root() / "docs" / "USER_GUIDE.md"
        webbrowser.open(guide.as_uri())

    def _ai_config_path(self) -> Path:
        return Path.home() / ".kindle-anki" / "ai-settings.json"

    def _load_ai_config(self) -> dict:
        try:
            data = json.loads(self._ai_config_path().read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def open_ai_settings_dialog(self) -> None:
        window = tk.Toplevel(self)
        window.title(COPY["ai_settings"])
        window.configure(bg=COLORS["paper"])
        window.transient(self)
        fields = (
            ("ai_endpoint", "endpoint"),
            ("ai_model", "model"),
            ("ai_key", "api_key"),
            ("ai_prompt", "system_prompt"),
        )
        values = {key: tk.StringVar(value=str(self.ai_config.get(key, ""))) for key, _ in fields}
        for row, (key, label) in enumerate(fields):
            ttk.Label(window, text=COPY[key]).grid(row=row, column=0, sticky="w", padx=16, pady=(10, 0))
            entry = ttk.Entry(window, textvariable=values[key], width=52)
            if key == "ai_key":
                entry.configure(show="•")
            entry.grid(row=row, column=1, sticky="ew", padx=(8, 16), pady=(10, 0))
        remember = tk.BooleanVar(value=self._ai_config_path().is_file())
        ttk.Checkbutton(window, text=COPY["ai_remember"], variable=remember).grid(
            row=len(fields), column=0, columnspan=2, sticky="w", padx=16, pady=(10, 0)
        )
        window.columnconfigure(1, weight=1)

        def save() -> None:
            config = {key: values[key].get().strip() for key, _ in fields}
            self.ai_config = config
            if self.pack_holder is not None:
                self.pack_holder["ai_config"] = config
                self.pack_holder["ai_code"] = self.ai_code
            if remember.get():
                path = self._ai_config_path()
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
            else:
                try:
                    self._ai_config_path().unlink()
                except FileNotFoundError:
                    pass
            self.ai_code_label.configure(text=COPY["ai_code_label"].format(code=self.ai_code))
            window.destroy()

        ttk.Button(window, text=COPY["save"], command=save).grid(
            row=len(fields) + 1, column=0, columnspan=2, sticky="e", padx=16, pady=12
        )


def main() -> int:
    app = ConverterApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
