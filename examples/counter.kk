/*----------------------------------------------------------------------------
   Effx example: a small counter app with a name input.

   Demonstrates:
     - `state/new` for reactive cells
     - the `build` / `div` / `p` / ... DSL for indented HTML
     - bare `button(<on-click-fn>) { kids }` (resolves to `direct/button`)
     - `input(...)` for two-way binding
     - `mount` to install handlers and produce a DOM node

   Build:
     cd /Users/kevin/KokaProjects/effx
     koka --target=js -c -ieffx -iexamples examples/counter.kk

   Then serve from the PROJECT ROOT (so the browser can reach `.koka/`):
     python3 -m http.server 8000
     # open http://localhost:8000/examples/
----------------------------------------------------------------------------*/

module counter

import std/core/list
import bindings
import effx
import html
import dsl

// The whole UI as a single component. `mount` installs the top-level
// `owner` and `react` handlers, so `app`'s effect row only needs
// `<io, react, owner>` (state allocation lives inside `io`).
pub fun app() : <io, react, owner> html
    val count = state/new("0")
    val name  = state/new("World")

    build
        div
            h1
                text-lit("Effx counter demo")

            p
                text-lit("Hello, ")
                text(name)
                text-lit("!")

            div
                text-lit("Name: ")
                input(
                    input-type = state/new("text"),
                    value      = name,
                    on-change  = fn(v) name.set(v)
                )

            p
                text-lit("Count: ")
                text(count)

            div
                button(fn()
                    val n = (!count.item).parse-int.default(0)
                    count.set((n + 1).show)
                )
                    text-lit(" +1 ")

                button(fn()
                    val n = (!count.item).parse-int.default(0)
                    count.set((n - 1).show)
                )
                    text-lit(" -1 ")

                button(fn() count.set("0"))
                    text-lit(" reset ")

pub fun main() : <io> ()
    val root = get-element-by-id("root")
    val node = mount(app)
    root.append-child(node)
