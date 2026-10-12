---
title: Edit Methods
---

# Edit Methods

`--edit` accepts edit methods, arguments, and boolean combinations. For example:

```sh
auto-editor example.mp4 --edit 'audio:0.05,stream=0'
```

The expression form is also accepted:

```sh
auto-editor example.mp4 --edit '(audio 0.05 (= stream 0))'
```

Built-in methods include `audio`, `motion`, `blackdetect`, `subtitle`, `regex`, `word`, `none`, and `all`. Boolean operators are `or`, `and`, `xor`, and `not`. The implementation and parameter defaults are defined in [`src/editmethods.nim`](../../../src/editmethods.nim).
