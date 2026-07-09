# Effx

An experimental fine-grained reactive web UI framework for [Koka](https://koka-lang.github.io/), built on algebraic effect handlers.

Effx asks what a reactivity system in the style of Solid.js looks like when the reactive machinery is expressed directly through effects and handlers rather than a hand written runtime. Dependency tracking, subscriptions, and ownership all arise from a small set of effect operations. Reading a reactive cell captures a continuation and writing to the cell resumes it. There is no virtual DOM and no diffing. When a value changes, only the narrowest computation that observed it runs again, down to a single attribute or a single text node.

## How it works

- `state<a>` is a reactive cell with a subscriber list.
- The `react` effect provides `get` and `set`. `get(s)` is a `ctl` operation: the handler stores the captured resumption on `s`'s subscriber list, so a later `set(s, v)` re-runs exactly the computation that read it. Dependencies are tracked per handler installation and re-diffed on each fire, the algorithmic analog of Solid's sources array.
- The `owner` effect gives explicit ownership scopes. Every `handle-react` installation registers a self-disposer with the ambient owner, so disposing an owner tears down all subscriptions created inside it (used by conditional and list rendering to clean up replaced subtrees).
- Rendering wraps each attribute and each child in its own `handle-react`, which is what makes updates fine-grained.

## Modules

| Module | Purpose |
|---|---|
| `effx/effx.kk` | Reactive core: `state<a>`, the `react` and `owner` effects and their handlers |
| `effx/html.kk` | `html` / `attr` data types and the `render` walk that produces live DOM nodes |
| `effx/dsl.kk` | Builder DSL: write HTML trees as indented blocks (`div`, `p`, `text`, `branch`, `each`, ...) |
| `effx/bindings.kk` | Raw `extern` JS/DOM bindings everything else is built on |

## Example

```koka
module counter

import bindings
import effx
import html
import dsl

pub fun app() : <io, react, owner, html-builder> ()
    val count = state/new("0")

    div
        h1
            text-lit("Effx counter")
        p
            text-lit("Count: ")
            text(count)
        button(fn()
            val n = (!count.item).parse-int.default(0)
            count.set((n + 1).show)
        )
            text-lit("+1")

pub fun main() : <io> ()
    val root = get-element-by-id("root")
    root.append-child(mount(app))
```

`mount` installs the top-level `owner` and `react` handlers, runs the build-tree to assemble the `html` value, and renders it to a DOM node. `text(count)` subscribes that one text node to the cell, so clicking the button updates only it.

## Running the examples

Compile an example to JavaScript (requires Koka, tested with v3.2.3):

```sh
koka --target=js -c -ieffx -iexamples examples/counter.kk
```

Point `examples/main.js` at the generated `<module>__main.mjs` under `examples/.koka/`, then serve from the project root and open the page:

```sh
python3 -m http.server 8000
# open http://localhost:8000/examples/
```

Examples:

- `examples/counter.kk` — counter with a two-way-bound name input
- `examples/card-demo.kk` — a reusable component that accepts indented children
- `examples/sheet.kk` — a spreadsheet: formulas with ranges and functions, selection, undo/redo, copy/paste, drag-fill, column resize/sort/filter, find/replace

## Status

This is a research/hobby project and the API changes freely. Known rough edges include the small set of built-in elements and the whole-subtree re-render on `branch`/`each` changes.

## License

MIT — see [LICENSE](LICENSE).
