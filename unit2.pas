unit unit2;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lazutf8classes, utf8process, process;

type

  { TStringListUTF8_mod }

  TStringListUTF8_mod = class(TStringListUTF8)
  protected
    function DoCompareText(const s1,s2 : string) : PtrInt; override;
  public
  end;

  { TStringVal }

  TStringVal = class
  public
    Val: string;
    constructor Create(const aval: string);
  end;

  { TValStringList }
  {
  　　Index文字列 と値のペアを高速に管理する。
    TStringValオブジェクトの自動開放は行わないので注意。
  }

  TValStringList = class(TStringListUTF8_mod)
  private
    function GetVali(index: integer): string;
    function GetVals(index: string): string;
    procedure SetiVali(index: integer; AValue: string);
    procedure SetVals(index: string; AValue: string);
  public
    constructor Create;
    procedure AddVal(const name, val: string);
    property Vali[index: integer]: string read GetVali write SetiVali;
    property Vals[index: string]: string read GetVals write SetVals;
  end;

  { TProcess_mod }

  TProcess_mod = class(TProcessUTF8)
  private
  public
    function SafeTerminate(AExitCode: Integer): Boolean;
  end;

  { TPipeProcExec }

  TPipeProcExec = class(TThread)
  private
  public
    Cmds, OutputMsgs, StderrMsgs: TStringList;
    Done, Complete: boolean;
    MaxMsgLen: integer;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;

procedure SleepThread(h: THandle; ms: integer);
function DecodeX(const s: string): string;
function EncodeX(const s: string): string;
function GetFileSize(const fname: string): Int64;
function GetFileTime(const fname: string): integer;
function SeekTimeStr2Num(const seek: string): double;
function SeekTimeNum2Str(seek: double): string;
procedure CopyDirPerfect(dir, dest: string);
procedure RemoveDirPerfect(const dir: string);
function SafeTerminateProcess(const hProcess: cardinal; uExitCode: cardinal): boolean;
function GetMediaInfoSingle(const fname, key: string; mi: Cardinal): string;
procedure GetMediaInfo(const fname: string; mi: Cardinal; sl: TValStringList;
 const exec_path: string; exKeys: TStrings);


implementation
uses
{$IFDEF Windows}
  Windows,
{$ENDIF}
  DOM, XMLRead,
  Contnrs,
  MediaInfoDll,
  fileutil, synautil;

{ TProcess_mod }

function TProcess_mod.SafeTerminate(AExitCode: Integer): Boolean;
begin
  Result:= SafeTerminateProcess(Handle, AexitCode);
end;

{ TStringVal }

constructor TStringVal.Create(const aval: string);
begin
  Val:= aval;
end;

{ TValStringList }

constructor TValStringList.Create;
begin
  inherited Create;
  Sorted:= True;
end;

function TValStringList.GetVali(index: integer): string;
begin
  Result:= TStringVal(Objects[index]).Val;
end;

function TValStringList.GetVals(index: string): string;
var
  i: Integer;
begin
  i:= IndexOf(index);
  if i >= 0 then
    Result:= Vali[i]
  else
    Result:= '';
end;

procedure TValStringList.SetiVali(index: integer; AValue: string);
begin
  TStringVal(Objects[index]).Val:= AValue;
end;

procedure TValStringList.SetVals(index: string; AValue: string);
var
  i: Integer;
begin
  i:= IndexOf(index);
  if i >= 0 then
    Vali[i]:= AValue
  else
    AddVal(index, AValue);
end;

procedure TValStringList.AddVal(const name, val: string);
begin
  AddObject(name, TStringVal.Create(val));
end;

{ TPipeProcExec }

constructor TPipeProcExec.Create;
begin
  Cmds:= TStringList.Create;
  OutputMsgs:= TStringList.Create;
  StderrMsgs:= TStringList.Create;
  Done:= False; Complete:= False;
  MaxMsgLen:= MaxInt;
  FreeOnTerminate:= False;
  inherited Create(True);
end;

destructor TPipeProcExec.Destroy;
begin
  Cmds.Free;
  OutputMsgs.Free;
  StderrMsgs.Free;
  inherited Destroy;
end;

type
  TPipeProcExecOne = class(TThread)
  private
  public
    OutputMsg, StderrMsg: string;
    Done: boolean;
    CurProc, NextProc: TProcess_mod;
    MaxMsgLen: integer;
    constructor Create;
    procedure Execute; override;
  end;

constructor TPipeProcExecOne.Create;
begin
  FreeOnTerminate:= False;
  inherited Create(True);
