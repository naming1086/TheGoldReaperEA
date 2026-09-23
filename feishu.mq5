//+------------------------------------------------------------------+
//|                                                      feishu.mq5   |
//|            Feishu (Lark) webhook sidebar panel / dashboard        |
//|                                                                  |
//| What it shows on the chart (no Journal spam):                     |
//|   * webhook URL and signing state                                 |
//|   * local clock vs server clock and their skew                     |
//|   * the signing material: timestamp, stringToSign, HmacSHA256, sign |
//|   * the exact JSON request body                                    |
//|   * HTTP status, reply code / message and the raw response body     |
//|   * a colour-coded verdict line                                    |
//|                                                                  |
//| Two buttons at the bottom of the panel:                            |
//|   [发送 / 重发]  re-sends the request and repaints the panel        |
//|   [清空结果]     clears the cached reply                           |
//|                                                                  |
//| IMPORTANT - why this is an EA and not a custom indicator           |
//|   WebRequest() is forbidden inside custom indicators: the terminal   |
//|   fails the call with error 4060 (function not allowed). Only EAs    |
//|   and scripts may open the URL, so the panel is delivered as an EA   |
//|   that draws itself on the chart exactly like a sidebar indicator.   |
//|   Remember to enable the "Algo Trading" button and to whitelist the  |
//|   URL:  Tools > Options > Expert Advisors >                        |
//|         "Allow WebRequest for listed URL"  ->  https://open.feishu.cn|
//+------------------------------------------------------------------+
#property copyright "PA Agent"
#property version   "1.00"
#property description "Feishu webhook sidebar panel: signature, payload, HTTP status and raw reply on the chart."

//--- Inputs ---------------------------------------------------------
input group "FEISHU"
input string         InpWebhookUrl       = "https://open.feishu.cn/open-apis/bot/v2/hook/8f8957be-02e8-4d58-800c-ae17c5cdcefa"; // Webhook URL
input string         InpSecret           = "mV3CKdwuKybTmZbslHlTtf"; // Signing secret (empty = unsigned)
input string         InpMessage          = "PA Agent 飞书 webhook 自检（来自 MT5 面板）"; // Message text
input bool           InpSignEnabled      = true;   // Attach timestamp + sign
input bool           InpSendOnInit       = true;   // Send once when the panel is attached
input int            InpTimeoutMs        = 5000;   // WebRequest timeout (milliseconds)
input bool           InpShowSecretInPanel= false;  // Show the secret inside stringToSign

input group "PANEL"
input ENUM_BASE_CORNER InpCorner         = CORNER_LEFT_UPPER; // Panel corner
input int            InpPanelX           = 10;     // Panel X offset
input int            InpPanelY           = 30;     // Panel Y offset
input int            InpPanelWidth       = 470;    // Panel width (pixels)
input int            InpLineHeight       = 14;     // Line height (pixels)
input int            InpCharsPerLine     = 68;     // Characters per line before wrapping
input int            InpFontSize         = 9;      // Font size
input string         InpFontName         = "Consolas"; // Font
input int            InpMaxBodyChars     = 1200;   // Max response-body characters shown
input bool           InpShowHeaders      = true;   // Show the response headers
input bool           InpLiveClock        = true;   // Refresh the clock lines every second
input bool           InpJournalErrorsOnly= true;   // Journal only gets failures
input color          InpBackColor        = C'16,20,26';    // Panel background
input color          InpBorderColor      = C'70,84,100';   // Panel border
input color          InpTextColor        = C'220,225,232'; // Normal text
input color          InpTitleColor       = C'90,180,255';  // Title / section text
input color          InpOkColor          = C'70,220,130';  // Success text
input color          InpFailColor        = C'255,95,95';   // Failure text

//--- Object names ---------------------------------------------------
#define FS_BG        "FS_PANEL_BG"
#define FS_BTN_SEND  "FS_BTN_SEND"
#define FS_BTN_RESET "FS_BTN_RESET"
#define FS_LINE_PFX  "FS_LINE_"

