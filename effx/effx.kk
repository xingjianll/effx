// Effx — fine-grained reactive UI on top of Koka's algebraic effect handlers.
//
// Design at a glance:
//
//   - `state<a>` is a reactive cell. Each cell has a unique `sid` and a
//     subscribers dict (keyed by `obs-id`).
//   - `react` provides `get` and `set` operations on cells. `get` captures
//     a continuation that is fired when the cell changes; `set` writes the new
//     value and dispatches all current subscribers.
//   - `handle-eff` installs a react handler. Each installation gets a
//     unique `obs-id` and tracks its read sources. On a subscriber fire, the
//     installation pops sources after the triggering signal and unsubscribes
//     from those signals — the algorithmic analog of Solid's sources-diff.
//   - `owner` and `handle-owner` give an explicit ownership scope. Each
//     `handle-eff` installation registers a self-disposer with the ambient
//     owner, so that disposing the owner tears down all its installations
//     (used by `If` and `For` for branch-swap cleanup).
//   - `render` walks an `html` tree producing real DOM nodes; per-kid and
//     per-attr `handle-eff` scopes keep captured continuations tight.
//
// Subscribers are deduplicated per (signal, obs-id), so multiple `get` calls
// in the same handler scope only register one subscriber per signal.

module effx

import std/core/list
import bindings

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

// HTML attribute. Each variant carries a reactive `state<string>` value.
pub type attr
    Class(value: state<string>)
    Id(value: state<string>)
    Style(value: state<string>)
    Data(name: string, value: state<string>)

// A reactive cell.
//   `item`        — the current value.
//   `subscribers` — list of (obs-id, callback) pairs. A callback fires when
//                   the cell changes. Keyed by obs-id so each handler
//                   installation appears at most once.
//   `sid`         — stable signal id, used by handlers to track which signals
//                   they currently depend on.
pub struct state<a>
    item: ref<global, a>
    subscribers : ref<global, list<(int, () -> <io, owner> ())>>
    sid: int

pub fun state(initial: a) : <st<global>, ndet> state<a>
    State(item = ref(initial), subscribers = ref([]), sid = unique())

// Reactive read/write operations. `get` subscribes the current handler
// installation; `set` writes the cell and fires subscribers.
pub effect react
    ctl get<a>(s: state<a>) : a
    ctl set<a>(s: state<a>, v: a) : ()

// Ownership scope for cleanup. Every `handle-eff` installation registers a
// self-disposer with the ambient owner; disposing the owner walks those
// disposers, unsubscribing each installation from every signal it held.
pub effect owner
    fun register-disposer(d: () -> <read<global>, write<global>, div> ()) : ()

// Run `action` under a fresh owner scope. Returns the action's result and a
// disposer that, when called, runs every disposer registered during action.
//
// Typical use:
//
//   val (node, dispose) = handle-owner(fn() ...)
//   ...
//   dispose()   // tears down everything created inside the scope
pub fun handle-owner(action: () -> <io, owner> a) : <io> (a, () -> <read<global>, write<global>, div> ())
    val disposers : ref<global, list<() -> <read<global>, write<global>, div> ()>> = ref([])
    val result =
        with handler
            fun register-disposer(d)
                disposers := Cons(d, !disposers)
        action()
    val dispose-all : () -> <read<global>, write<global>, div> () = fn()
        (!disposers).foreach fn(d) d()
        disposers := []
    (result, dispose-all)

// Install a fresh react handler. Each installation:
//
//   - allocates a unique `obs-id` and an empty `sources` list (signals read
//     in order during this run);
//   - registers a self-disposer with the ambient owner so the installation
//     can be torn down when its owner is disposed;
//   - on `get(s)`: if `s` is already in `sources`, just resume with the
//     current value (dedup); otherwise add `(sid, cleanup)` to `sources`,
//     add `(obs-id, k)` to `s.subscribers`, and resume. `k` is the
//     resumption — when fired by a later `set`, it pops everything in
//     `sources` after `s` (cleaning stale subscriptions) before resuming;
//   - on `set(s, v)`: write `s.item := v` and fire every subscriber on `s`.
pub fun handle-eff(
    action: () -> <io, react, owner> a
) : <io, owner> a
    val obs-id = unique()
    val sources : ref<global, list<(int, () -> <read<global>, write<global>, div> ())>> = ref([])

    // Tear-down: walk our sources, run each cleanup, then empty the list.
    val self-dispose : () -> <read<global>, write<global>, div> () = fn()
        (!sources).foreach fn((_, cleanup)) cleanup()
        sources := []
    register-disposer(self-dispose)

    with handler
        return(x)
            x

        ctl get(s)
            val sid = s.sid
            if (!sources).any(fn((key, _)) key == sid) then
                ()
            else
                // First time we see `s` in this run: register the cleanup
                // (which removes us from s.subscribers later if/when we
                // unsubscribe) and append `s` to our sources list.
                val cleanup : () -> <read<global>, write<global>, div> () = fn()
                    val sref = s.subscribers
                    sref := (!sref).filter(fn((key, _)) key != obs-id)
                sources := !sources ++ [(sid, cleanup)]
                // The resumption stored on `s.subscribers`. When fired:
                //   1. pop `sources` after `s`'s position;
                //   2. run cleanups for popped signals (unsubscribing this
                //      installation from each);
                //   3. resume the captured continuation with the current value.
                fun k(): <io, owner> ()
                    val cur = !sources
                    val (kept, popped) = split-after(cur, sid)
                    sources := kept
                    popped.foreach fn((_, cleanup2)) cleanup2()
                    resume(!s.item)
                    ()
                val sref2 = s.subscribers
                sref2 := !sref2 ++ [(obs-id, k)]
            resume(!s.item)

        ctl set(s, v)
            val iref = s.item
            iref := v
            val subs = !(s.subscribers)
            subs.foreach fn((_, k))
                k()
                ()
            resume(())
    action()

