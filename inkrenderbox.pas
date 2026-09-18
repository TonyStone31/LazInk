{ LazInk recursive renderer foundation.

  This unit is intentionally separate from InkRenderNext.  It is the
  structural experiment required by docs/RENDERER_SPEC.md section 2.1:
  layout is one recursive operation on a box subtree.  It has no HTML parser,
  no CSS parser, and no dependency on the existing renderer.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors
}
unit InkRenderBox;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, Types, Math;

type
  TInkBoxKind = (ibBlock, ibInline, ibLine, ibTable, ibRow, ibCell,
    ibRule, ibImage);
  TInkBoxVAlign = (ibBaseline, ibTop, ibMiddle, ibBottom, ibSuper, ibSub);

  TInkBoxStyle = record
    Face: string;
    Size: Integer;
    Color, BackColor: TColor;
    Styles: TFontStyles;
    VAlign: TInkBoxVAlign;
    LineHeight: Integer;
    ZIndex: Integer;
    Opacity: Byte;
    OverflowHidden: Boolean;
  end;

  TInkBoxRun = record
    Text: string;
    Style: TInkBoxStyle;
    Bounds: TRect;
    Baseline: Integer;
    Ascent, Descent: Integer;
    LinkIndex: Integer;
    Part: Integer;
  end;

  TInkBox = class;

  { How a host measures a box it owns the contents of.  A renderer keeps its
    own runs and its own wrapping; the tree only says who is measured inside
    whom, and in what width.  Return the height the box needed. }
  TInkBoxMeasureEvent = function(ABox: TInkBox; const Canvas: TCanvas;
    AWidth, AY: Integer): Integer of object;

  TInkBox = class
  private
    FKind: TInkBoxKind;
    FStyle: TInkBoxStyle;
    FChildren: array of TInkBox;
    FRuns: array of TInkBoxRun;
    FBounds: TRect;
    FClip: TRect;
    FZIndex: Integer;
    FPaintOrder: array of Integer;
    FOrderDirty, FMeasured: Boolean;
    FMeasuredWidth, FMeasuredHeight: Integer;
    FText: string;
    FImageSize: TSize;
    procedure EnsurePaintOrder;
    procedure SetZIndex(Value: Integer);
    function FontHeight(const Canvas: TCanvas; const Style: TInkBoxStyle;
      out Ascent, Descent: Integer): Integer;
    function MeasureInline(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
    function MeasureBlock(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
    function MeasureCell(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
    procedure PaintChildren(Canvas: TCanvas; const Clip: TRect;
      OffsetX, OffsetY: Integer);
  public
    { what the host put here: for InkRenderNext, the styled runs this box
      covers, as a first and last index }
    Tag, TagEnd: Integer;
    { when assigned, this is how the box is measured, instead of the
      built-in block or inline pass }
    OnMeasure: TInkBoxMeasureEvent;
    constructor Create(AKind: TInkBoxKind);
    destructor Destroy; override;
    function AddChild(AKind: TInkBoxKind): TInkBox;
    function Child(Index: Integer): TInkBox;
    function AddText(const Text: string; const Style: TInkBoxStyle): TInkBoxRun;
    function Measure(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
    procedure Paint(Canvas: TCanvas; const Clip: TRect; OffsetX, OffsetY: Integer);
    procedure Invalidate;
    function ChildCount: Integer;
    function RunCount: Integer;
    property Kind: TInkBoxKind read FKind;
    property Style: TInkBoxStyle read FStyle write FStyle;
    property Bounds: TRect read FBounds;
    property Clip: TRect read FClip;
    property Text: string read FText write FText;
    property ImageSize: TSize read FImageSize write FImageSize;
    property ZIndex: Integer read FZIndex write SetZIndex;
    property ChildCountValue: Integer read ChildCount;
    property RunCountValue: Integer read RunCount;
  end;

implementation

var
  GMetricKeys, GMetricValues: TStringList;

function BoxMetricKey(const Style: TInkBoxStyle): string;
var Bits: Integer;
begin
  Bits:=0; if fsBold in Style.Styles then Inc(Bits,1); if fsItalic in Style.Styles then Inc(Bits,2);
  if fsUnderline in Style.Styles then Inc(Bits,4); if fsStrikeOut in Style.Styles then Inc(Bits,8);
  Result:=Style.Face+#1+IntToStr(Style.Size)+#1+
    IntToStr(Bits)+#1+IntToStr(Style.LineHeight);
end;

function DefaultBoxStyle: TInkBoxStyle;
begin
  Result.Face:=''; Result.Size:=10; Result.Color:=clWindowText;
  Result.BackColor:=clNone; Result.Styles:=[]; Result.VAlign:=ibBaseline;
  Result.LineHeight:=0; Result.ZIndex:=0; Result.Opacity:=255;
  Result.OverflowHidden:=False;
end;

function InheritedBoxStyle(const Parent, Child: TInkBoxStyle): TInkBoxStyle;
begin
  Result:=Child;
  if Result.Face='' then Result.Face:=Parent.Face;
  if Result.Size<=0 then Result.Size:=Parent.Size;
  if Result.Color=clWindowText then Result.Color:=Parent.Color;
  if Result.LineHeight<=0 then Result.LineHeight:=Parent.LineHeight;
  if Result.Opacity=255 then Result.Opacity:=Parent.Opacity;
  Result.Styles:=Parent.Styles+Child.Styles;
end;

constructor TInkBox.Create(AKind: TInkBoxKind);
begin
  inherited Create; FKind:=AKind; FStyle:=DefaultBoxStyle;
  Tag:=-1; TagEnd:=-1; OnMeasure:=nil;
  FBounds:=Rect(0,0,0,0); FClip:=FBounds; FImageSize:=Size(0,0);
  FOrderDirty:=True; FMeasured:=False; FMeasuredWidth:=-1;
end;

destructor TInkBox.Destroy;
var I: Integer;
begin
  for I:=0 to High(FChildren) do FChildren[I].Free;
  inherited Destroy;
end;

function TInkBox.AddChild(AKind: TInkBoxKind): TInkBox;
var N: Integer;
begin
  N:=Length(FChildren); SetLength(FChildren,N+1);
  FChildren[N]:=TInkBox.Create(AKind); Result:=FChildren[N]; Invalidate;
end;

procedure TInkBox.Invalidate;
var I: Integer;
begin
  FMeasured:=False;
  for I:=0 to High(FChildren) do FChildren[I].Invalidate;
end;

procedure TInkBox.SetZIndex(Value: Integer);
begin
  if FZIndex=Value then Exit;
  FZIndex:=Value; FOrderDirty:=True;
end;

procedure TInkBox.EnsurePaintOrder;
var I,J,T: Integer;
begin
  if not FOrderDirty then Exit;
  SetLength(FPaintOrder,Length(FChildren));
  for I:=0 to High(FPaintOrder) do FPaintOrder[I]:=I;
  { Stable insertion sort is faster than a general sort for the small child
    lists typical of document boxes, and preserves document order on ties. }
  for I:=1 to High(FPaintOrder) do
  begin
    T:=FPaintOrder[I]; J:=I-1;
    while (J>=0) and (FChildren[FPaintOrder[J]].FZIndex>FChildren[T].FZIndex) do
    begin FPaintOrder[J+1]:=FPaintOrder[J]; Dec(J) end;
    FPaintOrder[J+1]:=T;
  end;
  FOrderDirty:=False;
end;

function TInkBox.ChildCount: Integer;
begin Result:=Length(FChildren) end;

function TInkBox.Child(Index: Integer): TInkBox;
begin Result:=FChildren[Index] end;

function TInkBox.RunCount: Integer;
begin Result:=Length(FRuns) end;

function TInkBox.AddText(const Text: string; const Style: TInkBoxStyle): TInkBoxRun;
var N: Integer;
begin
  N:=Length(FRuns); SetLength(FRuns,N+1); FRuns[N].Text:=Text;
  FRuns[N].Style:=Style; FRuns[N].Bounds:=Rect(0,0,0,0);
  FRuns[N].Baseline:=0; FRuns[N].Ascent:=0; FRuns[N].Descent:=0;
  FRuns[N].LinkIndex:=0; FRuns[N].Part:=0; Result:=FRuns[N];
end;

function TInkBox.FontHeight(const Canvas: TCanvas; const Style: TInkBoxStyle;
  out Ascent, Descent: Integer): Integer;
var Old: TFont; H,N: Integer; V: string;
begin
  N:=GMetricKeys.IndexOf(BoxMetricKey(Style));
  if N>=0 then
  begin
    V:=GMetricValues[N]; H:=StrToIntDef(Copy(V,1,Pos(',',V)-1),0);
    Ascent:=StrToIntDef(Copy(V,Pos(',',V)+1,MaxInt),0); Descent:=H-Ascent; Exit(H);
  end;
  Old:=TFont.Create; Old.Assign(Canvas.Font);
  Canvas.Font.Name:=Style.Face; Canvas.Font.Size:=Max(1,Style.Size);
  Canvas.Font.Style:=Style.Styles; H:=Canvas.TextHeight('Tg');
  { TextHeight alone is not a baseline. Approximate ascent/descent once here;
    a platform text backend can replace this without changing box layout. }
  Ascent:=Max(1,Round(H*0.78)); Descent:=Max(1,H-Ascent);
  if Style.LineHeight>0 then H:=Max(H,Style.LineHeight);
  Canvas.Font.Assign(Old); Old.Free; Result:=H;
  N:=GMetricKeys.Add(BoxMetricKey(Style)); GMetricValues.Insert(N,IntToStr(H)+','+IntToStr(Ascent));
end;

function TInkBox.MeasureInline(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
var I,P,Start,X,LineTop,LineHeight,MaxBottom,W: Integer; R: TInkBoxRun; Atom: string; A,D: Integer; SourceRuns: array of TInkBoxRun;
begin
  SourceRuns:=Copy(FRuns,0,Length(FRuns)); SetLength(FRuns,0);
  X:=FBounds.Left; LineTop:=AY; LineHeight:=0; MaxBottom:=AY;
  for I:=0 to High(SourceRuns) do
  begin
    R:=SourceRuns[I]; FontHeight(Canvas,R.Style,A,D); R.Ascent:=A; R.Descent:=D;
    P:=1;
    while P<=Length(R.Text) do
    begin
      Start:=P; while (P<=Length(R.Text)) and not (R.Text[P] in [' ',#9,#10]) do Inc(P);
      if (P=Start) and (R.Text[P] in [' ',#9]) then begin Inc(P); end;
      Atom:=Copy(R.Text,Start,P-Start); Canvas.Font.Name:=R.Style.Face;
      Canvas.Font.Size:=Max(1,R.Style.Size); Canvas.Font.Style:=R.Style.Styles;
      W:=Canvas.TextWidth(Atom);
      if (X>FBounds.Left) and (X+W>FBounds.Left+AWidth) and (Atom[1]<>' ') then
      begin
        MaxBottom:=Max(MaxBottom,LineTop+LineHeight); LineTop:=MaxBottom;
        X:=FBounds.Left; LineHeight:=0;
      end;
      R.Text:=Atom; R.Ascent:=A; R.Descent:=D; R.Baseline:=LineTop+A;
      R.Bounds:=Rect(X,R.Baseline-A,X+W,R.Baseline+D);
      if LineHeight=0 then LineHeight:=A+D;
      LineHeight:=Max(LineHeight,A+D); X:=X+W;
      SetLength(FRuns,Length(FRuns)+1); FRuns[High(FRuns)]:=R;
    end;
  end;
  MaxBottom:=Max(MaxBottom,LineTop+LineHeight); FBounds.Bottom:=MaxBottom;
  Result:=MaxBottom-AY;
end;

function TInkBox.MeasureCell(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
var I,Y,H: Integer;
begin
  FBounds:=Rect(FBounds.Left,AY,FBounds.Left+AWidth,AY);
  Y:=AY;
  for I:=0 to High(FChildren) do begin FChildren[I].FStyle:=InheritedBoxStyle(FStyle,FChildren[I].FStyle); H:=FChildren[I].Measure(Canvas,AWidth,Y); Inc(Y,H) end;
  FBounds.Bottom:=Y; Result:=Y-AY;
end;

function TInkBox.MeasureBlock(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
var I,Y,H: Integer;
begin
  FBounds:=Rect(FBounds.Left,AY,FBounds.Left+AWidth,AY); Y:=AY;
  if FKind=ibInline then Result:=MeasureInline(Canvas,AWidth,AY)
  else begin
    for I:=0 to High(FChildren) do begin FChildren[I].FStyle:=InheritedBoxStyle(FStyle,FChildren[I].FStyle); H:=FChildren[I].Measure(Canvas,AWidth,Y); Inc(Y,H) end;
    FBounds.Bottom:=Y; Result:=Y-AY;
  end;
end;

function TInkBox.Measure(const Canvas: TCanvas; AWidth, AY: Integer): Integer;
begin
  if FMeasured and (FMeasuredWidth=AWidth) and (FBounds.Top=AY) then
    Exit(FMeasuredHeight);
  if Assigned(OnMeasure) then
  begin
    { the host measures its own contents; the tree still owns the walk }
    FBounds:=Rect(FBounds.Left,AY,FBounds.Left+AWidth,AY);
    Result:=OnMeasure(Self,Canvas,AWidth,AY);
    FBounds.Bottom:=AY+Result;
    FMeasured:=True; FMeasuredWidth:=AWidth; FMeasuredHeight:=Result;
    Exit;
  end;
  case FKind of
    ibInline: Result:=MeasureInline(Canvas,AWidth,AY);
    ibCell: Result:=MeasureCell(Canvas,AWidth,AY);
    ibRule: begin FBounds:=Rect(FBounds.Left,AY,FBounds.Left+AWidth,AY+1); Result:=1 end;
    ibImage: begin FBounds:=Rect(FBounds.Left,AY,FBounds.Left+FImageSize.cx,AY+FImageSize.cy); Result:=FImageSize.cy end;
  else Result:=MeasureBlock(Canvas,AWidth,AY);
  end;
  FMeasured:=True; FMeasuredWidth:=AWidth; FMeasuredHeight:=Result;
end;

procedure TInkBox.PaintChildren(Canvas: TCanvas; const Clip: TRect; OffsetX, OffsetY: Integer);
var I: Integer; R: TInkBoxRun; D: TRect;
begin
  EnsurePaintOrder;
  for I:=0 to High(FRuns) do begin R:=FRuns[I]; D:=Rect(R.Bounds.Left+OffsetX,R.Bounds.Top+OffsetY,R.Bounds.Right+OffsetX,R.Bounds.Bottom+OffsetY); if IntersectRect(D,D,Clip) then begin Canvas.Font.Name:=R.Style.Face; Canvas.Font.Size:=R.Style.Size; Canvas.Font.Style:=R.Style.Styles; Canvas.Font.Color:=R.Style.Color; Canvas.TextOut(R.Bounds.Left+OffsetX,R.Baseline+OffsetY-R.Ascent,R.Text) end end;
  for I:=0 to High(FPaintOrder) do FChildren[FPaintOrder[I]].Paint(Canvas,Clip,OffsetX,OffsetY);
end;

procedure TInkBox.Paint(Canvas: TCanvas; const Clip: TRect; OffsetX, OffsetY: Integer);
var LocalClip: TRect;
begin
  LocalClip:=Clip; if FStyle.OverflowHidden then IntersectRect(LocalClip,LocalClip,Rect(FBounds.Left+OffsetX,FBounds.Top+OffsetY,FBounds.Right+OffsetX,FBounds.Bottom+OffsetY));
  PaintChildren(Canvas,LocalClip,OffsetX,OffsetY);
end;

initialization
  GMetricKeys:=TStringList.Create; GMetricValues:=TStringList.Create;
  GMetricKeys.Sorted:=True; GMetricKeys.CaseSensitive:=True;

finalization
  GMetricKeys.Free; GMetricValues.Free;

end.
