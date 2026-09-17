<!--
  Every language LazInk has rules for, one short block each.  Open it in the
  demo (the Documents tab links to it) to see what the highlighter does, or
  edit a block and watch it change.
-->

# Code, in the languages LazInk knows

LazInk colors four things and no more: **comments**, **strings**, **numbers**
and **keywords**. It is not a real highlighter - for that, hand the block to
one through `OnHighlightCode` - but it is enough to make code read like code.

The language comes from the fence (` ```pascal `). A block that names none
still gets colored, by the rules most languages share.

## Pascal

Braces, `(* *)`, `//`, doubled quotes, compiler directives and `$` numbers -
the fullest rules of any language here, and not by accident.

```pascal
unit Greeter;                     { the unit's name }
{$mode ObjFPC}{$H+}
interface
const Reply = 'It''s ready';      // a doubled quote inside a string
type
  TGreeter = class(TObject)
  public
    procedure Greet(Times: Integer);
  end;
implementation
procedure TGreeter.Greet(Times: Integer);
var I: Integer;
begin
  for I := 1 to Times do
    if I mod 2 = 0 then           (* an old-style comment *)
      WriteLn(Reply, ' #', I, ' ', $FF);
end;
end.
```

## C and C++

```c
#include <stdio.h>                /* the classic */
int main(int argc, char **argv) {
  const char *greeting = "hello, world";
  for (int i = 0; i < argc; i++)  // count them
    printf("%s (%d)\n", greeting, i);
  return 0;
}
```

## C#

```csharp
public class Greeter {
    private readonly string _reply = "ready";   // a field
    public async Task<int> GreetAsync(int times) {
        for (var i = 0; i < times; i++) Console.WriteLine($"{_reply} #{i}");
        return times;                           /* and back */
    }
}
```

## Java

```java
@Override
public List<String> greet(int times) {
    var out = new ArrayList<String>();          // an annotation above
    for (int i = 0; i < times; i++) out.add("ready #" + i);
    return out;
}
```

## JavaScript and TypeScript

Template strings in backticks count as strings.

```javascript
const replies = ['ready', 'set'];          // a list
export function greet(times = 3) {
  return replies.map((r, i) => `${r} #${i}`).slice(0, times);
  /* arrow functions and all */
}
```

## Python

Docstrings in triple quotes, `@decorators`, f-strings, and `self`.

```python
@property
def greeting(self) -> str:
    """What the greeter says."""
    count = 42                      # a number
    return f"{self.name} says ready, {count} times"
```

## Ruby

```ruby
class Greeter
  def greet(times = 3)              # a default argument
    times.times { |i| puts "ready ##{i}" }
  end
end
```

## Shell

```sh
# build every unit
for f in *.pas; do
  echo "compiling $f"               # a comment after a string
done
```

## Go

```go
package main

import "fmt"

func greet(times int) {             // Go's braces, C's comments
    for i := 0; i < times; i++ {
        fmt.Println(`ready`, i)     /* a raw string in backticks */
    }
}
```

## Rust

```rust
fn greet(times: u32) -> Vec<String> {
    let mut out = Vec::new();       // mut, let, fn
    for i in 0..times {
        out.push(format!("ready #{}", i));
    }
    out                             /* no semicolon: this is the result */
}
```

## PHP

```php
<?php
function greet(int $times = 3): array {
    $out = [];                      # PHP takes both comment styles
    for ($i = 0; $i < $times; $i++) $out[] = "ready #$i";   // like this
    return $out;
}
```

## SQL

```sql
-- how many are ready
SELECT name, COUNT(*) AS total
  FROM greetings
 WHERE state = 'ready'              /* a block comment */
 GROUP BY name
 ORDER BY total DESC
 LIMIT 10;
```

## Lua

```lua
--[[ a block comment ]]
local function greet(times)
  for i = 1, times or 3 do          -- a line comment
    print("ready #" .. i)
  end
end
```

## Haskell

```haskell
{- a block comment -}
greet :: Int -> [String]
greet times = map line [1 .. times]   -- a line comment
  where line i = "ready #" ++ show i
```

## HTML

Tag names are colored as this language's keywords.

```html
<!-- a card -->
<div class="card">
  <h3>Ready</h3>
  <a href="index.html" title="back">Home</a>
</div>
```

## CSS

```css
/* the card */
.card {
  background: #1e2127;
  padding: 10px 12px;
  border-radius: 8px;
}
```

## JSON

```json
{
  "name": "LazInk",
  "version": 1,
  "highlight": true,
  "languages": ["pascal", "c", "python"]
}
```

## YAML

```yaml
# what to build
name: LazInk
units: 14
widgetsets:
  - gtk3
  - win32
```

## Assembler

```asm
    mov ax, 1        ; the semicolon is the comment
    add ax, 41       ; 42
    int 0x80
```

## Visual Basic

```vb
' the apostrophe is the comment
Function Greet(times As Integer) As String
    REM and so is REM
    Greet = "ready " & CStr(times)
End Function
```

## MATLAB

```matlab
% how many
function out = greet(times)
  out = cell(1, times);
  for i = 1:times
    out{i} = sprintf('ready #%d', i);   % a note
  end
end
```

## OCaml

```ocaml
(* the ML comment *)
let greet times =
  let rec go i acc = if i > times then acc else go (i + 1) (i :: acc) in
  go 1 []
```

## Julia

```julia
#= a block comment =#
function greet(times = 3)
    for i in 1:times            # a line comment
        println("ready #$i")
    end
end
```

## Batch

```batch
:: build it
@echo off
REM and the old way of saying the same thing
for %%f in (*.pas) do echo compiling %%f
```

## And one that says nothing

No fence language, so the shared rules do what they can - which is most of it.

```
function widen(n) {
  /* a block comment */
  if (n > 42) return "too big";   // and a line one
  begin
    return n * 1.5;               # a note, spaced off the code
  end
}
```

[Back to the tour](tour.md)
