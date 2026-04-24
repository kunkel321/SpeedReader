; ======================================================================================================================
; TextExtractor.ahk — PDF / EPUB → plain-text converter companion for SpeedReader
; Author: Steve (kunkel321) with Claude (Anthropic)
; Version Date: 4-24-2026
; Requires: AutoHotkey v2.0+
;           pdftotext.exe (Poppler CLI, GPL v2) — place in the Tools\ sub-folder next to this script
;           PowerShell + .NET System.IO.Compression.ZipFile (built into Windows) for EPUB extraction
;
; OVERVIEW
; --------
; TextExtractor converts PDF and EPUB files to clean plain-text (.txt) so they can be
; opened in SpeedReader.  Drag-and-drop one or more files onto the window, or use the
; Browse button.  After conversion you can optionally launch SpeedReader with the result.
;
; PDF  — delegates to pdftotext.exe (Poppler build, shippable alongside this script).
;         Best for single-column prose (Project Gutenberg PDFs, essays, reports).
;         Multi-column layouts, tables, and footnotes may need manual cleanup.
;
; EPUB — uses PowerShell/.NET ZipFile to unpack, then pure AHK XML/HTML parsing.
;         Reads the OPF manifest for chapter order, strips HTML tags, joins chapters.
;         No external tool needed beyond built-in Windows PowerShell.
;
; TXT  — Gutenberg reflow: rejoins hard-wrapped lines that were broken mid-sentence
;         (lines ending without terminal punctuation, followed by a lowercase word).
;         Preserves intentional paragraph breaks (double newlines).
;
; SETUP
; -----
;  1. Place TextExtractor.ahk next to SpeedReader.ahk (same folder).
;  2. Create a Tools\ sub-folder and place pdftotext.exe inside it.
;     Download Poppler for Windows (GPL): https://github.com/oschwartz10612/poppler-windows/releases
;     You only need pdftotext.exe from the bin\ folder of that release.
;  3. Run with AHK v2.  Settings persist to TextExtractor.ini next to the script.
;
; CONTROLS
; --------
;  Browse        Open a file picker (PDF, EPUB, or TXT)
;  Drop zone     Drag one or more files onto the list
;  Convert       Extract/reflow all queued files
;  Clear list    Remove all files from the queue
;  Open in SR    Launch SpeedReader with the most recently converted file
;  Open folder   Open the output folder in Explorer
;
; OUTPUT
; ------
;  Output .txt files are written to the Converted\ sub-folder by default.
;  You can override this by unchecking "Save to a single output folder" or browsing
;  to a different folder.
;
; POST-PROCESSING PASSES (applied to PDF and EPUB output)
; ----------------------
;  • CRLF / CR  → LF  (SpeedReader requires bare LF)
;  • Hyphenated line-breaks  (word-\n)  → rejoined word  (optional, default ON)
;  • Runs of 3+ blank lines  → 2 blank lines  (paragraph spacing normalised)
;  • Leading/trailing whitespace trimmed per line
;
; SETTINGS  (TextExtractor.ini, auto-created on first run)
; --------
;  [Window]   W, H
;  [Options]  RejoinHyphens, UseOutputFolder, OutputFolder, OpenInSR, ReflowTxt, LastFile
; ======================================================================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

SetWinDelay    -1
SetControlDelay -1
TraySetIcon("imageres.dll", 333)

; ======================================================================================================================
; Constants / paths
; ======================================================================================================================
global AppName      := "TextExtractor"
global IniFile      := A_ScriptDir "\TextExtractor.ini"
global PdfTool      := A_ScriptDir "\Tools\pdftotext.exe"
global SpeedReader  := A_ScriptDir "\SpeedReader.ahk"
global TempBase     := A_Temp "\TextExtractor_epub_"