end;

procedure TPipeProcExecOne.Execute;
var
  i: Integer;
  s: string;
begin
  Done:= False;
  try
    OutputMsg:= ''; StderrMsg:= '';
    CurProc.Options:= [poUsePipes, poNoConsole];
    CurProc.Execute;
    try
      while not Terminated do begin
        i:= CurProc.Output.NumBytesAvailable;
        if i > 0 then begin
          if Assigned(NextProc) then begin
            if NextProc.Running then begin
              SetLength(s, i);
              i := CurProc.Output.Read(s[1], i);
              SetLength(s, i);
              NextProc.Input.Write(s[1], i);
            end;
          end else begin
            SetLength(s, i);
            i := CurProc.Output.Read(s[1], i);
            SetLength(s, i);
            if Length(OutputMsg+s) <= MaxMsgLen then
              OutputMsg := OutputMsg + s;
          end;
        end;

        i:= CurProc.Stderr.NumBytesAvailable;
        if i > 0 then begin
          SetLength(s, i);
          i := CurProc.Stderr.Read(s[1], i);
          SetLength(s, i);
          if Length(StderrMsg+s) <= MaxMsgLen then
            StderrMsg := StderrMsg + s;
        end;

        if not CurProc.Running and (CurProc.Output.NumBytesAvailable = 0)
         and (CurProc.Stderr.NumBytesAvailable = 0) then begin
          if Assigned(NextProc) and NextProc.Running then begin
            NextProc.CloseInput;
          end;
          Break;
        end;
      end;
    finally
      i:= 0;
      while CurProc.Running and (i < 180) do begin
        CurProc.SafeTerminate(-1);
        SleepThread(Handle, 1000);
        Inc(i);
      end;
    end;
  finally
    Done:= True;
  end;
end;

procedure TPipeProcExec.Execute;
var
  procs: TObjectList;
  proc: TPipeProcExecOne;
  i, j: Integer;
begin
  Done:= False; Complete:= False;
  try
    OutputMsgs.Clear; StderrMsgs.Clear;
    procs:= TObjectList.Create(False);
    try
      for i:= 0 to Cmds.Count-1 do begin
        proc:= TPipeProcExecOne.Create;
        proc.CurProc:= TProcess_mod.Create(nil);
        proc.CurProc.CommandLine:= Cmds[i];
        proc.MaxMsgLen:= MaxMsgLen;
        procs.Add(proc);
      end;
      for i:= 0 to procs.Count-1 do begin
        proc:= TPipeProcExecOne(procs[i]);
        if i < Cmds.Count-1 then begin
          proc.NextProc:= TPipeProcExecOne(procs[i+1]).CurProc;
        end;
        proc.Start;
      end;
      while not Terminated do begin
        i:= 1;
        while i < procs.Count do begin
          if not TPipeProcExecOne(procs[i-1]).Done and
           TPipeProcExecOne(procs[i]).Done then Break; // 異常終了
          Inc(i);
        end;

        if i < procs.Count then Break; // 異常終了

        if TPipeProcExecOne(procs[procs.Count-1]).Done then begin
          // 正常終了
          Complete:= True;
          Break;
        end;

      end;
    finally
      for i:= 0 to procs.Count-1 do begin
        proc:= TPipeProcExecOne(procs[i]);
        proc.Terminate;
        proc.WaitFor;
        j:= 0;
        while proc.CurProc.Running and (j < 180) do begin
          proc.CurProc.SafeTerminate(-1);
          SleepThread(Handle, 1000);
          Inc(j);
        end;
        proc.CurProc.Free;
        OutputMsgs.Add(proc.OutputMsg);
        StderrMsgs.Add(proc.StderrMsg);
        FreeAndNil(proc);
      end;
      procs.Free;
    end;
  finally
    Done:= True;
  end;
end;

{ TStringListUTF8_mod }

function TStringListUTF8_mod.DoCompareText(const s1, s2: string): PtrInt;
begin
  if CaseSensitive then
    Result:= CompareStr(s1, s2)
  else
    Result:= CompareText(s1, s2);
end;

procedure SleepThread(h: THandle; ms: integer);
begin
{$IFDEF Windows}
  WaitForSingleObject(h, ms);
{$ELSE}
  Sleep(ms);
{$ENDIF}
end;

function EncodeX(const s: string): string;
var
  i, l: Integer;
