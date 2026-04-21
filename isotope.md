# Isotope: Design Notes

**Architecture:** Retained mode, event-driven (Nitrogen-inspired).
**Runtime:** Erlang/OTP 27+ `prim_tty` (raw mode).

---

## Architecture Overview

Isotope follows a retained-mode architecture where the application declares a UI tree
and the framework handles layout, rendering, input dispatch, and focus management.

```
Application callback           Framework
┌─────────────┐    ┌──────────────────────────────┐
│ init/1      │───▶│ iso_server (gen_server)       │
│ view/1      │    │   ├── iso_engine (shared nav) │
│ handle_event│◀──▶│   ├── iso_layout (flexbox)    │
└─────────────┘    │   ├── iso_render (tree→cells) │
                   │   ├── iso_screen (diff buffer) │
                   │   ├── iso_tty (prim_tty I/O)  │
                   │   └── iso_input (ANSI parser)  │
                   └──────────────────────────────┘
```

### Event cycle

1. `iso_tty` reads raw bytes from the terminal via `prim_tty`
2. `iso_input` parses ANSI sequences into events (`{key, up}`, `{mouse, ...}`, etc.)
3. `iso_server` dispatches the event — navigation is handled internally,
   application events are forwarded to the callback's `handle_event/2`
4. The callback returns a response (`noreply`, `update_state`, `push_view`, etc.)
5. `iso_server` rebuilds the view tree, runs layout, diffs the screen, and writes changes

### Focus model

- **Containers** hold focusable children. Tab/Shift+Tab cycles between containers.
- **Children** within a container are navigated with arrow keys.
- Elements like `#table{}`, `#list{}`, `#tree{}` handle their own internal navigation.

---

## Element Records

All elements share a common base (id, position, size, style, visibility).

### Layout containers

| Record | Description |
|--------|-------------|
| `#box{}` | General container with children |
| `#vbox{}` | Vertical stack |
| `#hbox{}` | Horizontal stack with optional spacing |
| `#panel{}` | Bordered container with optional title |
| `#scroll{}` | Scrollable container with offset tracking |
| `#tabs{}` | Tab switcher with per-tab content |
| `#modal{}` | Overlay dialog |

### Content elements

| Record | Description |
|--------|-------------|
| `#text{}` | Static or styled text |
| `#button{}` | Clickable button with optional shortcut key |
| `#input{}` | Text input field with cursor |
| `#table{}` | Data grid with headers, virtual scrolling, row providers |
| `#list{}` | Selectable item list |
| `#tree{}` | Expandable/collapsible tree |
| `#sparkline{}` | Braille-based line chart |
| `#progress{}` | Progress bar |
| `#separator{}` | Horizontal rule |

---

## Callback Interface

An Isotope application implements a callback module:

```erlang
-module(my_app).

init(_Args) ->
    {ok, #my_state{}}.

view(State) ->
    #box{children = [
        #panel{title = <<"My App">>, children = [
            #table{id = my_table, headers = [...], rows = [...]}
        ]}
    ]}.

handle_event({table_select, my_table, Row, Data}, State) ->
    {update_state, State#my_state{selected = Row}};
handle_event({event, {key, enter}}, State) ->
    {push_view, detail_view, #{id => State#my_state.selected}};
handle_event(_, State) ->
    {noreply, State}.
```

### Handler responses

| Response | Effect |
|----------|--------|
| `{noreply, State}` | No visible change |
| `{update_state, State}` | Rebuild view with new state |
| `{update_tree, State, Tree}` | Use provided tree directly |
| `{push_view, Module, Args}` | Navigate to new view |
| `{pop_view, Result}` | Return to previous view |
| `{switch_view, Module, Args}` | Replace current view |
| `stop` | Shut down the application |