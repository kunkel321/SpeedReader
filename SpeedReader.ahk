; ======================================================================================================================
; SpeedReader.ahk — A speed reading trainer for plain-text files
; Author: Steve (kunkel321) with Claude (Anthropic)
; Version Date: 4-22-2026 
; Requires: AutoHotkey v2.0+  |  RichEdit.ahk by just-me (place in same folder)
;           https://github.com/AHK-just-me/AHK2_RichEdit
; ======================================================================================================================
;
; OVERVIEW
; --------
; SpeedReader opens a .txt file and highlights a configurable "chunk" of words at a time,
; advancing through the text at a user-set WPM rate.  Pauses are automatically inserted at
; sentence, paragraph, and list-item boundaries.  The goal is to train faster reading by
; giving the eye a single focal point that moves at a controlled pace.  Works well with
; plain-text books from Project Gutenberg and similar sources.
;
; SETUP
; -----
;  1. Place SpeedReader.ahk and RichEdit.ahk in the same folder and run with AHK v2.
;  2. On first run, Settings.ini is created automatically with sensible defaults.
;  3. Open a .txt file via File > Open, by dragging a file onto the window, or by
;     choosing from the recent-files list in the File menu.
;  4. Press Play (or the Down arrow key) to begin.  Press again to pause.
;
; CONTROLS
; --------
;  Play / Pause         ▶ Play button  —or—  Down arrow key (window must be active)
;  Restart              ⟲ Restart button — clears highlight and rewinds to word 1
;  Speed (WPM)          Big slider at the bottom of the window, plus:
;                         Left / Right arrow keys  (±WPMHotkeyStep per press, default ±25)
;                         Mouse wheel over the slider (wheel-up = faster, wheel-down = slower)
;  Jump to any word     Double-click the word — playback restarts from that point immediately.
;                         Works whether the reader is playing, paused, or stopped.
;  Open file            File > Open  (Ctrl+O),  or drag-and-drop a .txt file onto the window
;  Recent files         Numbered list in the File menu (files that no longer exist are omitted)
;
; TOP TOOLBAR  (never moves during window resize)
; -----------
;  ▶ Play / ❚❚ Pause    Toggle playback
;  ⟲ Restart            Rewind to the beginning
;  Size                 Font size spin-box — live update, no restart needed
;  Chunk                Words highlighted per tick (1–10). Larger = easier at high WPM.
;  Status bar           Filename + word count while stopped; "Word X of Y (Z%)" while playing
;
; ROW 2  (WPM display + checkboxes)
; ------
;  WPM: N  [m:ss]       Large WPM readout.  Once ~10 words have been read a rolling
;                         time-remaining estimate appears in [m:ss] format, updated at the
;                         interval set by TimeRemainingUpdateMs (default once per second).
;                         The estimate uses actual dwell times, so it accounts for sentence
;                         pauses, smart pacing, chunk size, etc. automatically.
;
;  Overlap              Sliding-window mode: the chunk-sized highlight advances one word per
;                         tick instead of jumping by a whole chunk.  Gives a smoother,
;                         flowing feel.  Sentence/list pause multipliers are suppressed in
;                         this mode (they would disrupt the slide); Smart pacing still works.
;
;  Sentence pause       Dwell longer at sentence ends (.  !  ?  …) and strong mid-sentence
;                         breaks (;  :  em-dash).  Paragraph ends always pause regardless.
;                         Comma pauses are lighter and never clip a chunk boundary.
;                         Common abbreviations (Mr. Dr. etc. e.g. p. …) are excluded from
;                         sentence detection so they don't trigger false pauses.
;
;  List pauses          Detect short lines that look like list or enumeration items and
;                         pause at the end of each.  A line qualifies if it is short
;                         (≤ ListMaxWords words), doesn't end in a comma/semicolon/hyphen,
;                         doesn't end in a bare conjunction (and/or/but…), and the next
;                         line starts with a capital letter.
;
;  Smart pacing         Scale each word's dwell time by its reading difficulty:
;                           Stopwords (the, of, and …)   → StopwordWeight × base  (faster)
;                           Monosyllabic content words   → MonoWeight × base      (baseline)
;                           Polysyllabic words           → +ExtraSyllableWeight per extra
;                                                          syllable beyond the first (slower)
;                         Syllables are counted with a vowel-group heuristic; silent trailing
;                         'e' is subtracted.  Good enough for relative weighting purposes.
;
;  Center scroll        Keep the highlighted word vertically centered in the reading pane
;                         as the text advances.  When off, the pane scrolls only when the
;                         highlight reaches the bottom edge (standard behavior).
;                         Scrolling is in whole-line increments (RichEdit limitation).
;
; COLOR / FONT ROW  (bottom band, Row 1)
; ----------------
;  Highlight / Text / Background
;                       Color swatches + "…" buttons open the Windows color picker.
;                         Changes apply immediately to live text.
;  Font                 Drop-down of preset font faces.
;
; MENUS
; -----
;  File > Open                  Standard open dialog, filtered to .txt files  (Ctrl+O)
;  File > Open Settings.ini     Opens the INI in your default text editor
;  File > 1 … N                 Recent files, most-recent-first (missing files skipped)
;  File > Exit
;  Links > Project Gutenberg    https://www.gutenberg.org/ebooks/results/
;  Links > AutoHotkey forum     Forum thread for this script (set URL_AhkForum below)
;  Links > GitHub repo          Repository for this script (set URL_GitHub below)
;  Debug > Token analysis       ListView of tokenization flags for ~80 words around the
;                                 current reading position.  Columns: index, text,
;                                 endsSentence, endsParagraph, endsLine, endsListItem,
;                                 endsCommaLike, weight.  Ctrl+C copies all rows as CSV.
;
; SETTINGS FILE  (Settings.ini, auto-created next to the script on first run)
; -------------
;  All GUI settings save automatically on change and restore on next launch.
;  [Reader]   WPM, ChunkSize, Overlap, SentencePause, ListPauses, SmartPacing, CenterScroll
;  [Colors]   HighlightColor, TextColor, BackColor  (stored as decimal RGB integers)
;  [Font]     Name, Size
;  [Window]   W, H  (saved on close)
;  [Session]  LastFile  (auto-loaded on launch if the file still exists on disk)
;  [Recent]   File1 … FileN  (most-recent-first; missing paths silently skipped on load)
;
; DEVELOPER TUNABLES  (near the top of this file, above the Cfg block)
; ------------------
;  Pacing object        Dwell-time multipliers applied on top of the base WPM rate:
;                         SentenceMult        after .!?…        (default 1.8×)
;                         ParagraphMult       after blank line   (default 2.5×)
;                         CommaMult           after comma        (default 1.15×)
;                         SemicolonColonMult  after ; : em-dash  (default 1.5×)
;                         ListItemMult        after list item    (default 1.4×)
;                         StopwordWeight      fast-word weight   (default 0.5)
;                         MonoWeight          baseline weight    (default 1.0)
;                         ExtraSyllableWeight per extra syllable (default 0.3)
;  WPMHotkeyStep        Arrow-key WPM step size (default 25)
;  ListMaxWords         Max line length in words for list-item detection (default 12)
;  TimeRemainingUpdateMs  How often [m:ss] refreshes, in ms (default 1000 = once/second)
;  RecentFilesMax       How many recent files to remember in the File menu (default 9)
;  URL_AhkForum         AHK forum thread URL — fill in when known
;  URL_GitHub           GitHub repo URL — fill in when known
;
; TECHNICAL NOTES
; ---------------
;  • Uses Just Me's RichEdit.ahk wrapper (RICHEDIT50W from Msftedit.dll, RichEdit v4.1).
;  • All character offsets are zero-based UTF-16 code units, matching RichEdit's internal
;    indexing.  AHK v2 strings are also UTF-16, so StrLen() and offsets always agree.
;  • Line endings are normalized to bare LF on load because RichEdit stores CR-only
;    internally.  Feeding CRLF without stripping \r causes one-character offset drift per
;    line — the highlight gets progressively misaligned through the document.
;  • The blinking caret is permanently suppressed by hooking WM_SETFOCUS and calling
;    CreateCaret(hwnd, 0, 0, 0) + HideCaret each time RichEdit gains focus, plus after
;    every programmatic SetSel call.  A zero-width caret is invisible regardless of blink.
;  • Drag-and-drop uses DragAcceptFiles + WM_DROPFILES.  Only the first dropped file is
;    used; non-.txt files are rejected with a message box.
;  • Mouse-wheel direction on the WPM slider is flipped (wheel-up = increase WPM) via a
;    WM_MOUSEWHEEL hook that only intercepts when the cursor is over the slider hwnd.
;  • Center-scroll uses EM_LINEFROMCHAR, EM_GETFIRSTVISIBLELINE, and EM_LINESCROLL.
;    Line height is measured from two currently-visible lines (not line 0/1) so the
;    measurement stays valid after the view has scrolled away from the top.
; ======================================================================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include RichEdit.ahk

