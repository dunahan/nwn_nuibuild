// =============================================================================
// wysi_editor.nss
// -----------------------------------------------------------------------------
// Minimal WYSIWYG NUI editor prototype (Variant 1: in-game editor with
// live "rebuild on change" preview).
//
// IDEA
// The player edits a small element list (label / button / checkbox) through
// a palette window. On every change, the preview window is destroyed and
// re-created from that list, giving a near-live visual result -- without
// true pixel drag & drop, since NUI auto-computes row/column layout itself.
//
// SETUP
// 1. Compile this file in your module.
// 2. Make sure it (or a call to HandleWysiEditorEvent()) runs on the
//    module's "OnNUIEvent" script. Either:
//      a) set this script directly as the module's OnNUIEvent script, or
//      b) if you already have a dispatcher (like nw_nui_demo_evt.nss),
//         just call HandleWysiEditorEvent(); from inside its main().
// 3. To open the editor for a player, call OpenEditor(oPC) from anywhere
//    (a debug command, an item, OnModuleLoad with GetFirstPC() for testing).
//
// LIMITATIONS (by design, to keep this beginner-friendly)
// - Only 3 element types (label / button / checkbox), appended in order.
// - No reordering, no deleting single elements (only "clear all").
// - No property panel beyond the "text" field.
//
// STATE ROUND-TRIP
// The element list is the working copy (local var on oPC, survives window
// rebuilds). Every rebuilt preview window additionally carries its own
// snapshot via NuiSetUserData(), so the data that produced a given window
// can always be read back from the window itself via NuiGetUserData() --
// independent of the working copy. "Self-Check" compares the two and logs
// a PASS/DIFF-style result. "Export" dumps the window's own snapshot as
// JSON text to the log (NWScript can't write files directly).
// =============================================================================

#include "nw_inc_nui"

const string WYSI_EDITOR_WND  = "wysi_editor";
const string WYSI_PREVIEW_WND = "wysi_preview";

const string WYSI_LOCAL_ELEMENTS     = "wysi_elements";
const string WYSI_LOCAL_TOKEN        = "wysi_preview_token";
const string WYSI_LOCAL_EDITOR_TOKEN = "wysi_editor_token";

// -----------------------------------------------------------------------------
// State handling
// -----------------------------------------------------------------------------

// Returns the stored element list for oPC, or an empty array if none exists yet.
json GetElements(object oPC)
{
    json jElements = GetLocalJson(oPC, WYSI_LOCAL_ELEMENTS);
    if (JsonGetType(jElements) != JSON_TYPE_ARRAY)
        jElements = JsonArray();
    return jElements;
}

void SaveElements(object oPC, json jElements)
{
    SetLocalJson(oPC, WYSI_LOCAL_ELEMENTS, jElements);
}

// -----------------------------------------------------------------------------
// Preview building
// -----------------------------------------------------------------------------

// Builds a single row containing the widget for one element entry.
// jElem = {"type": "label"|"button"|"check", "text": "...", "id": "elem_N"}
json BuildElementRow(json jElem)
{
    string sType = JsonGetString(JsonObjectGet(jElem, "type"));
    string sText = JsonGetString(JsonObjectGet(jElem, "text"));
    string sId   = JsonGetString(JsonObjectGet(jElem, "id"));

    json jWidget;
    if (sType == "button")
        jWidget = NuiButton(JsonString(sText));
    else if (sType == "check")
        jWidget = NuiCheck(JsonString(sText), JsonBool(FALSE));
    else // "label" (default/fallback)
        jWidget = NuiLabel(JsonString(sText), JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));

    jWidget = NuiId(jWidget, sId);
    jWidget = NuiHeight(jWidget, 30.0);

    json jRowList = JsonArray();
    jRowList = JsonArrayInsert(jRowList, jWidget);
    return NuiRow(jRowList);
}

// Builds the full preview window layout from the current element list.
json BuildPreviewWindow(json jElements)
{
    json jColList = JsonArray();
    int nCount = JsonGetLength(jElements);
    int n;

    for (n = 0; n < nCount; n++)
        jColList = JsonArrayInsert(jColList, BuildElementRow(JsonArrayGet(jElements, n)));

    if (nCount == 0)
    {
        json jEmptyWidget = NuiLabel(
            JsonString("(no elements yet - add some on the left)"),
            JsonInt(NUI_HALIGN_CENTER),
            JsonInt(NUI_VALIGN_MIDDLE));
        json jEmptyRow = JsonArray();
        jEmptyRow = JsonArrayInsert(jEmptyRow, jEmptyWidget);
        jColList = JsonArrayInsert(jColList, NuiRow(jEmptyRow));
    }

    json jRoot = NuiCol(jColList);

    return NuiWindow(
        jRoot,
        JsonString("Preview (live)"),
        NuiRect(440.0, 10.0, 350.0, 500.0),
        JsonBool(TRUE),   // resizable
        JsonBool(FALSE),  // collapsed
        JsonBool(TRUE),   // closable
        JsonBool(FALSE),  // transparent
        JsonBool(TRUE));  // border
}