//--- Panel line buffer ----------------------------------------------
struct PanelLine
  {
   string text; // Line content
   color  clr;  // Line colour
  };

PanelLine g_lines[];         // Lines of the current render
int       g_drawnLines = 0;  // Lines drawn by the previous render

//--- Last request / reply -------------------------------------------
struct WebhookResult
  {
   bool     attempted;   // True once a request has been made
   datetime sentAt;      // When it was made
   int      httpCode;    // HTTP status, -1 when nothing was sent
   int      lastError;   // Terminal error code
   string   timestamp;   // Feishu timestamp
   string   stringToSign;// Signing string (secret may be hidden)
   string   macHex;      // Raw HmacSHA256 bytes as hex
   string   sign;        // Base64 signature
   string   payload;     // JSON body that was posted
   string   headers;     // Response headers
   string   body;        // Raw response body
   string   code;        // Reply code field
   string   message;     // Reply message field
   bool     accepted;    // True when Feishu answered with code 0
   string   note;        // Extra hint for the user
  };

WebhookResult g_result;      // Cached result

long g_clockCorrection = 0;  // Seconds learned from the server "Date" header

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Reset the cached result and the panel
   g_result.attempted = false;
   g_result.httpCode  = -1;
   g_result.lastError = 0;
   g_result.timestamp = "";
   g_result.stringToSign = "";
   g_result.macHex    = "";
   g_result.sign      = "";
   g_result.payload   = "";
   g_result.headers   = "";
   g_result.body      = "";
   g_result.code      = "";
   g_result.message   = "";
   g_result.accepted  = false;
   g_result.note      = "";
   //--- Draw the panel for the first time
   RefreshPanel();
   //--- Send the first request when requested
   if(InpSendOnInit) SendRequest();
   //--- Refresh the clock lines every second
   if(InpLiveClock) EventSetTimer(1);
   //--- Report a successful init
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Stop the timer
   EventKillTimer();
   //--- Remove every object owned by this panel
   ObjectsDeleteAll(0, "FS_");
   //--- Repaint the chart
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Timer: keep the clock lines alive                                |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //--- Repaint only when the panel is enabled
   RefreshPanel();
  }

//+------------------------------------------------------------------+
//| Ticks are not needed, but keep the chart fresh                   |
//+------------------------------------------------------------------+
void OnTick()
  {
  }

//+------------------------------------------------------------------+
//| Button clicks                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   //--- Only button clicks matter here
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   //--- Send / resend
   if(sparam == FS_BTN_SEND)
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      SendRequest();
      RefreshPanel();
      return;
     }
   //--- Clear the cached reply
   if(sparam == FS_BTN_RESET)
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      g_result.attempted = false;
      g_result.httpCode  = -1;
      g_result.lastError = 0;
      g_result.headers   = "";
      RefreshPanel();
      return;
     }
  }

//+------------------------------------------------------------------+
//| Append one line to the panel buffer (internal)                   |
//+------------------------------------------------------------------+
void AddPanelLine(const string text, const color clr)
  {
   //--- Grow the buffer by one line
   int n = ArraySize(g_lines);
   ArrayResize(g_lines, n + 1);
   g_lines[n].text = text;
   g_lines[n].clr  = clr;
  }

//+------------------------------------------------------------------+
//| Append text, splitting on newlines and wrapping long lines       |
//+------------------------------------------------------------------+
void AddWrapped(const string text, const color clr)
  {
   //--- Split the source text on explicit line breaks
   string segments[];
   int count = StringSplit(text, '\n', segments);
   //--- Handle the empty-text case
   if(count <= 0)
     {
      AddPanelLine("", clr);
      return;
     }
   //--- Work through every segment
   int width = MathMax(16, InpCharsPerLine);
   for(int s = 0; s < count; s++)
     {
      //--- Read one segment
      string segment = segments[s];
      int    length  = StringLen(segment);
      //--- Keep blank lines as separators
      if(length == 0)
        {
         AddPanelLine("", clr);
         continue;
        }
      //--- Cut the segment into screen-width chunks
      for(int pos = 0; pos < length; pos += width)
         AddPanelLine(StringSubstr(segment, pos, width), clr);
     }
  }