SetWinDelay -1
SetControlDelay -1

; ======================================================================================================================
; Pacing tunables — adjust these to change the "feel" of pauses and emphasis.
; Each is a multiplier on the baseline per-chunk dwell time (60000 * chunk / WPM).
; ======================================================================================================================
global Pacing := {
    SentenceMult:         1.8,   ; dwell ×1.8 on chunks ending in .!?… (breathing room after a sentence)
    ParagraphMult:        2.5,   ; dwell ×2.5 on chunks ending a paragraph (blank line follows)
    CommaMult:            1.15,  ; dwell ×1.15 on chunks ending in a comma
    SemicolonColonMult:   1.8,   ; dwell ×1.30 on chunks ending in ; : or em-dash
    ListItemMult:         1.40,  ; dwell ×1.40 on chunks ending a detected list item
    ; Intelligent-pacing word weights (applied only when Cfg.SmartPacing is on):
    StopwordWeight:       0.5,   ; 'the', 'of', 'and', ... — read fast
    MonoWeight:           1.0,   ; 1-syllable non-stopword baseline
    ExtraSyllableWeight:  0.3    ; added per syllable beyond the first for polysyllabic words
}

; WPM hotkey step (Left/Right arrows adjust WPM by this amount)
global WPMHotkeyStep := 25

; List-detection heuristic thresholds (for the "List pauses" feature)
global ListMaxWords := 12       ; line must be shorter than this to be a candidate list item

; How often (ms) the time-remaining display refreshes. 1000 = once per second.
global TimeRemainingUpdateMs := 1000

; Maximum number of recent files to remember in the File menu (1–16)
global RecentFilesMax := 9

; Tray icon — An airplane image.
TraySetIcon("imageres.dll", 330)

; ======================================================================================================================
; Global configuration
; ======================================================================================================================
global AppName := "SpeedReader"
global IniFile := A_ScriptDir "\Settings.ini"

; ---- External URLs — fill these in when known -----------------------------------------------------------------------
global URL_Gutenberg  := "https://www.gutenberg.org/ebooks/results/"
global URL_AhkForum   := "https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140586" 
global URL_GitHub     := "https://github.com/kunkel321/SpeedReader"  
; Defaults — overridden by Settings.ini if present
global Cfg := {
    WPM:            525,
    ChunkSize:      1,
    Overlap:        False,
    SentencePause:  True,        ; longer dwell at sentence / paragraph boundaries
    ListPauses:     False,       ; detect line-oriented lists and pause at each item
    SmartPacing:    True,        ; weight dwell by word difficulty (stopword/syllables)
    CenterScroll:   True,        ; keep highlighted word vertically centered in the control
    HighlightColor: 15527806,    ; 0xED7B7E — soft red
    TextColor:      1913944,     ; 0x1D3658 — dark blue
    BackColor:      15198183,    ; 0xE7D5E7 — light lavender
    FontName:       "Verdana",
    FontSize:       14,
    GuiW:           900,
    GuiH:           650,
    LastFile:       ""
}

LoadSettings()

; ======================================================================================================================
; Runtime state
; ======================================================================================================================
global Words       := []       ; array of {start, end} zero-based RichEdit offsets
global CurIdx      := 0        ; 0 = not started; otherwise index of last-highlighted word
global PrevStart   := -1       ; start offset of previously highlighted chunk (for un-highlighting)
global PrevEnd     := -1
global IsPlaying   := False
global StepTimer   := StepWord.Bind()   ; bound timer callback
global RecentFiles := []       ; ordered list of recently opened file paths (most recent first)

; Rolling dwell buffer for time-remaining estimate.
; Stores ms-per-word samples (dwell / words_in_chunk) for the last N ticks.
global DwellBuf     := []      ; circular buffer of ms-per-word samples
global DwellBufMax  := 50      ; how many samples to keep
global DwellBufSum  := 0.0     ; running sum for O(1) average
global DwellMinSamples := 10   ; don't show estimate until we have this many samples

; ======================================================================================================================
; Build GUI
; ======================================================================================================================
MainGui := Gui("+Resize +MinSize600x400", AppName)
MainGui.OnEvent("Size", MainGuiSize)
MainGui.OnEvent("Close", GuiClosing)
MainGui.MarginX := 8
MainGui.MarginY := 8

; --- Menu bar ---------------------------------------------------------------------------------------------------------
; NOTE: FileMenu is rebuilt by RebuildRecentMenu() each time a file is opened.
; The static items (Open, Settings, separator) are always added first, then
; recent files, then Exit.
global FileMenu := Menu()
FileMenu.Add("&Open...`tCtrl+O", FileOpen)
FileMenu.Add("Open &Settings.ini", OpenIniFile)
; Recent files and Exit are appended by RebuildRecentMenu() below.

LinksMenu := Menu()
LinksMenu.Add("&Project Gutenberg",     (*) => Run(URL_Gutenberg))
LinksMenu.Add("&AutoHotkey forum thread", (*) => Run(URL_AhkForum))
LinksMenu.Add("&GitHub repo",           (*) => Run(URL_GitHub))

DebugMenu := Menu()
DebugMenu.Add("&Token analysis...", ShowTokenAnalysis)

MenuBarObj := MenuBar()
MenuBarObj.Add("&File", FileMenu)
MenuBarObj.Add("&Links", LinksMenu)
MenuBarObj.Add("&Debug", DebugMenu)
MainGui.MenuBar := MenuBarObj

; --- Top toolbar row --------------------------------------------------------------------------------------------------
BtnPlay    := MainGui.AddButton("xm ym w90 h28", "▶ Play")
BtnPlay.OnEvent("Click", TogglePlay)

BtnRestart := MainGui.AddButton("x+4 yp wp hp", "⟲ Restart")
BtnRestart.OnEvent("Click", Restart)

; Size and Chunk live here (not in the bottom band) so their spin-buttons aren't affected
; when the RichEdit is resized — the top toolbar is anchored at xm ym and never moves.
LblSize := MainGui.AddText("x+16 yp+6 w30", "Size:")
EdSize  := MainGui.AddEdit("x+2 yp-4 w50 Number", Cfg.FontSize)
UdSize  := MainGui.AddUpDown("Range6-72", Cfg.FontSize)
EdSize.OnEvent("Change", FontChanged)

LblChunk := MainGui.AddText("x+12 yp+4 w42", "Chunk:")
EdChunk  := MainGui.AddEdit("x+2 yp-4 w50 Number", Cfg.ChunkSize)
UdChunk  := MainGui.AddUpDown("Range1-10", Cfg.ChunkSize)
EdChunk.OnEvent("Change", ChunkChanged)

; Status label stays on the top row, after the spinboxes
LblStatus  := MainGui.AddText("x+20 yp+4 w400 h20", "No file loaded.")

; --- RichEdit (middle, resizes) ---------------------------------------------------------------------------------------
global RE := RichEdit(MainGui, "xm y+8 w" (Cfg.GuiW - 16) " h" (Cfg.GuiH - 220))
RE.SetOptions(["READONLY"], "OR")
RE.WordWrap(True)
ApplyFontSettings()
ApplyBackColor()

; --- Bottom band: color pickers + font + chunk + WPM slider -----------------------------------------------------------
RE.GetPos(&reX, &reY, &reW, &reH)
global Row1Y := reY + reH + 6          ; color/font/chunk row
global Row2Y := Row1Y + 34              ; WPM label row
global Row3Y := Row2Y + 30              ; slider row

LblHL := MainGui.AddText("xm y" Row1Y " w60", "Highlight:")
SwHL  := MainGui.AddText("x+2 yp-2 w32 h20 +Border +Background" Fmt(Cfg.HighlightColor), "")
BtnHL := MainGui.AddButton("x+2 yp-1 w22 h22", "…")
BtnHL.OnEvent("Click", (*) => PickColor("HighlightColor"))

LblTx := MainGui.AddText("x+14 yp+3 w36", "Text:")
SwTx  := MainGui.AddText("x+2 yp-2 w32 h20 +Border +Background" Fmt(Cfg.TextColor), "")
BtnTx := MainGui.AddButton("x+2 yp-1 w22 h22", "…")
BtnTx.OnEvent("Click", (*) => PickColor("TextColor"))

LblBg := MainGui.AddText("x+14 yp+3 w72", "Background:")
SwBg  := MainGui.AddText("x+2 yp-2 w32 h20 +Border +Background" Fmt(Cfg.BackColor), "")
BtnBg := MainGui.AddButton("x+2 yp-1 w22 h22", "…")
BtnBg.OnEvent("Click", (*) => PickColor("BackColor"))

LblFont := MainGui.AddText("x+18 yp+3 w36", "Font:")
DdlFont := MainGui.AddDropDownList("x+2 yp-3 w150", ["Georgia","Arial","Verdana","Tahoma","Calibri","Consolas","Courier New","Times New Roman"])
TryPickDDL(DdlFont, Cfg.FontName)
DdlFont.OnEvent("Change", FontChanged)

