/*----------------------------------------------------------------------------
   Effx example: a working spreadsheet.

   Features:
     - 6×8 grid with lettered columns (A–F) and numbered rows (1–8)
     - click a cell to select it; its formula appears in the formula bar
     - editing the formula bar (or the selected cell directly) updates the
       cell's src text and triggers re-evaluation
     - formula language: `=` followed by `+`-separated integers and cell
       refs (`=A1+B2+10`). Plain text cells are stored as-is and treated as
       integers (or 0) when referenced.
     - fully reactive: changing any cell updates every formula that
       transitively depends on it.

   Build:
     cd /Users/kevin/KokaProjects/effx
     koka --target=js -c -ieffx -iexamples examples/sheet.kk

   Then make sure examples/main.js imports sheet.mjs and reload
   http://localhost:8000/examples/.
----------------------------------------------------------------------------*/

module sheet

import std/core/list
import std/core/vector
import std/core/string
import std/core/unsafe
import bindings
import effx
import html
import dsl

// One spreadsheet cell. `src` holds whatever the user typed (e.g. "42" or
// "=A1+B2"); `value` is the evaluated display string. `col`/`row` are 0-indexed.
pub struct cell(src: state<string>, value: state<string>, col: int, row: int)

// Mask the `exn` from out-of-bounds vector indexing. Callers validate the
// indices before calling, so the throw never actually fires.
fun lookup(grid: vector<vector<cell>>, r: int, c: int) : div cell
    unsafe-total(fn()
        match grid.at(r)
            Just(row) -> match row.at(c)
                Just(cl) -> cl
                Nothing  -> Cell(state/new(""), state/new(""), c, r)
            Nothing -> Cell(state/new(""), state/new(""), c, r)
    )

val cols = 6
val rows = 8

// Allocate one empty cell.
fun make-cell(col: int, row: int)
    Cell(state/new(""), state/new(""), col, row)

// Allocate the whole grid as a vector of vectors so cell lookup is O(1).
fun make-grid()
    vector-init(rows, fn(r) vector-init(cols, fn(c) make-cell(c, r)))

// Convert a 0-indexed column to its letter name. 0 -> "A", 1 -> "B", ...
fun col-letter(c: int)
    string(['A'.int + c].map(int/char))

// Cell coordinate as a label, e.g. (0, 0) -> "A1".
fun cell-label(c: int, r: int)
    col-letter(c) ++ (r + 1).show

// Try to parse a cell ref like "A1" into (col, row). Case-insensitive on the
// letter. Returns Nothing if the string isn't a well-formed ref.
fun parse-ref(s: string)
    val t = s.trim
    if t.count < 2 then Nothing
    else
        match t.head-char
            Nothing -> Nothing
            Just(ch) ->
                val cc = ch.int
                val a  = 'A'.int
                val z  = 'Z'.int
                val al = 'a'.int
                val zl = 'z'.int
                val col =
                    if cc >= a && cc <= z then cc - a
                    elif cc >= al && cc <= zl then cc - al
                    else -1
                if col < 0 then Nothing
                else
                    match t.tail.parse-int
                        Nothing  -> Nothing
                        Just(rn) -> Just((col, rn - 1))

// Read one token from a formula: either a cell reference (read its evaluated
// value reactively) or a plain integer literal. Anything malformed reads as 0.
fun eval-token(t: string, grid: vector<vector<cell>>)
    val s = t.trim
    if s.is-empty then 0
    else
        match parse-ref(s)
            Just((c, r)) ->
                if r < 0 || r >= rows || c < 0 || c >= cols then 0
                else
                    val cl = lookup(grid, r, c)
                    get(cl.value).parse-int.default(0)
            Nothing ->
                s.parse-int.default(0)

// Evaluate a formula body (the part after `=`). We split on `+` and sum.
// Reading `get(cell.value)` for any referenced cells is what makes the
// formula reactive: a change in any reference fires this evaluation again.
fun eval-formula(expr: string, grid: vector<vector<cell>>)
    val parts = expr.split("+")
    parts.foldl(0, fn(acc, p) acc + eval-token(p, grid))

