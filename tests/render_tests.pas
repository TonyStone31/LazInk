program RenderTests;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types, LCLType, LCLIntf,
  {$IFDEF LCLGTK3}LazGLib2, LazGObject2, LazGdk3, LazGtk3, gtk3widgets,{$ENDIF}
  InkScrollBar, InkDraw, InkMarkdown, InkLabel, InkMemo, InkListBox, InkPage, InkCSS, InkCode, InkGIF,
  InkWebP, WebP_Checks, Layout_Cache_Checks,
  LResources, LazInkReg,
  InkTouch, InkCopyMenu, InkEdit, Menus, Clipbrd, URIParser, Math;
type
  TTestExceptions = class
    procedure Handle(Sender: TObject; E: Exception);
  end;
var TestExceptions: TTestExceptions;

procedure TTestExceptions.Handle(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr,E.ClassName,': ',E.Message);
  DumpExceptionBackTrace(StdErr);
  Halt(1);
end;

var B: TBitmap; O: THTMLOptions; Wide, Narrow: TSize; Hit: THTMLHitInfo;
  S: string; X,Y, Found: Integer; F: TForm; M: TInkMemo; L: TInkLabel;
  List: TInkListBox; Page: TInkPage; CSS: TInkStyleSheet;
  TextOutput: TStringList;
  Files: TStringList; I, Images, Pass: Integer; GIF: TInkGIF; GIFStream: TFileStream;
  Source: TStringList; Tags: string; K, Wanted: Integer;
{ how many images a GIF holds, by walking its blocks - independent of the
  decoder being tested }
function GIFFrames(AStream: TStream): Integer;
var Head: array[0..12] of Byte; B, Size: Byte; Packed_: Byte;
  procedure SkipSubBlocks;
  begin
    repeat
      AStream.ReadBuffer(Size, 1);
      AStream.Seek(Size, soCurrent);
    until Size = 0;
  end;
begin
  Result := 0;
  AStream.Position := 0;
  AStream.ReadBuffer(Head, 13);
  if (Head[10] and $80) <> 0 then AStream.Seek(3 * (1 shl ((Head[10] and 7) + 1)), soCurrent);
  while AStream.Position < AStream.Size do
  begin
    AStream.ReadBuffer(B, 1);
    case B of
      $21: begin AStream.Seek(1, soCurrent); SkipSubBlocks end;
      $2C:
        begin
          Inc(Result);
          AStream.Seek(8, soCurrent);
          AStream.ReadBuffer(Packed_, 1);
          if (Packed_ and $80) <> 0 then AStream.Seek(3 * (1 shl ((Packed_ and 7) + 1)), soCurrent);
          AStream.Seek(1, soCurrent);
          SkipSubBlocks;
        end;
    else
      Break;
    end;
  end;
  AStream.Position := 0;
end;

procedure Check(OK: Boolean; const MessageText: string);
begin
  if not OK then raise Exception.Create(MessageText);
end;