; Row 2: WPM label + value (large font), time remaining, then checkboxes to the right
LblWPMTitle := MainGui.AddText("xm y" Row2Y " w50 h28 +0x200", "WPM:")
LblWPMTitle.SetFont("s12 Bold")
LblWPM := MainGui.AddText("x+2 yp w50 h28 +0x200", Cfg.WPM)
LblWPM.SetFont("s14 Bold")
LblTimeRemain := MainGui.AddText("x+6 yp w70 h28 +0x200", "")
LblTimeRemain.SetFont("s11")

; Checkboxes live here (Row 2), to the right of the WPM display
CbxOverlap  := MainGui.AddCheckbox("x+20 yp+6", "Overlap")
CbxOverlap.Value := Cfg.Overlap
CbxOverlap.OnEvent("Click", OverlapChanged)

CbxSentence := MainGui.AddCheckbox("x+14 yp", "Sentence pause")
CbxSentence.Value := Cfg.SentencePause
CbxSentence.OnEvent("Click", SentencePauseChanged)

CbxList     := MainGui.AddCheckbox("x+14 yp", "List pauses")
CbxList.Value := Cfg.ListPauses
CbxList.OnEvent("Click", ListPausesChanged)

CbxSmart    := MainGui.AddCheckbox("x+14 yp", "Smart pacing")
CbxSmart.Value := Cfg.SmartPacing
CbxSmart.OnEvent("Click", SmartPacingChanged)

CbxCenter   := MainGui.AddCheckbox("x+14 yp", "Center scroll")
CbxCenter.Value := Cfg.CenterScroll
CbxCenter.OnEvent("Click", CenterScrollChanged)

; Row 3: the big slider
SldWPM := MainGui.AddSlider("xm y" Row3Y " w" (Cfg.GuiW - 16) " h40 Range100-1200 TickInterval100 Page50 Line10 ToolTip", Cfg.WPM)
SldWPM.OnEvent("Change", WPMChanged)

; ======================================================================================================================
; Show GUI and optionally auto-load last file
; ======================================================================================================================
MainGui.Show("w" Cfg.GuiW " h" Cfg.GuiH)

; Populate the Recent Files menu now that the menu object exists
RebuildRecentMenu()

If (Cfg.LastFile != "" && FileExist(Cfg.LastFile))
    LoadTextFile(Cfg.LastFile)

; Hook WM_LBUTTONDBLCLK globally and filter by the RichEdit's HWND in the handler.
; This lets the user double-click a word to start reading from there.
OnMessage(0x0203, OnDoubleClick)

; Enable drag-and-drop of .txt files onto the window.
; DragAcceptFiles tells Windows to send WM_DROPFILES (0x0233) to this hwnd.
DllCall("shell32\DragAcceptFiles", "Ptr", MainGui.Hwnd, "Int", 1)
OnMessage(0x0233, OnDropFiles)

; Hook WM_SETFOCUS (0x0007) on the RichEdit: every time it gains focus it recreates
; the caret internally. We intercept this and immediately replace it with a zero-width
; caret, making it permanently invisible regardless of the blink cycle.
OnMessage(0x0007, OnRichEditFocus)
; Windows default: wheel-up = increase toward left (decrease WPM). We reverse it.
OnMessage(0x020A, OnMouseWheel)
;   Left  = slow down by WPMHotkeyStep
;   Right = speed up by WPMHotkeyStep
;   Down  = toggle play/pause
; These suppress the native arrow-key behavior of whichever control has focus
; (caret navigation in the RichEdit, slider increments) so pressing arrows always
; means "speed control" inside this window.
HotIfWinActive("ahk_id " MainGui.Hwnd)
Hotkey("Left",  AdjustWPM.Bind(-WPMHotkeyStep))
Hotkey("Right", AdjustWPM.Bind(+WPMHotkeyStep))
Hotkey("Down",  (*) => TogglePlay())
HotIfWinActive()

Return  ; end of auto-execute section

; ======================================================================================================================
; ======================================================================================================================
; FUNCTIONS
; ======================================================================================================================
; ======================================================================================================================

; ----------------------------------------------------------------------------------------------------------------------
; GUI resize handler — keep RichEdit filling the middle; reposition bottom rows; stretch slider
; ----------------------------------------------------------------------------------------------------------------------
MainGuiSize(GuiObj, MinMax, W, H) {
    If (MinMax = -1)
        Return
    margin := 8
    bottomBandH := 100   ; room for two rows + slider + a little padding

    ; Resize RichEdit
    RE.GetPos(&rx, &ry)
    newREH := H - ry - bottomBandH - margin
    If (newREH < 50)
        newREH := 50
    RE.Move(, , W - 2*margin, newREH)

    ; Recompute row Ys based on new RichEdit bottom
    RE.GetPos(&rx2, &ry2, &rw2, &rh2)
    r1Y := ry2 + rh2 + 6
    r2Y := r1Y + 34
    r3Y := r2Y + 30

    ; Row 1 (color swatches + font dropdown) — rebuild left-to-right using each control's current width
    row1 := [LblHL, SwHL, BtnHL, LblTx, SwTx, BtnTx, LblBg, SwBg, BtnBg, LblFont, DdlFont]
    ; Gaps between controls, matching original "x+N" offsets from the layout code above
    gaps := [2, 2, 14, 2, 2, 14, 2, 2, 18, 2]
    x := margin
    For i, ctrl in row1 {
        ctrl.GetPos(, , &cw, &ch)
        ; Match the per-control y-offsets used at creation time
        If (ctrl = SwHL || ctrl = SwTx || ctrl = SwBg)
            yOff := -2
        Else If (ctrl = BtnHL || ctrl = BtnTx || ctrl = BtnBg || ctrl = DdlFont)
            yOff := -1
        Else
            yOff := 3
        ctrl.Move(x, r1Y + yOff)
        If (i <= gaps.Length)
            x += cw + gaps[i]
    }

    ; Row 2 — WPM label + value + time remaining + checkboxes
    LblWPMTitle.GetPos(, , &w1)
    LblWPMTitle.Move(margin, r2Y)
    LblWPM.Move(margin + w1 + 2, r2Y)
    LblWPM.GetPos(, , &w2)
    LblTimeRemain.Move(margin + w1 + 2 + w2 + 6, r2Y)
    ; Reposition checkboxes: pick up from where LblTimeRemain ends
    LblTimeRemain.GetPos(, , &w3)
    cbxX := margin + w1 + 2 + w2 + 6 + w3 + 20
    cbxY := r2Y + 6
    CbxOverlap.Move(cbxX, cbxY)
    CbxOverlap.GetPos(, , &cbW)
    cbxX += cbW + 14
    CbxSentence.Move(cbxX, cbxY)
    CbxSentence.GetPos(, , &cbW)
    cbxX += cbW + 14
    CbxList.Move(cbxX, cbxY)
    CbxList.GetPos(, , &cbW)
    cbxX += cbW + 14
    CbxSmart.Move(cbxX, cbxY)
    CbxSmart.GetPos(, , &cbW)
    cbxX += cbW + 14
    CbxCenter.Move(cbxX, cbxY)

    ; Row 3 — slider stretches to full width
    SldWPM.Move(margin, r3Y, W - 2*margin)
}

; ----------------------------------------------------------------------------------------------------------------------
; Window close — save settings & exit
; ----------------------------------------------------------------------------------------------------------------------
GuiClosing(*) {
    MainGui.GetClientPos(, , &cw, &ch)
    Cfg.GuiW := cw
    Cfg.GuiH := ch
    SaveSettings()
    ExitApp()
}

; ----------------------------------------------------------------------------------------------------------------------
; File menu handler
; ----------------------------------------------------------------------------------------------------------------------
FileOpen(*) {
    f := FileSelect(1, Cfg.LastFile, "Open text file", "Text Files (*.txt)")
    If (f = "")
        Return
    LoadTextFile(f)
}

; ----------------------------------------------------------------------------------------------------------------------
; Open Settings.ini in the default editor (usually Notepad)
; ----------------------------------------------------------------------------------------------------------------------
OpenIniFile(*) {
    If !FileExist(IniFile) {
        MsgBox("Settings.ini not found.`n`nIt will be created automatically when you change a setting.", AppName, 64)
        Return
    }
    Run(IniFile)
}

; ----------------------------------------------------------------------------------------------------------------------
; Push a path to the top of RecentFiles, deduplicating and capping at RecentFilesMax.
; ----------------------------------------------------------------------------------------------------------------------
PushRecentFile(path) {
    global RecentFiles, RecentFilesMax
    ; Remove any existing occurrence (case-insensitive) to avoid duplicates
    i := 1
    While (i <= RecentFiles.Length) {
        If (StrLower(RecentFiles[i]) = StrLower(path))
            RecentFiles.RemoveAt(i)
        Else
            i++
    }
    RecentFiles.InsertAt(1, path)
    While (RecentFiles.Length > RecentFilesMax)
        RecentFiles.Pop()
}