// Render a component into a DOM node. Installs the top-level owner and
// react handler.
pub fun mount(component: () -> <io, react, owner> html): <io> dom-node
    val (node, _dispose) = handle-owner(fn()
        with handle-eff
        render(component())
    )
    node

// Render an `html` value to a DOM node. Each `get` inside the body subscribes
// the surrounding handler installation, so the resulting DOM updates when
// any read state changes.
pub fun render(h: html): <io, react, owner> dom-node
    match h
        Text(content) ->
            val node = create-text-node("")
            set-text-content(node, get(content))
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
            set-attribute(node, "href", get(href))
            node
        Img(src, alt, attrs) ->
            val node = render-element("img", attrs, [])
            set-attribute(node, "src", get(src))
            set-attribute(node, "alt", get(alt))
            node
        Button(attrs, on-click, kids) ->
            val node = render-element("button", attrs, kids)
            add-event-listener(node, "click", on-click)
            node
        Input(input-type, value, on-change) ->
            val node = create-element("input")
            add-event-listener-string(node, "input", on-change)
            set-attribute(node, "type", get(input-type))
            set-attribute(node, "value", get(value))
            node
        If(cond, then-b, else-b) ->
            // Anchor stays put; on each cond change we dispose the previous
            // branch's owner, clear the anchor, and remount the new branch
            // under a fresh owner.
            val anchor = create-element("span")
            val current-dispose : ref<global, () -> <read<global>, write<global>, div> ()> = ref(fn() ())
            val branch = if get(cond) then then-b else else-b
            (!current-dispose)()
            clear-children(anchor)
            val (child, dispose) = handle-owner(fn()
                with handle-eff
                render(branch)
            )
            current-dispose := dispose
            append-child(anchor, child)
            anchor
        For(items) ->
            // Anchor stays put; on each items change we dispose the previous
            // render's owner, clear the anchor, and re-render every item
            // under a fresh per-item react scope.
            val anchor = create-element("span")
            val current-dispose : ref<global, () -> <read<global>, write<global>, div> ()> = ref(fn() ())
            val xs = get(items)
            (!current-dispose)()
            clear-children(anchor)
            val (_unit, dispose) = handle-owner(fn()
                xs.foreach fn(item)
                    with handle-eff
                    append-child(anchor, render(item))
            )
            current-dispose := dispose
            anchor

// Render an element node with attributes and children. Each attribute and
// each child is wrapped in its own `handle-eff` so the captured continuation
// from any internal `get` is scoped tightly — only that one attribute or
// child re-runs when its dependencies change.
fun render-element(tag: string, attrs: list<attr>, kids: list<html>): <io, react, owner> dom-node
    val node = create-element(tag)
    attrs.foreach fn(a)
        handle-eff(fn() apply-attr(node, a))
    kids.foreach fn(k)
        val child = handle-eff(fn() render(k))
        append-child(node, child)
    node

// Apply one attribute to an element. The reactive read happens here, so the
// surrounding `handle-eff` (per attribute) tightly scopes the captured
// continuation.
fun apply-attr(node: dom-node, a: attr): <io, react> ()
    match a
        Class(v) -> set-attribute(node, "class", get(v))
        Id(v) -> set-attribute(node, "id", get(v))
        Style(v) -> set-attribute(node, "style", get(v))
        Data(name, v) -> set-attribute(node, "data-" ++ name, get(v))

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
    add-event-listener-raw(node, kind, fn()
        val (_, dispose) = handle-owner(fn()
            with handle-eff
            cb()
        )
        dispose()
    )

// Attach an input-style listener whose callback receives a string and can
// use `react`. Same scoping rules as `add-event-listener`.
pub fun add-event-listener-string(
    node: dom-node,
    kind: string,
    cb: (string) -> <io, react> ()
): io ()
    add-event-listener-string-raw(node, kind, fn(s)
        val (_, dispose) = handle-owner(fn()
            with handle-eff
            cb(s)
        )
        dispose()
    )

// Split a sources list at the first occurrence of `sid`. Returns
// `(prefix-including-sid, suffix-after-sid)`. Used on subscriber fire to
// determine which downstream sources to drop.
fun split-after(sources, sid: int)
    match sources
        Nil -> (Nil, Nil)
        Cons((key, cleanup), xs) ->
            if key == sid then
                ([(key, cleanup)], xs)
            else
                val (kept, popped) = split-after(xs, sid)
                (Cons((key, cleanup), kept), popped)
