# SpeedReader
A reading pacer for text files.

![Screenshot of SpeedReader](https://github.com/kunkel321/SpeedReader/blob/main/SR%20Screencast%202026-04-28_11-30-07.gif)

From code comments
------------------

SpeedReader.ahk — A speed reading trainer for plain-text files

Author Steve (kunkel321) with Claude (Anthropic)

Version Date (see code)

Forum https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140586

Github https://github.com/kunkel321/SpeedReader

Requires AutoHotkey v2.0+  |  RichEdit.ahk by just-me (place in Tools\ folder) https://github.com/AHK-just-me/AHK2_RichEdit

OVERVIEW
--------
SpeedReader opens a .txt file and highlights a configurable "chunk" of words at a time,
advancing through the text at a user-set WPM rate.  Pauses are automatically inserted at
sentence, paragraph, and list-item boundaries.  The goal is to train faster reading by
giving the eye a single focal point that moves at a controlled pace.  Works well with
plain-text books from Project Gutenberg and similar sources.

SETUP
-----
 Portable mode (recommended): rename AutoHotkey64.exe to SpeedReader.exe and place it
 in the same folder as SpeedReader.ahk and RichEdit.ahk.  No installation needed.
 Standard mode: run SpeedReader.ahk directly with AHK v2 installed on the machine.
 Either way, RichEdit.ahk must be in the Tools\ folder.
 1. On first run, srSettings.ini is created automatically with sensible defaults.
 2. Open a .txt file via File > Open, by dragging a file onto the window, or by
    choosing from the recent-files list in the File menu.
 3. Press Play (or the Down arrow key) to begin.  Press again to pause.

CONTROLS
--------
 Play / Pause         ▶ Play button  —or—  Down arrow key (window must be active)
 Restart              ⟲ Restart button — clears highlight and rewinds to word 1
 Speed (WPM)          Big slider at the bottom of the window, plus:
                        Left / Right arrow keys  (±WPMHotkeyStep per press, default ±25)
                        Mouse wheel over the slider (wheel-up = faster, wheel-down = slower)
 Jump to any word     Double-click the word — playback restarts from that point immediately.
                        Works whether the reader is playing, paused, or stopped.
 Open file            File > Open  (Ctrl+O),  or drag-and-drop a .txt file onto the window
 Focus search box     Ctrl+F  (pauses the pacer if running; selects existing text)
 Recent files         Numbered list in the File menu (files that no longer exist are omitted)
 Resume position      When a file is re-opened that has a saved position, a prompt offers
                        to resume from the last reading point or start over.
                        Position is saved automatically on pause and on window close.

TOP TOOLBAR  (never moves during window resize)
-----------
 ▶ Play / ❚❚ Pause    Toggle playback
 ⟲ Restart            Rewind to the beginning
 Size                 Font size spin-box — live update, no restart needed
 Chunk                Words highlighted per tick (1–10). Larger = easier at high WPM.
 Status bar           Filename + word count while stopped; "Word X of Y (Z%)" while playing

ROW 2  (WPM display + checkboxes)
------
 WPM: N  [m:ss]       Large WPM readout.  Once ~10 words have been read a rolling
                        time-remaining estimate appears in [m:ss] format, updated at the
                        interval set by TimeRemainingUpdateMs (default once per second).
                        The estimate uses actual dwell times, so it accounts for sentence
                        pauses, smart pacing, chunk size, etc. automatically.

 Overlap              Sliding-window mode: the chunk-sized highlight advances one word per
                        tick instead of jumping by a whole chunk.  Gives a smoother,
                        flowing feel.  Sentence/list pause multipliers are suppressed in
                        this mode (they would disrupt the slide); Smart pacing still works.

 Sentence pause       Dwell longer at sentence ends (.  !  ?  …) and strong mid-sentence
                        breaks (;  :  em-dash).  Paragraph ends always pause regardless.
                        Comma pauses are lighter and never clip a chunk boundary.
                        Common abbreviations (Mr. Dr. etc. e.g. p. …) are excluded from
                        sentence detection so they don't trigger false pauses.

 List pauses          Detect short lines that look like list or enumeration items and
                        pause at the end of each.  A line qualifies if it is short
                        (≤ ListMaxWords words), doesn't end in a comma/semicolon/hyphen,
                        doesn't end in a bare conjunction (and/or/but…), and the next
                        line starts with a capital letter.

 Smart pacing         Scale each word's dwell time by its reading difficulty:
                          Stopwords (the, of, and …)   → StopwordWeight × base  (faster)
                          Monosyllabic content words   → MonoWeight × base      (baseline)
                          Polysyllabic words           → +ExtraSyllableWeight per extra
                                                         syllable beyond the first (slower)
                        Syllables are counted with a vowel-group heuristic; silent trailing
                        'e' is subtracted.  Good enough for relative weighting purposes.

 Center scroll        Keep the highlighted word vertically centered in the reading pane
                        as the text advances.  When off, the pane scrolls only when the
                        highlight reaches the bottom edge (standard behavior).
                        Scrolling is in whole-line increments (RichEdit limitation).

 Read Aloud            Speaks the text using Windows' built-in SAPI5 text-to-speech.
                        SAPI is queued one sentence at a time; within a sentence the
                        highlight follows SAPI's own word-boundary events, so the voice
                        and the highlight stay in genuine sync.  If a voice doesn't
                        report word boundaries, an internal fallback pacer (the same
                        WPM/weighted dwell-time math the silent pacer uses) carries the
                        highlight instead, and each sentence's end resyncs to the last
                        word once SAPI actually finishes speaking it. Only available
                        at or below TTSMaxWPM (see the tunables near the top of the
                        script) since spoken word stops being intelligible well before
                        the top of the WPM slider's range; the checkbox disables itself
                        automatically above that speed, and re-enables itself when WPM
                        drops back down. Chunk / Overlap / Sentence pause / List pauses /
                        Smart pacing are all timer-engine concepts and are grayed out
                        while Read Aloud is active. Play/Pause and double-click-to-jump
                        work the same as always. The Voice dropdown next to the checkbox
                        lists every SAPI voice installed on this machine; "(Default
                        voice)" leaves whatever Windows considers the default in place.
                        Changing the voice takes effect on the next launch, not
                        immediately — restart SpeedReader after picking a new one.