; ----------------------------------------------------------------------------------------------------------------------
; Rebuild the File menu from scratch: static items, then recent files (existing only), then Exit.
; Called at startup and whenever a new file is loaded.
; ----------------------------------------------------------------------------------------------------------------------
RebuildRecentMenu() {
    global FileMenu, RecentFiles
    ; Wipe and rebuild the whole menu so we don't have to track item positions
    FileMenu.Delete()
    FileMenu.Add("&Open...`tCtrl+O", FileOpen)
    FileMenu.Add("Open &Settings.ini", OpenIniFile)
    FileMenu.Add()   ; separator
    ; Add only files that still exist on disk
    added := 0
    For i, path in RecentFiles {
        If !FileExist(path)
            Continue
        added++
        label := "&" added "  " FileBaseName(path)
        ; Capture path in a closure so each menu item loads the right file
        FileMenu.Add(label, ((p, *) => LoadTextFile(p)).Bind(path))
    }
    If (added > 0)
        FileMenu.Add()   ; separator before Exit
    FileMenu.Add("E&xit", (*) => ExitApp())
}

; ----------------------------------------------------------------------------------------------------------------------
; WM_DROPFILES handler — user dragged a file onto the window.
; Extracts the first dropped filename; loads it if it's a .txt file.
; ----------------------------------------------------------------------------------------------------------------------
OnDropFiles(wParam, lParam, msg, hwnd) {
    ; DragQueryFileW with index 0xFFFFFFFF returns the file count
    count := DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0)
    If (count < 1) {
        DllCall("shell32\DragFinish", "Ptr", wParam)
        Return
    }
    ; Get the first dropped file path
    buf := Buffer(1024, 0)
    DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", 0, "Ptr", buf, "UInt", 512)
    DllCall("shell32\DragFinish", "Ptr", wParam)
    path := StrGet(buf, "UTF-16")
    SplitPath(path, , , &ext)
    If (StrLower(ext) != "txt") {
        MsgBox("Only .txt files are supported.`n`nDropped: " path, AppName, 48)
        Return
    }
    LoadTextFile(path)
}

; ----------------------------------------------------------------------------------------------------------------------
; Load a .txt file into the RichEdit and tokenize into words
; ----------------------------------------------------------------------------------------------------------------------
LoadTextFile(path) {
    Try {
        text := FileRead(path, "UTF-8")
    } Catch {
        Try text := FileRead(path)
        Catch As e2 {
            MsgBox("Could not read file:`n" path "`n`n" e2.Message, AppName, 16)
            Return
        }
    }
    ; Normalize line endings. RichEdit silently collapses CRLF -> CR internally,
    ; so if we feed it CRLF and tokenize the original CRLF text, our offsets will
    ; drift one character right per line break. Strip the \r so AHK and the control
    ; agree on character counts.
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r",   "`n")   ; handle old Mac-style CR-only too
    StopPlay()
    ResetDwellBuffer()
    RE.SetText(text)               ; SetText works even when control is read-only
    RE.SetSel(0, 0)
    RE.ScrollCaret()
    DllCall("HideCaret", "Ptr", RE.Hwnd)
    ApplyFontSettings()            ; re-apply font/color to the newly-loaded text
    Tokenize(text)
    global CurIdx, PrevStart, PrevEnd
    CurIdx := 0
    PrevStart := PrevEnd := -1
    Cfg.LastFile := path
    PushRecentFile(path)
    SaveSettings()
    RebuildRecentMenu()
    LblStatus.Text := Format("{1}  ({2} words)", FileBaseName(path), Words.Length)
}

FileBaseName(path) {
    SplitPath(path, &name)
    Return name
}

; ----------------------------------------------------------------------------------------------------------------------
; Tokenize text into words with zero-based character offsets matching RichEdit's indexing.
; Each word carries:
;   text          — the word as it appears in the source (including attached punctuation)
;   endsSentence  — word ends with . ! ? … possibly followed by closing quotes/parens
;   endsParagraph — the whitespace between this word and the next contains >=2 newlines
;   endsLine      — the gap to the next word contains at least one newline (but not a paragraph break)
;   endsListItem  — heuristically identified as the last word of a list-style line item
;                   (short line, no trailing comma/semicolon, next line capitalized)
;   endsCommaLike — word ends with , ; : — (em-dash) — for mid-sentence micro-pauses
;   weight        — smart-pacing difficulty weight
; ----------------------------------------------------------------------------------------------------------------------
Tokenize(text) {
    global Words
    Words := []
    pos := 1
    ; First pass: collect words with positions and per-word intrinsic flags.
    While (pos := RegExMatch(text, "\S+", &m, pos)) {
        start0 := pos - 1                         ; convert AHK 1-based to RichEdit 0-based
        end0   := start0 + StrLen(m[0])           ; exclusive end
        Words.Push({
            start:         start0,
            end:           end0,
            text:          m[0],
            endsSentence:  IsSentenceEnd(m[0]),
            endsCommaLike: IsCommaLikeEnd(m[0]),
            endsParagraph: False,    ; filled in pass 2
            endsLine:      False,    ; filled in pass 2
            endsListItem:  False,    ; filled in pass 3
            weight:        WeighWord(m[0])
        })
        pos += StrLen(m[0])
    }
    ; Second pass: look at whitespace gaps between adjacent words in the source text.
    ; Flag paragraph and line boundaries.
    Loop Words.Length - 1 {
        i := A_Index
        gapStart := Words[i].end + 1                   ; AHK 1-based
        gapEnd   := Words[i+1].start                   ; AHK 1-based
        gap := SubStr(text, gapStart, gapEnd - gapStart)
        ; A paragraph break: two or more newlines (possibly with whitespace between)
        If (RegExMatch(gap, "\n\s*\n"))
            Words[i].endsParagraph := True
        ; A simple line break: any newline in the gap (the paragraph case is a superset,
        ; but we use endsLine only for list detection where endsParagraph is already
        ; handled separately, so leave both flags on here — the consumers disambiguate).
        If (InStr(gap, "`n"))
            Words[i].endsLine := True
    }
    ; The final word always ends a paragraph/sentence (it ends everything).
    If (Words.Length > 0) {
        Words[Words.Length].endsParagraph := True
        Words[Words.Length].endsSentence  := True
        Words[Words.Length].endsLine      := True
    }
    ; Third pass: detect list items. Walk through word-runs ending at each endsLine
    ; boundary, evaluate whether the line "looks like" a list item, and set the flag
    ; on the last word of that line.
    lineStart := 1
    For i, w in Words {
        If !w.endsLine
            Continue
        ; This word terminates a line. Consider the run [lineStart..i].
        lineLen := i - lineStart + 1
        qualifies := True
        ; Rule A: skip — a paragraph boundary means the existing paragraph-pause handles it
        If (w.endsParagraph)
            qualifies := False
        ; Rule B: skip — already a sentence end, existing sentence-pause handles it
        Else If (w.endsSentence)
            qualifies := False
        ; Rule C: line must be short (configured max)
        Else If (lineLen > ListMaxWords)
            qualifies := False
        ; Rule D: last word must not end in a comma/semicolon/colon/em-dash/hyphen
        ;         (those signal the sentence is continuing on the next line)
        Else If (w.endsCommaLike || RegExMatch(w.text, "[-—]$"))
            qualifies := False
        ; Rule E: last word must not be a bare coordinating conjunction
        Else If (RegExMatch(StrLower(w.text), "^(and|or|but|nor|so|yet)$"))
            qualifies := False
        ; Rule F: the NEXT word (on the following line) must start with a capital letter.
        ;         Lowercase → the sentence is continuing across the line break (wrapped OCR).
        Else If (i < Words.Length) {
            nextFirst := SubStr(Words[i+1].text, 1, 1)
            If !RegExMatch(nextFirst, "[A-Z]")
                qualifies := False
        }
        If (qualifies)
            Words[i].endsListItem := True
        lineStart := i + 1
    }
}

; Does this word's text end with a mid-sentence pause marker (, ; : or em-dash U+2014)?
IsCommaLikeEnd(word) {
    ; Strip trailing closing-punctuation first, as with IsSentenceEnd
    rdq := Chr(0x201D)
    rsq := Chr(0x2019)
    emdash := Chr(0x2014)
    trimmed := RegExReplace(word, '["\)\]' . "'" . rdq . rsq . ']+$', "")
    If (trimmed = "")
        Return False
    last := SubStr(trimmed, -1)
    Return (last = "," || last = ";" || last = ":" || last = emdash)
}

; Subset of comma-like ends that are STRONG enough to clip a chunk. Commas alone
; aren't — they're too frequent and would make chunks too short. Semicolons, colons,
; and em-dashes are real pause points.
IsStrongCommaLike(word) {
    rdq := Chr(0x201D)
    rsq := Chr(0x2019)
    emdash := Chr(0x2014)
    trimmed := RegExReplace(word, '["\)\]' . "'" . rdq . rsq . ']+$', "")
    If (trimmed = "")
        Return False
    last := SubStr(trimmed, -1)
    Return (last = ";" || last = ":" || last = emdash)
}

