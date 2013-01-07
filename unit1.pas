{
TODO:
}
unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Menus, Buttons, SynMemo;

const
  APP_NAME = 'BEER Media Server';
  SHORT_APP_NAME = 'BMS';
  APP_VERSION = '2.0.130107';
  SHORT_APP_VERSION = '2.0';

type

  { TForm1 }

  TForm1 = class(TForm)
    BitBtn1: TBitBtn;
    BitBtn2: TBitBtn;
    CheckBoxLog: TCheckBox;
    MemoLog: TSynMemo;
    procedure BitBtn2Click(Sender: TObject);
    procedure CheckBoxLogChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { private declarations }
    procedure AsyncFromCreate({%H-}Data: PtrInt);
  public
    { public declarations }
  end; 

var
  Form1: TForm1; 
  TrayIcon: TTrayIcon;

procedure InitAfterApplicationInitialize;

implementation
uses
  LCLIntf, blcksock, synsock, synautil,
  DOM, XMLWrite, XMLRead, MediaInfoDll,
  //Lua, lualib, lauxlib,
  lua52,
  {$IFDEF Windows}
  interfacebase, win32int, windows, // for Hook SUSPEND EVENT
  {$ENDIF}
  lazutf8classes, inifiles, comobj, contnrs, process, SynRegExpr,
  dateutils, simpleipc,
  unit2;


{$R *.lfm}

const
  HTTP_HEAD_SERVER = 'OS/1.0, UPnP/1.0, ' + SHORT_APP_NAME + '/' + SHORT_APP_VERSION;
  INI_SEC_SYSTEM = 'SYSTEM';
  INI_SEC_MIKeys = 'MInfoKeys';
  INI_SEC_SCRIPTS = 'SCRIPTS';
  MEDIA_INFO_DB_FILENAME = 'mi.db';
  MEDIA_INFO_DB_HEADER = 'midb01';
  MAX_ONMEM_LOG = 500;

type

  { TMyApp }

  TMyApp = class
  public
    Log: TStringListUTF8;
    LogFile: TFileStreamUTF8;
    PopupMenu: TPopupMenu;
    constructor Create;
    destructor Destroy; override;
    procedure OnTrayIconClick(Sender: TObject);
    procedure OnMenuShowClick(Sender: TObject);
    procedure OnMenuQuitClick(Sender: TObject);
    procedure AddLog(const line: string);
    procedure WMPowerBoadcast(var msg: TMessage);
  end;

  { THttpDaemon }

  THttpDaemon = class(TThread)
  private
    Sock: TTCPBlockSocket;
    line: string;
    th_list: TObjectList;
    procedure AddLog;
  public
    SendAliveFlag: boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;

  { THttpThrd }

  TClientInfo = class;

  THttpThrd = class(TThread)
  private
    Sock: TTCPBlockSocket;
    line: string;
    L_S: Plua_State;
    ClientInfo: TClientInfo;
    procedure AddLog;
    function DoPlay(const fname, request: string): boolean;
    function DoPlayTranscode(sno: integer; const fname, request: string): boolean;
    function DoBrowse(docr, docw: TXMLDocument): boolean;
    function SendRaw(buf: Pointer; len: integer): boolean; overload;
    function SendRaw(const buf: string): boolean; overload;
  public
    Done: boolean;
    Headers: TStringListUTF8;
    InputData, OutputData: TMemoryStream;
    UniOutput: boolean;
    InHeader: string;
    constructor Create(hSock: TSocket);
    destructor Destroy; override;
    procedure Execute; override;
    function ProcessHttpRequest(const Request, URI: string): integer;
  end;

  { TSSDPDaemon }

  TSSDPDaemon = class(TThread)
  private
    Sock: TUDPBlockSocket;
    line: string;
    procedure AddLog;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;

  { TGetMediaInfo }
  TGetMediaInfo = class(TValStringList)
  private
  public
    FileName, AccTime: string;
    FileSize: Int64;
    IsTemp: boolean;
    PlayInfo: TStringList;
    constructor Create(const fname: string; mi: Cardinal; ExKeys: TStringList);
    destructor Destroy; override;
    procedure GetPlayInfo(L: PLua_State; get_new: boolean = False);
    procedure SaveToStream(Stream: TStream); override;
    procedure LoadFromStream(Stream: TStream); override;
  end;

  { TMediaInfoCollector }

  TMediaInfoCollector = class(TThread)
  private
    miHandle: Cardinal;
    mi_list, mi_ac_list, exkey_list: TStringListUTF8;
    MaxMediaInfo: integer;
  public
    cs_list, cs_ac_list, cs_pr_list, cs_get_mi: TCriticalSection;
    PriorityList: TStringListUTF8;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
    function GetMediaInfo(const fname: string): TGetMediaInfo;
    procedure AddExKey(const key: string);
    procedure ClearMediaInfo;
    procedure LoadMediaInfo;
    procedure SaveMediaInfo;
  end;

  { TClientInfo }

  TClientInfo = class
  private
  public
    L_S: Plua_State;
    CurId, CurDir: string;
    chunks: TStringList;
    FullInfoCount: integer;
    CurFileList: TStringList;
    LastAccTime: TDateTime;
    ScriptFileName: string;
    SortType: integer;
    InfoTable: TValStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  { TChunkObj }

  TChunkObj = class
    bin: string;
    time: integer;
  end;

  { TMySimpleIPCServer }

  TMySimpleIPCServer = class(TSimpleIPCServer)
  private
    cs_vsl: TCriticalSection;
    vsl: TValStringList;
    procedure DoMessage(Sender: TObject);
  public
    constructor {%H-}Create;
    destructor Destroy; override;
    function GetValue(const vname: string): string;
    procedure SetValue(const vname, val: string);
  end;

var
  iniFile: TIniFile;
  ExecPath, TempPath, UUID, DAEMON_PORT: string;
  MAX_REQUEST_COUNT, SEND_DATA_TIMEOUT: integer;
  MyApp: TMyApp;
  thHttpDaemon: THttpDaemon;
  thSSDPDAemon: TSSDPDaemon;
  thMIC: TMediaInfoCollector;
  SIPCServer: TMySimpleIPCServer;
  MediaDirs: TStringList;
  ClientInfoList: TStringList;
  MyIPAddr: string;

function Alloc({%H-}ud, ptr: Pointer; {%H-}osize, nsize: size_t) : Pointer; cdecl;
begin
  try
    Result:= ptr;
    ReallocMem(Result, nSize);
  except
    Result:= nil;
  end;
end;

function print_func(L : Plua_State) : Integer; cdecl;
var
  i, c: integer;
  s: string;
begin
  Result := 0;
  if not Assigned(MyApp) then Exit;
  c:= lua_gettop(L);
  s:= '';
  for i:= 1 to c do s:= s + lua_tostring(L, i);
  MyApp.AddLog(s);
end;

function tonumberDef_func(L : Plua_State) : Integer; cdecl;
var
  s: string;
  n: lua_Number;
begin
  s:= lua_tostring(L, 1);
  n:= lua_tonumber(L, 2);
  lua_pushnumber(L, StrToFloatDef(s, n));
  Result := 1;
end;

function regexpr_matches_func(L : Plua_State) : Integer; cdecl;
var
  s1, s2: string;
begin
  s1:= lua_tostring(L, 1);
  s2:= lua_tostring(L, 2);
  try
    lua_pushboolean(L, ExecRegExpr(s2, s1));
  except
    on E: Exception do begin
      luaL_error(L, PChar(E.Message), []);
    end;
  end;
  Result := 1;
end;

function ScriptFileExists_func(L : Plua_State) : Integer; cdecl;
var
  s: string;
  b: boolean;
begin
  s:= lua_tostring(L, 1);
  b:= FileExistsUTF8(ExecPath + 'script/' + s + '.lua') or
   FileExistsUTF8(ExecPath + 'script_user/' + s + '.lua');
  lua_pushboolean(L, b);
  Result := 1;
end;

function ExtractFileName_func(L : Plua_State) : Integer; cdecl;
begin
  lua_pushstring(L, ExtractFileName(lua_tostring(L, 1)));
  Result := 1;
end;

function ExtractFilePath_func(L : Plua_State) : Integer; cdecl;
begin
  lua_pushstring(L, ExtractFilePath(lua_tostring(L, 1)));
  Result := 1;
end;

function GetCmdStdOut_func(L : Plua_State) : Integer; cdecl;
var
  s: string;
  proc: TPipeProcExec;
begin
  proc:= TPipeProcExec.Create;
  try
    s:= lua_tostring(L, 1);
    {$IFDEF Windows}
    if ExtractFilePath(s) = '' then s:= ExecPath + s;
    {$ENDIF}
    proc.Cmds.Add('"' + s + '" ' + lua_tostring(L, 2));
    proc.Start;
    while not proc.Done do ;
    lua_pushstring(L, proc.OutputMsgs[0]);
    Result := 1;
  finally
    //proc.Terminate;
    //proc.WaitFor;
    proc.Free;
  end;
end;

(*
function GetTempFileName_func(L : Plua_State) : Integer; cdecl;
begin
  lua_pushstring(L, FileUtil.GetTempFileName(lua_tostring(L, 1), lua_tostring(L, 2)));
  Result := 1;
end;

function FileExists_func(L : Plua_State) : Integer; cdecl;
begin
  lua_pushboolean(L, FileExistsUTF8(lua_tostring(L, 1)));
  Result := 1;
end;

function DeleteFileMatches_func(L : Plua_State) : Integer; cdecl;
var
  info: TSearchRec;
  dir, reg: string;
begin
  Result := 0;
  dir:= lua_tostring(L, 1);
  reg:= lua_tostring(L, 2);
  if dir = '' then Exit;
  if FindFirstUTF8(dir+'*', faAnyFile, info) = 0 then
  try
    repeat
      if (info.Name <> '.') and (info.Name <> '..') and
       ExecRegExpr(reg, info.Name) then begin
        if info.Attr and faDirectory <> 0 then begin
          //RemoveDirPerfect(dir+info.Name+'/');
        end else begin
          DeleteFileUTF8(dir + info.Name);
        end;
      end;
    until FindNextUTF8(info) <> 0;
  finally
    FindCloseUTF8(Info);
  end;
end;
*)

procedure InitLua(L: Plua_State);

  procedure regTable(const tablename, funcname: string; func: lua_CFunction);
  begin
    lua_getglobal(L, PChar(tablename));
    if lua_isnil(L, -1) then begin
      lua_pop(L, 1);
      lua_newtable(L);
      lua_setglobal(L, PChar(tablename));
      lua_getglobal(L, PChar(tablename));
    end;
    lua_pushstring(L, funcname);
    lua_pushcfunction(L, func);
    lua_settable(L, -3);
    lua_setglobal(L, PChar(tablename));
  end;

begin
  luaL_openlibs(L);
  lua_register(L, 'print', @print_func);
  lua_register(L, 'tonumberDef', @tonumberDef_func);
  regTable('fileu', 'ExtractFileName', @ExtractFileName_func);
  regTable('fileu', 'ExtractFilePath', @ExtractFilePath_func);
  regTable('fileu', 'GetCmdStdOut', @GetCmdStdOut_func);
  //regTable('fileu', 'FileExists', @FileExists_func);
  //regTable('fileu', 'GetTempFileName', @GetTempFileName_func);
  //regTable('fileu', 'DeleteFileMatches', @DeleteFileMatches_func);
  regTable('regexpr', 'matches', @regexpr_matches_func);
  lua_register(L, 'BMS_ScriptFileExists', @ScriptFileExists_func);
  lua_pushstring(L, ExecPath); lua_setglobal(L, 'BMS_ExecPath');
  lua_pushstring(L, TempPath); lua_setglobal(L, 'BMS_TempPath');
end;

procedure CallLua(L: Plua_State; nargs, nresults: Integer);
begin
  if lua_pcall(L, nargs, nresults, 0) <> 0 then
    Raise Exception.Create('Lua Runtime Error('+lua_tostring(L, -1)+')');
end;

function DumpWriter({%H-}L: Plua_State; const p: Pointer; sz: size_t;
 ud: Pointer): Integer; cdecl;
var
  DumpSize: LongWord;
begin
  DumpSize:= PLongWord(ud^)^;
  PLongWord(ud^)^:= DumpSize + sz;
  ReallocMem(PChar(ud^), SizeOf(LongWord)+DumpSize+sz);
  move(Byte(p^), (PChar(ud^)+SizeOf(LongWord)+DumpSize)^,  sz);
  Result:= 0;
end;

function LoadLuaRawRaw(L: Plua_State; const code, module: string; GetBin: boolean): string;
var
  DumpCode: PChar;
begin
  Result:= '';

  if luaL_loadbuffer(L, PChar(code), Length(code), PChar(module)) <> 0 then
    Raise Exception.Create(module + ' Compile Error(' + lua_tostring(L, -1)+')');

  if GetBin then begin
    // コンパイル済みコードを保持
    GetMem(DumpCode, SizeOf(LongWord));
    try
      PLongWord(DumpCode)^:= 0;
      lua_dump(L, @DumpWriter, @DumpCode);
      SetLength(Result, PLongWord(DumpCode)^);
      move((DumpCode+SizeOf(LongWord))^, Result[1], PLongWord(DumpCode)^);
    finally
      FreeMem(DumpCode);
    end;
  end;

  CallLua(L, 0, 0);
end;

function LoadLuaRaw(L: Plua_State; const fname: string;
   const code: string = ''; code_t: integer = 0): string;
var
  sl: TStringListUTF8;
