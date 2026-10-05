{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkCodeMemo: a plain multi-line editor — the multi-line sibling of
  TInkEdit, built on TInkRichEdit's caret, selection, wrapping and undo but
  holding the text to plain: what is typed is plain, what is pasted comes in
  as plain text, and Text/Lines carry no markup.  A notes field on a form, a
  ticket, or the demo's Markdown source.

  The one decoration it offers is the host's: OnGetCharAttrs, the same event
  TInkEdit has, asked for every character's color and style as it is drawn
  and measured — which is how the demo colors Markdown source, and how a
  program colors anything else, without the control knowing any language.

  License: 0BSD.
}
unit InkCodeMemo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, Clipbrd, LazUTF8,
  LMessages, InkRichEdit, InkEdit;

type

  { TInkCodeMemo }

  TInkCodeMemo = class(TInkRichEdit)
  private
    FLines: TStringList;
    FSettingLines: Boolean;
    FOnGetCharAttrs: TInkGetCharAttrsEvent;
    FTextHint: string;
    FTextHintColor: TColor;
    FMaxLength: Integer;
    FWantReturns: Boolean;
    FWantTabs: Boolean;
    function GetText: string;
    procedure SetText(const AValue: string);
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    procedure LinesChanged(Sender: TObject);
    procedure SetTextHint(const AValue: string);
    procedure SetTextHintColor(AValue: TColor);
    procedure SelfChanged(Sender: TObject);
    function Room: Integer;
  protected
    FOnChangePlain: TNotifyEvent;
    procedure AdjustAttr(AIndex: Integer; var A: TInkAttr); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Paint; override;
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure PasteFromClipboard; override;
  published
    { the document as plain text, and the same line by line }
    property Text: string read GetText write SetText;
    property Lines: TStrings read GetLines write SetLines;
    { the gray words an empty box shows; see TInkEdit.TextHint }
    property TextHint: string read FTextHint write SetTextHint;
    property TextHintColor: TColor read FTextHintColor write SetTextHintColor default clDefault;
    { at most this many characters, counted over the whole text; 0 is no cap }
    property MaxLength: Integer read FMaxLength write FMaxLength default 0;
    { with WantReturns off, Enter goes to the form (a dialog's default
      button); with WantTabs on, Tab indents instead of leaving the box }
    property WantReturns: Boolean read FWantReturns write FWantReturns default True;
    property WantTabs: Boolean read FWantTabs write FWantTabs default False;
    { every character's color and style, asked as it is drawn and measured -
      AIndex counts from 1 over the whole text, line breaks included }
    property OnGetCharAttrs: TInkGetCharAttrsEvent read FOnGetCharAttrs write FOnGetCharAttrs;
    { fires on every edit, after Lines has caught up }
    property OnChange: TNotifyEvent read FOnChangePlain write FOnChangePlain;
  end;

implementation

uses
  InkDraw;

constructor TInkCodeMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLines := TStringList.Create;
  FLines.OnChange := @LinesChanged;
  FTextHintColor := clDefault;
  FWantReturns := True;
  { the plain editor keeps its own change hook under the inherited one }
  inherited OnChange := @SelfChanged;
end;

destructor TInkCodeMemo.Destroy;
begin
  FLines.OnChange := nil;
  FreeAndNil(FLines);
  inherited Destroy;
end;

procedure TInkCodeMemo.SelfChanged(Sender: TObject);
begin
  if FSettingLines then Exit;
  FSettingLines := True;
  try
    FLines.Text := PlainText;
  finally
    FSettingLines := False;
  end;
  if Assigned(FOnChangePlain) then FOnChangePlain(Self);
end;

function TInkCodeMemo.GetText: string;
begin
  Result := PlainText;
end;

procedure TInkCodeMemo.SetText(const AValue: string);
var
  M: TStringList;
  S: string;
begin
  if AValue = PlainText then Exit;
  { a form filling its field is not something to undo: Markup resets the
    document and its history in one go, each line escaped so the text means
    exactly itself }
  M := TStringList.Create;
  try
    M.Text := AValue;
    FSettingLines := True;
    try
      Markup.BeginUpdate;
      try
        Markup.Clear;
        if M.Count = 0 then
          Markup.Add('')
        else
          for S in M do
            Markup.Add(HTMLEscape(S));
      finally
        Markup.EndUpdate;
      end;
      FLines.Text := AValue;
    finally
      FSettingLines := False;
    end;
  finally
    M.Free;
  end;