//+------------------------------------------------------------------+
//| Truncate a long text so the panel stays readable                 |
//+------------------------------------------------------------------+
string TruncateText(const string text, const int maxChars)
  {
   //--- Leave short texts untouched
   if(maxChars <= 0 || StringLen(text) <= maxChars) return text;
   //--- Cut and mark the truncation
   return StringSubstr(text, 0, maxChars) + " …(截断)";
  }

//+------------------------------------------------------------------+
//| Current timeframe as a short label (M15, H1, ...)                |
//+------------------------------------------------------------------+
string TimeframeText()
  {
   //--- Strip the PERIOD_ prefix from the enum name
   string tf = EnumToString((ENUM_TIMEFRAMES)_Period);
   StringReplace(tf, "PERIOD_", "");
   return tf;
  }

//+------------------------------------------------------------------+
//| Convert a string into UTF-8 bytes (terminating zero removed)     |
//+------------------------------------------------------------------+
void Utf8Bytes(const string text, uchar &bytes[])
  {
   //--- Convert with the UTF-8 code page
   char raw[];
   int copied = StringToCharArray(text, raw, 0, WHOLE_ARRAY, CP_UTF8);
   //--- Ignore a failed conversion
   if(copied < 0) copied = 0;
   //--- Drop the terminating zero added by the conversion
   if(copied > 0 && raw[copied - 1] == 0) copied--;
   //--- Copy the bytes into the unsigned buffer
   ArrayResize(bytes, copied);
   for(int i = 0; i < copied; i++) bytes[i] = (uchar)raw[i];
  }

//+------------------------------------------------------------------+
//| Convert an ASCII byte buffer back into a string                  |
//+------------------------------------------------------------------+
string AsciiToString(const uchar &bytes[])
  {
   //--- Nothing to convert on an empty buffer
   int count = ArraySize(bytes);
   if(count <= 0) return "";
   //--- Build a char buffer for the conversion
   char raw[];
   ArrayResize(raw, count);
   for(int i = 0; i < count; i++) raw[i] = (char)bytes[i];
   //--- Convert exactly the measured number of characters
   return CharArrayToString(raw, 0, count, CP_ACP);
  }

//+------------------------------------------------------------------+
//| Render a byte buffer as spaced hex                               |
//+------------------------------------------------------------------+
string BytesToHex(const uchar &bytes[])
  {
   //--- Build one two-digit group per byte
   string out = "";
   for(int i = 0; i < ArraySize(bytes); i++)
     {
      if(i > 0) out += " ";
      out += StringFormat("%02x", bytes[i]);
     }
   //--- Return the dump
   return out;
  }

//+------------------------------------------------------------------+
//| Escape a string so it can be embedded in a JSON string           |
//+------------------------------------------------------------------+
string JsonEscape(const string text)
  {
   //--- Walk every character of the source text
   string out = "";
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
     {
      //--- Read one UTF-16 code unit
      ushort code = StringGetCharacter(text, i);
      switch(code)
        {
         case 34: out += "\\\""; break; // double quote
         case 92: out += "\\\\"; break; // backslash
         case 10: out += "\\n";  break; // line feed
         case 13: out += "\\r";  break; // carriage return
         case 9:  out += "\\t";  break; // tab
         case 8:  out += "\\b";  break; // backspace
         case 12: out += "\\f";  break; // form feed
         default:
            //--- Escape the remaining control characters numerically
            if(code < 32) out += StringFormat("\\u%04x", code);
            else          out += ShortToString(code);
            break;
        }
     }
   //--- Return the escaped text
   return out;
  }

//+------------------------------------------------------------------+
//| SHA-256 of a byte buffer (uses the terminal crypto library)      |
//+------------------------------------------------------------------+
bool Sha256Of(const uchar &data[], uchar &digest[])
  {
   //--- The key argument is unused by the hash methods
   uchar noKey[];
   //--- CryptEncode returns the byte count of the digest
   return (CryptEncode(CRYPT_HASH_SHA256, data, noKey, digest) > 0);
  }