; Match SpeedReader's color palette (from acSettings.ini [Colors])
; COLORREF decimals → HTML: HighlightColor=15527806 (#7EEFEC), TextColor=1913944 (#58341D), BackColor=15198183 (#E7E7E7)
global ColHL  := 0xEC8F7E   ; warm accent  (desaturated from SR highlight)
global ColTx  := 0x1D3458   ; dark brown-blue (SR TextColor)
global ColBg  := 0xE7E7E7   ; light gray (SR BackColor)

; ======================================================================================================================
; Configuration (overridden by INI on load)
; ======================================================================================================================
global Cfg := {
    GuiW:            680,
    GuiH:            480,
    RejoinHyphens:   True,
    ReflowTxt:       True,
    UseOutputFolder: True,
    OutputFolder:    A_ScriptDir "\Converted",
    OpenInSR:        True,
    LastFile:        ""
}

LoadSettings()

; ======================================================================================================================
; Runtime state
; ======================================================================================================================
global FileQueue  := []   ; array of full paths queued for conversion
global LastTxtOut := ""   ; path of most recently converted .txt (for Open in SR)

; ======================================================================================================================
; Build GUI
; ======================================================================================================================
MainGui := Gui("+Resize +MinSize500x360", AppName)
MainGui.OnEvent("Size",  OnGuiSize)
MainGui.OnEvent("Close", OnGuiClose)
MainGui.MarginX := 10
MainGui.MarginY := 10
MainGui.BackColor := Format("{:06X}", ColBg)

; --- Menu bar ---------------------------------------------------------------------------------------------------------
FileMenu := Menu()
FileMenu.Add("&Browse for file...`tCtrl+O", DoBrowse)
FileMenu.Add("Open &TextExtractor.ini",     (*) => (FileExist(IniFile) ? Run(IniFile) : MsgBox("INI not yet created.", AppName, 64)))
FileMenu.Add()
FileMenu.Add("E&xit", (*) => OnGuiClose())

HelpMenu := Menu()
HelpMenu.Add("&About",     ShowAbout)
HelpMenu.Add("&PDF tool",  ShowPdfToolHelp)

MenuBarObj := MenuBar()
MenuBarObj.Add("&File", FileMenu)
MenuBarObj.Add("&Help", HelpMenu)
MainGui.MenuBar := MenuBarObj

; Ctrl+O shortcut
HotIfWinActive("ahk_id " MainGui.Hwnd)
Hotkey("^o", DoBrowse)
HotIfWinActive()

; --- Header label -----------------------------------------------------------------------------------------------------
LblHead := MainGui.AddText("xm ym w" (Cfg.GuiW - 20) " h24 +0x200 Center", "PDF / EPUB / TXT Converter  (companion for SpeedReader)")
LblHead.SetFont("s11 Bold c" Format("{:06X}", ColTx))

; --- File list (ListView) ---------------------------------------------------------------------------------------------
global LV := MainGui.AddListView("xm y+8 w" (Cfg.GuiW - 20) " h" (Cfg.GuiH - 230) " -Multi +LV0x2000 Grid", ["File", "Type", "Status"])
LV.ModifyCol(1, 340, "File")
LV.ModifyCol(2,  50, "Type")
LV.ModifyCol(3, 180, "Status")
LV.OnEvent("DoubleClick", OnLVDoubleClick)

; --- Button row -------------------------------------------------------------------------------------------------------
BtnBrowse  := MainGui.AddButton("xm y+6 w110 h28", "📂  Browse...")
BtnBrowse.OnEvent("Click", DoBrowse)

BtnConvert := MainGui.AddButton("x+6 yp wp hp", "▶  Convert")
BtnConvert.OnEvent("Click", DoConvert)
BtnConvert.SetFont("Bold")

BtnClear   := MainGui.AddButton("x+6 yp wp hp", "✕  Clear list")
BtnClear.OnEvent("Click", DoClear)

global BtnOpenSR := MainGui.AddButton("x+6 yp wp hp", "▷  Open in SR")
BtnOpenSR.OnEvent("Click", DoOpenInSR)
BtnOpenSR.Enabled := False

global BtnOpenFolder := MainGui.AddButton("x+6 yp wp hp", "📁  Open folder")
BtnOpenFolder.OnEvent("Click", DoOpenFolder)
BtnOpenFolder.Enabled := False

; --- Options group ----------------------------------------------------------------------------------------------------
GrpOpts := MainGui.AddGroupBox("xm y+10 w" (Cfg.GuiW - 20) " h154", "Options")

global CbxHyphens := MainGui.AddCheckbox("xm+16 yp+22", "Rejoin hyphenated line-breaks  (word-↵  →  word)")
CbxHyphens.Value := Cfg.RejoinHyphens
CbxHyphens.OnEvent("Click", (*) => (Cfg.RejoinHyphens := CbxHyphens.Value, SaveSettings()))

global CbxReflow := MainGui.AddCheckbox("xm+16 y+6", "Reflow hard-wrapped TXT lines  (Gutenberg-style OCR text)")
CbxReflow.Value := Cfg.ReflowTxt
CbxReflow.OnEvent("Click", (*) => (Cfg.ReflowTxt := CbxReflow.Value, SaveSettings()))

global CbxUseFolder := MainGui.AddCheckbox("xm+16 y+6", "Save all output to a single folder:")
CbxUseFolder.Value := Cfg.UseOutputFolder
CbxUseFolder.OnEvent("Click", OnUseFolderChanged)

; Folder path edit + browse button on their own line, indented to align with checkbox text
global EdFolder  := MainGui.AddEdit("xm+32 y+4 w" (Cfg.GuiW - 130) " h22 ReadOnly", Cfg.OutputFolder)
global BtnFolder := MainGui.AddButton("x+4 yp-1 w80 h24", "Browse…")
BtnFolder.OnEvent("Click", BrowseOutputFolder)
UpdateFolderControls()

global CbxOpenSR := MainGui.AddCheckbox("xm+16 y+8", "Auto-launch SpeedReader after conversion")
CbxOpenSR.Value := Cfg.OpenInSR
CbxOpenSR.OnEvent("Click", (*) => (Cfg.OpenInSR := CbxOpenSR.Value, SaveSettings()))

; Show note if SpeedReader.ahk not found beside this script
If !FileExist(SpeedReader)
    MainGui.AddText("x+12 yp+3 w220 c808080", "(SpeedReader.ahk not found in same folder)")

; --- Status bar (bottom) -----------------------------------------------------------------------------------------------
global LblStatus := MainGui.AddText("xm y+16 w" (Cfg.GuiW - 20) " h20", "Ready.  Drop PDF, EPUB, or TXT files onto the list, or use Browse.")
LblStatus.SetFont("s9 c" Format("{:06X}", ColTx))

; ======================================================================================================================
; Show GUI + enable drag-and-drop
; ======================================================================================================================
MainGui.Show("w" Cfg.GuiW " h" Cfg.GuiH)

; Drag-and-drop files onto the ListView
DllCall("shell32\DragAcceptFiles", "Ptr", MainGui.Hwnd, "Int", 1)
OnMessage(0x0233, OnDropFiles)

Return  ; end of auto-execute

; ======================================================================================================================
; ======================================================================================================================
; FUNCTIONS
; ======================================================================================================================
; ======================================================================================================================

; ----------------------------------------------------------------------------------------------------------------------
; GUI resize
; ----------------------------------------------------------------------------------------------------------------------
OnGuiSize(GuiObj, MinMax, W, H) {
    global LblHead, LV, BtnBrowse, BtnConvert, BtnClear, BtnOpenSR, BtnOpenFolder
    global GrpOpts, CbxHyphens, CbxReflow, CbxUseFolder, EdFolder, BtnFolder, CbxOpenSR, LblStatus
    If (MinMax = -1)
        Return
    margin := 10

    ; Suspend redraw on the whole window while we reposition all ~13 controls,
    ; then force one clean repaint at the end. Without this, the rapid-fire
    ; Move() calls leave ghost renderings of controls at their previous
    ; positions (visible on vertical-only resize and at initial Show).
    ; WM_SETREDRAW is used instead of WS_EX_COMPOSITED because the latter
    ; causes the ListView to flicker continuously.
    ; DllCall is used in place of SendMessage because the initial OnGuiSize
    ; fires during Show() before DetectHiddenWindows-style matching can find
    ; the window, even though we have a valid HWND.
    static WM_SETREDRAW := 0x000B
    static RDW_INVALIDATE := 0x0001, RDW_ERASE := 0x0004, RDW_ALLCHILDREN := 0x0080
    DllCall("user32\SendMessageW", "Ptr", GuiObj.Hwnd, "UInt", WM_SETREDRAW, "Ptr", 0, "Ptr", 0)

    ; Stretch header
    LblHead.Move(margin, , W - 2*margin)

    ; Stretch ListView — leave ~254px for everything below it
    LV.GetPos(&lvX, &lvY, , )
    newLVH := H - lvY - 274
    If (newLVH < 60)
        newLVH := 60
    LV.Move( , , W - 2*margin, newLVH)

    ; Reposition buttons below LV
    LV.GetPos( , &ly2, , &lh2)
    btnY := ly2 + lh2 + 6
    BtnBrowse.Move(margin, btnY)
    BtnConvert.Move(margin + 116, btnY)
    BtnClear.Move(margin + 232, btnY)
    BtnOpenSR.Move(margin + 348, btnY)
    BtnOpenFolder.Move(margin + 464, btnY)

    ; Reposition options group
    GrpOpts.Move(margin, btnY + 38, W - 2*margin)
    CbxHyphens.Move(margin + 16,  btnY + 60)
    CbxReflow.Move(margin + 16,   btnY + 82)
    CbxUseFolder.Move(margin + 16, btnY + 104)
    ; Folder path row — full width minus Browse button
    EdFolder.Move(margin + 32, btnY + 126, W - 2*margin - margin - 32 - 88)
    EdFolder.GetPos(&efX, &efY, &efW)
    BtnFolder.Move(efX + efW + 4, efY - 1)
    CbxOpenSR.Move(margin + 16,   btnY + 152)

    ; Status bar at very bottom
    LblStatus.Move(margin, H - 28, W - 2*margin)

    ; Stretch ListView column 1 proportionally
    LV.ModifyCol(1, Max(180, W - 290))

    ; Re-enable drawing and force a single full invalidate for all children.
    DllCall("user32\SendMessageW", "Ptr", GuiObj.Hwnd, "UInt", WM_SETREDRAW, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", GuiObj.Hwnd, "Ptr", 0, "Ptr", 0,
            "UInt", RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN)
}

; ----------------------------------------------------------------------------------------------------------------------
; Window close
; ----------------------------------------------------------------------------------------------------------------------
OnGuiClose(*) {
    global Cfg
    MainGui.GetClientPos(, , &cw, &ch)
    Cfg.GuiW := cw
    Cfg.GuiH := ch
    SaveSettings()
    ExitApp()
}

; ----------------------------------------------------------------------------------------------------------------------
; Browse for PDF/EPUB/TXT files
; ----------------------------------------------------------------------------------------------------------------------
DoBrowse(*) {
    global FileQueue, Cfg
    f := FileSelect("M1", Cfg.LastFile, "Select PDF, EPUB, or TXT files", "Documents (*.pdf;*.epub;*.txt)")
    If (f = "")
        Return
    ; FileSelect "M" returns an array when multiple files selected
    If (Type(f) = "Array") {
        If (f.Length = 0)
            Return
        For path in f
            QueueFile(path)
        Cfg.LastFile := f[1]
    } Else {
        QueueFile(f)
        Cfg.LastFile := f
    }
    SaveSettings()
}

; ----------------------------------------------------------------------------------------------------------------------
; Add a file path to the queue (deduplicating)
; ----------------------------------------------------------------------------------------------------------------------
QueueFile(path) {
    global FileQueue, LV, LblStatus
    SplitPath(path, &name, , &ext)
    ext := StrUpper(ext)
    If (ext != "PDF" && ext != "EPUB" && ext != "TXT") {
        LblStatus.Text := "Skipped (not PDF, EPUB, or TXT): " name
        Return
    }
    ; Deduplicate
    For p in FileQueue {
        If (StrLower(p) = StrLower(path))
            Return
    }
    FileQueue.Push(path)
    LV.Add("", name, ext, "Queued")
    LblStatus.Text := FileQueue.Length " file(s) queued."
}

; ----------------------------------------------------------------------------------------------------------------------
; Clear the file queue
; ----------------------------------------------------------------------------------------------------------------------
DoClear(*) {
    global FileQueue, LastTxtOut, LV, LblStatus, BtnOpenSR
    FileQueue := []
    LV.Delete()
    LastTxtOut := ""
    BtnOpenSR.Enabled := False
    LblStatus.Text := "List cleared."
}

; ----------------------------------------------------------------------------------------------------------------------
; WM_DROPFILES handler
; ----------------------------------------------------------------------------------------------------------------------
OnDropFiles(wParam, lParam, msg, hwnd) {
    count := DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0)
    Loop count {
        buf := Buffer(8192, 0)   ; 4096 UTF-16 chars × 2 bytes — handles long-path-aware Windows
        DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", A_Index - 1, "Ptr", buf, "UInt", 4096)   ; UInt param is in CHARS, not bytes
        QueueFile(StrGet(buf, "UTF-16"))
    }
    DllCall("shell32\DragFinish", "Ptr", wParam)
}

