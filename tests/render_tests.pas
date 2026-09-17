program RenderTests;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types, LCLType,
  InkScrollBar, InkHtml, InkMarkdown, InkLabel, InkMemo, InkListBox, InkPage, InkCSS, InkGIF;
var B: TBitmap; O: THTMLOptions; Wide, Narrow: TSize; Hit: THTMLHitInfo;
  S: string; X,Y, Found: Integer; F: TForm; M: TInkMemo; L: TInkLabel;
  List: TInkListBox; Page: TInkPage; CSS: TInkStyleSheet;
  TextOutput: TStringList;
  Files: TStringList; I, Images, Pass: Integer; GIF: TInkGIF; GIFStream: TFileStream;
  Source: TStringList; Tags: string; K, Wanted: Integer;
type
  { the mouse handlers are protected; a test reaches them the way a
    descendant would }
  TPageProbe = class(TInkPage)
  public
    Clicked: string;
    procedure Press(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    procedure Let(X, Y: Integer);
    procedure LinkHit(Sender: TObject; const URL: string);
  end;

procedure TPageProbe.Press(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TPageProbe.MoveTo(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TPageProbe.Let(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TPageProbe.LinkHit(Sender: TObject; const URL: string);
begin
  Clicked := URL;
end;

type
  { the scrollbar's mouse handlers, reached the same way }
  TBarProbe = class(TInkScrollBar)
  public
    Changes: Integer;
    procedure Press(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    procedure Let(X, Y: Integer);
    procedure Key(K: Word);
    procedure Wheel(Delta: Integer);
    procedure Changed(Sender: TObject);
  end;

procedure TBarProbe.Press(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TBarProbe.MoveTo(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TBarProbe.Let(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TBarProbe.Key(K: Word);
begin
  KeyDown(K, []);
end;

procedure TBarProbe.Wheel(Delta: Integer);
begin
  DoMouseWheel([], Delta, Point(0, 0));
end;

procedure TBarProbe.Changed(Sender: TObject);
begin
  Inc(Changes);
end;

var Probe: TPageProbe; Tall: string; J: Integer;
  Bar: TBarProbe; TR: TRect; Before: Integer; Shot: TBitmap;

{ what the page's scrollbar comes out as, for a given style block }
procedure StyledBar(const CSSText: string);
begin
  Probe.LoadHTML('<html><head><style>' + CSSText + '</style></head><body>' +
    Tall + '</body></html>');
  Probe.ScrollTo(0);
end;

procedure Check(OK: Boolean; const MessageText: string);
begin
  if not OK then raise Exception.Create(MessageText);
end;
begin
  Application.Initialize;
  S := MarkdownToInk('# Heading'+LineEnding+'| Name | Value |'+LineEnding+
    '| --- | --- |'+LineEnding+'| **bold** | `a|b` |');
  Check(Pos('<table>',S)>0,'Markdown table');
  Check(Pos('<th>Name</th>',S)>0,'Header cells');
  Check(Pos('<b>bold</b>',S)>0,'Cell emphasis');
  Check(Pos('a|b</font>',S)>0,'Code pipes must not split cells');
  Check(Pos('&lt;script&gt;',MarkdownToInk('<script>'))>0,'Escape raw HTML');
  Check(Pos('<a href="x&amp;y">label</a>',MarkdownToInk('[label](x&y)'))>0,'Link escaping');
  Check(Pos('<table>',MarkdownToInk('a | b'+LineEnding+'-- | ---'))=0,'Invalid delimiter row');
  Check(Pos('a|b</td>',MarkdownToInk('a | b'+LineEnding+'--- | ---'+LineEnding+'a\|b | c'))>0,'Escaped pipes');
  Check(InkToHTML('<b>hello</b>',itfHTML)='<b>hello</b>','HTML passthrough');
  B := TBitmap.Create;
  F := TForm.Create(nil);
  try
    B.SetSize(700,700); B.Canvas.Font.Name := 'DejaVu Sans'; B.Canvas.Font.Size := 11;
    O := DefaultHTMLOptions;
    S := '<a href="before">Before</a><table><tr><th>Heading</th><th>Description</th></tr>'+ 
      '<tr><td><a href="cell">Cell</a></td><td>A long sentence with several words that should wrap in a narrow column.</td></tr></table>'+ 
      '<a href="after">After</a>';
    Wide := HTMLTextExtentOpt(B.Canvas,Rect(0,0,650,0),[],S,O);
    Narrow := HTMLTextExtentOpt(B.Canvas,Rect(0,0,180,0),[],S,O);
    Check(Narrow.cy>Wide.cy,'Narrow tables grow vertically');
    Check(Narrow.cx<=180,'Columns fit available width');
    HTMLDrawOpt(B.Canvas,Rect(0,0,180,700),[],S,O);
    Found := 0;
    Y := 0;
    while Y <= Narrow.cy do
    begin
      X := 0;
      while X <= 180 do
      begin
        Hit := HTMLHitTest(B.Canvas,Rect(0,0,180,700),S,O,X,Y);
        if Hit.OnLink then
        begin
          if Hit.LinkName='before' then begin Check(Hit.LinkIndex=1,'First link ordinal'); Found := Found or 1 end;
          if Hit.LinkName='cell' then begin Check(Hit.LinkIndex=2,'Cell link ordinal'); Found := Found or 2 end;
          if Hit.LinkName='after' then begin Check(Hit.LinkIndex=3,'Last link ordinal'); Found := Found or 4 end;
        end;
        Inc(X,6);
      end;
      Inc(Y,6);
    end;
    Check(Found=7,'All table/document links are hit-testable');
    HTMLDrawOpt(B.Canvas,Rect(0,0,100,700),[],'<table><tr><td>unfinished',O);
    HTMLDrawOpt(B.Canvas,Rect(0,0,100,700),[],'<table></table>',O);
    HTMLDrawOpt(B.Canvas,Rect(0,0,100,700),[],'<table><tr><td>A</td><td>B</td></tr><tr><td>C</td></tr></table>',O);
    M := TInkMemo.Create(F); M.Parent := F; M.TextFormat := itfMarkdown;
    M.LoadDocument('| A | B |'+LineEnding+'| --- | --- |'+LineEnding+'| C | D |');
    Check(M.Lines.Count=1,'Whole document remains one memo entry');
    M.TextFormat := itfHTML; M.TextFormat := itfMarkdown;
    L := TInkLabel.Create(F); L.Parent := F; L.TextFormat := itfMarkdown; L.Caption := '**hello**';
    List := TInkListBox.Create(F); List.Parent := F; List.TextFormat := itfMarkdown; List.Items.Add('**hello**');
    Check(Trim(List.GetPlainText(0))='hello','Markdown plain-text export');
    CSS := TInkStyleSheet.Create;
    try
      CSS.Add(':root { --bg: #23262c } body {background:var(--bg)} .note {color:#123456}');
      Check(CSS.Value('body','','background','')='#23262c','CSS custom property');
      Check(CSS.Value('p','note','color','')='#123456','CSS class selector');
      CSS.Add('@media (max-width:600px) {body {color:red}} p {color:blue}');
      Check(CSS.Value('p','','color','')='blue','Skip unsupported media blocks');
    finally CSS.Free end;
    Page := TInkPage.Create(F); Page.Parent := F; Page.SetBounds(0,0,700,500);
    Page.LoadHTML('<html><head><title>Test</title></head><body><h1>Heading</h1><p id="target">A&#x27;s &rsaquo; B</p><script>hidden</script></body></html>');
    Check(Page.DocumentTitle='Test','Document title');
    Check(Pos('A''s › B',Page.PlainText)>0,'HTML numeric and named entities');
    Check(Pos('hidden',Page.PlainText)=0,'Scripts do not paint');
    F.Show; Application.ProcessMessages;
    Page.JumpToAnchor('target');

    { Dragging the page scrolls it - a touch screen has no wheel, and on
      Windows a finger arrives as a press, moves and a release.  A press
      that barely moves is still a click; a drag that ends on a link is not. }
    Probe := TPageProbe.Create(F); Probe.Parent := F; Probe.SetBounds(0,0,400,200);
    Probe.OnLinkClick := @Probe.LinkHit;
    Tall := '<html><body><p><a href="top">top link</a></p>';
    for J := 1 to 80 do Tall := Tall + '<p>Line ' + IntToStr(J) + '</p>';
    Tall := Tall + '</body></html>';
    Probe.LoadHTML(Tall); Probe.ScrollTo(0);  { lays the page out }
    Check(Probe.ContentHeight > 600, 'A page long enough to scroll');
    Check(Probe.ScrollY = 0, 'Starts at the top');
    Probe.Press(100,150); Probe.MoveTo(100,120); Probe.MoveTo(100,50); Probe.Let(100,50);
    Check(Probe.ScrollY = 100, Format('Dragging up 100 px scrolls down 100 px (%d)', [Probe.ScrollY]));
    Probe.Press(100,50); Probe.MoveTo(100,150); Probe.Let(100,150);
    Check(Probe.ScrollY = 0, 'Dragging back down scrolls back');
    Probe.Press(100,150); Probe.MoveTo(100,-5000); Probe.Let(100,-5000);
    Check(Probe.ScrollY = Probe.ContentHeight - Probe.ClientHeight,
      'A long drag stops at the bottom');
    Probe.ScrollTo(0);
    { find the link, then tap it with a wobble smaller than the slop }
    Probe.Clicked := '';
    for J := 0 to 60 do
    begin
      Probe.Press(30, J); Probe.MoveTo(33, J + 3); Probe.Let(33, J + 3);
      if Probe.Clicked <> '' then Break;
    end;
    Check(Probe.Clicked <> '', 'A tap that wobbles a few pixels still follows the link');
    Check(Probe.ScrollY = 0, 'and does not scroll');
    { a drag that happens to finish on the link is a scroll, not a click }
    Probe.Clicked := '';
    Probe.Press(30, 180); Probe.MoveTo(30, 100); Probe.MoveTo(30, J + 3); Probe.Let(30, J + 3);
    Check(Probe.Clicked = '', 'A drag that ends on a link does not follow it');
    Probe.DragScroll := False;
    Probe.ScrollTo(0);
    Probe.Press(100,150); Probe.MoveTo(100,50); Probe.Let(100,50);
    Check(Probe.ScrollY = 0, 'DragScroll off leaves the page where it is');
    Probe.DragScroll := True;

    { --- CSS for the scrollbar, and the var() it may be written with --- }
    CSS := TInkStyleSheet.Create;
    try
      CSS.Add(':root { --Accent: #102030; --loop: var(--loop) } ' +
        'p { color: var(--missing, #405060) } ' +
        'h1 { color: var(--accent) } ' +
        'h2 { color: #111111 } h2 { color: var(--nothing) } ' +
        'h3 { color: var(--loop) }');
      Check(CSS.Value('p','','color','')='#405060', 'var() falls back to its second part');
      Check(CSS.Value('h1','','color','')='#102030', 'var() names are not case-sensitive in the lookup');
      Check(CSS.Value('h2','','color','')='#111111',
        'an unresolvable var() does not wipe out an earlier valid value');
      Check(CSS.Value('h3','','color','x')='x', 'a var() that refers to itself resolves to nothing');
      Check(CSS.Value('html','','--accent','')='#102030', ':root declarations are the html element''s');
    finally CSS.Free end;

    Tall := '';
    for J := 1 to 80 do Tall := Tall + '<p>Line ' + IntToStr(J) + '</p>';

    StyledBar('html { scrollbar-color: #ff0000 #00ff00 }');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor(255,0,0), 'scrollbar-color sets the thumb');
    Check(ColorToRGB(Probe.ScrollBar.TrackColor) = RGBToColor(0,255,0), 'and the track');
    Check(Probe.ScrollBar.Visible and (Probe.ScrollBar.Width = Probe.Scale96ToFont(18)),
      'auto width is the full bar');

    StyledBar(':root { --t: #123; --k: rgb(10, 20, 30) } ' +
      'html { scrollbar-color: var(--t) var(--k); scrollbar-width: thin }');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor($11,$22,$33),
      'short hex, through a variable');
    Check(ColorToRGB(Probe.ScrollBar.TrackColor) = RGBToColor(10,20,30),
      'rgb() with commas, through a variable');
    Check(Probe.ScrollBar.Width = Probe.Scale96ToFont(10), 'scrollbar-width: thin is narrower');

    StyledBar('body { color: #0000ff; scrollbar-color: currentcolor rgba(1 2 3 / 50%) }');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor(0,0,255),
      'currentcolor is the text colour, and body is read when html says nothing');
    Check(ColorToRGB(Probe.ScrollBar.TrackColor) = RGBToColor(1,2,3), 'rgba() with spaces');

    StyledBar('html { scrollbar-color: #ff0000 #00ff00 } body { scrollbar-color: #0000ff #0000ff }');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor(255,0,0), 'html wins over body');

    StyledBar('body { background: #000000; color: #ffffff; scrollbar-color: bogus #00ff00 }');
    Check(ColorToRGB(Probe.ScrollBar.TrackColor) = RGBToColor(0,0,0),
      'an unreadable pair is ignored: the track is the page background');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor(127,127,127),
      'and the thumb is halfway to the text colour');

    StyledBar('html { scrollbar-width: none }');
    Check(not Probe.ScrollBar.Visible, 'scrollbar-width: none hides it');
    Probe.Press(100,150); Probe.MoveTo(100,50); Probe.Let(100,50);
    Check(Probe.ScrollY = 100, 'and the page still scrolls without it');

    { the bar is drawn in its colours, where it says it is }
    StyledBar('html { scrollbar-color: #ff0000 #00ff00 }');
    Shot := TBitmap.Create;
    try
      Shot.SetSize(Probe.ClientWidth, Probe.ClientHeight);
      Probe.RenderTo(Shot.Canvas);
      TR := Probe.ScrollBar.ThumbRect;
      J := Probe.ClientWidth - Probe.ScrollBar.Width;
      Check(ColorToRGB(Shot.Canvas.Pixels[J + (TR.Left + TR.Right) div 2,
        (TR.Top + TR.Bottom) div 2]) = RGBToColor(255,0,0), 'the thumb is painted in its colour');
      Check(ColorToRGB(Shot.Canvas.Pixels[J + 1, Probe.ClientHeight - 3]) = RGBToColor(0,255,0),
        'the track is painted in its colour');
    finally Shot.Free end;

    { --- the scrollbar on its own --- }
    Bar := TBarProbe.Create(F); Bar.Parent := F; Bar.SetBounds(500, 0, 18, 200);
    Bar.OnChange := @Bar.Changed;
    Bar.SetParams(0, 0, 1000, 200);
    Check(Bar.Position = 0, 'starts at the top');
    Bar.Position := 5000;
    Check(Bar.Position = 800, Format('clamps to the last page (%d)', [Bar.Position]));
    Bar.Position := -5;
    Check(Bar.Position = 0, 'and to the first');
    TR := Bar.ThumbRect;
    Check((TR.Bottom - TR.Top) = (200 - 4) * 200 div 1000,
      Format('the thumb is the visible share of the track (%d)', [TR.Bottom - TR.Top]));
    Before := Bar.Changes;
    Bar.Press(9, TR.Bottom + 20); Bar.Let(9, TR.Bottom + 20);
    Check(Bar.Position = 200, 'a click below the thumb pages down');
    Check(Bar.Changes = Before + 1, 'and says so once');
    TR := Bar.ThumbRect;
    Bar.Press(9, TR.Top - 5); Bar.Let(9, TR.Top - 5);
    Check(Bar.Position = 0, 'a click above it pages up');
    TR := Bar.ThumbRect;
    Bar.Press(9, TR.Top + 5); Bar.MoveTo(9, TR.Top + 5 + (200 - 4 - (TR.Bottom - TR.Top)));
    Bar.Let(9, TR.Top + 5 + (200 - 4 - (TR.Bottom - TR.Top)));
    Check(Bar.Position = 800, Format('dragging the thumb the length of the track reaches the end (%d)', [Bar.Position]));
    Bar.Key(VK_HOME); Check(Bar.Position = 0, 'Home');
    Bar.Key(VK_NEXT); Check(Bar.Position = 200, 'Page Down');
    Bar.Key(VK_DOWN); Check(Bar.Position = 232, 'Down');
    Bar.Key(VK_END); Check(Bar.Position = 800, 'End');
    Bar.Wheel(120); Check(Bar.Position = 760, 'the wheel');
    Bar.SetParams(0, 0, 100, 200);
    Check(Bar.Position = 0, 'nothing to scroll: stays at the top');
    Bar.Press(9, 150); Bar.Let(9, 150);
    Check(Bar.Position = 0, 'and a click does nothing');
    if ParamCount>0 then
    begin
      Files := TStringList.Create; Images := 0; Wanted := 0;
      try
        Files.LoadFromFile(ParamStr(1));
        for I := 0 to Files.Count-1 do
        begin
          Page.LoadFromFile(Files[I]); Page.Repaint;
          Check(Page.DocumentTitle<>'','Missing title: '+Files[I]);
          Check(Page.ContentHeight>100,'Missing layout: '+Files[I]);
          Check(Pos('Heckers Sketch',Page.PlainText)>0,'Missing page text: '+Files[I]);
          if ParamCount>1 then
          begin
            TextOutput := TStringList.Create;
            try
              TextOutput.Text := Page.PlainText;
              TextOutput.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(2))+ExtractFileName(Files[I])+'.txt');
            finally TextOutput.Free end;
          end;
          Inc(Images,Page.ImageCount);
          { what the page itself asks for, so the total is checked against
            the pages given rather than against a count that was true of the
            site on the day the test was written }
          Source := TStringList.Create;
          try
            Source.LoadFromFile(Files[I]);
            Tags := LowerCase(Source.Text);
            K := Pos('<img', Tags);
            while K > 0 do
            begin
              Inc(Wanted);
              K := Pos('<img', Tags, K + 4);
            end;
          finally Source.Free end;
          Check((Pos('&uarr;',Page.PlainText)=0) and (Pos('&darr;',Page.PlainText)=0), 'Arrow entities decode');
          for Pass := 0 to 1 do
          begin
            if Pass=0 then Page.Width := 360 else Page.Width := 1100;
            Page.RenderTo(B.Canvas);
            Check(Page.ContentHeight>100,'Layout survives resizing');
          end;
          Page.Width := 700;
          if ExtractFileName(Files[I])='index.html' then
          begin
            GIFStream := TFileStream.Create(ExtractFilePath(Files[I])+'shots/tool-push.gif',fmOpenRead);
            try
              GIF := TInkGIF.Create(GIFStream);
              try
                Check(GIF.FrameCount=90,'Decode all animation frames');
                if ParamCount>1 then GIF.Bitmap.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(2))+'gif-0.bmp');
                Sleep(2000);
                Check(GIF.Advance,'Animation advances');
                if ParamCount>1 then GIF.Bitmap.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(2))+'gif-1.bmp');
              finally GIF.Free end;
            finally GIFStream.Free end;
          end;
          if (ParamCount>1) and ((ExtractFileName(Files[I])='commands.html') or
            (ExtractFileName(Files[I])='index.html') or (ExtractFileName(Files[I])='line.html') or (ExtractFileName(Files[I])='keys.html')) then
          begin
            Page.ScrollTo(0);
            if ExtractFileName(Files[I])='keys.html' then Page.ScrollTo(300);
            B.SetSize(Page.Width,Page.Height); Page.RenderTo(B.Canvas);
            B.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(2))+ExtractFileName(Files[I])+'.bmp');
          end;
        end;
        Check(Images=Wanted,Format('Every image decodes (%d of %d)',[Images,Wanted]));
        WriteLn('Rendered ',Files.Count,' help pages and ',Images,' images.');
        Page.Back; Page.Forward;
      finally Files.Free end;
    end;
    WriteLn('All renderer and Markdown tests passed.');
  finally F.Free; B.Free end;
end.