//+------------------------------------------------------------------+
//| HMAC-SHA256 over a byte buffer                                   |
//+------------------------------------------------------------------+
bool HmacSha256(const uchar &key[], const uchar &message[], uchar &mac[])
  {
   //--- Normalise the key into a 64-byte block
   uchar block[64];
   ArrayInitialize(block, 0);
   if(ArraySize(key) > 64)
     {
      //--- Keys longer than the block size are hashed first
      uchar keyDigest[];
      if(!Sha256Of(key, keyDigest)) return false;
      for(int i = 0; i < ArraySize(keyDigest); i++) block[i] = keyDigest[i];
     }
   else
      for(int i = 0; i < ArraySize(key); i++) block[i] = key[i];
   //--- Build ipad || message
   int msgLen = ArraySize(message);
   uchar inner[];
   ArrayResize(inner, 64 + msgLen);
   for(int i = 0; i < 64; i++)     inner[i]      = (uchar)(block[i] ^ 0x36);
   for(int i = 0; i < msgLen; i++) inner[64 + i] = message[i];
   //--- Hash the inner buffer
   uchar innerHash[];
   if(!Sha256Of(inner, innerHash)) return false;
   //--- Build opad || inner hash
   uchar outer[];
   ArrayResize(outer, 64 + ArraySize(innerHash));
   for(int i = 0; i < 64; i++)                   outer[i]      = (uchar)(block[i] ^ 0x5C);
   for(int i = 0; i < ArraySize(innerHash); i++) outer[64 + i] = innerHash[i];
   //--- The outer hash is the MAC
   return Sha256Of(outer, mac);
  }

//+------------------------------------------------------------------+
//| Build the Feishu timestamp, raw MAC and Base64 signature         |
//+------------------------------------------------------------------+
bool BuildSign(const string secret, string &timestampOut, string &signOut, string &macHexOut)
  {
   //--- Feishu compares the timestamp with real UTC time. TimeLocal() would send
   //--- the local wall clock as if it were UTC (8 hours ahead on a UTC+8 machine)
   //--- and every request would come back as 19021. TimeGMT() yields the real epoch.
   long stamp = (long)TimeGMT() + g_clockCorrection;
   //--- The string to sign is the timestamp, a newline and the secret
   string stringToSign = IntegerToString(stamp) + "\n" + secret;
   //--- The HMAC key is the string to sign and the payload is empty
   uchar keyBytes[], emptyMessage[], mac[];
   Utf8Bytes(stringToSign, keyBytes);
   if(!HmacSha256(keyBytes, emptyMessage, mac)) return false;
   //--- Base64 the raw MAC
   uchar noKey[], encoded[];
   if(CryptEncode(CRYPT_BASE64, mac, noKey, encoded) <= 0) return false;
   //--- Publish the results
   timestampOut = IntegerToString(stamp);
   signOut      = AsciiToString(encoded);
   macHexOut    = BytesToHex(mac);
   return true;
  }

//+------------------------------------------------------------------+
//| Read the text of a numeric JSON field (very small parser)        |
//+------------------------------------------------------------------+
string JsonNumberText(const string json, const string field)
  {
   //--- Locate the field name
   string needle = "\"" + field + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0) return "";
   //--- Skip the name, the colon and any spaces
   int i = pos + StringLen(needle);
   while(i < StringLen(json) && (StringGetCharacter(json, i) == ':' || StringGetCharacter(json, i) == ' ')) i++;
   //--- Collect the number characters
   string out = "";
   while(i < StringLen(json))
     {
      ushort code = StringGetCharacter(json, i);
      //--- Stop at anything that is not part of a number
      if(!((code >= '0' && code <= '9') || code == '-' || code == '.')) break;
      out += ShortToString(code);
      i++;
     }
   //--- Return what was found
   return out;
  }

