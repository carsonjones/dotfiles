# sort-tabs

one action, `sort`: reorders tabs in the current workspace A–Z by label (case-insensitive, ties by tab number). uses the socket API's `tab.move` since the CLI has no reorder

## install

```sh
herdr plugin link .
herdr plugin action list --plugin local.sort_tabs
```

## keybinding

`prefix+shift+t` in this repo's `herdr/config.toml`

## cli

```sh
bun sort-tabs.ts                    # current workspace ($HERDR_WORKSPACE_ID)
bun sort-tabs.ts --workspace w9
bun sort-tabs.ts --dry-run          # print order, don't move
```
