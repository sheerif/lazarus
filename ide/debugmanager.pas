{  $Id$  }
{
 /***************************************************************************
                             debugmanager.pp
                             ---------------
      TDebugManager controls all debugging related stuff in the IDE.


 ***************************************************************************/

 ***************************************************************************
 *                                                                         *
 *   This source is free software; you can redistribute it and/or modify   *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This code is distributed in the hope that it will be useful, but      *
 *   WITHOUT ANY WARRANTY; without even the implied warranty of            *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
 *   General Public License for more details.                              *
 *                                                                         *
 *   A copy of the GNU General Public License is available on the World    *
 *   Wide Web at <http://www.gnu.org/copyleft/gpl.html>. You can also      *
 *   obtain it by writing to the Free Software Foundation,                 *
 *   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.        *
 *                                                                         *
 ***************************************************************************
}
unit DebugManager;

{$mode objfpc}{$H+}

interface

{$I ide.inc}

uses
{$IFDEF IDE_MEM_CHECK}
  MemCheck,
{$ENDIF}
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, FileUtil, LCLProc,
  {$IFNDEF VER1_0}XMLCfg{$ELSE}Laz_XMLCfg{$ENDIF},
  SynEdit, CodeCache, CodeToolManager, LazConf, DebugOptionsFrm,
  CompilerOptions, EditorOptions, EnvironmentOpts, KeyMapping, UnitEditor,
  Project, IDEProcs, InputHistory, Debugger,
  IDEOptionDefs, LazarusIDEStrConsts,
  MainBar, MainIntf, MainBase, BaseDebugManager,
  SourceMarks,
  DebuggerDlg, Watchesdlg, BreakPointsdlg, LocalsDlg, WatchPropertyDlg,
  CallStackDlg, EvaluateDlg, DBGOutputForm,
  GDBMIDebugger, SSHGDBMIDebugger;


type
  TDebugDialogType = (
    ddtOutput,
    ddtBreakpoints,
    ddtWatches,
    ddtLocals,
    ddtCallStack,
    ddtEvaluate
    );
    
  TDebugManager = class(TBaseDebugManager)
    // Menu events
    procedure mnuViewDebugDialogClick(Sender: TObject);
    procedure mnuResetDebuggerClicked(Sender: TObject);
    procedure mnuDebuggerOptionsClick(Sender: TObject);

    // SrcNotebook events
    function OnSrcNotebookAddWatchesAtCursor(Sender: TObject): boolean;

    // Debugger events
    procedure OnDebuggerChangeState(ADebugger: TDebugger; OldState: TDBGState);
    procedure OnDebuggerCurrentLine(Sender: TObject;
                                    const ALocation: TDBGLocationRec);
    procedure OnDebuggerOutput(Sender: TObject; const AText: String);
    procedure OnDebuggerException(Sender: TObject; const AExceptionClass: String;
                                  const AExceptionText: String);

    // debugger dialog events
    function DebuggerDlgJumpToCodePos(Sender: TDebuggerDlg;
      const Filename: string; Line, Column: integer): TModalresult;
    procedure DebugDialogDestroy(Sender: TObject);
    function DebuggerDlgGetFullFilename(Sender: TDebuggerDlg;
      var Filename: string; AskUserIfNotFound: boolean): TModalresult;
  private
    FDebugger: TDebugger;
    FBreakPointGroups: TIDEBreakPointGroups;
    FDialogs: array[TDebugDialogType] of TDebuggerDlg;

    // When a source file is not found, the user can choose one
    // here are all choices stored
    FUserSourceFiles: TStringList;
    
    // when the debug output log is not open, store the debug log internally
    FHiddenDebugOutputLog: TStringList;
    
    procedure SetDebugger(const ADebugger: TDebugger);

    // Breakpoint routines
    procedure CreateSourceMarkForBreakPoint(const ABreakpoint: TIDEBreakPoint;
                                            ASrcEdit: TSourceEditor);
    procedure GetSourceEditorForBreakPoint(const ABreakpoint: TIDEBreakPoint;
                                           var ASrcEdit: TSourceEditor);

    // Dialog routines
    procedure ViewDebugDialog(const ADialogType: TDebugDialogType);
    procedure DestroyDebugDialog(const ADialogType: TDebugDialogType);
    procedure InitDebugOutputDlg;
    procedure InitBreakPointDlg;
    procedure InitWatchesDlg;
    procedure InitLocalsDlg;
    procedure InitCallStackDlg;
    procedure InitEvaluateDlg;

    procedure FreeDebugger;
  protected
    function  GetState: TDBGState; override;
    function  GetCommands: TDBGCommands; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure ConnectMainBarEvents; override;
    procedure ConnectSourceNotebookEvents; override;
    procedure SetupMainBarShortCuts; override;
    procedure UpdateButtonsAndMenuItems; override;

    procedure LoadProjectSpecificInfo(XMLConfig: TXMLConfig); override;
    procedure SaveProjectSpecificInfo(XMLConfig: TXMLConfig); override;
    procedure DoRestoreDebuggerMarks(AnUnitInfo: TUnitInfo); override;
    procedure ClearDebugOutputLog;

    function InitDebugger: Boolean; override;
    
    function DoPauseProject: TModalResult; override;
    function DoStepIntoProject: TModalResult; override;
    function DoStepOverProject: TModalResult; override;
    function DoRunToCursor: TModalResult; override;
    function DoStopProject: TModalResult; override;
    procedure DoToggleCallStack; override;
    procedure ProcessCommand(Command: word; var Handled: boolean); override;

    function RunDebugger: TModalResult; override;
    procedure EndDebugging; override;
    function Evaluate(const AExpression: String;
                      var AResult: String): Boolean; override;

    function DoCreateBreakPoint(const AFilename: string;
                                ALine: integer): TModalResult; override;

    function DoDeleteBreakPoint(const AFilename: string;
                                ALine: integer): TModalResult; override;
    function DoDeleteBreakPointAtMark(
                        const ASourceMark: TSourceMark): TModalResult; override;

    function ShowBreakPointProperties(const ABreakpoint: TIDEBreakPoint): TModalresult; override;
    function ShowWatchProperties(const AWatch: TIDEWatch): TModalresult; override;
  end;
  

implementation


const
  DebugDlgIDEWindow: array[TDebugDialogType] of TNonModalIDEWindow = (
    nmiwDbgOutput,  nmiwBreakPoints, nmiwWatches, nmiwLocals, nmiwCallStack,
    nmiwEvaluate
  );
  
type
  TManagedBreakPoint = class(TIDEBreakPoint)
  private
    FMaster: TDBGBreakPoint;
    FSourceMark: TSourceMark;
    procedure OnSourceMarkBeforeFree(Sender: TObject);
    procedure OnSourceMarkCreatePopupMenu(SenderMark: TSourceMark;
                                          const AddMenuItem: TAddMenuItemProc);
    procedure OnSourceMarkGetHint(SenderMark: TSourceMark; var Hint: string);
    procedure OnSourceMarkPositionChanged(Sender: TObject);
    procedure OnToggleEnableMenuItemClick(Sender: TObject);
    procedure OnDeleteMenuItemClick(Sender: TObject);
    procedure OnViewPropertiesMenuItemClick(Sender: TObject);
  protected
    procedure AssignTo(Dest: TPersistent); override;
    procedure DoChanged; override;
    function GetHitCount: Integer; override;
    function GetValid: TValidState; override;
    procedure SetEnabled(const AValue: Boolean); override;
    procedure SetInitialEnabled(const AValue: Boolean); override;
    procedure SetExpression(const AValue: String); override;
    procedure SetLocation(const ASource: String; const ALine: Integer); override;
    procedure SetSourceMark(const AValue: TSourceMark);
    procedure UpdateSourceMark;
    procedure UpdateSourceMarkImage;
    procedure UpdateSourceMarkLineColor;
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure ResetMaster;
    function GetSourceLine: integer; override;
    procedure CopySourcePositionToBreakPoint;
    property SourceMark: TSourceMark read FSourceMark write SetSourceMark;
  end;
  
  TManagedBreakPoints = class(TIDEBreakPoints)
  private
    FMaster: TDBGBreakPoints;
    FManager: TDebugManager;
    procedure SetMaster(const AValue: TDBGBreakPoints);
  protected
    procedure NotifyAdd(const ABreakPoint: TIDEBreakPoint); override;
    procedure NotifyRemove(const ABreakPoint: TIDEBreakPoint); override;
  public
    constructor Create(const AManager: TDebugManager);
    property Master: TDBGBreakPoints read FMaster write SetMaster;
  end;
  
  TManagedWatch = class(TIDEWatch)
  private
    FMaster: TDBGWatch;
  protected
    procedure AssignTo(Dest: TPersistent); override;
    function GetValid: TValidState; override;
    function GetValue: String; override;
    procedure SetEnabled(const AValue: Boolean); override;
    procedure SetExpression(const AValue: String); override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure ResetMaster;
  end;

  TManagedWatches = class(TIDEWatches)
  private
    FMaster: TDBGWatches;
    FManager: TDebugManager;
    procedure SetMaster(const AMaster: TDBGWatches);
  protected
    procedure NotifyAdd(const AWatch: TIDEWatch); override;
    procedure NotifyRemove(const AWatch: TIDEWatch); override;
  public
    constructor Create(const AManager: TDebugManager);
    property Master: TDBGWatches read FMaster write SetMaster;
  end;
  
  TManagedLocals = class(TIDELocals)
  private
    FMaster: TDBGLocals;
    procedure LocalsChanged(Sender: TObject);
    procedure SetMaster(const AMaster: TDBGLocals);
  protected
    function GetName(const AnIndex: Integer): String; override;
    function GetValue(const AnIndex: Integer): String; override;
  public
    function Count: Integer; override;
    property Master: TDBGLocals read FMaster write SetMaster;
  end;

  TManagedCallStack = class(TIDECallStack)
  private
    FMaster: TDBGCallStack;
    procedure CallStackChanged(Sender: TObject);
    procedure CallStackClear(Sender: TObject);
    procedure SetMaster(const AMaster: TDBGCallStack);
  protected
    function CheckCount: Boolean; override;
    function GetStackEntry(const AIndex: Integer): TCallStackEntry; override;
  public
    property Master: TDBGCallStack read FMaster write SetMaster;
  end;

  TManagedSignal = class(TIDESignal)
  private
    FMaster: TDBGSignal;
  protected
    procedure AssignTo(Dest: TPersistent); override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure ResetMaster;
  end;

  TManagedSignals = class(TIDESignals)
  private
    FMaster: TDBGSignals;
    FManager: TDebugManager;
    procedure SetMaster(const AValue: TDBGSignals);
  protected
  public
    constructor Create(const AManager: TDebugManager);
    property Master: TDBGSignals read FMaster write SetMaster;
  end;

  TManagedException = class(TIDEException)
  private
    FMaster: TDBGException;
  protected
    procedure DoChanged; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure ResetMaster;
  end;

  TManagedExceptions = class(TIDEExceptions)
  private
    FMaster: TDBGExceptions;
    FManager: TDebugManager;
    procedure SetMaster(const AValue: TDBGExceptions);
  protected
  public
    constructor Create(const AManager: TDebugManager);
    property Master: TDBGExceptions read FMaster write SetMaster;
  end;