// Set up the per-cell derivation: read `src` reactively. If it starts with
// `=`, evaluate the rest; otherwise echo the src text. Result goes into
// `value`. Each `get` here subscribes the surrounding handler installation,
// so any change in `src` (or any referenced cell) re-runs this body.
fun setup-cell-derivation(c: cell, grid: vector<vector<cell>>)
    val src = get(c.src)
    val out = if src.starts-with("=").bool then
        eval-formula(src.tail, grid).show
    else
        src
    c.value.set(out)

// One cell view: a div containing either
//   - an `<input>` bound to `src` if this cell is currently selected, or
//   - a static text node showing `value`
// plus an on-click that selects this cell.
fun cell-view(c: cell, sel-col: state<int>, sel-row: state<int>)
    val cls    = state/new("cell")
    val is-sel = state/new(False)
    // Track selection: derive `is-sel` and `cls` from the selected coords.
    val sc = get(sel-col)
    val sr = get(sel-row)
    val selected = sc == c.col && sr == c.row
    is-sel.set(selected)
    cls.set(if selected then "cell selected" else "cell")

    val edit-view : html = build
        direct/input(state/new("text"), c.src, fn(s) c.src.set(s))
    val show-view : html = build
        text(c.value)

    div(ats = [Class(cls)])
        // click handler: set selection to this cell
        button(fn() { sel-col.set(c.col); sel-row.set(c.row) })
            branch(is-sel, edit-view, show-view)

// Header row: a blank corner cell plus one cell per column showing its letter.
fun header-row()
    div(ats = [Class(state/new("row header"))])
        div(ats = [Class(state/new("rowhead"))])
            text-lit(" ")
        range/list(0, cols - 1).foreach fn(c)
            div(ats = [Class(state/new("colhead"))])
                text-lit(col-letter(c))

// One body row: a row-number header cell, then the cells.
fun body-row(r: int, grid: vector<vector<cell>>, sel-col: state<int>, sel-row: state<int>)
    div(ats = [Class(state/new("row"))])
        div(ats = [Class(state/new("rowhead"))])
            text-lit((r + 1).show)
        range/list(0, cols - 1).foreach fn(c)
            cell-view(lookup(grid, r, c), sel-col, sel-row)

// The main view. Sets up:
//   - cell derivations (so each cell.value is kept in sync with its src)
//   - formula-bar wiring (selected cell's src <-> formula bar input)
// then builds the DOM.
pub fun app() : <io, react, owner> html
    val grid = make-grid()
    val sel-col = state/new(0)
    val sel-row = state/new(0)
    val formula = state/new("")

    // Per-cell derivations.
    range/list(0, rows - 1).foreach fn(r)
        range/list(0, cols - 1).foreach fn(c)
            setup-cell-derivation(lookup(grid, r, c), grid)

    // Formula bar <-> selected cell src, both directions.
    val sc = get(sel-col)
    val sr = get(sel-row)
    val cur = lookup(grid, sr, sc)
    formula.set(get(cur.src))

    build
        div(ats = [Class(state/new("app"))])
            h1
                text-lit("Effx spreadsheet")

            // Formula bar
            div(ats = [Class(state/new("formula-bar"))])
                text-lit("Cell ")
                text(state/new(cell-label(0, 0)))  // static label of selection
                text-lit(": ")
                direct/input(
                    state/new("text"),
                    formula,
                    fn(s)
                        // Push the typed formula back to the currently-selected cell.
                        val c = get(sel-col)
                        val r = get(sel-row)
                        lookup(grid, r, c).src.set(s)
                )

            // Grid
            div(ats = [Class(state/new("grid"))])
                header-row()
                range/list(0, rows - 1).foreach fn(r)
                    body-row(r, grid, sel-col, sel-row)

pub fun main() : <io> ()
    val root = get-element-by-id("root")
    val node = mount(app)
    root.append-child(node)