//+------------------------------------------------------------------+
//| Read the value of a string JSON field (very small parser)        |
//+------------------------------------------------------------------+
string JsonStringText(const string json, const string field)
  {
   //--- Locate the field name
   string needle = "\"" + field + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0) return "";
   //--- Skip the name, the colon and any spaces
   int i = pos + StringLen(needle);
   while(i < StringLen(json) && (StringGetCharacter(json, i) == ':' || StringGetCharacter(json, i) == ' ')) i++;
   //--- Only string values are handled here
   if(i >= StringLen(json) || StringGetCharacter(json, i) != '"') return "";
   i++;
   //--- Collect characters up to the closing quote
   string out = "";
   while(i < StringLen(json))
     {
      //--- Read one code unit
      ushort code = StringGetCharacter(json, i);
      if(code == '"') break;
      //--- Undo the escapes Feishu actually uses
      if(code == 92 && i + 1 < StringLen(json))
        {
         ushort next = StringGetCharacter(json, i + 1);
         if(next == 'n')  { out += "\n"; i += 2; continue; }
         if(next == 't')  { out += "\t"; i += 2; continue; }
         if(next == '"')  { out += "\""; i += 2; continue; }
         if(next == 92)   { out += "\\"; i += 2; continue; }
        }
      //--- Append the plain character
      out += ShortToString(code);
      i++;
     }
   //--- Return what was found
   return out;
  }

//+------------------------------------------------------------------+
//| Look for a zero-valued field inside a compact JSON reply         |
//+------------------------------------------------------------------+
bool JsonFieldIsZero(const string json, const string field)
  {
   //--- Accept both compact and spaced layouts
   return (StringFind(json, "\"" + field + "\":0") >= 0 || StringFind(json, "\"" + field + "\": 0") >= 0);
  }

//+------------------------------------------------------------------+
//| Turn an HTTP month abbreviation into a month number              |
//+------------------------------------------------------------------+
int MonthFromName(const string name)
  {
   //--- RFC 7231 uses the English three letter abbreviations
   string months[12] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
   for(int i = 0; i < 12; i++)
      if(name == months[i]) return i + 1;
   //--- Unknown month
   return 0;
  }