COLOR / FONT / SEARCH ROW  (bottom band, Row 1)
-------------------------
 Highlight / Text / Background
                      Clickable colored buttons — click to open the Windows color picker.
                        Changes apply immediately to live text.
 Font                 Drop-down of preset font faces (condensed).
 Search               Incremental search box — results highlighted as you type (debounced).
                        Literal by default — "first second" matches the exact phrase,
                        including punctuation ("Mr. Darcy" matches literally).  Matching
                        is case-insensitive and can span multiple words.
                        Regex mode: prefix the term with '/' (optional trailing '/'):
                          /first\s+second/   — first + any whitespace + second
                          /\bthe\s+\w+ing\b/ — 'the' followed by an -ing word
                          /^Chapter \d+/m    — multi-line anchors work
                        Invalid regex patterns show a brief error in the status bar.
                        Ctrl+F focuses the search box (pauses the pacer if running).
                        F3 advances to the next match (honors current mode).
                        Disabled while the pacer is running; re-enabled on pause.
                        Clearing the box removes the search highlight immediately.

MENUS
-----
 File > Open                  Standard open dialog, filtered to .txt files  (Ctrl+O)
 File > Convert PDF/EPUB/TXT… Launches TextExtractor.ahk companion tool
 File > Open srSettings.ini     Opens the INI in your default text editor
 File > Recently converted    Submenu of *.txt files in the Converted\ subfolder (newest first)
 File > 1 … N                 Recent files, most-recent-first (missing files skipped)
 File > Exit
 Links > Project Gutenberg    https://www.gutenberg.org/ebooks/results/
 Links > AutoHotkey forum     Forum thread for this script (set URL_AhkForum below)
 Links > GitHub repo          Repository for this script (set URL_GitHub below)
 Debug > Token analysis       ListView of tokenization flags for ~80 words around the
                                current reading position.  Columns: index, text,
                                endsSentence, endsParagraph, endsLine, endsListItem,
                                endsCommaLike, weight.  Ctrl+C copies all rows as CSV.

