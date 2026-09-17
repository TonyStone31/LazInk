{ Touch input for LazInk's controls.  SPDX-License-Identifier: MIT

  Most platforms hand a finger to a program as mouse events, and there a
  control needs nothing: Windows turns a touch into a press, moves and a
  release; Qt does the same for any widget that has not asked for raw touch
  (LCL's do not); GTK2 is given pointer events by X.

  GTK3 is the exception.  The Lazarus GTK3 backend asks GDK for raw touch
  events on every window and then ignores them - and once a window has asked
  for touch, GDK stops turning fingers into mouse events for it.  So on GTK3
  a finger never reaches a control's mouse handlers at all.  InkHookTouch
  listens for those touch events on one control's own window and hands them
  to the control, in its client coordinates.

  One handler per control, not one for the program: several controls on
  several forms can each be touched.  Only the first finger down is
  followed; a second finger is ignored until the first lifts. }
unit InkTouch;
{$mode objfpc}{$H+}
interface
uses Classes, Controls;
type
  TInkTouchPhase = (itpBegin, itpMove, itpEnd, itpCancel);
  { X, Y are in the control's client coordinates }
  TInkTouchEvent = procedure(Phase: TInkTouchPhase; X, Y: Integer) of object;

{ Starts delivering touches on AControl's window to AHandler.  Call it from
  the control's CreateWnd: a recreated handle is a new window.  False where
  the platform already delivers fingers as mouse events, or cannot hook. }
function InkHookTouch(AControl: TWinControl; AHandler: TInkTouchEvent): Boolean;

{ For a control that only needs a finger to act like the left mouse button
  (an edit box, a scrollbar): touches on its window arrive as ordinary
  LCL mouse messages.  Call it from CreateWnd, as above. }
function InkHookTouchAsMouse(AControl: TWinControl): Boolean;

{ True while the mouse event being handled was made from a finger or a pen
  by the platform (Windows marks them).  Lets a control scroll for a finger
  and select for a mouse.  False where it cannot be told. }
function InkMouseIsTouch: Boolean;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF LCLGTK3}Types, LazGLib2, LazGObject2, LazGdk3, LazGtk3, gtk3widgets,{$ENDIF}
  LMessages, LCLType;

{$IFDEF WINDOWS}

function InkMouseIsTouch: Boolean;
const
  { the signature Windows puts in a mouse message's extra information when
    it was made from a pen or a touch; bit 7 set means touch }
  MI_WP_SIGNATURE = $FF515700;
  SIGNATURE_MASK = $FFFFFF00;
begin
  Result := (GetMessageExtraInfo and SIGNATURE_MASK) = MI_WP_SIGNATURE;
end;
{$ELSE}
function InkMouseIsTouch: Boolean;
begin
  Result := False;
end;
{$ENDIF}

{ what the left mouse button would have sent }
procedure SendAsMouse(AControl: TWinControl; Phase: TInkTouchPhase; X, Y: Integer);
var
  Msg: Cardinal;
  Keys: PtrInt;
begin
  Keys := MK_LBUTTON;
  case Phase of
    itpBegin: Msg := LM_LBUTTONDOWN;
    itpMove: Msg := LM_MOUSEMOVE;
  else
    begin
      Msg := LM_LBUTTONUP;
      Keys := 0;
    end;
  end;
  AControl.Perform(Msg, Keys, PtrInt(Word(SmallInt(X))) or (PtrInt(Word(SmallInt(Y))) shl 16));
end;

{$IFDEF LCLGTK3}
type
  PTouchHook = ^TTouchHook;
  TTouchHook = record
    Control: TWinControl;
    Handler: TInkTouchEvent;
    { no handler: the touch is sent on as mouse messages }
    AsMouse: Boolean;
    { the finger being followed, while one is down }
    Sequence: PGdkEventSequence;
  end;

function TouchCallback(Widget: PGtkWidget; Event: PGdkEventTouch; Data: gpointer): gboolean; cdecl;
var
  Hook: PTouchHook;
  Phase: TInkTouchPhase;
  P: TPoint;
begin
  Result := False;
  Hook := PTouchHook(Data);
  if (Event = nil) or (Hook = nil) then Exit;
  if not Hook^.AsMouse and not Assigned(Hook^.Handler) then Exit;
  case Event^.type_ of
    GDK_TOUCH_BEGIN:
      begin
        if Hook^.Sequence <> nil then Exit(True);   // a second finger
        Hook^.Sequence := Event^.sequence;
        Phase := itpBegin;
      end;
    GDK_TOUCH_UPDATE: Phase := itpMove;
    GDK_TOUCH_END: Phase := itpEnd;
    GDK_TOUCH_CANCEL: Phase := itpCancel;
  else
    Exit;
  end;
  if Event^.sequence <> Hook^.Sequence then Exit(True);
  if Phase in [itpEnd, itpCancel] then Hook^.Sequence := nil;
  try
    P := Hook^.Control.ScreenToClient(Point(Round(Event^.x_root), Round(Event^.y_root)));
    if Hook^.AsMouse then SendAsMouse(Hook^.Control, Phase, P.X, P.Y)
    else Hook^.Handler(Phase, P.X, P.Y);
  except
    { a fault in the control must not come back through GTK's event loop
      as a crash }
  end;
  Result := True;
end;

procedure FreeHook(Data: gpointer; Closure: PGClosure); cdecl;
begin
  Dispose(PTouchHook(Data));
end;

function AddHook(AControl: TWinControl; AHandler: TInkTouchEvent; AAsMouse: Boolean): Boolean;
var
  Widget: PGtkWidget;
  Hook: PTouchHook;
begin
  Result := False;
  if (AControl = nil) or not AControl.HandleAllocated then Exit;
  Widget := TGtk3Widget(AControl.Handle).GetContainerWidget;
  if Widget = nil then Exit;
  New(Hook);
  Hook^.Control := AControl;
  Hook^.Handler := AHandler;
  Hook^.AsMouse := AAsMouse;
  Hook^.Sequence := nil;
  { the hook lives as long as the window: GTK frees it with the widget }
  g_signal_connect_data(PGObject(Widget), 'touch-event',
    TGCallback(@TouchCallback), Hook, @FreeHook, G_CONNECT_DEFAULT);
  Result := True;
end;

function InkHookTouch(AControl: TWinControl; AHandler: TInkTouchEvent): Boolean;
begin
  Result := AddHook(AControl, AHandler, False);
end;

function InkHookTouchAsMouse(AControl: TWinControl): Boolean;
begin
  Result := AddHook(AControl, nil, True);
end;
{$ELSE}
function InkHookTouch(AControl: TWinControl; AHandler: TInkTouchEvent): Boolean;
begin
  Result := False;
end;

function InkHookTouchAsMouse(AControl: TWinControl): Boolean;
begin
  Result := False;
end;
{$ENDIF}

end.