; ----------------------------------------------------------------------------------------------------------------------
; ListView double-click — open the converted .txt in the default text editor
; ----------------------------------------------------------------------------------------------------------------------
OnLVDoubleClick(LVCtrl, RowNum) {
    global FileQueue, Cfg
    If (RowNum = 0 || RowNum > FileQueue.Length)
        Return
    srcPath := FileQueue[RowNum]
    outPath := DetermineOutputPath(srcPath)
    If FileExist(outPath)
        Run(outPath)   ; opens in default .txt handler
}

; ----------------------------------------------------------------------------------------------------------------------
; Convert all queued files
; ----------------------------------------------------------------------------------------------------------------------
DoConvert(*) {
    global FileQueue, LastTxtOut, LV, LblStatus, BtnOpenSR, BtnOpenFolder, Cfg, PdfTool, SpeedReader, AppName
    If (FileQueue.Length = 0) {
        MsgBox("No files in the queue.`nUse Browse or drag files onto the list.", AppName, 48)
        Return
    }

    ; Validate PDF tool if any PDFs are queued
    hasPdf := False
    For p in FileQueue {
        SplitPath(p, , , &ext)
        If (StrLower(ext) = "pdf")
            hasPdf := True
    }
    If (hasPdf && !FileExist(PdfTool)) {
        MsgBox("pdftotext.exe not found.`n`nExpected location:`n" PdfTool
             . "`n`nDownload Poppler for Windows (GPL) from:`nhttps://github.com/oschwartz10612/poppler-windows/releases`n`nCopy pdftotext.exe from its bin\ folder into the Tools\ sub-folder next to this script.",
               AppName, 48)
        Return
    }

    successCount := 0
    For i, path in FileQueue {
        SplitPath(path, &name, &dir, &ext)
        LV.Modify(i, , , , "Processing…")
        LblStatus.Text := "Processing " name " …"

        outPath := DetermineOutputPath(path)
        ok := False
        errMsg := ""

        Try {
            If (StrLower(ext) = "pdf")
                ok := ExtractPdf(path, outPath, &errMsg)
            Else If (StrLower(ext) = "epub")
                ok := ExtractEpub(path, outPath, &errMsg)
            Else If (StrLower(ext) = "txt")
                ok := ReflowTxt(path, outPath, &errMsg)
        } Catch As e {
            errMsg := e.Message
            ok := False
        }

        If ok {
            statusText := "✔ Done → " FileBaseName(outPath)
            If (errMsg != "")
                statusText .= "  (" errMsg ")"
            LV.Modify(i, , , , statusText)
            LastTxtOut := outPath
            successCount++
        } Else {
            LV.Modify(i, , , , "✘ Error: " errMsg)
        }
    }

    BtnOpenSR.Enabled    := (LastTxtOut != "")
    BtnOpenFolder.Enabled := (LastTxtOut != "")
    LblStatus.Text := successCount " of " FileQueue.Length " file(s) processed successfully."

    If (successCount > 0 && Cfg.OpenInSR && FileExist(SpeedReader) && LastTxtOut != "")
        DoOpenInSR()
}