; ----------------------------------------------------------------------------------------------------------------------
; Compute a difficulty weight for a single word token (as it appears in source, with
; punctuation still attached). Smaller weight = read faster. Used only when
; Cfg.SmartPacing is on.
;   Stopwords ('the', 'of', ...):         Pacing.StopwordWeight      (fast)
;   1-syllable non-stopwords:              Pacing.MonoWeight          (baseline)
;   Polysyllabic:      MonoWeight + (syllables-1) * ExtraSyllableWeight
; ----------------------------------------------------------------------------------------------------------------------
WeighWord(word) {
    ; Strip non-letter characters for syllable counting and stopword matching
    clean := RegExReplace(word, "[^A-Za-z]", "")
    If (clean = "")
        Return Pacing.MonoWeight   ; fallback for punctuation-only tokens
    clean := StrLower(clean)
    If (IsStopword(clean))
        Return Pacing.StopwordWeight
    syl := CountSyllables(clean)
    If (syl <= 1)
        Return Pacing.MonoWeight
    Return Pacing.MonoWeight + (syl - 1) * Pacing.ExtraSyllableWeight
}

; Heuristic English syllable count. Not perfect, but good enough for relative weighting.
;   1. Count groups of consecutive vowels (aeiouy).
;   2. Subtract 1 for a silent trailing 'e', unless the word is only 3 letters or shorter.
;   3. Minimum 1.
CountSyllables(word) {
    ; Count vowel groups
    count := 0
    pos := 1
    While (pos := RegExMatch(word, "[aeiouy]+", &m, pos)) {
        count++
        pos += StrLen(m[0])
    }
    ; Silent-e adjustment
    If (StrLen(word) > 3 && SubStr(word, -1) = "e")
        count--
    Return Max(1, count)
}

; A ~100-word English stopword list. Covers articles, common verbs, prepositions,
; pronouns, conjunctions — the function words that your eye reads without effort.
IsStopword(lowercaseWord) {
    static Set := BuildStopwordSet()
    Return Set.Has(lowercaseWord)
}

BuildStopwordSet() {
    words := ["a","an","the"
            , "and","or","but","so","yet","nor","for","as","if","than","that","though","while","when","where","because","since"
            , "of","in","on","at","to","from","by","with","about","into","onto","upon","over","under","out","off","up","down","is"
            , "i","me","my","mine","we","us","our","ours","you","your","yours","he","him","his","she","her","hers","it","its","they","them","their","theirs"
            , "am","are","was","were","be","been","being","have","has","had","do","does","did","will","would","shall","should","can","could","may","might","must"
            , "this","that","these","those","there","here","then","now","also","not","no","yes","very","just","only","even","still","too"
            , "what","which","who","whom","whose","how","why"]
    s := Map()
    s.CaseSense := False
    For _, w in words
        s[w] := True
    Return s
}

; Does this word's text end with sentence-terminating punctuation?
; Accepts trailing closing quotes/parens after the terminator: e.g. said."  or  (really?)
; Returns False for common abbreviations ending in '.' like Mr. Dr. e.g. — these
; shouldn't trigger sentence pauses.
IsSentenceEnd(word) {
    ; Strip trailing closing-punctuation: " ' ) ] and Unicode right-quotes.
    rdq := Chr(0x201D)   ; right double quote
    rsq := Chr(0x2019)   ; right single quote
    trimmed := RegExReplace(word, '["\)\]' . "'" . rdq . rsq . ']+$', "")
    If (trimmed = "")
        Return False
    last := SubStr(trimmed, -1)
    If !(last = "." || last = "!" || last = "?" || last = Chr(0x2026))
        Return False
    ; If the "sentence end" is actually a known abbreviation, it's not a sentence end.
    If (last = "." && IsAbbreviation(trimmed))
        Return False
    Return True
}

; A small English abbreviation exclusion list — words that commonly end in '.' but
; don't end a sentence. Case-insensitive comparison against the trimmed token.
IsAbbreviation(trimmedWord) {
    static Set := BuildAbbreviationSet()
    Return Set.Has(StrLower(trimmedWord))
}

BuildAbbreviationSet() {
    abbrevs := ["mr.","mrs.","ms.","dr.","st.","jr.","sr.","prof.","rev.","hon."
              , "vs.","etc.","e.g.","i.e.","cf.","ca.","ed.","eds.","vol.","vols."
              , "fig.","figs.","no.","nos.","p.","pp.","ch.","chs.","sec.","secs."
              , "jan.","feb.","mar.","apr.","jun.","jul.","aug.","sep.","sept.","oct.","nov.","dec."
              , "mon.","tue.","wed.","thu.","fri.","sat.","sun."
              , "inc.","ltd.","co.","corp.","dept."
              , "a.m.","p.m.","u.s.","u.s.a.","u.k."]
    s := Map()
    s.CaseSense := False
    For _, a in abbrevs
        s[a] := True
    Return s
}

; ----------------------------------------------------------------------------------------------------------------------
; Play / pause / restart
; ----------------------------------------------------------------------------------------------------------------------
TogglePlay(*) {
    If (Words.Length = 0)
        Return
    If (IsPlaying)
        StopPlay()
    Else
        StartPlay()
}

StartPlay() {
    global IsPlaying
    If (Words.Length = 0)
        Return
    ; If the user has placed the caret elsewhere (e.g. clicked a word), resume from there.
    ; During normal operation we leave the caret at end-of-last-highlighted-word, so this
    ; also naturally handles pause/resume.
    sel := RE.GetSel()
    caret := sel.S   ; start of selection (or bare caret position if nothing selected)
    If (caret > 0)
        JumpToCharPos(caret)
    If (CurIdx >= Words.Length)
        Restart()
    IsPlaying := True
    BtnPlay.Text := "❚❚ Pause"
    ; Kick off the first step immediately. StepWord will reschedule itself with a
    ; per-chunk dwell time computed from the content it highlights.
    StepWord()
}

StopPlay() {
    global IsPlaying
    IsPlaying := False
    BtnPlay.Text := "▶ Play"
    SetTimer(StepTimer, 0)
}

Restart(*) {
    global CurIdx, PrevStart, PrevEnd
    StopPlay()
    ResetDwellBuffer()
    ClearHighlight()
    CurIdx := 0
    PrevStart := PrevEnd := -1
    RE.SetSel(0, 0)
    RE.ScrollCaret()
    DllCall("HideCaret", "Ptr", RE.Hwnd)
}

; ----------------------------------------------------------------------------------------------------------------------
; One tick of the reading loop. Self-rescheduling: after highlighting, computes a
; content-aware dwell time and schedules the next tick.
;   Jumping (overlap off): highlight the next chunk-sized block, clipped at sentence
;                          boundaries. CurIdx advances to the end of the clipped chunk.
;   Sliding (overlap on):  highlight a chunk-sized window ending at CurIdx+1, advance
;                          CurIdx by 1. (Sentence clipping does not apply.)
; In both cases, CurIdx means "index of the latest word consumed".
; ----------------------------------------------------------------------------------------------------------------------
StepWord(*) {
    global CurIdx, PrevStart, PrevEnd
    If (CurIdx >= Words.Length) {
        StopPlay()
        Return
    }
    ClearHighlight()
    chunk := Max(1, Cfg.ChunkSize)
    If (Cfg.Overlap) {
        ; Sliding window: lead word advances by 1; window spans [lead - chunk + 1 .. lead]
        leadIdx  := CurIdx + 1
        startIdx := Max(1, leadIdx - chunk + 1)
        endIdx   := leadIdx
        newCur   := leadIdx
    } Else {
        ; Jumping window: next chunk-sized block, clipped so we never cross a strong
        ; boundary. Boundaries that clip:
        ;   - Paragraph end                                  (always)
        ;   - Sentence end                                   (when SentencePause on)
        ;   - List-item end                                  (when ListPauses on)
        ;   - Strong mid-sentence end: ; : em-dash           (when SentencePause on)
        ; Plain commas do NOT clip — too frequent, would make chunks tiny. If a comma
        ; happens to land at a chunk end, ComputeDwellMs applies its multiplier anyway.
        ; The boundary word itself is INCLUDED — we stop AT it so you see its final punct.
        startIdx := CurIdx + 1
        endIdx   := Min(CurIdx + chunk, Words.Length)
        Loop endIdx - startIdx + 1 {
            i := startIdx + A_Index - 1
            stopHere := Words[i].endsSentence || Words[i].endsParagraph
            If (Cfg.ListPauses && Words[i].endsListItem)
                stopHere := True
            If (Cfg.SentencePause && Words[i].endsCommaLike && IsStrongCommaLike(Words[i].text))
                stopHere := True
            If (stopHere) {
                endIdx := i
                Break
            }
        }
        newCur := endIdx
    }
    startOff := Words[startIdx].start
    endOff   := Words[endIdx].end
    RE.SetSel(startOff, endOff)
    RE.SetFont({BkColor: Cfg.HighlightColor})
    RE.SetSel(endOff, endOff)           ; collapse so the blue selection rectangle is invisible
    DllCall("HideCaret", "Ptr", RE.Hwnd)
    If (Cfg.CenterScroll)
        ScrollToCenter(startOff)
    Else
        RE.ScrollCaret()
    PrevStart := startOff
    PrevEnd   := endOff
    CurIdx    := newCur
    LblStatus.Text := Format("Word {1} of {2}  ({3}%)", CurIdx, Words.Length, Round(CurIdx / Words.Length * 100))
    ; Schedule the next tick with a dwell time appropriate for what we just highlighted.
    dwell := ComputeDwellMs(startIdx, endIdx)
    ; Feed rolling dwell buffer: store ms-per-word so chunk size doesn't skew the average.
    UpdateDwellBuffer(dwell / (endIdx - startIdx + 1))
    UpdateTimeRemaining()
    SetTimer(StepTimer, -dwell)   ; negative = one-shot
}

