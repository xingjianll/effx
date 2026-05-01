/*----------------------------------------------------------------------------
   Copyright 2026, Xingjian Liu

   Licensed under the MIT License. You may not use this file except in
   compliance with the License. A copy of the License can be found in the
   LICENSE file at the root of this distribution.
----------------------------------------------------------------------------*/

// Effx — Builder DSL.
//
// Indented-block syntax for writing HTML trees, compiling to plain `html`
// values defined in `html.kk`. The builder works in two layers:
//
//   - `html-tag` carries an element's *identity* and any hard-coded data
//     (e.g. `A(href)`, `Img(src, alt)`, `Button(on-click)`). Bare values
//     like `Div`, `Span`, `H1` are zero-arg constructors — usable as values.
//
//   - Modifier functions `tag`, `attr`, `class`, `battr`, `attrs` take an
//     `html-tag` plus optional inline data plus a trailing build-tree, and
//     emit a single `html` value into the surrounding scope via `add-kid`.
//
// Each modifier consumes the trailing block as its kids' build-tree, so:
//
//   Div.tag                       // bare Div with kids in the block
//     text-lit("hi")
//
//   Div.attr("id", state/new("main"))
//     text-lit("hi")
//
//   Div.attrs([Class(state/new("a")), Id(state/new("b"))])
//     text-lit("hi")
//
//   A(href = state/new("/home")).class(state/new("link"))
//     text-lit("home")
//
//   Img(src = state/new("/x.png"), alt = state/new("x")).leaf
//
// `text`, `text-lit`, `branch`, `each` are direct emitters (no build-tree).

module dsl

import effx
import html

// Effect that threads "current parent" state through the build-tree.
// `add-kid` appends a child to the current scope.
pub effect html-builder
    fun add-kid(h: html) : ()

// Convert a build-tree into a single `html` value. If the tree produced
// exactly one kid, returns it directly; otherwise wraps the kids in a
// top-level `Div`.
pub fun build(build-tree: () -> <html-builder|e> ()) : e html
    var kids : list<html> := []
    with handler
        fun add-kid(h) kids := Cons(h, kids)
        return(_)
            match kids.reverse
                Cons(only, Nil) -> only
                ks              -> Div([], ks)
    build-tree()

// Internal helper: run `build-tree` under a fresh override handler that
// collects kids locally; on exit, assemble the html (via `make`) and
// register it with the parent handler.
inline fun container(make: list<html> -> html, build-tree: () -> <html-builder|e> ()) : <html-builder|e> ()
    var kids : list<html> := []
    with override
        fun add-kid(h) kids := Cons(h, kids)
        return(_) add-kid(make(kids.reverse))
    build-tree()

// ----- Tag functions (no special inline data). ---------------------------
//
// Each takes a trailing block as kids. They can be used directly:
//
//   div
//     text-lit("hi")
//
// or through the chained-modifier methods (`.attr`, `.class`, `.battr`,
// `.attrs`) which accept a tag function as receiver:
//
//   div.class(state/new("card"))
//     text-lit("hi")
//
// Internally, each tag function takes `(build-tree, ats=[])`. The default
// `ats` lets you call them as `div { ... }` without arguments. The modifier
// functions call them via `t(build-tree, [...])`.

pub fun div(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) Div(ats, ks), build-tree)

pub fun span(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) Span(ats, ks), build-tree)

pub fun h1(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) H1(ats, ks), build-tree)

pub fun h2(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) H2(ats, ks), build-tree)

pub fun p(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) P(ats, ks), build-tree)

pub fun ul(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) Ul(ats, ks), build-tree)

pub fun li(build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) Li(ats, ks), build-tree)

// ----- Tag functions with extra hard-coded data. -------------------------
//
// `a`, `button`, `img`, `input` take their fixed parameters by name. Inline
// `attrs=[...]` for attributes. `.attr/.class/.battr/.attrs` chains do NOT
// work on these because their signatures differ.

// Each element with extra hard-coded data has TWO overloads sharing the
// same name: a `direct/` form that takes a build-tree and emits, and a
// `partial/` form that returns a tag-shape function `(build-tree, attrs) ->
// emit` so chained modifiers (`.attr`, `.class`, ...) compose. Koka's
// overload resolution picks the right one based on use context.

// ----- a -----

pub fun direct/a(href: state<string>, build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) A(href, ats, ks), build-tree)

