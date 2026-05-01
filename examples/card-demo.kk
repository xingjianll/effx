/*----------------------------------------------------------------------------
   Effx example: a custom `card` component that accepts indented children.

   Build:
     cd /Users/kevin/KokaProjects/effx
     koka --target=js -c -ieffx -iexamples examples/card-demo.kk

   Then point examples/main.js at card-demo.mjs and reload.
----------------------------------------------------------------------------*/

module card-demo

import bindings
import effx
import html
import dsl

// A reusable component. Takes a title (prop) and a build-tree (children).
// Renders a `div` with a header `h2(title)` followed by whatever the caller
// emits in the trailing block.
// Narrow card: no extra effects in row. Just wraps children in a div.
fun card(x: int, build-tree: () -> <html-builder|e> ()) : <html-builder|e> ()
    div
        build-tree()

pub fun app() : <io, react, owner, html-builder> ()
    val name = state/new("world")

    div
        // h1
        //     text-lit("Custom component demo")
        card(1)
            p
                text-lit("hello")
            p
                text-lit("world")
        card(2)
            p
                text-lit("Hello, ")
                text(name)
                text-lit("!")
            direct/input(state/new("text"), name, fn(s) name.set(s))

        card(4)
            card(3)
                p
                    text-lit("a child of an inner card")

pub fun main() : <io> ()
    val root = get-element-by-id("root")
    val node = mount(app)
    root.append-child(node)


fun derive(s: state<int>) : react int
    get(s) * 2

fun caller(s: state<int>) : <console, react> ()
    println("hi")
    val x = derive(s)
    println(x.show)