// Destroys the current preview window (if any) and rebuilds it from scratch.
// This is the "rebuild on change" core of the prototype.
void RefreshPreview(object oPC)
{
    int nOldToken = GetLocalInt(oPC, WYSI_LOCAL_TOKEN);
    if (nOldToken != 0)
        NuiDestroy(oPC, nOldToken);

    json jElements = GetElements(oPC);
    json jWindow   = BuildPreviewWindow(jElements);
    int  nNewToken = NuiCreate(oPC, jWindow, WYSI_PREVIEW_WND);

    // Snapshot the data that produced this window ON the window itself.
    // This decouples "what's shown" from "what we think we saved" and
    // lets Export/Self-Check read the window's own record back later,
    // instead of trusting the local-var working copy blindly.
    NuiSetUserData(oPC, nNewToken, jElements);

    SetLocalInt(oPC, WYSI_LOCAL_TOKEN, nNewToken);
}

// Compares the working copy (what we think we saved) against the userdata
// snapshot carried by the live preview window (what actually produced it).
// Mirrors the PASS/DIFF vocabulary of a runtime-parity check, just local
// and synchronous -- no HTTP round-trip needed since it's the same process.
void ValidateWysiState(object oPC)
{
    int nToken = GetLocalInt(oPC, WYSI_LOCAL_TOKEN);
    if (nToken == 0)
    {
        WriteTimestampedLogEntry("WYSI_SELFCHECK: MISSING_RUNTIME (no preview window open)");
        return;
    }

    string sWorking = JsonDump(GetElements(oPC), 0);
    string sRuntime = JsonDump(NuiGetUserData(oPC, nToken), 0);

    if (sWorking == sRuntime)
        WriteTimestampedLogEntry("WYSI_SELFCHECK: PASS (" + IntToString(JsonGetLength(GetElements(oPC))) + " elements)");
    else
    {
        WriteTimestampedLogEntry("WYSI_SELFCHECK: DIFF");
        WriteTimestampedLogEntry("  working: " + sWorking);
        WriteTimestampedLogEntry("  runtime: " + sRuntime);
    }
}

// Dumps the live preview window's own data snapshot as readable JSON to
// the log. This is the closest NWScript gets to "export a file" -- there
// is no native file write, so the log is the hand-off point to the developer.
void ExportWysiState(object oPC)
{
    int nToken = GetLocalInt(oPC, WYSI_LOCAL_TOKEN);
    if (nToken == 0)
    {
        WriteTimestampedLogEntry("WYSI_EXPORT: nothing to export (no preview window open)");
        return;
    }

    json jSnapshot = NuiGetUserData(oPC, nToken);
    WriteTimestampedLogEntry("WYSI_EXPORT: " + JsonDump(jSnapshot, 2));
    SendMessageToPC(oPC, "WYSIWYG-Editor: aktueller Stand wurde in den Server-Log geschrieben.");
}

// -----------------------------------------------------------------------------
// Editor actions
// -----------------------------------------------------------------------------

void AddElement(object oPC, string sType, string sText)
{
    if (sText == "")
        sText = sType;

    json jElements = GetElements(oPC);
    int  nCount    = JsonGetLength(jElements);

    json jElem = JsonObject();
    jElem = JsonObjectSet(jElem, "type", JsonString(sType));
    jElem = JsonObjectSet(jElem, "text", JsonString(sText));
    jElem = JsonObjectSet(jElem, "id",   JsonString("elem_" + IntToString(nCount)));

    jElements = JsonArrayInsert(jElements, jElem);
    SaveElements(oPC, jElements);
    RefreshPreview(oPC);
}

void ClearElements(object oPC)
{
    SaveElements(oPC, JsonArray());
    RefreshPreview(oPC);
}

// -----------------------------------------------------------------------------
// Editor window
// -----------------------------------------------------------------------------

