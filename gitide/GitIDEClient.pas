{******************************************************************************}
{                                                                              }
{ RAD Studio Version Insight                                                   }
{                                                                              }
{ The contents of this file are subject to the Mozilla Public License          }
{ Version 1.1 (the "License"); you may not use this file except in compliance  }
{ with the License. You may obtain a copy of the License at                    }
{ http://www.mozilla.org/MPL/                                                  }
{                                                                              }
{ Software distributed under the License is distributed on an "AS IS" basis,   }
{ WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for }
{ the specific language governing rights and limitations under the License.    }
{                                                                              }
{ The Original Code is GitIDEClient.pas.                                       }
{                                                                              }
{ The Initial Developer of the Original Code is Uwe Schuster.                  }
{ Portions created by Uwe Schuster are Copyright � 2010 Uwe Schuster. All      }
{ Rights Reserved.                                                             }
{                                                                              }
{ Contributors:                                                                }
{ Uwe Schuster (uschuster)                                                     }
{                                                                              }
{******************************************************************************}

unit GitIDEClient;

interface

uses
  SysUtils, Classes, GitClient, GitIDEColors;

type
  TGitOptions = class(TObject)
  private
    FDeleteBackupFilesAfterCommit: Boolean;
  public
    constructor Create;
    procedure Load;
    procedure Save;
    property DeleteBackupFilesAfterCommit: Boolean read FDeleteBackupFilesAfterCommit write FDeleteBackupFilesAfterCommit;
  end;

  TGitIDEClient = class(TObject)
  private
    FHistoryProviderIndex: Integer;
    FColors: TGitColors;
    FGitClient: TGitClient;
    FGitInitialized: Boolean;
    FOptions: TGitOptions;
    procedure Initialize;
    procedure Finalize;
    function GetGitClient: TGitClient;
  public
    constructor Create;
    destructor Destroy; override;
    property Colors: TGitColors read FColors;
    function GitInitialize: Boolean;
    property GitClient: TGitClient read GetGitClient;
    property Options: TGitOptions read FOptions;
  end;

procedure Register;

function BaseRegKey: string;
procedure LoadSourceRepoHistory(const List: TStringList);
procedure SaveSourceRepoHistory(const List: TStringList);

var
  IDEClient: TGitIDEClient;

implementation

uses
  Registry, ToolsAPI, FileHistoryAPI, GitIDEHistory, GitIDEAddInOptions, GitIDEMenus,
  GitImages, GitIDEConst;

const
  sSourceRepoHistory = 'SourceRepoHistory';
  sSourceRepoHistoryItem = 'SourceRepoHistory%d';
  MaxSourceRepoHistory = 20;
  cOptions = 'Options';
  cDeleteBackupFilesAfterCommit = 'DeleteBackupFilesAfterCommit';

procedure Register;
begin
  IDEClient := TGitIDEClient.Create;
  RegisterMenus(IDEClient);
  RegisterAddInOptions;
end;

{ TGitOptions }

constructor TGitOptions.Create;
begin
  inherited Create;
  FDeleteBackupFilesAfterCommit := False;
  Load;
end;

procedure TGitOptions.Load;
var
  Reg: TRegistry;
  BaseKey, Key: string;
begin
  Reg := TRegistry.Create;
  try
    BaseKey := BaseRegKey + cOptions;
    if not Reg.KeyExists(BaseKey) then
      Exit;
    Reg.OpenKeyReadOnly(BaseKey);
    Key := cDeleteBackupFilesAfterCommit;
    if Reg.ValueExists(Key) then
      FDeleteBackupFilesAfterCommit := Reg.ReadBool(Key);
  finally
    Reg.Free;
  end;
end;

procedure TGitOptions.Save;
var
  Reg: TRegistry;
  BaseKey: string;
begin
  Reg := TRegistry.Create;
  try
    BaseKey := BaseRegKey + cOptions;
    Reg.OpenKey(BaseKey, True);
    Reg.WriteBool(cDeleteBackupFilesAfterCommit, FDeleteBackupFilesAfterCommit);
  finally
    Reg.Free;
  end;
end;

{ TGitIDEClient }

constructor TGitIDEClient.Create;
begin
  inherited Create;
  FColors := TGitColors.Create;
  FOptions := TGitOptions.Create;
  Initialize;
end;

destructor TGitIDEClient.Destroy;
begin
  Finalize;
  FOptions.Free;
  FColors.Free;
  inherited Destroy;
end;

procedure TGitIDEClient.Finalize;
var
  FileHistoryManager: IOTAFileHistoryManager;
begin
  if (FHistoryProviderIndex <> -1) and Assigned(BorlandIDEServices)
    and BorlandIDEServices.GetService(IOTAFileHistoryManager, FileHistoryManager)
  then
    FileHistoryManager.UnregisterHistoryProvider(FHistoryProviderIndex);
  FHistoryProviderIndex := -1;
  FreeAndNil(GitImageModule);
end;

function TGitIDEClient.GetGitClient: TGitClient;
begin
  if not FGitInitialized then
    GitInitialize;
  Result := FGitClient;
end;

function TGitIDEClient.GitInitialize: Boolean;
var
  RegIniFile: TRegIniFile;
  Key: string;
begin
  Result := True;
  if FGitInitialized then
    Exit;
  FGitInitialized := True;

  GitImageModule := TGitImageModule.Create(nil);

  FGitClient := TGitClient.Create;

  Key := (BorlandIDEServices as IOTAServices).GetBaseRegistryKey + '\VersionInsight';
  RegIniFile := TRegIniFile.Create(Key);
  try
    FGitClient.GitExecutable := RegIniFile.ReadString('Git', 'Executable', '');
  finally
    RegIniFile.Free;
  end;
end;

procedure TGitIDEClient.Initialize;
var
  FileHistoryManager: IOTAFileHistoryManager;
begin
  if Assigned(BorlandIDEServices) then
  begin
    if BorlandIDEServices.GetService(IOTAFileHistoryManager, FileHistoryManager) then
      FHistoryProviderIndex := FileHistoryManager.RegisterHistoryProvider(TGitFileHistoryProvider.Create(Self));
  end;
end;

function BaseRegKey: string;
begin
  Result := (BorlandIDEServices as IOTAServices).GetBaseRegistryKey + '\' + sGit + '\';
end;

procedure LoadSourceRepoHistory(const List: TStringList);
var
  Reg: TRegistry;
  BaseKey: string;
  Key: string;
  S: string;
  I: Integer;
begin
  Reg := TRegistry.Create;
  try
    BaseKey := BaseRegKey + sSourceRepoHistory;
    if not Reg.KeyExists(BaseKey) then
      Exit;
    Reg.OpenKeyReadOnly(BaseKey);
    for I := 0 to MaxSourceRepoHistory - 1 do
    begin
      Key := Format(sSourceRepoHistoryItem, [I]);
      S := Reg.ReadString(Key);
      if S = '' then
        Break
      else
        List.Add(S);
    end;
  finally
    Reg.Free;
  end;
end;

procedure SaveSourceRepoHistory(const List: TStringList);
var
  Reg: TRegistry;
  BaseKey: string;
  Key: string;
  I: Integer;
  Count: Integer;
begin
  Reg := TRegistry.Create;
  try
    BaseKey := BaseRegKey + sSourceRepoHistory;
    Reg.OpenKey(BaseKey, True);
    if List.Count > MaxSourceRepoHistory then
      Count := MaxSourceRepoHistory
    else
      Count := List.Count;
    for I := 0 to Count - 1 do
    begin
      Key := Format(sSourceRepoHistoryItem, [I]);
      Reg.WriteString(Key, List[I]);
    end;
  finally
    Reg.Free;
  end;
end;

end.
