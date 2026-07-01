; ======================================================================================================================
; SpeedReader.ahk — A speed reading trainer for plain-text files
; Author: Steve (kunkel321) with Claude (Anthropic)
; Version Date: 7-1-2026
; Requires: AutoHotkey v2.0+  |  RichEdit.ahk by just-me (place in Tools\ folder)
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
;  Portable mode (recommended): rename AutoHotkey64.exe to SpeedReader.exe and place it
;  in the same folder as SpeedReader.ahk and RichEdit.ahk.  No installation needed.
;  Standard mode: run SpeedReader.ahk directly with AHK v2 installed on the machine.
;  Either way, RichEdit.ahk must be in the same folder as SpeedReader.ahk.
;  1. On first run, srSettings.ini is created automatically with sensible defaults.
;  2. Open a .txt file via File > Open, by dragging a file onto the window, or by
;     choosing from the recent-files list in the File menu.
;  3. Press Play (or the Down arrow key) to begin.  Press again to pause.
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
;  Focus search box     Ctrl+F  (pauses the pacer if running; selects existing text)
;  Recent files         Numbered list in the File menu (files that no longer exist are omitted)
;  Resume position      When a file is re-opened that has a saved position, a prompt offers
;                         to resume from the last reading point or start over.
;                         Position is saved automatically on pause and on window close.
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
;  Read Aloud            Speaks the text using Windows' built-in SAPI5 text-to-speech.
;                         SAPI is queued one sentence at a time; within a sentence the
;                         highlight is paced by the same WPM/weighted dwell-time math the
;                         silent pacer uses (some SAPI voices report per-word timing too
;                         unreliably to sync to directly), and resyncs to each sentence's
;                         last word once SAPI actually finishes speaking it. Only available
;                         at or below TTSMaxWPM (see the tunables near the top of the
;                         script) since spoken word stops being intelligible well before
;                         the top of the WPM slider's range; the checkbox disables itself
;                         automatically above that speed, and re-enables itself when WPM
;                         drops back down. Chunk / Overlap / Sentence pause / List pauses /
;                         Smart pacing are all timer-engine concepts and are grayed out
;                         while Read Aloud is active. Play/Pause and double-click-to-jump
;                         work the same as always. The Voice dropdown next to the checkbox
;                         lists every SAPI voice installed on this machine; "(Default
;                         voice)" leaves whatever Windows considers the default in place.
;                         Changing the voice takes effect on the next launch, not
;                         immediately — restart SpeedReader after picking a new one.
;
; COLOR / FONT / SEARCH ROW  (bottom band, Row 1)
; -------------------------
;  Highlight / Text / Background
;                       Clickable colored buttons — click to open the Windows color picker.
;                         Changes apply immediately to live text.
;  Font                 Drop-down of preset font faces (condensed).
;  Search               Incremental search box — results highlighted as you type (debounced).
;                         Literal by default — "first second" matches the exact phrase,
;                         including punctuation ("Mr. Darcy" matches literally).  Matching
;                         is case-insensitive and can span multiple words.
;                         Regex mode: prefix the term with '/' (optional trailing '/'):
;                           /first\s+second/   — first + any whitespace + second
;                           /\bthe\s+\w+ing\b/ — 'the' followed by an -ing word
;                           /^Chapter \d+/m    — multi-line anchors work
;                         Invalid regex patterns show a brief error in the status bar.
;                         Ctrl+F focuses the search box (pauses the pacer if running).
;                         F3 advances to the next match (honors current mode).
;                         Disabled while the pacer is running; re-enabled on pause.
;                         Clearing the box removes the search highlight immediately.
;
; MENUS
; -----
;  File > Open                  Standard open dialog, filtered to .txt files  (Ctrl+O)
;  File > Convert PDF/EPUB/TXT… Launches TextExtractor.ahk companion tool
;  File > Open srSettings.ini     Opens the INI in your default text editor
;  File > Recently converted    Submenu of *.txt files in the Converted\ subfolder (newest first)
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
; TEXTEXTRACTOR INTEGRATION
; -------------------------
;  SpeedReader polls srSettings.ini every 1.5 s for a new TEConvertedAt timestamp written
;  by TextExtractor after each successful conversion.  When a new stamp is detected the
;  converted file is loaded silently; the status bar shows the filename.
;  The polling only fires when the SpeedReader window is active, so there are no stale
;  loads while the user is working in TextExtractor.
;
; SETTINGS FILE  (srSettings.ini, auto-created next to the script on first run)
; -------------
;  All GUI settings save automatically on change and restore on next launch.
;  [Reader]   WPM, ChunkSize, Overlap, SentencePause, ListPauses, SmartPacing, CenterScroll
;  [Colors]   HighlightColor, TextColor, BackColor  (stored as decimal RGB integers)
;  [Font]     Name, Size
;  [srWindow] W, H  (saved on close)
;  [Session]  LastFile, TEConvertedAt
;             LastFile is stored as "path" or "path, wordIdx" and auto-loaded on launch.
;             TEConvertedAt is the sentinel timestamp written by TextExtractor.
;  [Recent]   File1 … FileN — each value is "path" or "path, wordIdx".
;             The word index is the saved reading position for that file.
;             Missing files are silently skipped on load.
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
;  SearchFromCurrent    true  → search starts from current reading position (default)
;                       false → search always starts from top of document
;  SearchDebounceMs     Delay (ms) after last keystroke before search fires (default 300)
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
#Include "Tools\RichEdit.ahk"

SetWinDelay -1
SetControlDelay -1

; ======================================================================================================================
; Pacing tunables — adjust these to change the "feel" of pauses and emphasis.
; Each is a multiplier on the baseline per-chunk dwell time (60000 * chunk / WPM).
; ======================================================================================================================
global Pacing := {
    SentenceMult:         2.3,   ; dwell ×1.8 on chunks ending in .!?… (breathing room after a sentence)
    ParagraphMult:        4.5,   ; dwell ×2.5 on chunks ending a paragraph (blank line follows)
    CommaMult:            1.5,  ; dwell ×1.15 on chunks ending in a comma
    SemicolonColonMult:   1.9,   ; dwell ×1.30 on chunks ending in ; : or em-dash
    ListItemMult:         1.40,  ; dwell ×1.40 on chunks ending a detected list item
    ; Intelligent-pacing word weights (applied only when Cfg.SmartPacing is on):
    StopwordWeight:       0.3,   ; 'the', 'of', 'and', ... — read fast
    MonoWeight:           1.0,   ; 1-syllable non-stopword baseline
    ExtraSyllableWeight:  0.6    ; added per syllable beyond the first for polysyllabic words
}

; WPM hotkey step (Left/Right arrows adjust WPM by this amount)
global WPMHotkeyStep := 80

; List-detection heuristic thresholds (for the "List pauses" feature)
global ListMaxWords := 12       ; line must be shorter than this to be a candidate list item

; How often (ms) the time-remaining display refreshes. 1000 = once per second.
global TimeRemainingUpdateMs := 1000

; Maximum number of recent files to remember in the File menu (1–16)
global RecentFilesMax := 9

; Search behaviour
; SearchFromCurrent = true  → first search starts from word at/after CurIdx (context-aware)
; SearchFromCurrent = false → first search always starts from word 1 (top of document)
global SearchFromCurrent := true

; Debounce delay (ms) after the last keystroke before the search fires
global SearchDebounceMs := 300

; ---- Read Aloud (TTS) tunables ----------------------------------------------------------
; Above this WPM, "Read Aloud" is disabled (spoken word is unintelligible much past this,
; and it stops being useful as a reading aid at high speeds anyway).
global TTSMaxWPM := 500
; Approximate calibration for mapping the WPM slider to SAPI's -10..10 Rate scale.
; SAPI's Rate isn't WPM-calibrated; this assumes rate 0 ≈ AvgWpmAtRate0 for the default
; voice and that each rate step changes speed by roughly PctPerStep. Adjust to taste.
global TTSAvgWpmAtRate0 := 180
global TTSPctPerStep    := 0.10
; SVSFlagsAsync = 1, SVSFPurgeBeforeSpeak = 2 — SAPI's own constants, inlined since AHK
; has no COM enum lookup for them. Declared up here (not near the TTS functions below)
; because they must execute before the "end of auto-execute section" Return.
global SVSFlagsAsync        := 1
global SVSFPurgeBeforeSpeak := 2
; SAPI's SpeechVoiceEvents bitmask — a freshly-created SAPI.SpVoice does NOT notify
; word-boundary events by default; EventInterests has to be set explicitly to opt in.
; SVEStartInputStream=2, SVEEndInputStream=4, SVEWordBoundary=32, SVESentenceBoundary=128.
global TTSEventInterests := 2 | 4 | 32 | 128

global DebugLog     := False
global DebugLogFile := A_ScriptDir "\SpeedReader_debug.log"

; Tray icon — An airplane image.
TraySetIcon("imageres.dll", 330)

; ======================================================================================================================
; Global configuration
; ======================================================================================================================
global AppName := "SpeedReader"
global IniFile := A_ScriptDir "\srSettings.ini"

; ---- External URLs — fill these in when known -----------------------------------------------------------------------
global URL_Gutenberg  := "https://www.gutenberg.org/ebooks/results/"
global URL_AhkForum   := "https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140586" 
global URL_GitHub     := "https://github.com/kunkel321/SpeedReader"  
; Defaults — overridden by srSettings.ini if present
global Cfg := {
    WPM:            525,
    ChunkSize:      1,
    Overlap:        False,
    SentencePause:  True,        ; longer dwell at sentence / paragraph boundaries
    ListPauses:     False,       ; detect line-oriented lists and pause at each item
    SmartPacing:    True,        ; weight dwell by word difficulty (stopword/syllables)
    CenterScroll:   True,        ; keep highlighted word vertically centered in the control
    TTSMode:        False,       ; Read Aloud — SAPI speaks and drives the highlight pacing
    TTSVoiceId:     "",          ; SAPI voice token Id; "" = leave SAPI's own default voice
    HighlightColor: 15527806,    ; 0xED7B7E — soft red
    TextColor:      1913944,     ; 0x1D3658 — dark blue
    BackColor:      15198183,    ; 0xE7D5E7 — light lavender
    FontName:       "Verdana",
    FontSize:       14,
    GuiW:           900,
    GuiH:           650,
    LastFile:       ""      ; stored as "path, wordIdx" in the INI
}

