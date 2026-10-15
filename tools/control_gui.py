#!/usr/bin/env python3
"""Панель TrollHub с окнами (без командной строки). Всё то же, что tools/control.py, но кнопками:

  * сервер лицензий + бесплатный HTTPS-туннель: запуск, остановка, адрес, сборка Loader.lua;
  * создание ключей (срок, режим, количество, заметка) и копирование в буфер;
  * список выданных ключей и отзыв ключа;
  * простая сборка с проверкой ключа внутри скрипта (сервер не нужен).

Запуск на Windows: двойной щелчок по PANEL_WINDOWS.bat (или: pythonw tools/control_gui.py).
  --autostart   сразу запустить сервер (так программа запускается вместе с Windows, если включить галочку)
  --no-server   не запускать сервер при открытии (для проверки внешнего вида)

Программа ничего не отправляет в интернет, кроме того, что делает сам туннель Cloudflare (как и консольная версия).
Секрет ключей хранится в .license/secret.hex и никогда не показывается в окне.
"""
import csv
import os
import pathlib
import queue
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import messagebox

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import control  # noqa: E402  (same logic as the console panel: one place for server, tunnel, keys)

APP_TITLE = "TrollHub — панель ключей"
SETTINGS_FILE = ROOT / ".license" / "panel.json"

# colours: black glass, white glossy edges, violet accent (the hub's "iOS 27" look)
BG = "#07070b"
CARD = "#12121a"
CARD_HI = "#1b1b27"
EDGE = "#3b3b52"
EDGE_HI = "#c9c9ff"
TEXT = "#f2f2f7"
DIM = "#9a9ab0"
ACCENT = "#8b5cf6"
ACCENT_HI = "#a78bfa"
OK = "#34d399"
BAD = "#f87171"
FONT = "Segoe UI" if sys.platform.startswith("win") else "DejaVu Sans"


# ---------------------------------------------------------------------------------------------------------- non-GUI helpers
def load_settings():
    import json
    try:
        return json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {"autostart_server": True}


def save_settings(data):
    import json
    SETTINGS_FILE.parent.mkdir(exist_ok=True)
    SETTINGS_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


def read_issued(path=None):
    """Rows of .license/issued.csv as dicts (newest first). The key column is kept: it is shown only in this local window."""
    path = path or (control.LICENSE_DIR / "issued.csv")
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        rows = list(csv.DictReader(f))
    return list(reversed(rows))


def revoked_ids():
    p = control.LICENSE_DIR / "revoked.txt"
    if not p.exists():
        return set()
    return {l.strip().lower() for l in p.read_text().splitlines() if l.strip() and not l.startswith("#")}


def startup_dir():
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return None
    return pathlib.Path(appdata) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"


def startup_script_text(python_exe, script):
    """Contents of the .cmd placed in the Windows Startup folder: starts this panel with --autostart, minimised."""
    pyw = pathlib.Path(python_exe).with_name("pythonw.exe")
    exe = pyw if pyw.exists() else pathlib.Path(python_exe)
    return f'@echo off\r\ncd /d "{ROOT}"\r\nstart "" /min "{exe}" "{script}" --autostart\r\n'


def set_windows_autostart(on):
    d = startup_dir()
    if not d:
        raise RuntimeError("автозапуск с Windows работает только на Windows")
    target = d / "MM2Hub_panel.cmd"
    if on:
        d.mkdir(parents=True, exist_ok=True)
        target.write_text(startup_script_text(sys.executable, pathlib.Path(__file__).resolve()), encoding="utf-8")
    elif target.exists():
        target.unlink()
    return target


def windows_autostart_on():
    d = startup_dir()
    return bool(d and (d / "MM2Hub_panel.cmd").exists())