ClearHighlight() {
    global PrevStart, PrevEnd
    If (PrevStart < 0 || PrevEnd <= PrevStart)
        Return
    RE.SetSel(PrevStart, PrevEnd)
    RE.SetFont({BkColor: "Auto"})
    RE.SetSel(PrevEnd, PrevEnd)
    DllCall("HideCaret", "Ptr", RE.Hwnd)
    PrevStart := PrevEnd := -1
}

; ----------------------------------------------------------------------------------------------------------------------
; Scroll the RichEdit so the highlighted word sits vertically centered in the control.
; Strategy:
;   1. EM_POSFROMCHAR gives the pixel Y of the target character (relative to control client area).
;   2. A second EM_POSFROMCHAR on the character one line below gives us the line height.
;   3. EM_GETFIRSTVISIBLELINE tells us which line is currently at the top.
;   4. EM_LINEFROMCHAR converts a char offset to a line number.
;   5. We compute how many lines to scroll so the target line lands at the vertical midpoint,
;      then call EM_LINESCROLL to apply the delta.
; Edge cases: near the top or bottom of the document, we just let it scroll as far as it can —
; the control clamps gracefully and won't over-scroll.
; ----------------------------------------------------------------------------------------------------------------------
ScrollToCenter(charOffset) {
    static EM_POSFROMCHAR         := 0x00D6
    static EM_LINEFROMCHAR        := 0x00C9
    static EM_GETFIRSTVISIBLELINE := 0x00CE
    static EM_LINESCROLL          := 0x00B6
    static EM_LINEINDEX           := 0x00BB

    hwnd := RE.Hwnd

    ; --- Which line is currently at the top of the viewport? ---
    firstVisible := SendMessage(EM_GETFIRSTVISIBLELINE, 0, 0, hwnd)

    ; --- Line height: measure two consecutive VISIBLE lines so Y coords are in-range ---
    ; EM_POSFROMCHAR returns coords relative to the control's client area, so the lines
    ; must be visible (on-screen) for the values to be meaningful. Using line 0 when the
    ; view has scrolled past it returns garbage (negative or wrapped Y).
    lineH := 0
    refLine0 := firstVisible
    refLine1 := firstVisible + 1
    idx0 := SendMessage(EM_LINEINDEX, refLine0, 0, hwnd)
    idx1 := SendMessage(EM_LINEINDEX, refLine1, 0, hwnd)
    If (idx0 >= 0 && idx1 > idx0) {
        y0 := (SendMessage(EM_POSFROMCHAR, idx0, 0, hwnd) >> 16) & 0xFFFF
        y1 := (SendMessage(EM_POSFROMCHAR, idx1, 0, hwnd) >> 16) & 0xFFFF
        If (y1 > y0)
            lineH := y1 - y0
    }
    If (lineH <= 0)
        lineH := Cfg.FontSize + 4   ; fallback: approximate from font size

    ; --- Control client height ---
    RE.GetPos(, , , &reH)
    visibleLines := Max(1, reH // lineH)
    halfLines    := visibleLines // 2

    ; --- Which line does our target character sit on? ---
    targetLine := SendMessage(EM_LINEFROMCHAR, charOffset, 0, hwnd)

    ; --- Desired first-visible line to center the target ---
    ; Clamp to 0: when near the top there isn't enough content above to center,
    ; so stay at top rather than oscillating.
    desiredFirst := Max(0, targetLine - halfLines)

    ; --- Scroll delta (positive = scroll down, negative = scroll up) ---
    delta := desiredFirst - firstVisible
    If (delta != 0)
        SendMessage(EM_LINESCROLL, 0, delta, hwnd)
}

; ----------------------------------------------------------------------------------------------------------------------
; Compute dwell time (ms) for a chunk spanning Words[startIdx..endIdx].
; Factors in (in priority order — first match wins for the boundary multiplier):
;   - Paragraph-end pause     (ParagraphMult)
;   - Sentence-end pause      (SentenceMult)        — requires SentencePause on
;   - List-item-end pause     (ListItemMult)        — requires ListPauses on
;   - Semicolon/Colon/Em-dash (SemicolonColonMult)  — requires SentencePause on
;   - Comma-end pause         (CommaMult)           — requires SentencePause on
; Smart-pacing word weights are applied multiplicatively BEFORE the boundary mult.
; In overlap mode, chunk is effectively 1 new word per tick; sentence/list/comma
; multipliers don't apply (they'd disrupt the sliding feel). Smart pacing still works.
; ----------------------------------------------------------------------------------------------------------------------
ComputeDwellMs(startIdx, endIdx) {
    wpm := Max(50, Cfg.WPM)
    If (Cfg.Overlap) {
        base := 60000 / wpm
        If (Cfg.SmartPacing)
            base *= Words[endIdx].weight
        Return Max(1, Round(base))
    }
    wordsInChunk := endIdx - startIdx + 1
    base := 60000 * wordsInChunk / wpm
    If (Cfg.SmartPacing) {
        totalW := 0.0
        Loop wordsInChunk
            totalW += Words[startIdx + A_Index - 1].weight
        base *= (totalW / wordsInChunk)
    }
    ; Boundary-pause multiplier (priority: paragraph > sentence > list > ; : — > , )
    lastW := Words[endIdx]
    If (lastW.endsParagraph) {
        base *= Pacing.ParagraphMult
    } Else If (Cfg.SentencePause && lastW.endsSentence) {
        base *= Pacing.SentenceMult
    } Else If (Cfg.ListPauses && lastW.endsListItem) {
        base *= Pacing.ListItemMult
    } Else If (Cfg.SentencePause && lastW.endsCommaLike) {
        ; Differentiate the stronger semicolon/colon/em-dash from a plain comma
        trail := SubStr(RegExReplace(lastW.text, '["\)\]' . "'" . Chr(0x201D) . Chr(0x2019) . ']+$', ""), -1)
        If (trail = "," )
            base *= Pacing.CommaMult
        Else
            base *= Pacing.SemicolonColonMult
    }
    Return Max(1, Round(base))
}

; ----------------------------------------------------------------------------------------------------------------------
; Event handlers for slider / font / chunk / overlap.
; With self-rescheduling timer, we don't need to call SetTimer here — the next tick
; of StepWord will pick up the new Cfg values naturally.
; ----------------------------------------------------------------------------------------------------------------------
WPMChanged(*) {
    Cfg.WPM := SldWPM.Value
    LblWPM.Text := Cfg.WPM
    SaveSettings()
}

FontChanged(*) {
    Cfg.FontName := DdlFont.Text
    Cfg.FontSize := EdSize.Value
    ApplyFontSettings()
    SaveSettings()
}

ChunkChanged(*) {
    Cfg.ChunkSize := Max(1, EdChunk.Value)
    SaveSettings()
}

OverlapChanged(*) {
    Cfg.Overlap := CbxOverlap.Value ? True : False
    SaveSettings()
}

SentencePauseChanged(*) {
    Cfg.SentencePause := CbxSentence.Value ? True : False
    SaveSettings()
}

ListPausesChanged(*) {
    Cfg.ListPauses := CbxList.Value ? True : False
    SaveSettings()
}

SmartPacingChanged(*) {
    Cfg.SmartPacing := CbxSmart.Value ? True : False
    SaveSettings()
}

