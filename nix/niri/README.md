# niri patch: `hide-from-own-capture`

shatterlock's live halves need niri to leave the rift out of the captures shatterlock itself makes.
These patches add that as a layer rule, against niri main (26.04, `f51d761`):

- `0001-Add-hide-from-own-capture-layer-rule.patch`: the rule, the config test. Applied by the
  flake's `overlays.niri` and `packages.niri`.
- `0002-wiki-Document-hide-from-own-capture.patch`: the wiki page. Only for upstream: niri's Nix
  package leaves `docs/` out of its source, so it can't be applied there.

`nix flake check` checks that both still apply to the pinned niri. To rework them: apply both to a
niri checkout, edit, commit, and `git format-patch --no-signature --zero-commit HEAD~2` back here.

## Draft PR description

Nothing has been submitted. This is a starting point if the patch goes upstream.

> **Add hide-from-own-capture layer rule**
>
> This adds a layer rule property that leaves a layer surface (and its popups) out of screen
> captures made by the client that owns it, over wlr-screencopy and ext-image-copy-capture.
> Captures made by any other client, the built-in screenshot UI and screencasts are unchanged.
>
> ```kdl
> layer-rule {
>     match namespace="^magnifier$"
>     hide-from-own-capture true
> }
> ```
>
> **Why.** An overlay that draws from a live capture of the screen under it (a magnifier, a
> screen effect, a "tear the screen open" session menu) currently sees itself in its own capture,
> which feeds back into the next frame. `block-out-from` doesn't help: it paints the surface black
> in the capture instead of leaving it out, and it applies to every capturing client.
>
> **How.**
> - `RenderCtx` gains `capture_client: Option<&ClientId>`, set only when rendering a capture for
>   a client.
> - `MappedLayer::render_normal` and `render_popups` skip surfaces with the rule whose client
>   matches it.
> - ext-image-copy-capture sessions still share renders. Sessions are keyed by cursor drawing, plus
>   the client when that client has such surfaces on the output, so ordinary captures still cost
>   one render each.
>
> **Testing.** There's a config parse test. Tested by hand with a Quickshell overlay that runs a
> live `ScreencopyView` of its own output in nested niri: its halves show the screen beneath, grim
> still sees the overlay.
>
> Open question: windows could get the same window rule; nothing needs it yet.