begin
  if fname = '' then Exit;
  if (code <> '') and (GetFileTime(fname) = code_t) then begin
    LoadLuaRawRaw(L, code, fname + '.lua', False);
    Result:= '';
  end else begin
    sl:= TStringListUTF8.Create;
    try
      try
        sl.LoadFromFile(fname);
      except
        Exit;
      end;
      if (sl.Count > 0) and (Length(sl[0]) >= 3) and
       (sl[0][1] = #$EF) and (sl[0][2] = #$BB) and (sl[0][3] = #$BF) then begin
        // BOM を削除
        sl[0]:= Copy(sl[0], 4, MaxInt);
      end;
      Result:= LoadLuaRawRaw(L, sl.Text, fname, True);
    finally
      sl.Free;
    end;
  end;
end;

procedure LoadLua(L: Plua_State; const fname: string; chunks: TStringList);
var
  s, s1, s2, chunk: string;
  i: Integer;
  obj: TChunkObj;
begin
  if fname = '' then Exit;
  if ExtractFilePath(fname) = '' then begin
    s:= ExecPath + 'script/' + fname + '.lua';
    if FileExistsUTF8(s) then begin
      i:= chunks.IndexOf(fname);
      if i < 0 then begin
        obj:= TChunkObj.Create;
        chunks.AddObject(fname, obj);
      end else
        obj:= TChunkObj(chunks.Objects[i]);
      chunk:= LoadLuaRaw(L, s, obj.bin, obj.time);
      if chunk <> '' then begin
        obj.bin:= chunk;
        obj.time:= GetFileTime(s);
      end;
    end;

    s1:= SIPCServer.GetValue('UserScripts');
    while True do begin
      s2:= Fetch(s1, '|');
      if s2 = '' then Break;
      s:= ExecPath + 'script/' + s2 + '/' + fname + '.lua';
      if not FileExistsUTF8(s) then Continue;
      i:= chunks.IndexOf(s2 + '/' + fname);
      if i < 0 then begin
        obj:= TChunkObj.Create;
        chunks.AddObject(s2 + '/' + fname, obj);
      end else
        obj:= TChunkObj(chunks.Objects[i]);
      chunk:= LoadLuaRaw(L, s, obj.bin, obj.time);
      if chunk <> '' then begin
        obj.bin:= chunk;
        obj.time:= GetFileTime(s);
      end;
    end;
  end else
    LoadLuaRaw(L, fname);
end;

procedure MIValue2LuaTable(L: PLua_State; const key, val: string);
var
  s, ss: string;
  isnill: boolean;
begin
  s:= key;
  ss:= Fetch(s, ';');
  if s = '' then begin
    lua_pushstring(L, ss);
    lua_pushstring(L, val);
    lua_rawset(L, -3);
  end else begin
    lua_pushstring(L, ss);
    lua_rawget(L, -2);
    isnill:= lua_isnil(L, -1);
    if isnill then begin
      lua_pop(L, 1);
      lua_pushstring(L, ss);
      lua_newtable(L);
    end;
    MIValue2LuaTable(L, s, val);
    if isnill then begin
      lua_rawset(L, -3);
    end else begin
      lua_pop(L, 1);
    end;
  end;
end;

procedure LuaTable2ValStringList(L: PLua_State; sl: TValStringList);
begin
  lua_pushnil(L);  // first key
  while lua_next(L, -2) <> 0 do begin
    // uses 'key' (at index -2) and 'value' (at index -1)
    sl.AddVal(lua_tostring(L, -2), lua_tostring(L, -1));
    // removes 'value'; keeps 'key' for next iteration
    lua_pop(L, 1);
  end;
end;

procedure ValStringList2LuaTable(L: PLua_State; sl: TValStringList);
var
  i: integer;
begin
  for i:= 0 to sl.Count-1 do begin
    lua_pushstring(L, sl[i]);
    lua_pushstring(L, sl.Vali[i]);
    lua_rawset(L, -3);
  end;
end;

procedure SendAlive;
var
  sock: TUDPBlockSocket;
  s: string;
begin
  // Sends an advertisement "alive" message on multicast
  sock:= TUDPBlockSocket.Create;
  try
    sock.Family:= SF_IP4;
    sock.CreateSocket();
    sock.Bind(MyIPAddr{'0.0.0.0'}, '0');
    sock.MulticastTTL:= 1;
    sock.Connect('239.255.255.250', '1900'{SSDP});
    if sock.LastError = 0 then begin
      //{
      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'CACHE-CONTROL: max-age=1800'+ CRLF +
       'LOCATION: http://' + MyIPAddr + ':' + DAEMON_PORT +
         '/desc.xml' + CRLF +
       'NT: upnp:rootdevice'+ CRLF +
       'NTS: ssdp:alive'+ CRLF +
       'SERVER: ' + HTTP_HEAD_SERVER + CRLF +
       'USN: uuid:' + UUID + '::upnp:rootdevice' +
       CRLF + CRLF;

      sock.SendString(s);

      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'CACHE-CONTROL: max-age=1800'+ CRLF +
       'LOCATION: http://' + MyIPAddr + ':' + DAEMON_PORT +
         '/desc.xml' + CRLF +
       'NT: uuid:' + UUID + CRLF +
       'NTS: ssdp:alive'+ CRLF +
       'SERVER: ' + HTTP_HEAD_SERVER + CRLF +
       'USN: uuid:' + UUID +
       CRLF + CRLF;

      sock.SendString(s);
      //}

      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'CACHE-CONTROL: max-age=1800'+ CRLF +
       'LOCATION: http://' + MyIPAddr + ':' + DAEMON_PORT +
         '/desc.xml' + CRLF +
       'NT: urn:schemas-upnp-org:device:MediaServer:1' + CRLF +
       'NTS: ssdp:alive'+ CRLF +
       'SERVER: ' + HTTP_HEAD_SERVER + CRLF +
       'USN: uuid:' + UUID + '::urn:schemas-upnp-org:device:MediaServer:1' +
       CRLF + CRLF;

      sock.SendString(s);

      //{
      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'CACHE-CONTROL: max-age=1800'+ CRLF +
       'LOCATION: http://' + MyIPAddr + ':' + DAEMON_PORT +
         '/desc.xml' + CRLF +
       'NT: urn:schemas-upnp-org:service:ContentDirectory:1' + CRLF +
       'NTS: ssdp:alive'+ CRLF +
       'SERVER: ' + HTTP_HEAD_SERVER + CRLF +
       'USN: uuid:' + UUID + '::urn:schemas-upnp-org:service:ContentDirectory:1' +
       CRLF + CRLF;

      sock.SendString(s);

      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'CACHE-CONTROL: max-age=1800'+ CRLF +
       'LOCATION: http://' + MyIPAddr + ':' + DAEMON_PORT +
         '/desc.xml' + CRLF +
       'NT: urn:schemas-upnp-org:service:ConnectionManager:1' + CRLF +
       'NTS: ssdp:alive'+ CRLF +
       'SERVER: ' + HTTP_HEAD_SERVER + CRLF +
       'USN: uuid:' + UUID + '::urn:schemas-upnp-org:service:ConnectionManager:1' +
       CRLF + CRLF;

      sock.SendString(s);
      //}
    end;
  finally
    sock.Free;
  end;
end;

procedure SendByebye;
var
  sock: TUDPBlockSocket;
  s: string;
begin
  // Sends an advertisement "byebye" message on multicast
  sock:= TUDPBlockSocket.Create;
  try
    Sock.Family:= SF_IP4;
    sock.CreateSocket();
    sock.Bind(MyIPAddr{'0.0.0.0'}, '0');
    sock.MulticastTTL:= 1;
    sock.Connect('239.255.255.250', '1900'{SSDP});
    if sock.LastError = 0 then begin
      //{
      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'NT: upnp:rootdevice'+ CRLF +
       'NTS: ssdp:byebye'+ CRLF +
       'USN: uuid:' + UUID + '::upnp:rootdevice' +
       CRLF + CRLF;

      sock.SendString(s);
      //}

      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'NT: urn:schemas-upnp-org:device:MediaServer:1' + CRLF +
       'NTS: ssdp:byebye'+ CRLF +
       'USN: uuid:' + UUID + '::urn:schemas-upnp-org:device:MediaServer:1' +
       CRLF + CRLF;

      sock.SendString(s);

      //{
      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'NT: urn:schemas-upnp-org:service:ContentDirectory:1' + CRLF +
       'NTS: ssdp:byebye'+ CRLF +
       'USN: uuid:' + UUID + '::urn:schemas-upnp-org:service:ContentDirectory:1' +
       CRLF + CRLF;

      sock.SendString(s);

      s:=
       'NOTIFY * HTTP/1.1' + CRLF +
       'HOST: 239.255.255.250:1900'+ CRLF +
       'NT: urn:schemas-upnp-org:service:ConnectionManager:1' + CRLF +
       'NTS: ssdp:byebye'+ CRLF +
       'USN: uuid:' + UUID + '::urn:schemas-upnp-org:service:ConnectionManager:1' +
       CRLF + CRLF;

      sock.SendString(s);
      //}
    end;
  finally
    sock.Free;
  end;
end;

function GetLineHeader: string;
begin
  Result:=  '*** ' + FormatDateTime('mm/dd hh:nn:ss ', Now);
end;

var
  PrevWndProc: WNDPROC;

{$IFDEF Windows}
function WndCallback(Ahwnd: HWND; uMsg: UINT; wParam: WParam; lParam: LParam):LRESULT; stdcall;
var
  msg: TMessage;
begin
  case uMsg of
    WM_POWERBROADCAST: begin
      msg.Result:= Windows.DefWindowProc(Ahwnd, uMsg, WParam, LParam);  //not sure about this one
      msg.msg:= uMsg;
      msg.wParam:= wParam;
      msg.lParam:= lParam;
      MyApp.WMPowerBoadcast(msg);
      Result:= msg.Result;
      Exit;
    end;
    WM_ENDSESSION: begin
      SendByebye;
    end;
  end;
  result:=CallWindowProc(PrevWndProc,Ahwnd, uMsg, WParam, LParam);
end;
{$ENDIF}

procedure InitAfterApplicationInitialize;
begin
  {$IFDEF Windows}
  PrevWndProc:= {%H-}Windows.WNDPROC(SetWindowLong(Widgetset.AppHandle, GWL_WNDPROC,{%H-}PtrInt(@WndCallback)));
  {$ENDIF}
end;

{ TMyApp }

constructor TMyApp.Create;
var
  mi: TMenuItem;
  i: integer;
  sl: TStringList;
  sock: TBlockSocket;
  s, tray_msg: String;
begin
  tray_msg:= '';
  UUID:= '';
  if FileExistsUTF8(ExecPath + 'UUID') then begin
    sl:= TStringListUTF8.Create;
    try
      sl.LoadFromFile(ExecPath + 'UUID');
      if sl.Count > 0 then UUID:= sl[0];
    finally
      sl.Free;
    end;
  end;

  if UUID = '' then begin
    UUID:= Copy(CreateClassID, 2, 36); // 新しいUUIDを作成
    sl:= TStringListUTF8.Create;
    try
      sl.Add(UUID);
      sl.SaveToFile(ExecPath + 'UUID');
    finally
      sl.Free;
    end;
  end;

  DAEMON_PORT:= iniFile.ReadString(INI_SEC_SYSTEM, 'HTTP_PORT', '5008');
  Log:= TStringListUTF8.Create;

  MAX_REQUEST_COUNT:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'MAX_REQUEST_COUNT', 0);
  SEND_DATA_TIMEOUT:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'SEND_DATA_TIMEOUT', 60*60);
  if SEND_DATA_TIMEOUT > 0 then SEND_DATA_TIMEOUT:= SEND_DATA_TIMEOUT * 1000
  else SEND_DATA_TIMEOUT:= MaxInt;

  MediaDirs:= TStringListUTF8.Create;
  iniFile.ReadSectionValues('MediaDirs', MediaDirs);
  i:= 0;
  while i < MediaDirs.Count do begin
    if (MediaDirs.Names[i] = '') or (MediaDirs.ValueFromIndex[i] = '') or
     (Trim(MediaDirs[i])[1] = ';') then begin
      MediaDirs.Delete(i);
    end else
      Inc(i);
  end;
  if MediaDirs.Count = 0 then
    tray_msg:= tray_msg + CR + 'ERROR: bms.iniにおいて[MediaDirs]が未設定です。';

  if not DirectoryExistsUTF8(TempPath) then
    ForceDirectoriesUTF8(TempPath);

  ClientInfoList:= TStringListUTF8_mod.Create;
  ClientInfoList.Sorted:= True;

  thMIC:= TMediaInfoCollector.Create;
  try
    thMIC.LoadMediaInfo;
  except
    tray_msg:= tray_msg + CR + 'ERROR: ' + MEDIA_INFO_DB_FILENAME + 'が破損しています。';
  end;

  sl:= TStringListUTF8.Create;
  try
    iniFile.ReadSections(sl);
    if sl.IndexOf(INI_SEC_MIKeys) < 0 then
      tray_msg:= tray_msg + CR + 'WARNING: bms.iniにおいて[' + INI_SEC_MIKeys + ']が未設定です。';
  finally
    sl.Free;
  end;
  thMIC.Start;

  SIPCServer:= TMySimpleIPCServer.Create;
  SIPCServer.ServerID:= 'SIPC:' + SHORT_APP_NAME + SHORT_APP_VERSION + ':' + DAEMON_PORT;
  SIPCServer.vsl.Vals['UserScripts']:= iniFile.ReadString(INI_SEC_SCRIPTS, 'user', '');
  SIPCServer.OnMessage:= @SIPCServer.DoMessage;
  SIPCServer.Global:= True;
  SIPCServer.StartServer;

  sl:= TStringListUTF8.Create;
  try
    sock:= TBlockSocket.Create;
    try
      sock.Family:= SF_IP4;
      sock.ResolveNameToIP(sock.LocalName, sl);
      if sl.Count > 0 then begin
        s:= iniFile.ReadString(INI_SEC_SYSTEM, 'IP_INTERFACE', '');
        if s <> '' then begin
          i:= StrToIntDef(s, 0);
          if i > 0 then begin
            if i <= sl.Count then
              MyIPAddr:= sl[i-1];
          end else if sl.IndexOf(s) >= 0 then
            MyIPAddr:= s;
        end;
        if MyIPAddr = '' then
          MyIPAddr:= sl[0];
      end;
    finally
      sock.Free;
    end;
  finally
    sl.Free;
  end;

  if MyIPAddr <> '' then begin
    // Run HTTP Daemon
    thHttpDaemon:= THttpDaemon.Create;
    // Run SSDP Daemon
    thSSDPDaemon:= TSSDPDaemon.Create;
    //SendAlive;
  end else begin
    tray_msg:= tray_msg + CR + 'ERROR: 自己 IP アドレスが取得できませんでした。';
  end;

  PopupMenu:= TPopupMenu.Create(nil);
  mi:= TMenuItem.Create(nil);
  mi.Caption:= '&Show';
  mi.OnClick:= @OnMenuShowClick;
  PopupMenu.Items.Add(mi);
  mi:= TMenuItem.Create(nil);
  mi.Caption:= '-';
  PopupMenu.Items.Add(mi);
  mi:= TMenuItem.Create(nil);
  mi.Caption:= '&Quit';
  mi.OnClick:= @OnMenuQuitClick;
  PopupMenu.Items.Add(mi);

  TrayIcon.PopUpMenu := PopupMenu;
  TrayIcon.OnClick:= @MyApp.OnTrayIconClick;

  if tray_msg <> '' then begin
    TrayIcon.BalloonHint:= tray_msg;
    TrayIcon.ShowBalloonHint;
  end;
end;

destructor TMyApp.Destroy;
var
  i: Integer;
begin
  SendByebye;
  if Assigned(thSSDPDaemon) then begin
    thSSDPDaemon.Terminate;
    //thSSDPDaemon.Sock.CloseSocket;
    thSSDPDaemon.WaitFor;
    thSSDPDaemon.Free;
  end;
  if Assigned(thHttpDaemon) then begin
    thHttpDaemon.Terminate;
    //thHTTPDaemon.Sock.CloseSocket;
    thHttpDaemon.WaitFor;
    thHttpDaemon.Free;
  end;
  SIPCServer.Free;
  if Assigned(thMIC) then begin
    tHMIC.Suspended:= False;
    thMIC.Terminate;
    thMIC.WaitFor;
    if iniFile.ReadInteger(INI_SEC_SYSTEM, 'SAVE_MEDIAINFO', 0) <> 0 then begin
      try
        thMIC.SaveMediaInfo;
      except
      end;
    end else begin
      DeleteFileUTF8(ExecPath + 'db/' + MEDIA_INFO_DB_FILENAME);
    end;
    thMIC.Free;
  end;
  for i:= 0 to ClientInfoList.Count-1 do ClientInfoList.Objects[i].Free;
  ClientInfoList.Free;
  Log.Free;
  LogFile.Free;
  MediaDirs.Free;
  while PopupMenu.Items.Count > 0 do begin
    PopupMenu.Items[0].Free;
    //PopupMenu.Items.Delete(0);
  end;
  PopupMenu.Free;
  inherited Destroy;
end;

procedure TMyApp.OnTrayIconClick(Sender: TObject);
begin
  if Assigned(Form1) then begin
    Form1.Show;
    Form1.WindowState:= wsNormal;
  end else begin
    Application.CreateForm(TForm1, Form1);
    try
      //TrayIcon.PopupMenu.Items[1].Visible:= False;
      if Form1.ShowModal = mrClose then begin
        Application.Terminate;
        Exit;
      end;
      //TrayIcon.PopupMenu.Items[1].Visible:= True;
    finally
      FreeAndNil(Form1);
    end;
  end;
end;

procedure TMyApp.OnMenuShowClick(Sender: TObject);
begin
  OnTrayIconClick(nil);
end;

