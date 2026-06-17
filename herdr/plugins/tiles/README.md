# tiles

A tiny herdr plugin: keyboard shortcuts to tile the **current** pane into common
proportions, with a "flip" for each so you can swap the big/small side.

| Action id      | What it does                                  | Suggested key      |
|----------------|-----------------------------------------------|--------------------|
| `h-wide`       | Horizontal split, current pane = left **6/10**| `prefix+y`         |
| `h-narrow`     | Flip → current pane = left **4/10**          | `prefix+shift+y`   |
| `h-even`       | Revert → horizontal **50/50**                | `prefix+alt+y`     |
| `v-top-small`  | Vertical split, current pane = top **1/5**    | `prefix+u`         |
| `v-top-large`  | Flip → current pane = top **4/5**            | `prefix+shift+u`   |
| `v-even`       | Revert → vertical **50/50**                  | `prefix+alt+u`     |

`prefix+y` = horizontal, `prefix+u` = vertical. The `shift` modifier **flips**
the big/small side; the `alt` modifier **reverts** to an even 50/50 split.

The **current/selected** pane is always the leading section (left for horizontal,
top for vertical).

## Split vs. resize (why flip doesn't spawn a third pane)

- If the current pane has **no neighbour** on that axis, it is **split** so the
  current pane becomes the leading side at the target fraction.
- If a neighbour **already exists**, the divider is **resized** to hit the target
  fraction instead — so the flip re-proportions the existing two panes.

Works best on a tab holding one or two panes. With deeper nesting it operates on
the current pane and its immediate neighbour on the chosen axis.

## Install / develop

```sh
# from this directory, for local development:
herdr plugin link .
herdr plugin action list --plugin local.tiles   # verify it loaded
```

> **Editing actions?** After you change `herdr-plugin.toml` (add/rename/remove
> an action), re-run `herdr plugin link <path>` to re-register the action list.
> `herdr server reload-config` only re-reads keybindings — it does **not**
> refresh plugin actions, so new actions will fail with `plugin action not
> found` until you re-link. Verify with `herdr plugin action list --plugin
> local.tiles`.

> **Note:** requires a herdr build whose socket API exposes the plugin runtime
> (`plugin.*` requests). On herdr 0.7.0 the `herdr plugin …` CLI exists but the
> daemon may reject `plugin.link` with `unknown variant 'plugin.link'` — that
> build can't load plugins yet. The pane primitives the plugin uses
> (`pane split`/`resize`/`layout`/`get`) all work, so you can run it directly:
>
> ```sh
> HERDR_PANE_ID=$(herdr pane current 2>/dev/null) python3 tile.py h 0.6
> ```

## Keybindings

Add to `~/.config/herdr/config.toml` (this repo's `herdr/config.toml`). These
keys avoid herdr's built-in defaults: `prefix+y` = horizontal, `prefix+u` =
vertical, with `shift` to flip and `alt` to revert to 50/50.

```toml
[[keys.command]]
key = "prefix+y"
type = "plugin_action"
command = "local.tiles.h-wide"
description = "tile: horizontal, current 6/10 left"

[[keys.command]]
key = "prefix+shift+y"
type = "plugin_action"
command = "local.tiles.h-narrow"
description = "tile: horizontal flip, current 4/10 left"

[[keys.command]]
key = "prefix+alt+y"
type = "plugin_action"
command = "local.tiles.h-even"
description = "tile: horizontal revert, even 50/50"

[[keys.command]]
key = "prefix+u"
type = "plugin_action"
command = "local.tiles.v-top-small"
description = "tile: vertical, current 1/5 top"

[[keys.command]]
key = "prefix+shift+u"
type = "plugin_action"
command = "local.tiles.v-top-large"
description = "tile: vertical flip, current 4/5 top"

[[keys.command]]
key = "prefix+alt+u"
type = "plugin_action"
command = "local.tiles.v-even"
description = "tile: vertical revert, even 50/50"
```

Reload with `herdr server reload-config` — a `status: applied` with no
diagnostics means all six bindings are active.

## How the herdr resize model works (learned empirically on 0.7.0)

- `pane split --ratio R` → the **original** (leading) pane keeps fraction `R`.
- `pane resize --direction D --amount A --pane X` grows pane `X`'s edge on side
  `D` outward by `A` (a fraction of the split span). An **outer** edge is a wall,
  so the call is a no-op there. To **shrink** a pane you grow its **neighbour**
  toward it instead. A single resize can be clamped by min pane size, so
  `tile.py` loops until it converges.