def generate_keys(values, mode_activation, count, note, forever=False):
    """Runs keygen.py gen and returns (keys, summary). Any number of years is accepted: a term longer than the key format holds
    (year 2106) becomes a key without a time limit, the same as forever=True."""
    if forever:
        args = ["--forever"]
    else:
        args = control.duration_args(values.get("months", 0), values.get("years", 0), values.get("days", 0),
                                     values.get("hours", 0), values.get("minutes", 0), values.get("seconds", 0))
    control.ensure_secret()
    cmd = [sys.executable, str(ROOT / "tools" / "keygen.py"), "gen", *args, "--mode", "activation" if mode_activation else "absolute",
           "--count", str(max(1, min(int(count), 100)))]
    if note:
        cmd += ["--note", note]
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=flags)
    if res.returncode != 0:
        raise RuntimeError((res.stderr or res.stdout or "ошибка генератора").strip())
    keys = [l.strip() for l in res.stdout.splitlines() if l.strip()]
    summary = res.stderr.strip().lstrip("# ")
    return keys, summary


# ---------------------------------------------------------------------------------------------------------- widgets
class GlassButton(tk.Canvas):
    """Rounded button with a glossy edge; primary = violet fill."""

    def __init__(self, master, text, command, primary=False, danger=False, width=None, height=40):
        import tkinter.font as tkfont
        width = tkfont.Font(family=FONT, size=11, weight="bold").measure(text) + 40  # always fits its text
        super().__init__(master, width=width, height=height, bg=master["bg"], highlightthickness=0, cursor="hand2")
        self.text, self.command, self.primary, self.danger = text, command, primary, danger
        self.w, self.h = width, height
        self.enabled = True
        self.hover = False
        self.bind("<Enter>", lambda e: self._set_hover(True))
        self.bind("<Leave>", lambda e: self._set_hover(False))
        self.bind("<ButtonRelease-1>", self._click)
        self.draw()

    def _set_hover(self, on):
        self.hover = on
        self.draw()

    def _click(self, _e):
        if self.enabled and self.command:
            self.command()

    def set_text(self, text):
        import tkinter.font as tkfont
        self.text = text
        self.w = max(self.w, tkfont.Font(family=FONT, size=11, weight="bold").measure(text) + 40)
        self.configure(width=self.w)
        self.draw()

    def set_enabled(self, on):
        self.enabled = on
        self.configure(cursor="hand2" if on else "arrow")
        self.draw()

    def draw(self):
        self.delete("all")
        w, h, r = self.w, self.h, 12
        if self.danger:
            fill = "#3a1520" if not self.hover else "#4a1a28"
            edge = BAD
        elif self.primary:
            fill = ACCENT if not self.hover else ACCENT_HI
            edge = "#e9e2ff"
        else:
            fill = CARD_HI if not self.hover else "#262636"
            edge = EDGE_HI if self.hover else EDGE
        if not self.enabled:
            fill, edge = "#1a1a22", "#2a2a36"
        round_rect(self, 1, 1, w - 1, h - 1, r, fill=fill, outline=edge, width=1.5)
        # glossy highlight along the top edge only
        self.create_line(r, 3, w - r, 3, fill="#ffffff" if self.enabled and (self.primary or self.hover) else "#4a4a62", width=1)
        self.create_text(w // 2, h // 2, text=self.text, fill=TEXT if self.enabled else "#55556a", font=(FONT, 11, "bold"))


def round_rect(c, x1, y1, x2, y2, r, **kw):
    pts = [x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y2 - r, x2, y2, x2 - r, y2, x1 + r, y2, x1, y2, x1, y2 - r, x1, y1 + r, x1, y1]
    stipple = kw.pop("stipple", None)
    if kw.get("fill") == "":
        return c.create_line(*pts, x1 + r, y1, smooth=True, fill=kw.get("outline"), width=kw.get("width", 1))
    item = c.create_polygon(pts, smooth=True, **kw)
    if stipple:
        c.itemconfigure(item, stipple=stipple)
    return item


def card(master, title):
    outer = tk.Frame(master, bg=EDGE, padx=1, pady=1)
    inner = tk.Frame(outer, bg=CARD, padx=16, pady=12)
    inner.pack(fill="both", expand=True)
    tk.Label(inner, text=title, bg=CARD, fg=TEXT, font=(FONT, 13, "bold"), anchor="w").pack(fill="x")
    tk.Frame(inner, bg="#2a2a3c", height=1).pack(fill="x", pady=(6, 10))
    return outer, inner


def label(master, text, dim=False, size=10, **kw):
    return tk.Label(master, text=text, bg=master["bg"], fg=DIM if dim else TEXT, font=(FONT, size), justify="left", **kw)


def entry(master, width=6, value=""):
    e = tk.Entry(master, width=width, bg="#0d0d14", fg=TEXT, insertbackground=TEXT, relief="flat", font=(FONT, 11), disabledbackground="#15151f", disabledforeground="#55556a",
                 highlightthickness=1, highlightbackground=EDGE, highlightcolor=ACCENT_HI)
    if value:
        e.insert(0, value)
    return e


# ---------------------------------------------------------------------------------------------------------- app
class App:
    def __init__(self, root, autostart=False):
        self.root = root
        self.stack = None
        self.busy = False
        self.events = queue.Queue()
        self.settings = load_settings()
        root.title(APP_TITLE)
        root.configure(bg=BG)
        root.geometry("1260x800")
        root.minsize(1160, 760)
        root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.build_header()
        body = tk.Frame(root, bg=BG)
        body.pack(fill="both", expand=True, padx=18, pady=(0, 16))
        left = tk.Frame(body, bg=BG)
        left.pack(side="left", fill="both", expand=True)
        right = tk.Frame(body, bg=BG, width=600)
        right.pack(side="left", fill="both", padx=(14, 0))
        right.pack_propagate(False)
        self.build_server(left)
        self.build_keys(left)
        self.build_list(right)
        self.build_log(right)
        self.refresh_list()
        root.after(100, self.pump)
        if "--no-server" in sys.argv:
            pass  # screenshots / tests
        elif autostart or self.settings.get("autostart_server", True):
            root.after(400, self.start_server)

    # header with a chrome "wave" drawn from layered curves
    def build_header(self):
        c = tk.Canvas(self.root, height=118, bg=BG, highlightthickness=0)
        c.pack(fill="x")
        self.header = c
        c.bind("<Configure>", lambda e: self.draw_header())

    def draw_header(self):
        import math
        c = self.header
        c.delete("all")
        w = c.winfo_width() or 1040
        shades = ["#1e2a44", "#2c4a7a", "#5d8fd6", "#c8dcff", "#ffffff", "#9cc2ff", "#3a5f9e"]
        for k, col in enumerate(shades):
            pts = []
            for x in range(0, w + 20, 20):
                fade = min(1.0, max(0.0, (x - 260) / 220))  # the wave starts to the right of the title
                y = 60 + fade * (22 * math.sin(x / 120 + k * 0.18) + 9 * math.sin(x / 47 + k)) + (k - 3) * 2.2
                pts += [x, y]
            c.create_line(*pts, smooth=True, fill=col, width=3 if k == 4 else 2)
        c.create_rectangle(0, 0, 250, 118, fill=BG, outline="")
        c.create_text(26, 44, text="TrollHub", anchor="w", fill=TEXT, font=(FONT, 22, "bold"))
        c.create_text(28, 78, text="ключи и сервер лицензий", anchor="w", fill=DIM, font=(FONT, 11))

    def build_server(self, parent):
        outer, f = card(parent, "Сервер лицензий")
        outer.pack(fill="x")
        row = tk.Frame(f, bg=CARD)
        row.pack(fill="x")
        self.dot = tk.Canvas(row, width=14, height=14, bg=CARD, highlightthickness=0)
        self.dot.pack(side="left")
        self.status = label(row, "остановлен", size=11)
        self.status.pack(side="left", padx=8)
        self.url = label(f, "Адрес появится после запуска.", dim=True, wraplength=440, anchor="w")
        self.url.pack(fill="x", pady=(8, 8))
        btns = tk.Frame(f, bg=CARD)
        btns.pack(fill="x")
        self.btn_server = GlassButton(btns, "Запустить", self.toggle_server, primary=True, width=150)
        self.btn_server.pack(side="left")
        GlassButton(btns, "Папка с Loader.lua", self.open_dist, width=190).pack(side="left", padx=8)
        GlassButton(btns, "Копировать адрес", self.copy_url, width=170).pack(side="left")
        opts = tk.Frame(f, bg=CARD)
        opts.pack(fill="x", pady=(10, 0))
        self.var_auto = tk.BooleanVar(value=self.settings.get("autostart_server", True))
        self.var_win = tk.BooleanVar(value=windows_autostart_on())
        for var, text, cmd in ((self.var_auto, "Запускать сервер сразу при открытии программы", self.on_auto),
                               (self.var_win, "Открывать программу вместе с Windows", self.on_win)):
            tk.Checkbutton(opts, text=text, variable=var, command=cmd, bg=CARD, fg=TEXT, selectcolor="#0d0d14", activebackground=CARD,
                           activeforeground=TEXT, font=(FONT, 10), anchor="w", highlightthickness=0, bd=0).pack(fill="x")
        label(f, "Адрес бесплатного туннеля меняется при каждом запуске. Программа сама пересобирает Loader.lua — "
                 "раздавайте свежий файл после перезапуска.", dim=True, size=9, wraplength=560, anchor="w").pack(fill="x", pady=(8, 0))
        self.set_status("stopped")

    def build_keys(self, parent):
        outer, f = card(parent, "Создать ключ")
        outer.pack(fill="x", pady=(14, 0))
        grid = tk.Frame(f, bg=CARD)
        grid.pack(fill="x")
        self.dur = {}
        for i, (key, name) in enumerate((("years", "Годы"), ("months", "Месяцы"), ("days", "Дни"), ("hours", "Часы"), ("minutes", "Минуты"))):
            label(grid, name, dim=True, size=9).grid(row=0, column=i, sticky="w", padx=(0, 10))
            e = entry(grid, 7, "30" if key == "days" else "")
            e.grid(row=1, column=i, sticky="w", padx=(0, 10), pady=(2, 8))
            self.dur[key] = e
        self.var_forever = tk.BooleanVar(value=False)
        tk.Checkbutton(f, text="Навсегда (бессрочный ключ). Годы можно вводить любые — слишком большой срок тоже станет бессрочным",
                       variable=self.var_forever, command=self.on_forever, bg=CARD, fg=TEXT, selectcolor="#0d0d14", activebackground=CARD,
                       activeforeground=TEXT, font=(FONT, 10), anchor="w", justify="left", wraplength=540, highlightthickness=0,
                       bd=0).pack(fill="x", pady=(0, 6))
        self.var_mode = tk.IntVar(value=0)
        mrow = tk.Frame(f, bg=CARD)
        mrow.pack(fill="x")
        for val, text in ((0, "Срок идёт с этого момента"), (1, "Срок идёт с первой активации покупателем")):
            tk.Radiobutton(mrow, text=text, variable=self.var_mode, value=val, bg=CARD, fg=TEXT, selectcolor="#0d0d14", activebackground=CARD,
                           activeforeground=TEXT, font=(FONT, 10), anchor="w", highlightthickness=0, bd=0).pack(fill="x")
        nrow = tk.Frame(f, bg=CARD)
        nrow.pack(fill="x", pady=(8, 0))
        label(nrow, "Количество", dim=True, size=9).grid(row=0, column=0, sticky="w")
        label(nrow, "Заметка (кому)", dim=True, size=9).grid(row=0, column=1, sticky="w", padx=(12, 0))
        self.count = entry(nrow, 6, "1")
        self.count.grid(row=1, column=0, sticky="w")
        self.note = entry(nrow, 30)
        self.note.grid(row=1, column=1, sticky="we", padx=(12, 0))
        brow = tk.Frame(f, bg=CARD)
        brow.pack(fill="x", pady=(12, 0))
        GlassButton(brow, "Создать ключ", self.make_keys, primary=True, width=170).pack(side="left")
        GlassButton(brow, "Копировать ключи", self.copy_keys, width=170).pack(side="left", padx=8)
        self.out = tk.Text(f, height=4, bg="#0d0d14", fg=OK, insertbackground=TEXT, relief="flat", font=("Consolas", 11),
                           highlightthickness=1, highlightbackground=EDGE, wrap="none")
        self.out.pack(fill="x", pady=(10, 0))
        self.summary = label(f, "", dim=True, size=9, wraplength=460, anchor="w")
        self.summary.pack(fill="x", pady=(4, 0))

    def build_list(self, parent):
        outer, f = card(parent, "Выданные ключи")
        outer.pack(fill="both", expand=True)
        wrap = tk.Frame(f, bg=CARD)
        wrap.pack(fill="both", expand=True)
        self.listbox = tk.Listbox(wrap, bg="#0d0d14", fg=TEXT, selectbackground=ACCENT, selectforeground="white", relief="flat",
                                  font=("Consolas", 10), highlightthickness=1, highlightbackground=EDGE, activestyle="none")
        sb = tk.Scrollbar(wrap, command=self.listbox.yview, bg=CARD, troughcolor=CARD, relief="flat")
        self.listbox.configure(yscrollcommand=sb.set)
        self.listbox.pack(side="left", fill="both", expand=True)
        sb.pack(side="left", fill="y")
        brow = tk.Frame(f, bg=CARD)
        brow.pack(fill="x", pady=(10, 0))
        GlassButton(brow, "Обновить", self.refresh_list, width=120).pack(side="left")
        GlassButton(brow, "Копировать ключ", self.copy_selected, width=170).pack(side="left", padx=8)
        brow2 = tk.Frame(f, bg=CARD)
        brow2.pack(fill="x", pady=(8, 0))
        GlassButton(brow2, "Отозвать ключ", self.revoke_selected, danger=True).pack(side="left")
        GlassButton(brow2, "Сборка без сервера", self.build_offline).pack(side="left", padx=8)

    def build_log(self, parent):
        outer, f = card(parent, "Журнал")
        outer.pack(fill="x", pady=(14, 0))
        self.log = tk.Text(f, height=6, bg="#0d0d14", fg=DIM, relief="flat", font=("Consolas", 9), highlightthickness=1,
                           highlightbackground=EDGE, wrap="word", state="disabled")
        self.log.pack(fill="x")

    # ------------------------------------------------------------------------------------------------ helpers
    def say(self, msg):
        self.events.put(("log", msg))

    def pump(self):
        try:
            while True:
                kind, data = self.events.get_nowait()
                if kind == "log":
                    self.log.configure(state="normal")
                    self.log.insert("end", time.strftime("%H:%M:%S  ") + data + "\n")
                    self.log.see("end")
                    self.log.configure(state="disabled")
                elif kind == "status":
                    self.set_status(*data)
                elif kind == "error":
                    messagebox.showerror(APP_TITLE, data)
        except queue.Empty:
            pass
        self.root.after(100, self.pump)

    def set_status(self, state, url=None):
        colours = {"stopped": ("#55556a", "остановлен"), "starting": ("#fbbf24", "запускается…"), "running": (OK, "работает"), "error": (BAD, "ошибка")}
        col, text = colours[state]
        self.dot.delete("all")
        self.dot.create_oval(2, 2, 12, 12, fill=col, outline="")
        self.status.configure(text=text)
        if url:
            self.url.configure(text=f"Адрес: {url}\nРаздавайте файл: {ROOT / 'dist' / 'Loader.lua'}", fg=TEXT)
        elif state == "stopped":
            self.url.configure(text="Адрес появится после запуска.", fg=DIM)
        self.btn_server.set_text("Остановить" if state in ("running", "starting") else "Запустить")
        self.btn_server.set_enabled(state != "starting")

    # ------------------------------------------------------------------------------------------------ server
    def toggle_server(self):
        if self.stack:
            self.stop_server()
        else:
            self.start_server()

    def start_server(self):
        if self.stack or self.busy:
            return
        self.busy = True
        self.events.put(("status", ("starting",)))
        self.say("Запуск сервера и туннеля…")

        def work():
            control.say = self.say  # the console helpers report through the log
            try:
                stack = control.start_stack(8787)
                self.stack = stack
                self.events.put(("status", ("running", stack.url)))
            except Exception as e:
                self.say(f"Ошибка: {e}")
                self.events.put(("status", ("error",)))
                self.events.put(("error", f"Сервер не запустился:\n{e}"))
            finally:
                self.busy = False

        threading.Thread(target=work, daemon=True).start()

    def stop_server(self):
        if self.stack:
            self.stack.stop()
            self.stack = None
            self.say("Сервер остановлен.")
        self.set_status("stopped")

    def open_dist(self):
        d = ROOT / "dist"
        d.mkdir(exist_ok=True)
        if sys.platform.startswith("win"):
            os.startfile(d)  # noqa: S606 (opens Explorer on our own folder)
        else:
            self.say(f"Папка: {d}")

    def copy_url(self):
        if self.stack and self.stack.url:
            self.clip(self.stack.url)
            self.say("Адрес скопирован.")
        else:
            self.say("Сервер ещё не запущен.")

    def on_auto(self):
        self.settings["autostart_server"] = bool(self.var_auto.get())
        save_settings(self.settings)

    def on_win(self):
        try:
            path = set_windows_autostart(bool(self.var_win.get()))
            self.say(("Добавлено в автозагрузку: " if self.var_win.get() else "Убрано из автозагрузки: ") + str(path))
        except Exception as e:
            self.var_win.set(windows_autostart_on())
            messagebox.showerror(APP_TITLE, str(e))

    # ------------------------------------------------------------------------------------------------ keys
    def make_keys(self):
        try:
            values = {}
            for k, e in self.dur.items():
                raw = e.get().strip()
                values[k] = int(raw) if raw else 0
            count = int(self.count.get().strip() or "1")
            keys, summary = generate_keys(values, self.var_mode.get() == 1, count, self.note.get().strip(), self.var_forever.get())
        except ValueError as e:
            messagebox.showwarning(APP_TITLE, f"Проверьте поля: {e}")
            return
        except Exception as e:
            messagebox.showerror(APP_TITLE, str(e))
            return
        self.out.delete("1.0", "end")
        self.out.insert("1.0", "\n".join(keys))
        self.summary.configure(text=summary)
        self.say(f"Создано ключей: {len(keys)}")
        self.refresh_list()

    def on_forever(self):
        state = "disabled" if self.var_forever.get() else "normal"
        for e in self.dur.values():
            e.configure(state=state)

    def copy_keys(self):
        text = self.out.get("1.0", "end").strip()
        if text:
            self.clip(text)
            self.say("Ключи скопированы.")

    def refresh_list(self):
        self.rows = read_issued()
        rev = revoked_ids()
        self.listbox.delete(0, "end")
        for r in self.rows:
            mark = "ОТОЗВАН " if (r.get("nonce") or "").lower() in rev else ""
            mode = "с активации" if r.get("mode") == "activation" else "с выдачи"
            self.listbox.insert("end", f"{mark}{r.get('issued_utc', '')[:16]}  {mode:11s}  {r.get('note', '')[:18]:18s}  {r.get('key', '')}")
        if not self.rows:
            self.listbox.insert("end", "Ключи ещё не выдавались.")

    def selected_row(self):
        sel = self.listbox.curselection()
        if not sel or not self.rows:
            messagebox.showinfo(APP_TITLE, "Выберите ключ в списке.")
            return None
        return self.rows[sel[0]]

    def copy_selected(self):
        r = self.selected_row()
        if r:
            self.clip(r.get("key", ""))
            self.say("Ключ скопирован.")

    def revoke_selected(self):
        r = self.selected_row()
        if not r:
            return
        if not messagebox.askyesno(APP_TITLE, f"Отозвать ключ?\n{r.get('key')}\n\nПокупатель с этим ключом больше не сможет войти."):
            return
        try:
            nonce = control.revoke(r.get("key", ""))
            self.say(f"Ключ отозван (номер {nonce}).")
        except Exception as e:
            messagebox.showerror(APP_TITLE, str(e))
        self.refresh_list()

    def build_offline(self):
        def work():
            try:
                control.ensure_secret()
                p = control.build.build(False, (control.LICENSE_DIR / "secret.hex").read_text().strip(), True)
                self.say(f"Собрано: {p} (ключ проверяется внутри скрипта, ограничения: docs/LICENSE.md)")
            except Exception as e:
                self.events.put(("error", str(e)))

        threading.Thread(target=work, daemon=True).start()

    def clip(self, text):
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

    def on_close(self):
        if self.stack and not messagebox.askyesno(APP_TITLE, "Сервер работает. Закрыть программу и остановить сервер?"):
            return
        self.stop_server()
        self.root.destroy()


def main():
    root = tk.Tk()
    App(root, autostart="--autostart" in sys.argv)
    root.mainloop()


if __name__ == "__main__":
    main()