; These two must be declared before LoadSettings() runs, because LoadSettings populates them.
global RecentFiles     := []    ; ordered list of recently opened file paths (most recent first)
global RecentPositions := Map() ; lowercase-path → saved word index (loaded from INI CSV)

LoadSettings()

; ======================================================================================================================
; Runtime state
; ======================================================================================================================
global Words       := []       ; array of {start, end} zero-based RichEdit offsets
global FullText    := ""       ; normalized document text — drives phrase/regex search (keep in sync with RE content)
global CurIdx      := 0        ; 0 = not started; otherwise index of last-highlighted word
global PrevStart   := -1       ; start offset of previously highlighted chunk (for un-highlighting)
global PrevEnd     := -1
global IsPlaying   := False
global StepTimer   := StepWord.Bind()   ; bound timer callback

; Read Aloud (TTS) engine state — see StartTTSEngine/StopTTSEngine and the SAPI_* event
; handlers near the bottom of the playback section.
global TTSEngine   := ""       ; SAPI.SpVoice COM object, created lazily on first use
global TTSSpeaking := False    ; True once a sentence-chunk Speak() is queued/active
                                ; (stays True across a soft Pause(), so Resume() can pick back up)
global TTSBaseOffset   := 0    ; FullText char offset where the current sentence-chunk began
global TTSNextWordIdx  := 0    ; index of the next word to queue once the current chunk ends
global TTSChunkEndIdx  := 0    ; last word index of the chunk currently being spoken
global TTSIgnoreNextEndStream := False  ; set on a hard stop that actually purged something
                                         ; in flight — consumed by the very next EndStream,
                                         ; regardless of what it reports, since that one is
                                         ; almost certainly the purge's own async echo
global TTSSubTimer     := TTSSubStep.Bind()  ; drives word-by-word highlighting within a chunk
global TTSVoiceList    := []   ; installed SAPI voices: array of {Id, Name, Token}

; Rolling dwell buffer for time-remaining estimate.
; Stores ms-per-word samples (dwell / words_in_chunk) for the last N ticks.
global DwellBuf     := []      ; circular buffer of ms-per-word samples
global DwellBufMax  := 50      ; how many samples to keep
global DwellBufSum  := 0.0     ; running sum for O(1) average
global DwellMinSamples := 10   ; don't show estimate until we have this many samples

; Search state
global SrchMatchStart := -1    ; char offset of current search highlight start (-1 = none)
global SrchMatchEnd   := -1    ; char offset of current search highlight end
global SrchLastWord   := ""    ; the term that produced the current highlight

; Enumerate installed SAPI voices up front (a throwaway SpVoice, not the lazily-created
; TTSEngine used for actual playback) so the Voice dropdown has choices before the first
; Read Aloud session. Failure here just leaves TTSVoiceList empty — Read Aloud still
; works with SAPI's own default voice, there's just nothing to pick from in the dropdown.
EnumerateTTSVoices() {
    global TTSVoiceList
    TTSVoiceList := []
    Try {
        tmp := ComObject("SAPI.SpVoice")
        voices := tmp.GetVoices()
        Loop voices.Count {
            tok := voices.Item(A_Index - 1)   ; SAPI collections are zero-based
            name := "<unnamed voice>"
            Try name := tok.GetDescription()
            TTSVoiceList.Push({Id: tok.Id, Name: name, Token: tok})
        }
        DBG("EnumerateTTSVoices — found " TTSVoiceList.Length " voice(s)")
    } Catch as e {
        DBG("EnumerateTTSVoices — failed: " e.Message)
    }
}
EnumerateTTSVoices()

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
; The static items (Open, Convert, Settings, separator) are always added first,
; then recently converted submenu (if any), then recent files, then Exit.
global FileMenu := Menu()
FileMenu.Add("&Open...`tCtrl+O", FileOpen)
FileMenu.Add("Con&vert PDF/EPUB/TXT...", LaunchTextExtractor)
FileMenu.Add("Open &srSettings.ini", OpenIniFile)
; Recently converted submenu, recent files, and Exit are appended by RebuildRecentMenu().

; TE output watcher — tracks the last TEConvertedAt stamp we acted on so we don't
; load the same conversion twice.
global TELastStampSeen := ""

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
LblStatus  := MainGui.AddText("x+20 yp+2 w400 h20", "No file loaded.")
LblStatus.SetFont("s13")

; --- RichEdit (middle, resizes) ---------------------------------------------------------------------------------------
global RE := RichEdit(MainGui, "xm y+8 w" (Cfg.GuiW - 16) " h" (Cfg.GuiH - 220))
RE.SetOptions(["READONLY"], "OR")
RE.WordWrap(True)
ApplyFontSettings()
ApplyBackColor()

; --- Bottom band: color pickers + font + search -----------------------------------------------------------------------
RE.GetPos(&reX, &reY, &reW, &reH)
global Row1Y := reY + reH + 6          ; color/font/search row
global Row2Y := Row1Y + 34              ; WPM label row
global Row3Y := Row2Y + 30              ; slider row

; Color swatches — Progress bars at 100% with the c option for bar color and
; Smooth for a solid fill.  Labels are superimposed via BackgroundTrans Text controls.
global SwHL := MainGui.AddProgress("xm y" Row1Y " w80 h24 Smooth c" Fmt(Cfg.HighlightColor), 100)
global SwTx := MainGui.AddProgress("x+4 yp w60 h24 Smooth c" Fmt(Cfg.TextColor), 100)
global SwBg := MainGui.AddProgress("x+4 yp w90 h24 Smooth c" Fmt(Cfg.BackColor), 100)
; Labels superimposed on the swatches via Static controls at the same coords.
; SS_CENTER=0x01, SS_CENTERIMAGE=0x200 (vertically centered), transparent background.
SwHL.GetPos(&shX, &shY, &shW, &shH)
SwTx.GetPos(&stX, &stY, &stW, &stH)
SwBg.GetPos(&sbX, &sbY, &sbW, &sbH)
global LblSwHL := MainGui.AddText("x" shX " y" shY " w" shW " h" shH " +0x01 +0x200 BackgroundTrans", "Highlight")
global LblSwTx := MainGui.AddText("x" stX " y" stY " w" stW " h" stH " +0x01 +0x200 BackgroundTrans", "Text")
global LblSwBg := MainGui.AddText("x" sbX " y" sbY " w" sbW " h" sbH " +0x01 +0x200 BackgroundTrans", "Background")

; Font label and dropdown — positioned explicitly after SwBg since the overlay
; Text labels above may shift AHK's internal x cursor unpredictably.
SwBg.GetPos(&swBgX2, , &swBgW2)
LblFont := MainGui.AddText("x" (swBgX2 + swBgW2 + 12) " y" (Row1Y + 5) " w30", "Font:")
DdlFont := MainGui.AddDropDownList("x+2 yp-5 w90", ["Georgia","Arial","Verdana","Tahoma","Calibri","Consolas","Courier New","Times New Roman"])
TryPickDDL(DdlFont, Cfg.FontName)
DdlFont.OnEvent("Change", FontChanged)

; Search box — fills the remaining width of Row 1.
; Disabled while the pacer is running (enabled in StopPlay, disabled in StartPlay).
DdlFont.GetPos(&ddlX2, , &ddlW2)
LblSearch := MainGui.AddText("x" (ddlX2 + ddlW2 + 14) " y" (Row1Y + 5) " w46", "Search:")
global SrchBox := MainGui.AddEdit("x+2 yp-5 w200 h24", "")
SrchBox.OnEvent("Change", OnSearchChanged)
; F3 = find next match (window-scoped hotkey registered after MainGui.Show)

; Row 2: WPM label + value (large font), time remaining, then checkboxes to the right
LblWPMTitle := MainGui.AddText("xm y" Row2Y " w50 h28 +0x200", "WPM:")
LblWPMTitle.SetFont("s12 Bold")
LblWPM := MainGui.AddText("x+2 yp w50 h28 +0x200", Cfg.WPM)
LblWPM.SetFont("s14 Bold")
LblTimeRemain := MainGui.AddText("x+6 yp w160 h28 +0x200", "")
LblTimeRemain.SetFont("s11")

; Checkboxes live here (Row 2), to the right of the WPM display
CbxOverlap  := MainGui.AddCheckbox("x+10 yp+6", "Overlap")
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

CbxTTS      := MainGui.AddCheckbox("x+14 yp", "Read Aloud")
CbxTTS.Value := Cfg.TTSMode
CbxTTS.OnEvent("Click", TTSModeChanged)
CbxTTS.Enabled := (Cfg.WPM <= TTSMaxWPM)

; Voice picker — "(Default voice)" first, then every installed SAPI voice found by
; EnumerateTTSVoices(). Selection is restored from Cfg.TTSVoiceId if it still matches an
; installed voice; otherwise falls back to "(Default voice)" (e.g. srSettings.ini was
; copied from a different machine with different voices installed).
DdlVoiceChoices := ["(Default voice)"]
For _, v in TTSVoiceList
    DdlVoiceChoices.Push(v.Name)
DdlTTSVoice := MainGui.AddDropDownList("x+8 yp w170", DdlVoiceChoices)
DdlTTSVoice.OnEvent("Change", TTSVoiceChanged)
DdlTTSVoice.Value := 1
For i, v in TTSVoiceList {
    If (v.Id = Cfg.TTSVoiceId) {
        DdlTTSVoice.Value := i + 1
        Break
    }
}

; Row 3: the big slider
SldWPM := MainGui.AddSlider("xm y" Row3Y " w" (Cfg.GuiW - 16) " h40 Range100-1200 TickInterval100 Page50 Line10 ToolTip", Cfg.WPM)
SldWPM.OnEvent("Change", WPMChanged)

; Reflect any loaded TTS setting in the controls that don't apply while it's active,
; and re-validate it against the WPM threshold in case srSettings.ini was hand-edited.
UpdateTTSControlStates()
GateTTSAvailability()

; ======================================================================================================================
; Show GUI and optionally auto-load last file
; ======================================================================================================================
MainGui.Show("w" Cfg.GuiW " h" Cfg.GuiH)