{ TManagedCallStack }

procedure TManagedCallStack.CallStackChanged(Sender: TObject);
begin
  // Clear it first to force the count update
  Clear;
  NotifyChange;
end;

procedure TManagedCallStack.CallStackClear(Sender: TObject);
begin
  // Don't clear, set it to 0 so there are no entries shown
  SetCount(0);
  NotifyChange;
end;

function TManagedCallStack.CheckCount: Boolean;
begin
  Result := Master <> nil;
  if Result
  then SetCount(Master.Count);
end;

function TManagedCallStack.GetStackEntry(const AIndex: Integer): TCallStackEntry;
begin
  Assert(FMaster <> nil);
  
  Result := FMaster.GetStackEntry(AIndex);
end;

procedure TManagedCallStack.SetMaster(const AMaster: TDBGCallStack);
var
  DoNotify: Boolean;
begin
  if FMaster = AMaster then Exit;

  if FMaster <> nil
  then begin
    FMaster.OnChange := nil;
    FMaster.OnClear := nil;
    DoNotify := FMaster.Count <> 0;
  end
  else DoNotify := False;

  FMaster := AMaster;

  if FMaster = nil
  then begin
    SetCount(0);
  end
  else begin
    FMaster.OnChange := @CallStackChanged;
    FMaster.OnClear := @CallStackClear;
    DoNotify := DoNotify or (FMaster.Count <> 0);
  end;

  if DoNotify
  then NotifyChange;
end;

{ TManagedLocals }

procedure TManagedLocals.LocalsChanged(Sender: TObject);
begin
  NotifyChange;
end;

procedure TManagedLocals.SetMaster(const AMaster: TDBGLocals);
var
  DoNotify: Boolean;
begin
  if FMaster = AMaster then Exit;

  if FMaster <> nil
  then begin
    FMaster.OnChange := nil;
    DoNotify := FMaster.Count <> 0;
  end
  else DoNotify := False;

  FMaster := AMaster;
  
  if FMaster <> nil
  then begin
    FMaster.OnChange := @LocalsChanged;
    DoNotify := DoNotify or (FMaster.Count <> 0);
  end;

  if DoNotify
  then NotifyChange;
end;

function TManagedLocals.GetName(const AnIndex: Integer): String;
begin
  if Master = nil
  then Result := inherited GetName(AnIndex)
  else Result := Master.GetName(AnIndex);
end;

function TManagedLocals.GetValue(const AnIndex: Integer): String;
begin
  if Master = nil
  then Result := inherited GetValue(AnIndex)
  else Result := Master.GetValue(AnIndex);
end;

function TManagedLocals.Count: Integer;
begin
  if Master = nil
  then Result := 0
  else Result := Master.Count;
end;

{ TManagedWatch }

procedure TManagedWatch.AssignTo(Dest: TPersistent);
begin
  inherited AssignTo(Dest);
  if (TManagedWatches(GetOwner).FMaster <> nil)
  and (Dest is TDBGWatch)
  then begin
    FMaster := TDBGWatch(Dest);
    FMaster.Slave := Self;
  end;
end;

function TManagedWatch.GetValid: TValidState;
begin
  if FMaster = nil
  then Result := inherited GetValid
  else Result := FMaster.GetValid;
end;

function TManagedWatch.GetValue: String;
begin
  if FMaster = nil
  then Result := inherited GetValue
  else Result := FMaster.GetValue;
end;

procedure TManagedWatch.SetEnabled(const AValue: Boolean);
begin
  if Enabled = AValue then Exit;
  inherited SetEnabled(AValue);
  if FMaster <> nil then FMaster.Enabled := AValue;
end;

procedure TManagedWatch.SetExpression(const AValue: String);
begin
  if AValue = Expression then Exit;
  inherited SetExpression(AValue);
  if FMaster <> nil then FMaster.Expression := AValue;
end;

constructor TManagedWatch.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
end;

procedure TManagedWatch.ResetMaster;
begin
  FMaster := nil;
end;

{ TManagedWatches }

procedure TManagedWatches.SetMaster(const AMaster: TDBGWatches);
var
  n: Integer;
begin
  if FMaster = AMaster then Exit;

  FMaster := AMaster;
  if FMaster = nil
  then begin
    for n := 0 to Count - 1 do
      TManagedWatch(Items[n]).ResetMaster;
  end
  else begin
    FMaster.Assign(Self);
  end;
end;

procedure TManagedWatches.NotifyAdd(const AWatch: TIDEWatch);
var
  W: TDBGWatch;
begin
  inherited;

  if FManager.FDebugger <> nil
  then begin
    W := FManager.FDebugger.Watches.Add(AWatch.Expression);
    W.Assign(AWatch);
  end;
end;

procedure TManagedWatches.NotifyRemove(const AWatch: TIDEWatch);
begin
  inherited NotifyRemove(AWatch);
end;

constructor TManagedWatches.Create(const AManager: TDebugManager);
begin
  FMaster := nil;
  FManager := AManager;
  inherited Create(TManagedWatch);
end;

{ TManagedException }

constructor TManagedException.Create(ACollection: TCollection);
begin
  FMaster := nil;
  inherited Create(ACollection);
end;

procedure TManagedException.DoChanged;
var
  E: TDBGExceptions;
begin
  E := TManagedExceptions(GetOwner).FMaster;
  if ((FMaster = nil) = Enabled) and (E <> nil)
  then begin
    if Enabled
    then FMaster := E.Add(Name)
    else FreeAndNil(FMaster);
  end;

  inherited DoChanged;
end;

procedure TManagedException.ResetMaster;
begin
  FMaster := nil;
end;

{ TManagedExceptions }

constructor TManagedExceptions.Create(const AManager: TDebugManager);
begin
  FMaster := nil;
  FManager := AManager;
  inherited Create(TManagedException);

  Add('ECodetoolError');
  Add('EFOpenError');
end;

procedure TManagedExceptions.SetMaster(const AValue: TDBGExceptions);
var
  n: Integer;
  Item: TIDEException;
begin
  if FMaster = AValue then Exit;
  FMaster := AValue;
  if FMaster = nil
  then begin
    for n := 0 to Count - 1 do
      TManagedException(Items[n]).ResetMaster;
  end
  else begin
    // Do not assign, add only enabled exceptions
    for n := 0 to Count - 1 do
    begin
      Item := Items[n];
      if Item.Enabled
      then FMaster.Add(Item.Name);
    end;
  end;
end;

{ TManagedSignal }

procedure TManagedSignal.AssignTo (Dest: TPersistent );
begin
  inherited AssignTo(Dest);
  if (TManagedSignals(GetOwner).FMaster <> nil)
  and (Dest is TDBGSignal)
  then begin
    FMaster := TDBGSignal(Dest);
  end;
end;

constructor TManagedSignal.Create(ACollection: TCollection);
begin
  FMaster := nil;
  inherited Create(ACollection);
end;

procedure TManagedSignal.ResetMaster;
begin
  FMaster := nil;
end;

{ TManagedSignals }

constructor TManagedSignals.Create(const AManager: TDebugManager);
begin
  FMaster := nil;
  FManager := AManager;
  inherited Create(TManagedSignal);
end;

procedure TManagedSignals.SetMaster(const AValue: TDBGSignals);
var
  n: Integer;
begin
  if FMaster = AValue then Exit;
  FMaster := AValue;
  if FMaster = nil
  then begin
    for n := 0 to Count - 1 do
      TManagedSignal(Items[n]).ResetMaster;
  end
  else begin
    FMaster.Assign(Self);
  end;
end;

