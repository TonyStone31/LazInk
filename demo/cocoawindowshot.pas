{ The demo's --screenshots on a Mac: the window as macOS draws it, title
  bar and shadow included. }
unit CocoaWindowShot;
{$mode objfpc}{$H+}
{$modeswitch objectivec1}
interface

uses Forms;

procedure SaveCocoaWindowScreenshot(Form: Forms.TForm; const FileName: string);

implementation

uses SysUtils, CocoaAll, CGWindow, CGGeometry, CGImage;

function HasVisibleWindow(Representation: Pointer): boolean;
var
  X, Y, Width, Height, StepX, StepY: integer;
  Pixel: Pointer;
begin
  Width := NSBitmapImageRep(Representation).pixelsWide;
  Height := NSBitmapImageRep(Representation).pixelsHigh;
  StepX := Width div 32;
  StepY := Height div 32;
  if StepX < 1 then StepX := 1;
  if StepY < 1 then StepY := 1;
  Y := 0;
  while Y < Height do
  begin
    X := 0;
    while X < Width do
    begin
      Pixel := Pointer(NSBitmapImageRep(Representation).colorAtX_y(X, Y));
      if (Pixel <> nil) and (NSColor(Pixel).alphaComponent > 0) then Exit(True);
      Inc(X, StepX);
    end;
    Inc(Y, StepY);
  end;
  Result := False;
end;

procedure SaveCocoaWindowScreenshot(Form: Forms.TForm; const FileName: string);
var
  // Keep Objective-C references opaque here: FPC 3.2.x's DWARF3 writer
  // cannot describe Objective-C class locals.
  Window: Pointer;
  Image: CGImageRef;
  Representation, Data: Pointer;
begin
  Window := Pointer(NSView(Form.Handle).window);
  if Window = nil then raise Exception.Create('The Cocoa demo window is unavailable.');
  NSApplication.sharedApplication.activateIgnoringOtherApps(True);
  NSWindow(Window).makeKeyAndOrderFront(nil);
  Application.ProcessMessages;
  Sleep(300);
  Application.ProcessMessages;
  // Capture this actual window, including its native title bar and shadow.
  Image := CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, NSWindow(Window).windowNumber, kCGWindowImageDefault);
  if Image = nil then
    raise Exception.Create('Could not capture the Cocoa window. Unlock the macOS desktop first.');
  Representation := nil;
  try
    Representation := Pointer(NSBitmapImageRep.alloc.initWithCGImage(Pointer(Image)));
    if Representation = nil then raise Exception.Create('Could not encode the Cocoa window image.');
    if not HasVisibleWindow(Representation) then
      raise Exception.Create('The Cocoa window is not visible. Unlock the macOS desktop first.');
    Data := Pointer(NSBitmapImageRep(Representation).representationUsingType_properties(NSPNGFileType, nil));
    if (Data = nil) or not NSData(Data).writeToFile_atomically(NSSTR(FileName), True) then
      raise Exception.Create('Could not save the Cocoa window screenshot: ' + FileName);
  finally
    if Representation <> nil then NSBitmapImageRep(Representation).Release;
    CGImageRelease(Image);
  end;
end;

end.