; ----------------------------------------------------------------------------------------------------------------------
; Determine where to write the output .txt
; ----------------------------------------------------------------------------------------------------------------------
DetermineOutputPath(srcPath) {
    global Cfg
    SplitPath(srcPath, &name, &srcDir, , &nameNoExt)
    outName := nameNoExt ".txt"
    outFolder := (Cfg.UseOutputFolder && Cfg.OutputFolder != "") ? Cfg.OutputFolder : srcDir
    If !DirExist(outFolder)
        DirCreate(outFolder)
    outPath := outFolder "\" outName
    If !FileExist(outPath)
        Return outPath
    ; Disambiguate: book.txt → book (2).txt, book (3).txt, ...
    Loop 99 {
        candidate := outFolder "\" nameNoExt " (" (A_Index + 1) ").txt"
        If !FileExist(candidate)
            Return candidate
    }
    Return outPath   ; give up and overwrite if we somehow hit 100 copies
}

; ----------------------------------------------------------------------------------------------------------------------
; PDF extraction via pdftotext.exe
; ----------------------------------------------------------------------------------------------------------------------
ExtractPdf(srcPath, outPath, &errMsg) {
    global PdfTool
    ; -nopgbrk  suppresses form-feed chars between pages
    ; -enc UTF-8 ensures output is UTF-8
    ; Wrap paths in quotes to handle spaces.
    ; Working directory is the Tools\ folder so Windows finds Poppler's sibling DLLs.
    cmd := '"' PdfTool '" -nopgbrk -enc UTF-8 "' srcPath '" "' outPath '"'
    toolDir := ""
    SplitPath(PdfTool, , &toolDir)
    RunWait(cmd, toolDir, "Hide", &exitCode)

    ; pdftotext returns non-zero for recoverable warnings (minor PDF issues, font
    ; substitutions, etc.) even when the output was written successfully.
    ; So: check the output file first — if it exists and has content, treat it as
    ; success regardless of exit code.  Only fail if the file is missing or empty.
    If FileExist(outPath) {
        fileSize := FileGetSize(outPath)
        If (fileSize > 0) {
            If (exitCode != 0)
                errMsg := "warning: pdftotext exit code " exitCode " (output OK)"
            ; Post-process
            text := FileRead(outPath, "UTF-8")
            text := PostProcess(text)
            FileOpen(outPath, "w", "UTF-8").Write(text)
            Return True
        }
        ; File exists but is empty — real failure
        errMsg := "pdftotext produced an empty file (exit code " exitCode ")."
                . "`n`nThe PDF may be scanned/image-only (no selectable text)."
        Return False
    }

    ; Output file was not created at all — hard failure.
    If (exitCode != 0)
        errMsg := "pdftotext failed (exit code " exitCode ")."
                . "`n`nPossible causes:"
                . "`n• Missing Poppler DLLs — copy all files from the Poppler bin\ folder into Tools\, not just pdftotext.exe"
                . "`n• PDF is password-protected or corrupt"
    Else
        errMsg := "pdftotext ran (exit 0) but did not create the output file."
    Return False
}