type
  { the mouse handlers are protected; a test reaches them the way a
    descendant would }
  TPageProbe = class(TInkPage)
  public
    Clicked: string;
    Changes, Navigations: Integer;
    Activated: TInkLinkInfo;
    Activations: Integer;
    HandleLinks: Boolean;
    procedure LinkActivated(Sender: TObject; const Link: TInkLinkInfo; var Handled: Boolean);
    procedure Navigated(Sender: TObject);
    procedure Button(AButton: TMouseButton; X, Y: Integer);
    procedure Press(X, Y: Integer; Shift: TShiftState = []);
    procedure Key(K: Word; Shift: TShiftState);
    procedure SelChanged(Sender: TObject);
    procedure AddToMenu(Sender: TObject; Menu: TPopupMenu; X, Y: Integer);
    procedure Tick;
    procedure LoadURLForTest(const URL: string);
    procedure MoveTo(X, Y: Integer);
    procedure Let(X, Y: Integer);
    procedure LinkHit(Sender: TObject; const URL: string);
    function LinkAt(X, Y: Integer): string;
    procedure Highlight(Sender: TObject; const ACode, ALanguage: string; var AMarkup: string);
    { a finger, at a time of the test's choosing }
    procedure Finger(Phase: TInkTouchPhase; X, Y: Integer; Time: QWord);
    procedure Coast(Milliseconds: Integer);
  end;

procedure TPageProbe.Press(X, Y: Integer; Shift: TShiftState);
begin
  MouseDown(mbLeft, [ssLeft] + Shift, X, Y);
end;

procedure TPageProbe.Key(K: Word; Shift: TShiftState);
begin
  KeyDown(K, Shift);
end;

procedure TPageProbe.LinkActivated(Sender: TObject; const Link: TInkLinkInfo; var Handled: Boolean);
begin
  Activated := Link;
  Inc(Activations);
  Handled := HandleLinks;
end;

procedure TPageProbe.Navigated(Sender: TObject);
begin
  Inc(Navigations);
end;

procedure TPageProbe.Button(AButton: TMouseButton; X, Y: Integer);
begin
  MouseDown(AButton, [], X, Y);
  MouseUp(AButton, [], X, Y);
end;

procedure TPageProbe.SelChanged(Sender: TObject);
begin
  Inc(Changes);
end;

procedure TPageProbe.AddToMenu(Sender: TObject; Menu: TPopupMenu; X, Y: Integer);
var Item: TMenuItem;
begin
  Item := TMenuItem.Create(Menu);
  Item.Caption := 'Mine';
  Menu.Items.Add(Item);
end;

procedure TPageProbe.LoadURLForTest(const URL: string);
begin
  LoadFromURL(URL);
end;

procedure TPageProbe.Tick;
begin
  AutoScrollTimer(Self);
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

function TPageProbe.LinkAt(X, Y: Integer): string;
begin
  Result := HitLink(X, Y);
end;

procedure TPageProbe.Highlight(Sender: TObject; const ACode, ALanguage: string;
  var AMarkup: string);
begin
  { a host with its own highlighter - SynEdit's, one day - answers like this }
  Clicked := ALanguage;
  AMarkup := '<font color="#123456">' + HTMLEscape(ACode) + '</font>';
end;

procedure TPageProbe.Finger(Phase: TInkTouchPhase; X, Y: Integer; Time: QWord);
begin
  TouchAt(Phase, X, Y, Time);
end;

procedure TPageProbe.Coast(Milliseconds: Integer);
begin
  FlickStep(Milliseconds);
end;

{$IFDEF LCLGTK3}
{ A touch event made the way GDK makes one, sent to the control's window the
  way GTK sends it - so the hook in InkTouch is what gets tested. }
{ a mouse button, the same way }
procedure SendButton(Control: TWinControl; Kind: TGdkEventType; AButton, X, Y: Integer);
var
  Event: PGdkEvent;
  Widget: PGtkWidget;
  P: TPoint;
begin
  Widget := TGtk3Widget(Control.Handle).GetContainerWidget;
  Event := gdk_event_new(Kind);
  P := Control.ClientToScreen(Point(X, Y));
  Event^.button.window := PGdkWindow(g_object_ref(gtk_widget_get_window(Widget)));
  Event^.button.x := X;
  Event^.button.y := Y;
  Event^.button.x_root := P.X;
  Event^.button.y_root := P.Y;
  Event^.button.button := AButton;
  Event^.button.time := GetTickCount64 and $FFFFFFFF;
  gtk_widget_event(Widget, Event);
  gdk_event_free(Event);
end;

procedure SendTouch(Control: TWinControl; Kind: TGdkEventType; Sequence: Pointer; X, Y: Integer);
var
  Event: PGdkEvent;
  Widget: PGtkWidget;
  P: TPoint;
begin
  Widget := TGtk3Widget(Control.Handle).GetContainerWidget;
  Event := gdk_event_new(Kind);
  P := Control.ClientToScreen(Point(X, Y));
  Event^.touch.window := PGdkWindow(g_object_ref(gtk_widget_get_window(Widget)));
  Event^.touch.x := X;
  Event^.touch.y := Y;
  Event^.touch.x_root := P.X;
  Event^.touch.y_root := P.Y;
  Event^.touch.sequence := Sequence;
  Event^.touch.time := GetTickCount64 and $FFFFFFFF;
  gtk_widget_event(Widget, Event);
  gdk_event_free(Event);
end;
{$ENDIF}

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

function Pos2(ABlock, AOffset: Integer): TInkPagePosition;
begin
  Result.Block := ABlock;
  Result.Offset := AOffset;
end;

type
  { protected members, reached as a descendant would }
  TMemoAccess = class(TInkMemo);
  TMemoProbe = class(TInkMemo)
  public
    Clicked: string;
    procedure LinkHit(Sender: TObject; LineIndex: Integer; const LinkName: string);
  end;

procedure TMemoProbe.LinkHit(Sender: TObject; LineIndex: Integer; const LinkName: string);
begin
  Clicked := IntToStr(LineIndex) + ':' + LinkName;
end;

type
  TListAccess = class(TInkListBox);
  TLabelAccess = class(TInkLabel);
  TInkEditAccess = class(TInkEdit);

{ --- the list box's in-place editor, by every route --- }
procedure ListEditChecks(AList: TInkListBox);
var R: TRect; K: Word; T: QWord;

  procedure Click(Shift: TShiftState = []);
  begin
    TListAccess(AList).MouseDown(mbLeft, Shift, R.Left + 5, R.Top + 2);
    TListAccess(AList).MouseUp(mbLeft, [], R.Left + 5, R.Top + 2);
  end;

begin
  R := AList.ItemRect(1);
  AList.EditMode := emNone;
  AList.ItemIndex := 1;
  Click;
  Check(not AList.Editing, 'emNone: a click does not edit');
  K := VK_F2; TListAccess(AList).KeyDown(K, []);
  Check(not AList.Editing, 'emNone: nor does F2');
  AList.EditItem(1);
  Check(AList.Editing, 'EditItem edits whatever the mode');
  AList.CancelEdit;
  Check(not AList.Editing, 'CancelEdit closes it');

  AList.EditMode := emOnDblClick;
  Sleep(GetDoubleClickTime + 50);
  Click;
  Check(not AList.Editing, 'emOnDblClick: one click does not edit');
  TListAccess(AList).DblClick;
  Check(AList.Editing, 'emOnDblClick: a double click edits');
  AList.CancelEdit;
  K := VK_F2; TListAccess(AList).KeyDown(K, []);
  Check(AList.Editing, 'F2 edits the current item');
  AList.CancelEdit;

  AList.EditMode := emOnTripleClick;
  Sleep(GetDoubleClickTime + 50);
  Click; Sleep(80); Click;
  Check(not AList.Editing, 'emOnTripleClick: two clicks do not edit');
  Sleep(80); Click;
  Check(AList.Editing, 'emOnTripleClick: the third does, unmarked as GTK3 sends it');
  AList.CancelEdit;

  AList.EditMode := emOnClickSelected;
  Sleep(GetDoubleClickTime + 50);
  AList.ItemIndex := 1;
  Click;
  Check(not AList.Editing, 'emOnClickSelected: not at once');
  T := GetTickCount64;
  while not AList.Editing and (GetTickCount64 - T < 3000) do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
  Check(AList.Editing, 'emOnClickSelected: a moment after a click on the selected item');
  AList.CancelEdit;
  Sleep(GetDoubleClickTime + 50);
  Click; Sleep(60); Click([ssDouble]);
  T := GetTickCount64;
  while GetTickCount64 - T < GetDoubleClickTime + 300 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
  Check(not AList.Editing, 'emOnClickSelected: a double click is not a rename');
  { a held button drags the highlight; emOnSelect edits on the release }
  AList.EditMode := emOnSelect;
  AList.ItemIndex := 0;
  Sleep(GetDoubleClickTime + 50);
  R := AList.ItemRect(0);
  TListAccess(AList).MouseDown(mbLeft, [ssLeft], R.Left + 5, R.Top + 2);
  R := AList.ItemRect(2);
  TListAccess(AList).MouseMove([ssLeft], R.Left + 5, R.Top + 2);
  Check(AList.ItemIndex = 2, Format('the highlight follows a held mouse (%d)', [AList.ItemIndex]));
  Check(not AList.Editing, 'emOnSelect waits while the button is down');
  TListAccess(AList).MouseUp(mbLeft, [], R.Left + 5, R.Top + 2);
  Check(AList.Editing, 'and edits on the release');
  AList.CancelEdit;
  TListAccess(AList).MouseMove([], R.Left + 5, AList.ItemRect(1).Top + 2);
  Check(AList.ItemIndex = 2, 'without the button the highlight stays');
  R := AList.ItemRect(0);
  AList.ItemIndex := 2;
  Sleep(GetDoubleClickTime + 50);
  TListAccess(AList).MouseDown(mbLeft, [ssLeft], R.Left + 5, R.Top + 2);
  Check(not AList.Editing, 'emOnSelect: the first item is not edited under the press');
  TListAccess(AList).MouseUp(mbLeft, [], R.Left + 5, R.Top + 2);
  Check(AList.Editing and (AList.ItemIndex = 0), 'the first item can be edited');
  AList.CancelEdit;
  AList.EditMode := emNone;
end;

{ --- copying from the memo, the list box and the label --- }
procedure ListCopyChecks(AMemo: TMemoProbe; AList: TInkListBox; ALabel: TInkLabel);
const
  E = LineEnding;
var
  Menu: TPopupMenu;
  R: TRect;
  P: TPoint;
  Handled: Boolean;
  K: Word;
  Y0: Integer;
begin
  AMemo.TextFormat := itfHTML;
  AMemo.SetBounds(0, 300, 300, 150);
  AMemo.WordWrap := True;
  AMemo.Lines.Text := '<b>first</b> line' + E + 'second <i>line</i>' + E + 'third';
  Application.ProcessMessages;
  Check(AMemo.Count = 3, 'memo: three lines');
  Check(AMemo.BlockText(1) = 'second line', 'memo: a line''s words: ' + AMemo.BlockText(1));
  AMemo.Select(Pos2(1, 0), Pos2(1, MaxInt));
  Check(AMemo.SelectedText = 'second line', 'memo: a selected line: ' + AMemo.SelectedText);
  Clipboard.AsText := '';
  K := VK_C; TMemoAccess(TInkMemo(AMemo)).KeyDown(K, [ssCtrl]);
  Check(Clipboard.AsText = 'second line', 'memo: Ctrl+C copies it');
  AMemo.Select(Pos2(0, 6), Pos2(1, 6));
  Check(AMemo.SelectedText = 'line' + E + 'second', 'memo: a selection across lines: ' + AMemo.SelectedText);
  K := VK_A; TMemoAccess(TInkMemo(AMemo)).KeyDown(K, [ssCtrl]);
  K := VK_C; TMemoAccess(TInkMemo(AMemo)).KeyDown(K, [ssCtrl]);
  Check(Clipboard.AsText = 'first line' + E + 'second line' + E + 'third',
    'memo: Ctrl+A then Ctrl+C copies everything: ' + Clipboard.AsText);
  P := AMemo.PositionPoint(Pos2(2, 1));
  Menu := AMemo.BuildCopyMenu(P.X, P.Y + 2);
  Check(Menu.Items[0].Caption = SInkCopy, 'memo menu: Copy');
  Check(Menu.Items[1].Caption = SInkCopyLine, 'memo menu: Copy this line');
  Menu.Items[1].Click;
  Check(Clipboard.AsText = 'third', 'memo menu copies the line under the pointer: ' + Clipboard.AsText);
  Menu.Items[2].Click;
  Check(Clipboard.AsText = 'first line' + E + 'second line' + E + 'third', 'memo menu: Copy all');
  AMemo.CopyMenu := False;
  Handled := False;
  TMemoAccess(TInkMemo(AMemo)).DoContextPopup(Point(P.X, P.Y + 2), Handled);
  Check(not Handled, 'memo: CopyMenu off shows no menu');
  AMemo.CopyMenu := True;

  { Append adds a line, and follows the end only when the view was there }
  for K := 1 to 29 do AMemo.Append('line ' + IntToStr(K));
  Check(AMemo.Count = 32, 'memo: Append');
  Check(AMemo.ScrollY > 0, 'memo: while it was all in view, the end was followed');
  AMemo.ScrollTo(0);
  AMemo.Append('line 30');
  Check(AMemo.ScrollY = 0, 'memo: a view scrolled back to the top stays there');
  AMemo.ScrollTo(MaxInt);
  Y0 := AMemo.ScrollY;
  AMemo.Append('<b>newest</b>');
  Check(AMemo.ScrollY > Y0, 'memo: a view at the end follows new lines');
  Check(AMemo.BlockText(33) = 'newest', 'memo: the appended line is drawn');
  Check(AMemo.Block(33).Bounds.Top > AMemo.Block(32).Bounds.Top, 'memo: below the one before');

  { links: the line and the href, as written }
  AMemo.Clicked := '';
  AMemo.OnLinkClick := @AMemo.LinkHit;
  AMemo.MouseDrag := imdSelect;
  AMemo.Lines.Text := 'a <a href="x&amp;y">link</a> here';
  AMemo.ScrollTo(0);
  P := AMemo.PositionPoint(Pos2(0, 3));
  TMemoAccess(TInkMemo(AMemo)).MouseDown(mbLeft, [ssLeft], P.X, P.Y + 3);
  TMemoAccess(TInkMemo(AMemo)).MouseUp(mbLeft, [], P.X, P.Y + 3);
  Check(AMemo.Clicked = '0:x&y', 'memo: OnLinkClick has the line and href: ' + AMemo.Clicked);
  AMemo.OnLinkClick := nil;
  AMemo.WordWrap := False;

  AList.TextFormat := itfHTML;
  AList.EditMode := emNone;
  AList.SetBounds(300, 300, 200, 150);
  AList.MultiSelect := True;
  AList.Items.Text := 'alpha' + E + '<b>beta</b>' + E + 'gamma';
  Application.ProcessMessages;
  AList.Selected[0] := True;
  AList.Selected[2] := True;
  Check(AList.SelectedText = 'alpha' + E + 'gamma', 'list: every selected item: ' + AList.SelectedText);
  Check(AList.PlainText = 'alpha' + E + 'beta' + E + 'gamma' + E, 'list: PlainText');
  R := AList.ItemRect(1);
  Menu := AList.BuildCopyMenu(R.Left + 5, R.Top + 2);
  Check(Menu.Items[1].Caption = SInkCopyItem, 'list menu: Copy this item');
  Menu.Items[1].Click;
  Check(Clipboard.AsText = 'beta', 'list menu copies the item under the pointer');
  Menu.Items[Menu.Items.Count - 1].Click;
  Check(AList.Selected[1] and (AList.SelectedText = 'alpha' + E + 'beta' + E + 'gamma'),
    'list menu: Select all');
  AList.PopupMenu := Menu;
  Handled := False;
  TListAccess(AList).DoContextPopup(Point(R.Left + 5, R.Top + 2), Handled);
  Check(not Handled, 'list: a PopupMenu of the program''s own wins');
  AList.PopupMenu := nil;
  AList.MultiSelect := False;
  ListEditChecks(AList);

  ALabel.TextFormat := itfMarkdown;
  ALabel.Caption := '**hello** [there](http://x.org)';
  Check(ALabel.PlainText = 'hello there', 'label: a Markdown caption''s plain text: ' + ALabel.PlainText);
  Menu := ALabel.BuildCopyMenu(0, 0);
  Check((Menu.Items.Count = 1) and (Menu.Items[0].Caption = SInkCopyAll), 'label menu: Copy all');
  Menu.Items[0].Click;
  Check(Clipboard.AsText = 'hello there', 'label menu copies the caption''s words');
  ALabel.CopyMenu := False;
  Handled := False;
  TLabelAccess(ALabel).DoContextPopup(Point(0, 0), Handled);
  Check(not Handled, 'label: CopyMenu off shows no menu');
  ALabel.CopyMenu := True;
end;


{ --- selecting text with the mouse, and copying it --- }
procedure SelectionChecks;
var
  K, B0, Wrong: Integer;
  P, Q: TPoint;
  At: TInkPagePosition;
  Text, Words: string;
  Shot: TBitmap;
  Menu: TPopupMenu;
  Tall2: string;
begin
  Tall2 := '<html><body>';
  for K := 1 to 60 do Tall2 := Tall2 + '<p>Paragraph ' + IntToStr(K) + '</p>';
  Tall2 := Tall2 + '</body></html>';
  Probe.MouseDrag := imdSelect;
  Probe.OnSelectionChange := @Probe.SelChanged;
  Probe.LoadHTML('<html><body><p>Hello brave new world, and a second sentence that is long enough ' +
    'to wrap onto another line of this narrow page.</p>' +
    '<ul><li>item one</li></ul>' +
    '<pre>code  line' + #10 + '  indented</pre>' +
    '<table><tr><td>a1</td><td>b1</td></tr><tr><td>a2</td><td>b2</td></tr></table>' +
    '<p>Last <a href="linked">link</a> here.</p></body></html>');
  Probe.ScrollTo(0);
  Check(not Probe.HasSelection, 'a new page has nothing selected');
  Words := Probe.BlockText(0);
  Check(Pos('Hello brave new world, and a second sentence', Words) = 1, 'block words: ' + Words);
  Check(Pos('another line of this narrow page.', Words) > 0, 'a wrapped line''s words join with a space: ' + Words);
  Check(Probe.BlockText(2) = 'code  line' + #10 + '  indented', 'code keeps its lines: ' + Probe.BlockText(2));
  Check(Pos('a1'#9'b1', Probe.BlockText(3)) > 0, 'cells are apart by tabs: ' + Probe.BlockText(3));

  { every place in the first block maps to a point and back }
  Wrong := 0;
  for K := 0 to Length(Words) do
  begin
    { only at character starts }
    if (K < Length(Words)) and ((Ord(Words[K + 1]) and $C0) = $80) then Continue;
    P := Probe.PositionPoint(Pos2(0, K));
    At := Probe.PositionAt(P.X, P.Y + 2);
    { the place at a wrap is both the end of one line and the start of the next }
    if (At.Block <> 0) or ((At.Offset <> K) and not ((K > 0) and (Words[K] = ' ') and (At.Offset = K - 1))) then
    begin
      Inc(Wrong);
      if Wrong < 30 then WriteLn('  k=', K, ' at=', At.Block, ':', At.Offset, ' pt=', P.X, ',', P.Y);
    end;
  end;
  Check(Wrong = 0, Format('PositionAt(PositionPoint(k)) = k (%d wrong)', [Wrong]));
  P := Probe.PositionPoint(Pos2(0, 6));
  Q := Probe.PositionPoint(Pos2(0, 11));
  Check((Q.X > P.X) and (Q.Y = P.Y), 'later on a line is further right');
  P := Probe.PositionPoint(Pos2(0, Length(Words)));
  Check(P.Y > Probe.PositionPoint(Pos2(0, 0)).Y, 'the end of a wrapped block is lower down');
  At := Probe.PositionAt(-50, 0);
  Check((At.Block = 0) and (At.Offset = 0), 'left of and above everything is the start');
  At := Probe.PositionAt(Probe.ClientWidth + 50, Probe.ContentHeight + 50);
  Check(At.Block = Probe.BlockCount - 1, 'below everything is the last block');

  { press, drag, release: "brave new" }
  Probe.Changes := 0;
  P := Probe.PositionPoint(Pos2(0, 6));
  Q := Probe.PositionPoint(Pos2(0, 15));
  Probe.Press(P.X, P.Y + 3);
  Probe.MoveTo((P.X + Q.X) div 2, P.Y + 3);
  Probe.MoveTo(Q.X, Q.Y + 3);
  Probe.Let(Q.X, Q.Y + 3);
  Check(Probe.SelectedText = 'brave new', 'a mouse drag selects: "' + Probe.SelectedText + '"');
  Check(Probe.Changes > 0, 'OnSelectionChange');
  Check(Probe.ScrollY = 0, 'and does not scroll');
  Check(Pos('<p>brave new</p>', Probe.SelectedHTML) > 0, 'selected HTML: ' + Probe.SelectedHTML);

  { the selection is painted }
  Shot := TBitmap.Create;
  try
    Shot.SetSize(Probe.ClientWidth, Probe.ClientHeight);
    Probe.RenderTo(Shot.Canvas);
    Check(ColorToRGB(Shot.Canvas.Pixels[P.X + 1, P.Y + 1]) = ColorToRGB(Probe.SelectionBackground),
      'selected text has the selection color behind it');
    Check(ColorToRGB(Shot.Canvas.Pixels[P.X - 3, P.Y + 1]) <> ColorToRGB(Probe.SelectionBackground),
      'and the text before it does not');
    Probe.SelectionColor := RGBToColor(1, 2, 3);
    Probe.RenderTo(Shot.Canvas);
    Check(ColorToRGB(Shot.Canvas.Pixels[P.X + 1, P.Y + 1]) = RGBToColor(1, 2, 3), 'SelectionColor');
    Probe.SelectionColor := clDefault;
  finally Shot.Free end;

  { Ctrl+C }
  Clipboard.AsText := 'before';
  Probe.Key(VK_C, [ssCtrl]);
  Check(Clipboard.AsText = 'brave new', 'Ctrl+C copies the selection: "' + Clipboard.AsText + '"');

  { a click without moving clears it, and a click on a link still follows it }
  Probe.Press(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Check(not Probe.HasSelection, 'a click clears the selection');
  Probe.Clicked := '';
  B0 := Probe.BlockCount - 1;
  P := Probe.PositionPoint(Pos2(B0, 6));
  Probe.Press(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Check(Probe.Clicked = 'linked', 'a click on a link follows it: ' + Probe.Clicked);

  { double click takes a word, triple click the block, Shift extends.
    Gestures in the same place are kept apart by more than a double-click
    time, or the page counts them as one more click. }
  Sleep(GetDoubleClickTime + 50);
  P := Probe.PositionPoint(Pos2(0, 8));
  Probe.Press(P.X, P.Y + 3, [ssDouble]); Probe.Let(P.X, P.Y + 3);
  Check(Probe.SelectedText = 'brave', 'a double click selects a word: "' + Probe.SelectedText + '"');
  Q := Probe.PositionPoint(Pos2(0, 18));
  Sleep(GetDoubleClickTime + 50);
  Probe.Press(P.X, P.Y + 3, [ssDouble]); Probe.MoveTo(Q.X, Q.Y + 3); Probe.Let(Q.X, Q.Y + 3);
  Check(Probe.SelectedText = 'brave new world', 'dragging after a double click goes by words: "' + Probe.SelectedText + '"');
  Sleep(GetDoubleClickTime + 50);
  Probe.Press(P.X, P.Y + 3, [ssTriple]); Probe.Let(P.X, P.Y + 3);
  Check(Probe.SelectedText = TrimRight(Words), 'a triple click selects the paragraph');
  { as GTK3 delivers one: press, press, press-marked-double, press, press -
    the third click comes unmarked }
  Sleep(GetDoubleClickTime + 50);
  Probe.Press(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Sleep(80);
  Probe.Press(P.X, P.Y + 3); Probe.Press(P.X, P.Y + 3, [ssDouble]); Probe.Let(P.X, P.Y + 3);
  Check(Probe.SelectedText = 'brave', 'GTK3''s double click is a word, not three clicks');
  Sleep(80);
  Probe.Press(P.X, P.Y + 3); Probe.Press(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Check(Probe.SelectedText = TrimRight(Words), 'and its unmarked third click is a triple click');
  Sleep(GetDoubleClickTime + 50);
  Probe.Press(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Probe.Press(Q.X, Q.Y + 3, [ssShift]); Probe.Let(Q.X, Q.Y + 3);
  Check(not Probe.HasSelection, 'Shift+click with nothing selected just places');
  Probe.Select(Pos2(0, 6), Pos2(0, 11));
  Probe.Press(Q.X, Q.Y + 3, [ssShift]); Probe.Let(Q.X, Q.Y + 3);
  Check(Probe.SelectedText = 'brave new wo', 'Shift+click extends, to the character: "' + Probe.SelectedText + '"');

  { across blocks, in document order, with the list's marker }
  P := Probe.PositionPoint(Pos2(0, Length(Words) - 5));
  Q := Probe.PositionPoint(Pos2(2, 4));
  Probe.Press(Q.X, Q.Y + 3); Probe.MoveTo(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Text := Probe.SelectedText;
  Check(Text = 'page.' + LineEnding + '• item one' + LineEnding + 'code',
    'a selection across blocks, dragged backwards: "' + Text + '"');

  { Ctrl+A }
  Probe.Key(VK_A, [ssCtrl]);
  Text := Probe.SelectedText;
  Check(Pos('Hello brave', Text) = 1, 'Ctrl+A selects from the start');
  Check(Pos('a1'#9'b1' + LineEnding + 'a2'#9'b2', Text) > 0, 'tables copy as tab-separated rows: ' + Text);
  Check(Pos('code  line' + #10 + '  indented', Text) > 0, 'code copies as written');
  Check(Copy(Text, Length(Text) - 9, 10) = 'link here.', 'to the end');

  { it survives a new layout, and a new page clears it }
  Probe.Select(Pos2(0, 6), Pos2(0, 15));
  Probe.Width := 600; Probe.ScrollTo(0);
  Check(Probe.SelectedText = 'brave new', 'the selection survives a resize');
  Probe.Width := 400; Probe.ScrollTo(0);

  { the copy menu }
  P := Probe.PositionPoint(Pos2(1, 2));
  Menu := Probe.BuildCopyMenu(P.X, P.Y + 3);
  Check(Menu.Items.Count >= 4, Format('copy menu items (%d)', [Menu.Items.Count]));
  Check(Menu.Items[0].Caption = SInkCopy, 'Copy first');
  Check(Menu.Items[0].Enabled, 'enabled with a selection');
  Clipboard.AsText := '';
  Menu.Items[1].Click;
  Check(Clipboard.AsText = '• item one', 'Copy this paragraph copies the block under the pointer: "' + Clipboard.AsText + '"');
  Menu.Items[2].Click;
  Check(Pos('Hello brave', Clipboard.AsText) = 1, 'Copy all');
  Check(Clipboard.AsText = TrimRight(Probe.PlainText), 'Copy all is the page''s text');
  Probe.ClearSelection;
  Menu := Probe.BuildCopyMenu(P.X, P.Y + 3);
  Check(not Menu.Items[0].Enabled, 'Copy is grayed with nothing selected');
  Menu.Items[Menu.Items.Count - 1].Click;
  Check(Probe.HasSelection, 'Select all');
  B0 := Probe.BlockCount - 1;
  P := Probe.PositionPoint(Pos2(B0, 6));
  Menu := Probe.BuildCopyMenu(P.X, P.Y + 3);
  Check(Menu.Items[1].Caption = SInkCopyLink, 'Copy link address, over a link');
  Menu.Items[1].Click;
  Check(Clipboard.AsText = 'linked', 'copies the link: ' + Clipboard.AsText);
  Probe.OnCopyMenu := @Probe.AddToMenu;
  Menu := Probe.BuildCopyMenu(P.X, P.Y + 3);
  Check(Menu.Items[Menu.Items.Count - 1].Caption = 'Mine', 'OnCopyMenu adds items');
  Menu := Probe.BuildCopyMenu(P.X, P.Y + 3);
  Check(Menu.Items[Menu.Items.Count - 1].Caption = 'Mine', 'once, however often it opens');
  Check(Menu.Items[Menu.Items.Count - 2].Caption <> 'Mine', 'not twice');
  Probe.OnCopyMenu := nil;

  { a finger scrolls, even when the mouse selects }
  Probe.ClearSelection;
  Probe.LoadHTML(Tall2);
  Probe.ScrollTo(0);
  Probe.FlickScroll := False;
  Probe.Finger(itpBegin, 100, 150, 20000);
  Probe.Finger(itpMove, 100, 50, 20300);
  Probe.Finger(itpEnd, 100, 50, 20600);
  Check(Probe.ScrollY = 100, 'a finger scrolls with MouseDrag = imdSelect');
  Check(not Probe.HasSelection, 'and selects nothing');
  Probe.FlickScroll := True;

  { dragging below the page scrolls it and selects on }
  Sleep(550);
  Probe.ScrollTo(0);
  Probe.Press(20, 30);
  Probe.MoveTo(20, Probe.ClientHeight + 40);
  for K := 1 to 10 do Probe.Tick;
  Check(Probe.ScrollY > 0, 'a drag below the page scrolls it');
  Probe.Let(20, Probe.ClientHeight + 40);
  Check(Probe.SelectionEnd.Block > 1, 'and the selection follows');

  { an ampersand in a link survives the click }
  Sleep(GetDoubleClickTime + 50);
  Probe.LoadHTML('<p><a href="p?a=1&amp;b=2">go there</a></p>');
  Probe.ScrollTo(0);
  P := Probe.PositionPoint(Pos2(0, 2));
  Probe.Clicked := '';
  Probe.Press(P.X, P.Y + 3); Probe.Let(P.X, P.Y + 3);
  Check(Probe.Clicked = 'p?a=1&b=2', 'a link''s & is kept: ' + Probe.Clicked);

  Probe.OnSelectionChange := nil;
  Probe.MouseDrag := imdScroll;
end;

{ --- Back and Forward --- }
procedure NavigationChecks;
var Dir, A, B2: string; SL: TStringList; K: Word;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'lazink-nav-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  A := Dir + PathDelim + 'a.html'; B2 := Dir + PathDelim + 'b.md';
  SL := TStringList.Create;
  try
    SL.Text := '<html><head><title>Page A</title></head><body><p><a href="b.md">to b</a></p></body></html>';
    SL.SaveToFile(A);
    SL.Text := '# Page B' + LineEnding + LineEnding + 'text';
    SL.SaveToFile(B2);
  finally SL.Free end;
  Probe.Navigations := 0;
  Probe.OnNavigate := @Probe.Navigated;
  Probe.OnLinkClick := nil;
  Probe.ClearHistory;
  Check(not Probe.CanGoBack, 'ClearHistory');
  Probe.LoadFromFile(A);
  Probe.ClearHistory;
  Check(Probe.Navigations = 1, 'OnNavigate after a load');
  Check(not Probe.CanGoBack and not Probe.CanGoForward, 'one page: no Back or Forward');
  Probe.LoadFromFile(B2);
  Check(Probe.DocumentTitle = 'Page B', 'a .md page, by its name: ' + Probe.DocumentTitle);
  Check(Probe.CanGoBack and not Probe.CanGoForward, 'two pages: Back');
  Probe.Back;
  Check((Probe.DocumentTitle = 'Page A') and Probe.CanGoForward and not Probe.CanGoBack,
    'Back, and then Forward is possible');
  Check(Probe.TextFormat = itfHTML, 'the .html page is HTML again');
  Check(Probe.Navigations = 3, Format('OnNavigate after Back (%d)', [Probe.Navigations]));
  Probe.Button(mbExtra2, 10, 10);
  Check(Probe.DocumentTitle = 'Page B', 'the mouse''s forward button');
  Probe.Button(mbExtra1, 10, 10);
  Check(Probe.DocumentTitle = 'Page A', 'the mouse''s back button');
  K := VK_RIGHT; Probe.KeyDown(K, [ssAlt]);
  Check(Probe.DocumentTitle = 'Page B', 'Alt+Right');
  K := VK_LEFT; Probe.KeyDown(K, [ssAlt]);
  Check(Probe.DocumentTitle = 'Page A', 'Alt+Left');
  K := VK_BROWSER_FORWARD; Probe.KeyDown(K, []);
  Check(Probe.DocumentTitle = 'Page B', 'the Forward key');
  K := VK_BROWSER_BACK; Probe.KeyDown(K, []);
  Check(Probe.DocumentTitle = 'Page A', 'the Back key');
  {$IFDEF LCLGTK3}
  { GTK3's backend drops buttons 8 and 9; the hook brings them back }
  Application.ProcessMessages;
  SendButton(Probe, GDK_BUTTON_PRESS, 9, 10, 10);
  SendButton(Probe, GDK_BUTTON_RELEASE, 9, 10, 10);
  Check(Probe.DocumentTitle = 'Page B', 'button 9 through GTK3 goes forward');
  SendButton(Probe, GDK_BUTTON_PRESS, 8, 10, 10);
  SendButton(Probe, GDK_BUTTON_RELEASE, 8, 10, 10);
  Check(Probe.DocumentTitle = 'Page A', 'button 8 through GTK3 goes back');
  {$ENDIF}
  { a link followed from a page goes into the history too }
  Probe.LoadFromFile(A);
  Probe.LoadURLForTest('b.md');
  Check(Probe.DocumentTitle = 'Page B', 'a relative link');
  Probe.Back;
  Check(Probe.DocumentTitle = 'Page A', 'and back from it');
  Probe.OnNavigate := nil;
  Probe.OnLinkClick := @Probe.LinkHit;
  DeleteFile(A); DeleteFile(B2); RemoveDir(Dir);
end;

{ --- pictures you can click, and pictures sized to fit --- }
procedure PictureChecks;
var Base: string; B: TInkPageBlock; R: TRect; P: TPoint; W: Integer;

  procedure ClickAt(X, Y: Integer);
  begin
    Probe.Press(X, Y); Probe.Let(X, Y);
  end;

begin
  Base := FilenameToURI(ExpandFileName('images/page.html'));
  Probe.OnLinkActivate := @Probe.LinkActivated;
  Probe.OnLinkClick := @Probe.LinkHit;
  Probe.LoadHTML('<html><body><p>Before</p>' +
    '<a href="palette.png" target="_blank"><img src="palette.png" alt="the palette"></a>' +
    '<p>after <a href="t.html" target="side">text</a> and <a href="u.html">plain</a></p>' +
    '</body></html>', Base);
  Probe.ScrollTo(0);
  Check(Probe.BlockCount = 3, Format('a linked picture makes no empty blocks (%d)', [Probe.BlockCount]));
  B := Probe.Block(1);
  Check(B.Picture.Graphic <> nil, 'the picture loads');
  Check((B.LinkHref = 'palette.png') and (B.LinkTarget = '_blank'), 'and knows its link');

  Probe.HandleLinks := True;
  Probe.Activations := 0; Probe.Clicked := '';
  R := B.ImageRect; OffsetRect(R, 0, -Probe.ScrollY);
  ClickAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
  Check(Probe.Activations = 1, 'a click on a linked picture is a link click');
  Check(Probe.Activated.Target = '_blank', 'with its target: ' + Probe.Activated.Target);
  Check(Pos('images/palette.png', Probe.Activated.Image) > 0, 'and the picture: ' + Probe.Activated.Image);
  Check(Pos('images/palette.png', Probe.Activated.URL) > 0, 'resolved: ' + Probe.Activated.URL);
  Check(Probe.Activated.Href = 'palette.png', 'as written');
  Check(Probe.Clicked = '', 'Handled stops it there');
  ClickAt(R.Right + 20, (R.Top + R.Bottom) div 2);
  Check(Probe.Activations = 1, 'beside the picture is not the link');

  P := Probe.PositionPoint(Pos2(2, 7));
  ClickAt(P.X, P.Y + 3);
  Check((Probe.Activations = 2) and (Probe.Activated.Target = 'side') and (Probe.Activated.Image = ''),
    'a text link''s target: ' + Probe.Activated.Target);
  P := Probe.PositionPoint(Pos2(2, 17));
  ClickAt(P.X, P.Y + 3);
  Check((Probe.Activations = 3) and (Probe.Activated.Target = ''), 'no target: ' + Probe.Activated.Href);

  Probe.HandleLinks := False;
  ClickAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
  Check(Pos('palette.png', Probe.Clicked) > 0, 'not handled, OnLinkClick has it');
  Check(Probe.ClickedLink.Target = '_blank', 'and ClickedLink says what it was');

  { with nobody to take the click, a picture opens as a page of its own }
  Probe.OnLinkClick := nil;
  ClickAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
  Check(Probe.DocumentTitle = 'palette.png', 'the picture alone: ' + Probe.DocumentTitle);
  Check(Probe.ImageCount = 1, 'showing the picture');
  Check(Probe.CanGoBack, 'with a way back');
  Probe.Back;
  Check(Probe.BlockCount = 3, 'and back to a page that was given as text');
  Probe.Forward;
  Check(Probe.DocumentTitle = 'palette.png', 'and forward again');
  Probe.Back;
  Probe.OnLinkClick := @Probe.LinkHit;
  Probe.OnLinkActivate := nil;

  { how big a picture is drawn }
  Probe.LoadHTML('<img src="palette.png">', Base);
  Probe.ScrollTo(0);
  B := Probe.Block(0);
  W := B.Bounds.Right - B.Bounds.Left;
  Check(B.ImageRect.Right - B.ImageRect.Left = Min(W, B.Picture.Width), 'iifShrink: never larger');
  Probe.ImageFit := iifWidth;
  B := Probe.Block(0);
  W := B.Bounds.Right - B.Bounds.Left;
  Check(B.ImageRect.Right - B.ImageRect.Left = W, 'iifWidth: as wide as the column');
  Check(B.ImageRect.Bottom - B.ImageRect.Top =
    Round(B.Picture.Height * W / B.Picture.Width), 'keeping its shape');
  Probe.ImageFit := iifWindow;
  B := Probe.Block(0);
  R := B.ImageRect;
  Check(R.Bottom - R.Top <= Probe.ClientHeight, 'iifWindow: no taller than the window');
  Check(R.Right - R.Left <= Probe.ClientWidth - Probe.ScrollBar.Width, 'nor wider');
  Check((R.Right - R.Left >= B.Bounds.Right - B.Bounds.Left - 2) or
    (R.Bottom - R.Top >= Probe.ClientHeight - 60), 'and as big as fits');
  Probe.ImageFit := iifShrink;
end;

{ --- tables that look like a page --- }
procedure CardTableChecks;
const
  Style =
    '<style>body { background: #000000; color: #ffffff } ' +
    'table.cards { width: 100%; border-collapse: separate; border-spacing: 10px; ' +
    '  table-layout: fixed; margin: 4px -10px 10px } ' +
    'table.cards td { background: #102030; border: 1px solid #405060; ' +
    '  border-radius: 6px; padding: 8px 12px; vertical-align: top; width: 33% } ' +
    'table.cards td.empty { background: none; border: none } ' +
    'table.cards small { color: #00ff00 } ' +
    'table.cards a { text-decoration: none } ' +
    'table.lines td { border-bottom: 1px solid #ff0000; padding: 4px 8px 4px 0 } ' +
    'small { color: #0000ff }</style>';
var
  CSS: TInkStyleSheet;
  B, Plain: TInkPageBlock;
  R: TRect;
  Shot: TBitmap;
  Col, Gap, X0, K: Integer;
  C: TColor;
  Sides: string;
begin
  { the CSS reader }
  CSS := TInkStyleSheet.Create;
  try
    CSS.Add('nav a { color: #111111 } a { color: #222222 } div.x > p.y { color: #333333 } ' +
      '.pad { padding: 1px 2px 3px 4px; padding-left: 9px } .two { margin: 5px -6px } ' +
      '.b1 { border: 2px solid #abc } .b2 { border: none } .b3 { border-bottom: 1px dashed red } ' +
      '.c { color: rgb(1, 2, 3) }');
    Check(CSS.Value('a', '', 'color', '') = '#222222', 'a plain selector');
    Check(CSS.Value('a', '', 'color', '', 'body nav') = '#111111', 'a descendant selector wins inside nav');
    Check(CSS.Value('a', '', 'color', '', 'body div') = '#222222', 'and not outside it');
    Check(CSS.Value('p', 'y', 'color', '', 'div.x') = '#333333', 'a child selector with classes');
    Check(CSS.Value('p', 'y', 'color', '', 'div.z') = '', 'needs the ancestor''s class');
    R := CSS.Box('div', 'pad', 'padding', Rect(0, 0, 0, 0));
    Check((R.Top = 1) and (R.Right = 2) and (R.Bottom = 3) and (R.Left = 9), 'padding shorthand, then longhand');
    R := CSS.Box('div', 'two', 'margin', Rect(0, 0, 0, 0));
    Check((R.Top = 5) and (R.Left = -6) and (R.Right = -6) and (R.Bottom = 5), 'two-value margin, negative');
    Check(CSS.Border('td', 'b1', C, Sides) and (ColorToRGB(C) = RGBToColor($AA, $BB, $CC)) and (Sides = 'trbl'),
      'border shorthand with #rgb');
    Check(CSS.Border('td', 'b2', C, Sides) and (Sides = ''), 'border: none');
    Check(CSS.Border('td', 'b3', C, Sides) and (Sides = 'b') and (ColorToRGB(C) = clRed), 'border-bottom alone');
    Check(not CSS.Border('td', 'none-at-all', C, Sides), 'no border said');
    Check(ColorToRGB(CSS.Color('p', 'c', 'color', clNone)) = RGBToColor(1, 2, 3), 'rgb() colors');
  finally CSS.Free end;

  Probe.SetBounds(0, 0, 500, 300);
  Probe.LoadHTML('<html><head>' + Style + '</head><body><table class="cards"><tr>' +
    '<td><a href="one.html"><b>One</b></a><br><small>first</small></td>' +
    '<td><a href="two.html"><b>Two</b></a><br><small>second card, longer than the first one</small></td>' +
    '<td class="empty"></td></tr></table>' +
    '<p>after <small>fine print</small></p>' +
    '<table class="lines"><tr><td>a</td><td>b</td></tr></table></body></html>');
  Probe.ScrollTo(0);
  B := Probe.Block(0);
  Check(B.Tag = 'table', 'the cards are a table');
  Check(Pos('width="100%"', B.Source) > 0, 'width: 100%');
  Check(Pos('layout="fixed"', B.Source) > 0, 'fixed layout');
  Check(Pos('cellspacing="10"', B.Source) > 0, 'border-spacing');
  Check(Pos('cellpadding="8 12 8 12"', B.Source) > 0, 'cell padding: ' + B.Source);
  Check(Pos('cellbg="#102030"', B.Source) > 0, 'cell background');
  Check(Pos('bordercolor="#405060"', B.Source) > 0, 'cell border color');
  Check(Pos('radius="6"', B.Source) > 0, 'rounded cells');
  Check(Pos('bgcolor="none"', B.Source) > 0, 'the empty cell has no background');
  Check(Pos('border="none"', B.Source) > 0, 'and no border');
  Check(Pos('color="#00ff00"', LowerCase(B.Source)) > 0, 'small in a card: its own color: ' + B.Source);
  Check(B.NoLinkUnderline, 'links in cards are not underlined');
  Check(B.MarginLeft = -10, 'the table reaches out by its margin');
  Plain := Probe.Block(1);
  Check((Pos('color="#0000ff"', LowerCase(Plain.Source)) > 0) and (Pos('size=', Plain.Source) > 0),
    'small elsewhere: smaller, and the plain rule''s color: ' + Plain.Source);
  Check(not Plain.NoLinkUnderline, 'links elsewhere keep their underline');
  Check(Pos('sides="b"', Probe.Block(2).Source) > 0, 'a bottom border alone');

  { painted: three equal columns with gaps, the third blank }
  Shot := TBitmap.Create;
  try
    Shot.SetSize(Probe.ClientWidth, Probe.ClientHeight);
    Probe.RenderTo(Shot.Canvas);
    R := B.Bounds; OffsetRect(R, 0, -Probe.ScrollY);
    Col := (R.Right - R.Left - 40) div 3;
    X0 := R.Left + 10;
    Gap := 0;
    for K := 0 to 2 do
      if ColorToRGB(Shot.Canvas.Pixels[X0 + K * (Col + 10) + Col div 2, R.Top + 12]) = RGBToColor($10, $20, $30) then
        Inc(Gap);
    Check(Gap = 2, Format('two cards painted, the empty one not (%d)', [Gap]));
    Check(ColorToRGB(Shot.Canvas.Pixels[X0 + Col + 5, R.Top + 20]) = clBlack, 'a gap between cards');
    Check(ColorToRGB(Shot.Canvas.Pixels[X0 + Col div 2, R.Top + 9]) = clBlack,
      'the first card starts one spacing down');
  finally Shot.Free end;
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- narrow windows: width queries, hidden things, wrapping --- }
procedure NarrowChecks;
const
  Doc =
    '<html><head><style>' +
    'body { background: #000000; color: #ffffff } ' +
    'p.note { color: #00ff00 } ' +
    '@media (max-width: 600px) { p.note { color: #ff0000 } ' +
    '  table.cards td { display: block; margin: 0 0 8px } table.cards td.empty { display: none } } ' +
    '@media print { p.note { color: #0000ff } } ' +
    'table.cards { width: 100%; border-spacing: 10px; table-layout: fixed } ' +
    'nav { display: flex; gap: 6px } ' +
    '.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px } ' +
    '.card { background: #102030; padding: 4px 6px; text-decoration: none } ' +
    '.gone { display: none } ' +
    '</style></head><body>' +
    '<nav><a href="a.html">Home</a><a href="b.html">Tools</a></nav>' +
    '<p class="note">note</p>' +
    '<table class="cards"><tr><td>one</td><td>two</td><td class="empty"></td></tr></table>' +
    '<div class="grid">' +
    '<a class="card" href="1.html"><b>One</b><br><small>first</small></a>' +
    '<a class="card" href="2.html"><b>Two</b></a>' +
    '<div class="card"><h3>Three</h3><p>third</p></div>' +
    '<a class="card gone" href="x.html">hidden card</a>' +
    '</div><p>after <span class="gone">secret</span>words</p></body></html>';
var
  CSS: TInkStyleSheet;
  Nav, Note, Cards, Grid: TInkPageBlock;
  K, Rows: Integer;

  function CountOf(const Needle, Hay: string): Integer;
  var Q: Integer;
  begin
    Result := 0;
    Q := Pos(Needle, Hay);
    while Q > 0 do
    begin
      Inc(Result);
      Q := Pos(Needle, Hay, Q + 1);
    end;
  end;

  procedure Blocks;
  var I: Integer;
  begin
    Nav := nil; Note := nil; Cards := nil; Grid := nil;
    for I := 0 to Probe.BlockCount - 1 do
      with Probe.Block(I) do
        if Flex and (Pos('Home', Source) > 0) then Nav := Probe.Block(I)
        else if Flex then Grid := Probe.Block(I)
        else if Tag = 'table' then Cards := Probe.Block(I)
        else if Pos('note', Source) > 0 then Note := Probe.Block(I);
    Check((Nav <> nil) and (Note <> nil) and (Cards <> nil) and (Grid <> nil), 'the blocks are all there');
  end;

begin
  CSS := TInkStyleSheet.Create;
  try
    CSS.Add('p { color: #111111 } @media (max-width: 600px) { p { color: #222222 } } ' +
      '@media screen and (min-width: 900px) { p { color: #333333 } } @media print { p { color: #444444 } } ' +
      '@media (prefers-color-scheme: dark) { p { color: #555555 } }');
    CSS.MediaWidth := 1024;
    Check(CSS.Value('p', '', 'color', '') = '#333333', 'min-width query at 1024');
    CSS.MediaWidth := 700;
    Check(CSS.Value('p', '', 'color', '') = '#111111', 'no query at 700');
    CSS.MediaWidth := 500;
    Check(CSS.Value('p', '', 'color', '') = '#222222', 'max-width query at 500');
    Check(CSS.MediaState(500) <> CSS.MediaState(1024), 'the media state changes across a breakpoint');
    Check(CSS.MediaState(700) = CSS.MediaState(800), 'and not between them');
  finally CSS.Free end;

  Probe.SetBounds(0, 0, 900, 300);
  Probe.LoadHTML(Doc);
  Probe.ScrollTo(0);
  Blocks;
  Check(Pos('secret', Probe.PlainText) = 0, 'display: none hides an inline element');
  Check(Pos('hidden card', Probe.PlainText) = 0, 'and a flex item');
  Check(Pos('afterwords', StringReplace(Probe.PlainText, ' ', '', [rfReplaceAll])) > 0, 'the words around it stay');
  Check(ColorToRGB(Note.TextColor) = RGBToColor(0, 255, 0), 'wide: the plain rule');
  Check(CountOf('<tr>', Cards.Source) = 1, 'wide: the cards are one row');
  Check(Length(Grid.FlexCells) = 3, Format('three grid items (%d)', [Length(Grid.FlexCells)]));
  Check(Grid.FlexCols = 3, Format('wide: three to a row (%d)', [Grid.FlexCols]));
  Check(Grid.NoLinkUnderline, 'a card that is a link is not underlined');
  Check(Nav.FlexCols = 2, 'a flex row that does not wrap');
  Check(Pos('width="100%"', Nav.Source) = 0, 'is as wide as its items');

  Probe.SetBounds(0, 0, 360, 300);
  Probe.ScrollTo(0);
  Blocks;
  Check(ColorToRGB(Note.TextColor) = RGBToColor(255, 0, 0), 'narrow: the max-width rule');
  Rows := CountOf('<tr>', Cards.Source);
  Check(Rows = 2, Format('narrow: a card to a row, the empty one gone (%d)', [Rows]));
  Check(Grid.FlexCols < 3, Format('narrow: fewer to a row (%d)', [Grid.FlexCols]));
  Check(CountOf('<tr>', Grid.Source) = (3 + Grid.FlexCols - 1) div Grid.FlexCols, 'in as many rows as that takes');
  K := Grid.FlexCols;
  Probe.SetBounds(0, 0, 900, 300);
  Probe.ScrollTo(0);
  Blocks;
  Check((Grid.FlexCols = 3) and (K < 3), 'and back when it widens');
  Check(ColorToRGB(Note.TextColor) = RGBToColor(0, 255, 0), 'wide again: the plain rule');
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- style attributes, <details>, <caption>, <q> and link titles --- }
procedure TagChecks;
const
  Doc =
    '<html><head><style>' +
    'body { background: #ffffff; color: #000000 } p.wide { color: #0000ff } ' +
    'h4 { text-align: center } ' +
    '</style></head><body>' +
    '<p>Plain <span style="color: #ff0000">red</span>, ' +
    '<span style="font-weight: bold">thick</span>, ' +
    '<span style="text-decoration: underline; font-style: italic">under</span>, ' +
    '<b style="color: #00ff00">both</b>.</p>' +
    '<p class="wide" style="color: #008800; background: #101010; font-size: 24px">styled block</p>' +
    '<p style="text-align: center">middled</p>' +
    '<h4>a heading the sheet centers</h4>' +
    '<center><p>in a center</p></center>' +
    '<p>She said <q>hello</q> loudly.</p>' +
    '<p><a href="a.html" title="the first page">link</a> and ' +
    '<a href="b.html">no title</a></p>' +
    '<table><caption>Table one</caption><tr><td>cell</td></tr></table>' +
    '<details><summary>More</summary><p>the secret</p></details>' +
    '<details open><summary>Already</summary><p>on show</p></details>' +
    '<details><p>no summary here</p></details>' +
    '<p>an icon <svg viewBox="0 0 8 8"><title>a drawing</title><path d="M0 0"/></svg> beside words</p>' +
    '<template><p>not a real paragraph</p></template>' +
    '<p>last line</p>' +
    '</body></html>';
var
  I, Summary, Secret, Caption, TableAt, Middled: Integer;
  B: TInkPageBlock; Plain, Spans: string; WasHigh: Integer;
begin
  Probe.SetBounds(0, 0, 500, 400);
  Probe.LoadHTML(Doc);
  Probe.ScrollTo(0);
  Summary := -1; Secret := -1; Caption := -1; TableAt := -1; Middled := -1;
  Spans := '';
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if Pos('Plain', B.Source) > 0 then Spans := B.Source;
    if (Summary < 0) and (B.FoldHead >= 0) then Summary := I;
    if Pos('the secret', B.Source) > 0 then Secret := I;
    if B.Tag = 'caption' then Caption := I;
    if (TableAt < 0) and (B.Tag = 'table') then TableAt := I;
    if Pos('middled', B.Source) > 0 then Middled := I;
  end;

  { a style attribute on something inside a paragraph }
  Check(Pos('<font color="#FF0000">red</font>', Spans) > 0, 'style="color" colors a span');
  Check(Pos('<b>thick</b>', Spans) > 0, 'style="font-weight: bold" thickens one');
  Check((Pos('<u>', Spans) > 0) and (Pos('<i>', Spans) > 0), 'underline and italic together');
  Check(Pos('</u></i>', Spans) > 0, 'and they are closed in order');
  Check(Pos('<b><font color="#00FF00">both</font></b>', Spans) > 0,
    'a style on an element that already draws something keeps both');

  { and on a block of its own }
  B := Probe.Block(1);
  Check(Pos('styled block', B.Source) > 0, 'the styled block is where it should be');
  Check(ColorToRGB(B.TextColor) = RGBToColor(0, $88, 0), 'a block''s style attribute beats its class');
  Check(ColorToRGB(B.BackColor) = RGBToColor($10, $10, $10), 'and gives it a background');
  { sizes are pixels, negative the way TFont.Height spells them }
  Check(B.PointSize = -24, Format('font-size: 24px is 24 pixels (%d)', [B.PointSize]));

  Check((Middled >= 0) and (Pos('<center>', Probe.Block(Middled).Source) = 1),
    'style="text-align: center" centers a block');
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'h4' then
      Check(Pos('<center>', Probe.Block(I).Source) = 1, 'and so does text-align in the stylesheet');
  for I := 0 to Probe.BlockCount - 1 do
    if Pos('in a center', Probe.Block(I).Source) > 0 then
      Check(Pos('<center>', Probe.Block(I).Source) = 1, 'a <center> centers what is inside it');

  Plain := Probe.PlainText;
  Check(Pos('said ' + #$E2#$80#$9C + 'hello' + #$E2#$80#$9D + ' loudly', Plain) > 0,
    '<q> puts quotation marks round what it holds');

  { a link''s title is its tooltip }
  for I := 0 to Probe.BlockCount - 1 do
    if Pos('no title', Probe.Block(I).Source) > 0 then
    begin
      B := Probe.Block(I);
      Check(Length(B.LinkTitles) = 2, Format('a title for each link (%d)', [Length(B.LinkTitles)]));
      Check(B.LinkTitles[0] = 'the first page', 'the title the page gave');
      Check(B.LinkTitles[1] = '', 'and nothing for the link without one');
    end;

  { a table''s caption is a line above it }
  Check(Caption >= 0, 'a <caption> makes a block');
  Check((TableAt >= 0) and (Caption < TableAt), 'and it comes before its table');
  Check(Pos('Table one', Probe.Block(Caption).Source) > 0, 'holding the caption''s words');
  Check(Pos('Table one', Probe.Block(TableAt).Source) = 0, 'and not left in the table');
  Check(Pos('cell', Probe.Block(TableAt).Source) > 0, 'whose cell is still there');

  { <details> starts shut, and a click on the summary opens it }
  Check(Summary >= 0, 'a <summary> is a block that works a fold');
  Check(Secret >= 0, 'and what it hides is a block too');
  Check(not Probe.BlockVisible(Secret), '<details> starts folded away');
  Check(Probe.Block(Secret).Bounds.Bottom - Probe.Block(Secret).Bounds.Top = 0, 'taking up no room');
  Check(Probe.Block(Summary).Marker = #$E2#$96#$B6, 'the summary points right while it is shut');
  B := Probe.Block(Summary);
  WasHigh := Probe.Block(Probe.BlockCount - 1).Bounds.Bottom;
  Probe.Press(B.Bounds.Left + 4, B.Bounds.Top + 2);
  Probe.Let(B.Bounds.Left + 4, B.Bounds.Top + 2);
  Check(Probe.BlockVisible(Secret), 'a click on the summary opens it');
  Check(Probe.Block(Secret).Bounds.Bottom - Probe.Block(Secret).Bounds.Top > 0, 'and it takes room');
  Check(Probe.Block(Probe.BlockCount - 1).Bounds.Bottom > WasHigh, 'so the page grows');
  Check(Probe.Block(Summary).Marker = #$E2#$96#$BC, 'and the summary points down');
  Probe.Press(B.Bounds.Left + 4, B.Bounds.Top + 2);
  Probe.Let(B.Bounds.Left + 4, B.Bounds.Top + 2);
  Check(not Probe.BlockVisible(Secret), 'and another click shuts it again');

  for I := 0 to Probe.BlockCount - 1 do
  begin
    if Pos('on show', Probe.Block(I).Source) > 0 then
      Check(Probe.BlockVisible(I), '<details open> starts open');
    if Pos('no summary', Probe.Block(I).Source) > 0 then
      Check(Probe.BlockVisible(I), 'a <details> with no summary is left open');
  end;
  Check(Pos('a drawing', Plain) = 0, 'what is inside an <svg> is not read out');
  Check(Pos('not a real paragraph', Plain) = 0, 'nor what is in a <template>');
  Check(Pos('icon', Plain) > 0, 'the words either side of a drawing stay');
  Check(Pos('last line', Plain) > 0, 'and so does the rest of the page');
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- coloring code blocks --- }
procedure CodeChecks;
const
  Pas =
    '```pascal'#10 +
    'procedure Go;'#10 +
    'begin'#10 +
    '  { a comment }'#10 +
    '  S := ''text'';'#10 +
    '  N := 42;'#10 +
    'end;'#10 +
    '```'#10;
  Bare =
    '```'#10 +
    'function f(n) {'#10 +
    '  // a line comment'#10 +
    '  if (n > 7) return "big";'#10 +
    '}'#10 +
    '```'#10;
var
  Colors: TInkCodeColors; Markup, Code: string; I, Block: Integer;

  function Lower(const S: string): string;
  begin
    Result := LowerCase(S);
  end;

  { the first <pre> block of the page }
  function CodeBlock: Integer;
  var K: Integer;
  begin
    Result := -1;
    for K := 0 to Probe.BlockCount - 1 do
      if Probe.Block(K).Tag = 'pre' then Exit(K);
  end;

begin
  { --- the highlighter on its own --- }
  Check(InkCodeLanguage('language-Pascal') = 'pascal', 'a class names the language');
  Check(InkCodeLanguage('PY') = 'python', 'and so does a short name');
  Check(InkCodeLanguage('pascal {.numberLines}') = 'pascal', 'a fence may say more than the language');
  Check(InkCodeLanguage('') = '', 'nothing said is nothing');
  Check(InkCodeKnown('pascal') and InkCodeKnown('go'), 'languages we have rules for');
  Check(not InkCodeKnown(''), 'a block that names none is colored by the common rules');

  Colors := InkCodeColors(clWhite);
  Check(Colors.Comment <> Colors.Keyword, 'the colors differ from each other');
  Check(InkCodeColors(clBlack).Comment <> Colors.Comment, 'and a dark page gets its own set');

  Markup := Lower(InkHighlight('procedure Go; { why } S := ''text''; N := 42;' + #10 +
    'Total := Total + 1;', 'pascal', Colors));
  Check(Pos('<font color="' + Lower(ColorToString(Colors.Keyword)) + '">', Markup) = 0,
    'colors are written as hex, not as names');
  Check(Pos('>procedure</font>', Markup) > 0, 'a keyword is colored');
  Check(Pos('>begin</font>', Markup) = 0, 'a word that is not there is not');
  Check(Pos('>{ why }</font>', Markup) > 0, 'a Pascal comment in braces');
  Check(Pos('>''text''</font>', Markup) > 0, 'a string in its quotes');
  Check(Pos('>42</font>', Markup) > 0, 'a number');
  Check(Pos('<br>', Markup) > 0, 'a line break stays a line break');
  Check(Pos('go;', Markup) > 0, 'and everything else is left as it was');

  { a comment runs to the end of its line, and a string does not swallow the line }
  Markup := InkHighlight('x = 1; // set it' + #10 + 'y = 2;', 'c', Colors);
  Check(Pos('>// set it</font>', Markup) > 0, 'a line comment stops at the line');
  Check(Pos('>2</font>', Markup) > 0, 'the next line is code again');

  { a block that says nothing still gets the words most languages share }
  Markup := InkHighlight('if (n > 7) begin end // done', '', Colors);
  Check(Pos('>if</font>', Markup) > 0, 'a common keyword is colored without a language');
  Check(Pos('>begin</font>', Markup) > 0, 'begin counts as one of those');
  Check(Pos('>// done</font>', Markup) > 0, 'and // is a comment everywhere');

  { prose is not code }
  Markup := InkHighlight('It is 42 degrees, and "quoted" text.', 'markdown', Colors);
  Check(Pos('<font', Markup) = 0, 'a Markdown block is left alone');

  { --- the things that used to color half a line by mistake --- }
  Markup := InkHighlight('a { color: #fff; background: red }', '', Colors);
  Check(Pos('#fff; background: red', Markup) > 0, 'a hex color is not a comment');
  Markup := InkHighlight('# install it' + #10 + 'x = 1   # and a note', '', Colors);
  Check(Pos('># install it</font>', Markup) > 0, 'but # at the start of a line is');
  Check(Pos('># and a note</font>', Markup) > 0, 'and so is # spaced off the code');
  Markup := InkHighlight('for (i = n; i > 0; i--) sum -= i;', '', Colors);
  Check(Pos('<font color', Copy(Markup, Pos('i--', Markup), 40)) = 0,
    'i-- is a decrement, not a comment');
  Markup := InkHighlight('SELECT 1 -- how many', '', Colors);
  Check(Pos('>-- how many</font>', Markup) > 0, 'a spaced -- still is one');
  Markup := InkHighlight('echo it''s fine' + #10 + 'echo ''really''', '', Colors);
  Check(Pos('>fine', Markup) = 0, 'an apostrophe in a word does not open a string');
  Check(Pos('>''really''</font>', Markup) > 0, 'a quote that closes on the line does');
  Markup := InkHighlight('let s = `a ${x} template`;', 'javascript', Colors);
  Check(Pos('>`a ${x} template`</font>', Markup) > 0, 'a backtick string in JavaScript');
  Markup := InkHighlight('<div class="card"><!-- a note --></div>', 'html', Colors);
  Check(Pos('>&lt;div</font>', Markup) > 0, 'an HTML tag name is colored');
  Check(Pos('>&lt;/div</font>', Markup) > 0, 'and so is a closing one');
  Check(Pos('>&lt;!-- a note --&gt;</font>', Markup) > 0, 'with its comment');
  Markup := InkHighlight('see section 1. it says', '', Colors);
  Check(Pos('>1</font>', Markup) > 0, 'a number at the end of a sentence keeps its dot out');

  { comments in the languages people put in documents }
  Check(Pos('>-- note</font>', InkHighlight('x = 1 -- note', 'lua', Colors)) > 0, 'Lua --');
  Check(Pos('>% note</font>', InkHighlight('x = 1 % note', 'matlab', Colors)) > 0, 'MATLAB %');
  Check(Pos('>; note</font>', InkHighlight('mov ax, 1 ; note', 'asm', Colors)) > 0, 'assembler ;');
  Check(Pos('>'' note</font>', InkHighlight('x = 1 '' note', 'vb', Colors)) > 0, 'Basic apostrophe');
  Check(Pos('>(* note *)</font>', InkHighlight('let x = 1 (* note *)', 'ocaml', Colors)) > 0,
    'OCaml (* *)');
  Check(Pos('>#= note =#</font>', InkHighlight('x = 1 #= note =#', 'julia', Colors)) > 0,
    'Julia #= =#');
  Check(Pos('>{- note -}</font>', InkHighlight('x = 1 {- note -}', 'haskell', Colors)) > 0,
    'Haskell {- -}');
  Check(Pos('>{ note }</font>', InkHighlight('X := 1; { note }', 'pascal', Colors)) > 0,
    'and Pascal braces, of course');

  { Pascal's doubled quote is one string, not two }
  Markup := InkHighlight('Reply := ''It''''s ready''; N := $FF;', 'pascal', Colors);
  Check(Pos('>''It''''s ready''</font>', Markup) > 0, 'a doubled quote stays inside its string');
  Check(Pos('>$FF</font>', Markup) > 0, 'and $FF is a number');

  { Python, which has a few habits of its own }
  Markup := InkHighlight('@property' + #10 + 'def go(self):' + #10 +
    '    """what it does"""' + #10 + '    return f"{self.n} left"', 'python', Colors);
  Check(Pos('>@property</font>', Markup) > 0, 'a decorator reads as a keyword');
  Check(Pos('>self</font>', Markup) > 0, 'and so does self');
  Check(Pos('>"""what it does"""</font>', Markup) > 0, 'a docstring is one string');
  Check(Pos('>f"{self.n} left"</font>', Markup) > 0, 'an f-string keeps its f');
  Check(Pos('>def</font>', Markup) > 0, 'and def is still def');

  { --- and through a page --- }
  Probe.SetBounds(0, 0, 500, 400);
  Probe.HighlightCode := True;
  Probe.LoadMarkdown(Pas);
  Block := CodeBlock;
  Check(Block >= 0, 'the fence made a code block');
  Check(Probe.Block(Block).CodeLanguage = 'pascal', 'which kept its language');
  Check(Pos('<font color=', Probe.Block(Block).Source) > 0, 'and was colored');
  Code := Probe.BlockText(Block);
  Check(Pos('procedure Go;', Code) > 0, 'the code copies out as it was written');
  Check(Pos('{ a comment }', Code) > 0, 'comment and all');
  Check(Pos('<font', Code) = 0, 'with no markup in it');
  Check(Probe.Block(Block).Code = Code, 'and the block keeps the same text');

  Probe.HighlightCode := False;
  Block := CodeBlock;
  Check(Pos('<font color=', Probe.Block(Block).Source) = 0, 'HighlightCode off leaves it plain');
  Check(Pos('procedure Go;', Probe.BlockText(Block)) > 0, 'and the code is still all there');
  Probe.HighlightCode := True;

  { a block with no language is colored by the common rules }
  Probe.LoadMarkdown(Bare);
  Block := CodeBlock;
  Check(Probe.Block(Block).CodeLanguage = '', 'the fence named no language');
  Check(Pos('<font color=', Probe.Block(Block).Source) > 0, 'it is colored anyway');

  { a page that colored its own code keeps its colors }
  Probe.LoadHTML('<html><body><pre><code class="language-pascal">' +
    '<span style="color: #ff00ff">begin</span> end;</code></pre></body></html>');
  Block := CodeBlock;
  Check(Pos('#FF00FF', UpperCase(Probe.Block(Block).Source)) > 0, 'the page''s own coloring is kept');
  I := 0; Code := Probe.Block(Block).Source;
  while Pos('<font color=', Code) > 0 do
  begin
    Inc(I); Delete(Code, 1, Pos('<font color=', Code) + 11);
  end;
  Check(I = 1, Format('and ours is not painted over the top of it (%d font tags)', [I]));

  { a host highlighter answers first }
  Probe.OnHighlightCode := @Probe.Highlight;
  Probe.Clicked := '';
  Probe.LoadMarkdown(Pas);
  Block := CodeBlock;
  Check(Probe.Clicked = 'pascal', 'the host is told which language it is');
  Check(Pos('#123456', Probe.Block(Block).Source) > 0, 'and its markup is what gets drawn');
  Probe.OnHighlightCode := nil;
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- WebP: synthetic container metadata (intentionally invalid compressed pixels) --- }
procedure WebPChecks;
var
  Still, Anim: TMemoryStream; W: TInkWebP; F: TInkWebPFrame;

  { the pieces a WebP file is built from, written by hand so the test does
    not need an encoder - and so that what the reader reads is exactly what
    the test wrote }
  procedure PutStr(S: TStream; const Text: string);
  begin
    if Text <> '' then S.WriteBuffer(Text[1], Length(Text));
  end;

  procedure Put32(S: TStream; N: LongWord);
  begin
    S.WriteBuffer(N, 4);
  end;

  procedure Put24(S: TStream; N: LongWord);
  var B: array[0..2] of Byte;
  begin
    B[0] := N and $FF; B[1] := (N shr 8) and $FF; B[2] := (N shr 16) and $FF;
    S.WriteBuffer(B, 3);
  end;

  procedure PutByte(S: TStream; N: Byte);
  begin
    S.WriteBuffer(N, 1);
  end;

  { RIFF....WEBP round whatever was written into Body }
  function Wrap(Body: TMemoryStream): TMemoryStream;
  begin
    Result := TMemoryStream.Create;
    PutStr(Result, 'RIFF');
    Put32(Result, Body.Size + 4);
    PutStr(Result, 'WEBP');
    Body.Position := 0;
    Result.CopyFrom(Body, Body.Size);
    Result.Position := 0;
  end;

  { a lossless still, 40 x 30: VP8L's header packs width-1 and height-1 in
    14 bits each after a signature byte }
  function BuildStill: TMemoryStream;
  var Body: TMemoryStream; Bits: LongWord;
  begin
    Body := TMemoryStream.Create;
    try
      PutStr(Body, 'VP8L');
      Put32(Body, 10);
      PutByte(Body, $2F);
      Bits := (40 - 1) or ((30 - 1) shl 14);
      Put32(Body, Bits);
      Put32(Body, 0);
      PutByte(Body, 0);
      Result := Wrap(Body);
    finally Body.Free end;
  end;

  { an animation: VP8X saying 64 x 48 and animated, ANIM with a background
    and a loop count, then two ANMF frames }
  function BuildAnimation: TMemoryStream;
  var Body, Frame: TMemoryStream;

    procedure AddFrame(X, Y, W, H, Duration: Integer; Flags: Byte);
    begin
      Frame := TMemoryStream.Create;
      try
        Put24(Frame, X div 2); Put24(Frame, Y div 2);
        Put24(Frame, W - 1); Put24(Frame, H - 1);
        Put24(Frame, Duration);
        PutByte(Frame, Flags);
        { the frame's pixels, as a lossless sub-chunk }
        PutStr(Frame, 'VP8L'); Put32(Frame, 6);
        PutByte(Frame, $2F); Put32(Frame, 0); PutByte(Frame, 0);
        PutStr(Body, 'ANMF'); Put32(Body, Frame.Size);
        Frame.Position := 0;
        Body.CopyFrom(Frame, Frame.Size);
      finally Frame.Free end;
    end;

  begin
    Body := TMemoryStream.Create;
    try
      PutStr(Body, 'VP8X'); Put32(Body, 10);
      PutByte(Body, 2); { the animation flag }
      Put24(Body, 0);
      Put24(Body, 64 - 1); Put24(Body, 48 - 1);
      PutStr(Body, 'ANIM'); Put32(Body, 6);
      { the background is written blue, green, red, alpha - BGRA }
      PutByte(Body, $10); PutByte(Body, $20); PutByte(Body, $30); PutByte(Body, $FF);
      PutByte(Body, 3); PutByte(Body, 0); { three loops }
      AddFrame(0, 0, 64, 48, 120, 0);
      AddFrame(8, 4, 32, 24, 80, 1);   { cleared to the background after it }
      Result := Wrap(Body);
    finally Body.Free end;
  end;

begin
  { is it a WebP at all }
  Check(not InkIsWebP('GIF89a stuff'), 'a GIF is not a WebP');
  Check(not InkIsWebP('RIFF----WAVE'), 'nor is a WAV');

  Still := BuildStill;
  try
    W := TInkWebP.Create(Still);
    try
      Check(W.Valid, 'a lossless still reads');
      Check((W.Width = 40) and (W.Height = 30),
        Format('its size comes from VP8L (%dx%d)', [W.Width, W.Height]));
      Check(W.Kind = wkLossless, 'and it knows it is lossless');
      Check(not W.Animated, 'one frame is not an animation');
      Check(W.FrameCount = 1, 'and there is one frame');
      Check(W.Frame(0).Size > 0, 'whose bytes it can point at');
      { Metadata-only fixture, not a decodable VP8L image. }
      Check(not W.DecodeFrame(0), 'invalid synthetic compressed pixels are rejected');
      Check(not W.Decoded, 'no fabricated pixels after a decoding failure');
    finally W.Free end;
  finally Still.Free end;

  Anim := BuildAnimation;
  try
    W := TInkWebP.Create(Anim);
    try
      Check(W.Valid, 'an animation reads');
      Check((W.Width = 64) and (W.Height = 48),
        Format('its canvas comes from VP8X (%dx%d)', [W.Width, W.Height]));
      Check(W.Kind = wkExtended, 'which makes it an extended file');
      Check(W.Animated and (W.FrameCount = 2),
        Format('with two frames (%d)', [W.FrameCount]));
      Check(W.Loops = 3, Format('and a loop count (%d)', [W.Loops]));
      Check(ColorToRGB(W.Background) = RGBToColor($30, $20, $10),
        'the background it clears to, read back out of BGRA');
      F := W.Frame(0);
      Check((F.Width = 64) and (F.Height = 48) and (F.Duration = 120),
        Format('frame one: %dx%d for %dms', [F.Width, F.Height, F.Duration]));
      Check(F.Blend, 'blended onto what is there');
      Check(F.Disposal = wdNone, 'and left in place');
      F := W.Frame(1);
      Check((F.X = 8) and (F.Y = 4) and (F.Width = 32) and (F.Height = 24),
        Format('frame two sits at %d,%d and is %dx%d', [F.X, F.Y, F.Width, F.Height]));
      Check(F.Duration = 80, 'for its own time');
      Check(F.Disposal = wdBackground, 'and the canvas is cleared after it');
      Check((F.Kind = wkLossless) and (F.Size > 0), 'its pixels are lossless, and located');
      Check(not W.DecodeFrame(1), 'invalid synthetic animation pixels are rejected');
    finally W.Free end;
  finally Anim.Free end;
end;

{ --- a cell that reaches across columns --- }
{ rowspan, line-height, image sizing, text-transform and white-space: the
  five things a help page asks for that LazInk used not to read }
procedure AuthorChecks;
var I, J, Plain, Airy, Tall, Short, Mid, Deep: Integer; B: TInkPageBlock; S: string;

begin
  { a cell that reaches down two rows is as tall as both of them }
  Probe.SetBounds(0, 0, 500, 400);
  Probe.LoadHTML('<html><body><table border="1">' +
    '<tr><td rowspan="3">deep</td><td>one</td></tr>' +
    '<tr><td>two</td></tr>' +
    '<tr><td>middle</td></tr>' +
    '<tr><td>three</td><td>four</td></tr>' +
    '</table></body></html>');
  Probe.ScrollTo(0);
  B := nil;
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then begin B := Probe.Block(I); Probe.BlockText(I) end;
  Check(B <> nil, 'the rowspan table is there');
  if B = nil then Exit;
  Check(Pos('rowspan="3"', B.Source) > 0, 'the page passes rowspan on');
  Tall := -1; Short := -1; Plain := -1; Mid := -1; Deep := -1;
  for J := 0 to B.RunCount - 1 do
  begin
    if Trim(B.Runs[J].Text) = 'deep' then
      begin Tall := B.Runs[J].Top; Deep := B.Runs[J].Left end;
    if Trim(B.Runs[J].Text) = 'two' then
      begin Short := B.Runs[J].Top; Mid := B.Runs[J].Left end;
    if Trim(B.Runs[J].Text) = 'three' then Plain := B.Runs[J].Top;
  end;
  { every row a rowspan covers starts to the right of it, and the row after
    it starts back in the first column }
  Check(Mid > Deep,
    Format('a row under a rowspan starts past it (%d against %d)', [Mid, Deep]));
  for J := 0 to B.RunCount - 1 do
    if Trim(B.Runs[J].Text) = 'middle' then
      Check(B.Runs[J].Left > Deep,
        Format('and so does the third row it covers (%d against %d)',
          [B.Runs[J].Left, Deep]));
  Check((Tall >= 0) and (Short >= 0) and (Plain >= 0),
    Format('every cell was laid out (deep %d, two %d, three %d)', [Tall, Short, Plain]));
  Check(Short > Tall,
    Format('the second row starts below the spanning cell (%d against %d)', [Short, Tall]));
  Check(Plain > Short,
    Format('and the third row is below that (%d against %d)', [Plain, Short]));
  { the cell under the spanning one starts in the first column again }
  for J := 0 to B.RunCount - 1 do
    if Trim(B.Runs[J].Text) = 'three' then
      for I := 0 to B.RunCount - 1 do
        if Trim(B.Runs[I].Text) = 'deep' then
          Check(Abs(B.Runs[J].Left - B.Runs[I].Left) < 4,
            Format('a row under a rowspan starts in the first column (%d against %d)',
              [B.Runs[J].Left, B.Runs[I].Left]));

  { line-height: the same words, further apart }
  Probe.LoadHTML('<html><head><style>p.airy { line-height: 2.4 }</style></head>' +
    '<body><p>one word and then enough more words that the line has to wrap ' +
    'at least once in this narrow column</p>' +
    '<p class="airy">one word and then enough more words that the line has to wrap ' +
    'at least once in this narrow column</p></body></html>');
  Probe.SetBounds(0, 0, 220, 400);
  Probe.ScrollTo(0);
  Plain := 0; Airy := 0;
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if B.Tag <> 'p' then Continue;
    if Pos('airy', B.CSSClass) > 0 then Airy := B.Bounds.Bottom - B.Bounds.Top
    else if Plain = 0 then Plain := B.Bounds.Bottom - B.Bounds.Top;
  end;
  Check((Plain > 0) and (Airy > 0),
    Format('both paragraphs were laid out (%d and %d)', [Plain, Airy]));
  Check(Airy > Plain + 8,
    Format('line-height: 2.4 makes a paragraph taller (%d against %d)', [Airy, Plain]));

  { a picture at the size the page asked for }
  Probe.SetBounds(0, 0, 500, 400);
  Probe.LoadHTML('<html><body><p><img src="palette.png" alt="a"></p>' +
    '<p><img src="palette.png" alt="b" width="60"></p>' +
    '<p><img src="palette.png" alt="c" width="25%"></p></body></html>',
    FilenameToURI(ExpandFileName('images/page.html')));
  Probe.ScrollTo(0);
  Plain := 0; Tall := 0; Short := 0;
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if B.Tag <> 'img' then Continue;
    if B.ImageWantW = 60 then Tall := B.ImageRect.Right - B.ImageRect.Left
    else if B.ImagePercent = 25 then Short := B.ImageRect.Right - B.ImageRect.Left
    else if Plain = 0 then Plain := B.ImageRect.Right - B.ImageRect.Left;
  end;
  Check(Tall = 60, Format('width="60" draws the picture 60 wide (%d)', [Tall]));
  Check((Short > 0) and (Short < 200),
    Format('width="25%%" is a quarter of the column (%d)', [Short]));

  { the end of an inline tag is not a place to break a line }
  Probe.SetBounds(0, 0, 220, 300);
  Probe.LoadHTML('<html><body><p>one two three four five ' +
    '<code>anchor</code>. And more words after it.</p></body></html>');
  Probe.ScrollTo(0);
  Probe.BlockText(0);
  B := Probe.Block(0);
  Plain := -1; Short := -1;
  for J := 0 to B.RunCount - 1 do
  begin
    if Trim(B.Runs[J].Text) = 'anchor' then Plain := B.Runs[J].Line;
    if (Trim(B.Runs[J].Text) = '.') and (Short < 0) then Short := B.Runs[J].Line;
  end;
  Check(Plain >= 0, 'the code span was laid out');
  if Short >= 0 then
    Check(Short = Plain,
      Format('a full stop stays with the word before it (line %d against %d)',
        [Short, Plain]));

  { a cell's own text-transform: a table is one block, so a th's uppercase
    cannot be done to the block as a whole }
  Probe.SetBounds(0, 0, 500, 300);
  Probe.LoadHTML('<html><head><style>' +
    'table.span th { text-transform: uppercase }' +
    '</style></head><body><table class="span">' +
    '<tr><th>Release</th><th>Part</th></tr>' +
    '<tr><td>quiet</td><td>also quiet</td></tr>' +
    '</table></body></html>');
  Probe.ScrollTo(0);
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then
    begin
      S := Probe.Block(I).Source;
      Check(Pos('RELEASE', S) > 0, 'a th wears its uppercase: ' + Copy(S, 1, 120));
      Check(Pos('PART', S) > 0, 'and so does the next one');
      Check(Pos('quiet', S) > 0, 'and a td is left alone');
      Check(Pos('QUIET', S) = 0, 'really left alone: ' + Copy(S, 1, 120));
    end;

  { border-left, which is how a documentation page draws a callout }
  Probe.SetBounds(0, 0, 400, 300);
  Probe.LoadHTML('<html><head><style>' +
    '.note { background: #f4f6f8; border-left: 4px solid #176bbd; padding: 8px }' +
    '.plain { background: #f4f6f8 }' +
    '.gone { border-left: none }' +
    '</style></head><body>' +
    '<div class="note">a callout</div><div class="plain">no stripe</div>' +
    '<div class="gone">nor here</div></body></html>');
  Probe.ScrollTo(0);
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if Pos('note', B.CSSClass) > 0 then
    begin
      Check(ColorToRGB(B.EdgeColor[0]) = RGBToColor($17, $6B, $BD),
        'border-left takes its color');
      Check(B.EdgeWidth[0] = 4, Format('and its width (%d)', [B.EdgeWidth[0]]));
      Check(B.EdgeColor[1] = clNone, 'and leaves the other sides alone');
    end
    else if Pos('plain', B.CSSClass) > 0 then
      Check(B.EdgeColor[0] = clNone, 'a block with no border-left has no stripe')
    else if Pos('gone', B.CSSClass) > 0 then
      Check(B.EdgeColor[0] = clNone, 'border-left: none is no stripe');
  end;

  { text-transform and white-space }
  Probe.LoadHTML('<html><head><style>p.shout { text-transform: uppercase }' +
    ' p.keep { white-space: nowrap }</style></head>' +
    '<body><p class="shout">quiet words &amp; <b>bold</b> ones</p>' +
    '<p class="keep">a line that is far too long to fit inside this ' +
    'narrow column and would wrap several times if it were allowed to</p>' +
    '<p>a line that is far too long to fit inside this ' +
    'narrow column and would wrap several times if it were allowed to</p>' +
    '</body></html>');
  Probe.SetBounds(0, 0, 200, 400);
  Probe.ScrollTo(0);
  Plain := 0; Short := 0;
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if B.Tag <> 'p' then Continue;
    S := B.Source;
    if Pos('shout', B.CSSClass) > 0 then
    begin
      Check(Pos('QUIET WORDS', S) > 0, 'text-transform: uppercase shouts: ' + Copy(S, 1, 60));
      Check(Pos('<b>', S) > 0, 'and leaves the markup alone');
      Check(Pos('&amp;', S) > 0, 'and the entities too');
    end
    else if Pos('keep', B.CSSClass) > 0 then Short := B.Bounds.Bottom - B.Bounds.Top
    else if Plain = 0 then Plain := B.Bounds.Bottom - B.Bounds.Top;
  end;
  Check((Short > 0) and (Plain > 0),
    Format('both long lines were laid out (%d and %d)', [Short, Plain]));
  Check(Short < Plain,
    Format('white-space: nowrap keeps a line to one row (%d against %d)', [Short, Plain]));
  Probe.SetBounds(0, 0, 400, 200);
end;

procedure ColspanChecks;
var
  I, J, Wide, Narrow: Integer; B: TInkPageBlock;
begin
  Probe.SetBounds(0, 0, 500, 300);
  Probe.LoadHTML('<html><body><table border="1">' +
    '<tr><td>alpha</td><td>beta</td><td>gamma</td></tr>' +
    '<tr><td colspan="2">spanned</td><td>tail</td></tr>' +
    '<tr><td colspan="3">everything</td></tr>' +
    '</table></body></html>');
  Probe.ScrollTo(0);
  B := nil;
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then begin B := Probe.Block(I); Probe.BlockText(I) end;
  Check(B <> nil, 'the table is there');
  if B = nil then Exit;
  Check(Pos('colspan="2"', B.Source) > 0, 'the page passes colspan on: ' + Copy(B.Source, 1, 120));

  { the words of a spanning cell start where the first column starts, and
    the cell reaches past where the second one would end }
  Wide := 0; Narrow := 0;
  for J := 0 to B.RunCount - 1 do
  begin
    if Trim(B.Runs[J].Text) = 'spanned' then Wide := B.Runs[J].Left;
    if Trim(B.Runs[J].Text) = 'beta' then Narrow := B.Runs[J].Left;
  end;
  Check((Wide > 0) and (Narrow > 0),
    Format('both cells were laid out (spanned at %d, beta at %d)', [Wide, Narrow]));
  Check(Wide < Narrow,
    Format('a cell that spans two columns starts in the first (%d against %d)',
      [Wide, Narrow]));
  Check(Pos('everything', Probe.BlockText(0)) > 0, 'and the three-column one is there');

  { the cell beside a spanning one sits past the columns it covers }
  for J := 0 to B.RunCount - 1 do
    if Trim(B.Runs[J].Text) = 'tail' then
      Check(B.Runs[J].Left > Narrow,
        Format('the cell after a spanning one sits after it (%d against %d)',
          [B.Runs[J].Left, Narrow]));
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- nothing a block paints may leak into the next one --- }
{ bugs/2026-09-21-inline-code-shading-covers-neighbor-lines: the shading
  behind inline code must stay inside the line it is on.  The line-height
  here is tighter than the fixed face's own cell, which is the shape the
  fault takes on Windows, where Consolas stands taller than Segoe UI. }
procedure InlineShadeChecks;
const
  CSS = 'body { background: #ffffff; color: #000000; font-size: 14px; ' +
        'line-height: 1 } code { background: #ff0000 }';
  Doc = 'A plain paragraph with `one piece of code` in the middle of a line ' +
        'that is long enough to wrap at least twice, so that there is a line ' +
        'of ordinary text above the shaded piece and another below it, with ' +
        'letters that hang down - g j p q y - above it and tall ones - ' +
        'b d f h k l - below it.';
var
  Shot: TBitmap; X, Y, Top, Band, Worst, Bands, RedRows: Integer; SL: TStringList;
  Row: Boolean; Para: TInkPageBlock; I: Integer;
begin
  SL := TStringList.Create;
  try
    SL.Text := CSS;
    Probe.StyleSheet := SL;
  finally SL.Free end;
  Probe.SetBounds(0, 0, 260, 400);
  Probe.TextFormat := itfMarkdown;
  Probe.LoadMarkdown(Doc);
  Probe.ScrollTo(0);
  Para := nil;
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'p' then begin Para := Probe.Block(I); Break end;
  Check(Para <> nil, 'the paragraph is there');
  if Para = nil then Exit;
  Check(Para.LineHeight = 14, Format('line-height: 1 is fourteen pixels (%d)', [Para.LineHeight]));

  Shot := TBitmap.Create;
  try
    Shot.SetSize(Probe.ClientWidth, Probe.ClientHeight);
    Probe.RenderTo(Shot.Canvas);
    { the shading, row by row: pure red comes only from the fill, never from
      black text laid over it }
    Worst := 0; Bands := 0; Band := 0; RedRows := 0; Top := -1;
    for Y := 0 to Shot.Height - 1 do
    begin
      Row := False;
      for X := 0 to Shot.Width - 1 do
        if ColorToRGB(Shot.Canvas.Pixels[X, Y]) = RGBToColor($FF, 0, 0) then
        begin Row := True; Break end;
      if Row then
      begin
        Inc(RedRows);
        if Band = 0 then begin Inc(Bands); Top := Y end;
        Inc(Band); Worst := Max(Worst, Band);
      end
      else Band := 0;
    end;
    Check(RedRows > 0, 'the code is shaded at all');
    Check(Worst <= Para.LineHeight,
      Format('the shading is no taller than its line (%d rows against a %d-pixel line, ' +
        'first band at %d)', [Worst, Para.LineHeight, Top]));
  finally Shot.Free end;
  Probe.TextFormat := itfHTML;
  SL := TStringList.Create;
  try Probe.StyleSheet := SL finally SL.Free end;
  Probe.SetBounds(0, 0, 400, 200);
end;

procedure BrushLeakChecks;
const
  { the rule's color is red only so a stray fill can be told from the text }
  CSS = 'body { background: #eceef1; color: #5e6670; font-size: 14px } ' +
        'hr { color: #ff0000 }';
  Doc = 'Paragraph before the rule.' + LineEnding + LineEnding +
        '---' + LineEnding + LineEnding +
        'Paragraph after the rule.' + LineEnding + LineEnding +
        '### A heading after the rule' + LineEnding + LineEnding +
        '- a bullet after the rule' + LineEnding +
        '- another bullet' + LineEnding + LineEnding +
        'Another paragraph at the end.';
var
  Shot: TBitmap; I, X, Y, Red, Looked: Integer; B: TInkPageBlock; SL: TStringList;
  Bullet, Para: TInkPageBlock;
begin
  SL := TStringList.Create;
  try
    SL.Text := CSS;
    Probe.StyleSheet := SL;
  finally SL.Free end;
  Probe.SetBounds(0, 0, 420, 400);
  Probe.TextFormat := itfMarkdown;
  Probe.LoadMarkdown(Doc);
  Probe.ScrollTo(0);

  Bullet := nil; Para := nil;
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if (Bullet = nil) and (B.Tag = 'li') then Bullet := B;
    if (Para = nil) and (B.Tag = 'p') and (Pos('at the end', B.Source) > 0) then Para := B;
  end;
  Check(Bullet <> nil, 'there is a list item after the rule');
  Check(Para <> nil, 'and a paragraph after that');
  if (Bullet = nil) or (Para = nil) then Exit;

  Shot := TBitmap.Create;
  try
    Shot.SetSize(Probe.ClientWidth, Probe.ClientHeight);
    Probe.RenderTo(Shot.Canvas);
    { every pixel across the bullet's line, at a height where its text sits:
      the page's background may show, the text's color may show, the rule's
      red may not }
    Red := 0; Looked := 0;
    Y := Bullet.TextBounds.Top + (Bullet.TextBounds.Bottom - Bullet.TextBounds.Top) div 2
      - Probe.ScrollY;
    if (Y >= 0) and (Y < Shot.Height) then
      for X := Bullet.TextBounds.Left to Min(Bullet.TextBounds.Right, Shot.Width - 1) do
      begin
        Inc(Looked);
        if ColorToRGB(Shot.Canvas.Pixels[X, Y]) = RGBToColor($FF, 0, 0) then Inc(Red);
      end;
    Check(Looked > 0, 'the bullet is on screen');
    Check(Red = 0, Format('a list item after a rule is not painted in the rule''s ' +
      'color (%d of %d pixels were)', [Red, Looked]));

    { and the same for the paragraph that follows the list }
    Red := 0;
    Y := Para.TextBounds.Top + (Para.TextBounds.Bottom - Para.TextBounds.Top) div 2
      - Probe.ScrollY;
    if (Y >= 0) and (Y < Shot.Height) then
      for X := Para.TextBounds.Left to Min(Para.TextBounds.Right, Shot.Width - 1) do
        if ColorToRGB(Shot.Canvas.Pixels[X, Y]) = RGBToColor($FF, 0, 0) then Inc(Red);
    Check(Red = 0, Format('nor is the paragraph after it (%d)', [Red]));

    { the rule itself is still red, or the test above proves nothing }
    Red := 0;
    for I := 0 to Probe.BlockCount - 1 do
      if Probe.Block(I).Tag = 'hr' then
      begin
        Y := Probe.Block(I).TextBounds.Top - Probe.ScrollY;
        if (Y >= 0) and (Y < Shot.Height) then
          for X := Probe.Block(I).TextBounds.Left to
            Min(Probe.Block(I).TextBounds.Right, Shot.Width - 1) do
            if ColorToRGB(Shot.Canvas.Pixels[X, Y]) = RGBToColor($FF, 0, 0) then Inc(Red);
      end;
    Check(Red > 0, 'and the rule is drawn in it');
  finally Shot.Free end;

  { the canvas a control was handed back is the canvas it lent out }
  Shot := TBitmap.Create;
  try
    Shot.SetSize(200, 60);
    Shot.Canvas.Brush.Style := bsClear;
    Shot.Canvas.Brush.Color := clLime;
    Shot.Canvas.Brush.Style := bsClear;
    HTMLDrawOpt(Shot.Canvas, Rect(0, 0, 200, 60), [], 'some words', DefaultHTMLOptions);
    Check(Shot.Canvas.Brush.Style = bsClear,
      'drawing leaves the brush style as it found it');
  finally Shot.Free end;

  Probe.TextFormat := itfHTML;
  SL := TStringList.Create;
  try Probe.StyleSheet := SL finally SL.Free end;
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- every link in a page, wherever it sits, answers a click --- }
procedure LinkReachChecks;
const
  { each link's words are its own, so a run can be matched back to the href
    it should fire }
  Doc =
    '<html><head><style>.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}' +
    '.card{background:#eef;padding:4px}</style></head><body>' +
    '<p>in a paragraph: <a href="l1.html">Lone</a>, and <b><a href="l2.html">Ltwo</a></b> in bold</p>' +
    '<ul><li><a href="l3.html">Lthree</a> in a list item</li></ul>' +
    '<blockquote><a href="l4.html">Lfour</a> in a quote</blockquote>' +
    '<table><tr><td><a href="l5.html">Lfive</a></td><td><a href="l6.html">Lsix</a></td>' +
    '<td><a href="l7.html">Lseven</a></td></tr>' +
    '<tr><td colspan="1"><a href="l8.html">Leight</a></td><td>plain</td>' +
    '<td><table><tr><td><a href="l9.html">Lnine</a></td></tr></table></td></tr></table>' +
    '<div class="grid"><a class="card" href="l10.html">Lten</a>' +
    '<a class="card" href="l11.html">Leleven</a>' +
    '<a class="card" href="l12.html">Ltwelve</a></div>' +
    '<p>a link whose words <a href="l13.html">Lthirteen wraps across more than one line ' +
    'because it is long enough to need a second line of its own</a> here</p>' +
    '</body></html>';
  Names: array[0..12] of string = ('Lone', 'Ltwo', 'Lthree', 'Lfour', 'Lfive', 'Lsix',
    'Lseven', 'Leight', 'Lnine', 'Lten', 'Leleven', 'Ltwelve', 'Lthirteen');
  Wanted: array[0..12] of string = ('l1.html', 'l2.html', 'l3.html', 'l4.html', 'l5.html',
    'l6.html', 'l7.html', 'l8.html', 'l9.html', 'l10.html', 'l11.html', 'l12.html', 'l13.html');
var
  I, J, K, Reached, Missing: Integer; B: TInkPageBlock; Seen: array[0..12] of Boolean;
  Report: string;
begin
  Report := '';
  Probe.SetBounds(0, 0, 460, 400);
  Probe.LoadHTML(Doc);
  Probe.ScrollTo(0);
  for K := 0 to High(Seen) do Seen[K] := False;
  Reached := 0;

  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    Probe.BlockText(I);
    for J := 0 to B.RunCount - 1 do
      for K := 0 to High(Names) do
        if (not Seen[K]) and (Trim(B.Runs[J].Text) = Names[K]) then
        begin
          Seen[K] := True;
          Probe.ScrollTo(Max(0, B.Runs[J].Top - 40));
          Probe.Clicked := '';
          Probe.Press(B.Runs[J].Left + B.Runs[J].Width div 2,
            B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
          Probe.Let(B.Runs[J].Left + B.Runs[J].Width div 2,
            B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
          if Pos(Wanted[K], Probe.Clicked) > 0 then Inc(Reached)
          else Report := Report + Format(' %s wanted %s got "%s";',
            [Names[K], Wanted[K], Probe.Clicked]);
        end;
  end;

  Missing := 0;
  for K := 0 to High(Seen) do
    if not Seen[K] then
    begin
      Inc(Missing);
      Report := Report + ' ' + Names[K] + ' was never laid out;';
    end;
  Check(Missing = 0, 'every link is in the page:' + Report);
  Check(Reached = Length(Names),
    Format('every link answers a click (%d of %d):%s', [Reached, Length(Names), Report]));
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- clicking where the page has been scrolled, and in awkward cells --- }
procedure ScrolledLinkChecks;
var
  I, J, Y, Tries: Integer; B: TInkPageBlock; Doc: string;
begin
  { a long page with a link near the bottom: the reader scrolls to it and
    clicks it where it now is on the screen }
  Doc := '<html><body>';
  for I := 1 to 60 do Doc := Doc + '<p>paragraph number ' + IntToStr(I) + '</p>';
  Doc := Doc + '<table><tr><td>left</td><td><a href="far.html">far away</a></td></tr></table>' +
    '</body></html>';
  Probe.SetBounds(0, 0, 500, 300);
  Probe.LoadHTML(Doc);
  Probe.ScrollTo(0);

  B := nil;
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then begin B := Probe.Block(I); Probe.BlockText(I) end;
  Check(B <> nil, 'the table at the bottom is there');
  if B = nil then Exit;

  { scroll so the table is on screen, the way a reader would }
  Probe.ScrollTo(Max(0, B.Bounds.Top - 60));
  Tries := 0;
  for J := 0 to B.RunCount - 1 do
    if Pos('far', B.Runs[J].Text) > 0 then
    begin
      Inc(Tries);
      Y := B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY;
      Probe.Clicked := '';
      Probe.Press(B.Runs[J].Left + 4, Y);
      Probe.Let(B.Runs[J].Left + 4, Y);
      Check(Pos('far.html', Probe.Clicked) > 0,
        Format('a link in a scrolled table cell is clickable at y=%d ("%s")',
          [Y, Probe.Clicked]));
    end;
  Check(Tries > 0, 'the link was laid out');

  { a cell whose words sit at its bottom - the run moved, so the click has
    to move with it }
  Probe.LoadHTML('<html><head><style>td{vertical-align:bottom}</style></head><body>' +
    '<table><tr><td>tall<br>cell<br>here</td>' +
    '<td valign="bottom"><a href="low.html">low link</a></td></tr></table></body></html>');
  Probe.ScrollTo(0);
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then
    begin
      B := Probe.Block(I); Probe.BlockText(I);
      for J := 0 to B.RunCount - 1 do
        if Pos('low', B.Runs[J].Text) > 0 then
        begin
          Probe.Clicked := '';
          Probe.Press(B.Runs[J].Left + 4, B.Runs[J].Top + 4 - Probe.ScrollY);
          Probe.Let(B.Runs[J].Left + 4, B.Runs[J].Top + 4 - Probe.ScrollY);
          Check(Pos('low.html', Probe.Clicked) > 0,
            'a link in a cell that sits low is clickable ("' + Probe.Clicked + '")');
          Break;
        end;
      Break;
    end;

  { a link inside a table inside a table }
  Probe.LoadHTML('<html><body><table><tr><td>outer</td>' +
    '<td><table><tr><td>inner</td><td><a href="nested.html">deep link</a></td></tr></table>' +
    '</td></tr></table></body></html>');
  Probe.ScrollTo(0);
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then
    begin
      B := Probe.Block(I); Probe.BlockText(I);
      for J := 0 to B.RunCount - 1 do
        if Pos('deep', B.Runs[J].Text) > 0 then
        begin
          Probe.Clicked := '';
          Probe.Press(B.Runs[J].Left + 4, B.Runs[J].Top + 4 - Probe.ScrollY);
          Probe.Let(B.Runs[J].Left + 4, B.Runs[J].Top + 4 - Probe.ScrollY);
          Check(Pos('nested.html', Probe.Clicked) > 0,
            'a link in a table inside a table ("' + Probe.Clicked + '")');
          Break;
        end;
      Break;
    end;

  { and the same link after the control is made narrower, which lays the
    page out again }
  Probe.SetBounds(0, 0, 320, 300);
  Probe.ScrollTo(0);
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then
    begin
      B := Probe.Block(I); Probe.BlockText(I);
      for J := 0 to B.RunCount - 1 do
        if Pos('deep', B.Runs[J].Text) > 0 then
        begin
          Probe.Clicked := '';
          Probe.Press(B.Runs[J].Left + 4, B.Runs[J].Top + 4 - Probe.ScrollY);
          Probe.Let(B.Runs[J].Left + 4, B.Runs[J].Top + 4 - Probe.ScrollY);
          Check(Pos('nested.html', Probe.Clicked) > 0,
            'and still clickable after a resize ("' + Probe.Clicked + '")');
          Break;
        end;
      Break;
    end;
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- Back and Forward over more than two pages --- }
procedure HistoryChecks;
var
  Dir, P1, P2, P3: string; SL: TStringList; I, Deep: Integer;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'lazink-hist-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  P1 := Dir + PathDelim + 'one.html';
  P2 := Dir + PathDelim + 'two.html';
  P3 := Dir + PathDelim + 'three.html';
  SL := TStringList.Create;
  try
    SL.Text := '<html><head><title>One</title></head><body>' +
      '<p><a href="two.html">to two</a></p>' +
      '<p id="far">a place further down</p></body></html>';
    SL.SaveToFile(P1);
    SL.Text := '<html><head><title>Two</title></head><body>' +
      '<table><tr><td>plain</td><td><a href="three.html">to three</a></td></tr></table>' +
      '</body></html>';
    SL.SaveToFile(P2);
    SL.Text := '<html><head><title>Three</title></head><body><p>the end</p></body></html>';
    SL.SaveToFile(P3);
  finally SL.Free end;

  Probe.OnLinkClick := nil;
  Probe.ClearHistory;
  Probe.LoadFromFile(P1);
  Probe.ClearHistory;
  Probe.LoadFromFile(P2);
  Probe.LoadFromFile(P3);
  Check(Probe.DocumentTitle = 'Three', 'three pages deep');
  Check(Probe.CanGoBack and not Probe.CanGoForward, 'Back, and nothing forward');

  Probe.Back;
  Check(Probe.DocumentTitle = 'Two', 'Back once');
  Probe.Back;
  Check(Probe.DocumentTitle = 'One', 'Back twice');
  Check(not Probe.CanGoBack, 'and that is the first page');
  Probe.Back;
  Check(Probe.DocumentTitle = 'One', 'Back at the start does nothing');
  Probe.Forward;
  Check(Probe.DocumentTitle = 'Two', 'Forward once');
  Probe.Forward;
  Check(Probe.DocumentTitle = 'Three', 'Forward twice');
  Check(not Probe.CanGoForward, 'and that is the last');
  Probe.Forward;
  Check(Probe.DocumentTitle = 'Three', 'Forward at the end does nothing');

  { going somewhere new from the middle throws the forward pages away, the
    way every browser does }
  Probe.Back; Probe.Back;
  Check(Probe.DocumentTitle = 'One', 'back to the start');
  Probe.LoadFromFile(P3);
  Check(Probe.DocumentTitle = 'Three', 'and off somewhere new');
  Check(not Probe.CanGoForward, 'which clears Forward');
  Check(Probe.CanGoBack, 'but not Back');
  Probe.Back;
  Check(Probe.DocumentTitle = 'One', 'and Back returns where it came from');

  { a link followed from a table cell - the second column, which is where
    clicking used to do nothing }
  Probe.LoadFromFile(P2);
  Probe.ClearHistory;
  Probe.Clicked := '';
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then
    begin
      Probe.BlockText(I);
      for Deep := 0 to Probe.Block(I).RunCount - 1 do
        if Pos('three', Probe.Block(I).Runs[Deep].Text) > 0 then
        begin
          Probe.Press(Probe.Block(I).Runs[Deep].Left + 4,
            Probe.Block(I).Runs[Deep].Top + 4 - Probe.ScrollY);
          Probe.Let(Probe.Block(I).Runs[Deep].Left + 4,
            Probe.Block(I).Runs[Deep].Top + 4 - Probe.ScrollY);
          Break;
        end;
      Break;
    end;
  Check(Probe.DocumentTitle = 'Three', 'a link in a table cell navigates: ' + Probe.DocumentTitle);
  Check(Probe.CanGoBack, 'and it can be gone back from');
  Probe.Back;
  Check(Probe.DocumentTitle = 'Two', 'back to the page with the table');

  { a page the program made, rather than one from a file, comes back too }
  Probe.ClearHistory;
  Probe.LoadHTML('<html><head><title>Made up</title></head><body><p>from the program</p></body></html>');
  Probe.LoadFromFile(P1);
  Check(Probe.CanGoBack, 'a generated page is in the history');
  Probe.Back;
  Check(Probe.DocumentTitle = 'Made up',
    'and Back shows it again: ' + Probe.DocumentTitle);
  Check(Pos('from the program', Probe.PlainText) > 0, 'with its words');
  Probe.Forward;
  Check(Probe.DocumentTitle = 'One', 'and Forward returns to the file');

  { a link to a place on another page: it goes there and lands on the place }
  SL := TStringList.Create;
  try
    SL.Text := '<html><head><title>Long</title></head><body><p>top</p><p>' +
      StringOfChar('e', 60) + ' ' + StringOfChar('f', 60) + '</p>';
    for I := 1 to 60 do SL.Text := SL.Text + '<p>filler paragraph ' + IntToStr(I) + '</p>';
    SL.Text := SL.Text + '<h2 id="deep">Deep</h2><p>the deep part</p></body></html>';
    SL.SaveToFile(Dir + PathDelim + 'long.html');
    SL.Text := '<html><head><title>Jumper</title></head><body>' +
      '<p><a href="long.html#deep">to the deep part</a></p></body></html>';
    SL.SaveToFile(Dir + PathDelim + 'jump.html');
  finally SL.Free end;
  Probe.ClearHistory;
  Probe.LoadFromFile(Dir + PathDelim + 'jump.html');
  for I := 0 to Probe.BlockCount - 1 do
    if Pos('deep part', Probe.Block(I).Source) > 0 then
    begin
      Probe.BlockText(I);
      Probe.Press(Probe.Block(I).Runs[0].Left + 4, Probe.Block(I).Runs[0].Top + 4 - Probe.ScrollY);
      Probe.Let(Probe.Block(I).Runs[0].Left + 4, Probe.Block(I).Runs[0].Top + 4 - Probe.ScrollY);
      Break;
    end;
  Check(Probe.DocumentTitle = 'Long', 'a link with #anchor loads the page: ' + Probe.DocumentTitle);
  Check(Probe.ScrollY > 0, Format('and scrolls to the anchor (%d)', [Probe.ScrollY]));
  Deep := Probe.ScrollY;
  Probe.Back;
  Check(Probe.DocumentTitle = 'Jumper', 'and Back returns to the page with the link');
  Probe.Forward;
  Check(Probe.DocumentTitle = 'Long', 'Forward returns to the page');
  Check(Probe.ScrollY = Deep,
    Format('at the anchor, not the top (%d, was %d)', [Probe.ScrollY, Deep]));

  { a link to an anchor on the page already showing }
  SL := TStringList.Create;
  try
    SL.Text := '<html><head><title>Same</title></head><body>' +
      '<p><a href="#bottom">jump down</a></p>';
    for I := 1 to 60 do SL.Text := SL.Text + '<p>filler paragraph ' + IntToStr(I) + '</p>';
    SL.Text := SL.Text + '<h2 id="bottom">Bottom</h2></body></html>';
    SL.SaveToFile(Dir + PathDelim + 'same.html');
  finally SL.Free end;
  Probe.ClearHistory;
  Probe.LoadFromFile(Dir + PathDelim + 'same.html');
  Probe.ScrollTo(0);
  for I := 0 to Probe.BlockCount - 1 do
    if Pos('jump down', Probe.Block(I).Source) > 0 then
    begin
      Probe.BlockText(I);
      Probe.Press(Probe.Block(I).Runs[0].Left + 4, Probe.Block(I).Runs[0].Top + 4);
      Probe.Let(Probe.Block(I).Runs[0].Left + 4, Probe.Block(I).Runs[0].Top + 4);
      Break;
    end;
  Check(Probe.ScrollY > 0, Format('an anchor on this page scrolls to it (%d)', [Probe.ScrollY]));
  Deep := Probe.ScrollY;
  Probe.Back;
  Check(Probe.ScrollY < Deep,
    Format('and Back returns to where the reader was (%d, was %d)', [Probe.ScrollY, Deep]));

  DeleteFile(Dir + PathDelim + 'long.html'); DeleteFile(Dir + PathDelim + 'jump.html');
  DeleteFile(Dir + PathDelim + 'same.html');

  DeleteFile(P1); DeleteFile(P2); DeleteFile(P3); RemoveDir(Dir);
end;

{ --- links everywhere in a table, not just the first column --- }
procedure TableLinkChecks;
var
  I, J, K, Hits: Integer; B: TInkPageBlock; Wanted: string;
  Found: array[0..2] of Boolean;
const
  Words: array[0..2] of string = ('alpha', 'beta', 'gamma');
  Hrefs: array[0..2] of string = ('one.html', 'two.html', 'three.html');
  Cards: array[0..2] of string = ('first', 'second', 'third');
begin
  Probe.SetBounds(0, 0, 500, 300);
  Probe.LoadHTML('<html><body><table>' +
    '<tr><td><a href="one.html">alpha</a></td>' +
    '<td><a href="two.html">beta</a></td>' +
    '<td><a href="three.html">gamma</a></td></tr>' +
    '<tr><td>plain</td><td><a href="four.html">delta</a></td><td>plain</td></tr>' +
    '</table></body></html>');
  Probe.ScrollTo(0);

  { the table's block, and its runs, so the test can click where the words
    actually are rather than where it guesses they are }
  B := nil;
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Tag = 'table' then
    begin
      B := Probe.Block(I); Probe.BlockText(I); Break;
    end;
  Check(B <> nil, 'the table is a block');
  if B = nil then Exit;

  for K := 0 to 2 do Found[K] := False;
  Hits := 0;
  for J := 0 to B.RunCount - 1 do
    for K := 0 to 2 do
      if Trim(B.Runs[J].Text) = Words[K] then
      begin
        Found[K] := True;
        Probe.Clicked := '';
        Probe.Press(B.Runs[J].Left + B.Runs[J].Width div 2,
          B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
        Probe.Let(B.Runs[J].Left + B.Runs[J].Width div 2,
          B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
        Wanted := Hrefs[K];
        Check(Pos(Wanted, Probe.Clicked) > 0,
          Format('a link in column %d is clickable (wanted %s, got "%s")',
            [K + 1, Wanted, Probe.Clicked]));
        if Pos(Wanted, Probe.Clicked) > 0 then Inc(Hits);
      end;
  Check(Found[0] and Found[1] and Found[2], 'all three links were laid out');
  Check(Hits = 3, Format('every column answered (%d of 3)', [Hits]));

  { and the second row's middle cell, which is neither the first column nor
    the first row }
  for J := 0 to B.RunCount - 1 do
    if Trim(B.Runs[J].Text) = 'delta' then
    begin
      Probe.Clicked := '';
      Probe.Press(B.Runs[J].Left + B.Runs[J].Width div 2,
        B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
      Probe.Let(B.Runs[J].Left + B.Runs[J].Width div 2,
        B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
      Check(Pos('four.html', Probe.Clicked) > 0,
        'a link in the second row, middle column: "' + Probe.Clicked + '"');
    end;

  { hovering reads the same way clicking does }
  for J := 0 to B.RunCount - 1 do
    if Trim(B.Runs[J].Text) = 'gamma' then
    begin
      Wanted := Probe.LinkAt(B.Runs[J].Left + B.Runs[J].Width div 2,
        B.Runs[J].Top + B.Runs[J].Height div 2 - Probe.ScrollY);
      Check(Pos('three.html', Wanted) > 0,
        'and the pointer over it knows: "' + Wanted + '"');
    end;

  { the card index: a grid, which is laid out as a table, so a link in the
    second or third card is a link in the second or third column }
  Probe.SetBounds(0, 0, 500, 300);
  Probe.LoadHTML('<html><head><style>' +
    '.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px } ' +
    '.card { background: #eef; padding: 6px }' +
    '</style></head><body><div class="grid">' +
    '<a class="card" href="card1.html">first</a>' +
    '<a class="card" href="card2.html">second</a>' +
    '<a class="card" href="card3.html">third</a>' +
    '</div></body></html>');
  Probe.ScrollTo(0);
  Hits := 0;
  for I := 0 to Probe.BlockCount - 1 do
    if Probe.Block(I).Flex then
    begin
      Probe.BlockText(I);
      for J := 0 to Probe.Block(I).RunCount - 1 do
        for K := 0 to 2 do
          if Trim(Probe.Block(I).Runs[J].Text) = Cards[K] then
          begin
            Probe.Clicked := '';
            Probe.Press(Probe.Block(I).Runs[J].Left + 4,
              Probe.Block(I).Runs[J].Top + 4 - Probe.ScrollY);
            Probe.Let(Probe.Block(I).Runs[J].Left + 4,
              Probe.Block(I).Runs[J].Top + 4 - Probe.ScrollY);
            Check(Pos('card' + IntToStr(K + 1), Probe.Clicked) > 0,
              Format('card %d is clickable ("%s")', [K + 1, Probe.Clicked]));
            if Pos('card' + IntToStr(K + 1), Probe.Clicked) > 0 then Inc(Hits);
          end;
      Break;
    end;
  Check(Hits = 3, Format('every card answered (%d of 3)', [Hits]));
  Probe.SetBounds(0, 0, 400, 200);
end;

{ --- the palette icons the IDE shows --- }
{ a page with nothing moving on it does not run the animation tick }
{ the page's own words about size and face reach the glyphs that are drawn.
  Every one of these was broken at once, and the total height of a document
  hid it: the sizes were computed correctly and then thrown away. }
procedure InheritedTextChecks;
var I, Base, H1, H2, P1, Small: Integer; B: TInkPageBlock;
begin
  Probe.SetBounds(0, 0, 500, 400);
  Probe.LoadHTML('<html><head><style>' +
    'body { font-size: 20px; font-family: monospace; line-height: 2 }' +
    'h1 { font-size: 40px } h2 { font-size: 30px }' +
    '</style></head><body>' +
    '<h1>a heading</h1><p>a paragraph with <small>small print</small> in it</p>' +
    '<h2>another heading</h2></body></html>');
  Probe.ScrollTo(0);
  Base := 0; H1 := 0; H2 := 0; P1 := 0;
  for I := 0 to Probe.BlockCount - 1 do
  begin
    B := Probe.Block(I);
    if B.Tag = 'h1' then H1 := B.PointSize
    else if B.Tag = 'h2' then H2 := B.PointSize
    else if (B.Tag = 'p') and (P1 = 0) then
    begin
      P1 := B.PointSize; Base := B.LineHeight;
      { <small> names its size in the markup the parser emits, and the
        parser runs before any layout: it used to read a base size that was
        still nought and ask for one pixel of text }
      Small := Pos('size="-1"', B.Source);
      Check(Small = 0, 'small print is not one pixel: ' + Copy(B.Source, 1, 90));
      Check(Pos('size="-17"', B.Source) > 0,
        'small is 0.83 of the body''s twenty pixels: ' + Copy(B.Source, 1, 90));
    end;
  end;
  { body font-size is inherited - everything else is a multiple of it }
  Check(P1 = -20, Format('body font-size: 20px reaches a paragraph (%d)', [P1]));
  Check(H1 = -40, Format('and h1 keeps its own 40px (%d)', [H1]));
  Check(H2 = -30, Format('and h2 its 30px (%d)', [H2]));
  { line-height is inherited too }
  Check(Base = 40, Format('line-height: 2 on the body reaches a paragraph (%d)', [Base]));

  { and the size survives into the runs that are actually drawn, which is
    where it used to be replaced by a flat ten points }
  Probe.BlockText(0);   { asking for a block's words lays out its runs }
  B := Probe.Block(0);
  Check(B.RunCount > 0, 'the heading has runs');
  Check(B.Runs[0].FontSize = -40,
    Format('a drawn run carries the heading''s size (%d)', [B.Runs[0].FontSize]));
  { a monospace family named on the body reaches the block }
  Check(B.FaceName <> '', 'font-family on the body reaches a heading');
  Probe.SetBounds(0, 0, 400, 200);
end;

procedure AnimationTimerChecks;
var Base: string;
begin
  Base := FilenameToURI(ExpandFileName('tests/fixtures/webp/page.html'));
  Probe.LoadHTML('<html><body><p>just words</p>' +
    '<p><img src="../../../images/palette.png" alt="a still picture"></p>' +
    '</body></html>', Base);
  Probe.ScrollTo(0);
  Check(not Probe.Animating, 'a page of still pictures stops the tick');

  Probe.LoadHTML('<html><body><p>and now one that moves</p>' +
    '<p><img src="animation.webp" alt="an animated WebP"></p></body></html>', Base);
  Probe.ScrollTo(0);
  Check(Probe.Animating, 'a page with an animation runs the tick');

  Probe.LoadHTML('<html><body><p>still again</p></body></html>', Base);
  Probe.ScrollTo(0);
  Check(not Probe.Animating, 'and it stops again when the page is replaced');
end;

procedure IconChecks;
const
  Components: array[0..5] of string =
    ('TInkLabel', 'TInkEdit', 'TInkRichEdit', 'TInkMemo', 'TInkListBox', 'TInkPage');
var
  I: Integer; Res: TLResource; Stream: TStringStream; Png: TPortableNetworkGraphic;
begin
  for I := Low(Components) to High(Components) do
  begin
    { a component with no resource of its own gets Lazarus's default icon,
      which is how TInkPage looked until its own was drawn }
    Res := LazarusResources.Find(Components[I]);
    Check(Res <> nil, Components[I] + ' has a palette icon');
    if Res = nil then Continue;
    Check(Res.ValueType = 'PNG', Components[I] + ': the icon is a PNG');
    Stream := TStringStream.Create(Res.Value);
    Png := TPortableNetworkGraphic.Create;
    try
      Png.LoadFromStream(Stream);
      Check((Png.Width = 24) and (Png.Height = 24),
        Format('%s: the icon is 24x24 (%dx%d)', [Components[I], Png.Width, Png.Height]));
    finally Png.Free; Stream.Free end;
  end;
end;

{ --- find in page --- }
procedure FindChecks;
var Current, Total, K: Integer; Key: Word; Doc: string;
begin
  Doc := '<html><body><p>The cat sat.</p>';
  for K := 1 to 40 do Doc := Doc + '<p>filler ' + IntToStr(K) + '</p>';
  Doc := Doc + '<p>Another CAT, and a cat.</p></body></html>';
  Probe.LoadHTML(Doc);
  Probe.ScrollTo(0);
  Total := Probe.FindCount('cat', [], Current);
  Check((Total = 3) and (Current = 0), Format('FindCount (%d, %d)', [Total, Current]));
  Check(Probe.FindCount('cat', [ifoMatchCase], Current) = 2, 'FindCount matching case');
  Check(Probe.Find('cat'), 'Find');
  Check((Probe.SelectedText = 'cat') and (Probe.SelectionStart.Block = 0), 'finds the first');
  Probe.FindCount('cat', [], Current);
  Check(Current = 1, 'and it is the first of three');
  Check(Probe.Find('cat') and (Probe.SelectedText = 'CAT'), 'the next, whatever its case');
  Check(Probe.ScrollY > 0, 'scrolled to it');
  Check(Probe.Find('cat') and (Probe.SelectionStart.Offset > 10), 'and the next in the same block');
  Check(Probe.Find('cat') and (Probe.SelectionStart.Block = 0), 'round the end to the first');
  Check(Probe.Find('cat', [ifoBackwards]) and (Probe.SelectionStart.Offset > 10), 'backwards round the start');
  Check(Probe.Find('cat', [ifoBackwards]) and (Probe.SelectedText = 'CAT'), 'and back again');
  Check(Probe.Find('cat', [ifoMatchCase]) and (Probe.SelectedText = 'cat'), 'matching case skips CAT');
  Probe.ClearSelection;
  Probe.ScrollTo(0);
  Check(Probe.Find('cat') and (Probe.SelectionStart.Block = 0), 'from the top again');
  Key := VK_F3; Probe.KeyDown(Key, []);
  Check((Probe.SelectedText = 'CAT') and (Probe.SelectionStart.Block > 0), 'F3 finds the next');
  Key := VK_F3; Probe.KeyDown(Key, [ssShift]);
  Check(Probe.SelectionStart.Block = 0, 'Shift+F3 the one before');
  Check(not Probe.Find('dog'), 'not found');
  Check(Probe.SelectedText = 'cat', 'leaves the selection alone');

  { the find bar }
  Probe.ClearSelection;
  Key := VK_F; Probe.KeyDown(Key, [ssCtrl]);
  Check(Probe.FindBarVisible, 'Ctrl+F opens the find bar');
  Probe.FindEdit.Text := 'fill';
  Check(Probe.SelectedText = 'fill', 'typing finds: ' + Probe.SelectedText);
  K := Probe.SelectionStart.Block;
  Probe.FindEdit.Text := 'filler 2';
  Check((Probe.SelectedText = 'filler 2') and (Probe.SelectionStart.Block = K + 1),
    'and the match grows in place where it can, moving on where it must');
  Probe.FindEdit.Text := 'filler';
  Key := VK_RETURN;
  TInkEditAccess(Probe.FindEdit).KeyDown(Key, []);
  Check(Probe.SelectionStart.Block = K + 2, 'Enter goes to the next');
  Key := VK_RETURN;
  TInkEditAccess(Probe.FindEdit).KeyDown(Key, [ssShift]);
  Check(Probe.SelectionStart.Block = K + 1, 'Shift+Enter to the one before');
  Probe.FindEdit.Text := 'nowhere';
  Check(Probe.SelectedText = 'filler', 'nothing found leaves the last match');
  Key := VK_ESCAPE;
  TInkEditAccess(Probe.FindEdit).KeyDown(Key, []);
  Check(not Probe.FindBarVisible, 'Esc closes it');
  Probe.Select(Pos2(0, 4), Pos2(0, 7));
  Probe.ShowFindBar;
  Check(Probe.FindEdit.Text = 'cat', 'the find bar starts with the selection');
  Probe.HideFindBar;
end;

{ --- a finger on the page ---
  J is set by the mouse tap test before this: a release at (33, J + 3) is
  on Probe's first line, a link. }
procedure TouchChecks;
var K, Before, LinkY: Integer;
begin
  LinkY := J;
  Probe.ScrollTo(0);
  Probe.Finger(itpBegin, 100, 150, 1000);
  Probe.Finger(itpMove, 100, 120, 1300);
  Probe.Finger(itpMove, 100, 50, 1600);
  Probe.Finger(itpEnd, 100, 50, 1900);
  Check(Probe.ScrollY = 100, Format('a finger dragged up 100 px scrolls down 100 px (%d)', [Probe.ScrollY]));
  Check(not Probe.Flicking, 'a slow drag does not coast');
  { some platforms send a touch again as mouse events; that copy must not
    move the page a second time }
  Probe.Press(100, 50); Probe.MoveTo(100, 150); Probe.Let(100, 150);
  Check(Probe.ScrollY = 100, 'the mouse copy of a touch is ignored');

  Probe.ScrollTo(0);
  Probe.Clicked := '';
  Probe.Finger(itpBegin, 30, LinkY, 5000);
  Probe.Finger(itpMove, 33, LinkY + 3, 5050);
  Probe.Finger(itpEnd, 33, LinkY + 3, 5100);
  Check(Probe.Clicked <> '', 'a tap with a finger follows a link');
  Probe.Clicked := '';
  Probe.Finger(itpBegin, 30, 180, 5200);
  Probe.Finger(itpMove, 30, 100, 5500);
  Probe.Finger(itpEnd, 30, LinkY, 6100);
  Check(Probe.Clicked = '', 'a finger drag that ends on a link does not follow it');
  Probe.ScrollTo(0);
  Probe.Finger(itpBegin, 30, LinkY, 6200);
  Probe.Finger(itpCancel, 30, LinkY, 6250);
  Check(Probe.Clicked = '', 'a canceled touch is not a tap');
  Probe.Finger(itpMove, 30, LinkY - 100, 6300);
  Check(Probe.ScrollY = 0, 'nor is anything after it');

  { a flick: 70 px in 60 ms is over a thousand pixels a second }
  Probe.ScrollTo(0);
  Probe.Finger(itpBegin, 100, 190, 7000);
  Probe.Finger(itpMove, 100, 170, 7020);
  Probe.Finger(itpMove, 100, 140, 7040);
  Probe.Finger(itpEnd, 100, 120, 7060);
  Before := Probe.ScrollY;
  Check(Before = 70, Format('the flick''s own drag (%d)', [Before]));
  Check(Probe.Flicking, 'a quick flick coasts');
  Probe.Coast(50);
  Check(Probe.ScrollY > Before, 'onwards, the way the finger went');
  K := 0;
  while Probe.Flicking and (K < 1000) do begin Probe.Coast(16); Inc(K) end;
  Check(not Probe.Flicking, 'and comes to a stop');
  Check(Probe.ScrollY > Before + 100, Format('having gone a fair way (%d)', [Probe.ScrollY - Before]));
  Check(Probe.ScrollY < Probe.ContentHeight - Probe.ClientHeight, 'but not to the end');

  { a flick up the page goes up, and stops at the top }
  Probe.Finger(itpBegin, 100, 50, 8000);
  Probe.Finger(itpMove, 100, 150, 8040);
  Probe.Finger(itpEnd, 100, 180, 8060);
  Check(Probe.Flicking, 'a flick the other way');
  K := 0;
  while Probe.Flicking and (K < 1000) do begin Probe.Coast(16); Inc(K) end;
  Check(Probe.ScrollY = 0, 'stops at the top');

  { a finger on the page stops it coasting }
  Probe.Finger(itpBegin, 100, 190, 9000);
  Probe.Finger(itpEnd, 100, 120, 9050);
  Check(Probe.Flicking, 'flicking again');
  Probe.Finger(itpBegin, 100, 100, 9100);
  Check(not Probe.Flicking, 'a touch catches the page');
  Probe.Finger(itpEnd, 100, 100, 9150);

  Probe.FlickScroll := False;
  Probe.Finger(itpBegin, 100, 190, 10000);
  Probe.Finger(itpEnd, 100, 120, 10050);
  Check(not Probe.Flicking, 'FlickScroll off: no coasting');
  Probe.FlickScroll := True;

  { a mouse is a mouse: once the touch is well over, it drags again, and a
    quick mouse drag does not coast }
  Sleep(550);
  Probe.ScrollTo(0);
  Probe.Press(100, 190); Probe.MoveTo(100, 150); Probe.MoveTo(100, 100); Probe.Let(100, 100);
  Check(Probe.ScrollY = 90, Format('the mouse drags after a touch (%d)', [Probe.ScrollY]));
  Check(not Probe.Flicking, 'a mouse drag does not coast');

  {$IFDEF LCLGTK3}
  { the real thing: GTK touch events, through the hook.  They carry the
    real time, so flicking is off to keep the page where the drag left it. }
  Probe.FlickScroll := False;
  Probe.ScrollTo(0);
  Application.ProcessMessages;
  SendTouch(Probe, GDK_TOUCH_BEGIN, Pointer(1), 100, 150);
  SendTouch(Probe, GDK_TOUCH_UPDATE, Pointer(1), 100, 100);
  { a second finger is not followed }
  SendTouch(Probe, GDK_TOUCH_BEGIN, Pointer(2), 200, 150);
  SendTouch(Probe, GDK_TOUCH_UPDATE, Pointer(2), 200, 0);
  SendTouch(Probe, GDK_TOUCH_UPDATE, Pointer(1), 100, 50);
  SendTouch(Probe, GDK_TOUCH_END, Pointer(1), 100, 50);
  Check(Probe.ScrollY = 100, Format('GTK3 touch events scroll the page (%d)', [Probe.ScrollY]));
  { and a tap through GTK follows a link }
  Probe.ScrollTo(0);
  Probe.Clicked := '';
  SendTouch(Probe, GDK_TOUCH_BEGIN, Pointer(3), 33, LinkY + 3);
  SendTouch(Probe, GDK_TOUCH_END, Pointer(3), 33, LinkY + 3);
  Check(Probe.Clicked <> '', 'a GTK3 tap follows a link');
  Probe.FlickScroll := True;
  {$ENDIF}
  Sleep(550);
end;

{ what the page's scrollbar comes out as, for a given style block }
procedure StyledBar(const CSSText: string);
begin
  Probe.LoadHTML('<html><head><style>' + CSSText + '</style></head><body>' +
    Tall + '</body></html>');
  Probe.ScrollTo(0);
end;


{ Markdown to HTML contains Wanted }
procedure HasHTML(const MD, Wanted, What: string);
var H: string;
begin
  H := MarkdownToHTML(MD);
  if Pos(Wanted, H) = 0 then
    raise Exception.Create('Markdown: ' + What + LineEnding + '  wanted: ' + Wanted +
      LineEnding + '  got: ' + H);
end;

procedure LacksHTML(const MD, Unwanted, What: string);
var H: string;
begin
  H := MarkdownToHTML(MD);
  if Pos(Unwanted, H) > 0 then
    raise Exception.Create('Markdown: ' + What + LineEnding + '  unwanted: ' + Unwanted +
      LineEnding + '  got: ' + H);
end;

function FindBlock(APage: TInkPage; const Tag, Text: string): TInkPageBlock;
var K: Integer;
begin
  Result := nil;
  for K := 0 to APage.BlockCount - 1 do
    if ((Tag = '') or (APage.Block(K).Tag = Tag)) and
      (Pos(Text, HTMLPlainText(APage.Block(K).Source)) > 0) then
      Exit(APage.Block(K));
  raise Exception.Create('No ' + Tag + ' block with "' + Text + '"');
end;

procedure MarkdownChecks;
const
  E = LineEnding;
var H: string;
begin
  { headings, both forms, with GitHub's anchors }
  HasHTML('# One', '<h1 id="one">One</h1>', 'ATX h1');
  HasHTML('###### Six ###', '<h6 id="six">Six</h6>', 'ATX h6, closing hashes dropped');
  HasHTML('#NoSpace', '<p>#NoSpace</p>', 'a hash without a space is text');
  HasHTML('Big' + E + '===', '<h1 id="big">Big</h1>', 'setext h1');
  HasHTML('Less' + E + '---', '<h2 id="less">Less</h2>', 'setext h2');
  HasHTML('## Complete help pages', 'id="complete-help-pages"', 'slug');
  HasHTML('## A' + E + '## A', 'id="a-1"', 'repeated headings get numbered anchors');
  { paragraphs }
  HasHTML('one' + E + 'two' + E + E + 'three', '<p>one' + #10 + 'two</p>', 'wrapped lines join');
  HasHTML('one' + E + 'two' + E + E + 'three', '<p>three</p>', 'a blank line ends a paragraph');
  HasHTML('hard  ' + E + 'break', 'hard<br>', 'two trailing spaces break a line');
  HasHTML('hard\' + E + 'break', 'hard<br>', 'a trailing backslash breaks a line');
  LacksHTML('no' + E + 'break', '<br>', 'a plain line end is not a break');
  { emphasis }
  HasHTML('**b** __b__', '<strong>b</strong> <strong>b</strong>', 'strong');
  HasHTML('*i* _i_', '<em>i</em> <em>i</em>', 'emphasis');
  HasHTML('***both***', '<strong><em>both</em></strong>', 'strong emphasis');
  HasHTML('~~gone~~', '<del>gone</del>', 'strikethrough');
  HasHTML('snake_case_name', 'snake_case_name', 'underscores inside words stay');
  HasHTML('2 * 3 * 4', '2 * 3 * 4', 'spaced asterisks stay');
  HasHTML('*a **b** c*', '<em>a <strong>b</strong> c</em>', 'nested emphasis');
  HasHTML('\*not\*', '*not*', 'escaped asterisks');
  { code }
  HasHTML('`a<b`', '<code>a&lt;b</code>', 'code span escapes');
  HasHTML('``a ` b``', '<code>a ` b</code>', 'double-backtick code span');
  HasHTML('`**x**`', '<code>**x**</code>', 'no emphasis in code');
  HasHTML('```pascal' + E + 'if a<b then' + E + '  x := 1;' + E + '```',
    '<pre><code class="language-pascal">if a&lt;b then' + #10 + '  x := 1;' + #10 + '</code></pre>',
    'fenced code keeps its language and indentation');
  HasHTML('~~~' + E + '```' + E + '~~~', '<pre><code>```' + #10 + '</code></pre>', 'tilde fence');
  HasHTML('```' + E + 'never closed', '<pre><code>never closed', 'an unclosed fence runs to the end');
  HasHTML('para' + E + E + '    indented' + E + '    code', '<pre><code>indented' + #10 + 'code', 'indented code');
  { lists }
  H := '- **Lead.**  First line' + E + '  wraps here' + E + '  and here.' + E + '- Second';
  HasHTML(H, '<li><strong>Lead.</strong>  First line' + #10 + 'wraps here' + #10 + 'and here.</li>',
    'a bullet''s wrapped continuation lines stay in it');
  HasHTML(H, '<li>Second</li>', 'second bullet');
  HasHTML('* a' + E + '* b', '<ul>', 'star bullets');
  HasHTML('+ a' + E + '+ b', '<li>b</li>', 'plus bullets');
  HasHTML('- a' + E + 'lazy', '<li>a' + #10 + 'lazy</li>', 'lazy continuation');
  HasHTML('- a' + E + '  - b' + E + '    - c' + E + '- d',
    '<li>a' + #10 + '<ul>' + #10 + '<li>b' + #10 + '<ul>' + #10 + '<li>c</li>', 'nested lists');
  HasHTML('1. one' + E + '2. two', '<ol>' + #10 + '<li>one</li>', 'numbered list');
  HasHTML('3. three' + E + '4. four', '<ol start="3">', 'a numbered list keeps its start');
  HasHTML('- a' + E + E + '- b', '<li><p>a</p></li>', 'a loose list has paragraphs');
  HasHTML('- [ ] todo' + E + '- [x] done',
    '<li class="task-list-item"><input type="checkbox" disabled=""> todo</li>', 'open task');
  HasHTML('- [ ] todo' + E + '- [x] done', 'checked=""> done', 'finished task');
  HasHTML('text' + E + '2. not a list', '<p>text' + #10 + '2. not a list</p>',
    'only a list starting at 1 interrupts a paragraph');
  HasHTML('- a' + E + '```' + E + 'code' + E + '```', '<pre><code>code', 'code after a list');
  { links and images }
  HasHTML('[text](http://x.org "Title")', '<a href="http://x.org" title="Title">text</a>', 'inline link');
  HasHTML('[a](<b c>)', '<a href="b c">a</a>', 'angle-bracket destination');
  HasHTML('[a](u(1))', '<a href="u(1)">a</a>', 'parentheses in a destination');
  HasHTML('[ref][R]' + E + E + '[r]: http://r.org', '<a href="http://r.org">ref</a>', 'reference link');
  HasHTML('[R]' + E + E + '[r]: http://r.org', '<a href="http://r.org">R</a>', 'shortcut reference');
  LacksHTML('[r]: http://r.org', 'http://r.org', 'a definition is not shown');
  HasHTML('<https://x.org/a?b&c>', '<a href="https://x.org/a?b&amp;c">', 'autolink');
  HasHTML('<me@example.com>', 'href="mailto:me@example.com"', 'email autolink');
  HasHTML('see https://x.org/p.', '<a href="https://x.org/p">https://x.org/p</a>.', 'bare URL');
  HasHTML('(www.x.org)', '<a href="http://www.x.org">www.x.org</a>)', 'bare www address');
  HasHTML('![shot](shots/a.png)', '<img src="shots/a.png" alt="shot">', 'image');
  HasHTML('[![b](i.png)](http://x)', '<a href="http://x"><img src="i.png" alt="b"></a>', 'linked image');
  LacksHTML('[a [b](c)](d)', 'href="c"></a', 'no link in a link''s text is made twice');
  { quotes, rules }
  HasHTML('> quoted' + E + 'lazy', '<blockquote>' + #10 + '<p>quoted' + #10 + 'lazy</p>', 'blockquote');
  HasHTML('> a' + E + '> > b', '<blockquote>' + #10 + '<p>b</p>', 'nested blockquote');
  HasHTML('> [!WARNING]' + E + '> Careful.', 'markdown-alert-warning', 'GitHub alert');
  HasHTML('---', '<hr>', 'rule of dashes');
  HasHTML('* * *', '<hr>', 'rule of spaced stars');
  HasHTML('___', '<hr>', 'rule of underscores');
  { tables }
  H := '| L | C | R |' + E + '|:--|:-:|--:|' + E + '| a | b | c |';
  HasHTML(H, '<th align="left">L</th><th align="center">C</th><th align="right">R</th>', 'header alignment');
  HasHTML(H, '<td align="right">c</td>', 'cell alignment');
  HasHTML('a | b' + E + '--- | ---' + E + 'only', '<td>only</td><td></td>', 'short rows are filled');
  { HTML in Markdown }
  HasHTML('<!-- note -->' + E + '# After', '<h1', 'a comment before a heading');
  LacksHTML('<!--' + E + 'hidden' + E + '-->' + E + 'shown', 'hidden', 'multi-line comments are dropped');
  LacksHTML('a <!-- x --> b', 'x', 'inline comments are dropped');
  HasHTML('<b>x</b>', '&lt;b&gt;x&lt;/b&gt;', 'raw HTML is text by default');
  Check(Pos('<b>x</b>', MarkdownToHTML('<b>x</b>', [imoRawHTML])) > 0, 'Markdown: raw HTML when trusted');
  Check(Pos('<div>' + #10 + '<b>y</b>' + #10 + '</div>',
    MarkdownToHTML('<div>' + E + '<b>y</b>' + E + '</div>', [imoRawHTML])) > 0, 'Markdown: raw HTML block');
  HasHTML('&copy; & &#169;', '&copy; &amp; &#169;', 'entities kept, a lone ampersand escaped');
  { flattened for the inline controls }
  H := MarkdownToInk('- [x] done' + E + '- item' + E + '  - nested');
  Check(Pos('☑ done', H) > 0, 'Ink: a finished task is ticked');
  Check(Pos('• item', H) > 0, 'Ink: bullets');
  Check(Pos('<ind="20">', H) > 0, 'Ink: nested items are indented');
  H := MarkdownToInk('```' + E + 'a  b' + E + 'c' + E + '```');
  Check(Pos('a  b<br>c</font>', H) > 0, 'Ink: code keeps its spaces and lines: ' + H);
  Check(Pos('&#169;', MarkdownToInk('&#169;')) = 0, 'Ink: numeric entities are decoded');
  Check(Copy(MarkdownToInk('para'), 1, 4) = 'para', 'Ink: no break before the first line');
  Check(Pos('<br><br>', MarkdownToInk('a' + E + E + 'b')) > 0, 'Ink: paragraphs are apart');
  Check(Pos('<th><right>R', MarkdownToInk('| R |' + E + '| --: |' + E + '| 1 |')) > 0,
    'Ink: cell alignment');
end;
procedure MarkdownPageChecks(APage: TInkPage);
const
  E = LineEnding;
var
  B, B2: TInkPageBlock;
  K, J, Lines, Rules, SavedHeight: Integer;
  Doc: string;
  Styles: TStringList;
  Shot: TBitmap;
  R: TRect;
begin
  Doc :=
    '<!--' + E + '  notes for whoever edits this' + E + '-->' + E +
    '# What''s New' + E + E +
    '## v1.2' + E + E +
    '### Fixed' + E + E +
    '- **Updates no longer fail.**  GitHub only answers so many update' + E +
    '  checks an hour, and when that runs out the check was simply' + E +
    '  refused.  It now falls back to the release page.' + E +
    '- **`--offline`** starts with the network off.' + E +
    '  - nested detail' + E + E +
    '1. first' + E + '2. second' + E + E +
    '- [x] shipped' + E + E +
    '> quoted words' + E + '>' + E + '> > deeper' + E + E +
    '---' + E + E +
    '```pascal' + E + 'begin' + E + '  WriteLn(''a  b'');   // ' +
      StringOfChar('x', 300) + E + 'end.' + E + '```' + E + E +
    '## Section two' + E + E + '[back](#whats-new)' + E;
  APage.LoadMarkdown(Doc);
  Check(APage.TextFormat = itfMarkdown, 'LoadMarkdown sets the format');
  Check(APage.DocumentTitle = 'What''s New', 'a Markdown page is named by its first heading');
  Check(Pos('notes for whoever', APage.PlainText) = 0, 'the leading comment is not shown');
  Check(APage.Block(0).Tag = 'h1', 'the first block is the heading');
  Check(FindBlock(APage, 'h3', 'Fixed') <> nil, 'h3');

  B := FindBlock(APage, 'li', 'Updates no longer fail');
  Check(B.Marker = '•', 'a bullet is a marker, not part of the text');
  Check(Pos('•', B.Source) = 0, 'and not in the words');
  Check(Pos('simply refused', HTMLPlainText(B.Source)) > 0, 'wrapped continuation lines join the bullet');
  Check(B.MarkerWidth > 0, 'the marker is measured');
  Check(B.Indent > 0, 'a list is indented');
  Check(B.TextBounds.Left = B.Bounds.Left + B.Padding,
    'the words start at the indent; the marker hangs to their left');
  { the old engine wrapped by inserting <br> into the markup; this one wraps
    while it lays out, so the check is that the words really do land on more
    than one line, which is what a reader sees either way }
  Lines := 0;
  for K := 0 to APage.BlockCount - 1 do
    if APage.Block(K) = B then
    begin
      APage.BlockText(K);
      for J := 0 to B.RunCount - 1 do Lines := Max(Lines, B.Runs[J].Line);
      Break;
    end;
  Check(Lines > 0, Format('a long bullet wraps (%d lines)', [Lines + 1]));
  B2 := FindBlock(APage, 'li', 'nested detail');
  Check(B2.Marker = '◦', 'a nested bullet is a circle');
  Check(B2.Indent > B.Indent, 'and indented further');
  Check(FindBlock(APage, 'li', 'first').Marker = '1.', 'numbered item 1');
  Check(FindBlock(APage, 'li', 'second').Marker = '2.', 'numbered item 2');
  Check(FindBlock(APage, 'li', 'shipped').Marker = '☑', 'a finished task shows a ticked box');

  B := FindBlock(APage, '', 'quoted words');
  Check(Length(B.Bars) = 1, 'a quote has a bar');
  Check(Length(FindBlock(APage, '', 'deeper').Bars) = 2, 'a quote in a quote has two');
  Check(ColorToRGB(B.TextColor) <> ColorToRGB(APage.Block(0).TextColor), 'quoted text is dimmed');

  Rules := 0;
  for K := 0 to APage.BlockCount - 1 do
    if APage.Block(K).Tag = 'hr' then Inc(Rules);
  Check(Rules = 1, Format('one rule (%d)', [Rules]));

  B := FindBlock(APage, 'pre', 'WriteLn');
  Check(B.Pre, 'a fence is a code block');
  Check(Pos('WriteLn(''a  b'')', HTMLPlainText(B.Source)) > 0, 'code keeps its spaces');
  Check(Pos('  WriteLn', HTMLPlainText(B.Source)) > 0, 'and its indentation');
  Check(B.Wrapped = B.Source, 'code is never wrapped');
  Check(B.FaceName <> '', 'code is in the fixed face');
  Check(B.BackColor <> clNone, 'code has a background');
  Check(Pos('end.', HTMLPlainText(B.Source)) > 0, 'every line of code is kept');

  { the code block's background is painted, and its long line is cut off
    at the block's edge }
  APage.ScrollTo(B.Bounds.Top - 10);
  Shot := TBitmap.Create;
  try
    Shot.SetSize(APage.ClientWidth, APage.ClientHeight);
    APage.RenderTo(Shot.Canvas);
    R := B.Bounds; OffsetRect(R, 0, -APage.ScrollY);
    Check(ColorToRGB(Shot.Canvas.Pixels[R.Right - 2, R.Top + 2]) = ColorToRGB(B.BackColor),
      'the code background is painted');
    { beside the block is bare page, all the way down it }
    Rules := 0;
    for K := R.Top to R.Bottom - 1 do
      if ColorToRGB(Shot.Canvas.Pixels[R.Right + 4, K]) <> ColorToRGB(Shot.Canvas.Pixels[2, K]) then
        Inc(Rules);
    Check(Rules = 0, Format('a long line of code does not run past the block (%d)', [Rules]));
  finally Shot.Free end;

  { Font/layout changes can make this document fit the normal viewport.
    An anchor-scroll assertion needs an explicitly scrollable page. }
  SavedHeight := APage.Height;
  try
    APage.Height := 200;
    APage.ScrollTo(0);
    Check(APage.ContentHeight > APage.ClientHeight, 'anchor fixture is scrollable');
    APage.JumpToAnchor('section-two');
    Check(APage.ScrollY > 0, 'a heading''s anchor can be jumped to');
  finally APage.Height := SavedHeight end;
  Check(FindBlock(APage, 'h2', 'Section two').Anchor = 'section-two',
    'the anchor belongs to the heading, not to an empty block before it');

  { the host dresses a Markdown page; a page's own rules still win }
  Styles := TStringList.Create;
  try
    Styles.Text := 'h1 { color: #ff0000 } li { color: #00ff00 }';
    APage.StyleSheet := Styles;
    Check(ColorToRGB(FindBlock(APage, 'h1', 'New').TextColor) = RGBToColor(255, 0, 0),
      'StyleSheet colors a Markdown heading');
    Check(ColorToRGB(FindBlock(APage, 'li', 'first').TextColor) = RGBToColor(0, 255, 0),
      'and its list items');
    APage.LoadHTML('<html><head><style>h1 { color: #0000ff }</style></head><body><h1>Own</h1></body></html>');
    Check(APage.TextFormat = itfHTML, 'LoadHTML sets the format');
    Check(ColorToRGB(FindBlock(APage, 'h1', 'Own').TextColor) = RGBToColor(0, 0, 255),
      'the page''s own style wins over the host''s');
    APage.StyleSheet.Clear;
  finally Styles.Free end;

  { HTML written inside Markdown }
  APage.LoadMarkdown('a <b>b</b>');
  Check(Pos('<b>', APage.PlainText) > 0, 'raw HTML is shown as text by default');
  APage.MarkdownRawHTML := True;
  Check(Pos('<b>', APage.PlainText) = 0, 'and drawn when MarkdownRawHTML is on');
  APage.MarkdownRawHTML := False;

  { a document with images beside it, loaded from a file: run.sh runs the
    tests from the repository's root }
  APage.LoadFromFile(ExpandFileName('README.md'));
  Check(APage.TextFormat = itfMarkdown, 'a .md file is read as Markdown');
  Check(APage.DocumentTitle = 'LazInk', 'README title');
  { every picture on a line of its own - the ones in table cells show as
    their alt text - counted from the file, so a new picture needs no edit
    here }
  Styles := TStringList.Create;
  try
    Styles.LoadFromFile('README.md');
    Rules := 0;
    for K := 0 to Styles.Count - 1 do
      if Copy(Styles[K], 1, 2) = '![' then Inc(Rules);
  finally Styles.Free end;
  Check((Rules > 0) and (APage.ImageCount = Rules),
    Format('README''s images load relative to it (%d of %d)', [APage.ImageCount, Rules]));
  Check(Pos('Credits and origins', APage.PlainText) > 0, 'README text');
  Check(Pos('```', APage.PlainText) = 0, 'no fence marks are left in the README');
  Check((Pos('Status: 0.9.', APage.PlainText) > 0) and (Pos('**Status', APage.PlainText) = 0),
    'README''s bold marks are read, not shown');
  APage.JumpToAnchor('complete-help-pages');
  Check(APage.ScrollY > 0, 'README''s own contents links lead somewhere');
end;

begin
  Application.Initialize;
  TestExceptions := TTestExceptions.Create;
  Application.OnException := @TestExceptions.Handle;
  LayoutCacheChecks;
  { a failed check ends the run with its message and stack trace, instead of
    waiting behind LCL's exception dialog once the test form is showing }
  Application.CaptureExceptions := False;
  S := MarkdownToInk('# Heading'+LineEnding+'| Name | Value |'+LineEnding+
    '| --- | --- |'+LineEnding+'| **bold** | `a|b` |');
  Check(Pos('<table>',S)>0,'Markdown table');
  Check(Pos('<th>Name</th>',S)>0,'Header cells');
  Check(Pos('<b>bold</b>',S)>0,'Cell emphasis');
  Check(Pos('a|b</font>',S)>0,'Code pipes must not split cells');
  Check(Pos('&lt;script&gt;',MarkdownToInk('<script>'))>0,'Escape raw HTML');
  Check(Pos('<a href="x&amp;y">label</a>',MarkdownToInk('[label](x&y)'))>0,'Link escaping');
  { GitHub takes a single dash as a delimiter; letters are not one }
  Check(Pos('<table>',MarkdownToInk('a | b'+LineEnding+'-- | x'))=0,'Invalid delimiter row');
  Check(Pos('<table>',MarkdownToInk('a | b'+LineEnding+'- | -'))>0,'One dash is a delimiter');
  Check(Pos('a|b</td>',MarkdownToInk('a | b'+LineEnding+'--- | ---'+LineEnding+'a\|b | c'))>0,'Escaped pipes');
  Check(InkToHTML('<b>hello</b>',itfHTML)='<b>hello</b>','HTML passthrough');
  MarkdownChecks;
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
    M := TMemoProbe.Create(F); M.Parent := F; M.TextFormat := itfMarkdown;
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
    ListCopyChecks(TMemoProbe(M), List, L);
    Page.JumpToAnchor('target');
    MarkdownPageChecks(Page);

    { Dragging the page scrolls it - a touch screen has no wheel, and on
      Windows a finger arrives as a press, moves and a release.  A press
      that barely moves is still a click; a drag that ends on a link is not. }
    Probe := TPageProbe.Create(F); Probe.Parent := F; Probe.SetBounds(0,0,400,200);
    Probe.OnLinkClick := @Probe.LinkHit;
    { the mouse scrolls in these; it selects by default, tested further on }
    Probe.MouseDrag := imdScroll;
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
    TouchChecks;
    SelectionChecks;
    NavigationChecks;
    PictureChecks;
    CardTableChecks;
    NarrowChecks;
    TagChecks;
    CodeChecks;
    IconChecks;
    AnimationTimerChecks;
    InheritedTextChecks;
    BrushLeakChecks;
  InlineShadeChecks;
    ColspanChecks;
  AuthorChecks;
    TableLinkChecks;
    LinkReachChecks;
    ScrolledLinkChecks;
    HistoryChecks;
    WebPChecks;
    RunWebPChecks;
    FindChecks;

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
      'currentcolor is the text color, and body is read when html says nothing');
    Check(ColorToRGB(Probe.ScrollBar.TrackColor) = RGBToColor(1,2,3), 'rgba() with spaces');

    StyledBar('html { scrollbar-color: #ff0000 #00ff00 } body { scrollbar-color: #0000ff #0000ff }');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor(255,0,0), 'html wins over body');

    StyledBar('body { background: #000000; color: #ffffff; scrollbar-color: bogus #00ff00 }');
    Check(ColorToRGB(Probe.ScrollBar.TrackColor) = RGBToColor(0,0,0),
      'an unreadable pair is ignored: the track is the page background');
    Check(ColorToRGB(Probe.ScrollBar.ThumbColor) = RGBToColor(127,127,127),
      'and the thumb is halfway to the text color');

    StyledBar('html { scrollbar-width: none }');
    Check(not Probe.ScrollBar.Visible, 'scrollbar-width: none hides it');
    Probe.Press(100,150); Probe.MoveTo(100,50); Probe.Let(100,50);
    Check(Probe.ScrollY = 100, 'and the page still scrolls without it');

    { the bar is drawn in its colors, where it says it is }
    StyledBar('html { scrollbar-color: #ff0000 #00ff00 }');
    Shot := TBitmap.Create;
    try
      Shot.SetSize(Probe.ClientWidth, Probe.ClientHeight);
      Probe.RenderTo(Shot.Canvas);
      TR := Probe.ScrollBar.ThumbRect;
      J := Probe.ClientWidth - Probe.ScrollBar.Width;
      Check(ColorToRGB(Shot.Canvas.Pixels[J + (TR.Left + TR.Right) div 2,
        (TR.Top + TR.Bottom) div 2]) = RGBToColor(255,0,0), 'the thumb is painted in its color');
      Check(ColorToRGB(Shot.Canvas.Pixels[J + 1, Probe.ClientHeight - 3]) = RGBToColor(0,255,0),
        'the track is painted in its color');
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
    {$IFDEF LCLGTK3}
    { a finger on the bar is a click, through InkHookTouchAsMouse }
    Bar.SetParams(0, 0, 1000, 200);
    SendTouch(Bar, GDK_TOUCH_BEGIN, Pointer(4), 9, 190);
    SendTouch(Bar, GDK_TOUCH_END, Pointer(4), 9, 190);
    Check(Bar.Position = 200, Format('a tap below the thumb pages down (%d)', [Bar.Position]));
    {$ENDIF}
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
                Check((GIF.FrameCount>1) and (GIF.FrameCount=GIFFrames(GIFStream)),
                  Format('Decode all animation frames (%d)',[GIF.FrameCount]));
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
  Application.OnException := nil; TestExceptions.Free;
end.