; Remove horizontal scrollbar from RichEdit — word-wrap makes it unnecessary,
; and it leaves an ugly empty trough when the window is resized narrow.
; WS_HSCROLL = 0x00100000
WinSetStyle("-0x100000", "ahk_id " RE.Hwnd)

; Populate the Recent Files menu now that the menu object exists
RebuildRecentMenu()

If (Cfg.LastFile != "" && FileExist(Cfg.LastFile)) {
    savedIdx := RecentPositions.Has(StrLower(Cfg.LastFile)) ? RecentPositions[StrLower(Cfg.LastFile)] : 0
    LoadTextFile(Cfg.LastFile, savedIdx)
}

; Poll for TextExtractor output every 1500 ms.
; CheckForTEOutput only acts when SpeedReader is the foreground window.
SetTimer(CheckForTEOutput, 1500)

; WM_LBUTTONDOWN (0x0201) — catch clicks on the colored swatch progress bars.
; The overlay Text labels are transparent so clicks pass through to the progress bar hwnd.
OnMessage(0x0201, OnSwatchClick)

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
Hotkey("F3",    (*) => SearchFindNext())
Hotkey("^f",    (*) => FocusSearchBox())
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

    ; Row 1 — swatch progress bars + overlay labels + font dropdown + search box
    ; Fixed-width controls placed left-to-right; search box gets whatever remains.
    x := margin
    SwHL.Move(x, r1Y)
    SwHL.GetPos(, , &w1, &hh)
    LblSwHL.Move(x, r1Y, w1, hh)
    x += w1 + 4
    SwTx.Move(x, r1Y)
    SwTx.GetPos(, , &w2, &hh)
    LblSwTx.Move(x, r1Y, w2, hh)
    x += w2 + 4
    SwBg.Move(x, r1Y)
    SwBg.GetPos(, , &w3, &hh)
    LblSwBg.Move(x, r1Y, w3, hh)
    x += w3 + 12
    LblFont.GetPos(, , &wLF)
    LblFont.Move(x, r1Y + 5)
    x += wLF + 2
    DdlFont.Move(x, r1Y)
    DdlFont.GetPos(, , &wDDL)
    x += wDDL + 14
    LblSearch.GetPos(, , &wLS)
    LblSearch.Move(x, r1Y + 5)
    x += wLS + 2
    ; Search box stretches to right margin
    srchW := W - x - margin
    If (srchW < 60)
        srchW := 60
    SrchBox.Move(x, r1Y, srchW)

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
    CbxCenter.GetPos(, , &cbW)
    cbxX += cbW + 14
    CbxTTS.Move(cbxX, cbxY)
    CbxTTS.GetPos(, , &cbW)
    cbxX += cbW + 8
    DdlTTSVoice.Move(cbxX, cbxY - 2)

    ; Row 3 — slider stretches to full width
    SldWPM.Move(margin, r3Y, W - 2*margin)
}

; ----------------------------------------------------------------------------------------------------------------------
; Window close — save settings & exit
; ----------------------------------------------------------------------------------------------------------------------
GuiClosing(*) {
    Critical
    StopPlay(True)
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
    savedIdx := RecentPositions.Has(StrLower(f)) ? RecentPositions[StrLower(f)] : 0
    LoadTextFile(f, savedIdx)
}

; ----------------------------------------------------------------------------------------------------------------------
; Open srSettings.ini in the default editor (usually Notepad)
; ----------------------------------------------------------------------------------------------------------------------
OpenIniFile(*) {
    If !FileExist(IniFile) {
        MsgBox("srSettings.ini not found.`n`nIt will be created automatically when you change a setting.", AppName, 64)
        Return
    }
    Run(IniFile)
}

; ----------------------------------------------------------------------------------------------------------------------
; Launch TextExtractor — portable exe pattern: TextExtractor.exe in same folder,
; falling back to running TextExtractor.ahk with the current AHK interpreter.
; TextExtractor is a companion, not part of SpeedReader, so we just launch and forget;
; SR learns about completed conversions via CheckForTEOutput polling.
; ----------------------------------------------------------------------------------------------------------------------
LaunchTextExtractor(*) {
    teExe := A_ScriptDir "\TextExtractor.exe"
    teAhk := A_ScriptDir "\TextExtractor.ahk"
    If FileExist(teExe) {
        ; Already running? Just activate it instead of launching a second instance.
        If WinExist("ahk_exe TextExtractor.exe")
            WinActivate("ahk_exe TextExtractor.exe")
        Else
            Run('"' teExe '"')
    } Else If FileExist(teAhk) {
        Run('"' A_AhkPath '" "' teAhk '"')
    } Else {
        MsgBox("TextExtractor not found.`n`nExpected:`n" teExe "`n`nor:`n" teAhk
             . "`n`nMake sure TextExtractor.exe (or TextExtractor.ahk) is in the same folder as SpeedReader.",
               AppName, 48)
    }
}

; ----------------------------------------------------------------------------------------------------------------------
; Poll for a completed TextExtractor conversion.
; Called by a 1500 ms repeating timer.  Only acts when SpeedReader is the foreground
; window to avoid loading a file while the user is mid-read somewhere else.
; TextExtractor signals completion by writing TEConvertedAt + LastFile to srSettings.ini.
; New TE files have no saved position so they always load from word 1 (no resume prompt).
; ----------------------------------------------------------------------------------------------------------------------
CheckForTEOutput(*) {
    global TELastStampSeen, Cfg, IniFile

    If !WinActive("ahk_id " MainGui.Hwnd)
        Return

    stamp := IniRead(IniFile, "Session", "TEConvertedAt", "")
    If (stamp = "" || stamp = TELastStampSeen)
        Return

    newPath := IniRead(IniFile, "Session", "LastFile", "")
    ; Strip any trailing ", wordIdx" that might be present from a previous SR write.
    ; Reuse the canonical parser so the format stays in sync with SaveSettings/LoadSettings.
    dummyIdx := 0
    newPath := ParseRecentEntry(newPath, &dummyIdx)

    If (newPath = "" || !FileExist(newPath)) {
        TELastStampSeen := stamp
        Return
    }
    If (StrLower(newPath) = StrLower(Cfg.LastFile)) {
        TELastStampSeen := stamp
        Return
    }

    TELastStampSeen := stamp
    ; TE output is always fresh — load from word 1, no resume prompt
    LoadTextFile(newPath, 0)
    LblStatus.Text := "Loaded from TextExtractor: " FileBaseName(newPath)
}

; ----------------------------------------------------------------------------------------------------------------------
; Push a path to the top of RecentFiles, deduplicating and capping at RecentFilesMax.
; wordIdx is the saved reading position (0 = beginning / no position saved).
; If the file is already in the list, its position is updated in place before moving
; it to the top so we don't lose a position saved earlier in the session.
; ----------------------------------------------------------------------------------------------------------------------
PushRecentFile(path, wordIdx := 0) {
    global RecentFiles, RecentFilesMax, RecentPositions
    lp := StrLower(path)
    ; Update position map — but don't wipe a saved position with 0 when an entry
    ; already exists (e.g. LoadTextFile calls PushRecentFile(path, 0) before the
    ; resume prompt; we need to preserve the saved index until the user decides).
    If (wordIdx > 0 || !RecentPositions.Has(lp))
        RecentPositions[lp] := wordIdx
    ; Remove any existing occurrence (case-insensitive)
    i := 1
    While (i <= RecentFiles.Length) {
        If (StrLower(RecentFiles[i]) = lp)
            RecentFiles.RemoveAt(i)
        Else
            i++
    }
    RecentFiles.InsertAt(1, path)
    While (RecentFiles.Length > RecentFilesMax)
        RecentFiles.Pop()
}

; ----------------------------------------------------------------------------------------------------------------------
; Save the current reading position (CurIdx) for the loaded file so it can be
; offered as a resume point next time the file is opened.
; Called on pause and on window close.
; ----------------------------------------------------------------------------------------------------------------------
SavePositionForCurrentFile() {
    global CurIdx, Cfg, RecentPositions
    If (Cfg.LastFile = "" || Words.Length = 0)
        Return
    ; Only save if we've actually started reading (CurIdx > 0)
    If (CurIdx > 0)
        RecentPositions[StrLower(Cfg.LastFile)] := CurIdx
    SaveSettings()
}
; Called at startup and whenever a new file is loaded.
; ----------------------------------------------------------------------------------------------------------------------
RebuildRecentMenu() {
    global FileMenu, RecentFiles
    ; Wipe and rebuild the whole menu so we don't have to track item positions
    FileMenu.Delete()
    FileMenu.Add("&Open...`tCtrl+O", FileOpen)
    FileMenu.Add("Con&vert PDF/EPUB/TXT...", LaunchTextExtractor)
    FileMenu.Add("Open &srSettings.ini", OpenIniFile)
    FileMenu.Add()   ; separator

    ; --- Recently converted submenu (*.txt files in Converted\ subfolder) ---
    convertedDir := A_ScriptDir "\Converted"
    if DirExist(convertedDir) {
        convertedFiles := []
        Loop Files, convertedDir "\*.txt" {
            convertedFiles.Push({path: A_LoopFileFullPath, time: A_LoopFileTimeModified})
        }
        ; Sort newest-first by comparing the time strings (YYYYMMDDHHMMSS — lexicographic = chronological)
        ; Simple insertion sort is fine for ≤9 items.
        Loop convertedFiles.Length - 1 {
            i := A_Index
            Loop convertedFiles.Length - i {
                j := i + A_Index - 1
                If (convertedFiles[j].time < convertedFiles[j+1].time) {
                    tmp := convertedFiles[j]
                    convertedFiles[j] := convertedFiles[j+1]
                    convertedFiles[j+1] := tmp
                }
            }
        }
        If (convertedFiles.Length > 0) {
            RecentConvMenu := Menu()
            cap := Min(convertedFiles.Length, RecentFilesMax)
            Loop cap {
                p := convertedFiles[A_Index].path
                RecentConvMenu.Add(FileBaseName(p), ((fp, *) => LoadTextFile(fp)).Bind(p))
            }
            FileMenu.Add("Recently &converted", RecentConvMenu)
            FileMenu.Add()   ; separator before regular recent files
        }
    }

    ; --- Regular recent files ---
    added := 0
    For i, path in RecentFiles {
        If !FileExist(path)
            Continue
        added++
        label := "&" added "  " FileBaseName(path)
        savedIdx := RecentPositions.Has(StrLower(path)) ? RecentPositions[StrLower(path)] : 0
        FileMenu.Add(label, ((p, si, *) => LoadTextFile(p, si)).Bind(path, savedIdx))
    }
    If (added > 0)
        FileMenu.Add()   ; separator before Exit
    FileMenu.Add("E&xit", (*) => GuiClosing())
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
    LoadTextFile(path, RecentPositions.Has(StrLower(path)) ? RecentPositions[StrLower(path)] : 0)
}

