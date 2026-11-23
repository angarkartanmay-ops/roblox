# UI artifacts (section 3)

The UI is built at runtime by the client controllers (HudController, SelectController,
NameplateController) from `src/client/Lib/UiKit.luau`, so these files are NOT synced by Rojo.
Each `.model.json` here is the instance tree EXPORTED from a Studio playtest (names and classes only),
the inventory the asset plan is checked against. `mockup.png` is a playtest capture of the
Phase Select screen over the HUD. `FighterDetail_<id>` files are the single detail panel as it is named
while showing that fighter. PhaseNameplate only exists with a second player (two-player test, section 5).

World-space text that must read through bodies lives on the `WorldOverlay` ScreenGui (DisplayOrder 2,
IgnoreGuiInset), projected each frame with `Camera:WorldToViewportPoint`: `RelationIndicator` and the
short-lived `DamageNumber` labels (0.9 s each, exported with one alive). A BillboardGui with
AlwaysOnTop = true did not render at all in this Studio build (measured), which is why they moved off
billboards. `DummyPhaseLabel` is the third line of a training dummy's own `Nameplate` billboard
(`DummyNameplate.model.json`), not a billboard of its own.