end;

function TInkCodeMemo.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TInkCodeMemo.SetLines(AValue: TStrings);
begin
  FLines.Assign(AValue);
end;

procedure TInkCodeMemo.LinesChanged(Sender: TObject);
begin
  if FSettingLines then Exit;
  SetText(FLines.Text);
end;

procedure TInkCodeMemo.SetTextHint(const AValue: string);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  Invalidate;
end;

procedure TInkCodeMemo.SetTextHintColor(AValue: TColor);
begin
  if FTextHintColor = AValue then Exit;
  FTextHintColor := AValue;
  Invalidate;
end;

procedure TInkCodeMemo.AdjustAttr(AIndex: Integer; var A: TInkAttr);
var
  C: TColor;
  St: TFontStyles;
  Ch: string;
begin
  { the document is plain; the host's event is the one source of looks }
  if not Assigned(FOnGetCharAttrs) then Exit;
  C := A.Color;
  if C = clDefault then C := Font.Color;
  St := A.Style;
  Ch := CharAt(AIndex);
  if Ch = '' then Exit;
  FOnGetCharAttrs(Self, AIndex + 1, Ch, C, St);
  A.Color := C;
  A.Style := St;
end;

function TInkCodeMemo.Room: Integer;
begin
  if FMaxLength <= 0 then Exit(MaxInt);
  Result := Max(0, FMaxLength - UTF8Length(PlainText) + SelLength);
end;

procedure TInkCodeMemo.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (UTF8Key <> '') and (Room < 1) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TInkCodeMemo.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Room < 1) then
  begin
    Key := 0;
    Exit;
  end;
  if (Key = VK_TAB) and FWantTabs and not (ssCtrl in Shift) then
  begin
    if Room >= 2 then InsertPlainText('  ');
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TInkCodeMemo.CMWantSpecialKey(var Message: TCMWantSpecialKey);
begin
  case Message.CharCode of
    VK_RETURN:
      if FWantReturns then
        Message.Result := 1
      else
        Message.Result := 0;    // Enter goes to the form's default button
    VK_TAB:
      if FWantTabs then
        Message.Result := 1
      else
        Message.Result := 0;    // Tab leaves the box, as a form expects
  else
    inherited;
  end;
end;

procedure TInkCodeMemo.PasteFromClipboard;
var
  S: string;
  N: Integer;
begin
  { pasting puts in plain text only, and no more than fits }
  if ReadOnly or not Clipboard.HasFormat(CF_TEXT) then Exit;
  S := Clipboard.AsText;
  N := Room;
  if N <= 0 then Exit;
  if UTF8Length(S) > N then S := UTF8Copy(S, 1, N);
  InsertPlainText(S);
end;

procedure TInkCodeMemo.Paint;
var
  W, X, TH: Integer;
  AHint: string;
  tm: TLCLTextMetric;
begin
  inherited Paint;
  if (PlainText <> '') or (FTextHint = '') then Exit;
  { the hint in the empty box, dimmed, under the caret }
  Canvas.Font := Font;
  if FTextHintColor = clDefault then
    Canvas.Font.Color := RGBToColor(
      (Red(ColorToRGB(Font.Color)) + Red(ColorToRGB(Color))) div 2,
      (Green(ColorToRGB(Font.Color)) + Green(ColorToRGB(Color))) div 2,
      (Blue(ColorToRGB(Font.Color)) + Blue(ColorToRGB(Color))) div 2)
  else
    Canvas.Font.Color := FTextHintColor;
  Canvas.Brush.Style := bsClear;
  if Canvas.GetTextMetrics(tm) then TH := tm.Height else TH := Canvas.TextHeight('Ag');
  W := ClientWidth - 8;
  AHint := FTextHint;
  if Canvas.TextWidth(AHint) > W then
  begin
    while (AHint <> '') and (Canvas.TextWidth(AHint + #$E2#$80#$A6) > W) do
      AHint := UTF8Copy(AHint, 1, UTF8Length(AHint) - 1);
    AHint := AHint + #$E2#$80#$A6;
  end;
  X := 3;
  Canvas.TextOut(X, 3 + Max(0, (TH - Canvas.TextHeight(AHint)) div 2), AHint);
end;

end.
