unit unit_mi1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs,
  StdCtrls;

type

  { TForm1 }

  TForm1 = class(TForm)
    Label1: TLabel;
    Memo1: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of String);
  private
    { private declarations }
    execpath: string;
    procedure DoCommand(const fname: string);
  public
    { public declarations }
  end; 

var
  Form1: TForm1; 

implementation
uses
  unit2, MediaInfoDll, inifiles;

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  ExecPath:= ExtractFilePath(ParamStrUTF8(0));
  if ParamCount > 0 then DoCommand(ParamStrUTF8(1));
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
end;

procedure TForm1.FormDropFiles(
 Sender: TObject; const FileNames: array of String);
begin
  DoCommand(FileNames[0]);
end;

procedure TForm1.DoCommand(const fname: string);
var
  mi: integer;
  sl: TValStringList;
  iniFile: TIniFile;
  exkeys: TStringList;
  i: Integer;
begin
  Label1.Caption:= fname;
  Memo1.Clear;
  Memo1.Lines.BeginUpdate;
  try
    mi:= MediaInfo_New;
    try
      exkeys:= TStringList.Create;
      iniFile:= TIniFile.Create({UTF8FILENAME}UTF8ToSys(ExecPath + 'bms.ini'));
      iniFile.ReadSectionRaw('MInfoKeys', exkeys);
      sl:= TValStringList.Create;
      try
        GetMediaInfo(fname, mi, sl, ExecPath, exkeys);
        for i:= 0 to sl.Count-1 do begin
          //sl[i]:=
          // StringReplace(sl.Names[i], ';', '.', [rfReplaceAll, rfIgnoreCase]) +
          // ' = ' + sl.ValueFromIndex[i];
          Memo1.Lines.Add(
           StringReplace(sl[i], ';', '.', [rfReplaceAll, rfIgnoreCase]) +
           ' = ' + sl.Vali[i]
          );
        end;
        //Memo1.Lines.AddStrings(sl);
      finally
        sl.Free;
        exkeys.Free;
        iniFile.Free;
      end;
    finally
      MediaInfo_Delete(mi);
    end;
  finally
    Memo1.Lines.EndUpdate;
  end;
end;

end.

