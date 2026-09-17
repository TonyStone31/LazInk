# Upstream attribution and provenance

## Project JEDI — JVCL

LazInk's `inkhtml.pas` is derived from the JVCL HTML drawing routines. It is
not merely an implementation inspired by them. `inktables.inc` is distributed
under MPL 1.1 as an implementation include of this renderer.

Upstream projects and source files:

- [Project JEDI / JVCL](https://github.com/project-jedi/jvcl)
- [JvHTControls.PAS](https://github.com/project-jedi/jvcl/blob/master/jvcl/run/JvHtControls.pas), released 2002-07-04.
- [JvJVCLUtils.PAS](https://github.com/project-jedi/jvcl/blob/master/jvcl/run/JvJVCLUtils.pas), released 2002-09-24.

The upstream file notices identify the following initial developers and
copyrights. These are preserved as upstream notices; they do not assert that
every contributor wrote every routine used here.

JvHTControls.PAS:

- Initial developer: Andrei Prygounkov.
- Copyright (c) 1999, 2002 Andrei Prygounkov. All Rights Reserved.
- Listed contributors: Maciej Kaczkowski, Timo Tegtmeier, Andreas Hausladen.

JvJVCLUtils.PAS:

- Initial developers: Fedor Koshevnikov, Igor Pavluk and Serge Korolev.
- Copyright (c) 1997, 1998 Fedor Koshevnikov, Igor Pavluk and Serge Korolev.
- Copyright (c) 2001,2002 SGB Software. All Rights Reserved.

The applicable renderer license is the
[Mozilla Public License 1.1](LICENSES/MPL-1.1.txt).
Keep its notices and the corresponding source available when distributing it.
LazInk modifications are recorded in [RENDERER_CHANGES.md](docs/RENDERER_CHANGES.md).

## Route into LazInk

The starting point was an HTML-formatted, owner-drawn Lazarus listbox example.
In an [August 24, 2021 forum post](https://forum.lazarus.freepascal.org/index.php/topic,55971.msg416110.html#msg416110),
wp explained that the HTML routines were copied from JVCL's `JvJVCLUtils`
into a standalone `jvclHTMLUtils` unit. This removed the package-installation
dependency; it did not replace the upstream code's license.

The [original html_log.zip attachment](https://forum.lazarus.freepascal.org/index.php?action=dlattach;topic=55971.0;attach=44903)
was recovered and compared with LazInk on September 16, 2026. The routines
`HTMLStringToColor`, `GetChar`, and `HTMLDeleteTag` still match that attachment
apart from whitespace and letter case. The drawing routine also retains
adapted upstream implementation. This is concrete evidence of retained code,
not an inference based only on similar names.

The attachment's SHA-256 at review time:
`5b82e6455b3f73eb3074a1ef9bc647891e12c1096c10eb2cec7e07e7256877ac`.

The reviewed upstream files' SHA-256 values:

- JvHTControls.pas: `de0821dc254f555d4c52433747093ff95f77bfb15a32948fb1e1dde7a4b4a1c9`
- JvJVCLUtils.pas: `9dd364c3263fed8115a2aa361d0cf72ed8bead541fde017e427e9b5f0e8f1c71`

The extracted attachment has no license header of its own. Its author's
explicit provenance statement and the upstream source notices establish why
LazInk preserves the JVCL license rather than treating the extraction as
unlicensed original LazInk code.

## Lazarus and Free Pascal

The components use Lazarus/LCL for widgets, graphics and platform integration,
and Free Pascal for the compiler, runtime and image decoding. In particular,
`InkGIF` delegates GIF/LZW decoding to FPC through LCL's image classes; it does
not contain a copied GIF decoder. These dependencies retain their own license
terms. They are separate from the JVCL-derived source bundled in this project.