pub fun partial/a(href: state<string>) : ((() -> <html-builder|e> (), list<attr>) -> <html-builder|e> ())
    fn(bt, at) container(fn(ks) A(href, at, ks), bt)

// ----- button -----

pub fun direct/button(on-click: () -> <io, react> (), build-tree: () -> <html-builder|e> (), ats: list<attr> = []) : <html-builder|e> ()
    container(fn(ks) Button(ats, on-click, ks), build-tree)

pub fun partial/button(on-click: () -> <io, react> ()) : ((() -> <html-builder|e> (), list<attr>) -> <html-builder|e> ())
    fn(bt, at) container(fn(ks) Button(at, on-click, ks), bt)

// ----- img (leaf, no kids) -----
//
// `direct/img` emits with given attrs. `partial/img` returns a tag-shape
// function whose `build-tree` argument is ignored (since img has no kids).

pub fun direct/img(src: state<string>, alt: state<string>, ats: list<attr> = []) : <html-builder|e> ()
    add-kid(Img(src, alt, ats))

pub fun partial/img(src: state<string>, alt: state<string>) : ((() -> <html-builder|e> (), list<attr>) -> <html-builder|e> ())
    fn(_bt, at) add-kid(Img(src, alt, at))

// ----- input (leaf, no kids) -----

pub fun direct/input(input-type: state<string>, value: state<string>, on-change: (string) -> <io, react> ()) : <html-builder|e> ()
    add-kid(Input(input-type, value, on-change))

pub fun partial/input(input-type: state<string>, value: state<string>, on-change: (string) -> <io, react> ()) : ((() -> <html-builder|e> (), list<attr>) -> <html-builder|e> ())
    fn(_bt, _at) add-kid(Input(input-type, value, on-change))

// ----- Chainable modifiers. -----
//
// Each takes a tag function (with signature `(build-tree, ats) -> ...`) as
// receiver, plus the modifier data, plus a trailing block (the kids). Calls
// the tag function with the built attrs list and the user's build-tree.
//
//   div.class(state/new("card"))
//     text-lit("hi")
//
// is equivalent to `class(div, state/new("card"), fn() text-lit("hi"))`,
// which calls `div(fn() text-lit("hi"), [Class(state/new("card"))])`.

pub fun attr(
    t: (() -> <html-builder|e> (), list<attr>) -> <html-builder|e> (),
    k: string,
    v: state<string>,
    build-tree: () -> <html-builder|e> ()
) : <html-builder|e> ()
    t(build-tree, [Attr(k, v)])

pub fun class(
    t: (() -> <html-builder|e> (), list<attr>) -> <html-builder|e> (),
    c: state<string>,
    build-tree: () -> <html-builder|e> ()
) : <html-builder|e> ()
    t(build-tree, [Class(c)])

pub fun battr(
    t: (() -> <html-builder|e> (), list<attr>) -> <html-builder|e> (),
    k: string,
    b: state<bool>,
    build-tree: () -> <html-builder|e> ()
) : <html-builder|e> ()
    t(build-tree, [BoolAttr(k, b)])

pub fun attrs(
    t: (() -> <html-builder|e> (), list<attr>) -> <html-builder|e> (),
    ats: list<attr>,
    build-tree: () -> <html-builder|e> ()
) : <html-builder|e> ()
    t(build-tree, ats)

// ----- Direct emitters (terminal — no build-tree). -----

// Render a reactive text node from a `state<string>`.
pub fun text(s: state<string>) : <html-builder|e> ()
    add-kid(Text(s))

// Convenience: render a static string. Allocates a fresh `state<string>`
// internally, so the caller's effect row picks up `<st<global>, ndet>`.
pub fun text-lit(s: string) : <html-builder, st<global>, ndet|e> ()
    add-kid(Text(state/new(s)))

// Conditional subtree. Named `branch` because `if` is a Koka keyword.
pub fun branch(cond: state<bool>, then-branch: html, else-branch: html) : <html-builder|e> ()
    add-kid(If(cond, then-branch, else-branch))

// Reactive list rendering. Named `each` because `for` is a Koka keyword.
pub fun each(items: state<list<html>>) : <html-builder|e> ()
    add-kid(For(items))

fun button2(on-click: int, f: (()-> io ()) -> io ()): ()
    ()

fun button3(f: ()-> io ()): ()
    ()
fun test1()
      button(fn() ())
          text-lit("hi")          // should resolve to direct/button

fun test2()
    button(fn() ()).attr("class", state/new("c"))
        text-lit("hi")          // should resolve to partial/button