; ----------------------------------------------------------------------------------------------------------------------
; Load a .txt file into the RichEdit and tokenize into words.
; savedIdx: word index to offer as resume point (0 = start from beginning, no prompt).
; When savedIdx > 0 the user is shown a "Resume / Start over" prompt.
; ----------------------------------------------------------------------------------------------------------------------
LoadTextFile(path, savedIdx := 0) {
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
    global FullText := text        ; store for phrase/regex search (same offsets as RichEdit)
    StopPlay(True)
    ClearSearchHighlight()
    SrchBox.Value := ""
    SrchLastWord  := ""
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
    PushRecentFile(path, 0)        ; register in recent list (position updated below if resuming)
    SaveSettings()
    RebuildRecentMenu()
    MainGui.Title := AppName " -- " FileBaseName(path)
    LblStatus.Text := Format("{1}  ({2} words)", FileBaseName(path), Words.Length)

    ; --- Resume prompt ---
    ; Only offer if savedIdx is a valid mid-document position (not word 1 or the last word).
    If (savedIdx > 1 && savedIdx < Words.Length) {
        pct := Round(savedIdx / Words.Length * 100)
        choice := MsgBox(
            Format("Resume reading '{1}'?`n`nLast position: word {2} of {3}  ({4}%)"
                . "`n`nYes = go to last position`nNo = start from beginning (clears saved position)`nCancel = do nothing (keeps saved position for later)",
                FileBaseName(path), savedIdx, Words.Length, pct),
            AppName " — Resume?",
            "YesNoCancel Icon? Default1")
        If (choice = "Yes") {
            ; Jump to saved position and scroll it into view
            JumpToCharPos(Words[savedIdx].start)
            If Cfg.CenterScroll
                ScrollToCenter(Words[savedIdx].start)
            Else {
                RE.SetSel(Words[savedIdx].start, Words[savedIdx].start)
                RE.ScrollCaret()
            }
            DllCall("HideCaret", "Ptr", RE.Hwnd)
            ; Update position map so SaveSettings writes the right index
            RecentPositions[StrLower(path)] := savedIdx
            PushRecentFile(path, savedIdx)
            SaveSettings()
            LblStatus.Text := Format("{1}  (resuming at word {2} of {3},  {4}%)",
                FileBaseName(path), savedIdx, Words.Length, pct)
        } Else If (choice = "No") {
            ; Start from beginning — explicitly clear the saved position so we don't re-prompt
            RecentPositions[StrLower(path)] := 0
            PushRecentFile(path, 0)
            SaveSettings()
        }
        ; "Cancel" = do nothing: position data is preserved in RecentPositions for next time
    }
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
        ; Words[i].end is the 0-based exclusive end offset of word i; Words[i+1].start
        ; is the 0-based start of word i+1. Their difference is the exact char count
        ; of the whitespace gap between them. For SubStr, convert the start of the gap
        ; from 0-based exclusive-end to 1-based inclusive start by adding 1.
        gapStart := Words[i].end + 1
        gapLen   := Words[i+1].start - Words[i].end
        gap := SubStr(text, gapStart, gapLen)
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
    Critical
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
    ClearSearchHighlight()
    SrchBox.Enabled := False
    sel := RE.GetSel()
    caret := sel.S
    If (caret > 0)
        JumpToCharPos(caret)
    If (CurIdx >= Words.Length)
        Restart()
    IsPlaying := True
    BtnPlay.Text := "❚❚ Pause"
    If (Cfg.TTSMode) {
        StartTTSEngine()
    } Else {
        DBG("StartPlay — scheduling first tick via SetTimer")
        SetTimer(StepTimer, -1)
    }
}

; hardStop=False (default): a normal Play/Pause-button pause. In TTS mode this calls
;   SAPI's Pause() rather than cancelling the utterance, so the next StartPlay() can
;   Resume() from the exact same spot instead of re-speaking from scratch.
; hardStop=True: used anywhere the reading position is about to change out from under
;   the engine — Restart, jumping to a new word, loading a new file, closing the window.
;   In TTS mode this purges the in-flight utterance instead of pausing it.
StopPlay(hardStop := False) {
    global IsPlaying
    DBG("StopPlay ENTER  IsPlaying=" IsPlaying "  CurIdx=" CurIdx "  PrevStart=" PrevStart "  PrevEnd=" PrevEnd "  hardStop=" hardStop)
    IsPlaying := False
    BtnPlay.Text := "▶ Play"
    If (Cfg.TTSMode)
        StopTTSEngine(hardStop)
    Else
        SetTimer(StepTimer, 0)
    SrchBox.Enabled := True
    DBG("StopPlay — engine stopped, calling SavePositionForCurrentFile")
    SavePositionForCurrentFile()
    DBG("StopPlay EXIT")
}