CenterScrollChanged(*) {
    Cfg.CenterScroll := CbxCenter.Value ? True : False
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; Debug: show a window listing tokens and their flags for a range around the current
; reading position. Useful for diagnosing why a pause did or didn't fire on a specific
; passage. The window shows 80 words centered on CurIdx (or from word 1 if not started).
; ----------------------------------------------------------------------------------------------------------------------
ShowTokenAnalysis(*) {
    If (Words.Length = 0) {
        MsgBox("No text loaded.", AppName, 64)
        Return
    }
    ; Range: 40 words before CurIdx, 40 after (clamped to valid range)
    center := CurIdx > 0 ? CurIdx : 1
    lo := Max(1, center - 40)
    hi := Min(Words.Length, center + 40)

    dbg := Gui("+Resize +MinSize500x400", "Token analysis")
    dbg.SetFont("s9", "Consolas")
    lv := dbg.AddListView("w900 h500 Grid",
        ["#", "Word", "Sent", "Para", "Line", "List", "Comma", "Weight"])
    For i, w in Words {
        If (i < lo || i > hi)
            Continue
        lv.Add(, i
                , w.text
                , w.endsSentence  ? "Y" : ""
                , w.endsParagraph ? "Y" : ""
                , w.endsLine      ? "Y" : ""
                , w.endsListItem  ? "Y" : ""
                , w.endsCommaLike ? "Y" : ""
                , Format("{:.2f}", w.weight))
    }
    ; Autosize columns
    Loop 8
        lv.ModifyCol(A_Index, "AutoHdr")
    dbg.AddText("y+8", "Showing words " lo "–" hi " of " Words.Length
                     ". Close this window to return.  Ctrl+C = copy all rows as CSV.")
    dbg.OnEvent("Close", (*) => dbg.Destroy())
    dbg.Show()

    ; Ctrl+C: copy all visible LV rows to clipboard as CSV
    HotIfWinActive("ahk_id " dbg.Hwnd)
    Hotkey("^c", CopyTokensToClipboard.Bind(lv))
    HotIfWinActive()

    CopyTokensToClipboard(lvCtrl, *) {
        cols := ["#","Word","Sent","Para","Line","List","Comma","Weight"]
        out  := ""
        ; Header row
        For _, h in cols
            out .= (A_Index = 1 ? "" : ",") '"' h '"'
        out .= "`n"
        ; Data rows — use GetCount() to know exactly how many rows exist
        rowCount := lvCtrl.GetCount()
        Loop rowCount {
            row  := A_Index
            cells := ""
            For c, _ in cols {
                val := lvCtrl.GetText(row, c)
                cells .= (c = 1 ? "" : ",") '"' StrReplace(val, '"', '""') '"'
            }
            out .= cells "`n"
        }
        A_Clipboard := out
        ToolTip("Copied " rowCount " rows to clipboard.")
        SetTimer(() => ToolTip(), -1500)
    }
}

; ----------------------------------------------------------------------------------------------------------------------
; Nudge WPM by delta (used by Left/Right arrow hotkeys). Clamps to the slider's range,
; updates the slider, updates Cfg, and updates the on-screen label. Slider.Value set
; programmatically does not fire OnEvent("Change"), so we update Cfg/label directly.
; ----------------------------------------------------------------------------------------------------------------------
AdjustWPM(delta, *) {
    newVal := Cfg.WPM + delta
    ; Clamp to the slider's configured range (see the Slider Range option)
    newVal := Max(100, Min(1200, newVal))
    If (newVal = Cfg.WPM)
        Return
    SldWPM.Value := newVal
    Cfg.WPM      := newVal
    LblWPM.Text  := newVal
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; Rolling dwell buffer — tracks actual ms-per-word to estimate time remaining.
; ----------------------------------------------------------------------------------------------------------------------
ResetDwellBuffer() {
    global DwellBuf, DwellBufSum
    DwellBuf    := []
    DwellBufSum := 0.0
    LblTimeRemain.Text := ""
}

UpdateDwellBuffer(msPerWord) {
    global DwellBuf, DwellBufSum, DwellBufMax
    If (DwellBuf.Length >= DwellBufMax) {
        DwellBufSum -= DwellBuf[1]
        DwellBuf.RemoveAt(1)
    }
    DwellBuf.Push(msPerWord)
    DwellBufSum += msPerWord
}

UpdateTimeRemaining() {
    global DwellBuf, DwellBufSum, DwellMinSamples, TimeRemainingUpdateMs
    static LastUpdate := 0
    n := DwellBuf.Length
    If (n < DwellMinSamples || Words.Length = 0) {
        LblTimeRemain.Text := ""
        LastUpdate := 0   ; reset so it shows promptly once samples accumulate
        Return
    }
    now := A_TickCount
    If (now - LastUpdate < TimeRemainingUpdateMs)
        Return
    LastUpdate    := now
    avgMsPerWord  := DwellBufSum / n
    wordsLeft     := Words.Length - CurIdx
    totalMs       := avgMsPerWord * wordsLeft
    totalSec      := Round(totalMs / 1000)
    mins          := totalSec // 60
    secs          := Mod(totalSec, 60)
    LblTimeRemain.Text := Format("[{1}:{2:02}]", mins, secs)
}
; Only acts when the cursor is over the WPM slider; flips the direction so
; wheel-up = increase WPM and wheel-down = decrease WPM.
; wParam high word = signed wheel delta (positive = up, negative = down, multiples of 120).
; We return 0 to suppress the default slider handling so it doesn't also fire.
; ----------------------------------------------------------------------------------------------------------------------
OnMouseWheel(wParam, lParam, msg, hwnd) {
    ; Check cursor is over the slider
    MouseGetPos(, , , &ctrlHwnd, 2)
    If (ctrlHwnd != SldWPM.Hwnd)
        Return   ; let other controls handle their own wheel normally
    ; Extract signed delta from high word of wParam
    delta := (wParam >> 16) & 0xFFFF
    If (delta >= 0x8000)              ; two's-complement negative
        delta -= 0x10000
    ; Each notch = 120; positive delta = wheel up = increase WPM
    steps := delta / 120
    AdjustWPM(Round(steps * WPMHotkeyStep))
    Return 0   ; suppress default handling
}
ApplyFontSettings() {
    global PrevStart, PrevEnd
    RE.SetDefaultFont({Name: Cfg.FontName, Size: Cfg.FontSize, Color: Cfg.TextColor})
    ; Also recolor existing content
    RE.SetSel(0, -1)
    RE.SetFont({Name: Cfg.FontName, Size: Cfg.FontSize, Color: Cfg.TextColor, BkColor: "Auto"})
    RE.SetSel(0, 0)
    ; Re-apply current highlight if any
    If (PrevStart >= 0 && PrevEnd > PrevStart) {
        RE.SetSel(PrevStart, PrevEnd)
        RE.SetFont({BkColor: Cfg.HighlightColor})
        RE.SetSel(PrevEnd, PrevEnd)
    }
}

ApplyBackColor() {
    RE.SetBkgndColor(Cfg.BackColor)
}

; ----------------------------------------------------------------------------------------------------------------------
; Color picker button handler
; ----------------------------------------------------------------------------------------------------------------------
PickColor(which) {
    current := Cfg.%which%
    new := ChooseColor(current, MainGui.Hwnd)
    If (new = "")
        Return
    Cfg.%which% := new
    Switch which {
        Case "HighlightColor":
            SwHL.Opt("+Background" Fmt(new))
            SwHL.Redraw()
            If (PrevStart >= 0 && PrevEnd > PrevStart) {
                RE.SetSel(PrevStart, PrevEnd)
                RE.SetFont({BkColor: new})
                RE.SetSel(PrevEnd, PrevEnd)
            }
        Case "TextColor":
            SwTx.Opt("+Background" Fmt(new))
            SwTx.Redraw()
            ApplyFontSettings()
        Case "BackColor":
            SwBg.Opt("+Background" Fmt(new))
            SwBg.Redraw()
            ApplyBackColor()
    }
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; System color picker (ChooseColorW common dialog)
; Returns RGB integer, or "" on cancel.
; CHOOSECOLORW struct layout (x64, 72 bytes total):
;   0:  DWORD  lStructSize
;   8:  HWND   hwndOwner
;   16: HWND   hInstance
;   24: COLORREF rgbResult (4 bytes + 4 padding)
;   32: COLORREF* lpCustColors
;   40: DWORD  Flags (+ 4 padding)
;   48: LPARAM lCustData
;   56: LPCCHOOKPROC lpfnHook
;   64: LPCTSTR lpTemplateName
; x86 layout is 36 bytes with 4-byte alignment.
; ----------------------------------------------------------------------------------------------------------------------
ChooseColor(initial := 0xFFFFFF, hwndOwner := 0) {
    static CustomColors := Buffer(64, 0)  ; 16 COLORREFs, persisted across calls
    bgr := RGBtoBGR(initial)
    If (A_PtrSize = 8) {
        cc := Buffer(72, 0)
        NumPut("UInt", 72,          cc, 0)        ; lStructSize
        NumPut("Ptr",  hwndOwner,   cc, 8)        ; hwndOwner
        NumPut("Ptr",  0,           cc, 16)       ; hInstance
        NumPut("UInt", bgr,         cc, 24)       ; rgbResult
        NumPut("Ptr",  CustomColors.Ptr, cc, 32)  ; lpCustColors
        NumPut("UInt", 0x03,        cc, 40)       ; Flags = CC_RGBINIT | CC_FULLOPEN
        resultOff := 24
    } Else {
        cc := Buffer(36, 0)
        NumPut("UInt", 36,          cc, 0)
        NumPut("Ptr",  hwndOwner,   cc, 4)
        NumPut("Ptr",  0,           cc, 8)
        NumPut("UInt", bgr,         cc, 12)
        NumPut("Ptr",  CustomColors.Ptr, cc, 16)
        NumPut("UInt", 0x03,        cc, 20)
        resultOff := 12
    }
    If !DllCall("comdlg32\ChooseColorW", "Ptr", cc.Ptr, "Int")
        Return ""   ; user cancelled
    newBGR := NumGet(cc, resultOff, "UInt")
    Return BGRtoRGB(newBGR)
}

RGBtoBGR(rgb) => ((rgb & 0xFF0000) >> 16) | (rgb & 0x00FF00) | ((rgb & 0x0000FF) << 16)
BGRtoRGB(bgr) => ((bgr & 0xFF0000) >> 16) | (bgr & 0x00FF00) | ((bgr & 0x0000FF) << 16)

; Format an RGB integer as 6-digit hex for Gui option strings (e.g., "FFFF00")
Fmt(rgb) => Format("{:06X}", rgb & 0xFFFFFF)

; Try to pick a DDL item by text; if not present, pick first
TryPickDDL(ddl, text) {
    Try {
        arr := ControlGetItems(ddl.Hwnd)
        For i, v in arr {
            If (v = text) {
                ddl.Value := i
                Return
            }
        }
    }
    ddl.Value := 1
}

; ----------------------------------------------------------------------------------------------------------------------
; WM_LBUTTONDBLCLK handler (registered globally, filtered by HWND).
; When the user double-clicks a word in the RichEdit, jump to that word and start playing.
; ----------------------------------------------------------------------------------------------------------------------
OnDoubleClick(wParam, lParam, msg, hwnd) {
    ; Only react to double-clicks inside our RichEdit control
    If (hwnd != RE.Hwnd)
        Return
    ; Let RichEdit process the default double-click first (it selects the word),
    ; then read the selection start as the jump target.
    ; We defer via a very short timer so our work runs AFTER the control's default handling.
    SetTimer(JumpToSelectionAndPlay, -10)
}

; ----------------------------------------------------------------------------------------------------------------------
; WM_SETFOCUS handler — RichEdit recreates its caret every time it gains focus.
; We immediately replace it with a zero-width caret, keeping it invisible permanently
; through blink cycles and focus changes.
; ----------------------------------------------------------------------------------------------------------------------
OnRichEditFocus(wParam, lParam, msg, hwnd) {
    If (hwnd != RE.Hwnd)
        Return
    ; CreateCaret with width=0 replaces whatever caret RichEdit just made.
    ; HideCaret then suppresses it for this focus session.
    DllCall("CreateCaret", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0)
    DllCall("HideCaret",   "Ptr", hwnd)
}

JumpToSelectionAndPlay() {
    global IsPlaying
    sel := RE.GetSel()
    ; On double-click RichEdit selects the word: sel.S is the word's start.
    ; If the click landed in whitespace, sel.S is still the caret position there.
    ; Stop any running/paused timer first so we don't fight with a pending tick,
    ; then jump and restart — bypassing StartPlay's caret-re-read so the
    ; double-clicked position always wins, even when paused.
    StopPlay()
    JumpToCharPos(sel.S)
    IsPlaying := True
    BtnPlay.Text := "❚❚ Pause"
    StepWord()
}

; ----------------------------------------------------------------------------------------------------------------------
; Set the current word index to the word at (or nearest after) a given character offset.
; ----------------------------------------------------------------------------------------------------------------------
JumpToCharPos(charPos) {
    global CurIdx, PrevStart, PrevEnd
    If (Words.Length = 0)
        Return
    ClearHighlight()
    idx := FindWordIndexAtChar(charPos)
    ; CurIdx represents "last highlighted word index". StepWord advances to CurIdx+1.
    ; So to have the target word highlighted on the next tick, set CurIdx = idx - 1.
    CurIdx := Max(0, idx - 1)
    PrevStart := PrevEnd := -1
}

; Binary search for the word whose span contains charPos, or the next word after it.
FindWordIndexAtChar(charPos) {
    lo := 1
    hi := Words.Length
    If (charPos <= Words[1].start)
        Return 1
    If (charPos >= Words[hi].end)
        Return hi
    While (lo <= hi) {
        mid := (lo + hi) // 2
        w := Words[mid]
        If (charPos < w.start)
            hi := mid - 1
        Else If (charPos >= w.end)
            lo := mid + 1
        Else
            Return mid   ; charPos is inside this word's span
    }
    ; charPos fell into whitespace between words; 'lo' now points to the next word
    Return Min(lo, Words.Length)
}

; ----------------------------------------------------------------------------------------------------------------------
; Settings persistence
; ----------------------------------------------------------------------------------------------------------------------
LoadSettings() {
    If !FileExist(IniFile)
        Return
    Cfg.WPM            := Integer(IniRead(IniFile, "Reader", "WPM",            Cfg.WPM))
    Cfg.ChunkSize      := Integer(IniRead(IniFile, "Reader", "ChunkSize",      Cfg.ChunkSize))
    Cfg.Overlap        := Integer(IniRead(IniFile, "Reader", "Overlap",        Cfg.Overlap ? 1 : 0)) ? True : False
    Cfg.SentencePause  := Integer(IniRead(IniFile, "Reader", "SentencePause",  Cfg.SentencePause ? 1 : 0)) ? True : False
    Cfg.ListPauses     := Integer(IniRead(IniFile, "Reader", "ListPauses",     Cfg.ListPauses ? 1 : 0)) ? True : False
    Cfg.SmartPacing    := Integer(IniRead(IniFile, "Reader", "SmartPacing",    Cfg.SmartPacing ? 1 : 0)) ? True : False
    Cfg.CenterScroll   := Integer(IniRead(IniFile, "Reader", "CenterScroll",   Cfg.CenterScroll ? 1 : 0)) ? True : False
    Cfg.HighlightColor := Integer(IniRead(IniFile, "Colors", "HighlightColor", Cfg.HighlightColor))
    Cfg.TextColor      := Integer(IniRead(IniFile, "Colors", "TextColor",      Cfg.TextColor))
    Cfg.BackColor      := Integer(IniRead(IniFile, "Colors", "BackColor",      Cfg.BackColor))
    Cfg.FontName       := IniRead(IniFile, "Font", "Name", Cfg.FontName)
    Cfg.FontSize       := Integer(IniRead(IniFile, "Font", "Size", Cfg.FontSize))
    Cfg.GuiW           := Integer(IniRead(IniFile, "Window", "W", Cfg.GuiW))
    Cfg.GuiH           := Integer(IniRead(IniFile, "Window", "H", Cfg.GuiH))
    Cfg.LastFile       := IniRead(IniFile, "Session", "LastFile", "")
    ; Load recent files — skip any that no longer exist on disk
    RecentFiles := []
    Loop RecentFilesMax {
        path := IniRead(IniFile, "Recent", "File" A_Index, "")
        If (path != "" && FileExist(path))
            RecentFiles.Push(path)
    }
}

SaveSettings() {
    IniWrite(Cfg.WPM,                  IniFile, "Reader",  "WPM")
    IniWrite(Cfg.ChunkSize,             IniFile, "Reader",  "ChunkSize")
    IniWrite(Cfg.Overlap       ? 1 : 0, IniFile, "Reader",  "Overlap")
    IniWrite(Cfg.SentencePause ? 1 : 0, IniFile, "Reader",  "SentencePause")
    IniWrite(Cfg.ListPauses    ? 1 : 0, IniFile, "Reader",  "ListPauses")
    IniWrite(Cfg.SmartPacing   ? 1 : 0, IniFile, "Reader",  "SmartPacing")
    IniWrite(Cfg.CenterScroll  ? 1 : 0, IniFile, "Reader",  "CenterScroll")
    IniWrite(Cfg.HighlightColor, IniFile, "Colors",  "HighlightColor")
    IniWrite(Cfg.TextColor,      IniFile, "Colors",  "TextColor")
    IniWrite(Cfg.BackColor,      IniFile, "Colors",  "BackColor")
    IniWrite(Cfg.FontName,       IniFile, "Font",    "Name")
    IniWrite(Cfg.FontSize,       IniFile, "Font",    "Size")
    IniWrite(Cfg.GuiW,           IniFile, "Window",  "W")
    IniWrite(Cfg.GuiH,           IniFile, "Window",  "H")
    IniWrite(Cfg.LastFile,       IniFile, "Session", "LastFile")
    ; Save recent files list — write all slots, clearing unused ones
    Loop RecentFilesMax {
        val := (A_Index <= RecentFiles.Length) ? RecentFiles[A_Index] : ""
        IniWrite(val, IniFile, "Recent", "File" A_Index)
    }
}
