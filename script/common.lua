----------------------------------------------------------------------
--
--  共通スクリプト
--
----------------------------------------------------------------------


BMS = { ClientInfo = {} }


----------------------------------------------------------------------
-- トランスコードフォルダを表示するかどうか
-- true でBMS1と同じ動作。
----------------------------------------------------------------------
BMS.ShowTranscodeFolder = false


----------------------------------------------------------------------
-- メディアファイルリストのソート順
--  0:BMS.GetPlayInfo 関数の3番目の戻り値でソート（注：遅いです）
--  1:ファイル名でソート
--  2:ファイル名でソート 逆順
--  3:ファイル名でソート 大文字小文字区別なし
--  4:ファイル名でソート 大文字小文字区別なし 逆順
--  5:タイムスタンプでソート 新しい順
--  6:タイムスタンプでソート 古い順
----------------------------------------------------------------------
BMS.MediaListSortType = 1


----------------------------------------------------------------------
-- BMS.GetScriptFileName 関数
-- スクリプト名を決定する。
-- 引数：
--   in_header: クライアントが送出した HTTP ヘッダの内容。
--   ip_addr: クライアントの IP アドレス。
--   in_uri: クライアントが問い合わせてきた URI アドレス。
--   
-- 戻り値：
--   スクリプト名。""（空白）を返すとそのクライアントにはサービスを提供しない。
---------------------------------------------------------------------]]
function BMS.GetScriptFileName(in_header, ip_addr, in_uri)

  local i1 = string.find(in_header, "X-AV-Client-Info:", 1, true)
  local s = ""
  if i1 then
    s = string.match(in_header, 'mn="(.-)"', i1)
    --print("\r\nDEBUG:"..s.."\r\n")
  end

  if s and string.sub(s, 1, 6) == "BRAVIA" then
    BMS.ClientInfo.name = "BRAVIA"
    BMS.ClientInfo.ext = s
    return BMS.ClientInfo.name
  end

  i1 = string.find(in_header, "X-AV-Physical-Unit-Info:", 1, true)
  s = nil
  if i1 then
    s = string.match(in_header, 'pa="(.-)"', i1)
  end

  if s then
    -- Sony Bravia 3000/5000/7000 Series
    BMS.ClientInfo.name = "BRAVIA"
    BMS.ClientInfo.ext = s
    return BMS.ClientInfo.name
  end

  i1 = string.find(in_header, "X-PANASONIC-Registration:", 1, true)
  if i1 then
    -- Panasonic プライベート・ビエラ SV-ME7000
    BMS.ClientInfo.name = "VIERA"
    BMS.ClientInfo.ext = "SV-ME7000"
    return BMS.ClientInfo.name
  end

  i1 = string.find(string.upper(in_header), "USER-AGENT:", 1, true)
  if i1 then
    s = string.match(in_header, "(Panasonic Digital Media Player/1%.00)", i1)
    if s then
      -- Panasonic ビエラ・ワンセグ SV-ME970
      BMS.ClientInfo.name = "VIERA-SV-ME970"
      return BMS.ClientInfo.name
    end
    
    s = string.match(in_header, "Panasonic MIL DLNA CP", i1)
    if s then
      -- Panasonic ビエラ
      BMS.ClientInfo.name = "VIERA"
      return BMS.ClientInfo.name
    end
  end

  -- IP アドレスと同じ名前のスクリプトファイル（例：192.168.0.17.lua）があるならそれを使う。
  if BMS_ScriptFileExists(ip_addr) then
    BMS.ClientInfo.name = ip_addr
    return BMS.ClientInfo.name
  end

  BMS.ClientInfo.name = "NONAME"
  return BMS.ClientInfo.name
end


