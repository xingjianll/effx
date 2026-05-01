/*----------------------------------------------------------------------------
   Copyright 2026, Xingjian Liu

   Licensed under the MIT License. You may not use this file except in
   compliance with the License. A copy of the License can be found in the
   LICENSE file at the root of this distribution.
----------------------------------------------------------------------------*/

// Effx — HTML types and rendering.
//
// This module defines the `html` and `attr` algebraic data types and the
// `render`/`mount` walk that turns them into live DOM nodes. The builder
// DSL (`build`, `div`, `text`, ...) for writing trees with indented blocks
// instead of nested constructors lives in `dsl.kk`.

module html

import bindings
import effx

// ---------------------------------------------------------------------------
// HTML types
// ---------------------------------------------------------------------------

// A virtual-DOM-style description of the UI. `state<_>` fields make a
// constructor reactive: changes to the cell are reflected in the rendered DOM.
pub type html
    Text(content: state<string>)
    Div(attrs: list<attr>, kids: list<html>)
    Span(attrs: list<attr>, kids: list<html>)
    H1(attrs: list<attr>, kids: list<html>)
    H2(attrs: list<attr>, kids: list<html>)
    P(attrs: list<attr>, kids: list<html>)
    A(href: state<string>, attrs: list<attr>, kids: list<html>)
    Img(src: state<string>, alt: state<string>, attrs: list<attr>)
    Button(
        attrs: list<attr>,
        on-click: () -> <io, react> (),
        kids: list<html>
    )
    Input(
        input-type: state<string>,
        value: state<string>,
        on-change: (string) -> <io, react> ()
    )
    Ul(attrs: list<attr>, kids: list<html>)
    Li(attrs: list<attr>, kids: list<html>)
    If(cond: state<bool>, then-branch: html, else-branch: html)
    For(items: state<list<html>>)

// HTML attribute. Most variants carry a reactive `state<string>` value.
//   `Class`, `Id`, `Style` — common shorthand variants.
//   `Data(name, _)`        — `data-<name>` attribute.
//   `Attr(name, _)`        — generic name/value attribute.
//   `BoolAttr(name, _)`    — boolean attribute: present iff the bool is True;
//                            removed from the DOM otherwise (matches HTML
//                            spec semantics for `disabled`, `checked`, etc.).
pub type attr
    Class(value: state<string>)
    Id(value: state<string>)
    Style(value: state<string>)
    Data(name: string, value: state<string>)
    Attr(name: string, value: state<string>)
    BoolAttr(name: string, value: state<bool>)

// Render an `html` value to a DOM node. Each `get` inside the body subscribes
// the surrounding handler installation, so the resulting DOM updates when
// any read state changes.
pub fun render(h: html): <io, react, owner> dom-node
    match h
        Text(content) ->
            val node = create-text-node("")
            node.set-text-content(get(content))
            node
        Div(attrs, kids) -> render-element("div", attrs, kids)
        Span(attrs, kids) -> render-element("span", attrs, kids)
        H1(attrs, kids) -> render-element("h1", attrs, kids)
        H2(attrs, kids) -> render-element("h2", attrs, kids)
        P(attrs, kids) -> render-element("p", attrs, kids)
        Ul(attrs, kids) -> render-element("ul", attrs, kids)
        Li(attrs, kids) -> render-element("li", attrs, kids)
        A(href, attrs, kids) ->
            val node = render-element("a", attrs, kids)
            node.set-attribute("href", get(href))
            node
        Img(src, alt, attrs) ->
            val node = render-element("img", attrs, [])
            node.set-attribute("src", get(src))
            node.set-attribute("alt", get(alt))
            node
        Button(attrs, on-click, kids) ->
            val node = render-element("button", attrs, kids)
            node.add-event-listener("click", on-click)
            node
        Input(input-type, value, on-change) ->
            val node = create-element("input")
            node.add-event-listener-string("input", on-change)
            node.set-attribute("type", get(input-type))
            node.set-attribute("value", get(value))
            node
        If(cond, then-b, else-b) ->
            // Anchor stays put; on each cond change we dispose the previous
            // branch's owner, clear the anchor, and remount the new branch
            // under a fresh owner.
            val anchor = create-element("span")
            val current-dispose : ref<global, disposer> = ref(fn() ())
            val branch = if get(cond) then then-b else else-b
            (!current-dispose)()
            anchor.clear-children
            val (child, dispose) = handle-owner(fn()
                with handle-react
                render(branch)
            )
            current-dispose := dispose
            anchor.append-child(child)
            anchor
        For(items) ->
            // Anchor stays put; on each items change we dispose the previous
            // render's owner, clear the anchor, and re-render every item
            // under a fresh per-item react scope.
            val anchor = create-element("span")
            val current-dispose : ref<global, disposer> = ref(fn() ())
            val xs = get(items)
            (!current-dispose)()
            anchor.clear-children
            val (_unit, dispose) = handle-owner(fn()
                xs.foreach fn(item)
                    with handle-react
                    anchor.append-child(render(item))
            )
            current-dispose := dispose
            anchor

// Render an element node with attributes and children. Each attribute and
// each child is wrapped in its own `handle-react` so the captured continuation
// from any internal `get` is scoped tightly — only that one attribute or
// child re-runs when its dependencies change.
fun render-element(tag: string, attrs: list<attr>, kids: list<html>): <io, react, owner> dom-node
    val node = create-element(tag)
    attrs.foreach fn(a)
        handle-react(fn() node.apply-attr(a))
    kids.foreach fn(k)
        val child = handle-react(fn() render(k))
        node.append-child(child)
    node

// Apply one attribute to an element. The reactive read happens here, so the
// surrounding `handle-react` (per attribute) tightly scopes the captured
// continuation.
fun apply-attr(node: dom-node, a: attr): <io, react> ()
    match a
        Class(v) -> node.set-attribute("class", get(v))
        Id(v) -> node.set-attribute("id", get(v))
        Style(v) -> node.set-attribute("style", get(v))
        Data(name, v) -> node.set-attribute("data-" ++ name, get(v))
        Attr(name, v) -> node.set-attribute(name, get(v))
        BoolAttr(name, b) ->
            if get(b) then node.set-attribute(name, "")
            else node.remove-attribute(name)

// Attach a click-style listener whose callback can use `react`.
//
// Each invocation runs the user callback inside its own owner scope and
// react handler, then disposes the scope when the callback returns. This
// prevents subscribers captured during the callback from leaking past the
// event boundary.
pub fun add-event-listener(                                                                                                                                                                                         
    node: dom-node,                                       
    kind: string,
    cb: () -> <io, react> ()
): io ()
    node.add-event-listener-raw(kind, fn()                                                                                                                                                                          
        @default-exn(fn()
            val (_, dispose) = handle-owner(fn()                                                                                                                                                                    
                with handle-react                         
                cb()
            )                                                                                                                                                                                                       
            dispose()
        )                                                                                                                                                                                                           
    )

// Attach an input-style listener whose callback receives a string and can
// use `react`. Same scoping rules as `add-event-listener`.
pub fun add-event-listener-string(                                                                                                                                                                                  
    node: dom-node,  
    kind: string,                                                                                                                                                                                                   
    cb: (string) -> <io, react> ()
): io ()                                                                                                                                                                                                            
    node.add-event-listener-string-raw(kind, fn(s)
        @default-exn(fn()                                                                                                                                                                                           
            val (_, dispose) = handle-owner(fn()                                                                                                                                                                    
                with handle-react
                cb(s)                                                                                                                                                                                               
            )        
            dispose()
        )
    )