begin
  Result:= '';
  i:= 1; l:= Length(s);
  while i <= l do begin
    if s[i] in ['/', '\'] then
      Result:= Result + '/'
    else if s[i] = ' ' then
        Result:= Result + '?'
    else if s[i] in ['0'..'9', 'A'..'J', 'a'..'z', '.', '-', '!', '$', '(', ')'] then
      Result:= Result + s[i]
    else
      Result:= Result +
       Char(Byte('K')+Byte(s[i]) shr 4) + Char(Byte('K')+Byte(s[i]) and $0F);
    Inc(i);
  end;
end;

function DecodeX(const s: string): string;
var
  i, l: Integer;
begin
  Result:= '';
  i:= 1; l:= Length(s);
  while i <= l do begin
    if (s[i] in ['K'..'Z']) and (i < l) then begin
      Result:= Result +
       Char((Byte(s[i])-Byte('K')) shl 4 + Byte(s[i+1])-Byte('K'));
      Inc(i);
    end else if s[i] = '/' then
      Result:= Result + DirectorySeparator
    else if s[i] = '?' then
      Result:= Result + ' '
    else
      Result:= Result + s[i];
    Inc(i);
  end;
end;

function GetFileSize(const fname: string): Int64;
var
  info: TSearchRec;
begin
  Result:= 0;
  if FindFirstUTF8(fname, faAnyFile, info) = 0 then
    try
      Result:= info.Size;
    finally
      FindCloseUTF8(Info);
    end;
end;

function GetFileTime(const fname: string): integer;
var
  info: TSearchRec;
begin
  Result:= 0;
  if FindFirstUTF8(fname, faAnyFile, info) = 0 then
    try
      Result:= info.Time;
    finally
      FindCloseUTF8(Info);
    end;
end;

function SeekTimeStr2Num(const seek: string): double;
var
  s, n1, n2, n3: string;
begin
  s:= seek;
  n1:= Fetch(s, ':');
  if s = '' then begin
    s:= Fetch(n1, '.');
    n1:= n1 + '000';
    n1:= Copy(n1, 1, 3);
    Result:= StrToIntDef(s, 0) * 1000 + StrToIntDef(n1, 0);
    Exit;
  end;
  n2:= Fetch(s, ':');
  if s = '' then begin
    s:= Fetch(n2, '.');
    n2:= n2 + '000';
    n2:= Copy(n2, 1, 3);
    Result:= StrToIntDef(n1, 0) * 60.0 * 1000 +
     StrToIntDef(s, 0) * 1000 + StrToIntDef(n2, 0);
    Exit;
  end;
  n3:= s;
  s:= Fetch(n3, '.');
  n3:= n3 + '000';
  n3:= Copy(n3, 1, 3);
  Result:= StrToIntDef(n1, 0) * 60 * 60 * 1000 +
   StrToIntDef(n2, 0) * 60 * 1000 +
   StrToIntDef(s, 0) * 1000 + StrToIntDef(n3, 0);
end;

function SeekTimeNum2Str(seek: double): string;
var
  i: integer;
begin
  if seek >= 60.0*60.0*1000.0 then begin
    i:= Trunc(seek / (60.0*60.0*1000.0));
    Result:= Format('%2.2d:', [i]);
    seek:= seek - (60.0*60.0*1000.0*i);
  end else
    Result:= '00:';
  if seek >= 60.0*1000.0 then begin
    i:= Trunc(seek / (60.0*1000.0));
    Result:= Result + Format('%2.2d:', [i]);
    seek:= seek - 60.0 * 1000.0 * i;
  end else
    Result:= Result + '00:';
  if seek >= 1000.0 then begin
    i:= Trunc(seek / 1000.0);
    Result:= Result + Format('%2.2d', [i]);
    seek:= seek - 1000.0 * i;
  end else
    Result:= Result + '00';
  Result:= Result + '.' + Format('%3.3d', [Trunc(seek)]);
end;

procedure CopyDirPerfect(dir, dest: string);
var
  info: TSearchRec;
begin
  if ForceDirectoriesUTF8(dest) then begin
    dir:= IncludeTrailingPathDelimiter(dir);
    dest:= IncludeTrailingPathDelimiter(dest);
    if FindFirstUTF8(dir+'*', faAnyFile, info) = 0 then
      try
        repeat
          if (info.Name <> '.') and (info.Name <> '..') and
           (info.Attr and faHidden = 0) then begin
            if info.Attr and faDirectory <> 0 then begin
              CopyDirPerfect(dir+info.Name, dest+info.Name);
            end else begin
              CopyFile(dir + info.Name, dest + info.Name);
            end;
          end;
        until FindNextUTF8(info) <> 0;
      finally
        FindCloseUTF8(Info);
      end;
  end;
end;

procedure RemoveDirPerfect(const dir: string);
var
  info: TSearchRec;
begin
  if FindFirstUTF8(dir+'*', faAnyFile, info) = 0 then
  try
    repeat
      if (info.Name <> '.') and (info.Name <> '..') then begin
        if info.Attr and faDirectory <> 0 then begin
          RemoveDirPerfect(dir+info.Name+'/');
        end else begin
          DeleteFileUTF8(dir + info.Name);
        end;
      end;
    until FindNextUTF8(info) <> 0;
  finally
    FindCloseUTF8(Info);
  end;
  RemoveDirUTF8(dir);
end;

function SafeTerminateProcess(const hProcess: cardinal; uExitCode: cardinal): boolean;
{$IFDEF Windows}
var
  dwTID, dwCode, dwErr: DWORD;
  hProcessDup: cardinal;
  bDup: BOOL;
  hrt:  cardinal;
  hKernel: HMODULE;
  bSuccess: BOOL;
  FARPROC: Pointer;
begin
  dwTID := 0;
  dwCode := 0;
  dwErr := 0;
  hProcessDup := INVALID_HANDLE_VALUE;
  hrt := 0;
  bSuccess := False;

  if (Win32Platform = VER_PLATFORM_WIN32_NT) then
  begin
    bDup := DuplicateHandle(GetCurrentProcess(), hProcess,
      GetCurrentProcess(), @hProcessDup, PROCESS_ALL_ACCESS, False, 0);

    // Detect the special case where the process is
    // already dead...
    if GetExitCodeProcess(hProcessDup, dwCode) and (dwCode = STILL_ACTIVE) then
    begin
      hKernel := GetModuleHandle('Kernel32');
      FARPROC := GetProcAddress(hKernel, 'ExitProcess');
      hRT := CreateRemoteThread(hProcessDup, nil, 0, Pointer(FARPROC),
        @uExitCode, 0, @dwTID);

      if (hRT = 0) then
        dwErr := GetLastError()
      else
        dwErr := ERROR_PROCESS_ABORTED;

      if (hrt <> 0) then
        WaitForSingleObject(hProcessDup, INFINITE);
      CloseHandle(hRT);
      bSuccess := True;

      if (bDup) then
        CloseHandle(hProcessDup);

      if not (bSuccess) then
        SetLastError(dwErr);

      Result := bSuccess;
    end;
  end;

{$ELSE}

begin

{$ENDIF}
end;

function GetMediaInfoSingleSub(const key: string; mi: Cardinal): string;

  function GetInfo2(mi: Cardinal; sk: TMIStreamKind; sn: Integer;
   const para: string): string;
  begin
    Result:= StrPas(MediaInfoA_Get(mi, sk, sn, PChar(para), Info_Text, Info_Name));
  end;

var
  sk, s: string;
  sn: integer;
  i: integer;
begin
  Result:= '';
  s:= key;
  sk:= Fetch(s, ';');
  if sk = '' then Exit;
  sn:= 0;
  i:= Pos('(', sk);
  if i > 0 then begin
    sn:= StrToIntDef(Copy(sk, i+1, Pos(')', sk)-i-1), 1) - 1;
    sk:= Copy(sk, 1, i-1);
  end;
  case LowerCase(sk) of
    'video': Result:= GetInfo2(mi, Stream_Video, sn, s);
    'audio': Result:= GetInfo2(mi, Stream_Audio, sn, s);
    'text': Result:= GetInfo2(mi, Stream_Text, sn, s);
    'chapters': Result:= GetInfo2(mi, Stream_Chapters, sn, s);
    'image': Result:= GetInfo2(mi, Stream_Image, sn, s);
    'menu': Result:= GetInfo2(mi, Stream_Menu, sn, s);
    else Result:= GetInfo2(mi, Stream_General, sn, s);
  end;
end;

function GetMediaInfoSingle(const fname, key: string; mi: Cardinal): string;
begin
  if MediaInfo_Open(mi, PWideChar(UTF8Decode(fname))) <> 1 then Exit;
  try
    Result:= GetMediaInfoSingleSub(key, mi);
  finally
    MediaInfo_Close(mi);
  end;
end;

procedure GetMediaInfo(const fname: string; mi: Cardinal; sl: TValStringList;
 const exec_path: string; exKeys: TStrings);

  function GetInfo(mi: Cardinal; const para: string): string;
  begin
    MediaInfoA_Option(mi, 'Inform', PChar(para));
    Result:= StrPas(MediaInfoA_Inform(mi, 0));
  end;

  function GetInfo2(mi: Cardinal; sk: TMIStreamKind; sn: Integer;
   const para: string): string;
  begin
    Result:= StrPas(MediaInfoA_Get(mi, sk, sn, PChar(para), Info_Text, Info_Name));
  end;

  (*
  function DoMPlayer(no: integer): string;
  var
    proc: TPipeProcExec;
  begin
    proc:= TPipeProcExec.Create;
    try
      proc.Cmds.Add(
       '"' + exec_path + 'mplayer.exe"' +
       ' -speed 100 -vo null -ao null -frames 1 -identify' +
       ' -dvd-device "' + ExtractShortPathNameUTF8(fname) + '" dvd://' + IntToStr(no)
      );
      proc.Start;
      while not proc.Done do ;
      Result:= proc.OutputMsgs[0];
    finally
      //proc.Terminate;
      //proc.WaitFor;
      FreeAndNil(proc);
    end;
  end;
  *)

  procedure DoLsDVD;
  var
    proc: TPipeProcExec;
    doc: TXMLDocument;
    item, item1, item2, item3: TDOMNode;
    c1, c2: integer;
    ss: TStringStream;
    s: string;
  begin
    proc:= TPipeProcExec.Create;
    try
      proc.Cmds.Add(
       '"' + exec_path + 'lsdvd.exe"' +
       ' -x -Ox "' + ExtractShortPathNameUTF8(fname) + '"'
      );
      proc.Start;
      while not proc.Done do ;

      s:= AnsiToUtf8(proc.OutputMsgs[0]);
      // lsDVDのバグ?対策
      s:= StringReplace(s, '&', '&amp;', [rfReplaceAll]);
      //s:= StringReplace(s, '<', '&lt;', [rfReplaceAll]);
      //s:= StringReplace(s, '>', '&gt;', [rfReplaceAll]);
      s:= StringReplace(s, '''', '&apos;', [rfReplaceAll]);
      ss:= TStringStream.Create(s);
      try
        ss.Position:= 0;
        readXMLFile(doc, ss);
        try
          item:= doc.DocumentElement.FindNode('disc_title');
          if not Assigned(item) then Exit;
          sl.AddVal('DVD;disc_title', item.TextContent);

          item:= doc.DocumentElement.FindNode('title_count');
          if not Assigned(item) then Exit;
          sl.AddVal('DVD;title_count', item.TextContent);
          c1:= StrToIntDef(item.TextContent, 0);
          if c1 <= 0 then Exit;

          item:= doc.DocumentElement.FindNode('title');
          while Assigned(item) do begin
            item1:= item.FirstChild;
            while Assigned(item1) do begin
              item2:= item1.FirstChild;
              while Assigned(item2) do begin
                case item2.NodeType of
                  TEXT_NODE: begin
                    case item1.NodeName of
                      'ix': begin
                        c1:= StrToIntDef(item2.NodeValue, 0);
                        if c1 <= 0 then Exit;
                      end;
                      'length': begin
                        sl.AddVal(Format('DVD;title%d;length', [c1]), item2.NodeValue);
                        sl.AddVal(Format('DVD;title%d;length_s', [c1]),
                         SeekTimeNum2Str(SeekTimeStr2Num(item2.NodeValue)));
                      end;
                      'aspect': begin
                        s:= item2.NodeValue;
                        s:= Format('%1.3f',
                         [StrToFloatDef(Fetch(s, '/'), 0) / StrToFloatDef(s, 1) + 0.0005]);
                        sl.AddVal(Format('DVD;title%d;aspect', [c1]), s);
                      end;
                      else begin
                        sl.AddVal(Format('DVD;title%d;%s', [c1, item1.NodeName]),
                         item2.NodeValue);
                      end;
                    end;
                  end;

                  ELEMENT_NODE: begin
                    item3:= item2.FirstChild;
                    while Assigned(item3) do begin
                      case item2.NodeName of
                        'ix': begin
                          c2:= StrToIntDef(item3.NodeValue, 0);
                          if c2 <= 0 then Exit;
                        end;
                        'langcode': begin
                          s:= item3.NodeValue;
                          sl.AddVal(Format('DVD;title%d;%s%d;langcode',
                           [c1, item1.NodeName, c2]), s);
                          if s = '--' then s:= '__';
                          if item1.NodeName = 'audio' then begin
                            sl.AddVal(Format('DVD;title%d;lang_a;%s',
                             [c1, s]), '1');
                          end else begin
                            sl.AddVal(Format('DVD;title%d;lang_s;%s',
                             [c1, s]), '1');
                          end;
                        end;
                        'length': begin
                          sl.AddVal(Format('DVD;title%d;%s%d;length',
                           [c1, item1.NodeName, c2]), item3.NodeValue);
                          sl.AddVal(Format('DVD;title%d;%s%d;length_s',
                           [c1, item1.NodeName, c2]),
                           SeekTimeNum2Str(SeekTimeStr2Num(item3.NodeValue)));
                        end;
                        else begin
                          sl.AddVal(Format('DVD;title%d;%s%d;%s',
                           [c1, item1.NodeName, c2, item2.NodeName]), item3.NodeValue);
                        end;
                      end;
                      item3:= item3.NextSibling;
                    end;
                  end;
                end;
                item2:= item2.NextSibling;
              end;
              item1:= item1.NextSibling;
            end;

            item:= item.NextSibling;
            if item.NodeName = 'longest_title' then begin
              sl.AddVal('DVD;longest_title', item.TextContent);
              Break;
            end;
          end;
          sl.Vals['General;Format']:= 'ISO DVD';
          sl.Vals['Video;Format']:= 'ISO DVD Video';
          sl.Vals['Audio;Format']:= 'ISO DVD Audio';
        finally
          doc.Free;
        end;
      finally
        ss.Free;
      end;
    finally
      //proc.Terminate;
      //proc.WaitFor;
      proc.Free;
    end;
  end;

var
  gf, {buf, res,} s: string;
  fs: TFileStreamUTF8;
  i, c, main_v, dur, w: integer;
  max_dur, max_w: Int64;
  //d, md: double;
begin
  try
    sl.AddVal('General;Format', '');
    sl.AddVal('Video;Format', '');
    sl.AddVal('Audio;Format', '');
    sl.AddVal('Text;Format', '');
    sl.AddVal('Chapters;Format', '');
    sl.AddVal('Image;Format', '');
    sl.AddVal('Menu;Format', '');

    if (fname = '') or not FileExistsUTF8(fname) then Exit;

    s:= LowerCase(ExtractFileExt(fname));
    if (s = '.lua') or (s = '.txt') or  (s = '.m3u') or  (s = '.m3u8') then begin
      // 拡張子だけでメディアファイルでないことが明らに判断できるもの
      Exit;
    end;

    try
      // 書き込み中のファイルかを調べるため、fmShareDenyWriteで開いてみる
      fs:= TFileStreamUTF8.Create(fname, fmOpenRead or fmShareDenyWrite);
    except
      sl.Vals['General;Format']:= 'NowRecording';
      Exit;
    end;

    if (GetFileSize(fname) <= 0) then begin
      Exit;
    end;

    try
      //mi:= MediaInfo_New;
      //try
        if MediaInfo_Open(mi, PWideChar(UTF8Decode(fname))) <> 1 then Exit;
        try
          gf:= GetInfo(mi, 'General;%Format%');
          sl.Vals['General;Format']:= gf;
          if gf = '' then Exit;
          sl.AddVal('General;Duration', GetInfo(mi, 'General;%Duration/String3%'));
          sl.AddVal('General;File_Created_Date_Local', GetInfo(mi, 'General;%File_Created_Date_Local%'));

          c:= StrToIntDef(GetInfo(mi, 'General;%VideoCount%'), 1);
          sl.AddVal('General;VideoCount', IntToStr(c));
          main_v:= 0;
          if c > 1 then begin
            max_dur:= 0; max_w:= 0;
            for i:= 0 to c-1 do begin
              dur:= StrToIntDef(GetInfo2(mi, Stream_Video, i, 'Duration'), 0);
              w:= StrToIntDef(GetInfo2(mi, Stream_Video, i, 'Width'), 0);
              if (gf = 'MPEG-TS') or (gf = 'BDAV') then begin
                if ((w > 320{=1SEG}) and (dur > max_dur)) or (w > max_w) then begin
                  main_v:= i;
                  max_dur:= dur;
                  max_w:= w;
                end;
              end else begin
                if (dur > max_dur) or (w > max_w) then begin
                  main_v:= i;
                  max_dur:= dur;
                  max_w:= w;
                end;
              end;
            end;
          end;
          s:= GetInfo2(mi, Stream_Video, main_v, 'Format');
          sl.Vals['Video;Format']:= s;
          if s <> '' then begin
            sl.AddVal('Video;Format_Profile', GetInfo2(mi, Stream_Video, main_v, 'Format_Profile'));
            sl.AddVal('Video;Width', GetInfo2(mi, Stream_Video, main_v, 'Width'));
            sl.AddVal('Video;Height', GetInfo2(mi, Stream_Video, main_v, 'Height'));
            sl.AddVal('Video;Duration', GetInfo2(mi, Stream_Video, main_v, 'Duration/String3'));
            sl.AddVal('Video;BitRate', GetInfo2(mi, Stream_Video, main_v, 'BitRate'));
            sl.AddVal('Video;FrameRate', GetInfo2(mi, Stream_Video, main_v, 'FrameRate'));
            sl.AddVal('Video;FrameRate_Mode', GetInfo2(mi, Stream_Video, main_v, 'FrameRate_Mode'));
            sl.AddVal('Video;Standard', GetInfo2(mi, Stream_Video, main_v, 'Standard'));
            sl.AddVal('Video;CodecID', GetInfo2(mi, Stream_Video, main_v, 'CodecID'));
            sl.AddVal('Video;DisplayAspectRatio', GetInfo2(mi, Stream_Video, main_v, 'DisplayAspectRatio'));
            sl.AddVal('Video;ID', GetInfo2(mi, Stream_Video, main_v, 'ID'));
            sl.AddVal('Video;ScanType', GetInfo2(mi, Stream_Video, main_v, 'ScanType'));

            if SeekTimeStr2Num(sl.Vals['General;Duration'])
             < SeekTimeStr2Num(sl.Vals['Video;Duration']) then begin
              // 矛盾を修正。 MediaInfo.DLL のバグ?
              sl.Vals['General;Duration']:= sl.Vals['Video;Duration'];
            end;
          end;

          sl.AddVal('General;AudioCount', GetInfo(mi, 'General;%AudioCount%'));
          s:= GetInfo2(mi, Stream_Audio, 0, 'Format');
          sl.Vals['Audio;Format']:= s;
          if s <> '' then begin
            sl.AddVal('Audio;Channels', GetInfo2(mi, Stream_Audio, 0, 'Channel(s)'));
            sl.AddVal('Audio;BitRate', GetInfo2(mi, Stream_Audio, 0, 'BitRate'));
            sl.AddVal('Audio;SamplingRate', GetInfo2(mi, Stream_Audio, 0, 'SamplingRate'));
            sl.AddVal('Audio;ID', GetInfo2(mi, Stream_Audio, 0, 'ID'));
          end;

          {
          if (gf = 'MPEG-TS') or (gf = 'BDAV') then begin
            SetLength(buf, 192 * 6);
            fs.ReadBuffer(buf[1], 192 * 6);
            if ((buf[1] = #$47) and (buf[192+1] = #$47) and (buf[192*2+1] = #$47)) or
             ((buf[5] = #$47) and (buf[192+5] = #$47) and (buf[192*2+5] = #$47)) then begin
              Add('Video;Timed=1');
            end;
          end else
          }

          if gf = 'ISO 9660' then begin
            DoLsDVD();
            (*
            res:= DoMPlayer(1);
            if Pos('ID_DVD_VOLUME_ID=', res) > 0 then begin
              sl.Vals['General;Format']:= 'ISO DVD';
              sl.Vals['Video;Format']:= 'ISO DVD Video';
              sl.Vals['Audio;Format']:= 'ISO DVD Audio';
              md:= 0; max_dur := 0;
              buf:= res;
              while True do begin
                c:= Pos('ID_DVD_TITLE_', buf);
                if c <= 0 then Break;
                buf:= Copy(buf, c+Length('ID_DVD_TITLE_'), MaxInt);
                c:= Pos('_', buf);
                if Copy(buf, c+1, 6) = 'LENGTH' then begin
                  s:= Copy(buf, c+8, MaxInt);
                  s:= Fetch(s, #$0d);
                  d:= StrToFloatDef(s, 0);
                  if d > 30 then begin
                    sl.AddVal('DVD;LENGTH'+Copy(buf, 1, c-1), s);
                    sl.AddVal('DVD;LENGTH_S'+Copy(buf, 1, c-1),
                     SeekTimeNum2Str(SeekTimeStr2Num(s)));
                    if d > md then begin
                      md:= d;
                      max_dur:= StrToInt(Copy(buf, 1, c-1));
                    end;
                  end;
                end;
              end;
              sl.AddVal('DVD;LONGEST', IntToStr(max_dur));

              if max_dur > 1 then res:= DoMPlayer(max_dur);

              cc:= 0;
              buf:= res;
              while True do begin
                c:= Pos('ID_AID_', buf);
                if c <= 0 then Break;
                buf:= Copy(buf, c+Length('ID_AID_'), MaxInt);
                c:= Pos('_', buf);
                if Copy(buf, c, 6) = '_LANG=' then begin
                  s:= Copy(buf, c+6, MaxInt);
                  s:= Fetch(s, #$0d);
                  if sl.Vals['DVD;ALANG;' + s] = '' then begin
                    sl.AddVal('DVD;ALANG;' + s, '1');
                    Inc(cc);
                  end;
                end;
              end;
              sl.AddVal('DVD;ALANG;Count', IntToStr(cc));

              cc:= 0;
              buf:= res;
              while True do begin
                c:= Pos('ID_SID_', buf);
                if c <= 0 then Break;
                buf:= Copy(buf, c+Length('ID_SID_'), MaxInt);
                c:= Pos('_', buf);
                if Copy(buf, c, 6) = '_LANG=' then begin
                  s:= Copy(buf, c+6, MaxInt);
                  s:= Fetch(s, #$0d);
                  if sl.Vals['DVD;SLANG;' + s] = '' then begin
                    sl.AddVal('DVD;SLANG;' + s, '1');
                    Inc(cc);
                  end;
                end;
              end;
              sl.AddVal('DVD;SLANG;Count', IntToStr(cc));

              c:= Pos('ID_VIDEO_BITRATE=', res);
              if c > 0 then begin
                buf:= Copy(res, c+Length('ID_VIDEO_BITRATE='), MaxInt);
                sl.Vals['Video;BitRate']:= Fetch(buf, #$0d);
              end;

              c:= Pos('ID_VIDEO_WIDTH=', res);
              if c > 0 then begin
                buf:= Copy(res, c+Length('ID_VIDEO_WIDTH='), MaxInt);
                sl.Vals['Video;Width']:= Fetch(buf, #$0d);
              end;

              c:= Pos('ID_VIDEO_HEIGHT=', res);
              if c > 0 then begin
                buf:= Copy(res, c+Length('ID_VIDEO_HEIGHT='), MaxInt);
                sl.Vals['Video;Height']:= Fetch(buf, #$0d);
              end;

              c:= Pos('ID_VIDEO_FPS=', res);
              if c > 0 then begin
                buf:= Copy(res, c+Length('ID_VIDEO_FPS='), MaxInt);
                sl.Vals['Video;FrameRate']:= Fetch(buf, #$0d);
              end;

              c:= Pos('Opening audio decoder:', res);
              if c > 0 then begin
                buf:= Copy(res, c, MaxInt);
                c:= Pos('ID_AUDIO_BITRATE=', buf);
                if c > 0 then begin
                  buf:= Copy(buf, c+Length('ID_AUDIO_BITRATE='), MaxInt);
                  sl.Vals['Audio;BitRate']:= Fetch(buf, #$0d);
                end;
                c:= Pos('ID_AUDIO_RATE=', buf);
                if c > 0 then begin
                  buf:= Copy(buf, c+Length('ID_AUDIO_RATE='), MaxInt);
                  sl.Vals['Audio;SamplingRate']:= Fetch(buf, #$0d);
                end;
                c:= Pos('ID_AUDIO_NCH=', buf);
                if c > 0 then begin
                  buf:= Copy(buf, c+Length('ID_AUDIO_NCH='), MaxInt);
                  sl.Vals['Audio;Channels']:= Fetch(buf, #$0d);
                end;
              end;

              c:= Pos('Movie-Aspect is', res);
              if c > 0 then begin
                buf:= Copy(res, c, MaxInt);
                c:= Pos('ID_VIDEO_ASPECT=', buf);
                if c > 0 then begin
                  buf:= Copy(buf, c+Length('ID_VIDEO_ASPECT='), MaxInt);
                  s:= Fetch(buf, #$0d);
                  s:= Format('%1.3f', [StrToFloatDef(s, 0)+0.0005]);
                  sl.Vals['Video;DisplayAspectRatio'] := s;
                end;
              end;
            end;
            *)
          end;

          if Assigned(exKeys) then begin
            for i:= 0 to exKeys.Count-1 do begin
              s:= exKeys[i];
              if sl.IndexOf(s) < 0 then
                sl.AddVal(s, GetMediaInfoSingleSub(s, mi));
            end;
          end;

        finally
          MediaInfo_Close(mi);
        end;
      //finally
      //  MediaInfo_Delete(mi);
      //end;
    finally
      fs.Free;
    end;
  except
  end;
end;

end.