----------------------------------------------------------------------
-- BMS.GetCmdTimeSeek 関数
-- トランスコードコマンド中の $_cmd_seek_xxxxx_$ に対応するタイムシークコマンド
-- を返す。
-- 引数：
--   tc : トランスコーダー名など($_cmd_seek_xxxxx_$における「xxxxx」の部分)
--   start : 開始時間（HH:MM:SS.msec）
--   len : 持続時間（HH:MM:SS.msec）
--   t_len : メディアファイルのサイズ(Byte)
--   t_msec : メディアファイルの総時間(ミリ秒)
----------------------------------------------------------------------
function BMS.GetCmdTimeSeek(tc, start, len, t_len, t_msec)
  local s = ""
  if tc == "mencoder" then
    if start then s = "-ss "..start end
    if len then s = s.." -endpos "..len end
  elseif tc == "ffmpeg" then
    if start then s = "-ss "..start end
    if len then s = s.." -t "..len end
  end
  return s
end


----------------------------------------------------------------------
-- BMS.GetCmdRangeSeek 関数
-- トランスコードコマンド中の $_cmd_seek_xxxxx_$ に対応するレンジシーク
-- コマンドを返す。
-- 引数：
--   tc : トランスコーダー名など($_cmd_seek_xxxxx_$における「xxxxx」の部分)
--   start : 開始オフセット(Byte、0～。なお、Seek不要の場合は nil）
--   len : 持続バイト数。なお、Seek不要の場合は nil。
--   t_len : メディアファイルのサイズ(Byte)
--   t_msec : メディアファイルの総時間(ミリ秒)
----------------------------------------------------------------------
function BMS.GetCmdRangeSeek(tc, start, len, t_len, t_msec)
  local s = ""
  if tc == "mencoder" then
    if start then s = "-sb "..start end
    if len then s = s.." -endpos "..len end
  elseif tc == "ffmpeg" then
    -- バイト単位でシークする機能はなさそうなので簡易的に秒数でシーク
    if start then
      local t = t_msec / t_len * start
      s = "-ss "..math.floor(t / 1000).."."..math.floor(t % 1000)
    end
    if len then
      local t = t_msec / t_len * len
      s = s.." -t "..math.floor(t / 1000).."."..math.floor(t % 1000)
    end
  end
  return s
end


----------------------------------------------------------------------
-- BMS.GetCmdQuiet 関数
-- トランスコードコマンド中の $_cmd_quiet_xxxxx_$ に対応するコマンド
-- （stdoutやstderr出力方法を指定するコマンド）を返す。
-- 引数：
--   tc : トランスコーダー名など($_cmd_quiet_xxxxx_$における「xxxxx」の部分)
----------------------------------------------------------------------
function BMS.GetCmdQuiet(tc)
  if tc == "mencoder" then
    return "-quiet"
  elseif tc == "ffmpeg" then
    return "-v error"
  end
  return ""
end


----------------------------------------------------------------------
-- BMS.GetFolderName 関数
-- メディアリストでのフォルダ名の表示方法を返す。
-- 引数：
--   fname : フォルダ名
----------------------------------------------------------------------
function BMS.GetFolderName(fname)
  return "< " .. fname .. " >"
end


-------------------------- 以下は、便利な関数群 -----------------------


----------------------------------------------------------------------
-- OrdSet 関数
--   リスト内の要素に一致するかという判断を簡潔に記述できる。
--   例)
--   BRAVIA_LIST = OrdSet({"HX850", "HX750", "EX550", "EX540"})
--   if BRAVIA_LIST[s] then・・・  s がリスト内のどれかの要素と一致するなら真となる
----------------------------------------------------------------------
function OrdSet(t)
  local s = {}
  for i,v in ipairs(t) do s[v] = i end
  return s
end


----------------------------------------------------------------------
-- GetFileBaseName 関数
--   指定されたパス内に含まれるファイルのベース名 (ファイル拡張子を除いたもの) を
--   表す文字列を返す。
--   例）c:/abc/defghijk.mpg -> defghijk
----------------------------------------------------------------------
function GetFileBaseName(fname)
  return string.gsub(fileu.ExtractFileName(fname), "%.[^%.]*$", "")
end


