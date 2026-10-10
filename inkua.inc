{ The browser's own stylesheet: what every element looks like before a page
  says anything - the parts of the HTML standard's rendering section that
  LazInk lays out.  Kept as CSS so it reads like the standard. }
const
  InkUserAgentCSS =
    'html, address, blockquote, body, center, dialog, div, figure, figcaption,' +
    ' footer, form, header, hr, legend, listing, main, p, plaintext, pre,' +
    ' search, xmp, article, aside, h1, h2, h3, h4, h5, h6, hgroup, nav,' +
    ' section, dir, dd, dl, dt, menu, ol, ul, details, summary, fieldset,' +
    ' optgroup, frameset, frame, noframes { display: block }' +
    'li { display: list-item }' +
    'head, script, style, link, meta, template, datalist, param, area,' +
    ' base, basefont, rp, noembed, [hidden], dialog:not([open]), title:not(svg title),' +
    ' input[type=hidden i] { display: none }' +
    'table { display: table; border-collapse: separate; border-spacing: 2px;' +
    ' box-sizing: border-box; text-indent: initial }' +
    'caption { display: table-caption; text-align: center }' +
    'colgroup { display: table-column-group } col { display: table-column }' +
    'thead { display: table-header-group; vertical-align: middle }' +
    'tbody { display: table-row-group; vertical-align: middle }' +
    'tfoot { display: table-footer-group; vertical-align: middle }' +
    'tr { display: table-row; vertical-align: inherit }' +
    'td, th { display: table-cell; vertical-align: inherit; padding: 1px }' +
    'th { font-weight: bold; text-align: center }' +
    'body { margin: 8px }' +
    'p, blockquote, figure, dl { margin-top: 1em; margin-bottom: 1em }' +
    'blockquote, figure { margin-left: 40px; margin-right: 40px }' +
    'h1 { font-size: 2em; margin-top: 0.67em; margin-bottom: 0.67em; font-weight: bold }' +
    'h2 { font-size: 1.5em; margin-top: 0.83em; margin-bottom: 0.83em; font-weight: bold }' +
    'h3 { font-size: 1.17em; margin-top: 1em; margin-bottom: 1em; font-weight: bold }' +
    'h4 { margin-top: 1.33em; margin-bottom: 1.33em; font-weight: bold }' +
    'h5 { font-size: 0.83em; margin-top: 1.67em; margin-bottom: 1.67em; font-weight: bold }' +
    'h6 { font-size: 0.67em; margin-top: 2.33em; margin-bottom: 2.33em; font-weight: bold }' +
    'ul, menu, dir { list-style-type: disc; margin-top: 1em; margin-bottom: 1em; padding-left: 40px }' +
    'ol { list-style-type: decimal; margin-top: 1em; margin-bottom: 1em; padding-left: 40px }' +
    ':is(dir, dl, menu, ol, ul) :is(dir, dl, menu, ol, ul) { margin-top: 0; margin-bottom: 0 }' +
    ':is(ul, menu, dir) :is(ul, menu, dir), :is(ol) :is(ul, menu, dir) { list-style-type: circle }' +
    ':is(ul, ol, menu, dir) :is(ul, ol, menu, dir) :is(ul, menu, dir) { list-style-type: square }' +
    'dd { margin-left: 40px }' +
    'pre, xmp, plaintext, listing { white-space: pre; margin-top: 1em; margin-bottom: 1em;' +
    ' font-family: monospace }' +
    'tt, code, kbd, samp { font-family: monospace }' +
    'textarea { white-space: pre-wrap; font-family: monospace }' +
    'b, strong { font-weight: bolder }' +
    'i, cite, em, var, dfn, address { font-style: italic }' +
    'u, ins { text-decoration-line: underline }' +
    's, strike, del { text-decoration-line: line-through }' +
    'big { font-size: larger } small { font-size: smaller }' +
    'sub { vertical-align: sub; font-size: smaller }' +
    'sup { vertical-align: super; font-size: smaller }' +
    ':any-link { color: linktext; text-decoration-line: underline; cursor: pointer }' +
    'mark { background-color: mark; color: marktext }' +
    'abbr[title], acronym[title] { text-decoration-line: underline; text-decoration-style: dotted }' +
    'center { text-align: -webkit-center }' +
    'hr { color: gray; border-style: inset; border-width: 1px; margin-top: 0.5em;' +
    ' margin-bottom: 0.5em; margin-left: auto; margin-right: auto; overflow: hidden }' +
    'q::before { content: open-quote } q::after { content: close-quote }' +
    'rt { font-size: 50% }' +
    'details > summary:first-of-type { display: list-item;' +
    ' list-style-type: disclosure-closed; list-style-position: inside }' +
    'details[open] > summary:first-of-type { list-style-type: disclosure-open }' +
    'fieldset { margin-left: 2px; margin-right: 2px; padding: 0.35em 0.75em 0.625em;' +
    ' border: 2px groove threedface }' +
    'legend { padding-left: 2px; padding-right: 2px }' +
    'input, select, button, textarea { display: inline-block; font-size: 13.333px;' +
    ' font-family: Arial; color: fieldtext; line-height: normal; text-transform: none;' +
    ' text-indent: 0; letter-spacing: normal; word-spacing: normal; text-align: start }' +
    'input[type=checkbox i] { margin: 3px 3px 3px 4px }' +
    'input:not([type=checkbox i], [type=radio i], [type=hidden i], [type=image i],' +
    ' [type=range i], [type=color i], [type=button i], [type=submit i], [type=reset i],' +
    ' [type=file i]), textarea { background-color: field; border: 2px inset light-dark(#767676, #858585);' +
    ' padding: 1px 2px }' +
    'input:not([type=image i], [type=range i], [type=checkbox i], [type=radio i]) { overflow: clip }' +
    'svg:not(:root), symbol, image, marker, pattern, foreignObject { overflow: hidden }' +
    'input[type=radio i] { margin: 3px 3px 0 5px }' +
    'img, video, canvas, iframe, embed, object { overflow: clip }' +
    'button, input[type=button i], input[type=submit i], input[type=reset i] { text-align: center }' +
    { a page with no doctype, or an old one, gets the old rules too }
    '@media (-ink-quirks) { table { font-weight: initial; font-style: initial;' +
    ' font-variant: initial; font-size: initial; line-height: initial;' +
    ' white-space: initial; text-align: initial } form { margin-bottom: 1em }' +
    ' img[align=left i] { margin-right: 3px } img[align=right i] { margin-left: 3px } }' +
    'button { padding: 1px 6px; border: 2px outset buttonborder;' +
    ' background-color: buttonface; color: buttontext }' +
    'iframe { border: 2px inset }' +
    'nobr { white-space: nowrap }' +
    'ruby { display: ruby } rt { display: ruby-text }';