{ TManagedBreakPoints }

constructor TManagedBreakPoints.Create(const AManager: TDebugManager);
begin
  FMaster := nil;
  FManager := AManager;
  inherited Create(TManagedBreakPoint);
end;

procedure TManagedBreakPoints.SetMaster(const AValue: TDBGBreakPoints);
var
  n: Integer;
begin
  if FMaster = AValue then Exit;
  
  FMaster := AValue;
  if FMaster = nil
  then begin
    for n := 0 to Count - 1 do
      TManagedBreakPoint(Items[n]).ResetMaster;
  end
  else begin
    FMaster.Assign(Self);
  end;
end;

procedure TManagedBreakPoints.NotifyAdd(const ABreakPoint: TIDEBreakPoint);
var
  BP: TBaseBreakPoint;
begin
  debugln('TManagedBreakPoints.NotifyAdd A ',ABreakpoint.Source,' ',IntToStr(ABreakpoint.Line));
  ABreakpoint.InitialEnabled := True;
  ABreakpoint.Enabled := True;

  inherited;

  if FManager.FDebugger <> nil
  then begin
    BP := FManager.FDebugger.BreakPoints.Add(ABreakpoint.Source, ABreakpoint.Line);
    BP.Assign(ABreakPoint);
  end;
  FManager.CreateSourceMarkForBreakPoint(ABreakpoint,nil);
  Project1.Modified := True;
end;

procedure TManagedBreakPoints.NotifyRemove(const ABreakPoint: TIDEBreakPoint);
begin
  debugln('TManagedBreakPoints.NotifyRemove A ',ABreakpoint.Source,' ',IntToStr(ABreakpoint.Line),' ',BoolToStr(TManagedBreakPoint(ABreakpoint).SourceMark <> nil));

  inherited;

  TManagedBreakPoint(ABreakpoint).SourceMark.Free;

  if Project1 <> nil
  then Project1.Modified := True;
end;


{ TManagedBreakPoint }

procedure TManagedBreakPoint.SetSourceMark(const AValue: TSourceMark);
begin
  if FSourceMark=AValue then exit;
  if FSourceMark<>nil then begin
    FSourceMark.RemoveAllHandlersForObject(Self);
    FSourceMark.Data:=nil;
  end;
  FSourceMark:=AValue;
  if FSourceMark<>nil then begin
    FSourceMark.AddPositionChangedHandler(@OnSourceMarkPositionChanged);
    FSourceMark.AddBeforeFreeHandler(@OnSourceMarkBeforeFree);
    FSourceMark.Data:=Self;
    FSourceMark.IsBreakPoint:=true;
    FSourceMark.Line:=Line;
    FSourceMark.Visible:=true;
    FSourceMark.AddGetHintHandler(@OnSourceMarkGetHint);
    FSourceMark.AddCreatePopupMenuHandler(@OnSourceMarkCreatePopupMenu);
    UpdateSourceMark;
  end;
end;

procedure TManagedBreakPoint.OnSourceMarkPositionChanged(Sender: TObject);
begin
  Changed;
end;

procedure TManagedBreakPoint.OnToggleEnableMenuItemClick(Sender: TObject);
begin
  Enabled:=not Enabled;
  InitialEnabled:=Enabled;
end;

procedure TManagedBreakPoint.OnDeleteMenuItemClick(Sender: TObject);
begin
  Free;
end;

procedure TManagedBreakPoint.OnViewPropertiesMenuItemClick(Sender: TObject);
begin
  DebugBoss.ShowBreakPointProperties(Self);
end;

procedure TManagedBreakPoint.OnSourceMarkBeforeFree(Sender: TObject);
begin
  SourceMark:=nil;
end;

procedure TManagedBreakPoint.OnSourceMarkGetHint(SenderMark: TSourceMark;
  var Hint: string);
begin
  Hint:=GetBreakPointStateDescription(Self)+LineEnding
      +'Hitcount: '+IntToStr(Hitcount)+LineEnding
      +'Action: '+GetBreakPointActionsDescription(Self)+LineEnding
      +'Condition: '+Expression;
end;

procedure TManagedBreakPoint.OnSourceMarkCreatePopupMenu(
  SenderMark: TSourceMark; const AddMenuItem: TAddMenuItemProc);
begin
  if Enabled then
    AddMenuItem('Disable Breakpoint',true,@OnToggleEnableMenuItemClick)
  else
    AddMenuItem('Enable Breakpoint',true,@OnToggleEnableMenuItemClick);
  AddMenuItem('Delete Breakpoint',true,@OnDeleteMenuItemClick);
  AddMenuItem('View Breakpoint Properties',false,@OnViewPropertiesMenuItemClick);
  // add separator
  AddMenuItem('-',true,nil);
end;

procedure TManagedBreakPoint.AssignTo(Dest: TPersistent);
begin
  inherited AssignTo(Dest);
  if (TManagedBreakPoints(GetOwner).FMaster <> nil)
  and (Dest is TDBGBreakPoint)
  then begin
    FMaster := TDBGBreakPoint(Dest);
    FMaster.Slave := Self;
  end;
end;

constructor TManagedBreakPoint.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FMaster := nil;
end;

destructor TManagedBreakPoint.Destroy;
begin
  if FMaster <> nil
  then begin
    FMaster.Slave := nil;
    FreeAndNil(FMaster);
  end;
  inherited Destroy;
end;

procedure TManagedBreakPoint.DoChanged;
begin
  if (FMaster <> nil)
  and (FMaster.Slave = nil)
  then FMaster := nil;

  inherited DoChanged;
  UpdateSourceMark;
end;

function TManagedBreakPoint.GetHitCount: Integer;
begin
  if FMaster = nil
  then Result := 0
  else Result := FMaster.HitCount;
end;

function TManagedBreakPoint.GetValid: TValidState;
begin
  if FMaster = nil
  then Result := vsUnknown
  else Result := FMaster.Valid;
end;

procedure TManagedBreakPoint.ResetMaster;
begin
  FMaster := nil;
  Changed;
end;

function TManagedBreakPoint.GetSourceLine: integer;
begin
  if FSourceMark<>nil then
    Result:=FSourceMark.Line
  else
    Result:=inherited GetSourceLine;
end;

procedure TManagedBreakPoint.CopySourcePositionToBreakPoint;
begin
  if FSourceMark=nil then exit;
  SetLocation(Source,FSourceMark.Line);
end;

procedure TManagedBreakPoint.SetEnabled(const AValue: Boolean);
begin
  if Enabled = AValue then exit;
  inherited SetEnabled(AValue);
  if FMaster <> nil then FMaster.Enabled := AValue;
end;

procedure TManagedBreakPoint.SetInitialEnabled(const AValue: Boolean);
begin
  if InitialEnabled = AValue then exit;
  inherited SetInitialEnabled(AValue);
  if FMaster <> nil then FMaster.InitialEnabled := AValue;
end;

procedure TManagedBreakPoint.SetExpression(const AValue: String);
begin
  if AValue=Expression then exit;
  inherited SetExpression(AValue);
  if FMaster <> nil then FMaster.Expression := AValue;
end;

procedure TManagedBreakPoint.SetLocation(const ASource: String;
  const ALine: Integer);
begin
  if (Source = ASource) and (Line = ALine) then exit;
  inherited SetLocation(ASource, ALine);
  if FMaster<>nil then FMaster.SetLocation(ASource,ALine);
end;

procedure TManagedBreakPoint.UpdateSourceMarkImage;
var
  Img: Integer;
begin
  if SourceMark=nil then exit;
  case Valid of
  vsValid:
    if Enabled then
      Img:=SourceEditorMarks.ActiveBreakPointImg
    else
      Img:=SourceEditorMarks.InactiveBreakPointImg;
  vsInvalid: Img:=SourceEditorMarks.InvalidBreakPointImg;
  else
    Img:=SourceEditorMarks.UnknownBreakPointImg;
  end;
  SourceMark.ImageIndex:=Img;
end;

procedure TManagedBreakPoint.UpdateSourceMarkLineColor;
var
  aha: TAdditionalHilightAttribute;
begin
  if SourceMark=nil then exit;
  aha:=ahaNone;
  case Valid of
  vsValid:
    if Enabled then
      aha:=ahaEnabledBreakpoint
    else
      aha:=ahaDisabledBreakpoint;
  vsInvalid: aha:=ahaInvalidBreakpoint;
  else
    aha:=ahaUnknownBreakpoint;
  end;
  SourceMark.LineColorAttrib:=aha;
end;

procedure TManagedBreakPoint.UpdateSourceMark;
begin
  UpdateSourceMarkImage;
  UpdateSourceMarkLineColor;
end;


//-----------------------------------------------------------------------------
// Menu events
//-----------------------------------------------------------------------------

function TDebugManager.DebuggerDlgJumpToCodePos(Sender: TDebuggerDlg;
  const Filename: string; Line, Column: integer): TModalresult;
begin
  if not Destroying then
    Result:=MainIDE.DoJumpToSourcePosition(Filename,Column,Line,0,true)
  else
    Result:=mrCancel;
end;

function TDebugManager.DebuggerDlgGetFullFilename(Sender: TDebuggerDlg;
  var Filename: string; AskUserIfNotFound: boolean): TModalresult;
var
  SrcFile: String;
  n: Integer;
  UserFilename: string;
  OpenDialog: TOpenDialog;