procedure TMyApp.OnMenuQuitClick(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TMyApp.AddLog(const line: string);
var
  s: string;
begin
  Log.Add(line);
  while Log.Count > MAX_ONMEM_LOG do Log.Delete(0);
  if Assigned(LogFile) then begin
    s:= line + CRLF;
    LogFile.Write(s[1], Length(s));
  end;
end;

procedure TMyApp.WMPowerBoadcast(var msg: TMessage);
begin
  case msg.WParam of
    $0004{PBT_APMSUSPEND}, $0005{PBT_APMSTANDBY}: begin
      MyApp.AddLog(GetLineHeader + ' GO TO SLEEP...' + CRLF + CRLF);
      SendByebye();
    end;
    // $0007{PBT_APMRESUMESUSPEND}, $0008{PBT_APMRESUMESTANDBY}: begin
    $0012{PBT_APMRESUMEAUTOMATIC}: begin
      MyApp.AddLog(GetLineHeader + ' WAKE UP!!!' + CRLF + CRLF);
      SendAlive; // alive
      thHTTPDaemon.SendAliveFlag:= True;
    end;
  end;
end;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption:= APP_NAME + ' ' + APP_VERSION;
  MemoLog.Text:= MyApp.Log.Text;
  MemoLog.CaretX:= 0;
  MemoLog.CaretY:= MemoLog.Lines.Count+10;
  //MemoLog.EnsureCursorPosVisible;
  Application.QueueAsyncCall(@AsyncFromCreate, 0);
  CheckBoxLog.OnChange:= nil;
  CheckBoxLog.Checked:= Assigned(MyApp.LogFile);
  CheckBoxLog.OnChange:= @CheckBoxLogChange;
end;

procedure TForm1.AsyncFromCreate(Data: PtrInt);
begin
  MemoLog.EnsureCursorPosVisible;
end;

procedure TForm1.CheckBoxLogChange(Sender: TObject);
var
  fn: string;
begin
  fn:= ExecPath + FormatDateTime('yyyy-mm-dd-hh-mm-ss', Now) + '.log';
  if CheckBoxLog.Checked then begin
    MyApp.Log.SaveToFile(fn);
    MyApp.LogFile:= TFileStreamUTF8.Create(fn, fmOpenReadWrite or fmShareExclusive);
    MyApp.LogFile.Seek(0, soEnd);
  end else begin
    FreeAndNil(MyApp.LogFile);
  end;
end;

procedure TForm1.BitBtn2Click(Sender: TObject);
begin
  MemoLog.Lines.BeginUpdate;
  try
    MemoLog.Text:= MyApp.Log.Text;
    MemoLog.CaretX:= 0;
    MemoLog.CaretY:= MemoLog.Lines.Count;
    MemoLog.EnsureCursorPosVisible;
  finally
    MemoLog.Lines.EndUpdate;
  end;
end;

{ THttpDaemon }

procedure THttpDaemon.AddLog;
begin
  if not Assigned(MyApp) then Exit;
  MyApp.AddLog(line);
  line:= '';
end;

constructor THttpDaemon.Create;
begin
  th_list:= TObjectList.Create(False);
  FreeOnTerminate:= False;
  inherited Create(False);
end;

destructor THttpDaemon.Destroy;
var
  th: THttpThrd;
  i: integer;
begin
  for i:= 0 to th_list.Count-1 do begin
    th:= THttpThrd(th_list[i]);
    th.Terminate;
    if Assigned(th.Sock) then th.Sock.AbortSocket;
    th.WaitFor;
    th.Free;
  end;
  th_list.Free;
  Sock.Free;
  inherited Destroy;
end;

procedure THttpDaemon.Execute;

  procedure InitSocket;
  begin
    Sock.Family:= SF_IP4;
    Sock.CreateSocket();
    if Sock.LastError <> 0 then raise Exception.Create(Sock.LastErrorDesc);
    Sock.SetLinger(True, 10000);
    //Sock.EnableReuse(True);
    Sock.Bind(MyIPAddr{'0.0.0.0'}, DAEMON_PORT); // ソケット登録
    if Sock.LastError <> 0 then raise Exception.Create(Sock.LastErrorDesc);
    Sock.Listen; // 接続準備
    if Sock.LastError <> 0 then raise Exception.Create(Sock.LastErrorDesc);
  end;

  procedure CleanThreadList;
  var
    th: THttpThrd;
    i: integer;
  begin
    i:= 0;
    while i < th_list.Count do begin
      th:= THttpThrd(th_list[i]);
      if th.Done then begin
        th.Terminate; // 念のため
        th.WaitFor; // 念のため
        th.Free;
        th_list.Delete(i);
      end else
        Inc(i);
    end;
  end;

var
  th: THttpThrd;
  ci: TClientInfo;
  i, c: integer;
  s: string;
begin
  try
    Sock:= TTCPBlockSocket.Create;
    InitSocket;
    SendAliveFlag:= True;
    c:= 0;
    while not Terminated do begin
      if SendAliveFlag then begin
        Inc(c);
        if c mod 5 = 0 then SendAlive; // 5秒毎に創出
        if c >= 300 then begin // 5分間が限度
          c:= 0;
          SendAliveFlag:= False;
        end;
      end;

      if Sock.CanRead(1000) then begin
        if Sock.LastError = 0 then begin
          th:= THttpThrd.Create(Sock.Accept); // 接続待機
          th_list.Add(th);

          if SendAliveFlag then begin
            s:= Sock.GetRemoteSinIP;
            if (MyIPAddr <> s) and (s <> '127.0.0.1') then begin
              SendAlive; // 念のため
              c:= 0;
              SendAliveFlag:= False;
            end;
          end;
        end;
      end;

      if th_list.Count > 10 then CleanThreadList; // ごみ処理

      if ClientInfoList.Count > 10 then begin
        // ごみ処理
        i:= 0;
        while i < ClientInfoList.Count do begin
          ci:= TClientInfo(ClientInfoList.Objects[i]);
          if Now - ci.LastAccTime > EncodeTime(6, 0, 0, 0) then begin
            ClientInfoList.Objects[i].Free;
            ClientInfoList.Delete(i);
          end else
            Inc(i);
        end;
      end;
    end;

  except
    on e: Exception do begin
      line:= '*** ERROR HTTPD : ' + e.Message + CRLF + CRLF;
      Synchronize(@AddLog);
    end;
  end;
end;

{ THttpThrd }

procedure THttpThrd.AddLog;
begin
  if not Assigned(MyApp) then Exit;
  MyApp.AddLog(line);
  line:= '';
end;

constructor THttpThrd.Create(hSock: TSocket);
begin
  Sock:= TTCPBlockSocket.Create;
  Sock.Family:= SF_IP4;
  Sock.Socket:= hSock;
  FreeOnTerminate:= False;
  Priority:= tpNormal;
  inherited Create(False);
end;

destructor THttpThrd.Destroy;
begin
  Sock.Free;
  inherited Destroy;
end;

procedure THttpThrd.Execute;
const
  TIMEOUT = 10 * 60 * 1000;
var
  s, rcv, cIP: string;
  method, uri, protocol: string;
  size: int64;
  x, i, cPort: integer;
  resultcode: integer;
  close: boolean;
begin
  Sock.SetSendTimeout(TIMEOUT);
  try
    Done:= False;
    L_S:= lua_newstate(@alloc, nil);
    Headers:= TStringListUTF8_mod.Create;
    InputData:= TMemoryStream.Create;
    OutputData:= TMemoryStream.Create;
    try
      cIP:= Sock.GetRemoteSinIP;
      cPort:= Sock.GetRemoteSinPort;
      line:= GetLineHeader + Format('%s:%d Connected. (ID=%d)',
       [cIP, cPort, Self.FThreadID]) + CRLF + CRLF;

      i:= ClientInfoList.IndexOf(cIP);
      if i < 0 then begin
        ClientInfo:= TClientInfo.Create;
        ClientInfoList.AddObject(cIP, ClientInfo);
      end else
        ClientInfo:= TClientInfo(ClientInfoList.Objects[i]);
      ClientInfo.LastAccTime:= Now;

      InitLua(L_S);
      LoadLua(L_S, 'common', ClientInfo.chunks);

      repeat
        if Terminated then Break;
        try
          //read request header
          line:= line + GetLineHeader + Format('%s:%d Read Request. (ID=%d)',
           [cIP, cPort, Self.FThreadID]) + CRLF + CRLF;
          rcv:= '';
          size := -1;
          close := false;
          repeat
            s:= Sock.RecvString(TIMEOUT);
            if Sock.LastError <> 0 then Exit;
            if (s = '') or not (s[1] in [' ', #$09]) then
              rcv:= rcv + s + CR
            else
              rcv:= Copy(rcv, 1, Length(rcv)-1) + TrimLeft(s) + CR;

            if Pos('CONTENT-LENGTH:', Uppercase(s)) = 1 then
              size:= StrToInt64Def(SeparateRight(s, ' '), -1);
            if Pos('CONNECTION: CLOSE', Uppercase(s)) = 1 then
              close:= true;
            line:= line + s + CRLF;
          until s = '';

          InHeader:= rcv;
          method:= fetch(InHeader, ' ');
          if (InHeader = '') or (method = '') then Exit;
          uri:= fetch(InHeader, ' ');
          if uri = '' then Exit;
          protocol:= fetch(InHeader, CR);
          if Pos('HTTP/', protocol) <> 1 then Exit;
          if Pos('HTTP/1.1', protocol) <> 1 then close := true;

          if (uri = '/desc.xml') or (ClientInfo.ScriptFileName = '') then begin
            lua_getglobal(L_S, 'BMS');
            lua_getfield(L_S, -1, 'GetScriptFileName');
            lua_remove(L_S, -2); // remove BMS
            lua_pushstring(L_S, InHeader);
            lua_pushstring(L_S, Sock.GetRemoteSinIP);
            lua_pushstring(L_S, uri);
            CallLua(L_S, 3, 1);
            ClientInfo.ScriptFileName:= lua_tostring(L_S, 1);
            lua_pop(L_S, 1);

            ClientInfo.InfoTable.Clear;
            lua_getglobal(L_S, 'BMS');
            lua_getfield(L_S, -1, 'ClientInfo');
            lua_remove(L_S, -2); // remove BMS
            LuaTable2ValStringList(L_S, ClientInfo.InfoTable);
            lua_pop(L_S, 1);
            if ClientInfo.ScriptFileName <> '' then
              line:= line + '*** ScriptName = ' + ClientInfo.ScriptFileName + CRLF + CRLF;
          end;

          if ClientInfo.ScriptFileName <> '' then begin
            LoadLua(L_S, ClientInfo.ScriptFileName, ClientInfo.chunks);

            ClientInfo.L_S:= L_S;
            ClientInfo.SortType:= 1;
            lua_getglobal(L_S, 'BMS');
            lua_getfield(L_S, -1, 'MediaListSortType');
            if not lua_isnil(L_S, -1) then
              ClientInfo.SortType:= lua_tointeger(L_S, -1);;
            lua_pop(L_S, 1);

            lua_getfield(L_S, -1, 'ClientInfo');
            ValStringList2LuaTable(L_S, ClientInfo.InfoTable);
            lua_pop(L_S, 1);
            lua_pop(L_S, 1); // remove BMS table
          end;

          //recv document...
          InputData.Clear;
          if size >= 0 then begin
            if Terminated then Break;
            InputData.SetSize(Size);
            x:= Sock.RecvBufferEx(InputData.Memory, size, TIMEOUT);
            InputData.SetSize(x);
            if Sock.LastError <> 0 then Exit;

            SetLength(s, x);
            strlcopy(PChar(s), InputData.Memory, x);
            line:= line + s + CRLF + CRLF;
          end;

          if Terminated then Break;

          line:= line + GetLineHeader + Format('%s:%d Sent Response. (ID=%d)',
           [cIP, cPort, Self.FThreadID]) + CRLF + CRLF;

          UniOutput:= False;
          Headers.Clear;
          OutputData.Clear;
          ResultCode:= ProcessHttpRequest(method, uri);
          if UniOutput = False then begin
            s:= protocol + ' ' + IntTostr(ResultCode);
            case ResultCode of
              200: s:= s + ' OK';
              404: s:= s + ' Not Found';
              406: s:= s + ' Not Acceptable';
              //500: s:= s + ' Internal Server Error';
            end;

            s:= s + CRLF;
            if Terminated then Break;
            sock.SendString(s);
            if Sock.LastError <> 0 then Exit;
            line:= line + s;
            if protocol <> '' then begin
              if close then
                Headers.Add('Connection: close')
              else
                Headers.Add('Connection: Keep-Alive');
              Headers.Add('Content-Length: ' + IntTostr(OutputData.Size));
              Headers.Add('Date: ' + Rfc822DateTime(now));
              Headers.Add('Server: ' + HTTP_HEAD_SERVER);
              Headers.Add('');
              for i:= 0 to Headers.Count - 1 do begin
                if Terminated then Break;
                Sock.SendString(Headers[i] + CRLF);
                if Sock.LastError <> 0 then Exit;
                line:= line + Headers[i] + CRLF;
              end;
              if UpperCase(protocol) = 'HEAD' then OutputData.Clear;
            end;

            if Terminated then Break;
            Sock.SendBuffer(OutputData.Memory, OutputData.Size);
          end;

          if close then Break;
        finally
          if line <> '' then Synchronize(@AddLog);
        end;
      until Sock.LastError <> 0;
    finally
      s:= '';
      if Sock.LastError <> 0 then
        s:= Format(', %d:%s', [Sock.LastError, Sock.LastErrorDesc]);
      line:= GetLineHeader + Format('%s:%d Disconnected. (ID=%d%s)',
       [cIP, cPort, Self.FThreadID, s]) + CRLF + CRLF;
      Synchronize(@AddLog);

      lua_close(L_S);
      FreeAndNil(Sock); //
      Headers.Free;
      InputData.Free;
      OutputData.Free;
      line:= '';
      InHeader:= '';
      Done:= True;
    end;
  except
    on e: Exception do begin
      line:= line + '*** ERROR HTTPT: ' + e.Message + CRLF + CRLF;
      Synchronize(@AddLog);
    end;
  end;
end;

function THttpThrd.ProcessHttpRequest(const request, uri: string): integer;
var
  docr, docw: TXMLDocument;
  item, val: TDOMNode;
  s: string;
  i, c: integer;
begin
  Result:= 404;
  if (request = 'GET') or (request = 'HEAD') then begin
    if uri = '/desc.xml' then begin // UPnP Device description MediaServer
      Headers.Clear;
      Headers.Add('Content-Type: text/xml; charset="utf-8"');
      Headers.Add('Cache-Control: no-cache');
      //Headers.Add('Expires: 0');
      Headers.Add('Accept-Ranges: bytes');

      s:= ExecPath + 'data_user/desc.xml';
      if not FileExistsUTF8(s) then s:= ExecPath + 'data/desc.xml';
      readXMLFile(docw, {UTF8FILENAME}UTF8ToSys(s));
      try
        with docw do begin

          item:= DocumentElement.FindNode('URLBase');
          if item = nil then Exit;
          item.TextContent:= 'http://' +  MyIPAddr + ':' + DAEMON_PORT + '/';

          item:= DocumentElement.FindNode('device');
          if item = nil then Exit;
          with item do begin
            val:= FindNode('friendlyName');
            if val = nil then Exit;
            s:= iniFile.ReadString(INI_SEC_SYSTEM, 'SERVER_NAME', SHORT_APP_NAME + ' : %LOCALNAME%');
            s:= StringReplace(s, '%LOCALNAME%', Sock.LocalName, [rfReplaceAll, rfIgnoreCase]);
            val.TextContent:= UTF8Decode(s);

            val:= FindNode('UDN');
            if val = nil then Exit;
            val.TextContent:= 'uuid:' + UUID;

            {
            val:= FindNode('presentationURL');
            if val = nil then Exit;
            val.TextContent:= 'http://' + MyIPAddr + ':' + DAEMON_PORT + '/index.html';
            }
          end;
        end;
        writeXMLFile(docw, OutputData);
      finally
        docw.Free;
      end;

      Result:= 200;
    end else if (uri = '/UPnP_AV_ContentDirectory_1.0.xml') or
     (uri = '/UPnP_AV_ConnectionManager_1.0.xml') then begin // UPnP Service description
      //<SCPDURL>/UPnP_AV_ContentDirectory_1.0.xml</SCPDURL>
      //<SCPDURL>/UPnP_AV_ConnectionManager_1.0.xml</SCPDURL>
      Headers.Clear;
      Headers.Add('Content-Type: text/xml; charset="utf-8"');
      Headers.Add('Cache-Control: no-cache');
      //Headers.Add('Expires: 0');
      Headers.Add('Accept-Ranges: bytes');

      s:= ExecPath + 'data_user' + uri;
      if not FileExistsUTF8(s) then s:= ExecPath + 'data' + uri;
      readXMLFile(docw, {UTF8FILENAME}UTF8ToSys(s));
      try
        writeXMLFile(docw, OutputData);
      finally
        docw.Free;
      end;

      Result:= 200;
    end else if (uri = '/images/icon-256.png') then begin
      Headers.Clear;
      Headers.Add('Content-Type: image/png');
      Headers.Add('Accept-Ranges: bytes');
      //Headers.Add('Expires: 0');

      try
        OutputData.LoadFromFile({UTF8FILENAME}UTF8ToSys(ExecPath + 'data/' +
         iniFile.ReadString(INI_SEC_SYSTEM, 'ICON_IMAGE', 'icon.png')));
        Result:= 200;
      except
        OutputData.LoadFromFile({UTF8FILENAME}UTF8ToSys(ExecPath + 'DATA/icon.png'));
        Result:= 200;
      end;
    end else if Pos('/p1/', uri) = 1 then begin
      if ClientInfo.ScriptFileName = '' then Exit;
      Headers.Clear;

      s:= DecodeX(Copy(uri, Length('/p1/')+1, MaxInt));
      if not FileExistsUTF8(s) then Exit;
      if not DoPlay(s, request) then Exit;

      Result:= 200;
    end else if Pos('/p2/', uri) = 1 then begin
      if ClientInfo.ScriptFileName = '' then Exit;
      Headers.Clear;

      s:= DecodeX(Copy(uri, Length('/p2/')+1, MaxInt));
      i:= StrToInt(Fetch(s, #$09));
      if not FileExistsUTF8(s) then Exit;
      if not DoPlayTranscode(i, s, request) then Exit;

      Result:= 200;
    end;
  end else if request = 'POST' then begin
    if ClientInfo.ScriptFileName = '' then Exit;
    if Pos('/upnp/control/', uri) = 1 then begin
      //<controlURL>/upnp/control/content_directory</controlURL>
      //<controlURL>/upnp/control/connection_manager</controlURL>
      Headers.Clear;
      Headers.Add('Content-Type: text/xml; charset="utf-8"');

      docw:= TXMLDocument.Create;
      readXMLFile(docr, InputData);
      try
        with docw do begin
          //Encoding:= 'utf-8';
          with TDOMElement(AppendChild(CreateElement('s:Envelope'))) do begin
            SetAttribute('xmlns:s', 'http://schemas.xmlsoap.org/soap/envelope/');
            SetAttribute('s:encodingStyle', 'http://schemas.xmlsoap.org/soap/encoding/');
            with TDOMElement(AppendChild(CreateElement('s:Body'))) do begin
              if uri = '/upnp/control/content_directory' then begin
                //SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#GetSystemUpdateID"
                //SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#GetSearchCapabilities"
                //SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#GetSortCapabilities"
                //SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#Browse"
                //SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#Search"
                val:= docr.DocumentElement.FindNode('s:Body');
                if val = nil then Exit;
                s:= val.ChildNodes.Item[0].NodeName;
                if s = 'u:GetSystemUpdateID' then begin
                  with TDOMElement(AppendChild(CreateElement(s+'Response'))) do begin
                    SetAttribute('xmlns:u', 'urn:schemas-upnp-org:service:ContentDirectory:1');
                    with TDOMElement(AppendChild(CreateElement('Id'))) do begin
                      AppendChild(CreateTextNode('1'));
                    end;
                  end;
                end else if s = 'u:GetSearchCapabilities' then begin
                  with TDOMElement(AppendChild(CreateElement(s+'Response'))) do begin
                    SetAttribute('xmlns:u', 'urn:schemas-upnp-org:service:ContentDirectory:1');
                    AppendChild(CreateElement('SearchCaps'));
                  end;
                end else if s = 'u:GetSortCapabilities' then begin
                  with TDOMElement(AppendChild(CreateElement(s+'Response'))) do begin
                    SetAttribute('xmlns:u', 'urn:schemas-upnp-org:service:ContentDirectory:1');
                    AppendChild(CreateElement('SortCaps'));
                  end;
                end else if s = 'u:Browse' then begin
                  DoBrowse(docr, docw);
                end else if s = 'u:Search' then begin
                  DoBrowse(docr, docw);
                end else begin
                  Exit; // 未対応
                end;
              end else if uri = '/upnp/control/connection_manager' then begin
                //SOAPACTION: "urn:schemas-upnp-org:service:ConnectionManager:1#GetCurrentConnectionInfo"
                //SOAPACTION: "urn:schemas-upnp-org:service:ConnectionManager:1#ConnectionComplete"
                //SOAPACTION: "urn:schemas-upnp-org:service:ConnectionManager:1#PrepareForConnection"
                //SOAPACTION: "urn:schemas-upnp-org:service:ConnectionManager:1#GetProtocolInfo"
                //SOAPACTION: "urn:schemas-upnp-org:service:ConnectionManager:1#GetCurrentConnectionIDs"
                val:= docr.DocumentElement.FindNode('s:Body');
                if val = nil then Exit;
                s:= val.ChildNodes.Item[0].NodeName;
                if s = 'u:GetCurrentConnectionInfo' then begin
                  Exit; // 未実装
                end else if s = 'u:ConnectionComplete' then begin
                  Exit; // 未実装
                end else if s = 'u:PrepareForConnection' then begin
                  Exit; // 未実装
                end else if s = 'u:GetProtocolInfo' then begin
                  with TDOMElement(AppendChild(CreateElement(s+'Response'))) do begin
                    SetAttribute('xmlns:u', 'urn:schemas-upnp-org:service:ConnectionManager:1');
                    with TDOMElement(AppendChild(CreateElement('Source'))) do begin
                      lua_getglobal(L_S, 'BMS');
                      lua_getfield(L_S, -1, 'SUPPORT_MEDIA_LIST');
                      lua_remove(L_S, -2); // remove BMS
                      c:= lua_rawlen(L_S, -1);
                      s:= '';
                      for i:= 1 to c do begin
                        lua_pushnumber(L_S, i);
                        lua_gettable(L_S, -2);
                        if s <> '' then s:= s + ',';
                        s:= s + 'http-get:*:' + lua_tostring(L_S, -1);
                        lua_pop(L_S, 1);
                      end;
                      lua_pop(L_S, 1);
                      AppendChild(CreateTextNode(s));
                    end;
                    AppendChild(CreateElement('Sink'));
                  end;
                end else if s = 'u:GetCurrentConnectionIDs' then begin
                  Exit; // 未実装
                end else begin
                  Exit; // 未対応
                end;
              end;
            end;
          end;
        end;
        writeXMLFile(docw, OutputData);
      finally
        docw.Free;
        docr.Free;
      end;

      Result:= 200;
    end;
  end else if request = 'SUBSCRIBE' then begin
    Headers.Clear;
    Headers.Add('SID: uuid:' + UUID);
    Headers.Add('TIMEOUT: Second-300');

    Result:= 200;
  end else if request = 'UNSUBSCRIBE' then begin
    Headers.Clear;

    Result:= 200;
  end else if request = 'NOTIFY' then begin
    Headers.Clear;
    Headers.Add('Content-Type: text/xml; charset="utf-8"');
    Headers.Add('NT: upnp:event');
    Headers.Add('NTS: upnp:propchange');
    Headers.Add('SID: uuid:' + UUID);
    Headers.Add('SEQ: 0');

    docw:= TXMLDocument.Create;
    try
      with docw do begin
        with TDOMElement(AppendChild(CreateElement('e:propertyset'))) do begin
          SetAttribute('xmlns:e', 'urn:schemas-upnp-org:event-1-0');
          with TDOMElement(AppendChild(CreateElement('e:property'))) do begin
            AppendChild(CreateElement('TransferIDs'));
          end;
          with TDOMElement(AppendChild(CreateElement('e:property'))) do begin
            AppendChild(CreateElement('ContainerUpdateIDs'));
          end;
          with TDOMElement(AppendChild(CreateElement('e:property'))) do begin
            with TDOMElement(AppendChild(CreateElement('SystemUpdateID'))) do begin
              AppendChild(CreateTextNode('1'));
            end;
          end;
        end;
      end;
      writeXMLFile(docw, OutputData);
    finally
      docw.Free;
    end;

    Result:= 200;
  end;
end;

function THttpThrd.DoBrowse(docr, docw: TXMLDocument): boolean;
var
  si, rc: integer;

  procedure GetFileList(const dir: string; sl: TStringList);
  var
    info: TSearchRec;
    sl2: TStringListUTF8;
    s, s2: string;
    i: integer;
    b: boolean;
    mi: TGetMediaInfo;
  begin
    sl.Clear;
    if FileExistsUTF8(dir) then begin
      s:= LowerCase(ExtractFileExt(dir));
      if (s = '.m3u') or (s = '.m3u8') then begin
        // m3u
        sl.Sorted:= False;
        sl2:= TStringListUTF8_mod.Create;
        try
          sl2.LoadFromFile(dir);
          b:= (sl.Count > 0) and (Length(sl[0]) >= 3) and
            (sl[0][1] = #$EF) and (sl[0][2] = #$BB) and (sl[0][3] = #$BF);
          if b then sl2[0]:= Copy(sl2[0], 4, MaxInt);
          b:= b or (s = '.m3u8');
          SetCurrentDirUTF8(ExtractFilePath(dir));
          for i:= 0 to sl2.Count-1 do begin
            s2:= Trim(sl2[i]);
            if (s2 <> '') and (s2 <> '#EXTM3U') and
             (Pos('#EXTINF:', s2) = 0) then begin

              if b then
                s2:= ExpandFileNameUTF8(s2)
              else
                s2:= AnsiToUTF8(ExpandFileName(s2));

              if DirectoryExistsUTF8(s2) then begin
                sl.Add(#2 + IncludeTrailingPathDelimiter(s2));
              end else begin
                s:= LowerCase(ExtractFileExt(s2));
                if (s = '.m3u') or (s = '.m3u8') then begin
                  mi:= thMIC.GetMediaInfo(s2);
                  try
                    mi.GetPlayInfo(L_S);
                    case mi.PlayInfo.Values['mime[1]'] of
                      '': ; // 表示しない
                      'M3U_FOLDER': sl.Add(#3 + s2);
                      else sl.Add(#$F + s2);
                    end;
                  finally
                    if mi.IsTemp then mi.Free;
                  end;
                end else begin
                  sl.Add(#$F + s2);
                end;
              end;
            end;
          end;
        finally
          sl2.Free;
        end;
      end;
    end else begin
      sl.Sorted:= True;
      sl.Duplicates:= dupAccept;
      if FindFirstUTF8(dir+'*', faAnyFile, info) = 0 then
        try
          repeat
            if (info.Name <> '.') and (info.Name <> '..') and
             (info.Attr and faHidden = 0) then begin
              if info.Attr and faDirectory <> 0 then begin
                sl.Add(#2 + dir + info.Name + DirectorySeparator);
              end else begin
                s:= LowerCase(ExtractFileExt(info.Name));
                if (s = '.m3u') or (s = '.m3u8') then begin
                  mi:= thMIC.GetMediaInfo(dir + info.Name);
                  try
                    mi.GetPlayInfo(L_S);
                    case mi.PlayInfo.Values['mime[1]'] of
                      '': ; // 表示しない
                      'M3U_FOLDER': sl.Add(#3 + dir + info.Name);
                      else sl.Add(#$F + dir + info.Name);
                    end;
                  finally
                    if mi.IsTemp then mi.Free;
                  end;
                end else if (s <> '.lua') and (s <> '.txt') then begin
                  sl.Add(#$F + dir + info.Name);
                end;
              end;
            end;
          until FindNextUTF8(info) <> 0;
        finally
          FindCloseUTF8(Info);
        end;
    end;
  end;

  procedure GetListInTrans(const dir: string; sl: TStringList);
  var
    i, c: integer;
    mi: TGetMediaInfo;
  begin
    sl.Clear;
    if FileExistsUTF8(dir) then begin
      // TRANSCODE
      mi:= thMIC.GetMediaInfo(dir);
      try
        mi.GetPlayInfo(L_S);
        sl.Sorted:= False;
        c:= StrToIntDef(mi.PlayInfo.Values['InfoCount'], 1);
        for i:= 1 to c do begin
          sl.Add(#$F + dir + #$09 + IntToStr(i) + '?t');
        end;
      finally
        if mi.IsTemp then mi.Free;
      end;
    end;
  end;

  procedure CleanMediaList(sl: TStringList; IsTrans: integer);
  var
    i, c, cc: integer;
    mi: TGetMediaInfo;
    s: String;
    b: boolean;
  begin
    if isTrans >= 0 then begin
      cc:= sl.Count;
      i:= 0;
    end else begin
      cc:= sl.Count;
      if cc > rc then cc:= rc;
      if (MAX_REQUEST_COUNT > 0) and (cc > MAX_REQUEST_COUNT) then cc:= MAX_REQUEST_COUNT;
      i:= si;
      if i > ClientInfo.FullInfoCount then i:= ClientInfo.FullInfoCount;
    end;

    c:= 0;
    while (c < cc) and (i < sl.Count) do begin
      s:= sl[i];
      if (s[1] = #$F) and (i >= ClientInfo.FullInfoCount) then begin
        mi:= thMIC.GetMediaInfo(Copy(s, 2, MaxInt));
        try
          mi.GetPlayInfo(L_S, True);
          case mi.PlayInfo.Values['mime[1]'] of
            '': begin
              // mime が '' なら表示しない
              b:= i = sl.Count - 1;
              sl.Delete(i);
              if b then i:= sl.Count;
              Continue;
            end;

            else begin
              if (mi.PlayInfo.Values['command[1]'] <> '') or
               (mi.PlayInfo.Values['IsFolder'] <> '') then begin
                // トランスコードの場合
                if mi.PlayInfo.Values['IsFolder'] <> '' then begin
                  s:= s + #$09'?T'; // トランスコフォルダの場合
                end else begin
                  s:= s + #$09'1?t';
                end;
                if sl.Sorted then begin
                  sl.Delete(i);
                  sl.Add(s);
                end else begin
                  sl[i]:= s;
                end;
              end;
            end;
          end; // case
        finally
          if mi.IsTemp then mi.Free;
        end;
      end;

      if i = IsTrans then begin
        GetListInTrans(Copy(sl[i], 2, Length(sl[i])-4), sl);
        ClientInfo.FullInfoCount:= sl.Count;
        Exit;
      end;

      if i >= si then Inc(c);
      Inc(i);
    end;

    if IsTrans >= 0 then begin
      // ERROR
      sl.Clear;
    end else begin
      if i > ClientInfo.FullInfoCount then ClientInfo.FullInfoCount:= i;
    end;
  end;

var
  parent, item, val: TDOMNode;
  mlist: TStringList;
  i, c, IsTransDir: integer;
  i64: int64;
  r, s, s1, fn, m, mt, id, dur, no, BrowseFlag: String;
  mi: TGetMediaInfo;
begin
  { <ObjectID>0</ObjectID>
   <BrowseFlag>BrowseDirectChildren</BrowseFlag>
   <Filter>
    dc:title,
    av:mediaClass,
    dc:date,
    @childCount,
    res,
    upnp:class,
    res@resolution,upnp:album,upnp:albumArtURI,upnp:albumArtURI@dlna:profileID,dc:creator,res@size,res@duration,res@bitrate,res@protocolInfo
    </Filter>
    <StartingIndex>0</StartingIndex>
    <RequestedCount>10</RequestedCount>
    <SortCriteria></SortCriteria>
  }

  Result:= False;

  item:= docr.DocumentElement.FindNode('s:Body');
  if item = nil then Exit;
  item:= item.FindNode('u:Browse');
  if item = nil then Exit;
  val:= item.FindNode('ObjectID');
  if val = nil then Exit;
  id:= val.TextContent;

  val:= item.FindNode('BrowseFlag'); // BrowseMetadata/BrowseDirectChildren
  if val = nil then Exit;
  BrowseFlag:= val.TextContent;
  if BrowseFlag = 'BrowseMetadata' then begin
    i:= RPos('$', id);
    if i > 1 then begin
      si:= StrToIntDef(Copy(id, i+1, MaxInt), 0);
      id:= Copy(id, 1, i-1);
    end else if id = '0' then begin
      si:= 0;
      id:= '-1';
    end else begin
      Exit;
    end;
  end else begin
    val:= item.FindNode('StartingIndex');
    if val = nil then Exit;
    si:= StrToIntDef(val.TextContent, 0);
  end;
  val:= item.FindNode('RequestedCount');
  if val = nil then Exit;
  rc:= StrToIntDef(val.TextContent, MaxInt);
  if rc < 1 then rc:= MaxInt;

  parent:= docw.DocumentElement.FindNode('s:Body');
  item:= docw.CreateElement('u:BrowseResponse');
  TDOMElement(item).SetAttribute(
   'xmlns:u', 'urn:schemas-upnp-org:service:ContentDirectory:1');
  parent.AppendChild(item);

  parent:= item; // >
  item:= docw.CreateElement('Result');
  parent.AppendChild(item);

  ClientInfo:= TClientInfo(ClientInfoList.Objects[
   ClientInfoList.IndexOf(Sock.GetRemoteSinIP)]);
  mlist:= ClientInfo.CurFileList;
  if id = '-1' then begin
    ClientInfo.CurId:= id; ClientInfo.CurDir:= '';
    mlist.Clear;
    mlist.Sorted:= False;
    mlist.Add(#1 + 'root');
  end else if id = '0' then begin
    ClientInfo.CurId:= id; ClientInfo.CurDir:= '';
    mlist.Clear;
    mlist.Sorted:= False;
    if MediaDirs.Count = 0 then begin
      mlist.Add(#1 + SHORT_APP_NAME + 'からのお知らせ: [MediaDirs]が未設定です');
    //end else if (thMIC.mi_list.Count < 100) and not thMIC.Suspended then begin
    //  for i:= 0 to MediaDirs.Count-1 do begin
    //    mlist.Add(#1 + 'メディア情報を収集中です。少しお待ちください');
    //  end;
    end else begin
      for i:= 0 to MediaDirs.Count-1 do begin
        mlist.Add(#1 + MediaDirs.Names[i]);
      end;
    end;
  end else begin
    IsTransDir:= -1;
    if ClientInfo.CurId <> id then begin
      s:= id;
      Fetch(s, '$');
      if s = '' then Exit;
      i:= StrToInt(Fetch(s, '$'));
      s1:= IncludeTrailingPathDelimiter(MediaDirs.ValueFromIndex[i]);
      GetFileList(s1, mlist);
      while s <> '' do begin
        i:= StrToInt(Fetch(s, '$'));
        if i >= mlist.Count then begin
          // ERROR
          mlist.Clear;
          Break;
        end;
        s1:= mlist[i];
        if s1[1] = #$F then begin
          IsTransDir:= i;
          Break;
        end;
        s1:= Copy(s1, 2, MaxInt);
        GetFileList(s1, mlist);
      end;
      ClientInfo.CurId:= id; ClientInfo.CurDir:= s1; ClientInfo.FullInfoCount:= 0;
    end;
    CleanMediaList(mlist, IsTransDir);
  end;

  c:= mlist.Count;
  if c > rc then c:= rc;
  if (MAX_REQUEST_COUNT > 0) and (c > MAX_REQUEST_COUNT) then c:= MAX_REQUEST_COUNT;
  if si + c > mlist.Count then c:= mlist.Count - si;

  r:= '<DIDL-Lite'+
  ' xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"'+
  ' xmlns:dc="http://purl.org/dc/elements/1.1/"'+
  ' xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">';

  for i:= si to si+c-1 do begin
    fn:= mlist[i];
    case fn[1] of
      #1, #2, #3: begin // folder(root, dir, m3u)
        s:= Copy(fn, 2, MaxInt);
        case fn[1] of
          #2: // dir
            s:= ExtractFileName(ExcludeTrailingPathDelimiter(s));
          #3: begin // m3u
            mi:= thMIC.GetMediaInfo(fn);
            try
              mi.GetPlayInfo(L_S);
              s:= mi.PlayInfo.Values['DispName'];
            finally
              if mi.IsTemp then mi.Free;
            end;
          end;
        end;

        lua_getglobal(L_S, 'BMS');
        lua_getfield(L_S, -1, 'GetFolderName');
        lua_remove(L_S, -2); // remove BMS
        lua_pushstring(L_S, s);
        CallLua(L_S, 1, 1);
        s:= lua_tostring(L_S, -1);
        lua_pop(L_S, 1);

        s:= StringReplace(s, '&', '&amp;', [rfReplaceAll]);
        s:= StringReplace(s, '<', '&lt;', [rfReplaceAll]);
        s:= StringReplace(s, '>', '&gt;', [rfReplaceAll]);
        s:= StringReplace(s, '''', '&apos;', [rfReplaceAll]);

        if id = '-1' then
          s1:= '0'
        else
          s1:= id + '$' + IntToStr(i);

        r:= r +
         '<container id="' + s1 + '" childCount="1"' +
         ' parentID="' + id + '" restricted="1">' +
         '<dc:title>' + s + '</dc:title><dc:date>0000-00-00T00:00:00</dc:date>'+
         '<upnp:class>object.container.storageFolder</upnp:class>'+
         '</container>';
      end;

      else begin
        if (Length(fn) >= 2) and (fn[Length(fn)-1] = '?') then begin
          case fn[Length(fn)] of
            't': begin // Transcode(File)
              no:= Copy(fn, 2, Length(fn)-3);
              fn:= Fetch(no, #$09);
              mi:= thMIC.GetMediaInfo(fn);
              try
                mi.GetPlayInfo(L_S);
                mt:= mi.PlayInfo.Values['mime['+no+']'];

                m:= ' protocolInfo="http-get:*:' + mt + '"';

                dur:= mi.PlayInfo.Values['duration['+no+']'];
                if dur = '' then
                  dur:= mi.Vals['General;Duration'];

                if dur <> '' then
                  m:= m + ' duration="' + dur + '"';

                if mi.PlayInfo.Values['IsFolder'] <> '' then begin
                  s:= mi.PlayInfo.Values['name['+no+']'];
                end else begin
                  s:= mi.PlayInfo.Values['DispName'];
                end;
                if s = '' then
                  s:= ExtractFileName(ExcludeTrailingPathDelimiter(fn));
                s:= StringReplace(s, '&', '&amp;', [rfReplaceAll]);
                s:= StringReplace(s, '<', '&lt;', [rfReplaceAll]);
                s:= StringReplace(s, '>', '&gt;', [rfReplaceAll]);
                s:= StringReplace(s, '''', '&apos;', [rfReplaceAll]);

                r:= r +
                 '<item id="' + id + '$' + IntToStr(i) + '"' +
                 ' parentID="' + id + '" restricted="1">' +
                 '<dc:title>' + s + '</dc:title>' +
                 '<res xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"'+
                 m + '>' +
                 'http://' + MyIPAddr + ':' + DAEMON_PORT + '/p2/' +
                 EncodeX(no + #$09 + fn) + '</res>';

                s:= mi.Vals['General;File_Created_Date_Local'];
                if s <> '' then begin
                  r:= r + '<dc:date>' + Fetch(s, ' ') + 'T' + Copy(s, 1, 8) + '</dc:date>';
                end else
                  r:= r + '<dc:date>0000-00-00T00:00:00</dc:date>';

                s:= mt;
                s:= Fetch(s, '/');
                if s = 'audio' then begin
                  r:= r + '<upnp:class>object.item.audioItem.musicTrack</upnp:class>';
                end else if s = 'image' then begin
                  r:= r + '<upnp:class>object.item.imageItem.photo</upnp:class>';
                end else begin
                  r:= r + '<upnp:class>object.item.videoItem</upnp:class>';
                end;
                r:= r + '</item>';
              finally
                if mi.IsTemp then mi.Free;
              end;
            end; // t

            'T': begin // Transcode(Folder)
              no:= Copy(fn, 2, Length(fn)-3);
              fn:= Fetch(no, #$09);
              mi:= thMIC.GetMediaInfo(fn);
              try
                mi.GetPlayInfo(L_S);

                s:= mi.PlayInfo.Values['DispName'];
                if s = '' then
                  s:= ExtractFileName(ExcludeTrailingPathDelimiter(fn));
                s:= StringReplace(s, '&', '&amp;', [rfReplaceAll]);
                s:= StringReplace(s, '<', '&lt;', [rfReplaceAll]);
                s:= StringReplace(s, '>', '&gt;', [rfReplaceAll]);
                s:= StringReplace(s, '''', '&apos;', [rfReplaceAll]);

                r:= r +
                 '<container id="' + id + '$' + IntToStr(i) + '" childCount="1"' +
                 ' parentID="' + id + '" restricted="1">' +
                 '<dc:title>' + s + '</dc:title><dc:date>0000-00-00T00:00:00</dc:date>'+
                 '<upnp:class>object.container.storageFolder</upnp:class>'+
                 '</container>';
              finally
                if mi.IsTemp then mi.Free;
              end;
            end // T
          end; // case
        end else begin

          fn:= Copy(fn, 2, MaxInt);
          mi:= thMIC.GetMediaInfo(fn);
          try
            mi.GetPlayInfo(L_S);
            mt:= mi.PlayInfo.Values['mime[1]'];

            m:= ' protocolInfo="http-get:*:';
            if mt <> '' then
              m:= m + mt
            else
              m:= m + 'text/plain:*';
            m:= m + '"';

            i64:= mi.FileSize;
            if i64 > 0 then
              m:= m + ' size="' + IntToStr(i64) + '"';

            s:= mi.Vals['General;Duration'];
            if s <> '' then
              m:= m + ' duration="' + s + '"';

            s:= mi.Vals['Video;Width'];
            if s <> '' then
              m:= m + ' resolution="' + s + 'x' + mi.Vals['Video;Height'] + '"';

            s:= mi.Vals['Audio;Channels'];
            if s <> '' then
              m:= m + ' nrAudioChannels="' + s + '"';

            s:= mi.Vals['Audio;BitRate'];
            if s <> '' then
              m:= m + ' bitrate="' + s + '"';

            s:= mi.Vals['Audio;SamplingRate'];
            if s <> '' then
              m:= m + ' sampleFrequency="' + s + '"';

            s:= mi.PlayInfo.Values['DispName'];
            if s = '' then s:= ExtractFileName(fn);
            s:= StringReplace(s, '&', '&amp;', [rfReplaceAll]);
            s:= StringReplace(s, '<', '&lt;', [rfReplaceAll]);
            s:= StringReplace(s, '>', '&gt;', [rfReplaceAll]);
            s:= StringReplace(s, '''', '&apos;', [rfReplaceAll]);

            r:= r +
             '<item id="' + id + '$' + IntToStr(i) + '"' +
             ' parentID="' + id + '" restricted="1">' +
             '<dc:title>' + s + '</dc:title>' +
             '<res xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"'+
             m + '>' +
             'http://' + MyIPAddr + ':' + DAEMON_PORT + '/p1/' + EncodeX(fn) +
             '</res>';

            s:= mi.Vals['General;File_Created_Date_Local'];
            if s <> '' then begin
              r:= r + '<dc:date>' + Fetch(s, ' ') + 'T' + Copy(s, 1, 8) + '</dc:date>';
            end else
              r:= r + '<dc:date>0000-00-00T00:00:00</dc:date>';

            s:= mt;
            s:= Fetch(s, '/');
            if s = 'audio' then begin
              r:= r + '<upnp:class>object.item.audioItem.musicTrack</upnp:class>';
            end else if s = 'image' then begin
              r:= r + '<upnp:class>object.item.imageItem.photo</upnp:class>';
            end else begin
              r:= r + '<upnp:class>object.item.videoItem</upnp:class>';
              //r:= r+'<av:mediaClass xmlns:av="urn:schemas-sony-com:av">V</av:mediaClass>';
            end;
            r:= r + '</item>';
          finally
            if mi.IsTemp then mi.Free;
          end;
        end;
      end;
    end;
  end;
  r := r + '</DIDL-Lite>';

  val:= docw.CreateTextNode(UTF8Decode(r));
  item.AppendChild(val);

  item:= docw.CreateElement('NumberReturned');
  parent.AppendChild(item);
  val:= docw.CreateTextNode(IntToStr(c));
  item.AppendChild(val);

  item:= docw.CreateElement('TotalMatches');
  parent.AppendChild(item);
  if BrowseFlag = 'BrowseMetadata' then begin
    val:= docw.CreateTextNode(IntToStr(c));
  end else begin
    val:= docw.CreateTextNode(IntToStr(mlist.Count));
  end;
  item.AppendChild(val);

  item:= docw.CreateElement('UpdateID');
  parent.AppendChild(item);
  val:= docw.CreateTextNode('1');
  item.AppendChild(val);

  Result:= True;
end;

function THttpThrd.SendRaw(buf: Pointer; len: integer): boolean;
var
  x, r: Integer;
begin
  Result:= False;
  x:= 0;
  while not Terminated and (x < len) do begin
    r:= synsock.Send(Sock.Socket, PByte(buf)+x, len-x, MSG_NOSIGNAL);
    Sock.SockCheck(r);
    case Sock.LastError of
      0: Inc(x, r);
      else Exit;
    end;
  end;
  Result:= True;
end;

function THttpThrd.SendRaw(const buf: string): boolean;
begin
  Result:= SendRaw(@buf[1], Length(buf));
end;

function THttpThrd.DoPlay(const fname, request: string): boolean;
const
  OKKAKE_SPACE = 100 * 1024 * 1024;
var
  mi: TGetMediaInfo;
  ct, cf, s, seek1, seek2, dur, ts_range, range: string;
  fs: TFileStreamUTF8;
  h: TStringListUTF8;
  i, buf_size, s_wait: integer;
  nseek1, nseek2, ndur: double;
  iseek1, isize, fsize, range1, range2: Int64;
  buf: PByte;
  now_rec, bTimeSeek, bRange: boolean;
  time1, time2: LongWord;
begin
  Result:= False;
  UniOutput:= True;
  h:= TStringListUTF8.Create;
  mi:= thMIC.GetMediaInfo(fname);
  try
    mi.GetPlayInfo(L_S);
    cf:= mi.PlayInfo.Values['mime[1]'];
    ct:= Fetch(cf, ':');

    now_rec:= mi.Vals['General;Format'] = 'NowRecording';
    if now_rec then
      fs:= TFileStreamUTF8.Create(fname, fmOpenRead or fmShareDenyNone)
    else
      fs:= TFileStreamUTF8.Create(fname, fmOpenRead or fmShareDenyWrite);
    try
      fsize:= unit2.GetFileSize(fname){fs.Size};
      iseek1:= 0; isize:= fsize;
      nseek1:= 0; nseek2:= 0;
      dur:= mi.Vals['General;Duration'];
      if now_rec then begin
        dur:= '20:00:00.000'; // 20時間のファイルと仮定する
        isize:= 200 * 1024 * 1024 * 1024; // 200GBのファイルと仮定
      end;
      ndur:= SeekTimeStr2Num(dur);
      i:= Pos('TIMESEEKRANGE.DLNA.ORG:', UpperCase(InHeader));
      bTimeSeek:= i > 0;
      if bTimeSeek then begin
        if ndur = 0 then begin
          // TIMESEEKRANGEは使えませんと答える
          // (DLNA Interoperability Guidelines v1.0 - 7.8.22.7)
          Sock.SendString('HTTP/1.1 406 Not Acceptable' + CRLF + CRLF);
          Exit;
        end;
        s:= Copy(InHeader, i+23, Length(InHeader));
        s:= Trim(Fetch(s, CR));
        Fetch(s, '=');
        seek2:= Trim(s);
        seek1:= Fetch(seek2, '-');
        nseek1:= SeekTimeStr2Num(seek1);
        nseek2:= SeekTimeStr2Num(seek2);
        if (nseek1 <> 0) or (nseek2 <> 0) then begin
          if now_rec then begin
            // 録画中のファイルは20Mbpsであると仮定
            iseek1:= Trunc(nseek1 / 1000 * 20 * 1024 * 1024 / 8);
            if nseek2 >= nseek1 then begin
              isize:= Trunc(nseek2 / 1000 * 20 * 1024 * 1024 / 8) - iseek1 + 1;
              if iseek1 + isize + OKKAKE_SPACE > fsize then begin
                iseek1:= fsize - OKKAKE_SPACE - isize;
              end;
            end else begin
              if iseek1 + OKKAKE_SPACE >= fsize then iseek1:= fsize - OKKAKE_SPACE;
            end;
            if iseek1 < 0 then iseek1:= 0;
          end else begin
            iseek1:= Trunc(fsize / ndur * nseek1);
            if nseek2 >= nseek1 then begin
              isize:= Trunc(fsize / ndur * nseek2) - iseek1 + 1;
            end else begin
              isize:= fsize - iseek1;
            end;
          end;
        end;
      end;

      range1:= 0; range2:= fsize - 1;
      i:= Pos('RANGE:', UpperCase(InHeader));
      bRange:= not bTimeSeek and (i > 0);
      if bRange then begin
        s:= Copy(InHeader, i+6, Length(InHeader));
        Fetch(s, '=');
        range1:= StrToInt64Def(Trim(Fetch(s, '-')), 0);
        iseek1:= range1;
        if now_rec then begin
          if iseek1 + OKKAKE_SPACE >= fsize then iseek1:= fsize - OKKAKE_SPACE;
        end;
        range2:= StrToInt64Def(Trim(Fetch(s, CR)), fsize-1);
        isize:= range2 - range1 + 1;
      end;

      if bRange then begin
        h.Add('HTTP/1.1 206 Partial Content');
      end else begin
        h.Add('HTTP/1.1 200 OK');
      end;
      h.Add('TransferMode.DLNA.ORG: Streaming');
      h.Add('Content-Type: ' + ct);
      h.Add('ContentFeatures.DLNA.ORG: ' + cf);
      h.Add('Accept-Ranges: bytes');
      h.Add('Connection: keep-alive');
      h.Add('Server: ' + HTTP_HEAD_SERVER);
      if now_rec then
        h.Add('Transfer-Encoding: chunked')
      else
        h.Add('Content-length: ' + IntToStr(isize));

      if nseek2 > 0 then
        s:= SeekTimeNum2Str(nseek2)
      else
        s:= SeekTimeNum2Str(ndur);
      ts_range:= SeekTimeNum2Str(nseek1) + '-' + s + '/' + dur;
      range:= Format('%d-%d/%d', [range1, range2, fsize]);
      if bTimeSeek then begin
        //s:= 'npt=' + ts_range + ' bytes=' + range;
        s:= 'npt=' + ts_range;
        h.Add('TimeSeekRange.dlna.org: ' + s);
        h.Add('X-Seek-Range: ' + s);
      end else if bRange then begin
        h.Add('Content-Range: bytes ' + range);
      end;
      h.Add('');
      for i:= 0 to h.Count - 1 do begin
        Sock.SendString(h[i] + CRLF);
        if Sock.LastError <> 0 then Exit;
        Line:= Line + h[i] + CRLF;
      end;
      Line:= Line + CRLF;

      if UpperCase(request) <> 'HEAD' then begin
        Line:= line + GetLineHeader + 'STREAM sent' + CRLF + fname + CRLF + CRLF;
        Synchronize(@AddLog);

        if now_rec then begin
          // 余白分が溜まるまで待つ
          while not Terminated and Sock.CanWrite(1*60*1000) do begin
            fsize:= unit2.GetFileSize(fname);
            if fsize > OKKAKE_SPACE then Break;
            SleepThread(Handle, 100);
          end;
        end;

        Sock.SetSendTimeout(SEND_DATA_TIMEOUT);
        s_wait:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'STREAM_WAIT', 0);
        lua_getglobal(L_S, 'STREAM_WAIT');
        if lua_isnumber(L_S, -1) then s_wait:= lua_tointeger(L_S, -1);
        lua_pop(L_S, 1);
        if (s_wait < 0) or (s_wait > 10000) then s_wait:= 0;

        time1:= LCLIntf.GetTickCount;
        buf_size:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'STREAM_BUFFER_SIZE', 10);
        if buf_size < 1 then buf_size:= 1;
        if buf_size > 1800 then buf_size:= 1800;
        buf_size:= buf_size * 1024 * 1024;
        buf:= GetMem(buf_size);
        try
          fs.Seek(iseek1, soBeginning);
          while (isize > 0) and not Terminated do begin
            if isize < buf_size then buf_size:= isize;
            i:= fs.Read(buf^, buf_size);
            if i <= 0 then begin
              if now_rec then begin
                SleepThread(Handle, 5000);
                i:= fs.Read(buf^, buf_size);
                if i <= 0 then begin
                  //Sock.SendString('0' + CRLF + CRLF);
                  SendRaw('0' + CRLF + CRLF);
                  Break; // 5秒待っても増えないのでたぶん録画終了
                end;
              end else
                Break;
            end;
            if now_rec then SendRaw(LowerCase(IntToHex(i, 1)) + CRLF);
            //Sock.SendBuffer(buf, i);
            SendRaw(buf, i);
            if now_rec then SendRaw(CRLF);
            if Sock.LastError <> 0 then Exit;
            time2:= LCLIntf.GetTickCount;
            if (s_wait > 0) and (time2 - time1 < s_wait) then
              SleepThread(Handle, s_wait - (time2 - time1));
            time1:= time2;
            Dec(isize, i);
          end;
        finally
          FreeMem(buf);
        end;

        Line:= GetLineHeader + 'STREAM fin' + CRLF +
         fname + CRLF + CRLF;
      end;
    finally
      fs.Free;
    end;
  finally
    h.Free;
    if mi.IsTemp then mi.Free;
  end;
  Result:= True;
end;

function THttpThrd.DoPlayTranscode(sno: integer; const fname, request: string): boolean;
var
  mi: TGetMediaInfo;
  cmd, exec, tmp_fname, ct, cf, seek1, seek2, dur, ts_range, range: string;
  s: string;
  fs: TFileStreamUTF8;
  h, sl: TStringListUTF8;
  i, j, buf_size, errc, s_wait: integer;
  nseek1, nseek2, ndur: double;
  buf: PByte;
  proc: TProcess_mod;
  pipe_proc: TPipeProcExec;
  bTimeSeek, bRange, KeepModeSendOnly: boolean;
  KeepMode: integer;
  range1, range2: Int64;
  time1, time2: LongWord;
  tck_path, tck_ini: string;
  cmds: TStringList;
  OutputMsgs, StderrMsgs: TStringList;
  TransComplete: boolean;
begin
  Result:= False;
  UniOutput:= True;
  h:= TStringListUTF8_mod.Create;
  cmds:= TStringList.Create;
  mi:= thMIC.GetMediaInfo(fname);
  try
    mi.GetPlayInfo(L_S);

    s:= Trim(mi.PlayInfo.Values['command['+IntToStr(sno)+']']);
    if s = '' then begin
      i:= 1;
      while True do begin
        s:= Trim(mi.PlayInfo.Values[
         'command['+IntToStr(sno)+']['+IntToStr(i)+']']);
        if s = '' then Break;
        //s:= StringReplace(s, CRLF, '', [rfReplaceAll]);
        s:= StringReplace(s, CR, '', [rfReplaceAll]);
        s:= StringReplace(s, LF, '', [rfReplaceAll]);
        cmds.Add(s);
        Inc(i);
      end;
    end else begin
      s:= StringReplace(s, CR, '', [rfReplaceAll]);
      s:= StringReplace(s, LF, '', [rfReplaceAll]);
      cmds.Add(s);
    end;

    case mi.PlayInfo.Values['excmd['+IntToStr(sno)+']'] of
      'KEEP': KeepMode:= 1;
      'CLEAR': KeepMode:= 100;
      else KeepMode:= 0;
    end;

    if not(KeepMode in [100]) and (cmds.Count = 0) then begin
      // トランスコードをせず通常のストリーミング再生をする
      Result:= DoPlay(fname, request);
      Exit;
    end;

    cf:= mi.PlayInfo.Values['mime['+IntToStr(sno)+']'];
    ct:= Fetch(cf, ':');
    nseek1:= 0; nseek2:= 0;
    dur:= mi.PlayInfo.Values['duration['+IntToStr(sno)+']'];
    if dur = '' then dur:= mi.Vals['General;Duration'];
    if dur = '' then dur:= '20:00:00.000'; // 20時間のファイルと仮定する
    ndur:= SeekTimeStr2Num(dur);
    i:= Pos('TIMESEEKRANGE.DLNA.ORG:', UpperCase(InHeader));
    bTimeSeek:= i > 0;
    if bTimeSeek then begin
      s:= Copy(InHeader, i+23, Length(InHeader));
      s:= Trim(Fetch(s, CR));
      Fetch(s, '=');
      seek2:= Trim(s);
      seek1:= Fetch(seek2, '-');
      nseek1:= SeekTimeStr2Num(seek1);
      nseek2:= SeekTimeStr2Num(seek2);
    end;

    range1:= 0; range2:= -1;
    i:= Pos('RANGE:', UpperCase(InHeader));
    bRange:= not bTimeSeek and (i > 0);
    if bRange then begin
      s:= Copy(InHeader, i+6, Length(InHeader));
      Fetch(s, '=');
      range1:= StrToInt64Def(Trim(Fetch(s, '-')), 0);
      range2:= StrToInt64Def(Trim(Fetch(s, CR)), -1);
    end;

    if bRange then begin
      h.Add('HTTP/1.1 206 Partial Content');
    end else begin
      h.Add('HTTP/1.1 200 OK');
    end;
    h.Add('TransferMode.DLNA.ORG: Streaming');
    h.Add('Content-Type: ' + ct);
    h.Add('ContentFeatures.DLNA.ORG: ' + cf);
    h.Add('Accept-Ranges: bytes');
    h.Add('Connection: keep-alive');
    h.Add('Server: ' + HTTP_HEAD_SERVER);
    h.Add('Transfer-Encoding: chunked');
    if nseek2 > 0 then
      s:= SeekTimeNum2Str(nseek2)
    else
      s:= SeekTimeNum2Str(ndur);
    ts_range:= SeekTimeNum2Str(nseek1) + '-' + s + '/' + dur;
    if range2 >= 0 then
      range:= Format('%d-%d/*', [range1, range2])
    else
      range:= Format('%d-/*', [range1]);
    if bTimeSeek then begin
      //s:= 'npt=' + ts_range + ' bytes=' + range;
      s:= 'npt=' + ts_range;
      h.Add('TimeSeekRange.dlna.org: ' + s);
      h.Add('X-Seek-Range: ' + s);
    end else if bRange then begin
      h.Add('Content-Range: bytes ' + range);
    end;
    h.Add('');
    for i:= 0 to h.Count - 1 do begin
      Sock.SendString(h[i] + CRLF);
      if Sock.LastError <> 0 then Exit;
      Line:= Line + h[i] + CRLF;
    end;
    Line:= Line + CRLF;

    if UpperCase(request) <> 'HEAD' then begin
      Line:= line + GetLineHeader + 'STREAM sent' + CRLF + fname + CRLF + CRLF;
      Synchronize(@AddLog);

      Sock.SetSendTimeout(SEND_DATA_TIMEOUT);
      s_wait:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'STREAM_WAIT', 0);
      lua_getglobal(L_S, 'STREAM_WAIT');
      if lua_isnumber(L_S, -1) then s_wait:= lua_tointeger(L_S, -1);
      lua_pop(L_S, 1);
      if (s_wait < 0) or (s_wait > 10000) then s_wait:= 0;

      time1:= LCLIntf.GetTickCount;
      buf_size:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'STREAM_BUFFER_SIZE', 10);
      if buf_size < 1 then buf_size:= 1;
      if buf_size > 1800 then buf_size:= 1800;
      buf_size:= buf_size * 1024 * 1024;
      buf:= GetMem(buf_size);
      try
        tmp_fname:= FileUtil.GetTempFileName(TempPath, '$BMS_TRANS');
        KeepModeSendOnly:= False;
        if KeepMode <> 0 then begin
          tmp_fname:= '';
          tck_path:= iniFile.ReadString(INI_SEC_SYSTEM, 'KEEP_DIR', '');
          if tck_path = '' then tck_path:= ExecPath + 'keep';
          tck_path:= IncludeTrailingPathDelimiter(tck_path);
          if not DirectoryExistsUTF8(tck_path) then
            ForceDirectoriesUTF8(tck_path);
          sl:= TStringListUTF8.Create;
          try
            tck_ini:= tck_path + ExtractFileName(fname) +
             '_' + IntToStr(unit2.GetFileSize(fname)) + '.ini';
            if FileExistsUTF8(tck_ini) then begin
              sl.LoadFromFile(tck_ini);
              i:= 0;
              while i < sl.Count do begin
                if KeepMode = 100 then begin
                  // トランスコファイルの消去
                  DeleteFileUTF8(tck_path + sl[i+1]);
                  if not FileExistsUTF8(tck_path + sl[i+1]) then begin
                    sl.Delete(i);
                    sl.Delete(i);
                    sl.Delete(i);
                  end else
                    Inc(i, 3); // ファイル使用中のため消去できなかった
                end else begin
                  if sl[i] = cmds.CommaText then begin
                    tmp_fname:= tck_path + sl[i+1];
                    KeepModeSendOnly:= unit2.GetFileSize(tmp_fname) > 0;
                    Break;
                  end;
                  Inc(i, 3);
                end;
              end;
            end;

            if KeepMode = 100 then begin
              if sl.Count = 0 then
                DeleteFileUTF8(tck_ini)
              else
                sl.SaveToFile(tck_ini); // ファイル使用中のため消去できなかった
              KeepModeSendOnly:= True;
            end else begin
              if not KeepModeSendOnly and (tmp_fname = '') then begin
                tmp_fname:= FileUtil.GetTempFileName(tck_path,
                 ExtractFileName(fname) + '_' + IntToStr(unit2.GetFileSize(fname)) + '_');
                sl.Add(cmds.CommaText);
                sl.Add(ExtractFileName(tmp_fname));
                sl.Add('');
                sl.SaveToFile(tck_ini);
              end;
            end;
          finally
            sl.Free;
          end;
        end;

        if not KeepModeSendOnly then begin
          // トランスコ
          try
            for j:= 0 to cmds.Count-1 do begin
              cmd:= cmds[j];
              if (cmd <> '') and (cmd[1] = '"') then begin
                cmd:= Copy(cmd, 2, MaxInt);
                exec:= Fetch(cmd, '"');
              end else
                exec:= Fetch(cmd, ' ');
              cmd:= Trim(cmd);
              exec:= Trim(exec);

              cmd:= StringReplace(cmd, '$_exec_path_$', ExecPath, [rfReplaceAll]);
              //cmd:= StringReplace(cmd, '$_in_$', ExtractShortPathNameUTF8(fname), [rfReplaceAll]);
              cmd:= StringReplace(cmd, '$_in_$', fname, [rfReplaceAll]);
              cmd:= StringReplace(cmd, '$_out_$', tmp_fname, [rfReplaceAll]);
              // $_cmd_seek_xxxxx_$
              while True do begin
                i:= Pos('$_cmd_seek_', cmd);
                if i = 0 then Break;
                s:= Copy(cmd, i+Length('$_cmd_seek_'), MaxInt);
                s:= Fetch(s, '_$'); // tc
                if bTimeSeek or bRange then begin
                  lua_getglobal(L_S, 'BMS');
                  if bRange then
                    lua_getfield(L_S, -1, 'GetCmdRangeSeek')
                  else
                    lua_getfield(L_S, -1, 'GetCmdTimeSeek');
                  lua_remove(L_S, -2); // remove BMS
                  if lua_isnil(L_S, -1) then begin
                    lua_pop(L_S, 1);
                    Break;
                  end;
                  lua_pushstring(L_S, s); // tc
                  if bRange then begin
                    lua_pushnumber(L_S, range1); // start
                    if range2 >= 0 then
                      lua_pushnumber(L_S, range2-range1+1) // len
                    else
                      lua_pushnil(L_S);
                  end else begin
                    if nseek1 <> 0 then
                      lua_pushstring(L_S, SeekTimeNum2Str(nseek1)) // start
                    else
                      lua_pushnil(L_S);
                    if (nseek2 > nseek1) then
                      lua_pushstring(L_S, SeekTimeNum2Str(nseek2-nseek1)) // len
                    else
                      lua_pushnil(L_S);
                  end;
                  lua_pushnumber(L_S, unit2.GetFileSize(fname)); // t_len
                  lua_pushnumber(L_S, ndur); // t_sec
                  CallLua(L_S, 5, 1);
                  cmd:= StringReplace(cmd, '$_cmd_seek_'+s+'_$', lua_tostring(L_S, -1), [rfReplaceAll]);
                  lua_pop(L_S, 1);
                end else
                  cmd:= StringReplace(cmd, '$_cmd_seek_'+s+'_$', '', [rfReplaceAll]);
              end;
              // $_cmd_quiet_xxxxx_$
              while True do begin
                i:= Pos('$_cmd_quiet_', cmd);
                if i = 0 then Break;
                s:= Copy(cmd, i+Length('$_cmd_quiet_'), MaxInt);
                s:= Fetch(s, '_$'); // tc
                lua_getglobal(L_S, 'BMS');
                lua_getfield(L_S, -1, 'GetCmdQuiet');
                lua_remove(L_S, -2); // remove BMS
                if lua_isnil(L_S, -1) then begin
                  lua_pop(L_S, 1);
                  Break;
                end;
                lua_pushstring(L_S, s); // tc
                CallLua(L_S, 1, 1);
                cmd:= StringReplace(cmd, '$_cmd_quiet_'+s+'_$', lua_tostring(L_S, -1), [rfReplaceAll]);
                lua_pop(L_S, 1);
              end;

              Line:= GetLineHeader + 'TRANSCODE ' + exec + CRLF + cmd + CRLF + CRLF;
              Synchronize(@AddLog);

              {$IFDEF Windows}
              if ExtractFilePath(exec) = '' then
                cmds[j]:= '"' + ExecPath + exec + '" ' + cmd
              else
              {$ENDIF}
                cmds[j]:= '"' + exec + '" ' + cmd;
            end; // for

            proc:= nil; pipe_proc:= nil;
            if cmds.Count = 1 then begin
              proc:= TProcess_mod.Create(nil);
              proc.CommandLine:= cmds[0];
              proc.Options:= [poNoConsole];
              proc.Execute;
            end else begin
              pipe_proc:= TPipeProcExec.Create;
              pipe_proc.Cmds.AddStrings(cmds);
              pipe_proc.MaxMsgLen:= 3000;
              pipe_proc.Start;
            end;

            try
              // 出力ファイルの生成待ち
              i:= 0;
              while not Terminated do begin
                if FileExistsUTF8(tmp_fname) then Break; // 出力ファイルが生成された

                // 出力ファイルを生成せずに終了してしまったかどうか
                if ((cmds.Count = 1) and not proc.Running) or
                 ((cmds.Count > 1) and pipe_proc.Done) or
                 (i > 1800) {3分間が我慢の限界} then Break;
                SleepThread(Handle, 100);
                Inc(i);
              end;

              if not FileExistsUTF8(tmp_fname) then begin
                OutputMsgs:= TStringList.Create; StderrMsgs:= TStringList.Create;
                try
                  if cmds.Count = 1 then begin
                    // エラーメッセージを取得するためもう一度実行
                    pipe_proc:= TPipeProcExec.Create;
                    try
                      pipe_proc.Cmds.Add(Cmds[0]);
                      pipe_proc.Start;
                      while not Terminated and not pipe_proc.Done do
                        SleepThread(Handle, 1000);
                      OutputMsgs.AddStrings(pipe_proc.OutputMsgs);
                      StderrMsgs.AddStrings(pipe_proc.StderrMsgs);
                    finally
                      pipe_proc.Terminate;
                      pipe_proc.WaitFor;
                      pipe_proc.Free;
                      pipe_proc:= nil;
                    end;
                  end else begin
                    OutputMsgs.AddStrings(pipe_proc.OutputMsgs);
                    StderrMsgs.AddStrings(pipe_proc.StderrMsgs);
                  end;

                  for i:= 0 to Cmds.Count-1 do begin
                    if OutputMsgs[i] <> '' then begin
                      line:= Format('Output of Process %d:', [i+1]) +
                       CRLF + OutputMsgs[i] + CRLF;
                      Synchronize(@AddLog);
                    end;
                    if StderrMsgs[i] <> '' then begin
                      line:= Format('Error of Process %d:', [i+1]) +
                       CRLF + StderrMsgs[i] + CRLF;
                      Synchronize(@AddLog);
                    end;
                  end;
                finally
                  OutputMsgs.Free; StdErrMsgs.Free;
                end;
                Exit;
              end;

              if Terminated then Exit;

              fs:= TFileStreamUTF8.Create(tmp_fname, fmOpenRead or fmShareDenyNone);
              try
                errc:= 0;

                TransComplete:= False;
                while True do begin
                  if cmds.Count = 1 then begin
                    if proc.Running = False then begin
                      TransComplete:= True;
                      Break;
                    end;
                  end else begin
                    if pipe_proc.Done then begin
                      TransComplete:= pipe_proc.Complete;
                      Break;
                    end;
                  end;

                  i:= fs.Read(buf^, buf_size);
                  if i <= 0 then begin
                    SleepThread(Handle, 1);
                    Inc(errc);
                  end else begin
                    errc:= 0;
                    //Sock.SendString(LowerCase(IntToHex(i, 1)) + CRLF);
                    //Sock.SendBuffer(buf, i);
                    //Sock.SendString(CRLF);
                    SendRaw(LowerCase(IntToHex(i, 1)) + CRLF);
                    SendRaw(buf, i);
                    SendRaw(CRLF);
                    time2:= LCLIntf.GetTickCount;
                    if (s_wait > 0) and (time2 - time1 < s_wait) then begin
                      SleepThread(Handle, s_wait - (time2 - time1));
                    end else begin
                      SleepThread(Handle, 1); // 変換作業を優先すべく最低でも1msは休むようにしてみた
                    end;
                    time1:= time2;
                  end;
                  if (Sock.LastError <> 0) or (errc > 10000) or Terminated then
                    Break; // 異常終了
                  if KeepMode = 1 then begin
                    // 送信内容はどうでもよいことなので休みながらにして、変換作業を急がせる
                    SleepThread(Handle, 1000);
                  end;
                end;

                if TransComplete then begin
                  if KeepMode = 0 then begin
                    while not Terminated do begin
                      i:= fs.Read(buf^, buf_size);
                      if i <= 0 then begin
                        //Sock.SendString('0' + CRLF + CRLF);
                        SendRaw('0' + CRLF + CRLF);
                        Break;
                      end;
                      //Sock.SendString(LowerCase(IntToHex(i, 1)) + CRLF);
                      //Sock.SendBuffer(buf, i);
                      //Sock.SendString(CRLF);
                      SendRaw(LowerCase(IntToHex(i, 1)) + CRLF);
                      SendRaw(buf, i);
                      SendRaw(CRLF);
                      if Sock.LastError <> 0 then Break;
                      time2:= LCLIntf.GetTickCount;
                      if (s_wait > 0) and (time2 - time1 < s_wait) then
                        SleepThread(Handle, s_wait - (time2 - time1));
                      time1:= time2;
                    end;
                  end else begin
                    // KeepMode では、トランスコ終了で転送も強制終了
                    SendRaw('0' + CRLF + CRLF);
                  end;
                end;
              finally
                fs.Free;
              end;
            finally
              if Assigned(proc) then begin
                if proc.Running then proc.SafeTerminate(-1);
                proc.Free;
                proc:= nil;
              end;
              if Assigned(pipe_proc) then begin
                pipe_proc.Terminate;
                pipe_proc.WaitFor;
                pipe_proc.Free;
                pipe_proc:= nil;
              end;
            end;
          finally
            if (KeepMode = 0) or (Sock.LastError <> 0) then begin
              for i:= 1 to 6 do begin
                if DeleteFileUTF8(tmp_fname) then
                  Break
                else
                  SleepThread(Handle, 10000);
              end;
            end;
            if (KeepMode <> 0) and (Sock.LastError <> 0) then begin
              fs:= TFileStreamUTF8.Create(tmp_fname, fmCreate);  // サイズを0に
              fs.Free;
            end;
          end;

        end else begin
          // KeepModeSendOnly
          if KeepMode = 100 then begin
            s:= 'mpg';
            if ct = 'video/mp4' then s:= 'mp4';
            fs:= TFileStreamUTF8.Create(ExecPath + 'data/clear_fin.' + s, fmOpenRead or fmShareDenyWrite);
          end else
            fs:= TFileStreamUTF8.Create(tmp_fname, fmOpenRead or fmShareDenyWrite);
          try
            while not Terminated do begin
              i:= fs.Read(buf^, buf_size);
              if i <= 0 then begin
                SendRaw('0' + CRLF + CRLF);
                Break;
              end;
              SendRaw(LowerCase(IntToHex(i, 1)) + CRLF);
              SendRaw(buf, i);
              SendRaw(CRLF);
              time2:= LCLIntf.GetTickCount;
              if (s_wait > 0) and (time2 - time1 < s_wait) then
                SleepThread(Handle, s_wait - (time2 - time1));
              time1:= time2;
              if (Sock.LastError <> 0) then Break;
            end;
          finally
            fs.Free;
          end;
        end;
      finally
        FreeMem(buf);
      end;

      Line:= GetLineHeader + 'STREAM fin' + CRLF + fname + CRLF + CRLF;
    end;
  finally
    h.Free;
    cmds.Free;
    if mi.IsTemp then mi.Free;
  end;
  Result:= True;
end;

{ TSSDPDaemon }

constructor TSSDPDaemon.Create;
begin
  Sock:= TUDPBlockSocket.Create;
  Sock.Family:= SF_IP4;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

destructor TSSDPDaemon.Destroy;
begin
  Sock.Free;
  inherited Destroy;
end;

procedure TSSDPDaemon.AddLog;
begin
  if not Assigned(MyApp) then Exit;
  MyApp.AddLog(line);
  line:= '';
end;

procedure TSSDPDaemon.Execute;

  procedure AddMulticast7(const MCastIP: AnsiString; const Intf: AnsiString);
  var
    Multicast: TIP_mreq;
  begin
    Multicast.imr_multiaddr.S_addr := synsock.inet_addr(PAnsiChar(MCastIP));
    Multicast.imr_interface.S_addr := INADDR_ANY; // Windows7ではINADDR_ANYのままだと不具合が出る場合がある
    if Intf <> '' then
      Multicast.imr_interface.S_addr := synsock.inet_addr(PAnsiChar(Intf));
    Sock.SockCheck(synsock.SetSockOpt(Sock.Socket, IPPROTO_IP,
     IP_ADD_MEMBERSHIP, PAnsiChar(@Multicast), SizeOf(Multicast)));
    Sock.ExceptCheck;
  end;

var
  sendSock: TUDPBlockSocket;
  s, st, rcv_st, usn, remoteip, remoteport: String; // st:ServiceType
  //L: Plua_State; // Luaで拡張できるようにする予定だったが・・・なくてもよさげ
  st_list: TStringList; // st_list:ServiceTypeList
begin
  try
    Sock.CreateSocket();
    Sock.EnableReuse(True);
    Sock.Bind(MyIPAddr{'0.0.0.0'}, '1900'{SSDP});
    if Sock.LastError <> 0 then Raise Exception.Create(Sock.LastErrorDesc);
    AddMulticast7('239.255.255.250', MyIPAddr);
    if Sock.LastError <> 0 then Raise Exception.Create(Sock.LastErrorDesc);
    //L:= lua_newstate(@alloc, nil);
    st_list:= TStringListUTF8.Create;
    try
      //InitLua(L);
      st_list.Add('upnp:rootdevice');
      st_list.Add('uuid:' + UUID);
      st_list.Add('urn:schemas-upnp-org:device:MediaServer:1');
      st_list.Add('urn:schemas-upnp-org:service:ContentDirectory:1');
      st_list.Add('urn:schemas-upnp-org:service:ConnectionManager:1');
      while not Terminated do begin
        s:= Sock.RecvPacket(1000);
        if Sock.LastError = 0 then begin
          if Pos('M-SEARCH', s) = 1 then begin
            remoteip:= Sock.GetRemoteSinIP;
            remoteport:= IntToStr(Sock.GetRemoteSinPort);
            rcv_st:= '';
            if Pos(LF+'ST:', s) > 0 then begin
              rcv_st:= SeparateLeft(SeparateRight(s, LF+'ST:'), CR);
            end;
            sendSock:= TUDPBlockSocket.Create;
            try
              try
                sendSock.Family:= SF_IP4;
                sendSock.CreateSocket();
                if sendSock.LastError <> 0 then Raise Exception.Create(sendSock.LastErrorDesc);
                sendSock.Bind(MyIPAddr{'0.0.0.0'}, '0');
                if sendSock.LastError <> 0 then Raise Exception.Create(sendSock.LastErrorDesc);
                if remoteip <> MyIPAddr then begin
                  sendSock.Connect(remoteip, remoteport);
                  if sendSock.LastError <> 0 then Raise Exception.Create(sendSock.LastErrorDesc);
                  for st in st_list do begin
                    if (Pos('ssdp:all', rcv_st) > 0) or (Pos(st, rcv_st) > 0) or (st = 'urn:schemas-upnp-org:device:MediaServer:1') then begin
                      if st = ('uuid:' + UUID) then begin
                        usn:= st;
                      end else begin
                        usn:= 'uuid:' + UUID + '::' + st;
                      end;
                      s:=
                       'HTTP/1.1 200 OK' + CRLF +
                       'CACHE-CONTROL: max-age=1800' + CRLF +
                       'DATE: ' + Rfc822DateTime(now) + CRLF +
                       'LOCATION: http://' + MyIPAddr + ':' + DAEMON_PORT + '/desc.xml' + CRLF +
                       'SERVER: ' + HTTP_HEAD_SERVER + CRLF +
                       'ST: ' + st + CRLF +
                       'EXT: '+ CRLF +
                       'USN: ' + usn + CRLF +
                       'Content-Length: 0' + CRLF + CRLF;
                      sendSock.SendString(s);
                      if sendSock.LastError <> 0 then Raise Exception.Create(sendSock.LastErrorDesc);
                      line:= GetLineHeader + remoteip + '  SSDP Sent for M-SEARCH' + CRLF + CRLF;
                      Synchronize(@AddLog);
                    end;
                  end;
                end;
              except
                on e: Exception do begin
                  line:= '*** ERROR SSDP Sent: ' + e.Message + CRLF + CRLF;
                  Synchronize(@AddLog);
                end;
              end;
            finally
              sendSock.Free;
            end;
          end;
        end else begin
          if Sock.LastError <> WSAETIMEDOUT then begin
            line:= '*** ERROR SSDP Recv : ' + Sock.LastErrorDesc + CRLF + CRLF;
            Synchronize(@AddLog);
          end;
        end;
      end;
    finally
      st_list.Free;
      //lua_close(L);
    end;
  except
    on e: Exception do begin
      line:= '*** ERROR SSDP : ' + e.Message + CRLF + CRLF;
      Synchronize(@AddLog);
    end;
  end;
end;

{ TMediaInfoCollector }

constructor TMediaInfoCollector.Create;
begin
  mi_list:= TStringListUTF8_mod.Create;
  mi_list.Sorted:= True;
  mi_ac_list:= TStringListUTF8_mod.Create;
  mi_ac_list.Sorted:= True;
  exkey_list:= TStringListUTF8_mod.Create;
  iniFile.ReadSectionRaw(INI_SEC_MIKeys, exkey_list);
  PriorityList:= TStringListUTF8_mod.Create;
  FreeOnTerminate:= False;
  MaxMediaInfo:= iniFile.ReadInteger(INI_SEC_SYSTEM, 'MAX_MEDIAINFO', 500);
  InitCriticalSection(CS_list);
  InitCriticalSection(CS_ac_list);
  InitCriticalSection(CS_pr_list);
  InitCriticalSection(CS_get_mi);
  inherited Create(True);
end;

destructor TMediaInfoCollector.Destroy;
var
  i: Integer;
begin
  for i:= 0 to mi_list.Count-1 do mi_list.Objects[i].Free;
  mi_list.Free;
  mi_ac_list.Free;
  exkey_list.Free;
  PriorityList.Free;
  DoneCriticalSection(CS_list);
  DoneCriticalSection(CS_ac_list);
  DoneCriticalSection(CS_pr_list);
  DoneCriticalSection(CS_get_mi);
  inherited Destroy;
end;

procedure TMediaInfoCollector.Execute;

  procedure GetFileList(const dir: string; depth: integer; prior:boolean = False);
  var
    info: TSearchRec;
    mi: TGetMediaInfo;
  begin
    if not prior and (mi_list.Count >= MAXMEDIAINFO) then Exit;
    if FindFirstUTF8(dir+'*', faAnyFile, info) = 0 then
      try
        repeat
          if Terminated or (not prior and (PriorityList.Count > 0)) then Break;
          if (info.Name <> '.') and (info.Name <> '..') and
           (info.Attr and faHidden = 0) then begin
            if info.Attr and faDirectory <> 0 then begin
              if depth > 0 then begin
                Dec(depth);
                GetFileList(dir + info.Name + DirectorySeparator, depth);
              end;
            end else begin
              if mi_list.IndexOf(dir + info.Name) < 0 then begin
                EnterCriticalSection(CS_get_mi);
                try
                  mi:= TGetMediaInfo.Create(dir + info.Name, miHandle, exkey_list);
                finally
                  LeaveCriticalSection(CS_get_mi);
                end;
                if mi.Vals['General;Format'] <> '' then begin
                  EnterCriticalSection(CS_list);
                  try
                    mi_list.AddObject(dir + info.Name, mi);
                    mi.AccTime:= FormatDateTime('yymmddhhnnss', Now);
                    EnterCriticalSection(CS_ac_list);
                    try
                      mi_ac_list.Add(mi.AccTime + dir + info.Name);
                    finally
                      LeaveCriticalSection(CS_ac_list);
                    end;
                  finally
                    LeaveCriticalSection(CS_list);
                  end;
                  if not prior and (mi_list.Count >= MAXMEDIAINFO) then Break;
                end else
                  mi.Free;
              end;
            end;
          end;
        until FindNextUTF8(info) <> 0;
      finally
        FindCloseUTF8(Info);
      end;
  end;

var
  depth, i: Integer;
begin
  while not Terminated do begin
    miHandle:= MediaInfo_New;
    try
      while not Terminated and (PriorityList.Count > 0) do begin
        try
          if PriorityList[0] <> '' then
            GetFileList(PriorityList[0], 0, True);
        finally
          EnterCriticalSection(CS_pr_list);
          try
            PriorityList.Delete(0);
          finally
            LeaveCriticalSection(CS_pr_list);
          end;
        end;
      end;

      // 浅い階層の分を先に収集
      for depth:= 0 to 2 do begin
        for i:= 0 to MediaDirs.Count-1 do begin
          if Terminated or (PriorityList.Count > 0) then Break;
          GetFileList(IncludeTrailingPathDelimiter(MediaDirs.ValueFromIndex[i]), depth);
        end;
      end;
      // 全階層分を収集
      for i:= 0 to MediaDirs.Count-1 do begin
        if Terminated or (PriorityList.Count > 0) then Break;
        GetFileList(IncludeTrailingPathDelimiter(MediaDirs.ValueFromIndex[i]), MaxInt);
      end;
    finally
      MediaInfo_Delete(miHandle);
    end;

    // 古い情報を削除
    while not Terminated and (mi_list.Count > MAXMEDIAINFO) do begin
      EnterCriticalSection(CS_list);
      try
        i:= mi_list.IndexOf(Copy(mi_ac_list[0], 13, MaxInt));
        mi_list.Objects[i].Free;
        mi_list.Delete(i);
      finally
        LeaveCriticalSection(CS_list);
      end;
      EnterCriticalSection(CS_ac_list);
      try
        mi_ac_list.Delete(0);
      finally
        LeaveCriticalSection(CS_ac_list);
      end;
    end;

    // 待機
    if not Terminated and (PriorityList.Count = 0) then Suspended:= True;
    //while not Terminated and (PriorityList.Count = 0) do Sleep(1000); // Best for Linux?
  end;
end;

// 注：他のスレッドからしか呼ばれることはないメソッド
function TMediaInfoCollector.GetMediaInfo(const fname: string): TGetMediaInfo;
var
  i, mi: Integer;
begin
  Result:= nil;

  EnterCriticalSection(CS_list);
  try
    i:= mi_list.IndexOf(fname);
    if i >= 0 then begin
      Result:= TGetMediaInfo(mi_list.Objects[i]);
      if Assigned(Result) and (Result.Count > 0) and
       (Result.Vals['General;Format'] <> 'NowRecording') and
       (Result.FileSize = unit2.GetFileSize(fname)) then begin
        EnterCriticalSection(CS_ac_list);
        try
          i:= mi_ac_list.IndexOf(Result.AccTime+fname);
          if i >= 0 then mi_ac_list.Delete(i);
          Result.AccTime:= FormatDateTime('yymmddhhnnss', Now);
          mi_ac_list.Add(Result.AccTime + fname);
        finally
          LeaveCriticalSection(CS_ac_list);
        end;
        Exit;
      end;
    end;
  finally
    LeaveCriticalSection(CS_list);
  end;

  mi:= MediaInfo_New;
  try
    EnterCriticalSection(CS_get_mi);
    try
      Result:= TGetMediaInfo.Create(fname, mi, exkey_list);
    finally
      LeaveCriticalSection(CS_get_mi);
    end;
    Result.IsTemp:= True;
    EnterCriticalSection(CS_pr_list);
    try
      PriorityList.Add(IncludeTrailingPathDelimiter(ExtractFilePath(fname)));
    finally
      LeaveCriticalSection(CS_pr_list);
    end;
    Suspended:= False;
  finally
    MediaInfo_Delete(mi);
  end;
end;

procedure TMediaInfoCollector.AddExKey(const key: string);
begin
  EnterCriticalSection(CS_get_mi);
  try
    exkey_list.Add(key);
  finally
    LeaveCriticalSection(CS_get_mi);
  end;
end;

procedure TMediaInfoCollector.ClearMediaInfo;
var
  i: Integer;
begin
  EnterCriticalSection(CS_list);
  try
    for i:= 0 to mi_list.Count-1 do mi_list.Objects[i].Free;
    mi_list.Clear;
  finally
    LeaveCriticalSection(CS_list);
  end;

  EnterCriticalSection(CS_ac_list);
  try
    mi_ac_list.Clear;
  finally
    LeaveCriticalSection(CS_ac_list);
  end;

  EnterCriticalSection(CS_pr_list);
  try
    PriorityList.Add('');
  finally
    LeaveCriticalSection(CS_pr_list);
  end;
  Suspended:= False;
end;

procedure TMediaInfoCollector.LoadMediaInfo;
var
  i, c: Integer;
  fs: TFileStreamUTF8;
  mi: TGetMediaInfo;
  s: String;
begin
  if not FileExistsUTF8(ExecPath + 'db/' + MEDIA_INFO_DB_FILENAME) then Exit;
  fs:= TFileStreamUTF8.Create(ExecPath + 'db/' + MEDIA_INFO_DB_FILENAME, fmOpenRead or fmShareExclusive);
  try
    c:= fs.ReadDWord;
    for i:= 0 to c-1 do begin
      SetLength(s, Length(MEDIA_INFO_DB_HEADER));
      fs.ReadBuffer(s[1], Length(MEDIA_INFO_DB_HEADER));
      if s <> MEDIA_INFO_DB_HEADER then Exit;
      s:= fs.ReadAnsiString;
      if FileExistsUTF8(s) then begin
        mi:= TGetMediaInfo.Create(s, 0, nil);
        mi.LoadFromStream(fs);
        mi_list.AddObject(s, mi);
        mi_ac_list.Add(mi.AccTime + s);
      end;
    end;
  finally
    fs.Free;
  end;
end;

procedure TMediaInfoCollector.SaveMediaInfo;
var
  i: Integer;
  fs: TFileStreamUTF8;
  mi: TGetMediaInfo;
  s: String;
begin
  if not DirectoryExistsUTF8(ExecPath + 'db/') then begin
    ForceDirectoriesUTF8(ExecPath + 'db/');
  end;
  fs:= TFileStreamUTF8.Create(ExecPath + 'db/' + MEDIA_INFO_DB_FILENAME, fmCreate);
  try
    fs.WriteDWord(mi_list.Count);
    for i:= 0 to mi_list.Count-1 do begin
      s:= mi_list[i];
      if FileExistsUTF8(s) then begin
        fs.WriteBuffer(MEDIA_INFO_DB_HEADER[1], Length(MEDIA_INFO_DB_HEADER));
        fs.WriteAnsiString(s);
        mi:= TGetMediaInfo(mi_list.Objects[i]);
        mi.SaveToStream(fs);
      end;
    end;
  finally
    fs.Free;
  end;
end;

{ TGetMediaInfo }

constructor TGetMediaInfo.Create(const fname: string; mi: Cardinal; ExKeys: TStringList);
begin
  inherited Create;
  FileName:= fname;
  FileSize:= unit2.GetFileSize(fname);
  PlayInfo:= TStringList.Create;
  if mi <> 0 then GetMediaInfo(fname, mi, Self, ExecPath, ExKeys);
end;

destructor TGetMediaInfo.Destroy;
var
  i: Integer;
begin
  for i:= 0 to Count-1 do Objects[i].Free;
  PlayInfo.Free;
  inherited Destroy;
end;

function minfo_mt_index(L : Plua_State) : Integer; cdecl;
var
  mi: TGetMediaInfo;
  p: PPointer;
  s, sk, key, sk_key: string;
  i: integer;
begin
  lua_getfield(L, 1{Table}, '$_StreamKind_$');
  sk:= lua_tostring(L, -1);
  lua_pop(L, 1);

  key:= lua_tostring(L, 2{key});
  lua_pushstring(L, LowerCase(key)); // 大文字小文字は区別しない
  lua_rawget(L, 1{Table});
  if lua_isnil(L, -1) then begin
    if (sk <> '') or (Pos(';', key) > 0) then begin
      lua_pop(L, 1);

      lua_getfield(L, 1{Table}, '$_TGetMediaInfo_$');
      p:= lua_touserdata(L, -1);
      mi:= TGetMediaInfo(p^);
      lua_pop(L, 1);

      if sk = 'user' then begin
        s:= mi.Vals['user;' + key];
      end else begin
        if sk <> '' then sk_key:= sk + ';' + key else sk_key:= key;
        // 新しいキーを追加
        i:= MediaInfo_New;
        try
          s:= GetMediaInfoSingle(mi.FileName, sk_key, i);
        finally
          MediaInfo_Delete(i);
        end;
        lua_pushstring(L, s);
        lua_setfield(L, 1{Table}, PChar(LowerCase(key)));
        mi.AddVal(sk_key, s);
        thMIC.AddExKey(sk_key);
      end;
      lua_pushstring(L, s); // 戻り値
    end;
  end;
  Result:= 1;
end;

function minfo_mt_newindex(L : Plua_State) : Integer; cdecl;
var
  mi: TGetMediaInfo;
  p: PPointer;
  s, key: string;
begin
  lua_getfield(L, 1{Table}, '$_TGetMediaInfo_$');
  p:= lua_touserdata(L, -1);
  mi:= TGetMediaInfo(p^);
  lua_pop(L, 1);

  key:= lua_tostring(L, 2{key});

  s:= lua_tostring(L, 3{value});
  mi.Vals['user;' + key]:= s;
  Result:= 0;
end;

procedure TGetMediaInfo.GetPlayInfo(L: PLua_State; get_new: boolean);

  procedure sub(const s: string);
  var
    p: PPointer;
    b: boolean;
  begin
    if s <> '' then begin
      lua_pushstring(L, s);
      lua_rawget(L, -2);
      b:= lua_istable(L, -1);
      if not b then begin
        lua_pop(L, 1);
        lua_pushstring(L, s);
        lua_newtable(L); // minfo.xxx
      end;
    end;

    lua_pushstring(L, '$_StreamKind_$');
    lua_pushstring(L, s);
    lua_settable(L, -3); // set minfo.xxx.$_StreamKind_$

    lua_pushstring(L, '$_TGetMediaInfo_$');
    p:= lua_newuserdata(L, SizeOf(Pointer));
    p^:= Self;
    lua_settable(L, -3); // set minfo.xxx.$_TGetMediaInfo_$

    if lua_getmetatable(L, -1) = 0 then lua_newtable(L);
    lua_pushstring(L, '__index');
    lua_pushcfunction(L, @minfo_mt_index);
    lua_settable(L, -3); // set minfo.xxx.メタテーブル.index
    if s = 'user' then begin
      lua_pushstring(L, '__newindex');
      lua_pushcfunction(L, @minfo_mt_newindex);
      lua_settable(L, -3); // set minfo.xxx.メタテーブル.newindex
    end;
    lua_setmetatable(L, -2);

    if s <> '' then begin
      if not b then begin
        lua_settable(L, -3); // set minfo
      end else
        lua_pop(L, 1);
    end;
  end;

  procedure LuaTable2PlayInfo(L: PLua_State; stacki, tablenum: integer);
  var
    s, s1: string;
    i, c: Integer;
  begin
    lua_pushnil(L);  // first key
    while lua_next(L, stacki) <> 0 do begin
      // uses 'key' (at index -2) and 'value' (at index -1)
      s:= lua_tostring(L, -2) + '[' + IntToStr(tablenum) + ']';
      if lua_istable(L, -1) then begin
        c:= lua_rawlen(L, -1);
        for i:= 1 to c do begin
          lua_rawgeti(L, -1, i);
          PlayInfo.Add(s + '[' + IntToStr(i) + ']=' + lua_tostring(L, -1));
          lua_pop(L, 1);
        end;
      end else begin
        s1:= lua_tostring(L, -1);
        PlayInfo.Add(s + '=' + s1);
      end;
      // removes 'value'; keeps 'key' for next iteration
      lua_pop(L, 1);
    end;
  end;

  procedure LuaTableCopy(L: PLua_State);
  begin
    lua_newtable(L);
    lua_pushnil(L);  // first key
    while lua_next(L, -3) <> 0 do begin
      // uses 'key' (at index -2) and 'value' (at index -1)
      lua_pushvalue(L, -2); // copy key
      lua_pushvalue(L, -2); // copy val
      if lua_istable(L, -1) then begin
        LuaTableCopy(L);
        lua_remove(L, -2); // remove old val
      end;
      lua_settable(L, -5); // copy2new
      // removes 'value'; keeps 'key' for next iteration
      lua_pop(L, 1);
    end;
  end;

var
  i: Integer;
  b: Boolean;
  c: size_t;
begin
  if not get_new and (PlayInfo.Count > 0) then Exit;
  if Self.Count = 0 then Exit;

  // グローバル変数BMSを保存
  lua_getglobal(L, 'BMS');
  LuaTableCopy(L);
  lua_setglobal(L, '$$$_SAVE_$$$');
  lua_pop(L, 1);

  try
    if FileExistsUTF8(ExtractFilePath(FileName) + '$.lua') then begin
      LoadLuaRaw(L, ExtractFilePath(FileName) + '$.lua');
    end;

    if FileExistsUTF8(FileName + '.lua') then begin
      LoadLuaRaw(L, FileName + '.lua');
    end;

    lua_getglobal(L, 'BMS');
    lua_getfield(L, -1, 'GetPlayInfo');
    lua_remove(L, -2); // remove BMS
    if lua_isnil(L, -1) then begin
      lua_pop(L, 1);
      Exit;
    end;
    lua_pushstring(L, FileName); // fname
    lua_newtable(L);             // minfo
    for i:= 0 to Count-1 do begin
      MIValue2LuaTable(L, LowerCase(Self.Strings[i]), Self.Vali[i]);
    end;
    sub('general');
    sub('video');
    sub('audio');
    sub('text');
    sub('chapters');
    sub('image');
    sub('menu');
    sub('dvd');
    sub('user');
    sub('');
    CallLua(L, 2, 3);

    PlayInfo.Clear;
    if lua_istable(L, 1{ret1}) then begin
      lua_rawgeti(L, 1{ret1}, 1);
      b:= lua_istable(L, -1);
      lua_pop(L, 1);
      if b then begin
        c:= lua_rawlen(L, 1{ret1});
        for i:= 1 to c do begin
          lua_pushnumber(L, i);
          lua_rawget(L, 1{ret1});
          LuaTable2PlayInfo(L, lua_gettop(L), i);
          lua_pop(L, 1);
        end;
        PlayInfo.Values['InfoCount']:= IntToStr(c);
        PlayInfo.Values['IsFolder']:= '1';
      end else begin
        LuaTable2PlayInfo(L, 1{ret1}, 1);
      end;
    end else begin
      PlayInfo.Values['mime[1]']:= lua_tostring(L, 1{ret1});
    end;

    if not lua_isnil(L, 2{ret2}) then PlayInfo.Values['DispName']:= lua_tostring(L, -2);
    if not lua_isnil(L, 3{ret3}) then PlayInfo.Values['SortName']:= lua_tostring(L, -1);
    lua_pop(L, 3);

  finally
    // グローバル変数BMSを復帰
    lua_getglobal(L, '$$$_SAVE_$$$');
    LuaTableCopy(L);
    lua_setglobal(L, 'BMS');
    lua_pop(L, 1);
  end;
end;

procedure TGetMediaInfo.SaveToStream(Stream: TStream);
var
  i: Integer;
begin
  //Stream.WriteAnsiString(FileName);
  Stream.WriteAnsiString(AccTime);
  Stream.WriteQWord(FileSize);
  Stream.WriteDWord(Count);
  for i:= 0 to Count-1 do begin
    Stream.WriteAnsiString(Strings[i]);
    Stream.WriteAnsiString(Vali[i]);
  end;
end;

procedure TGetMediaInfo.LoadFromStream(Stream: TStream);
var
  i, c: Cardinal;
  s1, s2: string;
begin
  //FileName:= Stream.ReadAnsiString;
  AccTime:= Stream.ReadAnsiString;
  FileSize:= Stream.ReadQWord();
  c:= Stream.ReadDWord();
  for i:= 0 to c-1 do begin
    s1:= Stream.ReadAnsiString;
    s2:= Stream.ReadAnsiString;
    AddVal(s1, s2);
  end;
end;

{ TClientInfo }

type
  TMediaFileList = class(TStringListUTF8)
  private
    ClientInfo: TClientInfo;
  protected
    function DoCompareText(const s1,s2 : string) : PtrInt; override;
  end;

constructor TClientInfo.Create;
begin
  CurFileList:= TMediaFileList.Create;
  TMediaFileList(CurFileList).ClientInfo:= Self;
  InfoTable:= TValStringList.Create;
  chunks:= TStringListUTF8_mod.Create;
  chunks.Sorted:= True;
end;

destructor TClientInfo.Destroy;
var
  i: Integer;
begin
  CurFileList.Free;
  InfoTable.Free;
  for i:= 0 to chunks.Count-1 do chunks.Objects[i].Free;
  chunks.Free;
  inherited Destroy;
end;

{ TMediaFileList }

function TMediaFileList.DoCompareText(const s1, s2: string): PtrInt;
var
  path1, path2, s: string;
  mi: TGetMediaInfo;
begin
  Result:= Byte(s1[1]) - Byte(s2[1]);
  if Result = 0 then begin
    path1:= Copy(s1, 2, Maxint);
    path2:= Copy(s2, 2, Maxint);
    case ClientInfo.SortType of
      1: Result:= CompareStr(path1, path2);
      2: Result:= CompareStr(path2, path1);
      3: Result:= CompareText(path1, path2);
      4: Result:= CompareText(path2, path1);
      5: Result:= GetFileTime(Fetch(path1, '?')) - GetFileTime(Fetch(path2, '?'));
      6: Result:= GetFileTime(Fetch(path2, '?')) - GetFileTime(Fetch(path1, '?'));
      else begin
        mi:= thMIC.GetMediaInfo(Fetch(path1, '?'));
        try
          mi.GetPlayInfo(ClientInfo.L_S);
          s:= mi.Vals['SortName'];
          if s <> '' then path1:= s;
        finally
          if mi.IsTemp then mi.Free;
        end;
        mi:= thMIC.GetMediaInfo(Fetch(path2, '?'));
        try
          mi.GetPlayInfo(ClientInfo.L_S);
          s:= mi.Vals['SortName'];
          if s <> '' then path2:= s;
        finally
          if mi.IsTemp then mi.Free;
        end;
        Result:= CompareStr(path1, path2);
      end;
    end;
  end;
end;

{ TMySimpleIPCServer }

constructor TMySimpleIPCServer.Create;
begin
  inherited Create(nil);
  vsl:= TValStringList.Create;
  InitCriticalSection(cs_vsl);
end;

destructor TMySimpleIPCServer.Destroy;
begin
  inherited Destroy;
  vsl.Free;
  DoneCriticalSection(cs_vsl);
end;

function TMySimpleIPCServer.GetValue(const vname: string): string;
begin
  EnterCriticalSection(cs_vsl);
  try
    Result:= vsl.Vals[vname];
  finally
    LeaveCriticalSection(cs_vsl);
  end;
end;

procedure TMySimpleIPCServer.SetValue(const vname, val: string);
begin
  EnterCriticalSection(cs_vsl);
  try
    vsl.Vals[vname]:= val;
  finally
    LeaveCriticalSection(cs_vsl);
  end;
end;

procedure TMySimpleIPCServer.DoMessage(Sender: TObject);
var
  s, s1: string;
begin
  s:= StringMessage;
  s1:= Fetch(s, '=');
  SetValue(s1, s);
end;

//--------------------------------------------------
procedure InitTrayIcon;
var
  p: TPicture;
begin
  p:= TPicture.Create;
  try
    p.LoadFromFile(ExecPath + 'DATA/' +
     iniFile.ReadString(INI_SEC_SYSTEM, 'ICON_IMAGE', 'icon.png'));
    TrayIcon.Icon.Assign(p.Graphic);
    TrayIcon.Show;
  finally
    p.Free;
  end;

  TrayIcon.Hint:= APP_NAME + ' ' + SHORT_APP_VERSION;
  TrayIcon.BalloonTimeout:= MaxInt;
end;

initialization
  ExecPath:= ExtractFilePath(ParamStrUTF8(0));
  iniFile:= TIniFile.Create({UTF8FILENAME}UTF8ToSys(ExecPath + 'bms.ini'));
  TempPath:= iniFile.ReadString(INI_SEC_SYSTEM, 'TEMP_DIR', '');
  if TempPath = '' then TempPath:= ExecPath + 'temp';
  TempPath:= IncludeTrailingPathDelimiter(TempPath);
  MyIPAddr:= '';
  TrayIcon:= TTrayIcon.Create(nil);
  InitTrayIcon;
  MyApp:= TMyApp.Create;
  Application.Title:= APP_NAME + ' ' + APP_VERSION;
finalization
  TrayIcon.OnClick:= nil;
  TrayIcon.PopUpMenu:= nil;
  TrayIcon.BalloonHint:= 'SAYONARA ...';
  TrayIcon.ShowBalloonHint;
  MyApp.Free;
  iniFile.Free;
  TrayIcon.Free;
end.