//+------------------------------------------------------------------+
//| Parse "Date: Wed, 23 Sep 2026 02:42:45 GMT" into a UTC epoch     |
//+------------------------------------------------------------------+
long ParseHttpDate(const string headers)
  {
   //--- Locate the header
   int pos = StringFind(headers, "Date:");
   if(pos < 0) return 0;
   //--- Cut the single header line out of the block
   int eol  = StringFind(headers, "\r\n", pos);
   string line = (eol < 0) ? StringSubstr(headers, pos) : StringSubstr(headers, pos, eol - pos);
   //--- Split it into: "Date:", "Wed,", "23", "Sep", "2026", "02:42:45", "GMT"
   string parts[];
   if(StringSplit(line, ' ', parts) < 6) return 0;
   //--- Split the clock field
   string hms[];
   if(StringSplit(parts[5], ':', hms) < 3) return 0;
   //--- Resolve the month name
   int month = MonthFromName(parts[3]);
   if(month == 0) return 0;
   //--- Assemble the time structure
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = (int)StringToInteger(parts[4]);
   dt.mon  = month;
   dt.day  = (int)StringToInteger(parts[2]);
   dt.hour = (int)StringToInteger(hms[0]);
   dt.min  = (int)StringToInteger(hms[1]);
   dt.sec  = (int)StringToInteger(hms[2]);
   //--- Interpret the fields as UTC, matching the timestamp convention
   return (long)StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Hint text for the codes Feishu returns most often                |
//+------------------------------------------------------------------+
string ReplyNote(const string code)
  {
   //--- Explain the codes worth acting on
   if(code == "19021") return "19021 = 签名校验失败：检查 secret；时间戳必须用 UTC（本面板已用 TimeGMT，勿改回 TimeLocal）";
   if(code == "19001") return "19001 = 参数非法：消息体或 hook token 有问题";
   if(code == "19002" || code == "19003") return "token 失效：机器人已被移出群或被禁用";
   if(code == "9499")  return "9499 = 消息被拒（频率限制或内容被拦截）";
   if(code != "")      return "未知返回码，请对照飞书自定义机器人文档";
   //--- Nothing to explain
   return "";
  }

//+------------------------------------------------------------------+
//| Send the request and cache every detail of the exchange          |
//+------------------------------------------------------------------+
void SendRequest()
  {
   //--- Reset the cached exchange
   g_result.attempted    = true;
   g_result.sentAt       = TimeLocal();
   g_result.httpCode     = -1;
   g_result.lastError    = 0;
   g_result.timestamp    = "";
   g_result.stringToSign = "";
   g_result.macHex       = "";
   g_result.sign         = "";
   g_result.payload      = "";
   g_result.headers      = "";
   g_result.body         = "";
   g_result.code         = "";
   g_result.message      = "";
   g_result.accepted     = false;
   g_result.note         = "";
   //--- Validate the URL
   if(StringLen(InpWebhookUrl) == 0)
     {
      g_result.note = "配置错误：webhook URL 为空";
      return;
     }
   //--- Decide whether a signature is attached
   bool signUsed = (InpSignEnabled && StringLen(InpSecret) > 0);
   //--- Build the signature when requested
   if(signUsed)
     {
      //--- Compute timestamp, MAC and Base64 signature
      if(!BuildSign(InpSecret, g_result.timestamp, g_result.sign, g_result.macHex))
        {
         g_result.note = "签名计算失败";
         return;
        }
      //--- Remember the signing string, hiding the secret on request
      g_result.stringToSign = InpShowSecretInPanel
                              ? g_result.timestamp + "\\n" + InpSecret
                              : "<epoch>\\n<secret 已隐藏, " + IntegerToString(StringLen(InpSecret)) + " 字符>";
     }
   //--- Resolve the message text
   string message = InpMessage;
   if(StringLen(message) == 0) message = "PA Agent webhook test (空消息输入)";
   //--- Assemble the JSON body
   string body = "{\"msg_type\":\"text\",\"content\":{\"text\":\"" + JsonEscape(message) + "\"}";
   if(signUsed) body += ",\"timestamp\":\"" + g_result.timestamp + "\",\"sign\":\"" + g_result.sign + "\"";
   body += "}";
   g_result.payload = body;
   //--- Convert the body to UTF-8 bytes
   char post[];
   int written = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(written > 0 && post[written - 1] == 0) ArrayResize(post, written - 1);
   //--- Send the request
   char   result[];
   string resultHeaders = "";
   string headers       = "Content-Type: application/json; charset=utf-8\r\n";
   ResetLastError();
   int httpCode = WebRequest("POST", InpWebhookUrl, headers, InpTimeoutMs, post, result, resultHeaders);
   g_result.httpCode  = httpCode;
   g_result.lastError = GetLastError();
   g_result.headers   = resultHeaders;
   //--- Learn the exact server clock from the reply's Date header, so a drifted
   //--- PC clock is compensated automatically on the next request
   long serverEpoch = ParseHttpDate(resultHeaders);
   if(serverEpoch > 0) g_clockCorrection = serverEpoch - (long)TimeGMT();
   //--- Explain a failed transport
   if(httpCode == -1)
     {
      //--- Map the most common terminal errors
      if(g_result.lastError == 4060 || g_result.lastError == 4014)
         g_result.note = "WebRequest 被拦截：请在 工具 > 选项 > 智能交易系统 中勾选「允许 WebRequest 的 URL 列表」并加入 https://open.feishu.cn";
      else if(g_result.lastError == 5273)
         g_result.note = "请求超时或网络不可达（代理/VPN？）";
      else
         g_result.note = "请求未发出，请查看错误码";
      //--- Mirror failures to the Journal when requested
      if(InpJournalErrorsOnly) Print("FEISHU> 请求失败 http=" + IntegerToString(httpCode) + " err=" + IntegerToString(g_result.lastError));
      return;
     }
   //--- Decode the reply body
   g_result.body = CharArrayToString(result, 0, ArraySize(result), CP_UTF8);
   //--- Pull out the status fields
   string codeField = (StringFind(g_result.body, "\"StatusCode\"") >= 0) ? "StatusCode" : "code";
   g_result.code    = JsonNumberText(g_result.body, codeField);
   g_result.message = JsonStringText(g_result.body, "msg");
   if(g_result.message == "") g_result.message = JsonStringText(g_result.body, "StatusMessage");
   //--- Decide whether Feishu accepted the message
   g_result.accepted = (JsonFieldIsZero(g_result.body, "code") || JsonFieldIsZero(g_result.body, "StatusCode"));
   //--- Attach a hint for known failures
   g_result.note = ReplyNote(g_result.code);
   //--- Mirror failures to the Journal when requested
   if(!g_result.accepted && InpJournalErrorsOnly)
      Print("FEISHU> 推送被拒 http=" + IntegerToString(httpCode) + " code=" + g_result.code + " body=" + g_result.body);
  }

//+------------------------------------------------------------------+
//| Rebuild the line buffer with the whole panel content             |
//+------------------------------------------------------------------+
void BuildPanelLines()
  {
   //--- Start from scratch
   ArrayResize(g_lines, 0);
   //--- Title
   AddPanelLine("FEISHU WEBHOOK 面板  " + _Symbol + " " + TimeframeText(), InpTitleColor);
   AddPanelLine("────────────────────────────────────────────────────────", InpBorderColor);
   //--- Configuration block
   AddWrapped("URL   : " + InpWebhookUrl, InpTextColor);
   bool signUsed = (InpSignEnabled && StringLen(InpSecret) > 0);
   AddPanelLine("签名  : " + (signUsed ? "启用（secret " + IntegerToString(StringLen(InpSecret)) + " 字符）" : "关闭"), InpTextColor);
   AddPanelLine("本机  : " + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + "   (本地墙钟，不能用于签名)", InpTextColor);
   AddPanelLine("UTC   : " + TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS) + "   <- 签名时间戳 epoch " + IntegerToString((long)TimeGMT()), InpOkColor);
   AddPanelLine("服务器: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "   本机-服务器 " + IntegerToString((long)TimeLocal() - (long)TimeCurrent()) + " 秒", InpTextColor);
   AddPanelLine("时钟校正: " + (g_clockCorrection >= 0 ? "+" : "") + IntegerToString(g_clockCorrection) + " 秒（按飞书响应 Date 头自动校正）", InpTextColor);
   //--- Request block
   if(g_result.attempted)
     {
      //--- Header line with the send time
      AddPanelLine("── 请求 ──  发送于 " + TimeToString(g_result.sentAt, TIME_DATE | TIME_SECONDS), InpTitleColor);
      AddPanelLine("timestamp    : " + g_result.timestamp, InpTextColor);
      AddWrapped("stringToSign : " + g_result.stringToSign, InpTextColor);
      AddWrapped("hmac(hex)    : " + g_result.macHex, InpTextColor);
      AddWrapped("sign(base64) : " + g_result.sign, InpTextColor);
      AddWrapped("payload      : " + g_result.payload, InpTextColor);
      //--- Reply block
      AddPanelLine("── 返回 ──", InpTitleColor);
      AddPanelLine("HTTP         : " + IntegerToString(g_result.httpCode) + "     last error " + IntegerToString(g_result.lastError), InpTextColor);
      //--- Show the parsed status when a body arrived
      if(StringLen(g_result.body) > 0)
        {
         //--- Colour the code line by the verdict
         AddPanelLine("code         : " + (g_result.code == "" ? "<未找到>" : g_result.code) + "     message " + (g_result.message == "" ? "<未找到>" : g_result.message),
                      g_result.accepted ? InpOkColor : InpFailColor);
         AddWrapped("body         : " + TruncateText(g_result.body, InpMaxBodyChars), InpTextColor);
        }
      //--- Response headers are optional
      if(InpShowHeaders && StringLen(g_result.headers) > 0)
         AddWrapped("headers      : " + TruncateText(g_result.headers, 400), InpTextColor);
      //--- Hint line
      if(StringLen(g_result.note) > 0) AddWrapped("提示         : " + g_result.note, g_result.accepted ? InpOkColor : InpFailColor);
      //--- Verdict
      string verdict = g_result.accepted
                       ? "RESULT : 成功 —— webhook 已接收，去群里确认"
                       : (g_result.httpCode == -1 ? "RESULT : 失败 —— 请求未发出" : "RESULT : 失败 —— 被飞书拒绝，见上方返回码");
      AddPanelLine(verdict, g_result.accepted ? InpOkColor : InpFailColor);
     }
   else
     {
      //--- Nothing sent yet
      AddPanelLine("尚未发送。点下方 [发送 / 重发] 立刻测试一次。", InpTextColor);
     }
   //--- Footer
   AddPanelLine("────────────────────────────────────────────────────────", InpBorderColor);
   AddPanelLine("面板每秒刷新时钟；参数改动后需重新加载本 EA", InpBorderColor);
  }

//+------------------------------------------------------------------+
//| Create or update a label object                                  |
//+------------------------------------------------------------------+
void DrawLabel(const string name, const int x, const int y, const string text, const color clr)
  {
   //--- Create the label once
   if(ObjectFind(0, name) < 0)
     {
      //--- Build a plain text label
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetString(0, name, OBJPROP_FONT, InpFontName);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
     }
   //--- Place, colour and fill the label
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Create or update a button object                                 |
//+------------------------------------------------------------------+
void DrawButton(const string name, const int x, const int y, const int w, const int h, const string text)
  {
   //--- Create the button once
   if(ObjectFind(0, name) < 0)
     {
      //--- Build a clickable button
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetString(0, name, OBJPROP_FONT, InpFontName);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 3);
     }
   //--- Place and style the button
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'38,48,62');
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpTextColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpBorderColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Redraw the whole panel                                           |
//+------------------------------------------------------------------+
void RefreshPanel()
  {
   //--- Rebuild the logical content first
   BuildPanelLines();
   //--- Panel geometry
   int padX     = 8;
   int padY     = 6;
   int lines    = ArraySize(g_lines);
   int btnH     = 22;
   int width    = MathMax(240, InpPanelWidth);
   int height   = padY * 2 + lines * InpLineHeight + btnH + 14;
   //--- Background rectangle
   if(ObjectFind(0, FS_BG) < 0)
     {
      //--- Create the panel frame once
      ObjectCreate(0, FS_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, FS_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, FS_BG, OBJPROP_BACK, false);
      ObjectSetInteger(0, FS_BG, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, FS_BG, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, FS_BG, OBJPROP_ZORDER, 1);
     }
   ObjectSetInteger(0, FS_BG, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, FS_BG, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, FS_BG, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, FS_BG, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, FS_BG, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, FS_BG, OBJPROP_BGCOLOR, InpBackColor);
   ObjectSetInteger(0, FS_BG, OBJPROP_COLOR, InpBorderColor);
   ObjectSetInteger(0, FS_BG, OBJPROP_WIDTH, 1);
   //--- Every text line
   for(int i = 0; i < lines; i++)
      DrawLabel(FS_LINE_PFX + IntegerToString(i), InpPanelX + padX, InpPanelY + padY + i * InpLineHeight, g_lines[i].text, g_lines[i].clr);
   //--- Drop labels left over from a longer previous render
   for(int i = lines; i < g_drawnLines; i++)
      ObjectDelete(0, FS_LINE_PFX + IntegerToString(i));
   g_drawnLines = lines;
   //--- Buttons at the bottom of the panel
   int btnY = InpPanelY + height - btnH - 6;
   DrawButton(FS_BTN_SEND,  InpPanelX + padX,                    btnY, 130, btnH, "发送 / 重发");
   DrawButton(FS_BTN_RESET, InpPanelX + padX + 130 + 8,          btnY, 110, btnH, "清空结果");
   //--- Repaint the chart
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
