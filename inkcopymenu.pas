{ The right-click copy menu LazInk's display controls share.
  SPDX-License-Identifier: MIT

  Text drawn on a canvas cannot be selected by the platform, so each
  display control offers its words through this menu instead: Copy (what
  is selected), Copy this paragraph (or line, or item - whatever is under
  the pointer), Copy link address when the pointer is on one, Copy all and
  Select all.  A control that has CopyMenu switched off, or a PopupMenu of
  its own, does not show it.  OnCopyMenu lets a program add items: the menu
  is built afresh each time it opens, and the event comes after the
  standard items are in. }
unit InkCopyMenu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, StdCtrls, Menus;

resourcestring
  SInkCopy = 'Copy';
  SInkCopyAll = 'Copy all';
  SInkCopyParagraph = 'Copy this paragraph';
  SInkCopyLine = 'Copy this line';
  SInkCopyItem = 'Copy this item';
  SInkCopyLink = 'Copy link address';
  SInkSelectAll = 'Select all';

type
  { Menu has the standard items in it already; X, Y is where it opens, in
    the control's client coordinates }
  TInkCopyMenuEvent = procedure(Sender: TObject; Menu: TPopupMenu; X, Y: Integer) of object;
  TInkItemTextFunc = function(Index: Integer): string of object;

  { What the menu shows and copies.  An empty text leaves its item out,
    except Selection, whose item is shown grayed when CanSelect is set. }
  TInkCopyTexts = record
    Selection, SelectionHTML, Block, BlockCaption, Link, All: string;
    CanSelect: Boolean;
    SelectAll: TNotifyEvent;
  end;

  TInkCopyMenu = class(TComponent)
  private
    FMenu: TPopupMenu;
    FTexts: TInkCopyTexts;
    procedure CopySelection(Sender: TObject);
    procedure CopyBlock(Sender: TObject);
    procedure CopyLink(Sender: TObject);
    procedure CopyAll(Sender: TObject);
    procedure SelectAll(Sender: TObject);
    function Add(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
  public
    constructor Create(AOwner: TComponent); override;
    { fills the menu for Texts and lets the program add to it }
    procedure Build(ASender: TObject; const ATexts: TInkCopyTexts; X, Y: Integer;
      AOnMenu: TInkCopyMenuEvent);
    { Build, then open it beside the pointer }
    procedure Show(AControl: TControl; const ATexts: TInkCopyTexts; X, Y: Integer;
      AOnMenu: TInkCopyMenuEvent);
    property Menu: TPopupMenu read FMenu;
  end;

{ Text for the clipboard, with HTML beside it when there is some. }
procedure InkCopyText(const AText: string; const AHTML: string = '');

{ The text of a list box's selected items - every selected one when it is
  MultiSelect, otherwise the current one - a line each. }
function InkListSelection(AList: TCustomListBox; AText: TInkItemTextFunc): string;

implementation
uses Clipbrd;

procedure InkCopyText(const AText: string; const AHTML: string);
begin
  if AHTML <> '' then Clipboard.SetAsHtml(AHTML, AText)
  else Clipboard.AsText := AText;
end;

function InkListSelection(AList: TCustomListBox; AText: TInkItemTextFunc): string;
var I: Integer; Lines: TStringList;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    if AList.MultiSelect then
    begin
      for I := 0 to AList.Items.Count - 1 do
        if AList.Selected[I] then Lines.Add(AText(I));
    end
    else if (AList.ItemIndex >= 0) and (AList.ItemIndex < AList.Items.Count) then
      Lines.Add(AText(AList.ItemIndex));
    for I := 0 to Lines.Count - 1 do
    begin
      if I > 0 then Result := Result + LineEnding;
      Result := Result + Lines[I];
    end;
  finally Lines.Free end;
end;

constructor TInkCopyMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenu := TPopupMenu.Create(Self);
end;

function TInkCopyMenu.Add(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  FMenu.Items.Add(Result);
end;

procedure TInkCopyMenu.Build(ASender: TObject; const ATexts: TInkCopyTexts;
  X, Y: Integer; AOnMenu: TInkCopyMenuEvent);
var Item: TMenuItem;
begin
  FTexts := ATexts;
  FMenu.Items.Clear;
  if ATexts.CanSelect or (ATexts.Selection <> '') then
  begin
    Item := Add(SInkCopy, @CopySelection);
    Item.Enabled := ATexts.Selection <> '';
  end;
  if ATexts.Link <> '' then Add(SInkCopyLink, @CopyLink);
  if ATexts.Block <> '' then
  begin
    if ATexts.BlockCaption <> '' then Add(ATexts.BlockCaption, @CopyBlock)
    else Add(SInkCopyParagraph, @CopyBlock);
  end;
  if ATexts.All <> '' then Add(SInkCopyAll, @CopyAll);
  if Assigned(ATexts.SelectAll) then
  begin
    FMenu.Items.AddSeparator;
    Add(SInkSelectAll, @SelectAll);
  end;
  if Assigned(AOnMenu) then AOnMenu(ASender, FMenu, X, Y);
end;

procedure TInkCopyMenu.Show(AControl: TControl; const ATexts: TInkCopyTexts;
  X, Y: Integer; AOnMenu: TInkCopyMenuEvent);
var P: TPoint;
begin
  Build(AControl, ATexts, X, Y, AOnMenu);
  if FMenu.Items.Count = 0 then Exit;
  P := AControl.ClientToScreen(Point(X, Y));
  FMenu.PopUp(P.X, P.Y);
end;

procedure TInkCopyMenu.CopySelection(Sender: TObject);
begin
  InkCopyText(FTexts.Selection, FTexts.SelectionHTML);
end;

procedure TInkCopyMenu.CopyBlock(Sender: TObject);
begin
  InkCopyText(FTexts.Block);
end;

procedure TInkCopyMenu.CopyLink(Sender: TObject);
begin
  InkCopyText(FTexts.Link);
end;

procedure TInkCopyMenu.CopyAll(Sender: TObject);
begin
  InkCopyText(FTexts.All);
end;

procedure TInkCopyMenu.SelectAll(Sender: TObject);
begin
  if Assigned(FTexts.SelectAll) then FTexts.SelectAll(Owner);
end;

end.
