program RenderTests;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types, LCLType, LCLIntf,
  {$IFDEF LCLGTK3}LazGLib2, LazGObject2, LazGdk3, LazGtk3, gtk3widgets,{$ENDIF}
  InkScrollBar, InkHtml, InkMarkdown, InkLabel, InkMemo, InkListBox, InkPage, InkCSS, InkGIF,
  InkTouch, InkCopyMenu, InkEdit, Menus, Clipbrd;
var B: TBitmap; O: THTMLOptions; Wide, Narrow: TSize; Hit: THTMLHitInfo;
  S: string; X,Y, Found: Integer; F: TForm; M: TInkMemo; L: TInkLabel;
  List: TInkListBox; Page: TInkPage; CSS: TInkStyleSheet;
  TextOutput: TStringList;
  Files: TStringList; I, Images, Pass: Integer; GIF: TInkGIF; GIFStream: TFileStream;
  Source: TStringList; Tags: string; K, Wanted: Integer;
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

type
  { protected members, reached as a descendant would }
  TMemoAccess = class(TInkMemo);
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
procedure ListCopyChecks(AMemo: TInkMemo; AList: TInkListBox; ALabel: TInkLabel);
const
  E = LineEnding;
var
  Menu: TPopupMenu;
  R: TRect;
  Handled: Boolean;
  K: Word;
begin
  AMemo.TextFormat := itfHTML;
  AMemo.SetBounds(0, 300, 300, 150);
  AMemo.Lines.Text := '<b>first</b> line' + E + 'second <i>line</i>' + E + 'third';
  Application.ProcessMessages;
  AMemo.ItemIndex := 1;
  Check(AMemo.SelectedText = 'second line', 'memo: the current line is the selection: ' + AMemo.SelectedText);
  Clipboard.AsText := '';
  K := VK_C; TMemoAccess(AMemo).KeyDown(K, [ssCtrl]);
  Check(Clipboard.AsText = 'second line', 'memo: Ctrl+C copies it');
  K := VK_A; TMemoAccess(AMemo).KeyDown(K, [ssCtrl]);
  K := VK_C; TMemoAccess(AMemo).KeyDown(K, [ssCtrl]);
  Check(Clipboard.AsText = 'first line' + E + 'second line' + E + 'third',
    'memo: Ctrl+A then Ctrl+C copies everything: ' + Clipboard.AsText);
  K := VK_DOWN; TMemoAccess(AMemo).KeyDown(K, []);
  Check(AMemo.SelectedText <> AMemo.PlainText, 'memo: another key ends "everything"');
  R := AMemo.ItemRect(2);
  Menu := AMemo.BuildCopyMenu(R.Left + 5, R.Top + 2);
  Check(Menu.Items[0].Caption = SInkCopy, 'memo menu: Copy');
  Check(Menu.Items[1].Caption = SInkCopyLine, 'memo menu: Copy this line');
  Menu.Items[1].Click;
  Check(Clipboard.AsText = 'third', 'memo menu copies the line under the pointer: ' + Clipboard.AsText);
  Menu.Items[2].Click;
  Check(Clipboard.AsText = 'first line' + E + 'second line' + E + 'third', 'memo menu: Copy all');
  AMemo.CopyMenu := False;
  Handled := False;
  TMemoAccess(AMemo).DoContextPopup(Point(R.Left + 5, R.Top + 2), Handled);
  Check(not Handled, 'memo: CopyMenu off shows no menu');
  AMemo.CopyMenu := True;

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

function Pos2(ABlock, AOffset: Integer): TInkPagePosition;
begin
  Result.Block := ABlock;
  Result.Offset := AOffset;
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
      if Wrong < 8 then WriteLn('  k=', K, ' at=', At.Block, ':', At.Offset, ' pt=', P.X, ',', P.Y);
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
  Probe.LoadFromFile(A);
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
  K, Rules: Integer;
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
  Check(Pos('<BR>', UpperCase(B.Wrapped)) > 0, 'a long bullet wraps');
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

  APage.ScrollTo(0);
  APage.JumpToAnchor('section-two');
  Check(APage.ScrollY > 0, 'a heading''s anchor can be jumped to');
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
    ListCopyChecks(M, List, L);
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
