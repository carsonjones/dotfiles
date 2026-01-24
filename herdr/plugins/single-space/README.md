# single-space

like a sheepdog, for the herd

a tiny herdr plugin: one action, `collect`, that rounds up every pane scattered across your other workspaces and dumps each one into its own new tab in your **current** workspace. panes already living in the current workspace are left untouched.

## why

if you end up with panes spread across `main`, `mobile`, etc. and just want everything in one space to eyeball at once, `collect` does the herding for you.

## install / develop

```sh
# from this directory, for local development:
herdr plugin link .
herdr plugin action list --plugin local.single_space   # verify it loaded
```

> editing `herdr-plugin.toml`? re-run `herdr plugin link <path>` — `herdr server reload-config` only re-reads keybindings, not plugin actions.

## keybinding

add to `~/.config/herdr/config.toml` (this repo's `herdr/config.toml`):

```toml
[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "local.single_space.collect"
description = "single-space: collect all panes into current space"
```

reload with `herdr server reload-config`.