begin
  Result:=mrCancel;
  if Destroying then exit;

  SrcFile := Filename;
  SrcFile := MainIDE.FindSourceFile(SrcFile,Project1.ProjectDirectory,
                      [fsfSearchForProject,fsfUseIncludePaths,fsfUseDebugPath]);
  if SrcFile = '' then SrcFile := Filename;

  if not FilenameIsAbsolute(SrcFile)
  then begin
    // first attempt to get a longer name
    // short file, look in the user list
    for n := 0 to FUserSourceFiles.Count - 1 do
    begin
      UserFilename := FUserSourceFiles[n];
      if CompareFileNames(ExtractFilenameOnly(SrcFile),
        ExtractFilenameOnly(UserFilename)) = 0
      then begin
        if FileExists(UserFilename)
        then begin
          FUserSourceFiles.Move(n, 0); // move most recent first
          SrcFile := UserFilename;
          Break;
        end;
      end;
    end;
  end;

  if ((not FilenameIsAbsolute(SrcFile)) or (not FileExists(SrcFile)))
  and AskUserIfNotFound
  then begin

    if MessageDlg(lisFileNotFound,
      Format(lisTheFileWasNotFoundDoYouWantToLocateItYourself, ['"',
        SrcFile, '"', #13, #13, #13])
      ,mtConfirmation, [mbYes, mbNo], 0) <> mrYes
    then Exit;

    repeat
      OpenDialog:=TOpenDialog.Create(nil);
      try
        InputHistories.ApplyFileDialogSettings(OpenDialog);
        OpenDialog.Title:=lisOpenFile+' '+SrcFile;
        OpenDialog.Options:=OpenDialog.Options+[ofFileMustExist];
        OpenDialog.FileName := SrcFile;
        if not OpenDialog.Execute then
          exit;
        SrcFile:=CleanAndExpandFilename(OpenDialog.FileName);
        InputHistories.StoreFileDialogSettings(OpenDialog);
      finally
        OpenDialog.Free;
      end;
    until FilenameIsAbsolute(SrcFile) and FileExists(SrcFile);

    FUserSourceFiles.Insert(0, SrcFile);
  end;
  
  if SrcFile<>'' then begin
    Filename:=SrcFile;
    Result:=mrOk;
  end;
end;

procedure TDebugManager.mnuViewDebugDialogClick(Sender: TObject);
begin                       
  ViewDebugDialog(TDebugDialogType(TMenuItem(Sender).Tag));
end;

procedure TDebugManager.mnuResetDebuggerClicked(Sender: TObject);
var
  OldState: TDBGState;
begin
  OldState := State;
  if OldState = dsNone then Exit;

  EndDebugging;
//  OnDebuggerChangeState(FDebugger, OldState);
//  InitDebugger;
end;

procedure TDebugManager.mnuDebuggerOptionsClick(Sender: TObject);
var
  DebuggerOptionsForm: TDebuggerOptionsForm;
begin
  DebuggerOptionsForm := TDebuggerOptionsForm.Create(nil);
  if DebuggerOptionsForm.ShowModal=mrOk then begin
    // save to disk
    EnvironmentOptions.Save(false);
  end;
  DebuggerOptionsForm.Free;
end;


//-----------------------------------------------------------------------------
// ScrNoteBook events
//-----------------------------------------------------------------------------

function TDebugManager.OnSrcNotebookAddWatchesAtCursor(Sender : TObject
  ): boolean;
var
  SE: TSourceEditor;
  WatchVar: String;
begin
  Result:=false;

  // get the sourceEditor.
  SE := TSourceNotebook(Sender).GetActiveSE;
  if not Assigned(SE) then Exit;
  WatchVar := SE.GetWordAtCurrentCaret;
  if WatchVar = ''  then Exit;

  if (Watches.Find(WatchVar) = nil)
  and (Watches.Add(WatchVar) = nil)
  then Exit;
  
  Result:=true;
end;

//-----------------------------------------------------------------------------
// Debugger events
//-----------------------------------------------------------------------------

procedure TDebugManager.OnDebuggerException(Sender: TObject;
  const AExceptionClass: String; const AExceptionText: String);
var
  msg: String;
begin
  if Destroying then exit;
  
  if AExceptionText = ''
  then
    msg := Format('Project %s raised exception class ''%s''.',
                  [Project1.Title, AExceptionClass])
  else
    msg := Format('Project %s raised exception class ''%s'' with message:%s%s',
                  [Project1.Title, AExceptionClass, #13, AExceptionText]);

  MessageDlg('Error', msg, mtError,[mbOk],0);
end;

procedure TDebugManager.OnDebuggerOutput(Sender: TObject; const AText: String);
begin
  if Destroying then exit;
  if FDialogs[ddtOutput] <> nil then
    TDbgOutputForm(FDialogs[ddtOutput]).AddText(AText)
  else begin
    // store it internally, and copy it to the dialog, when the user opens it
    if fHiddenDebugOutputLog=nil then
      fHiddenDebugOutputLog:=TStringList.Create;
    fHiddenDebugOutputLog.Add(AText);
    while fHiddenDebugOutputLog.Count>100 do
      fHiddenDebugOutputLog.Delete(0);
  end;
end;

procedure TDebugManager.OnDebuggerChangeState(ADebugger: TDebugger;
  OldState: TDBGState);
const
  // dsNone, dsIdle, dsStop, dsPause, dsInit, dsRun, dsError
  TOOLSTATEMAP: array[TDBGState] of TIDEToolStatus = (
    // dsNone, dsIdle, dsStop, dsPause, dsInit,     dsRun,      dsError
    itNone, itNone, itNone, itDebugger, itDebugger, itDebugger, itDebugger
  );
  STATENAME: array[TDBGState] of string = (
    'dsNone', 'dsIdle', 'dsStop', 'dsPause', 'dsInit', 'dsRun', 'dsError'
  );
var
  Editor: TSourceEditor;
begin
  if (ADebugger<>FDebugger) or (ADebugger=nil) then
    RaiseException('TDebugManager.OnDebuggerChangeState');

  if Destroying or (MainIDE=nil) or (MainIDE.ToolStatus=itExiting) then
    exit;
  
  if FDebugger.State=dsError
  then begin
    Include(FManagerStates,dmsDebuggerObjectBroken);
    if dmsInitializingDebuggerObject in FManagerStates
    then Include(FManagerStates,dmsInitializingDebuggerObjectFailed);
  end;

  DebugLn('[TDebugManager.OnDebuggerChangeState] state: ', STATENAME[FDebugger.State]);

  // All conmmands
  // -------------------
  // dcRun, dcPause, dcStop, dcStepOver, dcStepInto, dcRunTo, dcJumpto, dcBreak, dcWatch
  // -------------------

  UpdateButtonsAndMenuItems;
  if MainIDE.ToolStatus in [itNone,itDebugger]
  then MainIDE.ToolStatus := TOOLSTATEMAP[FDebugger.State];

  if (FDebugger.State in [dsRun])
  then begin
    // hide IDE during run
    if EnvironmentOptions.HideIDEOnRun
    and (MainIDE.ToolStatus=itDebugger)
    then MainIDE.HideIDE;
  end
  else begin
    if (OldState in [dsRun])
    then MainIDE.UnhideIDE;
  end;
  
  // unmark execution line
  if (FDebugger.State <> dsPause)
  and (SourceNotebook <> nil)
  then begin
    Editor := SourceNotebook.GetActiveSE;
    if Editor <> nil
    then Editor.ExecutionLine := -1;
  end;

  case FDebugger.State of 
    dsError: begin
      DebugLn('Ooops, the debugger entered the error state');
      MessageDlg(lisDebuggerError,
        Format(lisDebuggerErrorOoopsTheDebuggerEnteredTheErrorState, [#13#13,
          #13, #13#13]),
        mtError, [mbOK],0);
    end;
    dsStop: begin
      if (OldState<>dsIdle)
      then begin
        if EnvironmentOptions.DebuggerShowStopMessage then begin
        MessageDlg(lisExecutionStopped,
          Format(lisExecutionStoppedOn, [#13#13]),
          mtInformation, [mbOK],0);
        end;
        FDebugger.FileName := '';   
      end;
    end;

  end;
end;

procedure TDebugManager.OnDebuggerCurrentLine(Sender: TObject;
  const ALocation: TDBGLocationRec);
// debugger paused program due to pause or error
// -> show the current execution line in editor
// if SrcLine < 1 then no source is available
var
  SrcFile: String;
  NewSource: TCodeBuffer;
  Editor: TSourceEditor;
  SrcLine: Integer;
  i: Integer;
  StackEntry: TCallStackEntry;
begin
  if (Sender<>FDebugger) or (Sender=nil) then exit;
  if Destroying then exit;

  SrcFile:=ALocation.SrcFile;
  SrcLine:=ALocation.SrcLine;

  //TODO: Show assembler window if no source can be found.
  if SrcLine < 1
  then begin
    MessageDlg(lisExecutionPaused,
      Format(lisExecutionPausedAdress, [#13#13,
        HexStr(ALocation.Address, FDebugger.TargetWidth div 4), #13,
        ALocation.FuncName, #13, ALocation.SrcFile, #13#13#13, #13]),
      mtInformation, [mbOK],0);

    // jump to the deepest stack frame with debugging info
    i:=0;
    while (i<FDebugger.CallStack.Count) do begin
      StackEntry:=FDebugger.CallStack.Entries[i];
      if StackEntry.Line>0 then begin
        SrcLine:=StackEntry.Line;
        SrcFile:=StackEntry.Source;
        break;
      end;
      inc(i);
    end;
    if SrcLine<1 then
      Exit;
  end;
  
  if DebuggerDlgGetFullFilename(nil,SrcFile,true)<>mrOk then exit;

  NewSource:=CodeToolBoss.LoadFile(SrcFile,true,false);
  if NewSource=nil then begin
    MessageDlg(lisDebugUnableToLoadFile,
      Format(lisDebugUnableToLoadFile2, ['"', SrcFile, '"']),
      mtError,[mbCancel],0);
    exit;
  end;

  // clear old error and execution lines
  if SourceNotebook<>nil then begin
    SourceNotebook.ClearExecutionLines;
    SourceNotebook.ClearErrorLines;
  end;
  
  // jump editor to execution line
  if MainIDE.DoJumpToCodePos(nil,nil,NewSource,1,SrcLine,-1,true)<>mrOk
  then exit;

  // mark execution line
  if SourceNotebook <> nil
  then Editor := SourceNotebook.GetActiveSE
  else Editor := nil;

  if Editor <> nil
  then Editor.ExecutionLine:=SrcLine;
end;

//-----------------------------------------------------------------------------
// Debugger dialog routines
//-----------------------------------------------------------------------------

// Common handler
// The tag of the destroyed form contains the form variable pointing to it
procedure TDebugManager.DebugDialogDestroy(Sender: TObject);
var
  DlgType: TDebugDialogType;
begin
  for DlgType:=Low(TDebugDialogType) to High(TDebugDialogType) do begin
    if FDialogs[DlgType]<>Sender then continue;
    case DlgType of
    ddtOutput:
      begin
        if fHiddenDebugOutputLog=nil then
          fHiddenDebugOutputLog:=TStringList.Create;
        TDbgOutputForm(FDialogs[ddtOutput]).GetLogText(fHiddenDebugOutputLog);
      end;
    end;
    FDialogs[DlgType]:=nil;
    exit;
  end;
  RaiseException('Invalid debug window '+Sender.ClassName);
end;

procedure TDebugManager.ViewDebugDialog(const ADialogType: TDebugDialogType);
const
  DEBUGDIALOGCLASS: array[TDebugDialogType] of TDebuggerDlgClass = (
    TDbgOutputForm, TBreakPointsDlg, TWatchesDlg, TLocalsDlg, TCallStackDlg,
    TEvaluateDlg
  );
var
  CurDialog: TDebuggerDlg;
begin
  if Destroying then exit;
  if FDialogs[ADialogType] = nil
  then begin
    FDialogs[ADialogType] := DEBUGDIALOGCLASS[ADialogType].Create(Self);
    CurDialog:=FDialogs[ADialogType];
    CurDialog.Name:=NonModalIDEWindowNames[DebugDlgIDEWindow[ADialogType]];
    CurDialog.Tag := Integer(ADialogType);
    CurDialog.OnDestroy := @DebugDialogDestroy;
    CurDialog.OnJumpToCodePos:=@DebuggerDlgJumpToCodePos;
    CurDialog.OnGetFullDebugFilename:=@DebuggerDlgGetFullFilename;
    EnvironmentOptions.IDEWindowLayoutList.Apply(CurDialog,CurDialog.Name);
    case ADialogType of
      ddtOutput:      InitDebugOutputDlg;
      ddtBreakpoints: InitBreakPointDlg;
      ddtWatches:     InitWatchesDlg;
      ddtLocals:      InitLocalsDlg;
      ddtCallStack:   InitCallStackDlg;
      ddtEvaluate:    InitEvaluateDlg;
    end;
  end
  else begin
    CurDialog:=FDialogs[ADialogType];
    if (CurDialog is TBreakPointsDlg)
    then begin
      if (Project1<>nil) then
        TBreakPointsDlg(CurDialog).BaseDirectory:=Project1.ProjectDirectory;
    end;
  end;
  FDialogs[ADialogType].Show;
  FDialogs[ADialogType].BringToFront;
end;

procedure TDebugManager.DestroyDebugDialog(const ADialogType: TDebugDialogType);
begin
  if FDialogs[ADialogType] = nil then Exit;
  FDialogs[ADialogType].OnDestroy := nil;
  FDialogs[ADialogType].Free;
  FDialogs[ADialogType] := nil;
end;

procedure TDebugManager.InitDebugOutputDlg;
var
  TheDialog: TDbgOutputForm;
begin
  TheDialog := TDbgOutputForm(FDialogs[ddtOutput]);
  if FHiddenDebugOutputLog <> nil
  then begin
    TheDialog.SetLogText(FHiddenDebugOutputLog);
    FreeAndNil(FHiddenDebugOutputLog);
  end;
end;

procedure TDebugManager.InitBreakPointDlg;
var
  TheDialog: TBreakPointsDlg;
begin
  TheDialog:=TBreakPointsDlg(FDialogs[ddtBreakpoints]);
  if Project1 <> nil
  then TheDialog.BaseDirectory := Project1.ProjectDirectory;
  TheDialog.BreakPoints := FBreakPoints;
end;

procedure TDebugManager.InitWatchesDlg;
var
  TheDialog: TWatchesDlg;
begin
  TheDialog := TWatchesDlg(FDialogs[ddtWatches]);
  TheDialog.Watches := FWatches;
end;

procedure TDebugManager.InitLocalsDlg;
var
  TheDialog: TLocalsDlg;
begin
  TheDialog := TLocalsDlg(FDialogs[ddtLocals]);
  TheDialog.Locals := FLocals;
end;

procedure TDebugManager.InitCallStackDlg;
var
  TheDialog: TCallStackDlg;
begin
  TheDialog := TCallStackDlg(FDialogs[ddtCallStack]);
  TheDialog.CallStack := FCallStack;
end;

procedure TDebugManager.InitEvaluateDlg;
begin
  // todo: pass current selection
end;

constructor TDebugManager.Create(TheOwner: TComponent);
var
  DialogType: TDebugDialogType;
begin
  for DialogType := Low(TDebugDialogType) to High(TDebugDialogType) do
    FDialogs[DialogType] := nil; 

  FDebugger := nil;
  FBreakPoints := TManagedBreakPoints.Create(Self);
  FBreakPointGroups := TIDEBreakPointGroups.Create;

  FWatches := TManagedWatches.Create(Self);
  FExceptions := TManagedExceptions.Create(Self);
  FSignals := TManagedSignals.Create(Self);
  FLocals := TManagedLocals.Create;
  FCallStack := TManagedCallStack.Create;

  FUserSourceFiles := TStringList.Create;
  
  inherited Create(TheOwner);
end;

destructor TDebugManager.Destroy;
var
  DialogType: TDebugDialogType;
begin                          
  FDestroying:=true;
  
  for DialogType := Low(TDebugDialogType) to High(TDebugDialogType) do 
    DestroyDebugDialog(DialogType);
  
  SetDebugger(nil);

  FreeAndNil(FWatches);
  FreeAndNil(FBreakPoints);
  FreeAndNil(FBreakPointGroups);
  FreeAndNil(FCallStack);
  FreeAndNil(FExceptions);
  FreeAndNil(FSignals);
  FreeAndNil(FLocals);

  FreeAndNil(FUserSourceFiles);
  FreeAndNil(FHiddenDebugOutputLog);

  inherited Destroy;
end;

procedure TDebugManager.ConnectMainBarEvents;
begin
  with MainIDEBar do begin
    itmViewWatches.OnClick := @mnuViewDebugDialogClick;
    itmViewWatches.Tag := Ord(ddtWatches);
    itmViewBreakPoints.OnClick := @mnuViewDebugDialogClick;
    itmViewBreakPoints.Tag := Ord(ddtBreakPoints);
    itmViewLocals.OnClick := @mnuViewDebugDialogClick;
    itmViewLocals.Tag := Ord(ddtLocals);
    itmViewCallStack.OnClick := @mnuViewDebugDialogClick;
    itmViewCallStack.Tag := Ord(ddtCallStack);
    itmViewDebugOutput.OnClick := @mnuViewDebugDialogClick;
    itmViewDebugOutput.Tag := Ord(ddtOutput);

    itmRunMenuResetDebugger.OnClick := @mnuResetDebuggerClicked;

//    itmRunMenuInspect.OnClick := @mnuViewDebugDialogClick;
    itmRunMenuEvaluate.OnClick := @mnuViewDebugDialogClick;
    itmRunMenuEvaluate.Tag := Ord(ddtEvaluate);
//    itmRunMenuAddWatch.OnClick := @;
//    itmRunMenuAddBpSource.OnClick := @;

    itmEnvDebuggerOptions.OnClick := @mnuDebuggerOptionsClick;
  end;
end;

procedure TDebugManager.ConnectSourceNotebookEvents;
begin
  SourceNotebook.OnAddWatchAtCursor := @OnSrcNotebookAddWatchesAtCursor;
end;

procedure TDebugManager.SetupMainBarShortCuts;
begin
  with MainIDEBar, EditorOpts.KeyMap do
  begin
    itmViewWatches.ShortCut := CommandToShortCut(ecToggleWatches);
    itmViewBreakpoints.ShortCut := CommandToShortCut(ecToggleBreakPoints);
    itmViewDebugOutput.ShortCut := CommandToShortCut(ecToggleDebuggerOut);
    itmViewLocals.ShortCut := CommandToShortCut(ecToggleLocals);
    itmViewCallStack.ShortCut := CommandToShortCut(ecToggleCallStack);
    
    itmRunMenuInspect.ShortCut := CommandToShortCut(ecInspect);
    itmRunMenuEvaluate.ShortCut := CommandToShortCut(ecEvaluate);
    itmRunMenuAddWatch.ShortCut := CommandToShortCut(ecAddWatch);
  end;
end;

procedure TDebugManager.UpdateButtonsAndMenuItems;
var
  DebuggerInvalid: boolean;
begin
  DebuggerInvalid:=(FDebugger=nil) or (MainIDE.ToolStatus<>itDebugger);
  with MainIDEBar do begin
    // For 'run' and 'step' bypass 'idle', so we can set the filename later
    RunSpeedButton.Enabled := DebuggerInvalid
                 or (dcRun in FDebugger.Commands) or (FDebugger.State = dsIdle);
    itmRunMenuRun.Enabled := RunSpeedButton.Enabled;
    PauseSpeedButton.Enabled := (not DebuggerInvalid)
                                and (dcPause in FDebugger.Commands);
    itmRunMenuPause.Enabled := PauseSpeedButton.Enabled;
    StepIntoSpeedButton.Enabled := DebuggerInvalid
            or (dcStepInto in FDebugger.Commands) or (FDebugger.State = dsIdle);
    itmRunMenuStepInto.Enabled := StepIntoSpeedButton.Enabled;
    StepOverSpeedButton.Enabled := DebuggerInvalid or
              (dcStepOver in FDebugger.Commands)  or (FDebugger.State = dsIdle);
    itmRunMenuStepOver.Enabled := StepOverSpeedButton.Enabled;

    itmRunMenuRunToCursor.Enabled := DebuggerInvalid
                                     or (dcRunTo in FDebugger.Commands);
    itmRunMenuStop.Enabled := (FDebugger<>nil); // always allow to stop

    itmRunMenuEvaluate.Enabled := (not DebuggerInvalid)
                              and (dcEvaluate in FDebugger.Commands);
    // TODO: add other debugger menuitems
    // TODO: implement by actions
  end;
end;

{------------------------------------------------------------------------------
  procedure TDebugManager.LoadProjectSpecificInfo(XMLConfig: TXMLConfig);

  Called when the main project is loaded from the XMLConfig.
------------------------------------------------------------------------------}
procedure TDebugManager.LoadProjectSpecificInfo(XMLConfig: TXMLConfig);
begin
  FBreakPointGroups.LoadFromXMLConfig(XMLConfig,
                                     'Debugging/'+XMLBreakPointGroupsNode+'/');
  FBreakPoints.LoadFromXMLConfig(XMLConfig,'Debugging/'+XMLBreakPointsNode+'/',
                                 @Project1.LongenFilename,
                                 @FBreakPointGroups.GetGroupByName);
  FWatches.LoadFromXMLConfig(XMLConfig,'Debugging/'+XMLWatchesNode+'/');
  FExceptions.LoadFromXMLConfig(XMLConfig,'Debugging/'+XMLExceptionsNode+'/');
end;

{------------------------------------------------------------------------------
  procedure TDebugManager.SaveProjectSpecificInfo(XMLConfig: TXMLConfig);

  Called when the main project is saved to an XMLConfig.
------------------------------------------------------------------------------}
procedure TDebugManager.SaveProjectSpecificInfo(XMLConfig: TXMLConfig);
begin
  FBreakPointGroups.SaveToXMLConfig(XMLConfig,
                                    'Debugging/'+XMLBreakPointGroupsNode+'/');
  FBreakPoints.SaveToXMLConfig(XMLConfig,'Debugging/'+XMLBreakPointsNode+'/',
                               @Project1.ShortenFilename);
  FWatches.SaveToXMLConfig(XMLConfig,'Debugging/'+XMLWatchesNode+'/');
  FExceptions.SaveToXMLConfig(XMLConfig,'Debugging/'+XMLExceptionsNode+'/');
end;

procedure TDebugManager.DoRestoreDebuggerMarks(AnUnitInfo: TUnitInfo);
var
  ASrcEdit: TSourceEditor;
  i: Integer;
  CurBreakPoint: TIDEBreakPoint;
  SrcFilename: String;
begin
  if (AnUnitInfo.EditorIndex<0) or Destroying then exit;
  ASrcEdit:=SourceNotebook.Editors[AnUnitInfo.EditorIndex];
  // set breakpoints for this unit
  SrcFilename:=AnUnitInfo.Filename;
  for i:=0 to FBreakpoints.Count-1 do begin
    CurBreakPoint:=FBreakpoints[i];
    if CompareFileNames(CurBreakPoint.Source,SrcFilename)=0 then
      CreateSourceMarkForBreakPoint(CurBreakPoint,ASrcEdit);
  end;
end;

procedure TDebugManager.CreateSourceMarkForBreakPoint(
  const ABreakpoint: TIDEBreakPoint; ASrcEdit: TSourceEditor);
var
  ManagedBreakPoint: TManagedBreakPoint;
  NewSrcMark: TSourceMark;
begin
  if not (ABreakpoint is TManagedBreakPoint) then
    RaiseException('TDebugManager.CreateSourceMarkForBreakPoint');
  ManagedBreakPoint:=TManagedBreakPoint(ABreakpoint);

  if (ManagedBreakPoint.SourceMark<>nil) or Destroying then exit;
  if ASrcEdit=nil then
    GetSourceEditorForBreakPoint(ManagedBreakPoint,ASrcEdit);
  if ASrcEdit=nil then exit;
  NewSrcMark:=TSourceMark.Create(ASrcEdit.EditorComponent,nil);
  SourceEditorMarks.Add(NewSrcMark);
  ManagedBreakPoint.SourceMark:=NewSrcMark;
  ASrcEdit.EditorComponent.Marks.Add(NewSrcMark);
end;

procedure TDebugManager.GetSourceEditorForBreakPoint(
  const ABreakpoint: TIDEBreakPoint; var ASrcEdit: TSourceEditor);
var
  Filename: String;
begin
  Filename:=ABreakpoint.Source;
  if Filename<>'' then
    ASrcEdit:=SourceNotebook.FindSourceEditorWithFilename(ABreakpoint.Source)
  else
    ASrcEdit:=nil;
end;

procedure TDebugManager.ClearDebugOutputLog;
begin
  if FDialogs[ddtOutput] <> nil then
    TDbgOutputForm(FDialogs[ddtOutput]).Clear
  else if fHiddenDebugOutputLog<>nil then
    fHiddenDebugOutputLog.Clear;
end;

//-----------------------------------------------------------------------------
// Debugger routines
//-----------------------------------------------------------------------------

procedure TDebugManager.FreeDebugger;
var
  dbg: TDebugger;
begin
  dbg := FDebugger;
  SetDebugger(nil);
  dbg.Free;
  FManagerStates := [];
  
  if MainIDE.ToolStatus = itDebugger
  then MainIDE.ToolStatus := itNone;
end;

function TDebugManager.InitDebugger: Boolean;
var
  LaunchingCmdLine, LaunchingApplication, LaunchingParams: String;
  NewWorkingDir: String;
  DebuggerClass: TDebuggerClass;
begin
  DebugLn('[TDebugManager.DoInitDebugger] A');

  Result := False;
  if (Project1.MainUnitID < 0) or Destroying then Exit;

  LaunchingCmdLine := MainIDE.GetRunCommandLine;
  SplitCmdLine(LaunchingCmdLine,LaunchingApplication, LaunchingParams);
  if not FileIsExecutable(LaunchingApplication)
  then begin
    MessageDlg(lisLaunchingApplicationInvalid,
      Format(lisTheLaunchingApplicationDoesNotExistsOrIsNotExecuta, ['"',
        LaunchingCmdLine, '"', #13, #13, #13]),
      mtError, [mbOK],0);
    Exit;
  end;

  if not FileIsExecutable(EnvironmentOptions.DebuggerFilename)
  then begin
    MessageDlg(lisDebuggerInvalid,
      Format(lisTheDebuggerDoesNotExistsOrIsNotExecutableSeeEnviro, ['"',
        EnvironmentOptions.DebuggerFilename, '"', #13, #13, #13]),
      mtError,[mbOK],0);
    Exit;
  end;
  
  DebuggerClass := FindDebuggerClass(EnvironmentOptions.DebuggerClass);
  if DebuggerClass = nil
  then begin
    if FDebugger <> nil
    then FreeDebugger;
    Exit;
  end;
  
  if (dmsDebuggerObjectBroken in FManagerStates)
  then FreeDebugger;

  // check if debugger is already created with the right type
  if (FDebugger <> nil)
  and (not (FDebugger is DebuggerClass)
        or (FDebugger.ExternalDebugger <> EnvironmentOptions.DebuggerFilename)
      )
  then begin
    // the current debugger is the wrong type -> free it
    FreeDebugger;
  end;

  // create debugger object
  if FDebugger = nil
  then SetDebugger(DebuggerClass.Create(EnvironmentOptions.DebuggerFilename));

  if FDebugger = nil
  then begin
    // something went wrong
    Exit;
  end;

  ClearDebugOutputLog;

  FDebugger.OnState     := @OnDebuggerChangeState;
  FDebugger.OnCurrent   := @OnDebuggerCurrentLine;
  FDebugger.OnDbgOutput := @OnDebuggerOutput;
  FDebugger.OnException := @OnDebuggerException;

  if FDebugger.State = dsNone
  then begin
    Include(FManagerStates,dmsInitializingDebuggerObject);
    Exclude(FManagerStates,dmsInitializingDebuggerObjectFailed);
    FDebugger.Init;
    Exclude(FManagerStates,dmsInitializingDebuggerObject);
    if dmsInitializingDebuggerObjectFailed in FManagerStates
    then begin
      FreeDebugger;
      Exit;
    end;
  end;

  Project1.RunParameterOptions.AssignEnvironmentTo(FDebugger.Environment);
  NewWorkingDir:=Project1.RunParameterOptions.WorkingDirectory;
  if NewWorkingDir=''
  then NewWorkingDir:=Project1.ProjectDirectory;
  FDebugger.WorkingDir:=NewWorkingDir;
  // set filename after workingdir
  FDebugger.FileName := LaunchingApplication;
  FDebugger.Arguments := LaunchingParams;

  // check if debugging needs restart
  // mwe: can this still happen ?
  if (dmsDebuggerObjectBroken in FManagerStates)
  then begin
    FreeDebugger;
    Exit;
  end;

  Result := True;
  DebugLn('[TDebugManager.DoInitDebugger] END');
end;

// still part of main, should go here when dummydebugger is finished
//
//function TDebugManager.DoRunProject: TModalResult;

function TDebugManager.DoPauseProject: TModalResult;
begin
  Result := mrCancel;
  if (MainIDE.ToolStatus <> itDebugger)
  or (FDebugger = nil) or Destroying
  then Exit;
  FDebugger.Pause;
  Result := mrOk;
end;

function TDebugManager.DoStepIntoProject: TModalResult;
begin
  if (MainIDE.DoInitProjectRun <> mrOK)
  or (MainIDE.ToolStatus <> itDebugger)
  or (FDebugger = nil) or Destroying
  then begin
    Result := mrAbort;
    Exit;
  end;

  FDebugger.StepInto;
  Result := mrOk;
end;

function TDebugManager.DoStepOverProject: TModalResult;
begin
  if (MainIDE.DoInitProjectRun <> mrOK)
  or (MainIDE.ToolStatus <> itDebugger)
  or (FDebugger = nil) or Destroying
  then begin
    Result := mrAbort;
    Exit;
  end;

  FDebugger.StepOver;
  Result := mrOk;
end;

function TDebugManager.DoStopProject: TModalResult;
begin
  Result := mrCancel;
  SourceNotebook.ClearExecutionLines;
  if (MainIDE.ToolStatus=itDebugger) and (FDebugger<>nil) and (not Destroying)
  then begin
    FDebugger.Stop;
  end;
  if (dmsDebuggerObjectBroken in FManagerStates) then begin
    if (MainIDE.ToolStatus=itDebugger) then
      MainIDE.ToolStatus:=itNone;
  end;
  Result := mrOk;
end;

procedure TDebugManager.DoToggleCallStack;
begin
  ViewDebugDialog(ddtCallStack);
end;

procedure TDebugManager.ProcessCommand(Command: word; var Handled: boolean);
begin
  //debugln('TDebugManager.ProcessCommand ',dbgs(Command));
  Handled:=true;
  case Command of
  ecPause:       DoPauseProject;
  ecStepInto:    DoStepIntoProject;
  ecStepOver:    DoStepOverProject;
  ecRunToCursor: DoRunToCursor;
  ecStopProgram: DoStopProject;
  ecToggleCallStack:   DoToggleCallStack;
  ecToggleWatches:     ViewDebugDialog(ddtWatches);
  ecToggleBreakPoints: ViewDebugDialog(ddtBreakpoints);
  ecToggleDebuggerOut: ViewDebugDialog(ddtOutput);
  ecToggleLocals:      ViewDebugDialog(ddtLocals);
  else
    Handled:=false;
  end;
end;

function TDebugManager.RunDebugger: TModalResult;
begin
  //writeln('TDebugManager.RunDebugger A ',FDebugger<>nil,' Destroying=',Destroying);
  Result:=mrCancel;
  if Destroying then exit;
  if (FDebugger <> nil) then begin
    DebugLn('TDebugManager.RunDebugger B ',FDebugger.ClassName);
    // check if debugging needs restart
    if (dmsDebuggerObjectBroken in FManagerStates)
    and (MainIDE.ToolStatus=itDebugger) then begin
      MainIDE.ToolStatus:=itNone;
      Result:=mrCancel;
      exit;
    end;
    FDebugger.Run;
    Result:=mrOk;
  end;
end;

procedure TDebugManager.EndDebugging;
begin
  if FDebugger <> nil then FDebugger.Done;
  // if not already freed
  FreeDebugger;
end;

function TDebugManager.Evaluate(const AExpression: String;
  var AResult: String): Boolean;
begin
  Result := (not Destroying)
        and (MainIDE.ToolStatus = itDebugger)
        and (FDebugger <> nil)
        and (dcEvaluate in FDebugger.Commands)
        and FDebugger.Evaluate(AExpression, AResult)
end;

function TDebugManager.DoCreateBreakPoint(const AFilename: string;
  ALine: integer): TModalResult;
begin
  FBreakPoints.Add(AFilename, ALine);
  Result := mrOK
end;

function TDebugManager.DoDeleteBreakPoint(const AFilename: string;
  ALine: integer): TModalResult;
var
  OldBreakPoint: TIDEBreakPoint;
begin
  OldBreakPoint:=FBreakPoints.Find(AFilename,ALine);
  if OldBreakPoint=nil then exit;
  OldBreakPoint.Free;
  Project1.Modified:=true;
  Result := mrOK
end;

function TDebugManager.DoDeleteBreakPointAtMark(const ASourceMark: TSourceMark
  ): TModalResult;
var
  OldBreakPoint: TIDEBreakPoint;
begin
  // consistency check
  if (ASourceMark=nil) or (not ASourceMark.IsBreakPoint)
  or (ASourceMark.Data=nil) or (not (ASourceMark.Data is TIDEBreakPoint)) then
    RaiseException('TDebugManager.DoDeleteBreakPointAtMark');
  
  DebugLn('TDebugManager.DoDeleteBreakPointAtMark A ',ASourceMark.GetFilename,
    ' ',IntToStr(ASourceMark.Line));
  OldBreakPoint:=TIDEBreakPoint(ASourceMark.Data);
  DebugLn('TDebugManager.DoDeleteBreakPointAtMark B ',OldBreakPoint.ClassName,
    ' ',OldBreakPoint.Source,' ',IntToStr(OldBreakPoint.Line));
  OldBreakPoint.Free;
  Project1.Modified:=true;
  Result := mrOK
end;

function TDebugManager.DoRunToCursor: TModalResult;
var
  ActiveSrcEdit: TSourceEditor;
  ActiveUnitInfo: TUnitInfo;
  UnitFilename: string;
begin
  DebugLn('TDebugManager.DoRunToCursor A');
  if (MainIDE.DoInitProjectRun <> mrOK)
  or (MainIDE.ToolStatus <> itDebugger)
  or (FDebugger = nil) or Destroying
  then begin
    Result := mrAbort;
    Exit;
  end;
  DebugLn('TDebugManager.DoRunToCursor B');

  Result := mrCancel;

  MainIDE.GetCurrentUnitInfo(ActiveSrcEdit,ActiveUnitInfo);
  if (ActiveSrcEdit=nil) or (ActiveUnitInfo=nil)
  then begin
    MessageDlg(lisRunToFailed, lisPleaseOpenAUnitBeforeRun, mtError,
      [mbCancel],0);
    Result := mrCancel;
    Exit;
  end;

  if not ActiveUnitInfo.Source.IsVirtual
  then UnitFilename:=ActiveUnitInfo.Filename
  else UnitFilename:=MainIDE.GetTestUnitFilename(ActiveUnitInfo);

  DebugLn('TDebugManager.DoRunToCursor C');
  FDebugger.RunTo(ExtractFilename(UnitFilename),
                  ActiveSrcEdit.EditorComponent.CaretY);

  DebugLn('TDebugManager.DoRunToCursor D');
  Result := mrOK;
end;

function TDebugManager.GetState: TDBGState;       
begin
  if FDebugger = nil
  then Result := dsNone
  else Result := FDebugger.State;
end;

function TDebugManager.GetCommands: TDBGCommands; 
begin
  if FDebugger = nil
  then Result := []
  else Result := FDebugger.Commands;
end;

function TDebugManager.ShowBreakPointProperties(const ABreakpoint: TIDEBreakPoint): TModalresult;
begin
  Result:=mrCancel;
  // ToDo
end;

function TDebugManager.ShowWatchProperties(const AWatch: TIDEWatch): TModalresult;
begin
  with TWatchPropertyDlg.Create(Self, AWatch) do
  begin
    Result := ShowModal;
    Free;
  end;
end;

procedure TDebugManager.SetDebugger(const ADebugger: TDebugger);
begin
  if FDebugger = ADebugger then Exit;
  FDebugger := ADebugger;
  if FDebugger = nil
  then begin
    TManagedBreakpoints(FBreakpoints).Master := nil;
    TManagedWatches(FWatches).Master := nil;
    TManagedLocals(FLocals).Master := nil;
    TManagedCallStack(FCallStack).Master := nil;
    TManagedExceptions(FExceptions).Master := nil;
    TManagedSignals(FSignals).Master := nil;
  end
  else begin
    TManagedBreakpoints(FBreakpoints).Master := FDebugger.BreakPoints;
    TManagedWatches(FWatches).Master := FDebugger.Watches;
    TManagedLocals(FLocals).Master := FDebugger.Locals;
    TManagedCallStack(FCallStack).Master := FDebugger.CallStack;
    TManagedExceptions(FExceptions).Master := FDebugger.Exceptions;
    TManagedSignals(FSignals).Master := FDebugger.Signals;
  end;
end;

end.

{ =============================================================================
  $Log$
  Revision 1.83  2005/01/22 20:48:13  mattias
  added option to omit debugged program stopped  from Andrew Haines

  Revision 1.82  2005/01/15 13:44:03  vincents
  use xml units from fpc, if not compiling with fpc 1.0

  Revision 1.81  2004/12/18 10:20:17  mattias
  updatepofiles is now case sensitive,
  replaced many places, where Application was needlessly Owner
  updated po files, started Configure IDE Install Package dialog,
  implemented removing double file package links

  Revision 1.80  2004/12/03 14:35:30  vincents
  implemented TIDEExceptions.LoadFromXMLConfig and SaveToXMLConfig

  Revision 1.79  2004/11/24 08:18:13  mattias
  TTextStrings improvements (Exchange, Put), clean ups

  Revision 1.78  2004/11/23 11:01:10  mattias
  added key handling for debug manager

  Revision 1.77  2004/11/23 00:54:55  marc
  + Added Evaluate/Modify dialog

  Revision 1.76  2004/10/11 23:33:36  marc
  * Fixed interrupting GDB on win32
  * Reset exename after run so that the exe is not locked on win32

  Revision 1.75  2004/09/27 22:05:40  vincents
  splitted off unit FileUtil, it doesn't depend on other LCL units

  Revision 1.74  2004/09/23 07:45:53  vincents
  moved FDebugger field from BaseDebugManager to DebugManager

  Revision 1.73  2004/09/17 20:04:34  vincents
  replaced writeln by DebugLn

  Revision 1.72  2004/09/04 21:54:08  marc
  + Added option to skip compiler step on compile, build or run
  * Fixed adding of runtime watches
  * Fixed runnerror reporting (correct number and location is shown)

  Revision 1.71  2004/08/27 09:19:27  micha
  fix compile by adding braces

  Revision 1.70  2004/08/26 23:50:05  marc
  * Restructured debugger view classes
  * Fixed help

  Revision 1.69  2004/08/08 18:02:44  mattias
  splitted TMainIDE (main control instance) and TMainIDEBar (IDE menu and palette), added mainbase.pas and mainintf.pas

  Revision 1.68  2004/05/02 12:01:14  mattias
  removed unneeded units in uses sections

  Revision 1.67  2004/02/24 15:30:13  mattias
  added test if debugger filename exists

  Revision 1.66  2004/01/17 13:29:04  mattias
  using now fpc constant LineEnding   from Vincent

  Revision 1.65  2004/01/05 15:22:41  mattias
  improved debugger: saved log, error handling in initialization, better reinitialize

  Revision 1.64  2003/11/10 22:29:23  mattias
  fixed searching for default debugger line

  Revision 1.63  2003/10/16 23:54:27  marc
  Implemented new gtk keyevent handling

  Revision 1.62  2003/08/20 15:06:57  mattias
  implemented Build+Run File

  Revision 1.61  2003/08/15 14:28:47  mattias
  clean up win32 ifdefs

  Revision 1.60  2003/08/08 10:24:47  mattias
  fixed initialenabled, debuggertype, linkscaner open string constant

  Revision 1.59  2003/08/08 07:49:56  mattias
  fixed mem leaks in debugger

  Revision 1.58  2003/07/31 19:56:49  mattias
  fixed double messages SETLabel

  Revision 1.57  2003/07/30 23:15:38  marc
  * Added RegisterDebugger

  Revision 1.56  2003/07/25 17:05:58  mattias
  moved debugger type to the debugger options

  Revision 1.55  2003/07/24 08:47:36  marc
  + Added SSHGDB debugger

  Revision 1.54  2003/06/16 00:07:28  marc
  MWE:
    + Implemented DebuggerOptions-ExceptonAdd
    * fixed inputquery (cannot setfocus while dialog is invisuible)

  Revision 1.53  2003/06/14 02:24:34  marc
  MWE: + Added DebuggerOptionDialog

  Revision 1.52  2003/06/13 19:21:31  marc
  MWE: + Added initial signal and exception handling

  Revision 1.51  2003/06/10 23:48:26  marc
  MWE: * Enabled modification of breakpoints while running

  Revision 1.50  2003/06/09 15:58:05  mattias
  implemented view call stack key and jumping to last stack frame with debug info

  Revision 1.49  2003/06/09 14:39:52  mattias
  implemented setting working directory for debugger

  Revision 1.48  2003/06/05 15:25:28  mattias
  deactivated our TDataModule for fpc 1.0.8 and 1.1

  Revision 1.47  2003/06/04 16:34:11  mattias
  implemented popupmenu items in source editor for breakpoints

  Revision 1.46  2003/06/04 13:34:58  mattias
  implemented breakpoints hints for source editor

  Revision 1.45  2003/06/04 12:44:55  mattias
  implemented setting breakpoint while compiling

  Revision 1.44  2003/06/03 16:12:14  mattias
  fixed loading bookmarks for editor index 0

  Revision 1.43  2003/06/03 10:29:22  mattias
  implemented updates between source marks and breakpoints

  Revision 1.42  2003/06/03 08:02:32  mattias
  implemented showing source lines in breakpoints dialog

  Revision 1.41  2003/06/03 01:35:39  marc
  MWE: = Splitted TDBGBreakpoint into TBaseBreakPoint, TIDEBreakpoint and
         TDBGBreakPoint

  Revision 1.40  2003/05/30 08:10:51  mattias
  added try except to Application.Run, message on changing debugger items during compile

  Revision 1.39  2003/05/29 23:14:17  mattias
  implemented jump to code on double click for breakpoints and callstack dlg

  Revision 1.38  2003/05/29 18:47:27  mattias
  fixed reposition sourcemark

  Revision 1.37  2003/05/29 17:40:10  marc
  MWE: * Fixed string resolving
       * Updated exception handling

  Revision 1.36  2003/05/29 07:25:02  mattias
  added Destroying flag, debugger now always shuts down

  Revision 1.35  2003/05/28 22:43:21  marc
  MWE: * Fixed adding/removing breakpoints while paused

  Revision 1.34  2003/05/28 15:56:19  mattias
  implemented sourcemarks

  Revision 1.33  2003/05/28 09:00:35  mattias
  watches dialog now without DoInitDebugger

  Revision 1.32  2003/05/28 08:46:23  mattias
  break;points dialog now gets the items without debugger

  Revision 1.31  2003/05/28 00:58:50  marc
  MWE: * Reworked breakpoint handling

  Revision 1.30  2003/05/27 20:58:12  mattias
  implemented enable and deleting breakpoint in breakpoint dlg

  Revision 1.29  2003/05/27 15:04:00  mattias
  small fixes for debugger without file

  Revision 1.28  2003/05/27 08:01:31  marc
  MWE: + Added exception break
       * Reworked adding/removing breakpoints
       + Added Unknown breakpoint type

  Revision 1.27  2003/05/26 11:08:20  mattias
  fixed double breakpoints

  Revision 1.26  2003/05/26 10:34:46  mattias
  implemented search, fixed double loading breakpoints

  Revision 1.25  2003/05/25 15:31:11  mattias
  implemented searching for indirect include files

  Revision 1.24  2003/05/25 12:12:36  mattias
  added TScreen handlers, implemented TMainIDE.UnHideIDE

  Revision 1.23  2003/05/24 17:51:34  marc
  MWE: Added an usersource history

  Revision 1.22  2003/05/24 11:06:43  mattias
  started Hide IDE on run

  Revision 1.21  2003/05/23 18:50:07  mattias
  implemented searching debugging files in inherited unit paths

  Revision 1.20  2003/05/23 16:46:13  mattias
  added message, that debugger is readonly while running

  Revision 1.19  2003/05/23 14:12:50  mattias
  implemented restoring breakpoints

  Revision 1.18  2003/05/22 17:06:49  mattias
  implemented InitialEnabled for breakpoints and watches

  Revision 1.17  2003/05/22 06:50:04  mattias
  fixed double formats

  Revision 1.16  2003/05/21 16:19:12  mattias
  implemented saving breakpoints and watches

  Revision 1.15  2003/05/20 21:41:07  mattias
  started loading/saving breakpoints

  Revision 1.14  2003/05/18 10:42:57  mattias
  implemented deleting empty submenus

  Revision 1.13  2003/05/03 23:00:33  mattias
  localization

  Revision 1.12  2003/04/02 17:06:27  mattias
  improved deb creation

  Revision 1.11  2003/03/11 09:57:51  mattias
  implemented ProjectOpt: AutoCreateNewForms, added designer Show Options

  Revision 1.10  2002/12/09 16:48:34  mattias
  added basic file handling functions to filectrl

  Revision 1.9  2002/11/05 22:41:13  lazarus
  MWE:
    * Some minor debugger updates
    + Added evaluate to debugboss
    + Added hint debug evaluation

  Revision 1.8  2002/10/02 00:17:03  lazarus
  MWE:
    + Honoured the ofQuiet flag in DoOpenNotExistingFile, so custom messages
      can be shown
    + Added a dialog to make custom locate of a debug file possible

}