TEXTEXTRACTOR INTEGRATION
-------------------------
 SpeedReader polls srSettings.ini every 1.5 s for a new TEConvertedAt timestamp written
 by TextExtractor after each successful conversion.  When a new stamp is detected the
 converted file is loaded silently; the status bar shows the filename.
 The polling only fires when the SpeedReader window is active, so there are no stale
 loads while the user is working in TextExtractor.

SETTINGS FILE  (srSettings.ini, auto-created next to the script on first run)
-------------
 All GUI settings save automatically on change and restore on next launch.
 [Reader]   WPM, ChunkSize, Overlap, SentencePause, ListPauses, SmartPacing, CenterScroll
 [Colors]   HighlightColor, TextColor, BackColor  (stored as decimal RGB integers)
 [Font]     Name, Size
 [srWindow] W, H  (saved on close)
 [Session]  LastFile, TEConvertedAt
            LastFile is stored as "path" or "path, wordIdx" and auto-loaded on launch.
            TEConvertedAt is the sentinel timestamp written by TextExtractor.
 [Recent]   File1 … FileN — each value is "path" or "path, wordIdx".
            The word index is the saved reading position for that file.
            Missing files are silently skipped on load.

DEVELOPER TUNABLES  (near the top of this file, above the Cfg block)
------------------
 Pacing object        Dwell-time multipliers applied on top of the base WPM rate:
                        SentenceMult        after .!?…        (default 1.8×)
                        ParagraphMult       after blank line   (default 2.5×)
                        CommaMult           after comma        (default 1.15×)
                        SemicolonColonMult  after ; : em-dash  (default 1.5×)
                        ListItemMult        after list item    (default 1.4×)
                        StopwordWeight      fast-word weight   (default 0.5)
                        MonoWeight          baseline weight    (default 1.0)
                        ExtraSyllableWeight per extra syllable (default 0.3)
 WPMHotkeyStep        Arrow-key WPM step size (default 25)
 ListMaxWords         Max line length in words for list-item detection (default 12)
 TimeRemainingUpdateMs  How often [m:ss] refreshes, in ms (default 1000 = once/second)
 RecentFilesMax       How many recent files to remember in the File menu (default 9)
 SearchFromCurrent    true  → search starts from current reading position (default)
                      false → search always starts from top of document
 SearchDebounceMs     Delay (ms) after last keystroke before search fires (default 300)
 URL_AhkForum         AHK forum thread URL — fill in when known
 URL_GitHub           GitHub repo URL — fill in when known

TECHNICAL NOTES
---------------
 Uses Just Me's RichEdit.ahk wrapper (RICHEDIT50W from Msftedit.dll, RichEdit v4.1).
 
 All character offsets are zero-based UTF-16 code units, matching RichEdit's internal
   indexing.  AHK v2 strings are also UTF-16, so StrLen() and offsets always agree.
 
 Line endings are normalized to bare LF on load because RichEdit stores CR-only
   internally.  Feeding CRLF without stripping \r causes one-character offset drift per

line — the highlight gets progressively misaligned through the document.
 
The blinking caret is permanently suppressed by hooking WM_SETFOCUS and calling
   CreateCaret(hwnd, 0, 0, 0) + HideCaret each time RichEdit gains focus, plus after
   every programmatic SetSel call.  A zero-width caret is invisible regardless of blink.

Drag-and-drop uses DragAcceptFiles + WM_DROPFILES.  Only the first dropped file is
   used; non-.txt files are rejected with a message box.

Mouse-wheel direction on the WPM slider is flipped (wheel-up = increase WPM) via a
   WM_MOUSEWHEEL hook that only intercepts when the cursor is over the slider hwnd.

Center-scroll uses EM_LINEFROMCHAR, EM_GETFIRSTVISIBLELINE, and EM_LINESCROLL.
   Line height is measured from two currently-visible lines (not line 0/1) so the
   measurement stays valid after the view has scrolled away from the top.

UPDATE NOTES
------------
June 2026 -- Based on suggestion by andymbody, added support for read aloud. 

July 2026 -- Importand bug fix from rommmcek, see change log in forum.
