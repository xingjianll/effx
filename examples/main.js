// Bridge: imports the Koka-generated `__main` wrapper, which installs the
// default top-level handlers (specifically @default-exn from std/core) before
// invoking the entry. Calling `app.main()` directly skips that wrapper, which
// leaves `exn` unhandled in the runtime evidence vector — and any `<io>` row
// in the framework will then mis-resolve effect ops at runtime.
import "/.koka/v3.2.3/js-debug-40f210/card_dash_demo__main.mjs";