Restart(*) {
    global CurIdx, PrevStart, PrevEnd, RecentPositions
    StopPlay(True)
    ClearSearchHighlight()
    ResetDwellBuffer()
    ClearHighlight()
    ; Clear any stored resume position for the current file so the next pause/close
    ; doesn't write a stale index and re-prompt the user to resume from it.
    If (Cfg.LastFile != "")
        RecentPositions[StrLower(Cfg.LastFile)] := 0
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
    Critical
    static WM_SETREDRAW := 0x000B
    global CurIdx, PrevStart, PrevEnd
    DBG("StepWord ENTER  IsPlaying=" IsPlaying "  CurIdx=" CurIdx "  PrevStart=" PrevStart "  PrevEnd=" PrevEnd)
    If (!IsPlaying) {
        DBG("StepWord EXIT — not playing")
        Return
    }
    If (CurIdx >= Words.Length) {
        DBG("StepWord EXIT — end of words")
        StopPlay()
        Return
    }
    chunk := Max(1, Cfg.ChunkSize)
    If (Cfg.Overlap) {
        leadIdx  := CurIdx + 1
        startIdx := Max(1, leadIdx - chunk + 1)
        endIdx   := leadIdx
        newCur   := leadIdx
    } Else {
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
    CurIdx   := newCur

    HighlightRange(startOff, endOff, CurIdx, Words.Length)

    dwell := ComputeDwellMs(startIdx, endIdx)
    UpdateDwellBuffer(dwell / (endIdx - startIdx + 1))
    UpdateTimeRemaining()
    DBG("StepWord SCHED  word='" Words[CurIdx].text "'  idx=" CurIdx "  dwell=" dwell "ms  startOff=" startOff "  endOff=" endOff)
    SetTimer(StepTimer, -dwell)
}

; ----------------------------------------------------------------------------------------------------------------------
; Clear the previous highlight and paint [startOff, endOff) as the new one, scrolling it
; into view first. Shared by both playback engines: the timer-driven pacer (StepWord) and
; the TTS-driven pacer (SAPI_Word) — whichever is currently deciding when the next word
; is "due," they both just call this to paint it.
; curWordIdx/totalWords are only used for the status-bar readout.
; ----------------------------------------------------------------------------------------------------------------------
HighlightRange(startOff, endOff, curWordIdx, totalWords) {
    static WM_SETREDRAW := 0x000B
    global PrevStart, PrevEnd
    hwnd := RE.Hwnd

    ; Scroll before highlight — repaint from scroll shows previous highlight, no flash.
    If (Cfg.CenterScroll)
        ScrollToCenter(startOff)
    Else
        RE.ScrollCaret()

    ; Freeze repaints across clear+highlight so screen never sees the blue selection
    ; color between SetSel and SetFont.
    SendMessage(WM_SETREDRAW, False, 0, hwnd)
    If (PrevStart >= 0 && PrevEnd > PrevStart) {
        RE.SetSel(PrevStart, PrevEnd)
        RE.SetFont({BkColor: "Auto"})
    }
    RE.SetSel(startOff, endOff)
    RE.SetFont({BkColor: Cfg.HighlightColor})
    RE.SetSel(endOff, endOff)
    SendMessage(WM_SETREDRAW, True, 0, hwnd)
    DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", True)
    DllCall("HideCaret", "Ptr", hwnd)

    PrevStart := startOff
    PrevEnd   := endOff
    LblStatus.Text := Format("Word {1} of {2}  ({3}%)", curWordIdx, totalWords, Round(curWordIdx / totalWords * 100))
}

ClearHighlight() {
    global PrevStart, PrevEnd
    DBG("ClearHighlight  PrevStart=" PrevStart "  PrevEnd=" PrevEnd "  IsPlaying=" IsPlaying)
    If (PrevStart < 0 || PrevEnd <= PrevStart)
        Return
    RE.SetSel(PrevStart, PrevEnd)
    RE.SetFont({BkColor: "Auto"})
    RE.SetSel(PrevEnd, PrevEnd)
    DllCall("HideCaret", "Ptr", RE.Hwnd)
    PrevStart := PrevEnd := -1
}

; ======================================================================================================================
; Read Aloud (TTS) engine — SAPI5 via COM. SAPI's chunk-level events (StartStream/
; EndStream) have proven reliable in testing; its per-word Word event has NOT — voices
; vary, and at least one tested voice fires several jumbled sub-word events for any
; multi-syllable word instead of one clean event per word. So SAPI only tells us when a
; sentence-chunk starts and ends; word-by-word highlighting *within* a chunk is driven by
; our own timer (TTSSubStep), using the same weighted dwell-time math the silent pacer
; uses (ComputeDwellMs). EndStream re-syncs the highlight to the chunk's last word before
; moving on, so a chunk always finishes visually even if our dwell estimate and SAPI's
; actual speaking pace drift apart. The raw Word event is still logged for diagnostics
; but no longer drives anything.
;
; Lifecycle: StartTTSEngine() either resumes a soft-paused chunk (TTSSpeaking already
; True — see StopPlay's hardStop=False path) or starts fresh from CurIdx, queuing one
; sentence-chunk; each chunk's SAPI_EndStream queues the next one until the document ends.
; SAPI has no seek, so any position change (jump, restart, new file) must hard-stop first.
; (SVSFlagsAsync / SVSFPurgeBeforeSpeak are declared up in the tunables section near the
; top of the script, so they execute before the auto-execute section's Return.)
; ======================================================================================================================

EnsureTTSEngine() {
    global TTSEngine
    If (IsObject(TTSEngine))
        Return True
    Try {
        TTSEngine := ComObject("SAPI.SpVoice")
        ComObjConnect(TTSEngine, "SAPI_")
        ; Without this, Word/EndStream events are silently never delivered — audio
        ; still plays (it doesn't depend on events), but the highlight never moves.
        TTSEngine.EventInterests := TTSEventInterests
        voiceDesc := "<unknown>"
        Try voiceDesc := TTSEngine.Voice.GetDescription()
        DBG("EnsureTTSEngine — SAPI.SpVoice created, Voice='" voiceDesc "', EventInterests=" TTSEventInterests)
        Return True
    } Catch as e {
        MsgBox("Could not start Windows text-to-speech (SAPI):`n" e.Message
             . "`n`nRead Aloud has been turned off.", AppName, 16)
        TTSEngine := ""
        Cfg.TTSMode := False
        CbxTTS.Value := False
        UpdateTTSControlStates()
        Return False
    }
}

; Approximate WPM -> SAPI Rate (-10..10) mapping. See TTSAvgWpmAtRate0/TTSPctPerStep
; near the top of the script for the calibration knobs.
MapWpmToSapiRate(wpm) {
    ratio := Max(wpm, 20) / TTSAvgWpmAtRate0
    steps := Ln(ratio) / Ln(1 + TTSPctPerStep)
    Return Max(-10, Min(10, Round(steps)))
}

StartTTSEngine() {
    global TTSSpeaking, TTSNextWordIdx
    If (!EnsureTTSEngine())
        Return
    Try TTSEngine.Rate := MapWpmToSapiRate(Cfg.WPM)
    If (TTSSpeaking) {
        ; Soft-paused chunk — pick SAPI back up exactly where it left off, and resume
        ; our own word-by-word sub-pacer from the same spot.
        Try TTSEngine.Resume()
        If (CurIdx < TTSChunkEndIdx)
            SetTimer(TTSSubTimer, -ComputeDwellMs(CurIdx, CurIdx))
        Return
    }
    TTSNextWordIdx := Max(1, CurIdx + 1)
    ApplyTTSVoiceSetting()
    QueueNextTTSSentence()
}

; Speaks one sentence-sized chunk starting at TTSNextWordIdx, then advances the cursor
; past it. Chunking this way (rather than one Speak() for the whole rest of the document)
; keeps each utterance's string short — which matters because some SAPI voices garble
; their Word-event character positions on very long strings. A bad chunk's fallout is
; bounded to that one sentence; the next EndStream/chunk resyncs cleanly regardless.
QueueNextTTSSentence() {
    global TTSBaseOffset, TTSNextWordIdx, TTSChunkEndIdx, TTSSpeaking, CurIdx
    startIdx := TTSNextWordIdx
    endIdx   := startIdx
    Loop (Words.Length - startIdx + 1) {
        i := startIdx + A_Index - 1
        endIdx := i
        If (Words[i].endsSentence || Words[i].endsParagraph)
            Break
    }
    TTSBaseOffset  := Words[startIdx].start
    speakText      := SubStr(FullText, TTSBaseOffset + 1, Words[endIdx].end - TTSBaseOffset)
    TTSNextWordIdx := endIdx + 1
    TTSChunkEndIdx := endIdx
    TTSSpeaking    := True
    DBG("QueueNextTTSSentence  words " startIdx "-" endIdx "  TTSBaseOffset=" TTSBaseOffset "  len=" StrLen(speakText))
    ; Paint the chunk's first word immediately (don't wait on any SAPI event for it), then
    ; let TTSSubStep carry the highlight through the rest of the chunk on our own clock.
    CurIdx := startIdx
    HighlightRange(Words[startIdx].start, Words[startIdx].end, startIdx, Words.Length)
    If (startIdx < endIdx)
        SetTimer(TTSSubTimer, -ComputeDwellMs(startIdx, startIdx))
    Try TTSEngine.Speak(speakText, SVSFlagsAsync)
}

; Advances the highlight one word at a time through the chunk currently being spoken,
; using the same weighted dwell-time math (ComputeDwellMs) the silent timer pacer uses.
; Stops on its own once it reaches the chunk's last word — SAPI_EndStream takes it from
; there, re-syncing to the chunk boundary and queuing the next chunk.
TTSSubStep(*) {
    global CurIdx
    If (!IsPlaying || !Cfg.TTSMode)
        Return
    If (CurIdx >= TTSChunkEndIdx)
        Return
    nextIdx := CurIdx + 1
    CurIdx := nextIdx
    HighlightRange(Words[nextIdx].start, Words[nextIdx].end, nextIdx, Words.Length)
    If (nextIdx < TTSChunkEndIdx)
        SetTimer(TTSSubTimer, -ComputeDwellMs(nextIdx, nextIdx))
}

StopTTSEngine(hardStop := False) {
    global TTSSpeaking, TTSIgnoreNextEndStream
    If (!IsObject(TTSEngine))
        Return
    SetTimer(TTSSubTimer, 0)   ; always freeze our local sub-pacer alongside SAPI
    If (hardStop) {
        wasSpeaking := TTSSpeaking
        ; Empty string + purge flag cancels whatever is in flight essentially immediately.
        Try TTSEngine.Speak("", SVSFlagsAsync | SVSFPurgeBeforeSpeak)
        TTSSpeaking := False
        ; The purge is async — its own EndStream can still arrive later, possibly after a
        ; new chunk has already been queued (jumping, restarting, or loading a new file
        ; right after a hard stop). Only expect that stray echo if something was actually
        ; playing/queued to purge; otherwise there's nothing to ignore.
        TTSIgnoreNextEndStream := wasSpeaking
    } Else {
        Try TTSEngine.Pause()
    }
}

; SAPI event: diagnostic only — logged in case it's useful for a future voice, but not
; used for anything. StartStream's own StreamNumber turned out to be just as unreliable
; as everything else this particular voice reports (two clearly-different chunks logged
; the identical number in testing), so it isn't used to identify chunks.
SAPI_StartStream(this, StreamNumber, StreamPosition) {
    DBG("SAPI_StartStream [diagnostic]  StreamNumber=" StreamNumber)
}

; SAPI event: diagnostic only now — logged so a given voice's Word-event behavior can be
; inspected, but no longer drives the highlight (see the engine overview comment above
; for why: at least one tested voice fires several jumbled sub-word events per multi-
; syllable word instead of one clean event per word).
SAPI_Word(this, StreamNumber, StreamPosition, CharacterPosition, Length) {
    absOffset := TTSBaseOffset + CharacterPosition
    idx := FindWordIndexAtChar(absOffset)
    DBG("SAPI_Word [diagnostic]  CharacterPosition=" CharacterPosition "  absOffset=" absOffset
        "  idx=" idx "  word='" Words[idx].text "'  CurIdx=" CurIdx)
}

; SAPI event: fires when a sentence-chunk finishes (natural completion) or after a
; purge-stop. TTSIgnoreNextEndStream (armed only when a hard stop actually purged
; something in flight) absorbs that purge's own async echo, which can otherwise arrive
; after a new chunk has already been queued — the exact "TTS doesn't restart after
; jumping/loading a new file" bug. This voice's own StreamNumber turned out to be too
; unreliable to use for that filtering (see SAPI_StartStream), so this flag is entirely
; self-managed instead of depending on anything SAPI reports.
; Once past that, make sure the chunk that just finished actually got shown through to
; its last word (our local sub-pacer's estimate and SAPI's real speaking pace won't match
; exactly), then queue the next sentence — or, if there isn't one, the document is done,
; so end playback the same way StepWord does at EOF.
SAPI_EndStream(this, StreamNumber, StreamPosition) {
    global TTSSpeaking, TTSNextWordIdx, CurIdx, TTSIgnoreNextEndStream
    DBG("SAPI_EndStream  StreamNumber=" StreamNumber "  TTSNextWordIdx=" TTSNextWordIdx
        "  WordsLen=" Words.Length "  IsPlaying=" IsPlaying "  Cfg.TTSMode=" Cfg.TTSMode
        "  ignoreNext=" TTSIgnoreNextEndStream)
    If (TTSIgnoreNextEndStream) {
        TTSIgnoreNextEndStream := False
        DBG("SAPI_EndStream  consuming expected stray echo from a hard stop, ignoring")
        Return
    }
    SetTimer(TTSSubTimer, 0)
    If (!Cfg.TTSMode || !IsPlaying) {
        TTSSpeaking := False
        Return
    }
    If (CurIdx < TTSChunkEndIdx) {
        CurIdx := TTSChunkEndIdx
        HighlightRange(Words[TTSChunkEndIdx].start, Words[TTSChunkEndIdx].end, TTSChunkEndIdx, Words.Length)
    }
    If (TTSNextWordIdx <= Words.Length) {
        QueueNextTTSSentence()
    } Else {
        TTSSpeaking := False
        StopPlay(True)
    }
}

; ----------------------------------------------------------------------------------------------------------------------
; Get the RichEdit's line height in pixels by querying the font directly via GetTextMetricsW.
; This is far more reliable than sampling EM_POSFROMCHAR between visible lines, which
; produces garbage values when the visible region contains blank paragraph lines (the
; diary-format text in Apocalypse Z hit this constantly).
;
; The result is cached and only recomputed when the font changes (Name + Size). The
; cache key is the font signature, so a font change automatically invalidates without
; an explicit invalidation call from the rest of the code.
; ----------------------------------------------------------------------------------------------------------------------
GetRichEditLineHeight(hwnd) {
    static WM_GETFONT := 0x0031
    static cachedLineH := 0
    static cachedKey   := ""

    ; Cache key includes everything that could change pixel line height.
    key := Cfg.FontName "|" Cfg.FontSize
    If (cachedLineH > 0 && cachedKey = key)
        Return cachedLineH

    hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
    If (!hdc)
        Return Max(8, Cfg.FontSize + 8)   ; conservative fallback

    hFont   := SendMessage(WM_GETFONT, 0, 0, hwnd)
    oldFont := 0
    If (hFont)
        oldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")

    tm := Buffer(60, 0)   ; TEXTMETRICW is 60 bytes on x64
    ok := DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm)

    lineH := 0
    If (ok) {
        tmHeight        := NumGet(tm, 0, "Int")    ; ascent + descent
        tmExternalLead  := NumGet(tm, 8, "Int")    ; line spacing leading
        lineH := tmHeight + tmExternalLead
    }

    If (oldFont)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)

    If (lineH <= 0)
        lineH := Cfg.FontSize + 8           ; final fallback

    ; Add a small padding to account for RichEdit's rendered line spacing being
    ; slightly larger than raw font metrics in practice.
    lineH := Max(8, lineH + 4)

    cachedLineH := lineH
    cachedKey   := key
    Return lineH
}

