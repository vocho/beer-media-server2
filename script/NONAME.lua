----------------------------------------------------------------------
--
-- 一般的な DLNA クライアント用スクリプト
--
----------------------------------------------------------------------


----------------------------------------------------------------------
-- この機種がサポートしているメディア情報のリスト
----------------------------------------------------------------------
BMS.SUPPORT_MEDIA_LIST = {
  "image/jpeg:DLNA.ORG_PN=JPEG_SM",
  "image/jpeg:DLNA.ORG_PN=JPEG_MED",
  "image/jpeg:DLNA.ORG_PN=JPEG_LRG",
  "audio/mpeg:DLNA.ORG_PN=MP3",
  "audio/L16:DLNA.ORG_PN=LPCM",
  "video/mpeg:*",
  "video/mp4:*"
}


----------------------------------------------------------------------
-- BMS.GetPlayInfo 関数
--   メディアファイルの再生方法の情報を返す。
--   引数：
--     fname: ファイル名
--     minfo: MediaInfo.dll などから得られた情報
--   戻り値：
--     1: MimeType または トランスコード情報テーブル
--     2: 表示用文字列（省略でファイル名そのまま）
--     3: ソート用文字列（省略でファイル名そのまま）
----------------------------------------------------------------------
function BMS.GetPlayInfo(fname, minfo)

  local ext = string.lower(string.match(fname, "%.([^.]*)$") or "")

  if ext == "m3u" or ext == "m3u8" then
    -- m3u ファイルをフォルダとして取り扱うよう指示
    return "M3U_FOLDER", GetFileBaseName(fname)
  end

  if minfo.General.Format == "" then return "" end
  
  -- 録画中のファイル？
  if minfo.General.Format == "NowRecording" then
    return ""  -- 無視させる
  end

  if ext == "jpg" then
    return "image/jpeg:DLNA.ORG_PN=JPEG_LRG"
  end

  if ext == "mp3" then
    return "audio/mpeg:DLNA.ORG_PN=MP3"
  end
  
  if ext == "wav" then
    return "audio/L16:DLNA.ORG_PN=LPCM"
  end
  
  if minfo.Video.Format == "" then return "" end
  
  if minfo.General.Format == "MPEG-4" and minfo.Video.Format == "AVC" then
    return "video/mp4:*"
  else
    return "video/mpeg:*"
  end
end


