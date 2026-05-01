/*----------------------------------------------------------------------------
   Copyright 2026, Xingjian Liu

   Licensed under the MIT License. You may not use this file except in
   compliance with the License. A copy of the License can be found in the
   LICENSE file at the root of this distribution.
----------------------------------------------------------------------------*/

// Effx — fine-grained reactive primitives on top of Koka's algebraic effect
// handlers.
//
// Design at a glance:
//
//   - `state<a>` is a reactive cell. Each cell has a unique `sid` and a
//     subscribers dict (keyed by `obs-id`).
//   - `react` provides `get` and `set` operations on cells. `get` captures
//     a continuation that is fired when the cell changes; `set` writes the
//     new value and dispatches all current subscribers.
//   - `handle-react` installs a react handler. Each installation gets a
//     unique `obs-id` and tracks its read sources. On a subscriber fire, the
//     installation pops sources after the triggering signal and unsubscribes
//     from those signals — the algorithmic analog of Solid's sources-diff.
//   - `owner` and `handle-owner` give an explicit ownership scope. Each
//     `handle-react` installation registers a self-disposer with the ambient
//     owner, so disposing the owner tears down all its installations.
//
// Subscribers are deduplicated per (signal, obs-id), so multiple `get` calls
// in the same handler scope only register one subscriber per signal.
//
// HTML types and rendering live in `html.kk`. JS/DOM bindings live in
// `bindings.kk`.

module effx

import std/core/list

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

// Allocate a fresh cell with the given initial value.
pub fun state/new(initial: a) : <st<global>, ndet> state<a>
    State(item = ref(initial), subscribers = ref([]), sid = unique())

// Reactive read/write operations. `get` subscribes the current handler
// installation; `set` writes the cell and fires subscribers.
pub effect react
    ctl get<a>(s: state<a>) : a
    ctl set<a>(s: state<a>, v: a) : ()

// A side-effecting cleanup callback. Stored in owner scopes and signal
// cleanup slots; running it unsubscribes its installation or disposes a
// scope.
pub alias disposer = () -> <read<global>, write<global>, div> ()

// Ownership scope for cleanup. Every `handle-react` installation registers a
// self-disposer with the ambient owner; disposing the owner walks those
// disposers, unsubscribing each installation from every signal it held.
pub effect owner
    fun register-disposer(d: disposer) : ()

// Run `action` under a fresh owner scope. Returns the action's result and a
// disposer that, when called, runs every disposer registered during action.
//
// Typical use:
//
//   val (node, dispose) = handle-owner(fn() ...)
//   ...
//   dispose()   // tears down everything created inside the scope
pub fun handle-owner(action: () -> <io, owner> a) : <io> (a, disposer)
    val disposers : ref<global, list<disposer>> = ref([])
    val result =
        with handler
            fun register-disposer(d)
                disposers := Cons(d, !disposers)
        action()
    val dispose-all : disposer = fn()
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
pub fun handle-react(action: () -> <io, react, owner> a) : <io, owner> a
    val obs-id = unique()
    val sources : ref<global, list<(int, disposer)>> = ref([])

    // Tear-down: walk our sources, run each cleanup, then empty the list.
    val self-dispose : disposer = fn()
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
                val cleanup : disposer = fn()
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

// Split a sources list at the first occurrence of `sid`. Returns
// `(prefix-including-sid, suffix-after-sid)`. Used on subscriber fire to
// determine which downstream sources to drop.
pub fun split-after(sources: list<(int, disposer)>, sid: int) : (list<(int, disposer)>, list<(int, disposer)>)
    match sources
        Nil -> (Nil, Nil)
        Cons((key, cleanup), xs) ->
            if key == sid then
                ([(key, cleanup)], xs)
            else
                val (kept, popped) = split-after(xs, sid)
                (Cons((key, cleanup), kept), popped)