void OpenEditor(object oPC)
{
    json jInput = NuiTextEdit(JsonString("Text for next element..."), NuiBind("input_text"), 50, FALSE);
    jInput = NuiId(jInput, "input_text");
    jInput = NuiHeight(jInput, 35.0);

    json jBtnLabel   = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("+ Label")),  115.0), 32.0), "add_label");
    json jBtnButton  = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("+ Button")), 115.0), 32.0), "add_button");
    json jBtnCheck   = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("+ Chk")),    115.0), 32.0), "add_check");
    json jBtnClear   = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("Clear")),    115.0), 32.0), "clear_all");
    json jBtnExport  = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("Export")),   115.0), 32.0), "export_json");
    json jBtnCheckS  = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("Verify")),   115.0), 32.0), "self_check");
    json jBtnRefresh = NuiId(NuiHeight(NuiWidth(NuiButton(JsonString("Update")),   115.0), 32.0), "refresh_preview");

    json jRowInput = JsonArray();
    jRowInput = JsonArrayInsert(jRowInput, jInput);

    json jRowPalette = JsonArray();
    jRowPalette = JsonArrayInsert(jRowPalette, jBtnLabel);
    jRowPalette = JsonArrayInsert(jRowPalette, jBtnButton);
    jRowPalette = JsonArrayInsert(jRowPalette, jBtnCheck);

    json jRowClear = JsonArray();
    jRowClear = JsonArrayInsert(jRowClear, jBtnClear);
    jRowClear = JsonArrayInsert(jRowClear, jBtnExport);
    jRowClear = JsonArrayInsert(jRowClear, jBtnCheckS);

    json jRowRefresh = JsonArray();
    jRowRefresh = JsonArrayInsert(jRowRefresh, jBtnRefresh);

    json jColList = JsonArray();
    jColList = JsonArrayInsert(jColList, NuiRow(jRowInput));
    jColList = JsonArrayInsert(jColList, NuiRow(jRowPalette));
    jColList = JsonArrayInsert(jColList, NuiRow(jRowClear));
    jColList = JsonArrayInsert(jColList, NuiRow(jRowRefresh));

    json jRoot = NuiCol(jColList);

    json jWindow = NuiWindow(
        jRoot,
        JsonString("WYSIWYG Editor (Prototype)"),
        NuiRect(20.0, 10.0, 420.0, 260.0),
        JsonBool(FALSE),  // resizable
        JsonBool(FALSE),  // collapsed
        JsonBool(TRUE),   // closable
        JsonBool(FALSE),  // transparent
        JsonBool(TRUE));  // border

    int nEditorToken = NuiCreate(oPC, jWindow, WYSI_EDITOR_WND);
    SetLocalInt(oPC, WYSI_LOCAL_EDITOR_TOKEN, nEditorToken);

    // Explicit bind initialization. Without this, "input_text" only gets a
    // value once the player actually types something -- reading it before
    // that (e.g. clicking "+ Label" immediately) would hand back JsonNull()
    // instead of an empty string, and JsonGetString() on that is a footgun.
    NuiSetBind(oPC, nEditorToken, "input_text", JsonString(""));

    // Fresh start every time the editor is (re)opened.
    SaveElements(oPC, JsonArray());
    SetLocalInt(oPC, WYSI_LOCAL_TOKEN, 0);
    RefreshPreview(oPC);
}

// -----------------------------------------------------------------------------
// Event handling
// -----------------------------------------------------------------------------

// Call this from your module's OnNUIEvent dispatcher (or set this file
// directly as the OnNUIEvent script, see header comment).
void HandleWysiEditorEvent()
{
    object oPC    = NuiGetEventPlayer();
    int    nToken = NuiGetEventWindow();
    string sEvent = NuiGetEventType();
    string sElem  = NuiGetEventElement();
    string sWndId = NuiGetWindowId(oPC, nToken);

    if (sWndId != WYSI_EDITOR_WND) return;
    if (sEvent != "click") return;

    string sInputText = JsonGetString(NuiGetBind(oPC, nToken, "input_text"));

    if (sElem == "add_label")
        AddElement(oPC, "label", sInputText);
    else if (sElem == "add_button")
        AddElement(oPC, "button", sInputText);
    else if (sElem == "add_check")
        AddElement(oPC, "check", sInputText);
    else if (sElem == "clear_all")
        ClearElements(oPC);
    else if (sElem == "export_json")
        ExportWysiState(oPC);
    else if (sElem == "self_check")
        ValidateWysiState(oPC);
    else if (sElem == "refresh_preview")
        RefreshPreview(oPC);
}

/* Fallback entry point if this file is used standalone as the OnNUIEvent script.
void main()
{
    HandleWysiEditorEvent();
}*/