; ----------------------------------------------------------------------------------------------------------------------
; EPUB extraction via PowerShell Expand-Archive (synchronous) + pure AHK XML parsing
; Steps:
;   1. Unzip EPUB to a temp folder using PowerShell Expand-Archive (synchronous, reliable)
;   2. Parse META-INF/container.xml to locate content.opf
;   3. Parse content.opf <spine> to get reading order of XHTML items
;   4. Parse each XHTML file: strip tags, decode entities, join with blank lines
;   5. Post-process and write output
; ----------------------------------------------------------------------------------------------------------------------
ExtractEpub(srcPath, outPath, &errMsg) {
    global TempBase
    tempDir := TempBase Format("{:X}", A_TickCount)

    Try {
        ; --- Step 1: Unzip via PowerShell Expand-Archive -----------------------------------------------------------------
        ; RunWait with powershell.exe is fully synchronous — returns only when done.
        ; -LiteralPath handles spaces and special chars in the path.
        ; Escape single-quotes in paths by doubling them for PS string literals.
        ; Write a temp .ps1 file so we avoid ALL shell quoting issues with
        ; special characters in paths (parentheses, apostrophes, brackets, etc.)
        psScript  := A_Temp '\TextExtractor_expand.ps1'
        psErrFile := A_Temp '\TextExtractor_ps_err.txt'
        psOutFile := A_Temp '\TextExtractor_ps_out.txt'

        srcEsc  := StrReplace(srcPath,  "'", "''")
        destEsc := StrReplace(tempDir,  "'", "''")
        errEsc  := StrReplace(psErrFile, "'", "''")
        outEsc  := StrReplace(psOutFile, "'", "''")

        ps1Text := "Try {`r`n"
                 . "    Add-Type -Assembly 'System.IO.Compression.FileSystem'`r`n"
                 . "    [System.IO.Compression.ZipFile]::ExtractToDirectory('" srcEsc "', '" destEsc "')`r`n"
                 . "    'OK' | Out-File -FilePath '" outEsc "' -Encoding UTF8`r`n"
                 . "} Catch {`r`n"
                 . "    `$_.Exception.Message | Out-File -FilePath '" errEsc "' -Encoding UTF8`r`n"
                 . "    exit 1`r`n"
                 . "}"
        FileOpen(psScript, "w", "UTF-8-RAW").Write(ps1Text)

        RunWait('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' psScript '"', , "Hide", &psExit)

        ; Capture PS stderr BEFORE deleting the files, so we can surface it on failure.
        psErr := ""
        If FileExist(psErrFile) {
            Try psErr := Trim(FileRead(psErrFile, "UTF-8"))
        }
        Try FileDelete(psErrFile)
        Try FileDelete(psOutFile)
        Try FileDelete(psScript)

        ; Success check: container.xml existence is the reliable indicator.
        If !FileExist(tempDir "\META-INF\container.xml") {
            errMsg := "EPUB unpack failed — container.xml not found"
                    . (psErr != "" ? "`nPowerShell: " psErr : "")
            Return False
        }

        ; --- Step 2: Find the OPF file ----------------------------------------------------------------------------------
        ; Primary: parse META-INF/container.xml which points to the OPF by name
        containerXml := FileRead(tempDir "\META-INF\container.xml", "UTF-8")
        opfRelPath := ""
        If RegExMatch(containerXml, 'full-path="([^"]+\.opf)"', &m)
            opfRelPath := m[1]

        ; Fallback: search recursively for any *.opf file (handles package.opf, book.opf, etc.)
        If (opfRelPath = "" || !FileExist(tempDir "\" StrReplace(opfRelPath, "/", "\"))) {
            Loop Files, tempDir "\*.opf", "R" {
                ; Make path relative to tempDir
                opfRelPath := SubStr(A_LoopFileFullPath, StrLen(tempDir) + 2)
                Break
            }
        }

        If (opfRelPath = "") {
            errMsg := "No OPF file found in EPUB"
            Return False
        }

        opfRelPathBS := StrReplace(opfRelPath, "/", "\")
        SplitPath(opfRelPathBS, , &opfDir)
        opfPath := tempDir "\" opfRelPathBS
        If !FileExist(opfPath) {
            errMsg := "OPF not found at: " opfPath
            Return False
        }
        opfText := FileRead(opfPath, "UTF-8")

        ; --- Step 3: Build id→href map from <manifest>, then get spine order --------------------------------------------
        ; Manifest: <item href="..." id="..." .../> — attributes may appear in any order
        idHref := Map()
        pos := 1
        While RegExMatch(opfText, 'i)<item\b([^>]+)>', &im, pos) {
            attrs := im[1]
            hasId   := RegExMatch(attrs, 'i)\bid="([^"]+)"',   &aid)
            hasHref := RegExMatch(attrs, 'i)\bhref="([^"]+)"', &ahr)
            If (hasId && hasHref)
                idHref[aid[1]] := ahr[1]
            pos := im.Pos + im.Len
        }

        ; Spine: <itemref idref="..."/>  — in order
        spineIds := []
        pos := 1
        While RegExMatch(opfText, 'i)<itemref\b[^>]*\bidref="([^"]+)"', &sm, pos) {
            spineIds.Push(sm[1])
            pos := sm.Pos + sm.Len
        }

        If (spineIds.Length = 0) {
            errMsg := "No spine items found in OPF"
            Return False
        }

        ; --- Step 4: Extract and strip each chapter ----------------------------------------------------------------------
        chapters := []
        missingChapters := ""
        missingCount := 0
        For id in spineIds {
            If !idHref.Has(id) {
                missingChapters .= "  [no href for id=" id "]`n"
                missingCount++
                Continue
            }
            href := idHref[id]
            ; href may contain a fragment (#anchor) — strip it
            If RegExMatch(href, "^([^#]+)", &hm)
                href := hm[1]
            ; Build OS path: OPF dir + relative href
            chapterPath := tempDir "\" (opfDir != "" ? opfDir "\" : "") StrReplace(href, "/", "\")
            ; Some EPUBs list .xhtml in the OPF but extract as .html — try both
            If !FileExist(chapterPath) && SubStr(chapterPath, -5) = ".xhtml"
                chapterPath := SubStr(chapterPath, 1, StrLen(chapterPath) - 6) ".html"
            If !FileExist(chapterPath) && SubStr(chapterPath, -4) = ".html"
                chapterPath := SubStr(chapterPath, 1, StrLen(chapterPath) - 5) ".xhtml"
            If !FileExist(chapterPath) {
                missingChapters .= "  [not found] " chapterPath "`n"
                missingCount++
                Continue
            }
            html := FileRead(chapterPath, "UTF-8")
            chapters.Push(HtmlToText(html))
        }

        ; --- Step 5: Join and post-process -------------------------------------------------------------------------------
        If (chapters.Length = 0) {
            errMsg := "No readable chapters found (checked " spineIds.Length " spine items)"
            Return False
        }

        fullText := ""
        For i, ch in chapters {
            fullText .= ch
            If (i < chapters.Length)
                fullText .= "`n`n"   ; blank line between chapters
        }
        fullText := PostProcess(fullText)

        ; Write output
        f := FileOpen(outPath, "w", "UTF-8")
        f.Write(fullText)
        f.Close()

        ; If we got some chapters but not all, surface as a warning on success.
        If (missingCount > 0)
            errMsg := "warning: skipped " missingCount " chapter(s) — check OPF manifest integrity"

        Return True
    } Catch As e {
        errMsg := "EPUB extraction failed: " e.Message
        Return False
    } Finally {
        ; Guaranteed cleanup — runs on success, error returns, and uncaught exceptions alike.
        Try DirDelete(tempDir, True)
    }
}

; ----------------------------------------------------------------------------------------------------------------------
; Convert HTML/XHTML to plain text
; — Remove <head>…</head> entirely
; — Convert block-level tags to newlines
; — Strip all remaining tags
; — Decode common HTML entities
; ----------------------------------------------------------------------------------------------------------------------
HtmlToText(html) {
    ; Remove <head>...</head> (case-insensitive, dotall)
    html := RegExReplace(html, "is)<head>.*?</head>", "")

    ; Remove <script>...</script> and <style>...</style>
    html := RegExReplace(html, "is)<script[^>]*>.*?</script>", "")
    html := RegExReplace(html, "is)<style[^>]*>.*?</style>", "")

    ; Block-level tags → newlines (paragraphs, headings, breaks, divs)
    html := RegExReplace(html, "i)<br\s*/?>", "`n")
    html := RegExReplace(html, "i)</(p|div|h[1-6]|li|tr|blockquote|section|article|header|footer|nav|aside)>", "`n`n")
    html := RegExReplace(html, "i)<(p|div|h[1-6]|li|tr|blockquote|section|article|header|footer)(\s[^>]*)?>", "`n")

    ; Strip all remaining tags
    html := RegExReplace(html, "<[^>]+>", "")

    ; Decode common HTML entities
    html := DecodeEntities(html)

    ; Collapse runs of spaces/tabs within a line (but preserve newlines)
    html := RegExReplace(html, "[ `t]+", " ")

    ; Trim leading/trailing space on each line
    html := RegExReplace(html, "m)^ +| +$", "")

    Return html
}

; ----------------------------------------------------------------------------------------------------------------------
; Decode common HTML entities to their Unicode equivalents
; ----------------------------------------------------------------------------------------------------------------------
DecodeEntities(s) {
    ; Named entities (most common)
    s := StrReplace(s, "&amp;",   "&")
    s := StrReplace(s, "&lt;",    "<")
    s := StrReplace(s, "&gt;",    ">")
    s := StrReplace(s, "&quot;",  '"')
    s := StrReplace(s, "&apos;",  "'")
    s := StrReplace(s, "&nbsp;",  " ")
    s := StrReplace(s, "&mdash;", "—")
    s := StrReplace(s, "&ndash;", "–")
    s := StrReplace(s, "&lsquo;", "'")
    s := StrReplace(s, "&rsquo;", "'")
    s := StrReplace(s, "&ldquo;", '"')
    s := StrReplace(s, "&rdquo;", '"')
    s := StrReplace(s, "&hellip;","…")
    s := StrReplace(s, "&copy;",  "©")
    s := StrReplace(s, "&reg;",   "®")
    s := StrReplace(s, "&trade;", "™")
    s := StrReplace(s, "&eacute;","é")
    s := StrReplace(s, "&egrave;","è")
    s := StrReplace(s, "&ecirc;", "ê")
    s := StrReplace(s, "&agrave;","à")
    s := StrReplace(s, "&aacute;","á")
    s := StrReplace(s, "&acirc;", "â")
    s := StrReplace(s, "&ouml;",  "ö")
    s := StrReplace(s, "&uuml;",  "ü")
    s := StrReplace(s, "&auml;",  "ä")
    s := StrReplace(s, "&szlig;", "ß")

    ; Numeric decimal entities: &#NNN;
    pos := 1
    While RegExMatch(s, "&#(\d+);", &m, pos) {
        ch := Chr(Integer(m[1]))
        s   := StrReplace(s, m[0], ch)
        pos := m.Pos  ; restart from same position (string length changed)
    }

    ; Numeric hex entities: &#xHHHH;
    pos := 1
    While RegExMatch(s, "&#x([0-9A-Fa-f]+);", &m, pos) {
        ch := Chr(Integer("0x" m[1]))
        s   := StrReplace(s, m[0], ch)
        pos := m.Pos
    }

    Return s
}

; ----------------------------------------------------------------------------------------------------------------------
; Reflow hard-wrapped plain text (Gutenberg-style OCR ebooks)
;
; The problem: OCR'd paper books have hard line-breaks every ~70 chars mid-sentence.
; Actual paragraph breaks use double newlines.
;
; Strategy: a single newline is a candidate for removal (reflow) if:
;   • The next line starts with a lowercase letter  (mid-sentence wrap)
;   • OR the next line starts with a comma, em-dash, closing quote  (punctuation continuation)
; We KEEP the newline when:
;   • Current line ends with .  !  ?  :  (sentence/clause end)
;   • Next line starts with uppercase  (new sentence or proper noun — preserve)
;   • It's actually a double-newline (paragraph break — always preserved)
;
; This is intentionally conservative to avoid merging real paragraph breaks.
; ----------------------------------------------------------------------------------------------------------------------
ReflowTxt(srcPath, outPath, &errMsg) {
    global Cfg
    If !FileExist(srcPath) {
        errMsg := "Source file not found"
        Return False
    }
    text := FileRead(srcPath, "UTF-8")
    If (text = "") {
        errMsg := "File is empty or unreadable"
        Return False
    }

    ; Normalize line endings first
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r",   "`n")

    If Cfg.ReflowTxt {
        ; Protect paragraph breaks (double newlines) by replacing with a placeholder
        text := StrReplace(text, "`n`n", "`x00")

        ; Reflow: join line if next line starts with lowercase or continuation punctuation
        ; i.e. remove the single `n between them, replace with a space
        text := RegExReplace(text, '`n([a-z,;' "'" '"\x{2014}\x{2013}])', " $1")

        ; Restore paragraph breaks
        text := StrReplace(text, "`x00", "`n`n")
    }

    ; Apply standard post-processing (hyphen rejoin, blank line collapse, trim)
    text := PostProcess(text)

    f := FileOpen(outPath, "w", "UTF-8")
    f.Write(text)
    f.Close()
    Return True
}

; ----------------------------------------------------------------------------------------------------------------------
; Post-processing passes applied to both PDF and EPUB output
; ----------------------------------------------------------------------------------------------------------------------
; ----------------------------------------------------------------------------------------------------------------------
PostProcess(text) {
    global Cfg
    ; Normalize all line endings to LF (SpeedReader requirement)
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r",   "`n")

    ; Rejoin hyphenated line-breaks if option enabled:  "word-\nrest"  →  "wordrest"
    ; This handles hard-hyphenated text from PDF pagination and old print books.
    If Cfg.RejoinHyphens
        text := RegExReplace(text, "-`n(\S)", "$1")

    ; Collapse runs of 3+ blank lines → 2 blank lines (preserve chapter spacing but
    ; don't let huge gaps accumulate from page headers/footers that were stripped)
    text := RegExReplace(text, "(`n){3,}", "`n`n`n")

    ; Trim trailing spaces on each line
    text := RegExReplace(text, "m) +$", "")

    ; Strip leading/trailing blank lines from the whole document
    text := RegExReplace(text, "^(`n)+|(`n)+$", "")

    Return text
}

; ----------------------------------------------------------------------------------------------------------------------
; Open the last converted .txt in SpeedReader
; ----------------------------------------------------------------------------------------------------------------------
DoOpenInSR(*) {
    global LastTxtOut, SpeedReader, AppName
    If (LastTxtOut = "" || !FileExist(LastTxtOut)) {
        MsgBox("No converted file available yet.", AppName, 48)
        Return
    }
    If !FileExist(SpeedReader) {
        MsgBox("SpeedReader.ahk not found at:`n" SpeedReader "`n`nPlease ensure both scripts are in the same folder.", AppName, 48)
        Return
    }

    ; Always write the path and sentinel stamp to Settings.ini so SR's watcher picks it up.
    srIni := A_ScriptDir "\Settings.ini"
    IniWrite(LastTxtOut,                    srIni, "Session", "LastFile")
    IniWrite(FormatTime(, "yyyyMMddHHmmss"), srIni, "Session", "TEConvertedAt")

    ; SpeedReader runs as SpeedReader.exe (renamed AHK portable exe) — launch it directly.
    ; If already running, close it first so it restarts and picks up the new LastFile.
    SplitPath(SpeedReader, , &srDir, , &srBase)
    srExe := srDir "\" srBase ".exe"

    If FileExist(srExe) {
        ; Check if already running and close it
        If WinExist("ahk_exe " srBase ".exe")
            WinClose("ahk_exe " srBase ".exe")
        Sleep(300)
        Run('"' srExe '"')
    } Else {
        ; Fallback: launch via AutoHotkey if .exe not found
        Run('"' A_AhkPath '" "' SpeedReader '"')
    }
}

; ----------------------------------------------------------------------------------------------------------------------
; Open the output folder in Explorer
; ----------------------------------------------------------------------------------------------------------------------
DoOpenFolder(*) {
    global LastTxtOut, Cfg, AppName
    folder := ""
    If (LastTxtOut != "" && FileExist(LastTxtOut)) {
        SplitPath(LastTxtOut, , &folder)
    } Else If (Cfg.UseOutputFolder && Cfg.OutputFolder != "") {
        folder := Cfg.OutputFolder
    }
    If (folder != "" && DirExist(folder))
        Run('explorer.exe "' folder '"')
    Else
        MsgBox("Output folder not found.", AppName, 48)
}

; ----------------------------------------------------------------------------------------------------------------------
; Output folder option controls
; ----------------------------------------------------------------------------------------------------------------------
OnUseFolderChanged(*) {
    global Cfg
    Cfg.UseOutputFolder := CbxUseFolder.Value
    UpdateFolderControls()
    SaveSettings()
}

BrowseOutputFolder(*) {
    global Cfg
    folder := DirSelect(Cfg.OutputFolder != "" ? Cfg.OutputFolder : A_ScriptDir, 1, "Select output folder")
    If (folder = "")
        Return
    Cfg.OutputFolder := folder
    EdFolder.Value   := folder
    SaveSettings()
}

UpdateFolderControls() {
    en := Cfg.UseOutputFolder
    EdFolder.Enabled  := en
    BtnFolder.Enabled := en
}

; ----------------------------------------------------------------------------------------------------------------------
; Helpers
; ----------------------------------------------------------------------------------------------------------------------
FileBaseName(path) {
    SplitPath(path, &name)
    Return name
}

ShowAbout(*) {
    MsgBox(
        AppName " — PDF / EPUB → Plain Text Converter`n"
        "Companion utility for SpeedReader`n`n"
        "PDF extraction uses pdftotext.exe from the Poppler project (GPL v2).`n"
        "EPUB extraction uses Windows PowerShell + .NET ZipFile (no install needed).`n`n"
        "Poppler for Windows: https://github.com/oschwartz10612/poppler-windows/releases`n"
        "Place pdftotext.exe in the Tools\ sub-folder next to this script.",
        AppName, 64)
}

ShowPdfToolHelp(*) {
    global PdfTool, AppName
    MsgBox(
        "PDF tool: pdftotext.exe (Poppler, GPL v2)`n`n"
        "Expected location:`n" PdfTool "`n`n"
        (FileExist(PdfTool) ? "✔ Found — PDF conversion is available." : "✘ NOT FOUND — PDF conversion will not work.`n`nDownload from:`nhttps://github.com/oschwartz10612/poppler-windows/releases`nExtract the bin\ folder and copy pdftotext.exe to the Tools\ sub-folder."),
        AppName, 64)
}

; ----------------------------------------------------------------------------------------------------------------------
; Settings persistence
; ----------------------------------------------------------------------------------------------------------------------
LoadSettings() {
    If !FileExist(IniFile)
        Return
    Cfg.GuiW          := Integer(IniRead(IniFile, "Window",  "W",             Cfg.GuiW))
    Cfg.GuiH          := Integer(IniRead(IniFile, "Window",  "H",             Cfg.GuiH))
    Cfg.RejoinHyphens := Integer(IniRead(IniFile, "Options", "RejoinHyphens", Cfg.RejoinHyphens ? 1 : 0)) ? True : False
    Cfg.ReflowTxt     := Integer(IniRead(IniFile, "Options", "ReflowTxt",     Cfg.ReflowTxt     ? 1 : 0)) ? True : False
    Cfg.UseOutputFolder := Integer(IniRead(IniFile, "Options", "UseOutputFolder", 1)) ? True : False
    Cfg.OutputFolder  := IniRead(IniFile, "Options", "OutputFolder", A_ScriptDir "\Converted")
    Cfg.OpenInSR      := Integer(IniRead(IniFile, "Options", "OpenInSR", Cfg.OpenInSR ? 1 : 0)) ? True : False
    Cfg.LastFile      := IniRead(IniFile, "Options", "LastFile", "")
}

SaveSettings() {
    IniWrite(Cfg.GuiW,                     IniFile, "Window",  "W")
    IniWrite(Cfg.GuiH,                     IniFile, "Window",  "H")
    IniWrite(Cfg.RejoinHyphens  ? 1 : 0,   IniFile, "Options", "RejoinHyphens")
    IniWrite(Cfg.ReflowTxt      ? 1 : 0,   IniFile, "Options", "ReflowTxt")
    IniWrite(Cfg.UseOutputFolder ? 1 : 0,  IniFile, "Options", "UseOutputFolder")
    IniWrite(Cfg.OutputFolder,             IniFile, "Options", "OutputFolder")
    IniWrite(Cfg.OpenInSR       ? 1 : 0,  IniFile, "Options", "OpenInSR")
    IniWrite(Cfg.LastFile,                 IniFile, "Options", "LastFile")
}
