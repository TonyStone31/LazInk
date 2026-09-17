program RenderTests;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types,
  InkHtml, InkMarkdown, InkLabel, InkMemo, InkListBox, InkPage, InkCSS, InkGIF;
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

var Probe: TPageProbe; Tall: string; J: Integer;

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