; ----------------------------------------------------------------------------------------------------------------------
; Scroll the RichEdit so the highlighted word sits vertically centered in the control.
; Strategy:
;   1. Line height comes from GetRichEditLineHeight() — derived from font metrics, stable.
;   2. EM_GETFIRSTVISIBLELINE tells us which line is currently at the top.
;   3. EM_LINEFROMCHAR converts a char offset to a line number.
;   4. We compute how many lines to scroll so the target line lands at the vertical midpoint,
;      then call EM_LINESCROLL to apply the delta — but only when |delta| >= 2 to avoid
;      per-tick scroll churn while the highlight is already comfortably near center.
; Edge cases: near the top or bottom of the document, we just let it scroll as far as it can —
; the control clamps gracefully and won't over-scroll.
; ----------------------------------------------------------------------------------------------------------------------
ScrollToCenter(charOffset) {
    static EM_LINEFROMCHAR        := 0x00C9
    static EM_GETFIRSTVISIBLELINE := 0x00CE
    static EM_LINESCROLL          := 0x00B6
    static EM_GETLINECOUNT        := 0x00BA

    hwnd := RE.Hwnd
    firstVisible := SendMessage(EM_GETFIRSTVISIBLELINE, 0, 0, hwnd)

    lineH := GetRichEditLineHeight(hwnd)

    RE.GetPos(, , , &reH)
    visibleLines := Max(1, reH // lineH)
    halfLines    := visibleLines // 2
    targetLine   := SendMessage(EM_LINEFROMCHAR, charOffset, 0, hwnd)
    desiredFirst := Max(0, targetLine - halfLines)
    delta        := desiredFirst - firstVisible

    DBG("ScrollToCenter  charOff=" charOffset "  firstVis=" firstVisible "  targetLine=" targetLine
        . "  lineH=" lineH "  reH=" reH "  visLines=" visibleLines
        . "  halfLines=" halfLines "  desiredFirst=" desiredFirst "  delta=" delta)

    ; Safety clamp: never scroll more than the document's total line count in one call.
    ; A huge delta (e.g. on initial jump-to-position) could in theory disturb the RichEdit's
    ; internal state. The RichEdit clamps at document boundaries, so a large-but-bounded
    ; value is safe.
    maxSafeDelta := SendMessage(EM_GETLINECOUNT, 0, 0, hwnd) + visibleLines
    If (Abs(delta) > maxSafeDelta)
        delta := (delta > 0) ? maxSafeDelta : -maxSafeDelta

    ; Skip pointless single-line corrections — reduces scroll churn and the rate of
    ; EM_LINESCROLL calls. The highlight is already near center; ±1 line doesn't matter.
    ; Also skip on exact match (delta=0). Wrapped in try as a belt-and-suspenders guard
    ; in case EM_LINESCROLL ever does throw under odd RichEdit internal state.
    If (Abs(delta) >= 2) {
        try SendMessage(EM_LINESCROLL, 0, delta, hwnd)
    }
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
    Critical
    Cfg.WPM := SldWPM.Value
    LblWPM.Text := Cfg.WPM
    OnWpmValueChanged()
    SaveSettings()
}

FontChanged(*) {
    Critical
    Cfg.FontName := DdlFont.Text
    Cfg.FontSize := EdSize.Value
    ApplyFontSettings()
    SaveSettings()
}

ChunkChanged(*) {
    Critical
    Cfg.ChunkSize := Max(1, EdChunk.Value)
    SaveSettings()
}

OverlapChanged(*) {
    Critical
    Cfg.Overlap := CbxOverlap.Value ? True : False
    SaveSettings()
}

SentencePauseChanged(*) {
    Critical
    Cfg.SentencePause := CbxSentence.Value ? True : False
    SaveSettings()
}

ListPausesChanged(*) {
    Critical
    Cfg.ListPauses := CbxList.Value ? True : False
    SaveSettings()
}

SmartPacingChanged(*) {
    Critical
    Cfg.SmartPacing := CbxSmart.Value ? True : False
    SaveSettings()
}

CenterScrollChanged(*) {
    Critical
    Cfg.CenterScroll := CbxCenter.Value ? True : False
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; Read Aloud (TTS) mode toggle. Cleanly hands off between the two playback engines if
; the pacer is currently running, so checking/unchecking mid-read doesn't stop playback.
; ----------------------------------------------------------------------------------------------------------------------
TTSModeChanged(*) {
    Critical
    global IsPlaying
    wasPlaying := IsPlaying
    If (wasPlaying)
        StopPlay(True)
    Cfg.TTSMode := CbxTTS.Value ? True : False
    UpdateTTSControlStates()
    SaveSettings()
    If (wasPlaying)
        StartPlay()
}

; Chunk size, Overlap, sentence/list pausing, and Smart pacing are all properties of the
; timer-driven pacer's dwell-time math — none of them apply once SAPI is setting the pace,
; so gray them out while Read Aloud is active rather than leaving controls that silently
; do nothing. The voice picker is the opposite — only meaningful while Read Aloud is on.
UpdateTTSControlStates() {
    on := Cfg.TTSMode
    EdChunk.Enabled     := !on
    CbxOverlap.Enabled  := !on
    CbxSentence.Enabled := !on
    CbxList.Enabled     := !on
    CbxSmart.Enabled    := !on
    DdlTTSVoice.Enabled := on
}

; Voice picker change — the intent was for this to take effect the next time speech
; starts (ApplyTTSVoiceSetting re-applies Cfg.TTSVoiceId on every fresh StartTTSEngine
; call, the same way Rate gets re-applied). In practice it needs a full app restart to
; actually take effect — see the header notes. Left as-is rather than dropped, since the
; selection still needs to persist for the next launch either way.
TTSVoiceChanged(*) {
    Critical
    idx := DdlTTSVoice.Value
    Cfg.TTSVoiceId := (idx <= 1) ? "" : TTSVoiceList[idx - 1].Id
    SaveSettings()
}

; Applies Cfg.TTSVoiceId to the live TTSEngine, if it still matches an installed voice.
; A no-op (leaves SAPI's own default voice) when TTSVoiceId is blank or no longer matches
; anything installed — e.g. srSettings.ini was copied over from a different machine.
ApplyTTSVoiceSetting() {
    If (Cfg.TTSVoiceId = "")
        Return
    For _, v in TTSVoiceList {
        If (v.Id = Cfg.TTSVoiceId) {
            Try TTSEngine.Voice := v.Token
            Return
        }
    }
}

; Re-checked on every WPM change. Spoken word stops being intelligible/useful well before
; the top of the slider's range, so Read Aloud is only offered below TTSMaxWPM.
GateTTSAvailability() {
    global IsPlaying
    tooFast := Cfg.WPM > TTSMaxWPM
    CbxTTS.Enabled := !tooFast
    If (tooFast && Cfg.TTSMode) {
        wasPlaying := IsPlaying
        If (wasPlaying)
            StopPlay(True)
        Cfg.TTSMode := False
        CbxTTS.Value := False
        UpdateTTSControlStates()
        SaveSettings()
        LblStatus.Text := Format("Read Aloud disabled above {1} WPM", TTSMaxWPM)
        If (wasPlaying)
            StartPlay()
    }
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
    ; Unregister the window-scoped ^c when the dialog closes, otherwise reopening
    ; the dialog leaks hotkeys bound to destroyed ListViews.
    dbg.OnEvent("Close", CloseTokenAnalysis.Bind(dbg))
    dbg.Show()

    ; Ctrl+C: copy all visible LV rows to clipboard as CSV
    HotIfWinActive("ahk_id " dbg.Hwnd)
    Hotkey("^c", CopyTokensToClipboard.Bind(lv))
    HotIfWinActive()

    CloseTokenAnalysis(dbgGui, *) {
        HotIfWinActive("ahk_id " dbgGui.Hwnd)
        Try Hotkey("^c", "Off")
        HotIfWinActive()
        dbgGui.Destroy()
    }

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
    OnWpmValueChanged()
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; Common follow-up whenever Cfg.WPM changes, from either the slider drag or the
; Left/Right hotkey nudge: keep a live TTS utterance's speaking rate in sync, and
; re-check whether Read Aloud is still allowed at the new speed.
; ----------------------------------------------------------------------------------------------------------------------
OnWpmValueChanged() {
    If (Cfg.TTSMode && TTSSpeaking && IsObject(TTSEngine))
        Try TTSEngine.Rate := MapWpmToSapiRate(Cfg.WPM)
    GateTTSAvailability()
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
    hrs           := totalSec // 3600
    mins          := Mod(totalSec // 60, 60)
    secs          := Mod(totalSec, 60)
    ; LblTimeRemain.Text := Format("[{1}:{2:02}:{3:02}]", hrs, mins, secs)
    LblTimeRemain.Text := Format("{1}h {2:02}m {3:02}sec remaining", hrs, mins, secs)
}
; Only acts when the cursor is over the WPM slider; flips the direction so
; wheel-up = increase WPM and wheel-down = decrease WPM.
; wParam high word = signed wheel delta (positive = up, negative = down, multiples of 120).
; We return 0 to suppress the default slider handling so it doesn't also fire.
; ----------------------------------------------------------------------------------------------------------------------
OnMouseWheel(wParam, lParam, msg, hwnd) {
    Critical
    MouseGetPos(, , , &ctrlHwnd, 2)
    If (ctrlHwnd != SldWPM.Hwnd)
        Return
    delta := (wParam >> 16) & 0xFFFF
    If (delta >= 0x8000)
        delta -= 0x10000
    steps := delta / 120
    AdjustWPM(Round(steps * WPMHotkeyStep))
    Return 0
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
            SwHL.Opt("c" Fmt(new))
            SwHL.Redraw()
            ; Re-apply to current pacer highlight if visible
            If (PrevStart >= 0 && PrevEnd > PrevStart) {
                RE.SetSel(PrevStart, PrevEnd)
                RE.SetFont({BkColor: new})
                RE.SetSel(PrevEnd, PrevEnd)
            }
            ; Re-apply to current search highlight if visible
            If (SrchMatchStart >= 0 && SrchMatchEnd > SrchMatchStart) {
                RE.SetSel(SrchMatchStart, SrchMatchEnd)
                RE.SetFont({BkColor: new})
                RE.SetSel(SrchMatchEnd, SrchMatchEnd)
            }
        Case "TextColor":
            SwTx.Opt("c" Fmt(new))
            SwTx.Redraw()
            ApplyFontSettings()
        Case "BackColor":
            SwBg.Opt("c" Fmt(new))
            SwBg.Redraw()
            ApplyBackColor()
    }
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; WM_LBUTTONDOWN handler — fires for clicks on any control in the window.
; We filter to the three swatch progress bars and dispatch to PickColor.
; The transparent Text labels sit on top of the progress bars in Z-order; clicks on
; the label text pass through only if +0x20 (SS_NOTIFY is NOT set — static controls
; without SS_NOTIFY don't eat mouse messages, so clicks fall through to the bar).
; ----------------------------------------------------------------------------------------------------------------------
OnSwatchClick(wParam, lParam, msg, hwnd) {
    Critical
    If (hwnd = SwHL.Hwnd)
        PickColor("HighlightColor")
    Else If (hwnd = SwTx.Hwnd)
        PickColor("TextColor")
    Else If (hwnd = SwBg.Hwnd)
        PickColor("BackColor")
    ; All other controls: return nothing (let default processing continue)
}
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
    Critical
    If (hwnd != RE.Hwnd)
        Return
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
    StopPlay(True)
    ClearSearchHighlight()
    SrchBox.Enabled := False
    JumpToCharPos(sel.S)
    IsPlaying := True
    BtnPlay.Text := "❚❚ Pause"
    If (Cfg.TTSMode) {
        StartTTSEngine()
    } Else {
        DBG("JumpToSelectionAndPlay — scheduling first tick via SetTimer")
        SetTimer(StepTimer, -1)
    }
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
; Search — incremental, debounced, forward from current position (or top per tunable).
; Highlights the matched span using the highlight color.  No CurIdx manipulation —
; the user double-clicks to set a pacer start point if they want.
;
; Modes:
;   Literal (default): case-insensitive substring search against the full document
;     text via InStr.  Phrases with whitespace / punctuation match naturally —
;     "first second", "Mr. Darcy", etc.
;   Regex: term starts with '/'.  Trailing '/' is optional.  The pattern is passed
;     to RegExMatch with the 'i)' option prepended unless the user supplied their
;     own options block.  Invalid patterns show a brief error in the status bar.
;
; F3 advances past the current match (regex mode consumes at least one char to
; avoid zero-width infinite loops).
; ----------------------------------------------------------------------------------------------------------------------

; Parse a search term.  Returns a {isRegex, pattern} object.
; Regex form: "/pattern" or "/pattern/" — the slashes are stripped.
; A lone "/" or empty pattern after stripping falls back to literal.
ParseSearchTerm(term) {
    If (SubStr(term, 1, 1) = "/" && StrLen(term) >= 2) {
        pat := SubStr(term, 2)
        ; Strip optional trailing slash (but only if the user intended it as a
        ; delimiter — a trailing slash that's part of the pattern is preserved
        ; if there's nothing after it to terminate).
        If (SubStr(pat, -1) = "/" && StrLen(pat) >= 2)
            pat := SubStr(pat, 1, StrLen(pat) - 1)
        If (pat != "")
            Return {isRegex: True, pattern: pat}
    }
    Return {isRegex: False, pattern: term}
}

; Called on every keystroke in SrchBox.  Debounces via a one-shot timer.
OnSearchChanged(*) {
    SetTimer(SearchExecute, -SearchDebounceMs)
}

; Ctrl+F handler — move focus to the search box and select any existing text
; so the user can type to replace it immediately.  If the pacer is running,
; the search box is disabled; in that case pause first so the box accepts focus.
FocusSearchBox() {
    If (IsPlaying)
        StopPlay()
    SrchBox.Focus()
    ; Select all existing text so typing replaces it.
    ; EM_SETSEL (0x00B1):  wParam = start,  lParam = end.  -1 as end = end of text.
    SendMessage(0x00B1, 0, -1, SrchBox.Hwnd)
}

; Execute a fresh search (called by debounce timer or immediately when needed).
; Starts from the char offset corresponding to CurIdx if SearchFromCurrent is
; true and we have a position; else from offset 0 (top of document).
SearchExecute(*) {
    global SrchMatchStart, SrchMatchEnd, SrchLastWord
    term := SrchBox.Value
    If (term = "") {
        ClearSearchHighlight()
        LblStatus.Text := (Words.Length > 0)
            ? Format("{1}  ({2} words)", FileBaseName(Cfg.LastFile), Words.Length)
            : "No file loaded."
        Return
    }
    If (Words.Length = 0)
        Return
    ; Determine starting char offset for the search
    startChar := 0
    If (SearchFromCurrent && CurIdx > 0 && CurIdx <= Words.Length)
        startChar := Words[CurIdx].start
    SearchFrom(term, startChar, True)   ; True = wrap allowed; status set internally
}

; Search forward from charStart for term.  Dispatches to literal or regex impl.
; wrapAround: if true, wraps to offset 0 after reaching end (with a "Wrapped" notice).
; Always updates the status bar — returns True on match, False otherwise.
SearchFrom(term, charStart, wrapAround) {
    global SrchMatchStart, SrchMatchEnd, SrchLastWord, FullText
    If (FullText = "" || term = "")
        Return False
    parsed := ParseSearchTerm(term)
    ; Try forward from charStart to end-of-document
    result := SearchInText(parsed, charStart, StrLen(FullText))
    If (result.error != "") {
        ClearSearchHighlight()
        LblStatus.Text := "Regex error: " result.error
        SrchLastWord := term
        Return False
    }
    If (!result.found && wrapAround && charStart > 0) {
        ; Wrap: search from 0 up to charStart (exclusive)
        result := SearchInText(parsed, 0, charStart)
        If (result.error != "") {
            ClearSearchHighlight()
            LblStatus.Text := "Regex error: " result.error
            SrchLastWord := term
            Return False
        }
        If (result.found) {
            ApplySearchHighlight(result.matchStart, result.matchEnd)
            SrchLastWord := term
            idx := FindWordIndexAtChar(result.matchStart)
            LblStatus.Text := Format('Wrapped to beginning  —  match at word {1} of {2}  ({3}%)',
                idx, Words.Length, Round(idx / Words.Length * 100))
            Return True
        }
    }
    If (result.found) {
        ApplySearchHighlight(result.matchStart, result.matchEnd)
        SrchLastWord := term
        idx := FindWordIndexAtChar(result.matchStart)
        LblStatus.Text := Format("Match at word {1} of {2}  ({3}%)",
            idx, Words.Length, Round(idx / Words.Length * 100))
        Return True
    }
    ClearSearchHighlight()
    SrchLastWord := term
    LblStatus.Text := "Not found: " term
    Return False
}

; Search FullText in the character range [fromChar, toChar) for the parsed term.
; Returns a result object:
;   found:      True if a match was found within the range
;   matchStart: 0-based char offset (inclusive)
;   matchEnd:   0-based char offset (exclusive)
;   error:      "" on success, or a regex error message
; Literal mode: InStr with case-insensitive flag.  Regex mode: RegExMatch with
; 'i)' prepended unless the user supplied an options block.
SearchInText(parsed, fromChar, toChar) {
    global FullText
    result := {found: False, matchStart: 0, matchEnd: 0, error: ""}
    If (fromChar >= toChar || FullText = "")
        Return result
    ; Extract the slice we're allowed to search.  AHK SubStr is 1-based.
    sliceLen := toChar - fromChar
    slice := SubStr(FullText, fromChar + 1, sliceLen)
    If (parsed.isRegex) {
        ; Prepend case-insensitive option unless the user already supplied an
        ; options block ("foo)pattern" — note AHK uses ')' to terminate options).
        pat := parsed.pattern
        If !RegExMatch(pat, "^[imsxADJUXPS`r`n \t]*\)")
            pat := "i)" pat
        Try {
            pos := RegExMatch(slice, pat, &m)
        } Catch As e {
            result.error := e.Message
            Return result
        }
        If (pos > 0 && m.Len >= 0) {
            ; Guard against zero-width matches (e.g. ^ anchor) — treat as not found
            ; to avoid confusing UI.  F3 from a zero-width match would infinite-loop.
            If (m.Len = 0) {
                Return result
            }
            result.found      := True
            result.matchStart := fromChar + pos - 1
            result.matchEnd   := result.matchStart + m.Len
        }
        Return result
    }
    ; Literal mode — InStr with 4th param = false for case-insensitive.
    pos := InStr(slice, parsed.pattern, false)
    If (pos > 0) {
        result.found      := True
        result.matchStart := fromChar + pos - 1
        result.matchEnd   := result.matchStart + StrLen(parsed.pattern)
    }
    Return result
}

; Apply the search highlight to a character range and scroll it into view.
ApplySearchHighlight(charStart, charEnd) {
    global SrchMatchStart, SrchMatchEnd
    ; Clear previous search highlight first
    ClearSearchHighlight()
    SrchMatchStart := charStart
    SrchMatchEnd   := charEnd
    RE.SetSel(charStart, charEnd)
    RE.SetFont({BkColor: Cfg.HighlightColor})
    RE.SetSel(charEnd, charEnd)
    DllCall("HideCaret", "Ptr", RE.Hwnd)
    ; Scroll the match into view
    If Cfg.CenterScroll
        ScrollToCenter(charStart)
    Else {
        RE.SetSel(charStart, charStart)
        RE.ScrollCaret()
        RE.SetSel(charEnd, charEnd)
    }
    DllCall("HideCaret", "Ptr", RE.Hwnd)
}

; Remove the search highlight from the RichEdit (restore Auto background).
ClearSearchHighlight() {
    global SrchMatchStart, SrchMatchEnd
    If (SrchMatchStart < 0 || SrchMatchEnd <= SrchMatchStart)
        Return
    RE.SetSel(SrchMatchStart, SrchMatchEnd)
    RE.SetFont({BkColor: "Auto"})
    RE.SetSel(SrchMatchEnd, SrchMatchEnd)
    DllCall("HideCaret", "Ptr", RE.Hwnd)
    SrchMatchStart := -1
    SrchMatchEnd   := -1
}

; F3 — advance to the next match after the current one.
; If no current match exists, behaves like a fresh search.
SearchFindNext(*) {
    global SrchMatchEnd, FullText
    term := SrchBox.Value
    If (term = "" || Words.Length = 0 || FullText = "")
        Return
    ; Find the char offset just past the current match.  If there's no active
    ; match, start from the current reading position (or top, per tunable).
    If (SrchMatchEnd > 0) {
        startChar := SrchMatchEnd   ; already exclusive — no +1 needed
    } Else If (SearchFromCurrent && CurIdx > 0 && CurIdx <= Words.Length) {
        startChar := Words[CurIdx].start
    } Else {
        startChar := 0
    }
    SearchFrom(term, startChar, True)   ; status bar set internally
}

; ----------------------------------------------------------------------------------------------------------------------
; Settings persistence
; ----------------------------------------------------------------------------------------------------------------------
LoadSettings() {
    global TELastStampSeen, RecentFiles, RecentPositions
    If !FileExist(IniFile)
        Return
    Cfg.WPM            := Integer(IniRead(IniFile, "Reader", "WPM",            Cfg.WPM))
    Cfg.ChunkSize      := Integer(IniRead(IniFile, "Reader", "ChunkSize",      Cfg.ChunkSize))
    Cfg.Overlap        := Integer(IniRead(IniFile, "Reader", "Overlap",        Cfg.Overlap ? 1 : 0)) ? True : False
    Cfg.SentencePause  := Integer(IniRead(IniFile, "Reader", "SentencePause",  Cfg.SentencePause ? 1 : 0)) ? True : False
    Cfg.ListPauses     := Integer(IniRead(IniFile, "Reader", "ListPauses",     Cfg.ListPauses ? 1 : 0)) ? True : False
    Cfg.SmartPacing    := Integer(IniRead(IniFile, "Reader", "SmartPacing",    Cfg.SmartPacing ? 1 : 0)) ? True : False
    Cfg.CenterScroll   := Integer(IniRead(IniFile, "Reader", "CenterScroll",   Cfg.CenterScroll ? 1 : 0)) ? True : False
    Cfg.TTSMode        := Integer(IniRead(IniFile, "Reader", "TTSMode",       Cfg.TTSMode ? 1 : 0)) ? True : False
    Cfg.TTSVoiceId     := IniRead(IniFile, "Reader", "TTSVoiceId",     Cfg.TTSVoiceId)
    Cfg.HighlightColor := Integer(IniRead(IniFile, "Colors", "HighlightColor", Cfg.HighlightColor))
    Cfg.TextColor      := Integer(IniRead(IniFile, "Colors", "TextColor",      Cfg.TextColor))
    Cfg.BackColor      := Integer(IniRead(IniFile, "Colors", "BackColor",      Cfg.BackColor))
    Cfg.FontName       := IniRead(IniFile, "Font", "Name", Cfg.FontName)
    Cfg.FontSize       := Integer(IniRead(IniFile, "Font", "Size", Cfg.FontSize))
    Cfg.GuiW           := Integer(IniRead(IniFile, "srWindow", "W", Cfg.GuiW))
    Cfg.GuiH           := Integer(IniRead(IniFile, "srWindow", "H", Cfg.GuiH))

    ; LastFile is stored as "path" or "path, wordIdx"
    raw := IniRead(IniFile, "Session", "LastFile", "")
    Cfg.LastFile := ParseRecentEntry(raw, &lastIdx)
    If (Cfg.LastFile != "" && lastIdx > 0)
        RecentPositions[StrLower(Cfg.LastFile)] := lastIdx

    ; Seed the TE watcher stamp so we don't fire on a pre-existing conversion
    TELastStampSeen := IniRead(IniFile, "Session", "TEConvertedAt", "")

    ; Load recent files — each value is "path" or "path, wordIdx"; skip missing files
    RecentFiles := []
    Loop RecentFilesMax {
        raw := IniRead(IniFile, "Recent", "File" A_Index, "")
        p := ParseRecentEntry(raw, &idx)
        If (p = "" || !FileExist(p))
            Continue
        RecentFiles.Push(p)
        If (idx > 0)
            RecentPositions[StrLower(p)] := idx
    }
}

SaveSettings() {
    global RecentFiles, RecentPositions
    Critical
    DBG("SaveSettings ENTER  Cfg.WPM=" Cfg.WPM "  IsPlaying=" IsPlaying)
    DBG("SaveSettings  writing WPM")
    IniWrite(Cfg.WPM,                  IniFile, "Reader",  "WPM")
    DBG("SaveSettings  writing ChunkSize")
    IniWrite(Cfg.ChunkSize,             IniFile, "Reader",  "ChunkSize")
    DBG("SaveSettings  writing Overlap")
    IniWrite(Cfg.Overlap       ? 1 : 0, IniFile, "Reader",  "Overlap")
    DBG("SaveSettings  writing SentencePause")
    IniWrite(Cfg.SentencePause ? 1 : 0, IniFile, "Reader",  "SentencePause")
    DBG("SaveSettings  writing ListPauses")
    IniWrite(Cfg.ListPauses    ? 1 : 0, IniFile, "Reader",  "ListPauses")
    DBG("SaveSettings  writing SmartPacing")
    IniWrite(Cfg.SmartPacing   ? 1 : 0, IniFile, "Reader",  "SmartPacing")
    DBG("SaveSettings  writing CenterScroll")
    IniWrite(Cfg.CenterScroll  ? 1 : 0, IniFile, "Reader",  "CenterScroll")
    DBG("SaveSettings  writing TTSMode")
    IniWrite(Cfg.TTSMode       ? 1 : 0, IniFile, "Reader",  "TTSMode")
    DBG("SaveSettings  writing TTSVoiceId")
    IniWrite(Cfg.TTSVoiceId,            IniFile, "Reader",  "TTSVoiceId")
    DBG("SaveSettings  writing HighlightColor")
    IniWrite(Cfg.HighlightColor, IniFile, "Colors",  "HighlightColor")
    DBG("SaveSettings  writing TextColor")
    IniWrite(Cfg.TextColor,      IniFile, "Colors",  "TextColor")
    DBG("SaveSettings  writing BackColor")
    IniWrite(Cfg.BackColor,      IniFile, "Colors",  "BackColor")
    DBG("SaveSettings  writing FontName")
    IniWrite(Cfg.FontName,       IniFile, "Font",    "Name")
    DBG("SaveSettings  writing FontSize")
    IniWrite(Cfg.FontSize,       IniFile, "Font",    "Size")
    DBG("SaveSettings  writing GuiW")
    IniWrite(Cfg.GuiW,           IniFile, "srWindow",  "W")
    DBG("SaveSettings  writing GuiH")
    IniWrite(Cfg.GuiH,           IniFile, "srWindow",  "H")

    lf := Cfg.LastFile
    DBG("SaveSettings  writing LastFile  lf='" lf "'")
    If (lf != "") {
        idx := RecentPositions.Has(StrLower(lf)) ? RecentPositions[StrLower(lf)] : 0
        IniWrite(FormatRecentEntry(lf, idx), IniFile, "Session", "LastFile")
    } Else {
        IniWrite("", IniFile, "Session", "LastFile")
    }

    DBG("SaveSettings  writing Recent files")
    Loop RecentFilesMax {
        If (A_Index <= RecentFiles.Length) {
            p := RecentFiles[A_Index]
            idx := RecentPositions.Has(StrLower(p)) ? RecentPositions[StrLower(p)] : 0
            IniWrite(FormatRecentEntry(p, idx), IniFile, "Recent", "File" A_Index)
        } Else {
            IniWrite("", IniFile, "Recent", "File" A_Index)
        }
    }
    DBG("SaveSettings EXIT")
}

; ----------------------------------------------------------------------------------------------------------------------
; Debug logger. No-op when DebugLog is false. Appends timestamped lines to log file.
; Delete the log file manually between sessions for a clean slate.
; ----------------------------------------------------------------------------------------------------------------------
DBG(msg) {
    global DebugLog, DebugLogFile
    If (!DebugLog)
        Return
    FileAppend(FormatTime(A_Now, "MM-dd HH:mm:ss") "." SubStr(A_TickCount, -2) "  " msg "`n", DebugLogFile)
}

; ----------------------------------------------------------------------------------------------------------------------
; Parse a "path" or "path, wordIdx" INI value.
; Returns the path; sets idx via the ByRef param (0 if not present).
; ----------------------------------------------------------------------------------------------------------------------
ParseRecentEntry(raw, &idx) {
    idx := 0
    raw := Trim(raw)
    If (raw = "")
        Return ""
    ; Accept "path, wordIdx" (any trailing integer after the last comma-with-optional-space).
    ; Path itself could theoretically contain commas — regex anchors on the final
    ; ", <digits>" pair.
    If RegExMatch(raw, "^(.+?)\s*,\s*(\d+)$", &m) {
        idx := Integer(m[2])
        Return Trim(m[1])
    }
    Return raw   ; no valid trailing integer — whole string is the path
}

; ----------------------------------------------------------------------------------------------------------------------
; Build a "path, wordIdx" INI value (or just the path when idx is 0).
; All writers should use this so the on-disk format stays consistent with ParseRecentEntry.
; ----------------------------------------------------------------------------------------------------------------------
FormatRecentEntry(path, idx) => idx > 0 ? path ", " idx : path
