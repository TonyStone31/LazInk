# Material from elsewhere

LazInk's own code is 0BSD (see `0BSD.txt`).  These parts come from
published standards, and are credited here as their licenses ask.

## The HTML Living Standard - WHATWG

- `inkua.inc`: the default stylesheet, adapted from the standard's
  Rendering section - the rules LazInk lays out, some shortened or
  left out.
- `inkentities.inc`: the table of named character references, generated
  from it.

HTML Living Standard, https://html.spec.whatwg.org/ - Copyright WHATWG
(Apple, Google, Mozilla, Microsoft).  Licensed under the Creative Commons
Attribution 4.0 International License,
https://creativecommons.org/licenses/by/4.0/.  LazInk's copies are
changed from the original as described above.

## RFC 6386, VP8 Data Format and Decoding Guide - IETF

- `inkwebpvp8tables.inc`: the probability, quantizer and tree tables of
  sections 11.5, 13.4, 13.5 and 14.1.

The decoder in `inkwebpvp8.pas` was written from the RFC's description;
the tables are the RFC's own data and are used under its terms for code
components:

    Copyright (c) 2011 IETF Trust and the persons identified as the
    document authors.  All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    - Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    - Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    - Neither the name of Internet Society, IETF or IETF Trust, nor the
      names of specific contributors, may be used to endorse or promote
      products derived from this software without specific prior written
      permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
    OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

A program that ships with LazInk's WebP decoder linked in (anything using
`TInkPage`) should carry this notice in its documentation.

## RFC 9649, WebP Image Format - IETF

`inkwebplossless.pas` and `inkwebp.pas` were written from the RFC's
description.  No code or tables were taken from it.
