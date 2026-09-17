# Renderer provenance and modifications

The original code is the HTML drawing implementation from Project JEDI's
JVCL `JvHTControls.PAS` and `JvJVCLUtils.PAS`. Initial developers, copyright
notices and source links are preserved in `../THIRD_PARTY_NOTICES.md` and the
`inkhtml.pas` header. The modified renderer is distributed under MPL 1.1;
see `../LICENSES/MPL-1.1.txt`.

This record was assembled on September 16, 2026 from the original forum
attachment, repository history, and the current working tree. Entries that
cover accumulated work are not claims about each change's precise authorship
or date.

- **August 24, 2021:** wp published a Lazarus owner-drawn HTML listbox example
  with the relevant JVCL utility routines extracted into `jvclHTMLUtils`.
  The attachment includes LCL/UTF-8 adaptations and comments identifying
  adjustments to output parameters and drawing routines.
- **August 31, 2026:** LazInk's initial repository commit (`b02b535`) includes
  the adapted standalone renderer and component wrappers. Compared with the
  2021 attachment, the accumulated renderer changes include additional font,
  markup, entity, colour and layout handling.
- **August 31, 2026:** commit `0a8b53f` renames `jvclhtmlutils.pas` to
  `inkhtml.pas`, with unit name `InkHtml`.
- **Through September 16, 2026:** the working renderer adds/refines option
  records, borders, line spacing, image-list rendering, link hit information
  and hover styling, block alignment, background contrast, font restoration,
  superscript/subscript sizing, and UTF-8/CJK-aware word wrapping.
- **September 16, 2026:** table drawing, measurement and link hit testing are
  added in `inktables.inc`; the existing inline renderer is dispatched through
  `HTMLDrawTextEx3`. Table-aware wrapping and plain-text cell/row separators
  are added. The include is distributed under MPL 1.1 with the renderer.
- **September 16, 2026:** source notices are expanded to preserve the named
  initial developers and upstream copyrights. Full license texts, per-file
  licensing information, and the retained-code comparison are added.

Independent Markdown, page-viewer, CSS and animation helper units are covered
by the project's MIT license, not represented as upstream JVCL implementations.
Future modifications to the covered renderer should extend this record.
