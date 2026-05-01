/*----------------------------------------------------------------------------
   Copyright 2026, Kevin Liu

   Licensed under the MIT License. You may not use this file except in
   compliance with the License. A copy of the License can be found in the
   LICENSE file at the root of this distribution.
----------------------------------------------------------------------------*/

// Effx — JS/DOM bindings.
//
// Raw `extern` declarations for browser DOM operations and event registration.
// These are the primitive imperative operations that the rest of Effx is
// built on top of. Higher-level wrappers (which install handlers around the
// callbacks) live in the main `effx` module.

module bindings

// Opaque handle to a DOM node.
pub value type dom-node

// Look up an element by its `id` attribute.
pub extern get-element-by-id(id: string): io dom-node
    js inline "document.getElementById(#1)"

// Create a new element of the given tag (e.g. "div", "span").
pub extern create-element(tag: string): io dom-node
    js inline "document.createElement(#1)"

// Create a text node with the given initial text.
pub extern create-text-node(text: string): io dom-node
    js inline "document.createTextNode(#1)"

// Append `child` as the last child of `parent`.
pub extern append-child(parent: dom-node, child: dom-node): io ()
    js inline "(#1).appendChild(#2)"

// Set an attribute on a node.
pub extern set-attribute(node: dom-node, name: string, value: string): io ()
    js inline "(#1).setAttribute(#2, #3)"

// Remove an attribute from a node. Used to implement boolean attrs whose
// "false" state means the attribute is absent from the DOM.
pub extern remove-attribute(node: dom-node, name: string): io ()
    js inline "(#1).removeAttribute(#2)"

// Replace a node's text content.
pub extern set-text-content(node: dom-node, text: string): io ()
    js inline "(#1).textContent = #2"

// Remove `child` from `parent`.
pub extern remove-child(parent: dom-node, child: dom-node): io ()
    js inline "(#1).removeChild(#2)"

// Remove all children of `node`.
pub extern clear-children(node: dom-node): io ()
    js inline "(() => { while ((#1).firstChild) (#1).removeChild((#1).firstChild) })()"

// Register a click-style listener that takes no event payload.
// This is the raw form: callers in the main module wrap this so that
// the callback can use `react` operations.
pub extern add-event-listener-raw(
    node: dom-node,
    kind: string,
    cb: () -> <io-total, div> ()
): io ()
    js inline "(#1).addEventListener(#2, #3)"

// Register an input-style listener that receives the event target's `value`.
pub extern add-event-listener-string-raw(
    node: dom-node,
    kind: string,
    cb: (string) -> <io-total, div> ()
): io ()
    js inline "(#1).addEventListener(#2, e => (#3)(e.target.value))"
