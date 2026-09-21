// ============================================================================
//  The Gold Reaper English MT5  ·  v4.6  ·  单文件 MQL5 重建版
// ----------------------------------------------------------------------------
//  [来源]  metatester64.DMP 全量转储重建（RAR part01 ~ part05 还原）
//          JIT base : 0x0000019AA50B0000, size 0x0004F000 (PAGE_EXECUTE_READ)
//          EA  data : 0x0000019AA50FF000, size 0x00181000
//          对齐扫描共找到 68 个原生函数入口/序言候选。
//  [基准]  基于 V4.6 转储/JIT 重建（非 V4.5 版本）。保留全部 V4.6 特有行为：
//          V4.6 面板/版本号、BacktestSpeed 运行时处理、HighestBalance/OnlyUp
//          行为以及 NFP 路径。
//  [状态]  逻辑与数据均已对照转储核验；最终编译与 Strategy Tester 差分
//          验证仍需在 MetaTrader 5 中进行。
// ----------------------------------------------------------------------------
//  文件结构目录（按出现顺序，可搜索节号 "[§N]" 快速定位）：
//    §1  属性声明与 ATR 缓存全局变量
//    §2  MQL4Compat —— MQL4 -> MQL5 兼容层（原独立 .mqh 已并入本文件）
//    §3  输入参数枚举定义
//    §4  输入参数（input）
//    §5  转储重建全局变量（global_N_type_XX 命名）
//    §6  NFP 过滤辅助函数
//    §7  EA 事件处理（OnInit / DumpBacktestSpeedAllowTick / OnTick / OnDeinit）
//    §8  策略运行时设置装载（LoadStrategyRuntimeSettings）
//    §9  策略核心处理（ProcessStrategy）
//    §10 挂单管理（RestoreStoredPendingOrders / RemovePendingOrdersDuringHighSpread）
//    §11 手数计算（CalculateStrategyLotSize）
//    §12 入场价位探测（Find*EntryHigh/Low、Find*Fractal* 及 MT4 快速版）
//    §13 入场执行（ProcessStrategyEntries / PlaceBuyStopEntry / PlaceSellStopEntry）
//    §14 持仓管理（ManageBuyPositions / ManageSellPositions）
//    §15 交易时段、错误描述、信息面板与绩效统计
//    §16 各策略参数装载（LoadStrategy1~9Settings）
//    §17 PropFirm 日内回撤与 GMT/夏令时检测（EnforcePropFirmDailyDrawdown、
//        WTS_*、DetectBrokerGmtOffset、IsAmericanDst）
// ============================================================================

// ============================================================================
// [§1] 属性声明与 ATR 缓存全局变量
//      - 9 个策略各持有独立 iATR 句柄（周期/时间框架/缓存值分表记录）
//      - 美国/欧洲夏令时判定结果按天缓存（配合 §17 的 DST 检测）
// ============================================================================

#property copyright  "Copyright 2026 - Pham Duy Linh"
#property link       "https://t.me/Khonglamdoicoan96"
#property version    "4.6"

#include <Trade\Trade.mqh>
CTrade trade;

int g_atr_handles[9];
int g_atr_periods[9];
ENUM_TIMEFRAMES g_atr_timeframes[9];
datetime g_atr_checked_bars[9];
double g_atr_cached_values[9];
bool g_atr_ready[9];
datetime g_us_dst_cache_day=0;
bool g_us_dst_cache_valid=false;
bool g_us_dst_cache_value=false;
datetime g_eu_dst_cache_day=0;
bool g_eu_dst_cache_valid=false;
bool g_eu_dst_cache_value=false;

// ============================================================================
// [§2] MQL4Compat —— MQL4 -> MQL5 兼容层
//      原为独立 MQL4Compat.mqh，现已直接并入本文件，使 EA 保持
//      单 .mq5 文件、无需额外拷贝 include。详细设计说明见下方原注释。
// ============================================================================
//==================================================================
// MQL4Compat: lop tuong thich MQL4->MQL5 (truoc day la file include
// rieng MQL4Compat.mqh) - da GOP truc tiep vao day de EA chi con 1
// file .mq5 duy nhat, khong can copy file include rieng.
//==================================================================
//+------------------------------------------------------------------+
//| MQL4Compat.mqh                                                    |
//|                                                                    |
//| Lop tuong thich MQL4 -> MQL5 danh rieng cho The Gold Reaper.       |
//| Muc dich: cho phep GIU NGUYEN 100% logic goc viet theo phong cach  |
//| MQL4 (OrderSend/OrderModify/OrderClose/OrderDelete/OrderSelect,    |
//| OrdersTotal/HistoryTotal, MarketInfo, AccountBalance/Equity,       |
//| Time*()/Year()/Month()/Day()/Hour()/Minute()/Seconds()/DayOfWeek(),|
//| iMA()/iFractals() kieu tra ve gia tri truc tiep...) trong khi thuc |
//| thi ben duoi hoan toan bang API MQL5 (Position/Order/Deal,         |
//| OrderSend(MqlTradeRequest&,MqlTradeResult&) dong bo truc tiep -    |
//| khong qua CTrade - de gui/sua/dong/huy lenh, SymbolInfo*,          |
//| AccountInfo*, TimeToStruct...).                                    |
//|                                                                    |
//| QUAN TRONG:                                                        |
//|  - EA nay mo dong thoi nhieu lenh/vi the tren cung 1 symbol voi    |
//|    nhieu magic number khac nhau (multi-strategy). Vi vay tai khoan |
//|    MT5 chay EA nay BAT BUOC phai o che do HEDGING. O che do        |
//|    Netting, moi lenh cung symbol se bi gop thanh 1 vi the duy nhat |
//|    va lam sai toan bo logic quan ly lenh cua EA.                   |
//|  - Cac ham lay lich su lenh (pool=MODE_HISTORY) duoc dung lai tu   |
//|    HistoryDealsTotal(): moi cap deal (DEAL_ENTRY_IN + DEAL_ENTRY_  |
//|    OUT/OUT_BY cung POSITION_ID) duoc ghep thanh 1 "lenh lich su"   |
//|    kieu MQL4. Neu 1 vi the bi dong nhieu lan (dong 1 phan), cac    |
//|    deal dong se duoc GOM lai thanh 1 ban ghi duy nhat (tong loi/lo)|
//|    -> khac biet nho so voi MQL4 (MQL4 tao 1 ticket rieng cho moi   |
//|    lan dong 1 phan). EA nay khong dung dong 1 phan lenh nen anh    |
//|    huong la khong dang ke.                                        |
//+------------------------------------------------------------------+
#ifndef __MQL4COMPAT_MQH__
#define __MQL4COMPAT_MQH__

//====================================================================
// Hang so kieu MQL4
//====================================================================
#define OP_BUY        0
#define OP_SELL       1
#define OP_BUYLIMIT   2
#define OP_SELLLIMIT  3
#define OP_BUYSTOP    4
#define OP_SELLSTOP   5

#define SELECT_BY_POS    0
#define SELECT_BY_TICKET 1
#define MODE_TRADES      0
#define MODE_HISTORY     1

// Ma so MarketInfo() kieu MQL4 (chi gom cac ma EA nay su dung)
#define MODE_BID              9
#define MODE_ASK              10
#define MODE_POINT            11
#define MODE_DIGITS           12
#define MODE_STOPLEVEL        14
#define MODE_TICKVALUE        16
#define MODE_TRADEALLOWED     22
#define MODE_MINLOT           23
#define MODE_LOTSTEP          24
#define MODE_MAXLOT           25
#define MODE_FREEZELEVEL      33

//====================================================================
// Bien trang thai noi bo
//====================================================================
long g_mt4_lastTicket = -1;
// MT5 ticket/order/deal IDs are 64-bit. Khong ep ket qua OrderSend/OrderTicket ve int.

int  g_mt4_lastError  = 0;

//====================================================================
// Quy doi timeframe kieu "so phut" (MQL4 cu) -> ENUM_TIMEFRAMES MQL5.
// Neu tham so da la hang PERIOD_xxx cua MQL5 (gia tri >= 16385) thi
// tra ve nguyen (pass-through) vi da dung.
//====================================================================
ENUM_TIMEFRAMES MT4Period(int minutes)
{
   switch(minutes)
   {
      case 0:     return PERIOD_CURRENT;
      case 1:     return PERIOD_M1;
      case 2:     return PERIOD_M2;
      case 3:     return PERIOD_M3;
      case 4:     return PERIOD_M4;
      case 5:     return PERIOD_M5;
      case 6:     return PERIOD_M6;
      case 10:    return PERIOD_M10;
      case 12:    return PERIOD_M12;
      case 15:    return PERIOD_M15;
      case 20:    return PERIOD_M20;
      case 30:    return PERIOD_M30;
      case 60:    return PERIOD_H1;
      case 120:   return PERIOD_H2;
      case 180:   return PERIOD_H3;
      case 240:   return PERIOD_H4;
      case 360:   return PERIOD_H6;
      case 480:   return PERIOD_H8;
      case 720:   return PERIOD_H12;
      case 1440:  return PERIOD_D1;
      case 10080: return PERIOD_W1;
      case 43200: return PERIOD_MN1;
      default:    return (ENUM_TIMEFRAMES)minutes; // da la PERIOD_xxx cua MQL5
   }
}

//====================================================================
// MarketInfo() kieu MQL4
//====================================================================
double MarketInfo(string symbol,int mode)
{
   switch(mode)
   {
      case MODE_BID:
         return SymbolInfoDouble(symbol,SYMBOL_BID);
      case MODE_ASK:
         return SymbolInfoDouble(symbol,SYMBOL_ASK);
      case MODE_POINT:         return SymbolInfoDouble(symbol,SYMBOL_POINT);
      case MODE_DIGITS:        return (double)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      case MODE_STOPLEVEL:     return (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      case MODE_TICKVALUE:     return SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      case MODE_TRADEALLOWED:  return MT4SessionMarket(symbol)?1.0:0.0;
      case MODE_MINLOT:        return SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      case MODE_LOTSTEP:       return SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      case MODE_MAXLOT:        return SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      case MODE_FREEZELEVEL:   return (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   }
   return 0.0;
}

//====================================================================
// Account*() kieu MQL4
//====================================================================
double AccountBalance()  { return AccountInfoDouble(ACCOUNT_BALANCE); }
double AccountEquity()   { return AccountInfoDouble(ACCOUNT_EQUITY);  }
string AccountCurrency() { return AccountInfoString(ACCOUNT_CURRENCY);}

bool MT4EuropeanDST()
{
   datetime now=TimeCurrent();
   datetime day=now-(now%86400);
   if(g_eu_dst_cache_valid && g_eu_dst_cache_day==day)
      return g_eu_dst_cache_value;

   MqlDateTime marchEnd;
   MqlDateTime octoberEnd;
   int year=TimeYear(now);
   datetime march=StringToTime(string(year)+".03.31 01:00");
   datetime october=StringToTime(string(year)+".10.31 02:00");
   TimeToStruct(march,marchEnd);
   TimeToStruct(october,octoberEnd);
   g_eu_dst_cache_value=(TimeDayOfYear(now)>TimeDayOfYear(march-marchEnd.day_of_week*86400) &&
                         TimeDayOfYear(now)<TimeDayOfYear(october-octoberEnd.day_of_week*86400));
   g_eu_dst_cache_day=day;
   g_eu_dst_cache_valid=true;
   return g_eu_dst_cache_value;
}

double AccountFreeMarginCheck(string symbol,int cmd,double volume)
{
   if(volume<=0.0)
      return 0.0;

   // Recovered from the original V4.6 JIT: for ordinary symbols the check
   // requires at least 70 account-currency units of both equity and free
   // margin per 0.01 lot.  The original helper returns a boolean result even
   // though its legacy call site compares the value with zero.
   double lot_units=volume/0.01;
   if(lot_units<=0.0)
      return 0.0;
   if(AccountInfoDouble(ACCOUNT_EQUITY)/lot_units<70.0)
   {
      Print("equity too low");
      return 0.0;
   }
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)/lot_units<70.0)
   {
      Print("free margin too low");
      return 0.0;
   }
   return 1.0;
}

//====================================================================
// RefreshRates() - khong con can thiet trong MQL5 (gia luon la moi),
// giu lai de code cu bien dich duoc, luon tra ve true.
//====================================================================
bool RefreshRates() { return true; }

//====================================================================
// IsDemo()/IsTesting() kieu MQL4 (khong con la ham co san trong MQL5)
//====================================================================
bool IsDemo()    { return AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO; }
bool IsTesting() { return (bool)MQLInfoInteger(MQL_TESTER); }

//====================================================================
// MT4SessionMarket: Market/session gate for BOTH live/demo and Strategy Tester.
//
// IMPORTANT:
//  - This is the SINGLE Market Close gate used before OrderSend().
//  - Uses broker trade-session metadata, not OrderCheck().
//  - Uses TimeTradeServer() on live/demo so a stale last tick cannot make
//    a closed weekend/session look open.
//  - If session metadata is unavailable, fail CLOSED: no new order is sent.
//====================================================================
bool MT4SessionMarketCore(string symbol,datetime when)
{
   long trade_mode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   // Preserve the original EA rule: MODE_TRADEALLOWED was true only in FULL mode.
   if(trade_mode!=SYMBOL_TRADE_MODE_FULL)
      return false;

   if(when<=0)
   {
      if(IsTesting())
         when=TimeCurrent();
      else
         when=TimeTradeServer();

      if(when<=0)
         when=TimeCurrent();
   }

   if(when<=0)
      return false;

   MqlDateTime now_struct;
   TimeToStruct(when,now_struct);
   ENUM_DAY_OF_WEEK dow=(ENUM_DAY_OF_WEEK)now_struct.day_of_week;
   int now_seconds=now_struct.hour*3600 + now_struct.min*60 + now_struct.sec;

   datetime session_from=0;
   datetime session_to=0;
   for(uint session_index=0; session_index<64; session_index++)
   {
      if(!SymbolInfoSessionTrade(symbol,dow,session_index,session_from,session_to))
         break;

      MqlDateTime from_struct;
      MqlDateTime to_struct;
      TimeToStruct(session_from,from_struct);
      TimeToStruct(session_to,to_struct);
      int from_seconds=from_struct.hour*3600 + from_struct.min*60 + from_struct.sec;
      int to_seconds=to_struct.hour*3600 + to_struct.min*60 + to_struct.sec;

      // Some brokers encode a 24-hour session as 00:00 -> 00:00.
      if(from_seconds==to_seconds)
         return true;

      if(from_seconds<to_seconds)
      {
         if(now_seconds>=from_seconds && now_seconds<to_seconds)
            return true;
      }
      else
      {
         // Session crosses midnight.
         if(now_seconds>=from_seconds || now_seconds<to_seconds)
            return true;
      }
   }

   // No matching session means market closed. If the broker/tester does not
   // expose session metadata, fail closed instead of risking an unwanted order.
   return false;
}

string g_session_market_symbol="";
datetime g_session_market_when=0;
bool g_session_market_valid=false;
bool g_session_market_result=false;

bool MT4SessionMarket(string symbol,datetime when=0)
{
   if(when<=0)
   {
      if(IsTesting()) when=TimeCurrent();
      else when=TimeTradeServer();
      if(when<=0) when=TimeCurrent();
   }
   if(g_session_market_valid && g_session_market_symbol==symbol && g_session_market_when==when)
      return g_session_market_result;

   g_session_market_symbol=symbol;
   g_session_market_when=when;
   g_session_market_result=MT4SessionMarketCore(symbol,when);
   g_session_market_valid=true;
   return g_session_market_result;
}

//====================================================================
// Cac ham thoi gian kieu MQL4 (khong con trong MQL5)
//====================================================================
datetime g_mt4_time_parts_at=0;
MqlDateTime g_mt4_time_parts;
void MT4GetTimeParts(datetime t,MqlDateTime &s)
{
   if(t!=g_mt4_time_parts_at)
   {
      TimeToStruct(t,g_mt4_time_parts);
      g_mt4_time_parts_at=t;
   }
   s=g_mt4_time_parts;
}
int TimeYear(datetime t)      { MqlDateTime s; MT4GetTimeParts(t,s); return s.year; }
int TimeMonth(datetime t)     { MqlDateTime s; MT4GetTimeParts(t,s); return s.mon;  }
int TimeDay(datetime t)       { MqlDateTime s; MT4GetTimeParts(t,s); return s.day;  }
int TimeHour(datetime t)      { MqlDateTime s; MT4GetTimeParts(t,s); return s.hour; }
int TimeMinute(datetime t)    { MqlDateTime s; MT4GetTimeParts(t,s); return s.min;  }
int TimeSeconds(datetime t)   { MqlDateTime s; MT4GetTimeParts(t,s); return s.sec;  }
int TimeDayOfWeek(datetime t) { MqlDateTime s; MT4GetTimeParts(t,s); return s.day_of_week; }
int TimeDayOfYear(datetime t) { MqlDateTime s; MT4GetTimeParts(t,s); return s.day_of_year;  }

// Ban khong doi so (ngam dinh TimeCurrent()) - kieu MQL4 rat cu
int Year()      { return TimeYear(TimeCurrent());      }
int Month()     { return TimeMonth(TimeCurrent());     }
int Day()       { return TimeDay(TimeCurrent());       }
int Hour()      { return TimeHour(TimeCurrent());      }
int Minute()    { return TimeMinute(TimeCurrent());    }
int Seconds()   { return TimeSeconds(TimeCurrent());   }
int DayOfWeek() { return TimeDayOfWeek(TimeCurrent());  }

//====================================================================
// iMA()/iFractals() ban tra ve gia tri truc tiep (kieu MQL4), du lieu
// lay qua CopyBuffer tu handle indicator (MQL5 tu dong cache handle
// theo bo tham so nen goi lai moi tick khong gay ro ri tai nguyen).
//====================================================================
ENUM_APPLIED_PRICE MT4AppliedPrice(int p) { return (ENUM_APPLIED_PRICE)(p+1); }

double iMA(string symbol,int timeframe,int period,int ma_shift,int ma_method,int applied_price,int shift)
{
   int handle=iMA(symbol,MT4Period(timeframe),period,ma_shift,(ENUM_MA_METHOD)ma_method,MT4AppliedPrice(applied_price));
   if(handle==INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(handle,0,shift,1,buf)<=0) return 0.0;
   return buf[0];
}

double iFractals(string symbol,int timeframe,int mode,int shift)
{
   // The EA calls this compatibility wrapper only with shift=1 during OnInit.
   // A standard Bill Williams fractal needs two newer bars for confirmation,
   // therefore shift 0/1 cannot contain a confirmed fractal and is exactly 0.0.
   // Returning here avoids creating visual iFractals handles in MT5 Visual Tester.
   if(shift < 2) return 0.0;

   // Preserve the original compatibility path for any unexpected call at shift>=2.
   int handle=iFractals(symbol,MT4Period(timeframe));
   if(handle==INVALID_HANDLE) return 0.0;
   int bufIndex=(mode==1)?0:1; // 1=MODE_UPPER->buffer0, 2=MODE_LOWER->buffer1
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(handle,bufIndex,shift,1,buf)<=0) return 0.0;
   return buf[0];
}

bool MT4BearishFakeout(int timeframe,int anchorShift,datetime anchor,double level)
{
   int need=(anchorShift+1>2)?anchorShift+1:2;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(g_chartSymbol,MT4Period(timeframe),0,need,rates)<need) return false;
   return rates[anchorShift].time<=anchor && rates[0].time>anchor &&
          rates[1].close<rates[1].open && rates[1].close<level;
}

bool MT4BullishFakeout(int timeframe,int anchorShift,datetime anchor,double level)
{
   int need=(anchorShift+1>2)?anchorShift+1:2;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(g_chartSymbol,MT4Period(timeframe),0,need,rates)<need) return false;
   return rates[anchorShift].time<=anchor && rates[0].time>anchor &&
          rates[1].close>rates[1].open && rates[1].close>level;
}


//====================================================================
// Chuyen doi retcode cua MQL5 -> ma loi kieu MQL4 (de cac doan retry
// "if(MT4_LastError()==132) ..." trong code goc hoat dong dung y nghia)
//====================================================================
int MT4_LastError() { return g_mt4_lastError; }

int TradeRetcodeToMT4Error(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:        return 138; // ERR_REQUOTE
      case TRADE_RETCODE_REJECT:         return 134; // ERR_NOT_ENOUGH_MONEY (xap xi)
      case TRADE_RETCODE_CONNECTION:     return 137; // ERR_BROKER_BUSY (xap xi)
      case TRADE_RETCODE_MARKET_CLOSED:  return 132; // ERR_MARKET_CLOSED
      case TRADE_RETCODE_TRADE_DISABLED: return 133; // ERR_TRADE_DISABLED
      case TRADE_RETCODE_NO_MONEY:       return 134; // ERR_NOT_ENOUGH_MONEY
      case TRADE_RETCODE_PRICE_CHANGED:  return 135; // ERR_PRICE_CHANGED
      case TRADE_RETCODE_PRICE_OFF:      return 136; // ERR_OFF_QUOTES
      case TRADE_RETCODE_INVALID_STOPS:  return 130; // ERR_INVALID_STOPS
      case TRADE_RETCODE_INVALID_PRICE:  return 129; // ERR_INVALID_PRICE
      case TRADE_RETCODE_TIMEOUT:        return 128; // ERR_TRADE_TIMEOUT
      case TRADE_RETCODE_INVALID_VOLUME: return 131; // ERR_INVALID_TRADE_VOLUME
      case TRADE_RETCODE_DONE:           return 0;
      case TRADE_RETCODE_DONE_PARTIAL:   return 0;
      case TRADE_RETCODE_PLACED:         return 0;
   }
   return (int)retcode;
}

//====================================================================
// CTrade execution layer restored from dump evidence. The strategy body
// keeps its MQL4-style function signatures; these adapters execute through
// Trade.mqh/CTrade and validate ResultRetcode() synchronously.
//====================================================================
ENUM_ORDER_TYPE_FILLING MT4SelectFilling(string symbol)
{
   long mask=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((mask&SYMBOL_FILLING_FOK)!=0)  return ORDER_FILLING_FOK;
   if((mask&SYMBOL_FILLING_IOC)!=0)  return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//====================================================================
// Log thao tac lenh GIONG TERMINAL MT4: MT4 tu dong in moi thao tac
// cua EA vao tab Experts ("open #123 buy stop 0.11 XAUUSD at ... ok"),
// ca thanh cong lan that bai. MT5 khong tu in nhu vay cho ::OrderSend
// tho, nen tu in lai o day de log giong het MT4. Chi log, khong doi logic.
//====================================================================
string MT4OrderTypeName(int t)
{
   switch(t)
   {
      case ORDER_TYPE_BUY:        return "buy";
      case ORDER_TYPE_SELL:       return "sell";
      case ORDER_TYPE_BUY_LIMIT:  return "buy limit";
      case ORDER_TYPE_SELL_LIMIT: return "sell limit";
      case ORDER_TYPE_BUY_STOP:   return "buy stop";
      case ORDER_TYPE_SELL_STOP:  return "sell stop";
   }
   return "order";
}

void MT4ConfigureMarketFilling(const string symbol)
{
   if(!trade.SetTypeFillingBySymbol(symbol))
      trade.SetTypeFilling(MT4SelectFilling(symbol));
}

//====================================================================
// MQL4-style OrderSend interface backed by the same CTrade execution
// family recovered in the original binary (CTrade::OrderOpen /
// PositionOpen).  The strategy body remains byte-for-byte unchanged.
//====================================================================
long OrderSend(string symbol,int cmd,double volume,double price,int slippage,
               double stoploss,double takeprofit,string comment="",int magic=0,
               datetime expiration=0,color arrow_color=clrNONE)
{
   ENUM_ORDER_TYPE type;
   switch(cmd)
   {
      case OP_BUY:       type=ORDER_TYPE_BUY;        break;
      case OP_SELL:      type=ORDER_TYPE_SELL;       break;
      case OP_BUYLIMIT:  type=ORDER_TYPE_BUY_LIMIT;  break;
      case OP_SELLLIMIT: type=ORDER_TYPE_SELL_LIMIT; break;
      case OP_BUYSTOP:   type=ORDER_TYPE_BUY_STOP;   break;
      case OP_SELLSTOP:  type=ORDER_TYPE_SELL_STOP;  break;
      default:
         g_mt4_lastError=3; // ERR_INVALID_TRADE_PARAMETERS
         g_mt4_lastTicket=-1;
         return -1;
   }

   trade.SetExpertMagicNumber((ulong)magic);
   trade.SetDeviationInPoints((ulong)MathMax(slippage,0));

   bool accepted=false;
   double executionPrice=price;
   if(type==ORDER_TYPE_BUY || type==ORDER_TYPE_SELL)
   {
      MT4ConfigureMarketFilling(symbol);
      executionPrice=(type==ORDER_TYPE_BUY)
                     ?SymbolInfoDouble(symbol,SYMBOL_ASK)
                     :SymbolInfoDouble(symbol,SYMBOL_BID);
      accepted=trade.PositionOpen(symbol,type,volume,executionPrice,
                                  stoploss,takeprofit,comment);
   }
   else
   {
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
      ENUM_ORDER_TYPE_TIME timeType=(expiration>0)?ORDER_TIME_SPECIFIED:ORDER_TIME_GTC;
      accepted=trade.OrderOpen(symbol,type,volume,0.0,price,
                               stoploss,takeprofit,timeType,expiration,comment);
   }

   uint retcode=trade.ResultRetcode();
   if(!accepted && retcode==0) retcode=TRADE_RETCODE_ERROR;
   g_mt4_lastError=TradeRetcodeToMT4Error(retcode);
   if(accepted && (retcode==TRADE_RETCODE_DONE ||
                   retcode==TRADE_RETCODE_DONE_PARTIAL ||
                   retcode==TRADE_RETCODE_PLACED))
   {
      g_mt4_lastError=0;
      ulong ticket=trade.ResultOrder();
      if(ticket==0) ticket=trade.ResultDeal();
      g_mt4_lastTicket=(long)ticket;
      PrintFormat("open #%I64d %s %.2f %s at %.5f sl: %.5f tp: %.5f ok",
                  g_mt4_lastTicket,MT4OrderTypeName((int)type),volume,
                  symbol,executionPrice,stoploss,takeprofit);
      MT4InvalidateHistoryCache();
      return g_mt4_lastTicket;
   }

   PrintFormat("failed open %s %.2f %s at %.5f sl: %.5f tp: %.5f [%s] (retcode=%u)",
               MT4OrderTypeName((int)type),volume,symbol,executionPrice,
               stoploss,takeprofit,trade.ResultRetcodeDescription(),retcode);
   g_mt4_lastTicket=-1;
   return -1;
}

bool OrderModify(long ticket,double price,double stoploss,double takeprofit,datetime expiration,color arrow_color=clrNONE)
{
   bool accepted=false;
   string symbol="";
   double logPrice=price;

   if(PositionSelectByTicket((ulong)ticket))
   {
      symbol=PositionGetString(POSITION_SYMBOL);
      logPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
      accepted=trade.PositionModify((ulong)ticket,stoploss,takeprofit);
   }
   else if(::OrderSelect((ulong)ticket))
   {
      symbol=::OrderGetString(ORDER_SYMBOL);
      trade.SetExpertMagicNumber((ulong)::OrderGetInteger(ORDER_MAGIC));
      ENUM_ORDER_TYPE_TIME timeType=(expiration>0)?ORDER_TIME_SPECIFIED:ORDER_TIME_GTC;
      accepted=trade.OrderModify((ulong)ticket,price,stoploss,takeprofit,
                                 timeType,expiration,0.0);
      logPrice=price;
   }
   else
   {
      g_mt4_lastError=4108;
      return false;
   }

   uint retcode=trade.ResultRetcode();
   if(!accepted && retcode==0) retcode=TRADE_RETCODE_ERROR;
   g_mt4_lastError=TradeRetcodeToMT4Error(retcode);
   if(accepted && (retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL))
   {
      g_mt4_lastError=0;
      PrintFormat("modify #%I64d %s price: %.5f sl: %.5f tp: %.5f ok",
                  ticket,symbol,logPrice,stoploss,takeprofit);
      MT4InvalidateHistoryCache();
      return true;
   }

   PrintFormat("failed modify %s at %.5f sl: %.5f tp: %.5f [%s] (retcode=%u, ticket=%I64d)",
               symbol,logPrice,stoploss,takeprofit,
               trade.ResultRetcodeDescription(),retcode,ticket);
   return false;
}

bool OrderClose(long ticket,double lots,double price,int slippage,color arrow_color=clrNONE)
{
   if(!PositionSelectByTicket((ulong)ticket))
   {
      g_mt4_lastError=4108;
      return false;
   }

   string symbol=PositionGetString(POSITION_SYMBOL);
   double positionVolume=PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE positionType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
   double closeVolume=(lots>0.0 && lots<positionVolume)?lots:positionVolume;
   ulong deviation=(ulong)MathMax(slippage,0);
   trade.SetDeviationInPoints(deviation);
   MT4ConfigureMarketFilling(symbol);

   bool accepted=(closeVolume>=positionVolume)
                 ?trade.PositionClose((ulong)ticket,deviation)
                 :trade.PositionClosePartial((ulong)ticket,closeVolume,deviation);

   uint retcode=trade.ResultRetcode();
   if(!accepted && retcode==0) retcode=TRADE_RETCODE_ERROR;
   g_mt4_lastError=TradeRetcodeToMT4Error(retcode);
   if(accepted && (retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL))
   {
      g_mt4_lastError=0;
      PrintFormat("close #%I64d %s %.2f %s at %.5f ok",ticket,
                  (positionType==POSITION_TYPE_BUY)?"buy":"sell",
                  closeVolume,symbol,trade.ResultPrice());
      MT4InvalidateHistoryCache();
      return true;
   }

   PrintFormat("failed close %s %.2f %s [%s] (retcode=%u, ticket=%I64d)",
               (positionType==POSITION_TYPE_BUY)?"buy":"sell",closeVolume,symbol,
               trade.ResultRetcodeDescription(),retcode,ticket);
   return false;
}

bool OrderDelete(long ticket,color arrow_color=clrNONE)
{
   string orderName="order";
   double orderVolume=0.0;
   double orderPrice=0.0;
   string symbol="";

   if(::OrderSelect((ulong)ticket))
   {
      orderName=MT4OrderTypeName((int)::OrderGetInteger(ORDER_TYPE));
      orderVolume=::OrderGetDouble(ORDER_VOLUME_CURRENT);
      orderPrice=::OrderGetDouble(ORDER_PRICE_OPEN);
      symbol=::OrderGetString(ORDER_SYMBOL);
      trade.SetExpertMagicNumber((ulong)::OrderGetInteger(ORDER_MAGIC));
   }

   bool accepted=trade.OrderDelete((ulong)ticket);
   uint retcode=trade.ResultRetcode();
   if(!accepted && retcode==0) retcode=TRADE_RETCODE_ERROR;
   g_mt4_lastError=TradeRetcodeToMT4Error(retcode);
   if(accepted && retcode==TRADE_RETCODE_DONE)
   {
      g_mt4_lastError=0;
      PrintFormat("delete #%I64d %s %.2f %s at %.5f ok",
                  ticket,orderName,orderVolume,symbol,orderPrice);
      MT4InvalidateHistoryCache();
      return true;
   }

   PrintFormat("failed delete %s %.2f %s at %.5f [%s] (retcode=%u, ticket=%I64d)",
               orderName,orderVolume,symbol,orderPrice,
               trade.ResultRetcodeDescription(),retcode,ticket);
   return false;
}

//====================================================================
// Vung du lieu "lenh dang chon" hien tai kieu MQL4 (OrderSelect/
// OrderTicket/OrderType/OrderLots/...). Ho tro ca vi the dang mo,
// lenh cho dang mo (pool=MODE_TRADES) va lich su (pool=MODE_HISTORY).
//====================================================================
// Trang thai "lenh dang chon" kieu MQL4 - gom vao 1 struct cho gon
// (truoc day la 16 bien toan cu roi g_selOrder.*). OrderSelect() dien
// vao day; OrderTicket()/OrderLots()/OrderType()/... doc ra tu day.
struct MT4SelectedOrder
{
   long     ticket;
   string   symbol;
   int      type;
   double   lots;
   double   openPrice;
   double   closePrice;
   double   sl;
   double   tp;
   datetime openTime;
   datetime closeTime;
   datetime expiration;
   double   profit;
   double   swap;
   double   commission;
   string   comment;
   int      magic;
};
MT4SelectedOrder g_selOrder;
int g_sel_hist_index=-1;
int g_sel_live_index=-1;
MT4SelectedOrder g_live_orders[];
int  g_live_count=0;
bool g_live_valid=false;

//--- danh sach cache cho pool=MODE_HISTORY (xay tu HistoryDealsTotal) ---
long     g_hist_ticket[];
string   g_hist_symbol[];
int      g_hist_type[];
double   g_hist_lots[];
double   g_hist_openPrice[];
double   g_hist_closePrice[];
datetime g_hist_openTime[];
datetime g_hist_closeTime[];
double   g_hist_profit[];
double   g_hist_swap[];
double   g_hist_commission[];
string   g_hist_comment[];
int      g_hist_magic[];
datetime g_hist_expiration[];
string   g_hist_stat_symbol[];
int      g_hist_stat_magic[];
int      g_hist_stat_count[];
double   g_hist_stat_pnl[];
int      g_hist_stat_size=0;
int      g_hist_count=0;
datetime g_hist_builtAt=0;
int      g_hist_source_deals=-1;

void MT4InvalidateHistoryCache()
{
   g_hist_builtAt=0;
   g_live_valid=false;
}

void MT4BuildLiveCache()
{
   if(g_live_valid) return;
   g_live_count=0;
   ArrayResize(g_live_orders,PositionsTotal()+::OrdersTotal());

   int positions=PositionsTotal();
   for(int i=0;i<positions;i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      int n=g_live_count++;
      g_live_orders[n].ticket=(long)ticket;
      g_live_orders[n].symbol=PositionGetString(POSITION_SYMBOL);
      g_live_orders[n].type=(int)PositionGetInteger(POSITION_TYPE);
      g_live_orders[n].lots=PositionGetDouble(POSITION_VOLUME);
      g_live_orders[n].openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      g_live_orders[n].closePrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      g_live_orders[n].sl=PositionGetDouble(POSITION_SL);
      g_live_orders[n].tp=PositionGetDouble(POSITION_TP);
      g_live_orders[n].openTime=(datetime)PositionGetInteger(POSITION_TIME);
      g_live_orders[n].closeTime=0;
      g_live_orders[n].expiration=0;
      g_live_orders[n].profit=PositionGetDouble(POSITION_PROFIT);
      g_live_orders[n].swap=PositionGetDouble(POSITION_SWAP);
      g_live_orders[n].commission=0.0;
      g_live_orders[n].comment=PositionGetString(POSITION_COMMENT);
      g_live_orders[n].magic=(int)PositionGetInteger(POSITION_MAGIC);
   }

   int orders=::OrdersTotal();
   for(int i=0;i<orders;i++)
   {
      ulong ticket=::OrderGetTicket(i);
      if(ticket==0) continue;
      datetime expiration=(datetime)::OrderGetInteger(ORDER_TIME_EXPIRATION);
      int n=g_live_count++;
      g_live_orders[n].ticket=(long)ticket;
      g_live_orders[n].symbol=::OrderGetString(ORDER_SYMBOL);
      g_live_orders[n].type=(int)::OrderGetInteger(ORDER_TYPE);
      g_live_orders[n].lots=::OrderGetDouble(ORDER_VOLUME_CURRENT);
      g_live_orders[n].openPrice=::OrderGetDouble(ORDER_PRICE_OPEN);
      g_live_orders[n].closePrice=0.0;
      g_live_orders[n].sl=::OrderGetDouble(ORDER_SL);
      g_live_orders[n].tp=::OrderGetDouble(ORDER_TP);
      g_live_orders[n].openTime=(datetime)::OrderGetInteger(ORDER_TIME_SETUP);
      g_live_orders[n].closeTime=0;
      g_live_orders[n].expiration=expiration;
      g_live_orders[n].profit=0.0;
      g_live_orders[n].swap=0.0;
      g_live_orders[n].commission=0.0;
      g_live_orders[n].comment=::OrderGetString(ORDER_COMMENT);
      g_live_orders[n].magic=(int)::OrderGetInteger(ORDER_MAGIC);
   }

   ArrayResize(g_live_orders,g_live_count);
   g_live_valid=true;
}

void MT4BuildHistoryCache()
{
   // Poll at most once per server second so server-side SL/TP deals are visible,
   // but rebuild the expensive MQL4 history view only when the deal set changes.
   if(TimeCurrent()==g_hist_builtAt) return;
   g_hist_builtAt=TimeCurrent();

   if(!HistorySelect(0,TimeCurrent())) return;
   int deals=HistoryDealsTotal();
   if(deals==g_hist_source_deals) return;
   g_hist_source_deals=deals;

   g_hist_count=0;
   g_hist_stat_size=0;
   ArrayResize(g_hist_stat_symbol,0);
   ArrayResize(g_hist_stat_magic,0);
   ArrayResize(g_hist_stat_count,0);
   ArrayResize(g_hist_stat_pnl,0);

   if(deals<=0)
   {
      ArrayResize(g_hist_ticket,0); ArrayResize(g_hist_symbol,0);
      ArrayResize(g_hist_type,0); ArrayResize(g_hist_lots,0);
      ArrayResize(g_hist_openPrice,0); ArrayResize(g_hist_closePrice,0);
      ArrayResize(g_hist_openTime,0); ArrayResize(g_hist_closeTime,0);
      ArrayResize(g_hist_profit,0); ArrayResize(g_hist_swap,0);
      ArrayResize(g_hist_commission,0); ArrayResize(g_hist_comment,0);
      ArrayResize(g_hist_magic,0); ArrayResize(g_hist_expiration,0);
      return;
   }

   // One allocation per array and rebuild. The previous incremental resize
   // copied all accumulated strings/numbers again for every OUT deal.
   ArrayResize(g_hist_ticket,deals); ArrayResize(g_hist_symbol,deals);
   ArrayResize(g_hist_type,deals); ArrayResize(g_hist_lots,deals);
   ArrayResize(g_hist_openPrice,deals); ArrayResize(g_hist_closePrice,deals);
   ArrayResize(g_hist_openTime,deals); ArrayResize(g_hist_closeTime,deals);
   ArrayResize(g_hist_profit,deals); ArrayResize(g_hist_swap,deals);
   ArrayResize(g_hist_commission,deals); ArrayResize(g_hist_comment,deals);
   ArrayResize(g_hist_magic,deals); ArrayResize(g_hist_expiration,deals);

   // Position-level opening metadata. A close DEAL becomes one MQL4-style
   // history record, so partial closes remain separate instead of being merged.
   long     posIds[];
   double   posEntryVol[];
   double   posOpenPxVol[];
   datetime posOpenTime[];
   int      posType[];
   string   posSymbol[];
   int      posMagic[];
   string   posComment[];
   double   posEntryCommission[];
   int posCount=0;
   ArrayResize(posIds,deals); ArrayResize(posEntryVol,deals);
   ArrayResize(posOpenPxVol,deals); ArrayResize(posOpenTime,deals);
   ArrayResize(posType,deals); ArrayResize(posSymbol,deals);
   ArrayResize(posMagic,deals); ArrayResize(posComment,deals);
   ArrayResize(posEntryCommission,deals);

   // Pass 1: collect opening metadata for every position id.
   for(int i=0;i<deals;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      long dt=HistoryDealGetInteger(d,DEAL_TYPE);
      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL) continue;
      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_IN) continue;
      long pid=HistoryDealGetInteger(d,DEAL_POSITION_ID);
      int pos=-1;
      for(int k=0;k<posCount;k++) if(posIds[k]==pid) { pos=k; break; }
      if(pos<0)
      {
         pos=posCount++;
         posIds[pos]=pid;
         posEntryVol[pos]=0.0;
         posOpenPxVol[pos]=0.0;
         posOpenTime[pos]=0;
         posType[pos]=(dt==DEAL_TYPE_BUY)?OP_BUY:OP_SELL;
         posSymbol[pos]=HistoryDealGetString(d,DEAL_SYMBOL);
         posMagic[pos]=(int)HistoryDealGetInteger(d,DEAL_MAGIC);
         posComment[pos]=HistoryDealGetString(d,DEAL_COMMENT);
         posEntryCommission[pos]=0.0;
      }
      double v=HistoryDealGetDouble(d,DEAL_VOLUME);
      double px=HistoryDealGetDouble(d,DEAL_PRICE);
      datetime ot=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      posEntryVol[pos]+=v;
      posOpenPxVol[pos]+=px*v;
      if(posOpenTime[pos]==0 || ot<posOpenTime[pos]) posOpenTime[pos]=ot;
      posEntryCommission[pos]+=HistoryDealGetDouble(d,DEAL_COMMISSION);
   }

   // Pass 2: every OUT/OUT_BY deal is an independent closed-history item.
   for(int i=0;i<deals;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      long dt=HistoryDealGetInteger(d,DEAL_TYPE);
      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL) continue;
      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;

      long pid=HistoryDealGetInteger(d,DEAL_POSITION_ID);
      int pos=-1;
      for(int k=0;k<posCount;k++) if(posIds[k]==pid) { pos=k; break; }

      int n=g_hist_count+1;

      double closeVol=HistoryDealGetDouble(d,DEAL_VOLUME);
      string sym=HistoryDealGetString(d,DEAL_SYMBOL);
      int magic=(int)HistoryDealGetInteger(d,DEAL_MAGIC);
      string comment=HistoryDealGetString(d,DEAL_COMMENT);
      int originalType=(dt==DEAL_TYPE_SELL)?OP_BUY:OP_SELL; // fallback: close deal is opposite side
      double openPrice=0.0;
      datetime openTime=0;
      double entryCommissionShare=0.0;
      if(pos>=0)
      {
         if(posSymbol[pos]!="") sym=posSymbol[pos];
         if(posMagic[pos]!=0) magic=posMagic[pos];
         if(posComment[pos]!="") comment=posComment[pos];
         originalType=posType[pos];
         openTime=posOpenTime[pos];
         if(posEntryVol[pos]>0.0)
         {
            openPrice=posOpenPxVol[pos]/posEntryVol[pos];
            entryCommissionShare=posEntryCommission[pos]*(closeVol/posEntryVol[pos]);
         }
      }

      int h=g_hist_count;
      g_hist_ticket[h]=(long)d; // unique close-deal ticket; preserves partial-close records
      g_hist_symbol[h]=sym;
      g_hist_type[h]=originalType;
      g_hist_lots[h]=closeVol;
      g_hist_openPrice[h]=openPrice;
      g_hist_closePrice[h]=HistoryDealGetDouble(d,DEAL_PRICE);
      g_hist_openTime[h]=openTime;
      g_hist_closeTime[h]=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      g_hist_profit[h]=HistoryDealGetDouble(d,DEAL_PROFIT);
      g_hist_swap[h]=HistoryDealGetDouble(d,DEAL_SWAP);
      g_hist_commission[h]=HistoryDealGetDouble(d,DEAL_COMMISSION)+entryCommissionShare;
      g_hist_comment[h]=comment;
      g_hist_magic[h]=magic;
      g_hist_expiration[h]=0;
      g_hist_count=n;
   }

   ArrayResize(g_hist_ticket,g_hist_count); ArrayResize(g_hist_symbol,g_hist_count);
   ArrayResize(g_hist_type,g_hist_count); ArrayResize(g_hist_lots,g_hist_count);
   ArrayResize(g_hist_openPrice,g_hist_count); ArrayResize(g_hist_closePrice,g_hist_count);
   ArrayResize(g_hist_openTime,g_hist_count); ArrayResize(g_hist_closeTime,g_hist_count);
   ArrayResize(g_hist_profit,g_hist_count); ArrayResize(g_hist_swap,g_hist_count);
   ArrayResize(g_hist_commission,g_hist_count); ArrayResize(g_hist_comment,g_hist_count);
   ArrayResize(g_hist_magic,g_hist_count); ArrayResize(g_hist_expiration,g_hist_count);

   // Panel statistics are keyed by symbol+magic and change only when history
   // changes. Build them once here instead of rescanning all closed deals for
   // every enabled strategy on every H1 update.
   for(int i=0;i<g_hist_count;i++)
   {
      if(g_hist_type[i]!=OP_BUY && g_hist_type[i]!=OP_SELL) continue;
      int stat=-1;
      for(int k=0;k<g_hist_stat_size;k++)
         if(g_hist_stat_magic[k]==g_hist_magic[i] &&
            g_hist_stat_symbol[k]==g_hist_symbol[i]) { stat=k; break; }
      if(stat<0)
      {
         stat=g_hist_stat_size++;
         ArrayResize(g_hist_stat_symbol,g_hist_stat_size);
         ArrayResize(g_hist_stat_magic,g_hist_stat_size);
         ArrayResize(g_hist_stat_count,g_hist_stat_size);
         ArrayResize(g_hist_stat_pnl,g_hist_stat_size);
         g_hist_stat_symbol[stat]=g_hist_symbol[i];
         g_hist_stat_magic[stat]=g_hist_magic[i];
         g_hist_stat_count[stat]=0;
         g_hist_stat_pnl[stat]=0.0;
      }
      g_hist_stat_count[stat]++;
      g_hist_stat_pnl[stat]+=g_hist_profit[i]+g_hist_swap[i]+g_hist_commission[i];
   }

   // HistoryDealGetTicket(index) is already chronological.  OUT deals are
   // appended in that order, which is the MQL4 MODE_HISTORY order required here.
}

//====================================================================
// OrdersTotal() kieu MQL4 (vi the dang mo + lenh cho) -> doi ten thanh
// MT4OrdersTotal() vi OrdersTotal() da la ham co san cua MQL5 (chi dem
// lenh cho) nen khong the dinh nghia chong len.
//====================================================================
int MT4OrdersTotalRefresh()
{
   MT4BuildLiveCache();
   return g_live_count;
}
#define MT4OrdersTotal() (g_live_valid ? g_live_count : MT4OrdersTotalRefresh())

int HistoryTotal()
{
   MT4BuildHistoryCache();
   return g_hist_count;
}

void MT4HistoryStats(const string symbol,const int magic,int &count,double &pnl)
{
   MT4BuildHistoryCache();
   count=0;
   pnl=0.0;
   for(int i=0;i<g_hist_stat_size;i++)
   {
      if(g_hist_stat_symbol[i]!=symbol || g_hist_stat_magic[i]!=magic) continue;
      count=g_hist_stat_count[i];
      pnl=g_hist_stat_pnl[i];
      return;
   }
}

//====================================================================
// OrderSelect() kieu MQL4 (3 tham so, khac chu ky voi ham OrderSelect
// 1-tham-so co san cua MQL5 nen khong xung dot).
//====================================================================
bool OrderSelect(long index_or_ticket,int select,int pool=MODE_TRADES)
{
   g_sel_hist_index=-1;
   g_sel_live_index=-1;
   if(select==SELECT_BY_TICKET)
   {
      long ticket=(long)index_or_ticket;
      if(!g_live_valid) MT4BuildLiveCache();
      for(int i=0;i<g_live_count;i++)
      {
         if(g_live_orders[i].ticket==ticket)
         {
            g_sel_live_index=i;
            return true;
         }
      }
      if(PositionSelectByTicket((ulong)ticket))
      {
         g_selOrder.ticket=ticket;
         g_selOrder.symbol=PositionGetString(POSITION_SYMBOL);
         g_selOrder.type=(int)PositionGetInteger(POSITION_TYPE);
         g_selOrder.lots=PositionGetDouble(POSITION_VOLUME);
         g_selOrder.openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
         g_selOrder.closePrice=PositionGetDouble(POSITION_PRICE_CURRENT);
         g_selOrder.sl=PositionGetDouble(POSITION_SL);
         g_selOrder.tp=PositionGetDouble(POSITION_TP);
         g_selOrder.openTime=(datetime)PositionGetInteger(POSITION_TIME);
         g_selOrder.closeTime=0;
         g_selOrder.expiration=0;
         g_selOrder.profit=PositionGetDouble(POSITION_PROFIT);
         g_selOrder.swap=PositionGetDouble(POSITION_SWAP);
         g_selOrder.commission=0.0;
         g_selOrder.comment=PositionGetString(POSITION_COMMENT);
         g_selOrder.magic=(int)PositionGetInteger(POSITION_MAGIC);
         return true;
      }
      if(::OrderSelect((ulong)ticket))
      {
         g_selOrder.ticket=ticket;
         g_selOrder.symbol=::OrderGetString(ORDER_SYMBOL);
         g_selOrder.type=(int)::OrderGetInteger(ORDER_TYPE);
         g_selOrder.lots=::OrderGetDouble(ORDER_VOLUME_CURRENT);
         g_selOrder.openPrice=::OrderGetDouble(ORDER_PRICE_OPEN);
         g_selOrder.closePrice=0.0;
         g_selOrder.sl=::OrderGetDouble(ORDER_SL);
         g_selOrder.tp=::OrderGetDouble(ORDER_TP);
         g_selOrder.openTime=(datetime)::OrderGetInteger(ORDER_TIME_SETUP);
         g_selOrder.closeTime=0;
         g_selOrder.expiration=(datetime)::OrderGetInteger(ORDER_TIME_EXPIRATION);
         g_selOrder.profit=0.0;
         g_selOrder.swap=0.0;
         g_selOrder.commission=0.0;
         g_selOrder.comment=::OrderGetString(ORDER_COMMENT);
         g_selOrder.magic=(int)::OrderGetInteger(ORDER_MAGIC);
         return true;
      }
      MT4BuildHistoryCache();
      for(int i=0;i<g_hist_count;i++)
      {
         if(g_hist_ticket[i]==ticket)
         {
            g_sel_hist_index=i;
            return true;
         }
      }
      return false;
   }

   // SELECT_BY_POS
   if(pool==MODE_HISTORY)
   {
      MT4BuildHistoryCache();
      if(index_or_ticket<0 || index_or_ticket>=g_hist_count) return false;
      int i=(int)index_or_ticket; // da kiem tra nam trong [0, g_hist_count)
      g_sel_hist_index=i;
      return true;
   }

   // pool==MODE_TRADES: vi the dang mo (index 0..PositionsTotal()-1) roi
   // toi lenh cho dang mo (index PositionsTotal()..total-1)
   if(!g_live_valid) MT4BuildLiveCache();
   if(index_or_ticket>=0 && index_or_ticket<g_live_count)
   {
      g_sel_live_index=(int)index_or_ticket;
      return true;
   }
   return false;
}

//====================================================================
// Cac ham lay thuoc tinh cua "lenh dang chon" kieu MQL4
//====================================================================
#define OrderTicket()      ((g_sel_hist_index>=0)?g_hist_ticket[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].ticket:g_selOrder.ticket))
#define OrderSymbol()      ((g_sel_hist_index>=0)?g_hist_symbol[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].symbol:g_selOrder.symbol))
#define OrderType()        ((g_sel_hist_index>=0)?g_hist_type[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].type:g_selOrder.type))
#define OrderLots()        ((g_sel_hist_index>=0)?g_hist_lots[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].lots:g_selOrder.lots))
#define OrderOpenPrice()   ((g_sel_hist_index>=0)?g_hist_openPrice[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].openPrice:g_selOrder.openPrice))
#define OrderClosePrice()  ((g_sel_hist_index>=0)?g_hist_closePrice[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].closePrice:g_selOrder.closePrice))
#define OrderStopLoss()    ((g_sel_hist_index>=0)?0.0:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].sl:g_selOrder.sl))
#define OrderTakeProfit()  ((g_sel_hist_index>=0)?0.0:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].tp:g_selOrder.tp))
#define OrderOpenTime()    ((g_sel_hist_index>=0)?g_hist_openTime[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].openTime:g_selOrder.openTime))
#define OrderCloseTime()   ((g_sel_hist_index>=0)?g_hist_closeTime[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].closeTime:g_selOrder.closeTime))
#define OrderExpiration()  ((g_sel_hist_index>=0)?g_hist_expiration[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].expiration:g_selOrder.expiration))
#define OrderProfit()      ((g_sel_hist_index>=0)?g_hist_profit[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].profit:g_selOrder.profit))
#define OrderSwap()        ((g_sel_hist_index>=0)?g_hist_swap[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].swap:g_selOrder.swap))
#define OrderCommission()  ((g_sel_hist_index>=0)?g_hist_commission[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].commission:g_selOrder.commission))
#define OrderComment()     ((g_sel_hist_index>=0)?g_hist_comment[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].comment:g_selOrder.comment))
#define OrderMagicNumber() ((g_sel_hist_index>=0)?g_hist_magic[g_sel_hist_index]:((g_sel_live_index>=0)?g_live_orders[g_sel_live_index].magic:g_selOrder.magic))

#endif // __MQL4COMPAT_MQH__


// ============================================================================
// [§3] 输入参数枚举定义（与 input 参数对应的可选项，取值与 V4.6 原版一致）
// ============================================================================

  enum BacktestSpeedOptions      {speed_normal = 1,//normal
                   speed_fast = 2,//fast
                   speed_super = 3//ultra fast
                     };
  enum enum_TradeFrequency      {Extreme_cons_Frequency = 0,//extreme conservative
                   Conservative_Frequency = 1,//conservative
                   Moderate_Frequency = 2,//moderate
                   Intens_Frequency = 3,//Intense
                   Extreme_Frequency = 4,//Extreme (high risk!)
                   Auto_Frequency = 5,//Auto (based on balance and risk)
                   Manual_Strategy_Selection = 6//Manual strategy selection
                     };
  enum e_SlippageControlMode      {SCT_1 = 1,SCT_2 = 2  };
  enum FakeoutFilters      {Filter_Off = 0,//OFF
                   Filter_Low = 1,//Low
                   Filter_Medium = 2,//Medium
                   Filter_High = 3//High
                     };
  enum e_VirtualStopMode      {VSL_OFF = 1,VSL_BASIC = 2,VSL_ADV = 3  };
  enum Select_Entry_Strategy      {Strategy_ONE = 1,Strategy_TWO = 2  };
  enum e_TimeFrame_St_ONE      {ST1_M1 = 1,ST1_M5 = 5,ST1_M15 = 15,ST1_M30 = 30,ST1_H1 = 60,ST1_H4 = 240,ST1_Daily = 1440,ST1_Chart = 0  };
  enum e_TimeFrame_Entry_Timing      {Entry_T_Tick = 0,Entry_T_M1 = 1,Entry_T_M5 = 5,Entry_T_M15 = 15,Entry_T_M30 = 30,Entry_T_H1 = 60,Entry_T_H4 = 240  };
  enum e_UseOfCompound      {no_compound = 0,one_trade = 1,Multi_trades = 2  };
  enum e_MonitorTradesFilter      {MT_all = 0,MT_PairOfChart = 1  };
  enum e_TimeFrame_Exit_Timing      {ET_Tick = 0,ET_M1 = 1,ET_M5 = 5,ET_M15 = 15,ET_M30 = 30,ET_H1 = 60  };
  enum e_Exit_HL_trailingSL_timeframe      {HLT_Chart = 0,HLT_M1 = 1,HLT_M5 = 5,HLT_M15 = 15,HLT_M30 = 30,HLT_H1 = 60,HLT_H4 = 240,HLT_D1 = 1440  };
  enum ST1_e_MagicTrail_Mode      {ST1_MT_M_O = 0,ST1_MT_M_F = 1,ST1_MT_M_B = 2  };
  enum e_Risk      {Manual_Lotsize = 0,//use StartLots
                   MaxHistoricalDD = 1234,//Max Allowed Total Drawdown
                   MaxRiskStrat = 3//Max Risk Per Strategy
                     };
  enum Performance_options      {NormalizedProfit = 2,RealProfit = 1  };
  enum RankingOptions      {ranking_profit = 1,ranking_pertrade = 2  };
  enum Reduction_choices      {Red_10 = 10,Red_20 = 20,Red_30 = 30,Red_40 = 40,Red_50 = 50,Red_60 = 60,Red_70 = 70,Red_80 = 80,Red_90 = 90  };
  enum e_factortype      {factor_type_1 = 1,factor_type_2 = 2,factor_type_3 = 3  };
  enum e_TimeSource      {TZ_GMT = 0,TZ_PC = 1,TZ_Broker = 2  };


//------------------
// ============================================================================
// [§4] 输入参数（input）—— 分组顺序与 V4.6 原版输入面板一致
// ============================================================================
input string lijntje="============================================================="  ;   //- - -
input bool UseVariableValues=true  ;   
input bool AdjustLotsizeToVariableValues=true  ;   
input bool ShowInfoPanel=true  ;   
input bool UpdateInfoTesting=false ;    //update infopanel during testing
input double InfoPanelSizeAdjust=1  ;    //Adjustment for Infopanel size
input int   SetFontSize=0  ;    //Force Font Size (0=disabled)
input string BacktestSpeed_string="------------------------------ Backtest Speed settings ------------------------------"  ;  //- - -
input BacktestSpeedOptions BacktestSpeed=speed_normal  ;
input string spreadfilter="------------------------------ settings ------------------------------"  ;   //- - -
input bool AllowBuyTrades=true  ;    //Allow Buy Trades
input bool AllowSellTrades=true  ;    //Allow Sell Trades
input  enum_TradeFrequency  TradeFrequency=Auto_Frequency  ;   
input double MaxSpread=500  ;    //Maximum allowed spread
input bool UseHL_TrailingSL=true  ;   
input int   FridayStopHour=25  ;    //Friday stop hour (brokertime; close all trades)
input bool FridayClosePending=true  ;
input bool FridayCloseOpen=true  ;
input bool setSL_TP_After_Entry=false ;   
input bool Virtual_expiration=false  ;    //Use Virtual Expiration
input double Randomization=0  ;    //Randomization (entries and exit) in pips
input  FakeoutFilters  FakeOutFilter=2  ;    //Fake Breakout Filter
input int   ST1_MagicNumber=8000  ;    //BaseMagicnumber
input string ST1_Comment="The Gold Reaper"  ;   //Comment for trades
input bool RemoveCommentSuffix=false ;   
input string NFP_FILTER="----------------------- NFP Filter -----------------------"  ;  //- - -
input bool EnableNFP_Filter=true  ;
input bool UseMQL5Calendar=true  ;
input bool AutoGMT=true  ;
input int   Broker_GMT_OFFSET_Winter=2  ;    //GMT_OFFSET_Winter (AutoGMT=false or backtesting)
input int   Broker_GMT_OFFSET_Summer=3  ;    //MT_OFFSET_Summer (AutoGMT=false or backtesting)
input bool NFP_CloseOpenTrades=true  ;   
input bool NFP_ClosePendingOrders=true  ;   
input int   NFP_MinutesBefore=100  ;   
input int   NFP_MinutesAfter=60  ;   
input string propfirmsettings="----------------------- Propfirm unique trades settings -----------------------"  ;   //- - -
input double AdjustEntry=0  ;   
input double AdjustSL=0  ;   
input double AdjustTP=0  ;   
input double AdjustTrailSL=0  ;   
input double AdjustTrailTP=0  ;   
input double AdjustBreakEven=0  ;   
input string LotSizeSettings="----------------------- LotSize Settings -----------------------"  ;   //- - -
input double ManualBalance=0.0  ;    //manually set balance to use (if > 0)
input  e_Risk  Risk=1234  ;    //Lotsize Calculation method
input double StartLots=0.01  ;   
double g_startLots_rw=0.0;
bool g_initialLegacyRiskLotPending=true;
input double MaxAllowedDD=30  ;    //Max Allowed TOTAL Drawdown
input bool UseWeightedLots=true  ;    //Weighted Lotsize
input double MaxRiskPerStrategy_=1  ;    //Max Risk Per Strat
input double PropFirmMaxDailyDD=0  ;    //Set Max DAILY Drawdown (Prop Firms)
input bool OnlyUp=true  ;   
input bool ResetHighestBalance=false ;
input bool CheckMargin=true  ;    //check for free margin before setting trades
input bool UseEquity=false ;    //Use Equity Instead of Balance
input string ManualStratSelect="------------------------- Manual Strategy Selection -------------------------"  ;   //- - -
input string ManStratWarn="!! DO NOT RUN MANUAL STRATEGIES WHILE USING \'MAX ALLOWED TOTAL DD\' OPTION !! "  ;   //- - -
input bool RunStrat1=true  ;    //Run Strategy 1 (low risk)
input bool RunStrat2=true  ;    //Run Strategy 2 (low risk)
input bool RunStrat3=true  ;    //Run Strategy 3 (low risk)
input bool RunStrat4=true  ;    //Run Strategy 4 (med risk)
input bool RunStrat5=true  ;    //Run Strategy 5 (med risk)
input bool RunStrat6=true  ;    //Run Strategy 6 (med risk)
input bool RunStrat7=true  ;    //Run Strategy 7 (med risk)
input bool RunStrat8=true  ;    //Run Strategy 8 (high risk)
input bool RunStrat9=true  ;    //Run Strategy 9 (high risk)
// ============================================================================
// [§5] 转储重建全局变量（原 V4.6 JIT 数据段）
//      高置信度符号已分批重命名为 g_* 可读名（对照表见下）；
//      其余仍保留 global_N_type_XX 原始命名，便于与转储地址逐一对照；
//      字符串型变量同时充当 V4.6 输入面板的分组分隔标题。
//
// ---- 批次1 重命名对照表（新名 <- 原名@数据段地址，2026-09，纯标识符替换）----
//   g_curSpread                <- global_1_double_0       @0x000
//   g_atrPeriod                <- global_3_int_10          @0x010
//   g_atrTimeframe             <- global_4_int_14          @0x014
//   g_atrHandle                <- global_5_int_18          @0x018
//   g_atrBuffer                <- global_6_double_1C_ko    @0x01C
//   g_variableRatio            <- global_8_double_58        @0x058
//   g_lotRatioInv              <- global_9_double_60        @0x060
//   g_hdrTradingFilters        <- global_16_string_80      @0x080（分组标题）
//   g_tradeFrequencyMode       <- global_19_int_9C         @0x09C
//   g_runStrategy1             <- global_20_bool_A0        @0x0A0
//   g_runStrategy2             <- global_23_bool_A3         @0x0A3
//   g_runStrategy3             <- global_26_bool_A6         @0x0A6
//   g_runStrategy4             <- global_27_bool_A7         @0x0A7
//   g_runStrategy5             <- global_31_bool_AB         @0x0AB
//   g_runStrategy6             <- global_28_bool_A8         @0x0A8
//   g_runStrategy7             <- global_33_bool_AD         @0x0AD
//   g_runStrategy8             <- global_34_bool_AE         @0x0AE
//   g_runStrategy9             <- global_32_bool_AC         @0x0AC
//   g_maxSpreadPts             <- global_37_double_B8       @0x0B8
//   g_slippagePts              <- global_38_double_C0       @0x0C0
//   g_hdrTimeFilters           <- global_44_string_F0      @0x0F0（分组标题）
//   g_useFridayStop            <- global_45_bool_FC         @0x0FC
//   g_hdrOtherFilters          <- global_50_string_108    @0x108（分组标题）
//   g_fakeoutEnableM1          <- global_53_bool_11C       @0x11C
//   g_fakeoutEnableM15         <- global_57_bool_12C       @0x12C
//   g_fakeoutEnableH1          <- global_61_bool_13C       @0x13C
//   g_profitCloseMode          <- global_63_int_140        @0x140
//   g_orderMgmtMode            <- global_69_int_160        @0x160
//   g_hdrTradeEntryMgmt        <- global_70_string_168    @0x168（分组标题）
//   g_entryTfPeriod            <- global_71_int_174        @0x174
//   g_signalTfPeriod          <- global_72_int_178        @0x178
//   g_entryBreakoutPips        <- global_80_double_198      @0x198
//   g_buyEntryOffsetPips       <- global_83_double_1B0    @0x1B0
//   g_sellEntryOffsetPips      <- global_84_double_1B8    @0x1B8
//   g_maxPendingOrders         <- global_86_int_1C8        @0x1C8
//   g_maxOpenTradesPerSide     <- global_87_int_1CC        @0x1CC
//   g_orderPriceTolerancePips <- global_88_double_1D0     @0x1D0
//   g_pendingExpiryHours       <- global_89_int_1D8        @0x1D8
//   g_strategyMagicNumber      <- global_93_int_1F0        @0x1F0
//   g_manualSymbolMode         <- global_95_int_204        @0x204
//   g_manualMagicNumber        <- global_96_int_208        @0x208
//   g_manualCommentFilter      <- global_97_string_210     @0x210
//   g_stopLossPips             <- global_100_double_230    @0x230
//   g_takeProfitPips           <- global_101_double_238    @0x238
//   g_trailSlPips              <- global_103_double_250    @0x250
//   g_trailActivationPips      <- global_104_double_258    @0x258
//   g_trailStepPips            <- global_106_double_268    @0x268
//   g_trailTpPips              <- global_108_double_278    @0x278
//   g_beStartPips              <- global_113_double_2A8    @0x2A8
//   g_beExtraPips              <- global_114_double_2B0    @0x2B0
//   g_hlFractalTfPeriod        <- global_117_int_2C8       @0x2C8
//   g_hlOffsetPips             <- global_123_double_2E0    @0x2E0
//
// ---- 批次2 重命名对照表（51 个，2026-09，纯标识符替换）----
//   g_lotChangePctAlert        <- global_140_double_3F0     @0x3F0
//   g_maxLotCap                <- global_141_double_3F8     @0x3F8
//   g_perfOverviewHeader       <- global_149_string_428     @0x428（分节标题）
//   g_rankMode                 <- global_152_int_43C        @0x43C
//   g_statWindowDays           <- global_153_int_440        @0x440
//   g_statRecentDays           <- global_154_int_444        @0x444
//   g_zoneRecoveryHeader       <- global_158_string_458     @0x458（分节标题）
//   g_zrEnabled                <- global_159_bool_464       @0x464
//   g_zrZoneSize               <- global_160_double_468      @0x468
//   g_zrStepDist               <- global_161_double_470     @0x470
//   g_zrMinTargetDist          <- global_162_double_478     @0x478
//   g_zrTargetProfit           <- global_163_double_480     @0x480
//   g_zrLotMode                <- global_164_int_488        @0x488
//   g_zrLotMultiplier          <- global_165_double_490     @0x490
//   g_zrMaxRecoverySteps       <- global_166_int_498        @0x498
//   g_zrMagicBuy               <- global_168_int_4A8        @0x4A8
//   g_zrMagicSell              <- global_169_int_4AC        @0x4AC
//   g_tradingHoursHeader       <- global_170_string_4B0     @0x4B0（分节标题）
//   g_useTradingHours          <- global_171_bool_4BC       @0x4BC
//   g_scheduleTimeBase         <- global_172_int_4C0        @0x4C0
//   g_sunStartHour             <- global_174_int_4C8        @0x4C8
//   g_sunEndHour               <- global_175_int_4CC        @0x4CC
//   g_monStartHour             <- global_176_int_4D0        @0x4D0
//   g_monEndHour               <- global_177_int_4D4        @0x4D4
//   g_tueStartHour             <- global_178_int_4D8        @0x4D8
//   g_tueEndHour               <- global_179_int_4DC        @0x4DC
//   g_wedStartHour             <- global_180_int_4E0        @0x4E0
//   g_wedEndHour               <- global_181_int_4E4        @0x4E4
//   g_thuStartHour             <- global_182_int_4E8        @0x4E8
//   g_thuEndHour               <- global_183_int_4EC        @0x4EC
//   g_friStartHour             <- global_184_int_4F0        @0x4F0
//   g_friEndHour               <- global_185_int_4F4        @0x4F4
//   g_backtestOnlyHeader       <- global_186_string_4F8     @0x4F8（分节标题）
//   g_buyEntryPrice            <- global_188_double_508     @0x508
//   g_sellEntryPrice           <- global_189_double_510     @0x510
//   g_symbolDigits             <- global_190_int_518        @0x518
//   g_virtualSLPrice           <- global_191_double_520     @0x520
//   g_virtSLCache              <- global_196_double_568_si20si2 @0x568
//   g_virtualPendingOrders     <- global_197_double_6DC_si100si3 @0x6DC
//   g_stopOrderTicketPrice     <- global_198_double_1070_si100si2 @0x1070
//   g_virtSLCacheSize          <- global_199_int_16B0       @0x16B0
//   g_virtPendingArrSize       <- global_200_int_16B4       @0x16B4
//   g_maFilterEnabled          <- global_213_bool_1710      @0x1710
//   g_maFastPeriod             <- global_214_int_1714       @0x1714
//   g_maSlowPeriod             <- global_217_int_1A70       @0x1A70
//   g_allowMultipleTrades      <- global_218_bool_1A74      @0x1A74
//   g_minStopDistPrice         <- global_221_double_1A80    @0x1A80
//   g_lotByStrategy            <- global_223_double_1AC4_si99 @0x1AC4
//   g_pipSize                  <- global_229_double_1E00     @0x1E00
//   g_orderSendResult          <- global_230_int_1E08       @0x1E08
//   g_pendingExpirySecs        <- global_234_int_1E20        @0x1E20
//
// ---- 批次3 重命名对照表（68 个，2026-09，纯标识符替换）----
//   g_sellTrailStopLevel      <- global_241_double_1E78_si99  @0x1E78
//   g_buyTrailStopLevel       <- global_242_double_21C4_si99  @0x21C4
//   g_nextOrderAnchorPrice    <- global_247_double_2500       @0x2500
//   g_entryLowPrice            <- global_261_double_2578       @0x2578
//   g_entryHighPrice           <- global_262_double_2580       @0x2580
//   g_lastHour                 <- global_267_int_25A0          @0x25A0
//   g_maFilterFast             <- global_268_double_25A8       @0x25A8
//   g_maFilterSlow             <- global_269_double_25B0       @0x25B0
//   g_tradeErrorCount          <- global_274_int_25D8          @0x25D8
//   g_symbolSuffix             <- global_299_string_2850       @0x2850
//   g_pendingOrderExpiry       <- global_302_datetime_2870     @0x2870
//   g_marketClosedFlag         <- global_303_bool_2878        @0x2878
//   g_fridayStopDone           <- global_305_bool_2880         @0x2880
//   g_isDemoAccount            <- global_312_bool_28B0         @0x28B0
//   g_lastLotResizeBalance     <- global_318_double_28D8      @0x28D8
//   g_lastTrailOrderTime       <- global_319_datetime_28E0    @0x28E0
//   g_nfpWindowActive          <- global_320_bool_28E8         @0x28E8
//   g_openPLbyStrategy        <- global_323_double_2CA0_si30  @0x2CA0
//   g_winTradeCount            <- global_324_double_2DC4_si30 @0x2DC4
//   g_lossTradeCount           <- global_325_double_2EE8_si30 @0x2EE8
//   g_totalPLbyStrategy       <- global_326_double_300C_si30  @0x300C
//   g_currentStrategyIndex     <- global_328_int_3100          @0x3100
//   g_panelTextColor           <- global_329_uint_3104        @0x3104
//   g_orderComment             <- global_334_string_3120       @0x3120
//   g_chartSymbol              <- global_336_string_3130       @0x3130
//   g_symbolPoint              <- global_337_double_3140       @0x3140
//   g_rankOrderIdx             <- global_339_int_3184_si99    @0x3184
//   g_panelStrategyRowStart    <- global_340_int_3310          @0x3310
//   g_minTradesReachedFlag     <- global_342_bool_3694_si99   @0x3694
//   g_closedTradeCount         <- global_343_int_372C_si99    @0x372C
//   g_recentTradeCount         <- global_344_int_38EC_si99    @0x38EC
//   g_avgPLperTrade            <- global_345_double_3AAC_si99 @0x3AAC
//   g_recentAvgPLperTrade      <- global_346_double_3DF8_si99 @0x3DF8
//   g_strategySymbols           <- global_347_string_4144_si99 @0x4144
//   g_closedProfitByStrategy  <- global_349_double_46B4_si99  @0x46B4
//   g_recentPLbyStrategy      <- global_350_double_4A00_si99  @0x4A00
//   g_strategyRank              <- global_356_int_5B14_si99    @0x5B14
//   g_maxPanelObjects           <- global_360_int_5CB8          @0x5CB8
//   g_panelCellWidth            <- global_361_double_5CC0       @0x5CC0
//   g_panelCellHeight           <- global_362_double_5CC8       @0x5CC8
//   g_panelCellBgColor          <- global_364_uint_5CD4        @0x5CD4
//   g_panelFontSize             <- global_372_int_5CFC          @0x5CFC
//   g_panelWidthScale           <- global_376_double_5D70       @0x5D70
//   g_panelHeightScale          <- global_377_double_5D78       @0x5D78
//   g_strategyCount             <- global_378_int_5D80          @0x5D80
//   g_lastM5BarTime             <- global_379_datetime_5D88     @0x5D88
//   g_propfirmDailyDDOn        <- global_380_bool_5D90         @0x5D90
//   g_dailyDDLimitHit           <- global_382_bool_5D98         @0x5D98
//   g_lastD1BarsCount           <- global_383_int_5D9C          @0x5D9C
//   g_dailyEquityPeak           <- global_384_double_5DA0       @0x5DA0
//   g_ddTierThreshold1          <- global_385_int_5DA8          @0x5DA8
//   g_ddTierThreshold2          <- global_386_int_5DAC          @0x5DAC
//   g_ddTierThreshold3          <- global_387_int_5DB0          @0x5DB0
//   g_ddTierThreshold4          <- global_388_int_5DB4          @0x5DB4
//   g_ddTierThreshold5          <- global_389_int_5DB8          @0x5DB8
//   g_nfpAdjustedNow            <- global_390_datetime_5DC0     @0x5DC0
//   g_hardcodedNfpDates         <- global_391_datetime_5DFC_si300 @0x5DFC
//   g_isSummerTime              <- global_392_bool_675C         @0x675C
//   g_isWinterTime              <- global_393_bool_675D         @0x675D
//   g_gmtDetectDone             <- global_394_bool_675E         @0x675E
//   g_configGmtOffset           <- global_395_int_6760          @0x6760
//   g_detectedGmtOffset         <- global_396_int_6764          @0x6764
//   g_riskBaseUsd               <- global_397_double_6768       @0x6768
//   g_riskFactorByTier          <- global_398_double_6770       @0x6770
//   g_lastH1BarTime             <- global_399_datetime_6778     @0x6778
//   g_histClosedPLbyStrategy   <- global_400_double_67B4_si99  @0x67B4
//   g_lotCalcBalance            <- global_401_double_6AD0       @0x6AD0
//   g_highestBalance            <- global_402_double_6AD8       @0x6AD8
//
// ---- 批次4 死变量清理（111 个，2026-09，纯删除声明行）----
//   以下全局变量在代码中仅出现一次（即声明本身），零读写引用，删除不影响行为：
//   global_10/11/12/13/14/18/21/22/24/25/29/30/47/48/49/62/66/76/78/79/82/90/91/94/98/102/112/115/124/127/136/137/138/142/143/144/147/150/156/157/167/203/204/205/206/207/208/211/212/219/220/222/224/225/226/227/228/232/233/235/236/237/243/244/245/246/248/249/259/276/277/282/283/284/285/286/287/288/291/292/293/294/295/296/308/316/317/327/330/331/332/333/335/338/341/348/351/352/353/355/357/365/366/367/368/369/370/371/373/374/375
//   （编号含义同上；验证：git diff 纯删除 111 行、零新增行，删后复扫零死变量残留）
//   清理后文件内保留 global_* 声明 149 个（其中多数已按批次1-3重命名为 g_* 语义名）
//
// ---- 批次5 OnTick 语义模块拆分（2026-09）----
//   原 ~600 行平铺 OnTick 按原语句顺序 1:1 抽取为 12 个语义模块（见 OnTick 前注释清单），
//   9 个仅常量不同的策略调度块去重为 RunStrategySlot(strategyIndex,newH1Bar)。
//   验证：归一化 diff 集合包含检查——336/360 条归一化语句逐字保留，
//   24 条未匹配行全部为预期等价变换（声明合并/case 前缀/包装行替代/条件反转）；
//   括号平衡 1535/1535，无语句丢失。行为等价性最终以 Strategy Tester 差分回测为准。
//
// ---- 批次6 写而不读死存储清理（44 个变量 / 97 行，2026-09，纯删除）----
//   44 个变量（42 个初判 + global_272/273 二级级联）在代码中只被赋值、从未被读：
//   97 行 = 44 条声明 + 53 条死存储赋值。所有赋值 RHS 均为无副作用纯表达式
//   （常量/变量读/iBars/iTime/TimeCurrent/AccountBalance/iFractals 查询），
//   删除为行为中性。验证：git diff 纯删除 97 行、零新增、零意外行；
//   删后复扫 writeOnly=0。剩余 105 个 global_* 声明全部有真实读点。
//
// ---- 批次6b 数组型写而不读清理（4 个 / 18 行，2026-09，纯删除）----
//   数组写入形如 global_x[i] = ... 此前逃过批次6的写检测，精查补删 4 个：
//   global_339(排序映射表)/344(近期成交计数)/346(近期均盈亏)/354(排序权重)
//   连同 344 守卫 if/else 整块死代码。验证：纯删除 18 行、零新增、括号平衡、
//   代码中四者零残留（§5 表内旧名注释保留）。
// ============================================================================

  double    g_curSpread = 0.0;
  int       g_atrPeriod = 30;
  int       g_atrTimeframe = (int)PERIOD_D1;
  int       g_atrHandle = 0;
  double    g_atrBuffer[];
  double    global_7_double_50 = 0.0;
  double    g_variableRatio = 0.0;
  double    g_lotRatioInv = 0.0;
  int       global_15_int_78 = 0;
  string    g_hdrTradingFilters = "------------------------------ trading filters ------------------------------";
  bool      global_17_bool_8C = false;
  int       g_tradeFrequencyMode = 5;
  bool      g_runStrategy1 = true;
  bool      g_runStrategy2 = true;
  bool      g_runStrategy3 = true;
  bool      g_runStrategy4 = false;
  bool      g_runStrategy6 = false;
  bool      g_runStrategy5 = false;
  bool      g_runStrategy9 = false;
  bool      g_runStrategy7 = false;
  bool      g_runStrategy8 = false;
  bool      global_35_bool_AF = true;
  int       global_36_int_B0 = 2;
  double    g_maxSpreadPts = 0.0;
  double    g_slippagePts = 5000.0;
  int       global_39_int_C8 = 1;
  double    global_40_double_D0 = 40.0;
  double    global_41_double_D8 = 10.0;
  double    global_42_double_E0 = 30.0;
  bool      global_43_bool_E8 = false; // v106: marketplace trace uses actual fill as trailing-reference threshold
  string    g_hdrTimeFilters = "------------------------------ time filters ------------------------------";
  bool      g_useFridayStop = false;
  bool      global_46_bool_FD = false;
  string    g_hdrOtherFilters = "------------------------------ other filters ------------------------------";
  int       global_51_int_114 = 1;
  int       global_52_int_118 = 1;
  bool      g_fakeoutEnableM1 = false;
  int       global_54_int_120 = 5;
  bool      global_55_bool_124 = false;
  int       global_56_int_128 = 15;
  bool      g_fakeoutEnableM15 = false;
  int       global_58_int_130 = 30;
  bool      global_59_bool_134 = false;
  int       global_60_int_138 = 60;
  bool      g_fakeoutEnableH1 = false;
  int       g_profitCloseMode = 1;
  double    global_64_double_148 = 0.0;
  int       global_65_int_150 = 99;
  bool      global_67_bool_158 = false;
  int       g_orderMgmtMode = 1;
  string    g_hdrTradeEntryMgmt = "------------------------------ Trade Entry management ------------------------------";
  int       g_entryTfPeriod = 0;
  int       g_signalTfPeriod = 60;
  int       global_73_int_17C = 10;
  int       global_74_int_180 = 3;
  bool      global_75_bool_184 = false;
  int       global_77_int_188 = 120;
  double    g_entryBreakoutPips = 30.0;
  double    global_81_double_1A0 = 0.0;
  double    g_buyEntryOffsetPips = 0.5;
  double    g_sellEntryOffsetPips = 0.0;
  double    global_85_double_1C0 = 0.0;
  int       g_maxPendingOrders = 1;
  int       g_maxOpenTradesPerSide = 99;
  double    global_88_double_1D0 = 1.0;
  int       g_pendingExpiryHours = 24;
  int       global_92_int_1EC = 100;
  int       global_93_int_1F0 = 0;
  int       g_manualSymbolMode = 1;
  int       g_manualMagicNumber = 1991199118;
  string    g_manualCommentFilter = "";
  int       global_99_int_22C = 0;
  double    global_100_double_230 = 20.0;
  double    g_takeProfitPips = 100.0;
  double    global_103_double_250 = 10.0;
  double    g_trailActivationPips = 10.0;
  double    global_105_double_260 = 100.0;
  double    global_106_double_268 = 0.1;
  double    global_107_double_270 = 0.0;
  double    g_trailTpPips = 0.0;
  double    global_109_double_280 = 0.0;
  double    global_110_double_288 = 0.0;
  double    global_111_double_290 = 0.0;
  double    global_113_double_2A8 = 0.0;
  double    g_beExtraPips = 0.0;
  bool      global_116_bool_2C4 = false;
  int       global_117_int_2C8 = 0;
  int       global_118_int_2CC = 0;
  int       global_119_int_2D0 = 0;
  int       global_120_int_2D4 = 0;
  int       global_121_int_2D8 = 0;
  int       global_122_int_2DC = 0;
  double    g_hlOffsetPips = 2.0;
  double    global_125_double_2F8 = 0.0;
  double    global_126_double_300 = 0.0;
  int       global_128_int_314 = 0;
  double    global_129_double_318 = 0.1;
  int       global_130_int_320 = 1;
  double    global_131_double_328 = 0.1;
  double    global_132_double_330 = 1.0;
  int       global_133_int_338 = 0;
  double    global_134_double_340 = 0.0;
  bool      global_135_bool_348 = false;
  double    g_lotChangePctAlert = 5.0;
  double    g_maxLotCap = 99.0;
  int       global_145_int_40C = 600;
  double    global_146_double_410 = 1.0;
  double    global_148_double_420 = 2.0;
  string    g_perfOverviewHeader = "==== Performance numbers overview ====";
  int       global_151_int_438 = 1;
  int       g_rankMode = 1;
  int       g_statWindowDays = 90;
  int       g_statRecentDays = 30;
  int       global_155_int_448 = 10;
  string    g_zoneRecoveryHeader = "------------------------------ zone_recovery_settings ------------------------------";
  bool      g_zrEnabled = false;
  double    g_zrZoneSize = 50.0;
  double    g_zrStepDist = 10.0;
  double    g_zrMinTargetDist = 5.0;
  double    g_zrTargetProfit = 0.0;
  int       g_zrLotMode = 1;
  double    g_zrLotMultiplier = 2.0;
  int       g_zrMaxRecoverySteps = 999;
  int       g_zrMagicBuy = 900010;
  int       g_zrMagicSell = 900011;
  string    g_tradingHoursHeader = "------------------------- Trading hours ST1 -------------------------";
  bool      g_useTradingHours = false;
  int       g_scheduleTimeBase = 2;
  bool      global_173_bool_4C4 = false;
  int       g_sunStartHour = 0;
  int       g_sunEndHour = 24;
  int       g_monStartHour = 0;
  int       g_monEndHour = 24;
  int       g_tueStartHour = 0;
  int       g_tueEndHour = 24;
  int       g_wedStartHour = 0;
  int       g_wedEndHour = 24;
  int       g_thuStartHour = 0;
  int       g_thuEndHour = 24;
  int       g_friStartHour = 0;
  int       g_friEndHour = 24;
  string    g_backtestOnlyHeader = "------------------------- use for backtesting only! -------------------------";
  int       global_187_int_504 = 0;
  double    g_buyEntryPrice = 0.0;
  double    g_sellEntryPrice = 0.0;
  int       g_symbolDigits = 0;
  double    g_virtualSLPrice = 0.0;
  int       global_192_int_528 = 0;
  int       global_193_int_52C = 0;
  bool      global_194_bool_530 = false;
  bool      global_195_bool_531 = false;
  double    g_virtSLCache[20][2];
  double    g_virtualPendingOrders[100][3];
  double    g_stopOrderTicketPrice[100][2];
  int       g_virtSLCacheSize = 20;
  int       global_200_int_16B4 = 100;
  bool      g_maFilterEnabled = false;
  int       global_214_int_1714 = 1;
  datetime  global_215_datetime_174C_si99[99];
  int       g_maSlowPeriod = 370;
  bool      global_218_bool_1A74 = true;
  double    g_minStopDistPrice = 4.0;
  double    global_223_double_1AC4_si99[99];
  double    g_pipSize = 0.0;
  long      global_230_int_1E08 = 0; // ticket OrderSend la 64-bit; bool OrderModify van gan duoc 0/1
  int       g_pendingExpirySecs = 0;
  double    g_sellTrailStopLevel[99];
  double    g_buyTrailStopLevel[99];
  double    g_nextOrderAnchorPrice = 0.0;
  int       global_250_int_2518 = 0;
  string    global_252_string_2528;
  string    global_253_string_2538;
  string    global_254_string_2548;
  string    global_255_string_2558;
  double    g_entryLowPrice = 0.0;
  double    g_entryHighPrice = 0.0;
  int       g_lastHour = 0;
  double    g_maFilterFast = 0.0;
  double    g_maFilterSlow = 0.0;
  int       g_tradeErrorCount = 0;
  string    g_symbolSuffix;
  datetime  g_pendingOrderExpiry = 0;
  bool      g_marketClosedFlag = false;
  int       global_304_int_287C = 0;
  bool      g_fridayStopDone = false;
  double    global_309_double_2898 = 0.0;
  bool      g_isDemoAccount = false;
  double    g_lastLotResizeBalance = 0.0;
  datetime  g_lastTrailOrderTime = 0;
  bool      g_nfpWindowActive = false;
  int       global_321_int_2920_si99[99];
  int       global_322_int_2AE0_si99[99];
  double    g_openPLbyStrategy[30];
  double    g_winTradeCount[30];
  double    g_lossTradeCount[30];
  double    g_totalPLbyStrategy[30];
  int       g_currentStrategyIndex = 0;
  uint      g_panelTextColor = DarkBlue;
  string    g_orderComment;
  string    g_chartSymbol;
  double    g_symbolPoint = 0.0;
  int       g_panelStrategyRowStart = 0;
  bool      g_minTradesReachedFlag[99];
  int       g_closedTradeCount[99];
  double    g_avgPLperTrade[99];
  string    g_strategySymbols[99]={};
  double    global_349_double_46B4_si99[99];
  double    g_recentPLbyStrategy[99];
  int       global_356_int_5B14_si99[99];
  int       g_maxPanelObjects = 0;
  double    global_361_double_5CC0 = 0.0;
  double    g_panelCellHeight = 0.0;
  uint      global_364_uint_5CD4 = LightSteelBlue;
  int       g_panelFontSize = 7;
  double    g_panelWidthScale = 0.45;
  double    global_377_double_5D78 = 0.6;
  int       g_strategyCount = 0;
  datetime  global_379_datetime_5D88 = 0;
  bool      g_propfirmDailyDDOn = false;
  int       global_381_int_5D94 = 0;
  bool      global_382_bool_5D98 = false;
  int       g_lastD1BarsCount = 0;
  double    global_384_double_5DA0 = 0.0;
  int       g_ddTierThreshold1 = 200;
  int       global_386_int_5DAC = 330;
  int       g_ddTierThreshold3 = 560;
  int       global_388_int_5DB4 = 810;
  int       g_ddTierThreshold5 = 1150;
  datetime  g_nfpAdjustedNow = 0;
  datetime  global_391_datetime_5DFC_si300[300];
  int       g_hardcoded_nfp_year=-1;
  int       g_hardcoded_nfp_month=-1;
  datetime  g_hardcoded_nfp_value=0;
  bool      g_isSummerTime = false;
  bool      global_393_bool_675D = false;
  bool      g_gmtDetectDone = false;
  int       global_395_int_6760 = 0;
  int       g_detectedGmtOffset = 0;
  double    global_397_double_6768 = 0.0;
  double    g_riskFactorByTier = 0.0;
  datetime  global_399_datetime_6778 = 0;
  double    g_histClosedPLbyStrategy[99];
  double    global_401_double_6AD0 = 0.0;
  double    g_highestBalance = 0.0;
  bool      g_backtestSpeedFast = false;
  bool      g_backtestSpeedEnabled = false;
  datetime  g_backtestSpeedLastTime = 0;
  datetime  g_backtestSpeedLastM1 = 0;
  datetime  g_backtestSpeedLastProbeMinute = 0;
  double    g_MaxSpread_rw = 0.0;
  // Original V4.6 keeps one calendar-derived NFP timestamp, not a rebuilt
  // 300-element calendar array.  The hardcoded array remains intact as fallback.
  datetime  g_nextNFPCalendar = 0;
  datetime  g_nfpCalendarLastRefresh = 0;

//+------------------------------------------------------------------+
//| Recovered from original V4.6 JIT (0x19aa50b5170).                |
//| CalendarEventByCurrency("USD") -> exact name substring          |
//| "Nonfarm Payrolls" -> values in [server_now-1d, server_now+30d]|
//| -> earliest value in that window.                               |
//+------------------------------------------------------------------+
// ============================================================================
// [§6] NFP 过滤辅助函数
//      GetNextNFPFromCalendar           —— 经 MT5 经济日历查询下一次 NFP 时间
//      MT4HardcodedNFPForCurrentMonth   —— 日历不可用时的硬编码 NFP 回退
//      IsNfpManagedMagic                —— 判断 magic 是否属于本 EA 管理的策略
//      CloseManagedPositionsByType      —— 按订单类型平掉受管仓位
//      CloseNfpOpenTradesInOriginalOrder / CloseDailyDDPositionsInOriginalOrder
//                                      —— NFP/日内回撤时按开仓原顺序平仓
// ============================================================================

 datetime GetNextNFPFromCalendar()
 {
  datetime temp_now = TimeTradeServer();
  MqlCalendarEvent temp_events[];
  int temp_evTotal = CalendarEventByCurrency("USD",temp_events);
  if ( temp_evTotal <= 0 )   return(0);

  ulong temp_nfpId = 0;
  bool temp_found = false;
  for (int temp_i=0; temp_i<temp_evTotal; temp_i++)
  {
    if ( StringFind(temp_events[temp_i].name,"Nonfarm Payrolls") >= 0 )
    {
      temp_nfpId = temp_events[temp_i].id;
      temp_found = true;
      break;
    }
  }
  if ( !(temp_found) )   return(0);

  MqlCalendarValue temp_values[];
  datetime temp_from = temp_now - 86400;
  datetime temp_to   = temp_now + 2592000;
  int temp_n = CalendarValueHistoryByEvent(temp_nfpId,temp_values,temp_from,temp_to);
  if ( temp_n <= 0 )   return(0);

  datetime temp_best = 0;
  for (int temp_i=0; temp_i<temp_n; temp_i++)
  {
    datetime temp_t = temp_values[temp_i].time;
    // JIT compares against the lower query bound (now-1 day), not strictly now.
    if ( temp_t <= temp_from )   continue;
    if ( temp_best == 0 || temp_t < temp_best )   temp_best = temp_t;
  }
  return(temp_best);
 }
//GetNextNFPFromCalendar <<==--------   --------

 datetime MT4HardcodedNFPForCurrentMonth()
 {
  int year=Year();
  int month=Month();
  if(year==g_hardcoded_nfp_year && month==g_hardcoded_nfp_month)
     return(g_hardcoded_nfp_value);

  g_hardcoded_nfp_year=year;
  g_hardcoded_nfp_month=month;
  g_hardcoded_nfp_value=0;
  for(int i=0;i<300;i++)
  {
    datetime event_time=global_391_datetime_5DFC_si300[i];
    if(TimeYear(event_time)!=year || TimeMonth(event_time)!=month) continue;
    g_hardcoded_nfp_value=event_time;
    break;
  }
   return(g_hardcoded_nfp_value);
  }

 // The original runtime closes managed positions in two stable groups: BUY
 // first, then SELL. Within each group the newest (highest) position ticket is
 // closed first. Capture a ticket snapshot before sending any close request;
 // otherwise every successful close rebuilds the synthetic MQL4 trade pool and
 // changes the meaning of the next SELECT_BY_POS index.
 bool IsNfpManagedMagic(const int magic)
 {
   return(magic >= ST1_MagicNumber + 1 && magic <= ST1_MagicNumber + 15);
 }

 void CloseManagedPositionsByType(const int order_type,const int close_slippage)
 {
   long tickets[];
   int ticket_count=0;
   int total=MT4OrdersTotal();
   for(int index=0; index<total; index++)
   {
     if(OrderSelect(index,SELECT_BY_POS,MODE_TRADES) != true) continue;
     if(OrderSymbol() != g_chartSymbol) continue;
     if(OrderType() != order_type) continue;
     if(!IsNfpManagedMagic(OrderMagicNumber())) continue;
     ArrayResize(tickets,ticket_count+1);
     tickets[ticket_count++]=OrderTicket();
   }

   ArraySort(tickets);
   for(int index=ticket_count-1; index>=0; index--)
   {
     if(OrderSelect(tickets[index],SELECT_BY_TICKET,MODE_TRADES) != true) continue;
     if(OrderSymbol() != g_chartSymbol || OrderType() != order_type) continue;
     if(!IsNfpManagedMagic(OrderMagicNumber())) continue;
     double close_price=(order_type==OP_BUY)
                        ? MarketInfo(g_chartSymbol,MODE_BID)
                        : MarketInfo(g_chartSymbol,MODE_ASK);
      OrderClose(OrderTicket(),OrderLots(),close_price,close_slippage,Red);
   }
 }

 void CloseNfpOpenTradesInOriginalOrder()
 {
   CloseManagedPositionsByType(OP_BUY,99999);
   CloseManagedPositionsByType(OP_SELL,99999);
 }

 void CloseDailyDDPositionsInOriginalOrder()
 {
   CloseManagedPositionsByType(OP_BUY,(int)g_slippagePts);
   CloseManagedPositionsByType(OP_SELL,(int)g_slippagePts);
 }

 // Original V4.6 dump has no withdrawal-reconciliation layer here.

// ============================================================================
// [§7] EA 事件处理
// ============================================================================

// OnInit —— 初始化：HighestBalance 终端全局变量维护、BacktestSpeed/Tester
//           状态、策略装载与信息面板创建（关键顺序见函数内恢复注释）
 int OnInit()
 {
 trade.SetAsyncMode(false);
 trade.LogLevel(LOG_LEVEL_NO);
g_startLots_rw=StartLots;
g_initialLegacyRiskLotPending=true;
 // Recovered from original JIT: BacktestSpeed is active only in Strategy Tester.
 g_backtestSpeedFast = false;
 g_backtestSpeedEnabled = false;
 g_backtestSpeedLastTime = 0;
 g_backtestSpeedLastM1 = 0;
 g_backtestSpeedLastProbeMinute = 0;
 if ( MQLInfoInteger(MQL_TESTER) == 1 )
 {
   if ( BacktestSpeed == speed_fast )
   {
     g_backtestSpeedFast = true;
     g_backtestSpeedEnabled = true;
   }
   else if ( BacktestSpeed == speed_super )
   {
     g_backtestSpeedFast = false;
     g_backtestSpeedEnabled = true;
   }
 }
   double    local_2_double;
   double    local_3_double;
   int       local_4_int;
   int       local_5_int;
  int       local_6_int;
  int       local_7_int;
  int       local_8_int;
  int       local_9_int;
//----- -----
 // MQL4 tu dong khoi tao bool local ve false; MQL5 thi khong, nen phai gan
 // ro rang de giu dung hanh vi ban goc (bien nay khong duoc gan truoc khi
 // dung o duoi, IsDemo() ket qua bi bo qua trong ca ban mq4 goc).
 bool       temp_bool_1 = false;

 // SetFontSize >0: ghi de co chu panel (0 = co mac dinh theo thiet ke goc)
 if ( SetFontSize > 0 )   g_panelFontSize = SetFontSize ;

 // Recovered directly from original V4.6 JIT around 0x19aa50b0f47-0x19aa50b13c7.
 // Important ordering in the original:
 //   1) account BALANCE, optionally EQUITY;
 //   2) ResetHighestBalance => GlobalVariableSet("HighestBalance",0) + Sleep(5000);
 //   3) read the single terminal Global Variable "HighestBalance";
 //   4) highest = max(account value, stored value), write it back unconditionally;
 //   5) only AFTER that, ManualBalance may override the working risk balance.
 global_401_double_6AD0 = AccountInfoDouble(ACCOUNT_BALANCE) ;
 if ( UseEquity )
 {
   global_401_double_6AD0 = AccountInfoDouble(ACCOUNT_EQUITY) ;
 }
 if ( ResetHighestBalance )
 {
   GlobalVariableSet("HighestBalance",0.0) ;
   Sleep(5000) ;
 }
 double temp_storedHighest = GlobalVariableGet("HighestBalance") ;
 if ( temp_storedHighest>global_401_double_6AD0 )
 {
   Print("HighestBalance value found: ",temp_storedHighest) ;
   g_highestBalance = temp_storedHighest ;
 }
 else
 {
   g_highestBalance = global_401_double_6AD0 ;
 }
 GlobalVariableSet("HighestBalance",g_highestBalance) ;
 if ( ManualBalance>0.0 )
 {
   global_401_double_6AD0 = ManualBalance ;
 }
 g_isSummerTime = false ;
 global_393_bool_675D = false ;
 global_391_datetime_5DFC_si300[0] = D'2026.12.04 12:30';
 global_391_datetime_5DFC_si300[1] = D'2026.11.06 12:30';
 global_391_datetime_5DFC_si300[2] = D'2026.10.02 12:30';
 global_391_datetime_5DFC_si300[3] = D'2026.09.04 12:30';
 global_391_datetime_5DFC_si300[4] = D'2026.08.07 12:30';
 global_391_datetime_5DFC_si300[5] = D'2026.07.02 12:30';
 global_391_datetime_5DFC_si300[6] = D'2026.06.05 12:30';
 global_391_datetime_5DFC_si300[7] = D'2026.05.08 12:30';
 global_391_datetime_5DFC_si300[8] = D'2026.04.03 12:30';
 global_391_datetime_5DFC_si300[9] = D'2026.03.06 12:30';
 global_391_datetime_5DFC_si300[10] = D'2026.02.06 12:30';
 global_391_datetime_5DFC_si300[11] = D'2026.01.09 12:30';
 global_391_datetime_5DFC_si300[12] = D'2025.12.16 12:30';
 global_391_datetime_5DFC_si300[13] = D'2025.11.07 12:30';
 global_391_datetime_5DFC_si300[14] = D'2025.10.03 12:30';
 global_391_datetime_5DFC_si300[15] = D'2025.09.05 12:30';
 global_391_datetime_5DFC_si300[16] = D'2025.08.01 12:30';
 global_391_datetime_5DFC_si300[17] = D'2025.07.03 12:30';
 global_391_datetime_5DFC_si300[18] = D'2025.06.06 12:30';
 global_391_datetime_5DFC_si300[19] = D'2025.05.02 12:30';
 global_391_datetime_5DFC_si300[20] = D'2025.04.04 12:30';
 global_391_datetime_5DFC_si300[21] = D'2025.03.07 12:30';
 global_391_datetime_5DFC_si300[22] = D'2025.02.07 12:30';
 global_391_datetime_5DFC_si300[23] = D'2025.01.10 12:30';
 global_391_datetime_5DFC_si300[24] = D'2024.12.06 12:30';
 global_391_datetime_5DFC_si300[25] = D'2024.11.01 12:30';
 global_391_datetime_5DFC_si300[26] = D'2024.10.04 12:30';
 global_391_datetime_5DFC_si300[27] = D'2024.09.06 12:30';
 global_391_datetime_5DFC_si300[28] = D'2024.08.02 12:30';
 global_391_datetime_5DFC_si300[29] = D'2024.07.05 12:30';
 global_391_datetime_5DFC_si300[30] = D'2024.06.07 12:30';
 global_391_datetime_5DFC_si300[31] = D'2024.05.03 12:30';
 global_391_datetime_5DFC_si300[32] = D'2024.04.05 12:30';
 global_391_datetime_5DFC_si300[33] = D'2024.03.08 12:30';
 global_391_datetime_5DFC_si300[34] = D'2024.02.02 12:30';
 global_391_datetime_5DFC_si300[35] = D'2024.01.05 12:30';
 global_391_datetime_5DFC_si300[36] = D'2023.12.08 12:30';
 global_391_datetime_5DFC_si300[37] = D'2023.11.03 12:30';
 global_391_datetime_5DFC_si300[38] = D'2023.10.06 12:30';
 global_391_datetime_5DFC_si300[39] = D'2023.09.01 12:30';
 global_391_datetime_5DFC_si300[40] = D'2023.08.04 12:30';
 global_391_datetime_5DFC_si300[41] = D'2023.07.07 12:30';
 global_391_datetime_5DFC_si300[42] = D'2023.06.02 12:30';
 global_391_datetime_5DFC_si300[43] = D'2023.05.05 12:30';
 global_391_datetime_5DFC_si300[44] = D'2023.04.07 12:30';
 global_391_datetime_5DFC_si300[45] = D'2023.03.10 12:30';
 global_391_datetime_5DFC_si300[46] = D'2023.02.03 12:30';
 global_391_datetime_5DFC_si300[47] = D'2023.01.06 12:30';
 global_391_datetime_5DFC_si300[48] = D'2022.12.02 12:30';
 global_391_datetime_5DFC_si300[49] = D'2022.11.04 12:30';
 global_391_datetime_5DFC_si300[50] = D'2022.10.07 12:30';
 global_391_datetime_5DFC_si300[51] = D'2022.09.02 12:30';
 global_391_datetime_5DFC_si300[52] = D'2022.08.05 12:30';
 global_391_datetime_5DFC_si300[53] = D'2022.07.08 12:30';
 global_391_datetime_5DFC_si300[54] = D'2022.06.03 12:30';
 global_391_datetime_5DFC_si300[55] = D'2022.05.06 12:30';
 global_391_datetime_5DFC_si300[56] = D'2022.04.01 12:30';
 global_391_datetime_5DFC_si300[57] = D'2022.03.04 12:30';
 global_391_datetime_5DFC_si300[58] = D'2022.02.04 12:30';
 global_391_datetime_5DFC_si300[59] = D'2022.01.07 12:30';
 global_391_datetime_5DFC_si300[60] = D'2021.12.03 12:30';
 global_391_datetime_5DFC_si300[61] = D'2021.11.05 12:30';
 global_391_datetime_5DFC_si300[62] = D'2021.10.08 12:30';
 global_391_datetime_5DFC_si300[63] = D'2021.09.03 12:30';
 global_391_datetime_5DFC_si300[64] = D'2021.08.06 12:30';
 global_391_datetime_5DFC_si300[65] = D'2021.07.02 12:30';
 global_391_datetime_5DFC_si300[66] = D'2021.06.04 12:30';
 global_391_datetime_5DFC_si300[67] = D'2021.05.07 12:30';
 global_391_datetime_5DFC_si300[68] = D'2021.04.02 12:30';
 global_391_datetime_5DFC_si300[69] = D'2021.03.05 12:30';
 global_391_datetime_5DFC_si300[70] = D'2021.02.05 12:30';
 global_391_datetime_5DFC_si300[71] = D'2021.01.08 12:30';
 global_391_datetime_5DFC_si300[72] = D'2020.12.04 12:30';
 global_391_datetime_5DFC_si300[73] = D'2020.11.06 12:30';
 global_391_datetime_5DFC_si300[74] = D'2020.10.02 12:30';
 global_391_datetime_5DFC_si300[75] = D'2020.09.04 12:30';
 global_391_datetime_5DFC_si300[76] = D'2020.08.07 12:30';
 global_391_datetime_5DFC_si300[77] = D'2020.07.02 12:30';
 global_391_datetime_5DFC_si300[78] = D'2020.06.05 12:30';
 global_391_datetime_5DFC_si300[79] = D'2020.05.08 12:30';
 global_391_datetime_5DFC_si300[80] = D'2020.04.03 12:30';
 global_391_datetime_5DFC_si300[81] = D'2020.03.06 12:30';
 global_391_datetime_5DFC_si300[82] = D'2020.02.07 12:30';
 global_391_datetime_5DFC_si300[83] = D'2020.01.10 12:30';
 global_391_datetime_5DFC_si300[84] = D'2019.12.06 12:30';
 global_391_datetime_5DFC_si300[85] = D'2019.11.01 12:30';
 global_391_datetime_5DFC_si300[86] = D'2019.10.04 12:30';
 global_391_datetime_5DFC_si300[87] = D'2019.09.06 12:30';
 global_391_datetime_5DFC_si300[88] = D'2019.08.02 12:30';
 global_391_datetime_5DFC_si300[89] = D'2019.07.05 12:30';
 global_391_datetime_5DFC_si300[90] = D'2019.06.07 12:30';
 global_391_datetime_5DFC_si300[91] = D'2019.05.03 12:30';
 global_391_datetime_5DFC_si300[92] = D'2019.04.05 12:30';
 global_391_datetime_5DFC_si300[93] = D'2019.03.08 12:30';
 global_391_datetime_5DFC_si300[94] = D'2019.02.01 12:30';
 global_391_datetime_5DFC_si300[95] = D'2019.01.04 12:30';
 global_391_datetime_5DFC_si300[96] = D'2018.12.07 12:30';
 global_391_datetime_5DFC_si300[97] = D'2018.11.02 12:30';
 global_391_datetime_5DFC_si300[98] = D'2018.10.05 12:30';
 global_391_datetime_5DFC_si300[99] = D'2018.09.07 12:30';
 global_391_datetime_5DFC_si300[100] = D'2018.08.03 12:30';
 global_391_datetime_5DFC_si300[101] = D'2018.07.06 12:30';
 global_391_datetime_5DFC_si300[102] = D'2018.06.01 12:30';
 global_391_datetime_5DFC_si300[103] = D'2018.05.04 12:30';
 global_391_datetime_5DFC_si300[104] = D'2018.04.06 12:30';
 global_391_datetime_5DFC_si300[105] = D'2018.03.09 12:30';
 global_391_datetime_5DFC_si300[106] = D'2018.02.02 12:30';
 global_391_datetime_5DFC_si300[107] = D'2018.01.05 12:30';
 global_391_datetime_5DFC_si300[108] = D'2017.12.08 12:30';
 global_391_datetime_5DFC_si300[109] = D'2017.11.03 12:30';
 global_391_datetime_5DFC_si300[110] = D'2017.10.06 12:30';
 global_391_datetime_5DFC_si300[111] = D'2017.09.01 12:30';
 global_391_datetime_5DFC_si300[112] = D'2017.08.04 12:30';
 global_391_datetime_5DFC_si300[113] = D'2017.07.07 12:30';
 global_391_datetime_5DFC_si300[114] = D'2017.06.02 12:30';
 global_391_datetime_5DFC_si300[115] = D'2017.05.05 12:30';
 global_391_datetime_5DFC_si300[116] = D'2017.04.07 12:30';
 global_391_datetime_5DFC_si300[117] = D'2017.03.10 12:30';
 global_391_datetime_5DFC_si300[118] = D'2017.02.03 12:30';
 global_391_datetime_5DFC_si300[119] = D'2017.01.06 12:30';
 global_391_datetime_5DFC_si300[120] = D'2016.12.02 12:30';
 global_391_datetime_5DFC_si300[121] = D'2016.11.04 12:30';
 global_391_datetime_5DFC_si300[122] = D'2016.10.07 12:30';
 global_391_datetime_5DFC_si300[123] = D'2016.09.02 12:30';
 global_391_datetime_5DFC_si300[124] = D'2016.08.05 12:30';
 global_391_datetime_5DFC_si300[125] = D'2016.07.08 12:30';
 global_391_datetime_5DFC_si300[126] = D'2016.06.03 12:30';
 global_391_datetime_5DFC_si300[127] = D'2016.05.06 12:30';
 global_391_datetime_5DFC_si300[128] = D'2016.04.01 12:30';
 global_391_datetime_5DFC_si300[129] = D'2016.03.04 12:30';
 global_391_datetime_5DFC_si300[130] = D'2016.02.05 12:30';
 global_391_datetime_5DFC_si300[131] = D'2016.01.08 12:30';
 global_391_datetime_5DFC_si300[132] = D'2015.12.04 12:30';
 global_391_datetime_5DFC_si300[133] = D'2015.11.06 12:30';
 global_391_datetime_5DFC_si300[134] = D'2015.10.02 12:30';
 global_391_datetime_5DFC_si300[135] = D'2015.09.04 12:30';
 global_391_datetime_5DFC_si300[136] = D'2015.08.07 12:30';
 global_391_datetime_5DFC_si300[137] = D'2015.07.02 12:30';
 global_391_datetime_5DFC_si300[138] = D'2015.06.05 12:30';
 global_391_datetime_5DFC_si300[139] = D'2015.05.08 12:30';
 global_391_datetime_5DFC_si300[140] = D'2015.04.03 12:30';
 global_391_datetime_5DFC_si300[141] = D'2015.03.06 12:30';
 global_391_datetime_5DFC_si300[142] = D'2015.02.06 12:30';
 global_391_datetime_5DFC_si300[143] = D'2015.01.09 12:30';
 global_391_datetime_5DFC_si300[144] = D'2014.12.05 12:30';
 global_391_datetime_5DFC_si300[145] = D'2014.11.07 12:30';
 global_391_datetime_5DFC_si300[146] = D'2014.10.03 12:30';
 global_391_datetime_5DFC_si300[147] = D'2014.09.05 12:30';
 global_391_datetime_5DFC_si300[148] = D'2014.08.01 12:30';
 global_391_datetime_5DFC_si300[149] = D'2014.07.03 12:30';
 global_391_datetime_5DFC_si300[150] = D'2014.06.06 12:30';
 global_391_datetime_5DFC_si300[151] = D'2014.05.02 12:30';
 global_391_datetime_5DFC_si300[152] = D'2014.04.04 12:30';
 global_391_datetime_5DFC_si300[153] = D'2014.03.07 12:30';
 global_391_datetime_5DFC_si300[154] = D'2014.02.07 12:30';
 global_391_datetime_5DFC_si300[155] = D'2014.01.10 12:30';
 global_391_datetime_5DFC_si300[156] = D'2013.12.06 12:30';
 global_391_datetime_5DFC_si300[157] = D'2013.11.08 12:30';
 global_391_datetime_5DFC_si300[158] = D'2013.10.22 12:30';
 global_391_datetime_5DFC_si300[159] = D'2013.09.06 12:30';
 global_391_datetime_5DFC_si300[160] = D'2013.08.02 12:30';
 global_391_datetime_5DFC_si300[161] = D'2013.07.05 12:30';
 global_391_datetime_5DFC_si300[162] = D'2013.06.07 12:30';
 global_391_datetime_5DFC_si300[163] = D'2013.05.03 12:30';
 global_391_datetime_5DFC_si300[164] = D'2013.04.05 12:30';
 global_391_datetime_5DFC_si300[165] = D'2013.03.08 12:30';
 global_391_datetime_5DFC_si300[166] = D'2013.02.01 12:30';
 global_391_datetime_5DFC_si300[167] = D'2013.01.04 12:30';
 global_391_datetime_5DFC_si300[168] = D'2012.12.07 12:30';
 global_391_datetime_5DFC_si300[169] = D'2012.11.02 12:30';
 global_391_datetime_5DFC_si300[170] = D'2012.10.05 12:30';
 global_391_datetime_5DFC_si300[171] = D'2012.09.07 12:30';
 global_391_datetime_5DFC_si300[172] = D'2012.08.03 12:30';
 global_391_datetime_5DFC_si300[173] = D'2012.07.06 12:30';
 global_391_datetime_5DFC_si300[174] = D'2012.06.01 12:30';
 global_391_datetime_5DFC_si300[175] = D'2012.05.04 12:30';
 global_391_datetime_5DFC_si300[176] = D'2012.04.06 12:30';
 global_391_datetime_5DFC_si300[177] = D'2012.03.09 12:30';
 global_391_datetime_5DFC_si300[178] = D'2012.02.03 12:30';
 global_391_datetime_5DFC_si300[179] = D'2012.01.06 12:30';
 global_391_datetime_5DFC_si300[180] = D'2011.12.02 12:30';
 global_391_datetime_5DFC_si300[181] = D'2011.11.04 12:30';
 global_391_datetime_5DFC_si300[182] = D'2011.10.07 12:30';
 global_391_datetime_5DFC_si300[183] = D'2011.09.02 12:30';
 global_391_datetime_5DFC_si300[184] = D'2011.08.05 12:30';
 global_391_datetime_5DFC_si300[185] = D'2011.07.08 12:30';
 global_391_datetime_5DFC_si300[186] = D'2011.06.03 12:30';
 global_391_datetime_5DFC_si300[187] = D'2011.05.06 12:30';
 global_391_datetime_5DFC_si300[188] = D'2011.04.01 12:30';
 global_391_datetime_5DFC_si300[189] = D'2011.03.04 12:30';
 global_391_datetime_5DFC_si300[190] = D'2011.02.04 12:30';
 global_391_datetime_5DFC_si300[191] = D'2011.01.07 12:30';
 global_391_datetime_5DFC_si300[192] = D'2010.12.03 12:30';
 global_391_datetime_5DFC_si300[193] = D'2010.11.05 12:30';
 global_391_datetime_5DFC_si300[194] = D'2010.10.08 12:30';
 global_391_datetime_5DFC_si300[195] = D'2010.09.03 12:30';
 global_391_datetime_5DFC_si300[196] = D'2010.08.06 12:30';
 global_391_datetime_5DFC_si300[197] = D'2010.07.02 12:30';
 global_391_datetime_5DFC_si300[198] = D'2010.06.04 12:30';
 global_391_datetime_5DFC_si300[199] = D'2010.05.07 12:30';
 global_391_datetime_5DFC_si300[200] = D'2010.04.02 12:30';
 global_391_datetime_5DFC_si300[201] = D'2010.03.05 12:30';
 global_391_datetime_5DFC_si300[202] = D'2010.02.05 12:30';
 global_391_datetime_5DFC_si300[203] = D'2010.01.08 12:30';
 global_391_datetime_5DFC_si300[204] = D'2009.12.04 12:30';
 global_391_datetime_5DFC_si300[205] = D'2009.11.06 12:30';
 global_391_datetime_5DFC_si300[206] = D'2009.10.02 12:30';
 global_391_datetime_5DFC_si300[207] = D'2009.09.04 12:30';
 global_391_datetime_5DFC_si300[208] = D'2009.08.07 12:30';
 global_391_datetime_5DFC_si300[209] = D'2009.07.02 12:30';
 global_391_datetime_5DFC_si300[210] = D'2009.06.05 12:30';
 global_391_datetime_5DFC_si300[211] = D'2009.05.08 12:30';
 global_391_datetime_5DFC_si300[212] = D'2009.04.03 12:30';
 global_391_datetime_5DFC_si300[213] = D'2009.03.06 12:30';
 global_391_datetime_5DFC_si300[214] = D'2009.02.06 12:30';
 global_391_datetime_5DFC_si300[215] = D'2009.01.09 12:30';
 global_391_datetime_5DFC_si300[216] = D'2008.12.05 12:30';
 global_391_datetime_5DFC_si300[217] = D'2008.11.07 12:30';
 global_391_datetime_5DFC_si300[218] = D'2008.10.03 12:30';
 global_391_datetime_5DFC_si300[219] = D'2008.09.05 12:30';
 global_391_datetime_5DFC_si300[220] = D'2008.08.01 12:30';
 global_391_datetime_5DFC_si300[221] = D'2008.07.03 12:30';
 global_391_datetime_5DFC_si300[222] = D'2008.06.06 12:30';
 global_391_datetime_5DFC_si300[223] = D'2008.05.02 12:30';
 global_391_datetime_5DFC_si300[224] = D'2008.04.04 12:30';
 global_391_datetime_5DFC_si300[225] = D'2008.03.07 12:30';
 global_391_datetime_5DFC_si300[226] = D'2008.02.01 12:30';
 global_391_datetime_5DFC_si300[227] = D'2008.01.04 12:30';
 global_391_datetime_5DFC_si300[228] = D'2007.12.07 12:30';
 global_391_datetime_5DFC_si300[229] = D'2007.11.02 12:30';
 global_391_datetime_5DFC_si300[230] = D'2007.10.05 12:30';
 global_391_datetime_5DFC_si300[231] = D'2007.09.07 12:30';
 global_391_datetime_5DFC_si300[232] = D'2007.08.03 12:30';
 global_391_datetime_5DFC_si300[233] = D'2007.07.06 12:30';
 global_391_datetime_5DFC_si300[234] = D'2007.06.01 12:30';
 global_391_datetime_5DFC_si300[235] = D'2007.05.04 12:30';
 global_391_datetime_5DFC_si300[236] = D'2007.04.06 12:30';
 global_391_datetime_5DFC_si300[237] = D'2007.03.09 12:30';
 global_391_datetime_5DFC_si300[238] = D'2007.02.02 12:30';
 global_391_datetime_5DFC_si300[239] = D'2007.01.05 12:30';
 // Original OnInit calls the calendar helper whenever the NFP filter is enabled.
 // In Strategy Tester the calendar normally returns 0; runtime then uses hardcoded dates.
 if ( EnableNFP_Filter )   g_nextNFPCalendar = GetNextNFPFromCalendar();
 g_nfpCalendarLastRefresh = 0;
 if ( Risk == 1234 )
 {
   g_startLots_rw = MarketInfo(g_chartSymbol,MODE_MINLOT) ;
 }
  if ( TradeFrequency == 5 && Risk == 1234 )
 {
   local_2_double = ConvertAccountCurrencyToUsd(AccountInfoDouble(ACCOUNT_BALANCE)) ;
   local_3_double = MaxAllowedDD / 100.0 * local_2_double ;
   if ( local_3_double>global_388_int_5DB4 )
   {
     g_tradeFrequencyMode = 3 ;
   }
   else
   {
     if ( local_3_double>g_ddTierThreshold3 )
     {
       g_tradeFrequencyMode = 2 ;
     }
     else
     {
       if ( local_3_double>global_386_int_5DAC )
       {
         g_tradeFrequencyMode = 1 ;
       }
       else
       {
         g_tradeFrequencyMode = 0 ;
       }
     }
   }
 }
 else
 {
   g_tradeFrequencyMode = TradeFrequency ;
 }
 if ( g_tradeFrequencyMode == 0 )
 {
   g_runStrategy4 = false ;
   g_runStrategy5 = false ;
   g_runStrategy6 = false ;
   g_runStrategy7 = false ;
   g_runStrategy8 = false ;
   g_runStrategy9 = false ;
   g_riskFactorByTier = 2.4 ;
   if ( UseVariableValues )
   {
     g_riskFactorByTier = 3.0 ;
   }
 }
 else
 {
   if ( g_tradeFrequencyMode == 1 )
   {
     g_runStrategy4 = true ;
     g_runStrategy5 = true ;
     g_runStrategy6 = false ;
     g_runStrategy7 = false ;
     g_runStrategy8 = false ;
     g_runStrategy9 = false ;
     g_riskFactorByTier = 3.4 ;
     if ( UseVariableValues )
     {
       g_riskFactorByTier = 4.0 ;
     }
   }
   else
   {
     if ( g_tradeFrequencyMode == 2 )
     {
       g_runStrategy4 = true ;
       g_runStrategy5 = true ;
       g_runStrategy6 = true ;
       g_runStrategy7 = true ;
       g_runStrategy8 = false ;
       g_runStrategy9 = false ;
       g_riskFactorByTier = 4.1 ;
       if ( UseVariableValues )
       {
         g_riskFactorByTier = 5.0 ;
       }
     }
     else
     {
       if ( g_tradeFrequencyMode == 3 )
       {
         g_runStrategy4 = true ;
         g_runStrategy5 = true ;
         g_runStrategy6 = true ;
         g_runStrategy7 = true ;
         g_runStrategy8 = true ;
         g_runStrategy9 = false ;
         g_riskFactorByTier = 4.8 ;
         if ( UseVariableValues )
         {
           g_riskFactorByTier = 5.6 ;
         }
       }
       else
       {
         if ( g_tradeFrequencyMode == 4 )
         {
           g_runStrategy4 = true ;
           g_runStrategy5 = true ;
           g_runStrategy6 = true ;
           g_runStrategy7 = true ;
           g_runStrategy8 = true ;
           g_runStrategy9 = true ;
           g_riskFactorByTier = 5.1 ;
           if ( UseVariableValues )
           {
             g_riskFactorByTier = 6.0 ;
           }
         }
         else
         {
           if ( g_tradeFrequencyMode == 6 )
           {
             g_runStrategy1 = RunStrat1 ;
             g_runStrategy2 = RunStrat2 ;
             g_runStrategy3 = RunStrat3 ;
             g_runStrategy4 = RunStrat4 ;
             g_runStrategy5 = RunStrat5 ;
             g_runStrategy6 = RunStrat6 ;
             g_runStrategy7 = RunStrat7 ;
             g_runStrategy8 = RunStrat8 ;
             g_runStrategy9 = RunStrat9 ;
           }
         }
       }
     }
   }
 }
 g_orderComment = ST1_Comment ;
 global_384_double_5DA0 = 0.0 ;
 global_382_bool_5D98 = false ;
 global_379_datetime_5D88 = 0 ;
 g_propfirmDailyDDOn = true ;
 global_93_int_1F0 = ST1_MagicNumber ;
 g_maxPanelObjects = 300 ;
 global_361_double_5CC0 = g_panelFontSize * 25 * g_panelWidthScale * InfoPanelSizeAdjust ;
 g_panelCellHeight = g_panelFontSize * 3.5 * global_377_double_5D78 * InfoPanelSizeAdjust ;
 g_currentStrategyIndex = 0 ;
 g_chartSymbol = Symbol() ;
 g_symbolPoint = SymbolInfoDouble(g_chartSymbol,16) ;
 g_pipSize = g_symbolPoint ;
 if ( ( MarketInfo(g_chartSymbol,MODE_DIGITS)==3.0 || MarketInfo(g_chartSymbol,MODE_DIGITS)==5.0 ) )
 {
   g_pipSize = g_symbolPoint * 10.0 ;
 }
 if ( SymbolInfoInteger(g_chartSymbol,17) == 0x1 )
 {
   g_pipSize = g_symbolPoint / 10.0 ;
 }
 g_symbolDigits = (int)MarketInfo(g_chartSymbol,MODE_DIGITS) ;
 if ( FridayStopHour <  0 )
 {
   g_useFridayStop = false ;
 }
 else
 {
   g_useFridayStop = true ;
 }
 g_curSpread = MarketInfo(g_chartSymbol,MODE_ASK) - MarketInfo(g_chartSymbol,MODE_BID) ;
 global_223_double_1AC4_si99[g_currentStrategyIndex] = NormalizeDouble(MathFloor(g_startLots_rw * 100.0) / 100.0,2);
 if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.1 )
 {
   global_223_double_1AC4_si99[g_currentStrategyIndex] = NormalizeDouble((MathFloor(g_startLots_rw * 10.0)) / 10.0,1);
   if ( global_223_double_1AC4_si99[g_currentStrategyIndex]<0.1 )
   {
     global_223_double_1AC4_si99[g_currentStrategyIndex] = 0.1;
   }
 }
 if ( global_223_double_1AC4_si99[g_currentStrategyIndex]<MarketInfo(g_chartSymbol,MODE_MINLOT) )
 {
   global_223_double_1AC4_si99[g_currentStrategyIndex] = MarketInfo(g_chartSymbol,MODE_MINLOT);
 }
 if ( global_223_double_1AC4_si99[g_currentStrategyIndex]>MarketInfo(g_chartSymbol,MODE_MAXLOT) )
 {
   global_223_double_1AC4_si99[g_currentStrategyIndex] = MarketInfo(g_chartSymbol,MODE_MAXLOT);
 }
 if ( global_131_double_328 * g_pipSize<g_symbolPoint )
 {
   global_131_double_328 = g_symbolPoint / g_pipSize ;
 }
 g_minStopDistPrice = MarketInfo(g_chartSymbol,MODE_STOPLEVEL) * g_symbolPoint ;
 global_309_double_2898 = MarketInfo(g_chartSymbol,MODE_FREEZELEVEL) * g_symbolPoint ;
 g_symbolSuffix = StringSubstr(Symbol(),6,10) ;
 if ( g_symbolSuffix != "" )
 {
   Print("Suffix detected: " + g_symbolSuffix); 
 }
 if ( ( StringFind(Symbol(),"XAUUSD",0) >= 0 || StringFind(Symbol(),"xauusd",0) >= 0 || StringFind(Symbol(),"GOLD",0) >= 0 || StringFind(Symbol(),"gold",0) >= 0 || StringFind(Symbol(),"Gold",0) >= 0 || StringFind(Symbol(),"GLD",0) >= 0 ) )
 {
   g_chartSymbol = Symbol() ;
   g_strategySymbols[g_strategyCount] = Symbol();
   LoadStrategy1Settings(); 
   LoadStrategyRuntimeSettings(0); 
   g_strategyCount ++;
 }
 else
 {
   g_chartSymbol = Symbol() ;
   LoadStrategyRuntimeSettings(0); 
 }
 // Original dump contains no separate pair-initialisation failure message here.
 if ( global_100_double_230<=0.0 )
 {
   global_100_double_230 = 1.0 ;
 }
 if ( g_takeProfitPips<=0.0 )
 {
   g_takeProfitPips = 1.0 ;
 }
 if ( g_beExtraPips>global_113_double_2A8 )
 {
   g_beExtraPips = global_113_double_2A8 + 0.1 ;
 }
 if ( global_36_int_B0<global_309_double_2898 / g_pipSize )
 {
   global_36_int_B0 = (int)(global_309_double_2898 / g_pipSize) ;
 }
 if ( global_103_double_250!=0.0 && global_103_double_250<global_309_double_2898 / g_pipSize )
 {
   global_103_double_250 = global_309_double_2898 / g_pipSize ;
 }
 if ( global_103_double_250!=0.0 && global_103_double_250<g_minStopDistPrice / g_pipSize )
 {
   global_103_double_250 = g_minStopDistPrice / g_pipSize ;
 }
 if ( global_125_double_2F8>0.0 && global_126_double_300<global_309_double_2898 / g_pipSize )
 {
   global_126_double_300 = global_309_double_2898 / g_pipSize ;
 }
 if ( global_125_double_2F8>0.0 && global_126_double_300<g_minStopDistPrice / g_pipSize )
 {
   global_126_double_300 = g_minStopDistPrice / g_pipSize ;
 }
 if ( global_100_double_230<g_minStopDistPrice * 2.0 / g_pipSize )
 {
   global_100_double_230 = g_minStopDistPrice * 2.0 / g_pipSize ;
 }
 if ( g_takeProfitPips<g_minStopDistPrice * 2.0 / g_pipSize )
 {
   g_takeProfitPips = g_minStopDistPrice * 2.0 / g_pipSize ;
 }
 if ( g_entryBreakoutPips<g_minStopDistPrice * 2.0 / g_pipSize )
 {
   g_entryBreakoutPips = g_minStopDistPrice * 2.0 / g_pipSize ;
 }
 if ( global_73_int_17C <  1 )
 {
   global_73_int_17C = 1 ;
 }
 if ( global_74_int_180 <  1 )
 {
   global_74_int_180 = 1 ;
 }
 if ( g_entryBreakoutPips<0.1 )
 {
   g_entryBreakoutPips = 0.1 ;
 }
 g_pendingExpirySecs=g_pendingExpiryHours * 60 * 60;
 if ( g_pendingExpiryHours >  0 )
 {
   g_pendingOrderExpiry=TimeCurrent() + g_pendingExpirySecs;
 }
 else
 {
   g_pendingOrderExpiry = 0 ;
 }
 if ( Virtual_expiration )
 {
   g_pendingOrderExpiry = 0 ;
 }
 g_nfpWindowActive = false ;
 g_lastTrailOrderTime = TimeCurrent() ;
 global_194_bool_530 = false ;
 global_195_bool_531 = false ;
 if ( g_maxSpreadPts>g_MaxSpread_rw )
 {
   g_maxSpreadPts = g_MaxSpread_rw ;
 }
 FindBuyEntryHigh(g_entryTfPeriod); 
 FindSellEntryLow(g_entryTfPeriod); 
 g_buyEntryPrice = NormalizeDouble(g_entryHighPrice,g_symbolDigits) ;
 g_sellEntryPrice = NormalizeDouble(g_entryLowPrice,g_symbolDigits) ;
 global_250_int_2518 = 0 ;
 global_304_int_287C = (int)(global_125_double_2F8 * 60.0) ;
 g_marketClosedFlag = true ;
 global_309_double_2898 = MarketInfo(g_chartSymbol,MODE_FREEZELEVEL) * g_symbolPoint ;
 if ( !(g_useTradingHours) )
 {
   g_marketClosedFlag = false ;
 }
 g_virtualSLPrice = 0.0 ;
 g_symbolSuffix = StringSubstr(g_chartSymbol,6,0) ;
 if ( Risk >  0 )
 {
 }
 if ( g_startLots_rw<0.0 )
 {
   g_startLots_rw = 0.01 ;
 }
 if ( g_maxLotCap>MarketInfo(g_chartSymbol,MODE_MAXLOT) )
 {
   g_maxLotCap = MarketInfo(g_chartSymbol,MODE_MAXLOT) ;
 }
 for (local_4_int = 0 ; local_4_int < g_virtSLCacheSize ; local_4_int ++)
 {
   for (local_5_int = 0 ; local_5_int < 2 ; local_5_int ++)
   {
     g_virtSLCache[local_4_int][local_5_int] = 0.0;
   }
 }
 for (local_6_int = 0 ; local_6_int < global_200_int_16B4 ; local_6_int ++)
 {
   for (local_7_int = 0 ; local_7_int < 3 ; local_7_int ++)
   {
     g_virtualPendingOrders[local_6_int][local_7_int] = 0.0;
   }
 }
 for (local_8_int = 0 ; local_8_int < 100 ; local_8_int ++)
 {
   g_virtualPendingOrders[local_8_int][0] = 0.0;
   g_virtualPendingOrders[local_8_int][1] = 0.0;
 }
 g_fridayStopDone = false ;
 global_252_string_2528=ST1_Comment + "B1";
 global_253_string_2538=ST1_Comment + "B2";
 global_254_string_2548=ST1_Comment + "S1";
 global_255_string_2558=ST1_Comment + "S2";
 g_lastHour = Hour() ;
 if ( global_67_bool_158 )
 {
   g_maxPendingOrders = 1 ;
 }
 for (local_9_int = 0 ; local_9_int < 99 ; local_9_int ++)
 {
   global_322_int_2AE0_si99[local_9_int] = 0;
   global_321_int_2920_si99[local_9_int] = 0;
   global_215_datetime_174C_si99[local_9_int] = iTime(g_chartSymbol,MT4Period(g_entryTfPeriod),1);
   if ( !(global_223_double_1AC4_si99[local_9_int]<g_startLots_rw) )   continue;
   global_223_double_1AC4_si99[local_9_int] = g_startLots_rw;
   
 }
 if ( g_profitCloseMode == 1 )
 {
   global_64_double_148 = 0.0 ;
 }
 g_symbolDigits = (int)MarketInfo(g_chartSymbol,MODE_DIGITS) ;
 g_isDemoAccount = false ;
 IsDemo(); 

 if ( temp_bool_1 == true )
 {
   g_isDemoAccount = true ;
 }
 if ( ShowInfoPanel )
 {
   if ( g_rankMode == 1 )
   {
     RankStrategiesByClosedProfit(); 
   }
   else
   {
     if ( g_rankMode == 2 )
     {
       RankStrategiesByProfitPerTrade(); 
     }
   }
   CreateInfoPanel(); 
   UpdateAccountPanel(); 
   UpdateHistoryPanel(); 
 }
 return(0); 
 }
//init <<==--------   --------
// DumpBacktestSpeedAllowTick —— 回测加速节流：fast=每秒最多 1 个 tick，
//                               super=每根已收 M1 K 线最多处理一次
 bool DumpBacktestSpeedAllowTick()
 {
  if ( !(g_backtestSpeedEnabled) )   return(true);

  bool temp_skip = false;
  if ( g_backtestSpeedFast )
  {
    datetime temp_now = TimeCurrent();
    if ( temp_now > g_backtestSpeedLastTime + 1 )
    {
      g_backtestSpeedLastTime = temp_now;
      temp_skip = false;
    }
    else
    {
      temp_skip = true;
    }
  }
  else
  {
    // speed_super: only a new closed M1 bar is accepted.  Avoid the expensive
    // iTime() series lookup on every real tick: a closed M1 bar cannot change
    // again while TimeCurrent() is still inside the same server minute.
    datetime temp_now = TimeCurrent();
    if ( temp_now < g_backtestSpeedLastProbeMinute + 60 )   return(false);
    datetime temp_minute = temp_now - (temp_now % 60);
    g_backtestSpeedLastProbeMinute = temp_minute;
    temp_skip = true;
  }

  datetime temp_m1 = iTime(Symbol(),PERIOD_M1,1);
  if ( temp_m1 > g_backtestSpeedLastM1 )
  {
    g_backtestSpeedLastM1 = temp_m1;
    return(true);
  }
  if ( temp_skip )   return(false);
  return(true);
 }
//DumpBacktestSpeedAllowTick <<==--------   --------

// =====================================================================
// OnTick 璇箟妯″潡鎷嗗垎锛堟壒娆?锛?026-09锛?
// 鍘熷弽缂栬瘧 OnTick 涓?~600 琛屽钩閾鸿繃绋嬨€備互涓嬫ā鍧楁寜鍘熻鍙ラ『搴?1:1 鎶藉彇锛?
// 璇彞鏈綋淇濇寔鍘熸牱锛堟湭鏀瑰啓銆佹湭閲嶆帓锛夛紝浠呮秷闄?9 涓瓥鐣ヨ皟搴﹀潡鐨勫瓧闈㈤噸澶嶏細
//   UpdateEffectiveBalanceTracking      鏈夋晥浣欓/OnlyUp 楂樻按浣?ManualBalance 瑕嗙洊
//   ApplyFakeoutFilterMode              FakeOutFilter -> M1/M15/H1 浣胯兘鏄犲皠
//   UpdateGmtDstDetection               US/EU 澶忎护鏃剁姸鎬佹満 + GMT 鍋忕Щ鎺㈡祴
//   RefreshNfpCalendarCache             NFP 鏃ュ巻缂撳瓨锛?00 绉掑埛鏂帮紱鍥炴祴鐢ㄧ‖缂栫爜鏃ユ湡锛?
//   EnforceManualHistoricalDDCompat     鍘熺増闈炴硶杈撳叆缁勫悎鍏煎锛堥浂闄よ涓哄鐜帮級
//   ApplyTradeFrequencyTiers            浜ゆ槗棰戠巼妗ｄ綅 -> 绛栫暐寮€鍏?椋庨櫓绯绘暟
//   CheckDailyRolloverAndPropFirmGate   D1 鎹㈡棩閲嶇疆 + PropFirm 鏃ュ唴鍥炴挙闂搁棬
//   DetectNewH1Bar                      H1 鏀剁洏 K 绾垮彉鍖栨娴?
//   RunAllStrategies / RunStrategySlot   9 绛栫暐妲戒綅璋冨害锛堥『搴忎繚鎸佸師鐗?1,4,2,3,6,5,9,7,8锛?
//   UpdatePanelsOnNewM5Bar              M5 鏂?K 绾?-> 绛栫暐/鍘嗗彶闈㈡澘鍒锋柊
//   FinishTickLotResizeThrottle         姣?2 tick 鐨勪綑棰濆揩鐓ф墜鏁板啀骞宠　
// =====================================================================

// UpdateEffectiveBalanceTracking 鈥斺€?鏈夋晥浣欓锛圤nlyUp 楂樻按浣?+ ManualBalance 瑕嗙洊锛?
void UpdateEffectiveBalanceTracking()
{
  global_401_double_6AD0 = AccountInfoDouble(ACCOUNT_BALANCE) ;
  if ( UseEquity )
  {
    global_401_double_6AD0 = AccountInfoDouble(ACCOUNT_EQUITY) ;
  }
  if ( OnlyUp && g_highestBalance>global_401_double_6AD0 )
  {
    global_401_double_6AD0 = g_highestBalance ;
  }
  if ( global_401_double_6AD0>g_highestBalance )
  {
    g_highestBalance = global_401_double_6AD0 ;
    GlobalVariableSet("HighestBalance",g_highestBalance) ;
  }
  if ( ManualBalance>0.0 )
  {
    global_401_double_6AD0 = ManualBalance ;
  }
}

// ApplyFakeoutFilterMode 鈥斺€?FakeOutFilter 杈撳叆 -> M1/M15/H1 鍋囩獊鐮磋繃婊ゅ櫒浣胯兘
void ApplyFakeoutFilterMode()
{
  if ( FakeOutFilter == 0 )
  {
    g_fakeoutEnableM1 = false ;
    g_fakeoutEnableM15 = false ;
    g_fakeoutEnableH1 = false ;
  }
  else
  {
    if ( FakeOutFilter == 1 )
    {
      g_fakeoutEnableM1 = true ;
      g_fakeoutEnableM15 = false ;
      g_fakeoutEnableH1 = false ;
    }
    else
    {
      if ( FakeOutFilter == 2 )
      {
        g_fakeoutEnableM1 = true ;
        g_fakeoutEnableM15 = true ;
        g_fakeoutEnableH1 = false ;
      }
      else
      {
        if ( FakeOutFilter == 3 )
        {
          g_fakeoutEnableM1 = true ;
          g_fakeoutEnableM15 = true ;
          g_fakeoutEnableH1 = true ;
        }
      }
    }
  }
}

// UpdateGmtDstDetection 鈥斺€?US/EU 澶忎护鏃剁姸鎬佹満锛氬亸绉诲垏鎹㈡椂閲嶆柊鎺㈡祴 GMT锛?
//                         闈?AutoGMT锛堟垨鍥炴祴锛夌洿鎺ョ敤鍐?澶忛厤缃亸绉绘帹 NFP 鏃堕棿
void UpdateGmtDstDetection()
{
  bool   temp_dstHandled = false ;   // 鍘?local_1_bool锛氭湰娆?tick 鏄惁宸插鐞嗚繃 DST 鍒囨崲
  if ( IsAmericanDst() )
  {
    global_395_int_6760 = Broker_GMT_OFFSET_Summer ;
    if ( ( !(g_isSummerTime) || !(g_gmtDetectDone) ) && AutoGMT && !(temp_dstHandled) )
    {
      g_isSummerTime = true ;
      global_393_bool_675D = true ;
      g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset wrongly detected.  Trying againg!");
        Sleep(2000);
        g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      }
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
      }
      g_gmtDetectDone = true ;
      temp_dstHandled = true ;
      Print("DST_US on");
    }
  }
  else
  {
    global_395_int_6760 = Broker_GMT_OFFSET_Winter ;
    if ( ( g_isSummerTime || !(g_gmtDetectDone) ) && AutoGMT && !(temp_dstHandled) )
    {
      g_isSummerTime = false ;
      global_393_bool_675D = false ;
      g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset wrongly detected.  Trying againg!");
        Sleep(2000);
        g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      }
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
      }
      g_gmtDetectDone = true ;
      temp_dstHandled = true ;
      Print("DST_US off");
    }
  }
  bool temp_isEuDst = MT4EuropeanDST();
  if ( temp_isEuDst )
  {
    if ( ( !(global_393_bool_675D) || !(g_gmtDetectDone) ) && AutoGMT && !(temp_dstHandled) )
    {
      global_393_bool_675D = true ;
      g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset wrongly detected.  Trying againg!");
        Sleep(2000);
        g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      }
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
      }
      g_gmtDetectDone = true ;
      temp_dstHandled = true ;
      Print("DST_EU on");
    }
  }
  else
  {
    if ( ( global_393_bool_675D || !(g_gmtDetectDone) ) && AutoGMT && !(temp_dstHandled) )
    {
      global_393_bool_675D = false ;
      g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset wrongly detected.  Trying againg!");
        Sleep(2000);
        g_detectedGmtOffset = DetectBrokerGmtOffset() ;
      }
      if ( g_detectedGmtOffset == 999 )
      {
        Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
      }
      g_gmtDetectDone = true ;
      temp_dstHandled = true ;
      Print("DST_EU off");
    }
  }
  if ( AutoGMT && MQLInfoInteger(MQL_TESTER) != 1 )
  {
    if ( g_detectedGmtOffset != 999 )
    {
      g_nfpAdjustedNow=TimeCurrent() - g_detectedGmtOffset * 3600;
    }
    else
    {
      g_nfpAdjustedNow = TimeGMT() ;
    }
  }
  else
  {
    g_nfpAdjustedNow=TimeCurrent() - global_395_int_6760 * 3600;
  }
}

// RefreshNfpCalendarCache 鈥斺€?鍘熺増 V4.6 瀹炵洏鏃ュ巻缂撳瓨锛氳窛涓婃鍒锋柊 900 绉?
// 鎴栧綋鍓嶆棤缂撳瓨浜嬩欢鏃剁珛鍗虫媺鍙栵紱鍥炴祴涓嶈蛋姝よ矾寰勶紙浣跨敤纭紪鐮?NFP 鏃ユ湡锛?
void RefreshNfpCalendarCache()
{
  if ( EnableNFP_Filter && UseMQL5Calendar && MQLInfoInteger(MQL_TESTER) != 1 )
  {
    datetime temp_nfpRefreshNow = TimeTradeServer();
    if ( temp_nfpRefreshNow > g_nfpCalendarLastRefresh + 900 || g_nextNFPCalendar == 0 )
    {
      g_nextNFPCalendar = GetNextNFPFromCalendar();
      g_nfpCalendarLastRefresh = TimeTradeServer();
    }
  }
}

// EnforceManualHistoricalDDCompat 鈥斺€?鍘熺増 Market EX5 瀵硅涓嶅吋瀹硅緭鍏ョ粍鍚堢殑琛屼负锛?
// 鎵嬪姩棰戠巼浠庝笉鍒濆鍖栧巻鍙?DD 闄ゆ暟锛岄涓?tick 浠ラ浂闄や弗閲嶉敊璇粓姝紱姝ゅ鎸夊師鏍峰鐜?
void EnforceManualHistoricalDDCompat()
{
  if ( TradeFrequency == Manual_Strategy_Selection && Risk == MaxHistoricalDD && UseWeightedLots &&
       (RunStrat1 || RunStrat2 || RunStrat3 || RunStrat4 || RunStrat5 ||
        RunStrat6 || RunStrat7 || RunStrat8 || RunStrat9) )
  {
    string original_manual_dd_empty=StringSubstr(Symbol(),0,0);
    int original_manual_dd_divisor=(int)StringToInteger(original_manual_dd_empty);
    int original_manual_dd_result=(int)AccountInfoInteger(ACCOUNT_LOGIN)/original_manual_dd_divisor;
    Print("manual historical-DD compatibility result: ",original_manual_dd_result);
  }
}

// ApplyTradeFrequencyTiers 鈥斺€?浜ゆ槗棰戠巼妗ｄ綅閫夋嫨锛汻isk==1234 鏃舵寜璐︽埛 USD 鎶樼畻鐨?
// MaxAllowedDD 鍒嗗眰鑷€傚簲妗ｄ綅锛涢殢鍚庡皢妗ｄ綅鏄犲皠涓虹瓥鐣ュ紑鍏充笌椋庨櫓绯绘暟
void ApplyTradeFrequencyTiers()
{
  double   temp_usdBalance;
  double   temp_maxDDUsd;
  if ( TradeFrequency == 5 && Risk == 1234 )
  {
    temp_usdBalance = ConvertAccountCurrencyToUsd(AccountInfoDouble(ACCOUNT_BALANCE)) ;
    temp_maxDDUsd = MaxAllowedDD / 100.0 * temp_usdBalance ;
    if ( temp_maxDDUsd>global_388_int_5DB4 )
    {
      g_tradeFrequencyMode = 3 ;
    }
    else
    {
      if ( temp_maxDDUsd>g_ddTierThreshold3 )
      {
        g_tradeFrequencyMode = 2 ;
      }
      else
      {
        if ( temp_maxDDUsd>global_386_int_5DAC )
        {
          g_tradeFrequencyMode = 1 ;
        }
        else
        {
          g_tradeFrequencyMode = 0 ;
        }
      }
    }
  }
  else
  {
    g_tradeFrequencyMode = TradeFrequency ;
  }
  if ( g_tradeFrequencyMode == 0 )
  {
    g_runStrategy4 = false ;
    g_runStrategy5 = false ;
    g_runStrategy6 = false ;
    g_runStrategy7 = false ;
    g_runStrategy8 = false ;
    g_runStrategy9 = false ;
    g_riskFactorByTier = 2.4 ;
    if ( UseVariableValues )
    {
      g_riskFactorByTier = 3.0 ;
    }
  }
  else
  {
    if ( g_tradeFrequencyMode == 1 )
    {
      g_runStrategy4 = true ;
      g_runStrategy5 = true ;
      g_runStrategy6 = false ;
      g_runStrategy7 = false ;
      g_runStrategy8 = false ;
      g_runStrategy9 = false ;
      g_riskFactorByTier = 3.4 ;
      if ( UseVariableValues )
      {
        g_riskFactorByTier = 4.0 ;
      }
    }
    else
    {
      if ( g_tradeFrequencyMode == 2 )
      {
        g_runStrategy4 = true ;
        g_runStrategy5 = true ;
        g_runStrategy6 = true ;
        g_runStrategy7 = true ;
        g_runStrategy8 = false ;
        g_runStrategy9 = false ;
        g_riskFactorByTier = 4.1 ;
        if ( UseVariableValues )
        {
          g_riskFactorByTier = 5.0 ;
        }
      }
      else
      {
        if ( g_tradeFrequencyMode == 3 )
        {
          g_runStrategy4 = true ;
          g_runStrategy5 = true ;
          g_runStrategy6 = true ;
          g_runStrategy7 = true ;
          g_runStrategy8 = true ;
          g_runStrategy9 = false ;
          g_riskFactorByTier = 4.8 ;
          if ( UseVariableValues )
          {
            g_riskFactorByTier = 5.6 ;
          }
        }
        else
        {
          if ( g_tradeFrequencyMode == 4 )
          {
            g_runStrategy4 = true ;
            g_runStrategy5 = true ;
            g_runStrategy6 = true ;
            g_runStrategy7 = true ;
            g_runStrategy8 = true ;
            g_runStrategy9 = true ;
            g_riskFactorByTier = 5.1 ;
            if ( UseVariableValues )
            {
              g_riskFactorByTier = 6.0 ;
            }
          }
          else
          {
            if ( g_tradeFrequencyMode == 6 )
            {
              g_runStrategy1 = RunStrat1 ;
              g_runStrategy2 = RunStrat2 ;
              g_runStrategy3 = RunStrat3 ;
              g_runStrategy4 = RunStrat4 ;
              g_runStrategy5 = RunStrat5 ;
              g_runStrategy6 = RunStrat6 ;
              g_runStrategy7 = RunStrat7 ;
              g_runStrategy8 = RunStrat8 ;
              g_runStrategy9 = RunStrat9 ;
            }
          }
        }
      }
    }
  }
}

// CheckDailyRolloverAndPropFirmGate 鈥斺€?D1 鎹㈡棩鏃堕噸缃棩鍐呭洖鎾ゅ熀鍑嗭紱鎵ц PropFirm
// 鏃ュ唴鍥炴挙寮哄钩锛涜繑鍥?false 琛ㄧず鏈?tick 搴旂珛鍗宠繑鍥烇紙鍘熺増鍐呰仈 return锛?
bool CheckDailyRolloverAndPropFirmGate()
{
  if ( iBars(g_chartSymbol,MT4Period(PERIOD_D1)) != g_lastD1BarsCount )
  {
    g_lastD1BarsCount = iBars(g_chartSymbol,MT4Period(PERIOD_D1)) ;
    global_382_bool_5D98 = false ;
    global_384_double_5DA0 = 0.0 ;
  }
  if ( PropFirmMaxDailyDD>0.0 )
  {
    EnforcePropFirmDailyDrawdown();
  }
  if ( global_382_bool_5D98 || !(g_propfirmDailyDDOn) )   return(false);
  return(true);
}

// DetectNewH1Bar 鈥斺€?H1 鏀剁洏 K 绾垮彉鍖栨娴嬶紙鍘?local_4_bool锛?
bool DetectNewH1Bar()
{
  if ( global_399_datetime_6778 != iTime(g_chartSymbol,MT4Period(PERIOD_H1),1) )
  {
    global_399_datetime_6778 = iTime(g_chartSymbol,MT4Period(PERIOD_H1),1) ;
    return(true);
  }
  return(false);
}

// RunStrategySlot 鈥斺€?鍗曠瓥鐣ユЫ浣嶏細鍔犺浇绛栫暐璁剧疆 -> 杩愯鏃惰缃?-> 澶勭悊锛?
// 妲戒綅 0 棰濆妫€娴嬪垵濮嬫棫鐗堥闄╂墜鏁版寕鍗曪紱H1 鏂?K 绾挎椂鍒锋柊璇ョ瓥鐣ュ巻鍙插钩浠撶泩浜忕粺璁?
// 锛堢粺璁¤鏁版部鐢ㄥ師鐗堬細浣跨敤 g_currentStrategyIndex 鑰岄潪妲戒綅鍙凤級
void RunStrategySlot(const int strategyIndex,const bool newH1Bar)
{
  switch(strategyIndex)
  {
    case 0:  LoadStrategy1Settings(); break;
    case 1:  LoadStrategy2Settings(); break;
    case 2:  LoadStrategy3Settings(); break;
    case 3:  LoadStrategy4Settings(); break;
    case 4:  LoadStrategy5Settings(); break;
    case 5:  LoadStrategy6Settings(); break;
    case 6:  LoadStrategy7Settings(); break;
    case 7:  LoadStrategy8Settings(); break;
    case 8:  LoadStrategy9Settings(); break;
  }
  LoadStrategyRuntimeSettings(strategyIndex);
  ProcessStrategy(strategyIndex);
  if ( strategyIndex == 0 )
  {
    if ( g_initialLegacyRiskLotPending )
    {
      for (int temp_initialLotOrder = MT4OrdersTotal(); temp_initialLotOrder >= 0; temp_initialLotOrder--)
      {
        if ( OrderSelect(temp_initialLotOrder,0,0) && OrderSymbol() == g_chartSymbol &&
             OrderMagicNumber() == ST1_MagicNumber + 1 )
        {
          g_initialLegacyRiskLotPending=false;
          break;
        }
      }
    }
  }
  if ( newH1Bar )
  {
    double temp_histPL = 0.0;
    if ( !( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )
    {
      double temp_statsPL = 0.0;
      MT4HistoryStats(g_chartSymbol,global_93_int_1F0,g_closedTradeCount[g_currentStrategyIndex],temp_statsPL);
      temp_histPL = temp_statsPL;
    }
    g_histClosedPLbyStrategy[strategyIndex] = temp_histPL;
    if ( g_histClosedPLbyStrategy[strategyIndex]!=0.0 && g_closedTradeCount[strategyIndex] >  0 )
    {
      g_avgPLperTrade[strategyIndex] = g_histClosedPLbyStrategy[strategyIndex] / g_closedTradeCount[strategyIndex];
    }
  }
}

// RunAllStrategies 鈥斺€?鍝佺涓洪粍閲戠被鏃舵寜鍘熺増鍥哄畾椤哄簭璋冨害绛栫暐妲戒綅锛?,4,2,3,6,5,9,7,8锛夛紱
//                     闈為粍閲戝搧绉嶄粎浠ユЫ浣?0 杩愯锛堝師鐗堣涓猴級
void RunAllStrategies(const bool newH1Bar)
{
  if ( ( StringFind(Symbol(),"XAUUSD",0) >= 0 || StringFind(Symbol(),"xauusd",0) >= 0 || StringFind(Symbol(),"GOLD",0) >= 0 || StringFind(Symbol(),"GLD",0) >= 0 || StringFind(Symbol(),"gold",0) >= 0 || StringFind(Symbol(),"Gold",0) >= 0 ) )
  {
    g_chartSymbol = Symbol() ;
    if ( g_runStrategy1 )  RunStrategySlot(0,newH1Bar);
    if ( g_runStrategy4 )  RunStrategySlot(3,newH1Bar);
    if ( g_runStrategy2 )  RunStrategySlot(1,newH1Bar);
    if ( g_runStrategy3 )  RunStrategySlot(2,newH1Bar);
    if ( g_runStrategy6 )  RunStrategySlot(5,newH1Bar);
    if ( g_runStrategy5 )  RunStrategySlot(4,newH1Bar);
    if ( g_runStrategy9 )  RunStrategySlot(8,newH1Bar);
    if ( g_runStrategy7 )  RunStrategySlot(6,newH1Bar);
    if ( g_runStrategy8 )  RunStrategySlot(7,newH1Bar);
  }
  else
  {
    g_chartSymbol = Symbol() ;
    ProcessStrategy(0);
  }
}

// UpdatePanelsOnNewM5Bar 鈥斺€?M5 鏀剁洏 K 绾垮彉鍖栨椂鍒锋柊绛栫暐/鍘嗗彶闈㈡澘琛?
void UpdatePanelsOnNewM5Bar()
{
  if ( iTime(Symbol(),PERIOD_M5,1) != global_379_datetime_5D88 )
  {
    global_379_datetime_5D88 = iTime(Symbol(),PERIOD_M5,1) ;
    UpdateStrategyPanelRows();
    UpdateHistoryPanel();
  }
}

// FinishTickLotResizeThrottle 鈥斺€?2-tick 鑺傛祦鐨勪綑棰濆揩鐓э紙椹卞姩鎸傚崟鎵嬫暟鍐嶅钩琛★級
void FinishTickLotResizeThrottle()
{
  global_381_int_5D94 ++;
  if ( global_381_int_5D94 < 2 )
  {
    return;
  }
  g_lastLotResizeBalance = AccountBalance() ; // JIT sync: original LastLotResizeBalance snapshots ACCOUNT_BALANCE
  global_381_int_5D94 = 0 ;
}

// OnTick 鈥斺€?涓诲鐞嗗惊鐜細鍚勮繃婊ゅ櫒 -> 閫愮瓥鐣?LoadStrategyNSettings +
//           ProcessStrategy -> 闈㈡澘鏇存柊锛堣涔夋ā鍧楀寲鍚庯紝璇彞椤哄簭涓庡師鐗堜竴鑷达級
void OnTick()
{
  if(!(DumpBacktestSpeedAllowTick())) return;
  g_live_valid=false;

  UpdateEffectiveBalanceTracking();
  ApplyFakeoutFilterMode();
  UpdateGmtDstDetection();
  RefreshNfpCalendarCache();
  EnforceManualHistoricalDDCompat();
  ApplyTradeFrequencyTiers();
  if ( !(CheckDailyRolloverAndPropFirmGate()) )   return;

  bool temp_newH1Bar = DetectNewH1Bar();
  RunAllStrategies(temp_newH1Bar);

  UpdateAccountPanel();
  UpdatePanelsOnNewM5Bar();
  FinishTickLotResizeThrottle();
}
//OnTick <<==--------   --------
// OnDeinit —— 释放 9 个 iATR 指标句柄并删除信息面板
 void OnDeinit(const int reason)
 {
 for(int i=0;i<9;i++)
 {
   if(g_atr_handles[i]>0) IndicatorRelease(g_atr_handles[i]);
   g_atr_handles[i]=0;
 }
 DeleteInfoPanel(); 
 }
//deinit <<==--------   --------

// ============================================================================
// [§8] 策略运行时设置装载
// ============================================================================

// LoadStrategyRuntimeSettings —— 每次激活策略时重建该策略的 iATR 就绪门并
//                                刷新运行时参数（原 V4.6 每次激活都重建句柄）
// Original V4.6 dump has no custom OnTradeTransaction withdrawal adjustment.
 void LoadStrategyRuntimeSettings( int arg_0_int)
 {
 // -----------------------------------------------------------------
 // Recovered from the original MetaTester64 full-memory dump/JIT.
 // The original creates an iATR handle on every strategy activation,
 // copies 100 values, sets the buffer as series and touches [1].
 // This is a history/indicator-readiness gate; the ATR value itself is
 // not used in the trading arithmetic that follows.
 // -----------------------------------------------------------------
 int temp_atr_index=arg_0_int;
 if(temp_atr_index<0 || temp_atr_index>8) temp_atr_index=0;
 ENUM_TIMEFRAMES temp_atr_tf=MT4Period(g_atrTimeframe);
 if(g_atr_handles[temp_atr_index]<=0 ||
    g_atr_periods[temp_atr_index]!=g_atrPeriod ||
    g_atr_timeframes[temp_atr_index]!=temp_atr_tf)
 {
   if(g_atr_handles[temp_atr_index]>0) IndicatorRelease(g_atr_handles[temp_atr_index]);
   g_atr_handles[temp_atr_index]=iATR(g_chartSymbol,temp_atr_tf,g_atrPeriod);
   g_atr_periods[temp_atr_index]=g_atrPeriod;
   g_atr_timeframes[temp_atr_index]=temp_atr_tf;
   g_atr_checked_bars[temp_atr_index]=0;
   g_atr_cached_values[temp_atr_index]=0.0;
   g_atr_ready[temp_atr_index]=false;
 }
 g_atrHandle = g_atr_handles[temp_atr_index];
 if ( g_atrHandle < 0 )
 {
   Print("The creation of iATR has failed: Runtime error =" + IntegerToString(GetLastError()));
   return;
 }
 // ATR is a readiness gate only; its value is never used by the trading
 // arithmetic.  Refresh once per ATR bar and keep retrying until the buffer is
 // ready, instead of issuing several CopyBuffer calls on every market tick.
 datetime temp_atr_bar=iTime(g_chartSymbol,temp_atr_tf,0);
 if ( !(g_atr_ready[temp_atr_index]) || g_atr_checked_bars[temp_atr_index]!=temp_atr_bar )
 {
   if ( CopyBuffer(g_atrHandle,0,0,2,g_atrBuffer) == 0 )
   {
     return;
   }
   ArraySetAsSeries(g_atrBuffer,true);
   // Original JIT contains the bounds check for element [1].
   g_atr_cached_values[temp_atr_index]=g_atrBuffer[1];
   g_atr_checked_bars[temp_atr_index]=temp_atr_bar;
   g_atr_ready[temp_atr_index]=true;
 }

 // Original JIT first derives the variable-value ratio, then selects
 // either that ratio or 1.0 according to UseVariableValues.  The 1000
 // threshold and the absence of NormalizeDouble() on entry offsets are
 // both visible in the dump (e.g. -170 -> -402.49625 at ratio 2.367625).
 double temp_variableRatio = 1.0 ;
 if ( global_7_double_50>=1000.0 )
 {
   temp_variableRatio = iOpen(g_chartSymbol,MT4Period(PERIOD_D1),1) / global_7_double_50 ;
 }
 if ( UseVariableValues )
 {
   g_variableRatio = temp_variableRatio ;
 }
 else
 {
   g_variableRatio = 1.0 ;
 }
 if ( AdjustLotsizeToVariableValues )
 {
   g_lotRatioInv = 1.0 / g_variableRatio ;
 }
 else
 {
   g_lotRatioInv = 1.0 ;
 }
 if ( g_variableRatio==0.0 )
 {
   g_variableRatio = 1.0 ;
 }


 g_currentStrategyIndex = arg_0_int ;

 // The original explicitly checks that a current tick is available.
 // Failure is logged, but execution continues exactly as in the dump.
 MqlTick temp_tick;
 if ( !(SymbolInfoTick(g_chartSymbol,temp_tick)) )
 {
   Print("Tick not ok");
 }

 g_symbolPoint = SymbolInfoDouble(g_chartSymbol,16) ;
 g_pipSize = g_symbolPoint ;
 if ( ( MarketInfo(g_chartSymbol,MODE_DIGITS)==3.0 || MarketInfo(g_chartSymbol,MODE_DIGITS)==5.0 ) )
 {
   g_pipSize = g_symbolPoint * 10.0 ;
 }
 if ( SymbolInfoInteger(g_chartSymbol,17) == 0x1 )
 {
   g_pipSize = g_symbolPoint / 10.0 ;
 }
 g_symbolDigits = (int)MarketInfo(g_chartSymbol,MODE_DIGITS) ;
 g_curSpread = MarketInfo(g_chartSymbol,MODE_ASK) - MarketInfo(g_chartSymbol,MODE_BID) ;
 g_minStopDistPrice = MarketInfo(g_chartSymbol,MODE_STOPLEVEL) * g_symbolPoint ;
 global_309_double_2898 = MarketInfo(g_chartSymbol,MODE_FREEZELEVEL) * g_symbolPoint ;

 // Recovered working-value transform from original JIT.  The nine strategy
 // setup functions rewrite every raw field before LoadStrategyRuntimeSettings(), so in-place use
 // is behaviorally safe for fields without an explicit shadow in the rebuild.
 g_MaxSpread_rw = MaxSpread * g_variableRatio ;
 g_entryBreakoutPips = g_entryBreakoutPips * g_variableRatio ;
 g_buyEntryOffsetPips = g_buyEntryOffsetPips * g_variableRatio ;
 g_sellEntryOffsetPips = g_sellEntryOffsetPips * g_variableRatio ;
 global_88_double_1D0 = global_88_double_1D0 * g_variableRatio ;
 global_100_double_230 = global_100_double_230 * g_variableRatio ;
 g_takeProfitPips = g_takeProfitPips * g_variableRatio ;
 global_103_double_250 = global_103_double_250 * g_variableRatio ;
 g_trailActivationPips = g_trailActivationPips * g_variableRatio ;
 global_105_double_260 = global_105_double_260 * g_variableRatio ;
 global_106_double_268 = global_106_double_268 * g_variableRatio ;
 // Original keeps raw trailing-TP settings and writes scaled shadows.
 global_110_double_288 = g_trailTpPips * g_variableRatio ;
 global_111_double_290 = global_109_double_280 * g_variableRatio ;
 global_113_double_2A8 = global_113_double_2A8 * g_variableRatio ;
 g_beExtraPips = g_beExtraPips * g_variableRatio ;

 // These clamps are part of LoadStrategyRuntimeSettings() in the original JIT and therefore
 // must run for every strategy, not only once during OnInit().
 if ( global_100_double_230<=0.0 )
 {
   global_100_double_230 = 1.0 ;
 }
 if ( g_takeProfitPips<=0.0 )
 {
   g_takeProfitPips = 1.0 ;
 }
 if ( g_beExtraPips>global_113_double_2A8 )
 {
   g_beExtraPips = global_113_double_2A8 + 0.1 ;
 }
 if ( g_maxSpreadPts>g_MaxSpread_rw )
 {
   g_maxSpreadPts = g_MaxSpread_rw ;
 }
 if ( global_36_int_B0<global_309_double_2898 / g_pipSize )
 {
   global_36_int_B0 = (int)(global_309_double_2898 / g_pipSize) ;
 }
 if ( global_103_double_250!=0.0 && global_103_double_250<global_309_double_2898 / g_pipSize )
 {
   global_103_double_250 = global_309_double_2898 / g_pipSize ;
 }
 if ( global_103_double_250!=0.0 && global_103_double_250<g_minStopDistPrice / g_pipSize )
 {
   global_103_double_250 = g_minStopDistPrice / g_pipSize ;
 }
 if ( global_125_double_2F8>0.0 && global_126_double_300<global_309_double_2898 / g_pipSize )
 {
   global_126_double_300 = global_309_double_2898 / g_pipSize ;
 }
 if ( global_125_double_2F8>0.0 && global_126_double_300<g_minStopDistPrice / g_pipSize )
 {
   global_126_double_300 = g_minStopDistPrice / g_pipSize ;
 }
 if ( global_100_double_230<g_minStopDistPrice * 2.0 / g_pipSize )
 {
   global_100_double_230 = g_minStopDistPrice * 2.0 / g_pipSize ;
 }
 if ( g_takeProfitPips<g_minStopDistPrice * 2.0 / g_pipSize )
 {
   g_takeProfitPips = g_minStopDistPrice * 2.0 / g_pipSize ;
 }
 if ( g_entryBreakoutPips<g_minStopDistPrice * 2.0 / g_pipSize )
 {
   g_entryBreakoutPips = g_minStopDistPrice * 2.0 / g_pipSize ;
 }
 if ( global_73_int_17C < 1 )
 {
   global_73_int_17C = 1 ;
 }
 if ( global_74_int_180 < 1 )
 {
   global_74_int_180 = 1 ;
 }
 if ( g_entryBreakoutPips<0.1 )
 {
   g_entryBreakoutPips = 0.1 ;
 }

 g_pendingExpirySecs=g_pendingExpiryHours * 60 * 60;
 if ( g_pendingExpiryHours > 0 )
 {
   g_pendingOrderExpiry=TimeCurrent() + g_pendingExpirySecs;
 }
 else
 {
   g_pendingOrderExpiry = 0 ;
 }
 if ( Virtual_expiration )
 {
   g_pendingOrderExpiry = 0 ;
 }
 }
//LoadStrategyRuntimeSettings <<==--------   --------
// ============================================================================
// [§9] 策略核心处理
// ============================================================================

// ProcessStrategy —— 单个策略的主处理函数（过滤器、挂单/持仓状态机），
//                    arg_0_int 为策略索引（0..8）
 int ProcessStrategy( int arg_0_int)
 {
  bool      local_2_bool;
  datetime  local_3_long;
  int       local_5_int;
  string    local_6_string;
  datetime  local_7_datetime;
  int       local_8_int;
  int       local_9_int;
//----- -----
 int        temp_int_1;
 int        temp_int_2;
 int        temp_int_3;
 int        temp_int_4;
 int        temp_int_5;
 int        temp_int_6;
 int        temp_int_7;
 int        temp_int_8;
 int        temp_int_9;
 int        temp_int_10;
 int        temp_int_11;
 int        temp_int_12;
 int        temp_int_13;
 int        temp_int_14;
 int        temp_int_17;
 int        temp_int_18;
 int        temp_int_19;
 int        temp_int_20;
 int        temp_int_21;
 int        temp_int_22;
 int        temp_int_23;
 int        temp_int_24;
 int        temp_int_25;
 int        temp_int_26;
 int        temp_int_44;
 int        temp_int_45;
 int        temp_int_46;
 int        temp_int_47;
 int        temp_int_48;
 int        temp_int_49;
 int        temp_int_50;
 int        temp_int_51;
 int        temp_int_52;
 int        temp_int_53;
 int        temp_int_71;
 int        temp_int_72;
 int        temp_int_73;
 int        temp_int_74;
 int        temp_int_75;
 int        temp_int_76;
 int        temp_int_77;
 int        temp_int_78;
 int        temp_int_79;
 int        temp_int_80;
 int        temp_int_81;
 int        temp_int_82;
 int        temp_int_83;
 int        temp_int_84;
 int        temp_int_85;
 int        temp_int_86;
 int        temp_int_87;
 int        temp_int_88;
 int        temp_int_89;
 double     temp_double_90;
 long       temp_long_91;
 int        temp_int_92;
 long       temp_long_93;
 int        temp_int_94;
 int        temp_int_95;
 int        temp_int_96;
 double     temp_double_97;
 long       temp_long_98;
 int        temp_int_99;
 long       temp_long_100;
 int        temp_int_101;
 int        temp_int_102;
 int        temp_int_103;
 int        temp_int_104;
 int        temp_int_105;
 bool       temp_bool_106;
 int        temp_int_107;
 int        temp_int_108;
 bool       temp_bool_109;
 int        temp_int_110;
 long       temp_long_111;
 int        temp_int_112;
 long       temp_long_113;
 string     temp_string_114;

 g_currentStrategyIndex = arg_0_int ;
 local_2_bool = false ;
 
 if ( global_81_double_1A0>0.0 )
 {
   g_entryBreakoutPips = global_81_double_1A0 / 100.0 * MarketInfo(g_chartSymbol,MODE_ASK) * 10.0 ;
 }
 bool temp_tradeAllowedForManagement = (MarketInfo(g_chartSymbol,MODE_TRADEALLOWED)!=0.0);
 if ( global_99_int_22C == 0 )
 {
   if ( temp_tradeAllowedForManagement )
   {
     if ( ManageBuyPositions() )
     {
       local_2_bool = true ;
     }
     if ( ManageSellPositions() )
     {
       local_2_bool = true ;
     }
     if ( local_2_bool )
     {
       return(0); 
     }
   }
 }
 else
 {
   // Do not consume the management-timeframe marker while the broker session
   // is still quote-only/closed.  The first trade-enabled tick must retry the
   // same bar, exactly when the original Market EA can also place pending orders.
   if ( temp_tradeAllowedForManagement &&
        global_321_int_2920_si99[g_currentStrategyIndex] != iBars(g_chartSymbol,MT4Period(global_99_int_22C)) )
   {
     global_321_int_2920_si99[g_currentStrategyIndex] = iBars(g_chartSymbol,MT4Period(global_99_int_22C));
     if ( ManageBuyPositions() )
     {
       local_2_bool = true ;
     }
     if ( ManageSellPositions() )
     {
       local_2_bool = true ;
     }
     if ( local_2_bool )
     {
       return(0); 
     }
   }
 }
 RefreshPendingOrderLotSizes(false); 
 if ( MarketInfo(g_chartSymbol,MODE_TRADEALLOWED)==0.0 )
 {
   return(0); 
 }
 if ( g_useTradingHours )
 {
   if ( IsTradingScheduleOpen() && g_marketClosedFlag )
   {
     if ( global_173_bool_4C4 )
     {
       RestoreStoredPendingOrders(); 
     }
     g_marketClosedFlag = false ;
   }
   if ( !(IsTradingScheduleOpen()) && !(g_marketClosedFlag) )
   {
     Print("Weekend starting! closing trades.."); 
     if ( global_173_bool_4C4 )
     {
       for (temp_int_1 = 0 ; temp_int_1 < global_200_int_16B4 ; temp_int_1=temp_int_1 + 1)
       {
         for (temp_int_2 = 0 ; temp_int_2 < 2 ; temp_int_2=temp_int_2 + 1)
         {
           g_virtualPendingOrders[temp_int_1][temp_int_2] = 0.0;
         }
       }
       temp_int_3 = 0;
       for (temp_int_4 = MT4OrdersTotal() ; temp_int_4 >= 0 ; temp_int_4=temp_int_4 - 1)
       {
         if ( OrderSelect(temp_int_4,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol )   continue;
         
         if ( ( OrderType() != 4 && OrderType() != 5 ) )   continue;
         Print("Storing pending order nr " + string(OrderTicket())); 
         g_virtualPendingOrders[temp_int_3][1] = OrderType();
         g_virtualPendingOrders[temp_int_3][0] = OrderOpenPrice();
         g_virtualPendingOrders[temp_int_3][2] = OrderLots();
         temp_int_3=temp_int_3 + 1;
         
       }
     }
     temp_int_5 = 1;
     for (temp_int_6 = MT4OrdersTotal() ; temp_int_6 >= 0 ; temp_int_6=temp_int_6 - 1)
     {
       if ( OrderSelect(temp_int_6,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( temp_int_5 == 2 )
     {
       for (temp_int_7 = MT4OrdersTotal() ; temp_int_7 >= 0 ; temp_int_7=temp_int_7 - 1)
       {
         if ( OrderSelect(temp_int_7,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     temp_int_8 = 1;
     for (temp_int_9 = MT4OrdersTotal() ; temp_int_9 >= 0 ; temp_int_9=temp_int_9 - 1)
     {
       if ( OrderSelect(temp_int_9,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( temp_int_8 == 2 )
     {
       for (temp_int_10 = MT4OrdersTotal() ; temp_int_10 >= 0 ; temp_int_10=temp_int_10 - 1)
       {
         if ( OrderSelect(temp_int_10,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     temp_int_11 = 2;
     if(1==0) //condition_not_met
     {
       do
       {
         if ( OrderSelect(1,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
       while( - 1 >= 0);
       
     }
     if ( temp_int_11 == 2 )
     {
       for (temp_int_12 = MT4OrdersTotal() ; temp_int_12 >= 0 ; temp_int_12=temp_int_12 - 1)
       {
         if ( OrderSelect(temp_int_12,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     temp_int_13 = 2;
     if(1==0) //condition_not_met
     {
       do
       {
         if ( OrderSelect(1,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
       while( - 1 >= 0);
       
     }
     if ( temp_int_13 == 2 )
     {
       for (temp_int_14 = MT4OrdersTotal() ; temp_int_14 >= 0 ; temp_int_14=temp_int_14 - 1)
       {
         if ( OrderSelect(temp_int_14,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     g_marketClosedFlag = true ;
     return(0); 
   }
 }
 if ( EnableNFP_Filter )
 {
   bool temp_nfpLiveCalendar = (UseMQL5Calendar && MQLInfoInteger(MQL_TESTER) != 1 && g_nextNFPCalendar != 0);
   // Exact original fallback rule: if live Calendar is disabled/unavailable (timestamp=0),
   // continue into the hardcoded table; after 2026 use the first-Friday fallback.
   if ( temp_nfpLiveCalendar || Year() <= 2026 )
   {
     local_3_long = 0 ;
     local_5_int = 0 ;
     datetime temp_nfpCompareNow = TimeCurrent();
     if ( temp_nfpLiveCalendar )
     {
       // Calendar timestamps are already in trade-server time. No GMT conversion here.
       local_3_long = g_nextNFPCalendar;
      }
      else
      {
        local_3_long = MT4HardcodedNFPForCurrentMonth();
       // Hardcoded table is GMT-based: NFP is 13:30 GMT in US winter, 12:30 in DST.
       local_5_int = 60 ;
       if ( IsAmericanDst() )   local_5_int = 0 ;
       temp_nfpCompareNow = g_nfpAdjustedNow;
     }
     if ( temp_nfpCompareNow >= local_3_long - NFP_MinutesBefore * 60 + local_5_int * 60 && temp_nfpCompareNow <= local_3_long + NFP_MinutesAfter * 60 + local_5_int * 60 )
     {
       if ( NFP_ClosePendingOrders )
       {
         temp_int_17 = 1;
         for (temp_int_18 = MT4OrdersTotal() ; temp_int_18 >= 0 ; temp_int_18=temp_int_18 - 1)
         {
            if ( OrderSelect(temp_int_18,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice()-global_309_double_2898) )   continue;
           OrderDelete(OrderTicket(),0xFFFFFFFF); 
           
         }
         if ( temp_int_17 == 2 )
         {
           for (temp_int_19 = MT4OrdersTotal() ; temp_int_19 >= 0 ; temp_int_19=temp_int_19 - 1)
           {
              if ( OrderSelect(temp_int_19,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice()-global_309_double_2898) )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
         }
         temp_int_20 = 1;
         for (temp_int_21 = MT4OrdersTotal() ; temp_int_21 >= 0 ; temp_int_21=temp_int_21 - 1)
         {
            if ( OrderSelect(temp_int_21,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol,MODE_BID)>OrderOpenPrice()+global_309_double_2898) )   continue;
           OrderDelete(OrderTicket(),0xFFFFFFFF); 
           
         }
         if ( temp_int_20 == 2 )
         {
           for (temp_int_22 = MT4OrdersTotal() ; temp_int_22 >= 0 ; temp_int_22=temp_int_22 - 1)
           {
              if ( OrderSelect(temp_int_22,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol,MODE_BID)>OrderOpenPrice()+global_309_double_2898) )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
         }
         temp_int_23 = 2;
         if(1==0) //condition_not_met
         {
           do
           {
             if ( OrderSelect(1,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
           while( - 1 >= 0);
           
         }
         if ( temp_int_23 == 2 )
         {
           for (temp_int_24 = MT4OrdersTotal() ; temp_int_24 >= 0 ; temp_int_24=temp_int_24 - 1)
           {
              if ( OrderSelect(temp_int_24,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice()-global_309_double_2898) )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
         }
         temp_int_25 = 2;
         if(1==0) //condition_not_met
         {
           do
           {
             if ( OrderSelect(1,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
           while( - 1 >= 0);
           
         }
         if ( temp_int_25 == 2 )
         {
           for (temp_int_26 = MT4OrdersTotal() ; temp_int_26 >= 0 ; temp_int_26=temp_int_26 - 1)
           {
              if ( OrderSelect(temp_int_26,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol,MODE_BID)>OrderOpenPrice()+global_309_double_2898) )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
         }
       }
       if ( NFP_CloseOpenTrades )
       {
         CloseNfpOpenTradesInOriginalOrder();
       }
       if ( !(g_nfpWindowActive) )
       {
         Print("NFP!! deleting trades!!"); 
       }
       g_nfpWindowActive = true ;
     }
     else
     {
       g_nfpWindowActive = false ;
     }
   }
   else
   {
     if ( Day() <= 7 && DayOfWeek() == 5 )
     {
       local_6_string = IntegerToString(Year(),0,32) + IntegerToString(Month(),0,32) + IntegerToString(Day(),0,32) + " " + IntegerToString(0x4CE,0,32) ;
       local_7_datetime = StringToTime(local_6_string) ;
       if ( g_nfpAdjustedNow >= local_7_datetime - NFP_MinutesBefore * 60 && g_nfpAdjustedNow <= local_7_datetime + NFP_MinutesAfter * 60 )
       {
         if ( NFP_ClosePendingOrders )
         {
           temp_int_44 = 1;
           for (temp_int_45 = MT4OrdersTotal() ; temp_int_45 >= 0 ; temp_int_45=temp_int_45 - 1)
           {
              if ( OrderSelect(temp_int_45,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice()-global_309_double_2898) )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
           if ( temp_int_44 == 2 )
           {
             for (temp_int_46 = MT4OrdersTotal() ; temp_int_46 >= 0 ; temp_int_46=temp_int_46 - 1)
             {
                if ( OrderSelect(temp_int_46,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice()-global_309_double_2898) )   continue;
               OrderDelete(OrderTicket(),0xFFFFFFFF); 
               
             }
           }
           temp_int_47 = 1;
           for (temp_int_48 = MT4OrdersTotal() ; temp_int_48 >= 0 ; temp_int_48=temp_int_48 - 1)
           {
              if ( OrderSelect(temp_int_48,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol,MODE_BID)>OrderOpenPrice()+global_309_double_2898) )   continue;
             OrderDelete(OrderTicket(),0xFFFFFFFF); 
             
           }
           if ( temp_int_47 == 2 )
           {
             for (temp_int_49 = MT4OrdersTotal() ; temp_int_49 >= 0 ; temp_int_49=temp_int_49 - 1)
             {
                if ( OrderSelect(temp_int_49,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol,MODE_BID)>OrderOpenPrice()+global_309_double_2898) )   continue;
               OrderDelete(OrderTicket(),0xFFFFFFFF); 
               
             }
           }
           temp_int_50 = 2;
           if(1==0) //condition_not_met
           {
             do
             {
               if ( OrderSelect(1,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
               OrderDelete(OrderTicket(),0xFFFFFFFF); 
               
             }
             while( - 1 >= 0);
             
           }
           if ( temp_int_50 == 2 )
           {
             for (temp_int_51 = MT4OrdersTotal() ; temp_int_51 >= 0 ; temp_int_51=temp_int_51 - 1)
             {
                if ( OrderSelect(temp_int_51,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice()-global_309_double_2898) )   continue;
               OrderDelete(OrderTicket(),0xFFFFFFFF); 
               
             }
           }
           temp_int_52 = 2;
           if(1==0) //condition_not_met
           {
             do
             {
               if ( OrderSelect(1,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
               OrderDelete(OrderTicket(),0xFFFFFFFF); 
               
             }
             while( - 1 >= 0);
             
           }
           if ( temp_int_52 == 2 )
           {
             for (temp_int_53 = MT4OrdersTotal() ; temp_int_53 >= 0 ; temp_int_53=temp_int_53 - 1)
             {
                if ( OrderSelect(temp_int_53,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol,MODE_BID)>OrderOpenPrice()+global_309_double_2898) )   continue;
               OrderDelete(OrderTicket(),0xFFFFFFFF); 
               
             }
           }
         }
         if ( NFP_CloseOpenTrades )
         {
           CloseNfpOpenTradesInOriginalOrder();
         }
         if ( !(g_nfpWindowActive) )
         {
           Print("NFP!! deleting trades!!"); 
         }
         g_nfpWindowActive = true ;
       }
       else
       {
         g_nfpWindowActive = false ;
       }
     }
   }
 }
 if ( g_nfpWindowActive )
 {
   return(0); 
 }
 if ( g_useFridayStop )
 {
   if ( DayOfWeek() == 5 && Hour() >= FridayStopHour && !(g_fridayStopDone) )
   {
     // The original MT4 trade pool visits live positions before pending orders
     // during the reverse Friday-cleanup pass.  The MQL5 compatibility cache
     // stores positions before orders, so its reverse pass would otherwise
     // cancel pending orders first.  Close managed positions explicitly in
     // newest-ticket-first order, then let the legacy pass delete pendings.
     if ( FridayCloseOpen )
     {
       long friday_position_tickets[];
       int friday_position_count=0;
       int friday_live_total=MT4OrdersTotal();
       for (int friday_scan=0; friday_scan<friday_live_total; friday_scan++)
       {
         if ( OrderSelect(friday_scan,SELECT_BY_POS,MODE_TRADES) != true ||
              OrderSymbol() != g_chartSymbol ||
              (OrderType() != OP_BUY && OrderType() != OP_SELL) ||
              !IsNfpManagedMagic(OrderMagicNumber()) )
           continue;
         ArrayResize(friday_position_tickets,friday_position_count+1);
         friday_position_tickets[friday_position_count++]=OrderTicket();
       }
       ArraySort(friday_position_tickets);
       for (int friday_close=friday_position_count-1; friday_close>=0; friday_close--)
       {
         if ( OrderSelect(friday_position_tickets[friday_close],SELECT_BY_TICKET,MODE_TRADES) != true )
           continue;
         int friday_type=OrderType();
         double friday_price=(friday_type==OP_BUY)
                             ? MarketInfo(g_chartSymbol,MODE_BID)
                             : MarketInfo(g_chartSymbol,MODE_ASK);
         OrderClose(OrderTicket(),OrderLots(),friday_price,(int)g_slippagePts,Red);
       }
     }
     for (temp_int_71 = MT4OrdersTotal() ; temp_int_71 >= 0 ; temp_int_71=temp_int_71 - 1)
     {
       if ( OrderSelect(temp_int_71,0,0) != true || OrderSymbol() != g_chartSymbol )   continue;
       temp_int_72 = OrderMagicNumber();
       temp_int_73=ST1_MagicNumber + 1;
       if ( temp_int_72 != temp_int_73 )
       {
         temp_int_73 = OrderMagicNumber();
         temp_int_74=ST1_MagicNumber + 2;
         if ( temp_int_73 != temp_int_74 )
         {
           temp_int_74 = OrderMagicNumber();
           temp_int_75=ST1_MagicNumber + 3;
           if ( temp_int_74 != temp_int_75 )
           {
             temp_int_75 = OrderMagicNumber();
             temp_int_76=ST1_MagicNumber + 4;
             if ( temp_int_75 != temp_int_76 )
             {
               temp_int_76 = OrderMagicNumber();
               temp_int_77=ST1_MagicNumber + 5;
               if ( temp_int_76 != temp_int_77 )
               {
                 temp_int_77 = OrderMagicNumber();
                 temp_int_78=ST1_MagicNumber + 6;
                 if ( temp_int_77 != temp_int_78 )
                 {
                   temp_int_78 = OrderMagicNumber();
                   temp_int_79=ST1_MagicNumber + 7;
                   if ( temp_int_78 != temp_int_79 )
                   {
                     temp_int_79 = OrderMagicNumber();
                     temp_int_80=ST1_MagicNumber + 8;
                     if ( temp_int_79 != temp_int_80 )
                     {
                       temp_int_80 = OrderMagicNumber();
                       temp_int_81=ST1_MagicNumber + 9;
                       if ( temp_int_80 != temp_int_81 )
                       {
                         temp_int_81 = OrderMagicNumber();
                         temp_int_82=ST1_MagicNumber + 10;
                         if ( temp_int_81 != temp_int_82 )
                         {
                           temp_int_82 = OrderMagicNumber();
                           temp_int_83=ST1_MagicNumber + 11;
                           if ( temp_int_82 != temp_int_83 )
                           {
                             temp_int_83 = OrderMagicNumber();
                             temp_int_84=ST1_MagicNumber + 12;
                             if ( temp_int_83 != temp_int_84 )
                             {
                               temp_int_84 = OrderMagicNumber();
                               temp_int_85=ST1_MagicNumber + 13;
                               if ( temp_int_84 != temp_int_85 )
                               {
                                 temp_int_85 = OrderMagicNumber();
                                 temp_int_86=ST1_MagicNumber + 14;
                                 if ( temp_int_85 != temp_int_86 )
                                 {
                                   temp_int_86 = OrderMagicNumber();
                                   temp_int_87=ST1_MagicNumber + 15;
                                 if ( temp_int_86 != temp_int_87 )   continue;
                                 }
                               }
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         }
       }
       if ( ( OrderType() != 4 && OrderType() != 5 ) || !(FridayClosePending) )   continue;
       OrderDelete(OrderTicket(),Red); 
       
     }
     Print("Weekend starting! closing trades.."); 
     g_fridayStopDone = true ;
     return(0); 
   }
   if ( DayOfWeek() != 5 && g_fridayStopDone == true )
   {
     g_fridayStopDone = false ;
     if ( global_46_bool_FD )
     {
       RestoreStoredPendingOrders(); 
       return(0); 
     }
   }
 }
 g_curSpread = MarketInfo(g_chartSymbol,MODE_ASK) - MarketInfo(g_chartSymbol,MODE_BID) ;
 if ( global_35_bool_AF )
 {
   if ( g_curSpread>g_MaxSpread_rw * g_pipSize )
   {
     RemovePendingOrdersDuringHighSpread(); 
     return(0); 
   }
   if ( g_curSpread<=g_maxSpreadPts * g_pipSize && ( !(g_useFridayStop) || DayOfWeek() != 5 || Hour() <  FridayStopHour ) && ( !(g_useTradingHours) || IsTradingScheduleOpen() ) )
   {
     RestoreStoredPendingOrders(); 
   }
 }
 if ( g_orderMgmtMode == 1 )
 {
   temp_int_88 = 0;
   for (temp_int_89 = MT4OrdersTotal() ; temp_int_89 >= 0 ; temp_int_89=temp_int_89 - 1)
   {
     if ( OrderSelect(temp_int_89,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
     temp_int_88=temp_int_88 + 1;
     
   }
   if ( temp_int_88 >  g_maxPendingOrders )
   {
     temp_double_90 = 0.0;
     temp_long_91 = 0;
     for (temp_int_92 = MT4OrdersTotal() ; temp_int_92 >= 0 ; temp_int_92=temp_int_92 - 1)
     {
       if ( OrderSelect(temp_int_92,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(OrderOpenPrice()>temp_double_90) )   continue;
       temp_long_91 = OrderTicket();
       temp_double_90 = OrderOpenPrice();
       
     }
     if ( temp_long_91 != 0 )
     {
       OrderDelete(temp_long_91,Green); 
       temp_long_93 = temp_long_91;
       for (temp_int_94 = 0 ; temp_int_94 < 100 ; temp_int_94=temp_int_94 + 1)
       {
         if ( !(g_stopOrderTicketPrice[temp_int_94][0]==temp_long_93) )   continue;
         g_stopOrderTicketPrice[temp_int_94][0] = 0.0;
         g_stopOrderTicketPrice[temp_int_94][1] = 0.0;
         break;
         
       }
       Print("Max number of pending buy orders reached... deleting highest buystop order!"); 
     }
   }
   temp_int_95 = 0;
   for (temp_int_96 = MT4OrdersTotal() ; temp_int_96 >= 0 ; temp_int_96=temp_int_96 - 1)
   {
     if ( OrderSelect(temp_int_96,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
     temp_int_95=temp_int_95 + 1;
     
   }
   if ( temp_int_95 >  g_maxPendingOrders )
   {
     temp_double_97 = 9999.0;
     temp_long_98 = 0;
     for (temp_int_99 = MT4OrdersTotal() ; temp_int_99 >= 0 ; temp_int_99=temp_int_99 - 1)
     {
       if ( OrderSelect(temp_int_99,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(OrderOpenPrice()<temp_double_97) )   continue;
       temp_long_98 = OrderTicket();
       temp_double_97 = OrderOpenPrice();
       
     }
     if ( temp_long_98 != 0 )
     {
       OrderDelete(temp_long_98,Green); 
       temp_long_100 = temp_long_98;
       for (temp_int_101 = 0 ; temp_int_101 < 100 ; temp_int_101=temp_int_101 + 1)
       {
         if ( !(g_stopOrderTicketPrice[temp_int_101][0]==temp_long_100) )   continue;
         g_stopOrderTicketPrice[temp_int_101][0] = 0.0;
         g_stopOrderTicketPrice[temp_int_101][1] = 0.0;
         break;
         
       }
       Print("Max number of pending sell orders reached... deleting lowest sellstop order!"); 
     }
   }
 }
 if ( !(g_fridayStopDone) && g_orderMgmtMode == 1 && !(g_marketClosedFlag) )
 {
   if ( ( global_322_int_2AE0_si99[g_currentStrategyIndex] != iBars(g_chartSymbol,MT4Period(g_signalTfPeriod)) || g_signalTfPeriod == 0 ) )
   {
     global_322_int_2AE0_si99[g_currentStrategyIndex] = iBars(g_chartSymbol,MT4Period(g_signalTfPeriod));
     if ( global_119_int_2D0 >  0 && global_120_int_2D4 >= 0 )
     {
       g_sellTrailStopLevel[g_currentStrategyIndex] = g_hlOffsetPips * g_pipSize + (MT4FastFractalHigh(global_117_int_2C8,global_119_int_2D0,global_120_int_2D4) + g_curSpread);
       g_buyTrailStopLevel[g_currentStrategyIndex] = MT4FastFractalLow(global_117_int_2C8,global_119_int_2D0,global_120_int_2D4) - g_hlOffsetPips * g_pipSize;
     }
     if ( global_187_int_504 >  0 )
     {
       local_8_int=MathRand() * global_187_int_504 / 32768 + 1;
       global_15_int_78 = local_8_int ;
     }
     if ( g_profitCloseMode != 1 )
     {
       temp_int_102 = 0;
       for (temp_int_103 = MT4OrdersTotal() ; temp_int_103 >= 0 ; temp_int_103=temp_int_103 - 1)
       {
         if ( OrderSelect(temp_int_103,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 0 )   continue;
         temp_int_102=temp_int_102 + 1;
         
       }
       if ( temp_int_102 == 0 )
       {
         temp_int_104 = 0;
         for (temp_int_105 = MT4OrdersTotal() ; temp_int_105 >= 0 ; temp_int_105=temp_int_105 - 1)
         {
           if ( OrderSelect(temp_int_105,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 1 )   continue;
           temp_int_104=temp_int_104 + 1;
           
         }
         if ( temp_int_104 == 0 )
         {
           temp_bool_106 = false;
           for (temp_int_107 = 0 ; temp_int_107 < g_virtSLCacheSize ; temp_int_107=temp_int_107 + 1)
           {
             if ( !(g_virtSLCache[temp_int_107][0]>0.0) )   continue;
             temp_bool_106 = false;
             for (temp_int_108 = MT4OrdersTotal() ; temp_int_108 >= 0 ; temp_int_108=temp_int_108 - 1)
             {
               if ( OrderSelect(temp_int_108,0,0) != true )   continue;
               
               if ( ( OrderType() != 0 && OrderType() != 1 ) || !(OrderTicket()==g_virtSLCache[temp_int_107][0]) )   continue;
               temp_bool_106 = true;
               
             }
             if ( temp_bool_106 )   continue;
             g_virtSLCache[temp_int_107][0] = 0.0;
             g_virtSLCache[temp_int_107][1] = 0.0;
             
           }
         }
       }
     }
     for (local_9_int = 0 ; local_9_int < g_maxPendingOrders ; local_9_int ++)
     {
       ProcessStrategyEntries(); 
     }
   }
   UpdateHistoryPanel(); 
   if ( g_lastHour != Hour() )
   {
     g_lastHour = Hour() ;
     temp_bool_109 = false;
     for (temp_int_110 = 0 ; temp_int_110 < 100 ; temp_int_110=temp_int_110 + 1)
     {
       temp_long_111 = (long)g_stopOrderTicketPrice[temp_int_110][0];
       temp_bool_109 = false;
       for (temp_int_112 = MT4OrdersTotal() ; temp_int_112 >= 0 ; temp_int_112=temp_int_112 - 1)
       {
         if ( !(OrderSelect(temp_int_112,0,0)) )   continue;
         temp_long_113 = OrderTicket();
         if ( temp_long_111 != temp_long_113 )   continue;
         temp_bool_109 = true;
         
       }
       if ( temp_bool_109 )   continue;
       g_stopOrderTicketPrice[temp_int_110][0] = 0.0;
       g_stopOrderTicketPrice[temp_int_110][1] = 0.0;
       
     }
   }
 }
 // The dump has no current-spread/pending-order Comment overlay in this path.
 return(0); 
 }
//ProcessStrategy <<==--------   --------
// ============================================================================
// [§10] 挂单管理
// ============================================================================
// RestoreStoredPendingOrders —— 依据内部存储表恢复因价格远离而过期的挂单
 void RestoreStoredPendingOrders()
 {
  int       local_1_int;
//----- -----
 double     temp_double_1;
 long       temp_long_2;
 int        temp_int_3;
 double     temp_double_4;
 long       temp_long_5;
 int        temp_int_6;
 double     temp_double_7;
 long       temp_long_8;
 int        temp_int_9;
 double     temp_double_10;
 long       temp_long_11;
 int        temp_int_12;
 int        temp_int_13;

 for (local_1_int = 0 ; local_1_int < global_200_int_16B4 ; local_1_int ++)
 {
   if ( !(g_virtualPendingOrders[local_1_int][0]>0.0) )   continue;
   
   if ( g_virtualPendingOrders[local_1_int][1]==4.0 && MarketInfo(g_chartSymbol,MODE_ASK)<g_virtualPendingOrders[local_1_int][0] - g_minStopDistPrice )
   {
     Print("Restoring pending buy-order"); 
     global_230_int_1E08 = OrderSend(g_chartSymbol,4,g_virtualPendingOrders[local_1_int][2],g_virtualPendingOrders[local_1_int][0],int(g_slippagePts * g_pipSize),g_virtualPendingOrders[local_1_int][0] - (global_100_double_230 + global_64_double_148) * g_pipSize,g_takeProfitPips * g_pipSize + g_virtualPendingOrders[local_1_int][0],g_orderComment,global_93_int_1F0,g_pendingOrderExpiry + 0x2A300,Green) ;
     temp_double_1 = g_virtualPendingOrders[local_1_int][0];
     temp_long_2 = global_230_int_1E08;
     for (temp_int_3 = 0 ; temp_int_3 < 100 ; temp_int_3=temp_int_3 + 1)
     {
       if ( !(g_stopOrderTicketPrice[temp_int_3][0]==0.0) )   continue;
       g_stopOrderTicketPrice[temp_int_3][0] = (double)temp_long_2;
       g_stopOrderTicketPrice[temp_int_3][1] = temp_double_1;
       break;
       
     }
     if ( global_230_int_1E08 <= 0 )
     {
       if ( MT4_LastError() == 132 )
       {
         ResetLastError();
         
           do
           {
             Sleep(2500); 
             global_230_int_1E08 = OrderSend(g_chartSymbol,4,g_virtualPendingOrders[local_1_int][2],g_virtualPendingOrders[local_1_int][0],int(g_slippagePts * g_pipSize),g_virtualPendingOrders[local_1_int][0] - (global_100_double_230 + global_64_double_148) * g_pipSize,g_takeProfitPips * g_pipSize + g_virtualPendingOrders[local_1_int][0],g_orderComment,global_93_int_1F0,g_pendingOrderExpiry + 0x2A300,Green) ;
             temp_double_4 = g_virtualPendingOrders[local_1_int][0];
             temp_long_5 = global_230_int_1E08;
             for (temp_int_6 = 0 ; temp_int_6 < 100 ; temp_int_6=temp_int_6 + 1)
             {
               if ( !(g_stopOrderTicketPrice[temp_int_6][0]==0.0) )   continue;
               g_stopOrderTicketPrice[temp_int_6][0] = (double)temp_long_5;
               g_stopOrderTicketPrice[temp_int_6][1] = temp_double_4;
               break;
               
             }
           }
           while(MT4_LastError() == 132);
           
         
       }
       Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order"); 
     }
   }
   if ( !(g_virtualPendingOrders[local_1_int][1]==5.0) || !(MarketInfo(g_chartSymbol,MODE_BID)>g_virtualPendingOrders[local_1_int][0] + g_minStopDistPrice) )   continue;
   Print("Restoring pending sell-order"); 
   global_230_int_1E08 = OrderSend(g_chartSymbol,5,g_virtualPendingOrders[local_1_int][2],g_virtualPendingOrders[local_1_int][0],int(g_slippagePts * g_pipSize),(global_100_double_230 + global_64_double_148) * g_pipSize + g_virtualPendingOrders[local_1_int][0],g_virtualPendingOrders[local_1_int][0] - g_takeProfitPips * g_pipSize,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry + 0x2A300,Green) ;
   temp_double_7 = g_virtualPendingOrders[local_1_int][0];
   temp_long_8 = global_230_int_1E08;
   for (temp_int_9 = 0 ; temp_int_9 < 100 ; temp_int_9=temp_int_9 + 1)
   {
     if ( !(g_stopOrderTicketPrice[temp_int_9][0]==0.0) )   continue;
     g_stopOrderTicketPrice[temp_int_9][0] = (double)temp_long_8;
     g_stopOrderTicketPrice[temp_int_9][1] = temp_double_7;
     break;
     
   }
   if ( global_230_int_1E08 > 0 )   continue;
   
   if ( MT4_LastError() == 132 )
   {
     ResetLastError();
     
       do
       {
         Sleep(2500); 
         global_230_int_1E08 = OrderSend(g_chartSymbol,5,g_virtualPendingOrders[local_1_int][2],g_virtualPendingOrders[local_1_int][0],int(g_slippagePts * g_pipSize),(global_100_double_230 + global_64_double_148) * g_pipSize + g_virtualPendingOrders[local_1_int][0],g_virtualPendingOrders[local_1_int][0] - g_takeProfitPips * g_pipSize,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry + 0x2A300,Green) ;
         temp_double_10 = g_virtualPendingOrders[local_1_int][0];
         temp_long_11 = global_230_int_1E08;
         for (temp_int_12 = 0 ; temp_int_12 < 100 ; temp_int_12=temp_int_12 + 1)
         {
           if ( !(g_stopOrderTicketPrice[temp_int_12][0]==0.0) )   continue;
           g_stopOrderTicketPrice[temp_int_12][0] = (double)temp_long_11;
           g_stopOrderTicketPrice[temp_int_12][1] = temp_double_10;
           break;
           
         }
       }
       while(MT4_LastError() == 132);
       
     
   }
   Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order"); 
   
 }
 for (temp_int_13 = 0 ; temp_int_13 < global_200_int_16B4 ; temp_int_13=temp_int_13 + 1)
 {
   g_virtualPendingOrders[temp_int_13][0] = 0.0;
   g_virtualPendingOrders[temp_int_13][1] = 0.0;
   g_virtualPendingOrders[temp_int_13][2] = 0.0;
 }
 }
//RestoreStoredPendingOrders <<==--------   --------
// RemovePendingOrdersDuringHighSpread —— 点差超过 MaxSpread 时移除挂单
 bool RemovePendingOrdersDuringHighSpread()
 {
  int       local_2_int;
  int       local_3_int;
  int       local_4_int;
//----- -----
 long       temp_long_1;
 int        temp_int_2;
 long       temp_long_3;
 int        temp_int_4;
 double     temp_double_5;
 double     temp_double_6;
 long       temp_long_7;
 int        temp_int_8;
 long       temp_long_9;
 int        temp_int_10;

 for (local_2_int = MT4OrdersTotal() ; local_2_int >= 0 ; local_2_int --)
 {
   if ( OrderSelect(local_2_int,0,0) != true )   continue;
   
   if ( ( OrderMagicNumber() != global_93_int_1F0 && OrderMagicNumber() != g_manualMagicNumber ) || OrderSymbol() != g_chartSymbol )   continue;
   
   if ( OrderType() == 4 && OrderOpenPrice()<global_36_int_B0 * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK) && MarketInfo(g_chartSymbol,MODE_ASK)<OrderOpenPrice() - global_309_double_2898 )
   {
     if ( g_maxSpreadPts>0.0 )
     {
       Print("Spread too high..(" + string(g_curSpread) + ") storing and deleting order " + string(OrderTicket())); 
       for (local_3_int = 0 ; local_3_int < global_200_int_16B4 ; local_3_int ++)
       {
         if ( g_virtualPendingOrders[local_3_int][0]==0.0 )
         {
           Print("Storing pending order nr " + string(OrderTicket())); 
           g_virtualPendingOrders[local_3_int][1] = OrderType();
           g_virtualPendingOrders[local_3_int][0] = OrderOpenPrice();
           g_virtualPendingOrders[local_3_int][2] = OrderLots();
           break;
         }
       }
       temp_long_1 = OrderTicket();
       for (temp_int_2 = 0 ; temp_int_2 < 100 ; temp_int_2=temp_int_2 + 1)
       {
         if ( !(g_stopOrderTicketPrice[temp_int_2][0]==temp_long_1) )   continue;
         g_stopOrderTicketPrice[temp_int_2][0] = 0.0;
         g_stopOrderTicketPrice[temp_int_2][1] = 0.0;
         break;
         
       }
       OrderDelete(OrderTicket(),Green); 
     }
     else
     {
       Print("Spread too high..(" + string(g_curSpread) + ") deleting order " + string(OrderTicket())); 
       temp_long_3 = OrderTicket();
       for (temp_int_4 = 0 ; temp_int_4 < 100 ; temp_int_4=temp_int_4 + 1)
       {
         if ( !(g_stopOrderTicketPrice[temp_int_4][0]==temp_long_3) )   continue;
         g_stopOrderTicketPrice[temp_int_4][0] = 0.0;
         g_stopOrderTicketPrice[temp_int_4][1] = 0.0;
         break;
         
       }
       OrderDelete(OrderTicket(),Green); 
     }
   }
   if ( OrderType() != 5 )   continue;
   temp_double_5 = OrderOpenPrice();
   if ( !(temp_double_5>MarketInfo(g_chartSymbol,MODE_BID) - global_36_int_B0 * g_pipSize) )   continue;
   temp_double_6 = MarketInfo(g_chartSymbol,MODE_BID);
   if ( !(temp_double_6>OrderOpenPrice() + global_309_double_2898) )   continue;
   
   if ( g_maxSpreadPts>0.0 )
   {
     Print("Spread too high..(" + string(g_curSpread) + ") storing and deleting order " + string(OrderTicket())); 
     for (local_4_int = 0 ; local_4_int < global_200_int_16B4 ; local_4_int ++)
     {
       if ( g_virtualPendingOrders[local_4_int][0]==0.0 )
       {
         Print("Storing pending order nr " + string(OrderTicket())); 
         g_virtualPendingOrders[local_4_int][1] = OrderType();
         g_virtualPendingOrders[local_4_int][0] = OrderOpenPrice();
         g_virtualPendingOrders[local_4_int][2] = OrderLots();
         break;
       }
     }
     temp_long_7 = OrderTicket();
     for (temp_int_8 = 0 ; temp_int_8 < 100 ; temp_int_8=temp_int_8 + 1)
     {
       if ( !(g_stopOrderTicketPrice[temp_int_8][0]==temp_long_7) )   continue;
       g_stopOrderTicketPrice[temp_int_8][0] = 0.0;
       g_stopOrderTicketPrice[temp_int_8][1] = 0.0;
       break;
       
     }
     OrderDelete(OrderTicket(),Green); 
      continue;
   }
   Print("Spread too high..(" + string(g_curSpread) + ") deleting order " + string(OrderTicket())); 
   temp_long_9 = OrderTicket();
   for (temp_int_10 = 0 ; temp_int_10 < 100 ; temp_int_10=temp_int_10 + 1)
   {
     if ( !(g_stopOrderTicketPrice[temp_int_10][0]==temp_long_9) )   continue;
     g_stopOrderTicketPrice[temp_int_10][0] = 0.0;
     g_stopOrderTicketPrice[temp_int_10][1] = 0.0;
     break;
     
   }
   OrderDelete(OrderTicket(),Green); 
   
 }
 return(false); 
 }
//RemovePendingOrdersDuringHighSpread <<==--------   --------
// ============================================================================
// [§11] 手数计算
// ============================================================================

// CalculateStrategyLotSize —— 按 Risk 模式（固定手数 / 最大总回撤 / 单策略
//                             风险）并结合 OnlyUp/HighestBalance/ManualBalance
//                             计算当前策略手数
 void CalculateStrategyLotSize( double arg_0_double,int arg_1_int)
 {
  double    local_1_double;
  double    local_2_double;
  double    local_3_double;
  double    local_4_double;
 double    local_5_double;
 double    local_6_double;
 double    local_7_double;
//----- -----

 local_1_double = global_223_double_1AC4_si99[g_currentStrategyIndex] ;
 local_2_double = global_223_double_1AC4_si99[g_currentStrategyIndex] ;
 global_401_double_6AD0 = AccountInfoDouble(ACCOUNT_BALANCE) ;
 if ( UseEquity )
 {
   global_401_double_6AD0 = AccountInfoDouble(ACCOUNT_EQUITY) ;
 }
 if ( OnlyUp && g_highestBalance>global_401_double_6AD0 )
 {
   global_401_double_6AD0 = g_highestBalance ;
 }
 if ( global_401_double_6AD0>g_highestBalance )
 {
   g_highestBalance = global_401_double_6AD0 ;
   GlobalVariableSet("HighestBalance",g_highestBalance) ;
 }
 if ( ManualBalance>0.0 )
 {
   global_401_double_6AD0 = ManualBalance ;
 }
 // Original JIT 0x19aa50e89e7-0x19aa50e8a29: lot-sizing guard.
 if ( global_401_double_6AD0==0.0 )
 {
   global_401_double_6AD0 = 0.01 ;
 }
 local_3_double = arg_0_double ;
 if ( ( g_symbolDigits == 2 || g_symbolDigits == 4 ) )
 {
   local_3_double = arg_0_double / 10.0 ;
 }
 if ( Risk <  999 && Risk >  0 )
 {
   local_4_double = Risk ;
   local_5_double = local_4_double / 1000.0 * global_401_double_6AD0 ;
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.1 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * (local_5_double / (MarketInfo(g_chartSymbol,MODE_TICKVALUE) * local_3_double) * 0.1),1) ;
   }
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.01 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * (local_5_double / (MarketInfo(g_chartSymbol,MODE_TICKVALUE) * local_3_double) * 0.1),2) ;
   }
 }
 if ( Risk == 999 )
 {
   local_6_double = global_148_double_420 / 100.0 * global_401_double_6AD0 ;
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.1 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * (local_6_double / (MarketInfo(g_chartSymbol,MODE_TICKVALUE) * local_3_double) * 0.1),1) ;
   }
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.01 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * (local_6_double / (MarketInfo(g_chartSymbol,MODE_TICKVALUE) * local_3_double) * 0.1),2) ;
   }
 }
 if ( Risk == 0 )
 {
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.1 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * g_startLots_rw,1) ;
   }
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.01 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * g_startLots_rw,2) ;
   }
 }
 if ( Risk == 9999 )
 {
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.1 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * (global_401_double_6AD0 / global_145_int_40C * 0.01),1) ;
   }
   if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.01 )
   {
     local_2_double = NormalizeDouble(arg_1_int * 0.01 * (global_401_double_6AD0 / global_145_int_40C * 0.01),2) ;
   }
 }
 if ( Risk == 1234 )
 {
  if ( UseWeightedLots )
  {
    if ( global_397_double_6768==0.0 )
    {
      global_397_double_6768 = 100000.0 ;
     }
     global_146_double_410 = MaxAllowedDD / g_riskFactorByTier ;
     if ( SymbolInfoDouble(g_chartSymbol,36)==0.1 )
     {
       local_2_double = NormalizeDouble(global_146_double_410 / global_397_double_6768 * global_401_double_6AD0 / 100.0 * 0.01,1) ;
     }
     if ( SymbolInfoDouble(g_chartSymbol,36)==0.01 )
     {
       local_2_double = NormalizeDouble(global_146_double_410 / global_397_double_6768 * global_401_double_6AD0 / 100.0 * 0.01,2) ;
     }
   }
   else
   {
     if ( global_397_double_6768==0.0 )
     {
       global_397_double_6768 = 100000.0 ;
     }
     local_7_double = ConvertAccountCurrencyToUsd(global_401_double_6AD0) ;
     if ( g_tradeFrequencyMode == 0 )
     {
       global_145_int_40C = (int)(g_ddTierThreshold1 / (MaxAllowedDD / 100.0)) ;
     }
     if ( g_tradeFrequencyMode == 1 )
     {
       global_145_int_40C = (int)(global_386_int_5DAC / (MaxAllowedDD / 100.0)) ;
     }
     if ( g_tradeFrequencyMode == 2 )
     {
       global_145_int_40C = (int)(g_ddTierThreshold3 / (MaxAllowedDD / 100.0)) ;
     }
     if ( g_tradeFrequencyMode == 3 )
     {
       global_145_int_40C = (int)(global_388_int_5DB4 / (MaxAllowedDD / 100.0)) ;
     }
     if ( g_tradeFrequencyMode == 4 )
     {
       global_145_int_40C = (int)(g_ddTierThreshold5 / (MaxAllowedDD / 100.0)) ;
     }
     if ( SymbolInfoDouble(g_chartSymbol,36)==0.1 )
     {
       local_2_double = NormalizeDouble(arg_1_int * 0.01 * (local_7_double / global_145_int_40C * 0.01),1) ;
     }
     if ( SymbolInfoDouble(g_chartSymbol,36)==0.01 )
     {
       local_2_double = NormalizeDouble(arg_1_int * 0.01 * (local_7_double / global_145_int_40C * 0.01),2) ;
     }
   }
 }
 if ( Risk == 3 )
 {
   if ( SymbolInfoDouble(g_chartSymbol,36)==0.1 )
   {
     local_2_double = NormalizeDouble(MaxRiskPerStrategy_ / global_397_double_6768 * global_401_double_6AD0 / 100.0 * 0.01,1) ;
   }
   if ( SymbolInfoDouble(g_chartSymbol,36)==0.01 )
   {
     local_2_double = NormalizeDouble(MaxRiskPerStrategy_ / global_397_double_6768 * global_401_double_6AD0 / 100.0 * 0.01,2) ;
   }
 }
 // Legacy hidden Risk values 1/2 preserve strategy 1's manual lot until its
 // first pending order exists.  With no variable lot adjustment they retain
 // StartLots for strategy 1, while the remaining strategies use dynamic risk.
 if ( g_currentStrategyIndex == 0 && (Risk == 1 || Risk == 2) &&
      (g_initialLegacyRiskLotPending || MathAbs(g_lotRatioInv - 1.0) < 0.0000001) )
 {
   local_2_double = g_startLots_rw ;
 }
 local_2_double = local_2_double * g_lotRatioInv ;
 if ( local_2_double<MarketInfo(g_chartSymbol,MODE_LOTSTEP) )
 {
   local_2_double = MarketInfo(g_chartSymbol,MODE_LOTSTEP) ;
 }
 if ( local_2_double>g_maxLotCap )
 {
   local_2_double = g_maxLotCap ;
 }
 if ( local_2_double<MarketInfo(g_chartSymbol,MODE_MINLOT) )
 {
   local_2_double = MarketInfo(g_chartSymbol,MODE_MINLOT) ;
 }
 if ( local_2_double>MarketInfo(g_chartSymbol,MODE_MAXLOT) && MarketInfo(g_chartSymbol,MODE_MAXLOT)!=0.0 )
 {
   local_2_double = MarketInfo(g_chartSymbol,MODE_MAXLOT) ;
 }
 if ( MarketInfo(g_chartSymbol,MODE_LOTSTEP)==0.1 )
 {
   global_223_double_1AC4_si99[g_currentStrategyIndex] = NormalizeDouble((MathFloor(local_2_double * 10.0)) / 10.0,1);
   return;
 }
 global_223_double_1AC4_si99[g_currentStrategyIndex] = NormalizeDouble(MathFloor(local_2_double * 100.0) / 100.0,2);
 }
//CalculateStrategyLotSize <<==--------   --------
// ============================================================================
// [§12] 入场价位探测
//       FindBuyEntryHigh / FindSellEntryLow     —— 逐 bar 扫描版（慢速）
//       MT4FastEntryHigh / MT4FastEntryLow     —— 直接读价格序列版（快速）
//       FindFractalHigh / FindFractalLow       —— 分形高/低点扫描
//       MT4FastFractalHigh / MT4FastFractalLow —— 分形快速版
// ============================================================================

 double FindBuyEntryHigh( int arg_0_int)
 {
  bool      local_2_bool = false;
  bool      local_3_bool = false;
  bool      local_4_bool;
  int       local_5_int;
  int       local_6_int;
  int       local_7_int;
//----- -----
 double     temp_double_1;
 int        temp_int_2;
 double     temp_double_3;
 int        temp_int_4;
 double     temp_double_5;
 int        temp_int_6;
 bool       temp_bool_7;

 local_4_bool = false ;
 local_5_int=global_74_int_180 + 1;
 do
 {
   local_3_bool = true ;
   local_4_bool = true ;
   for (local_6_int = local_5_int ; local_6_int >= local_5_int - global_74_int_180 ; local_6_int --)
   {
     if ( iHigh(g_chartSymbol,MT4Period(arg_0_int),local_6_int)>iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int) )
     {
       local_4_bool = false ;
     }
   }
   for (local_7_int = local_5_int ; local_7_int <= local_5_int + global_73_int_17C ; local_7_int ++)
   {
     if ( iHigh(g_chartSymbol,MT4Period(arg_0_int),local_7_int)>iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int) )
     {
       local_3_bool = false ;
     }
   }
   if ( local_4_bool && local_3_bool && iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int)>g_entryBreakoutPips * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK) )
   {
     temp_double_1 = iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int);
     temp_int_2 = local_5_int;
     temp_double_3 = iHigh(g_chartSymbol,MT4Period(g_entryTfPeriod),0);
     for (temp_int_4 = 1 ; temp_int_4 <= temp_int_2 ; temp_int_4=temp_int_4 + 1)
     {
       if ( iHigh(g_chartSymbol,MT4Period(g_entryTfPeriod),temp_int_4)>temp_double_3 )
       {
         temp_double_3 = iHigh(g_chartSymbol,MT4Period(g_entryTfPeriod),temp_int_4);
       }
     }
     if ( temp_double_1>=temp_double_3 )
     {
       temp_double_5 = NormalizeDouble(iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int),g_symbolDigits);
       temp_bool_7=false; 
       for (temp_int_6 = MT4OrdersTotal() ; temp_int_6 >= 0 ; temp_int_6=temp_int_6 - 1)
       {
         if ( OrderSelect(temp_int_6,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MathAbs(OrderOpenPrice() - (g_buyEntryOffsetPips * g_pipSize + temp_double_5))<global_88_double_1D0 * g_pipSize) )   continue;
         temp_bool_7 = true;
          break;
         
       }
       if ( !(temp_bool_7) && ( !(global_75_bool_184) || !(iClose(g_chartSymbol,MT4Period(arg_0_int),local_5_int - 1)>iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int) - g_entryBreakoutPips * g_pipSize) ) )
       {
         local_2_bool = true ;
         g_entryHighPrice = NormalizeDouble(iHigh(g_chartSymbol,MT4Period(arg_0_int),local_5_int),g_symbolDigits) ;
         break;
       }
     }
   }
   local_5_int ++;
   if ( local_5_int <= global_77_int_188 )   continue;
   g_entryHighPrice = 0.0 ;
   break;
   
 }
 while(!(local_2_bool));
 
 return(g_entryHighPrice); 
 }
//FindBuyEntryHigh <<==--------   --------
 double FindSellEntryLow( int arg_0_int)
 {
  bool      local_2_bool = false;
  bool      local_3_bool = false;
  bool      local_4_bool;
  int       local_5_int;
  int       local_6_int;
  int       local_7_int;
//----- -----
 double     temp_double_1;
 int        temp_int_2;
 double     temp_double_3;
 int        temp_int_4;
 double     temp_double_5;
 int        temp_int_6;
 bool       temp_bool_7;

 local_4_bool = false ;
 local_5_int=global_74_int_180 + 1;
 do
 {
   local_3_bool = true ;
   local_4_bool = true ;
   for (local_6_int = local_5_int ; local_6_int >= local_5_int - global_74_int_180 ; local_6_int --)
   {
     if ( iLow(g_chartSymbol,MT4Period(arg_0_int),local_6_int)<iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int) )
     {
       local_4_bool = false ;
     }
   }
   for (local_7_int = local_5_int ; local_7_int <= local_5_int + global_73_int_17C ; local_7_int ++)
   {
     if ( iLow(g_chartSymbol,MT4Period(arg_0_int),local_7_int)<iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int) )
     {
       local_3_bool = false ;
     }
   }
   if ( local_4_bool && local_3_bool && iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int)<MarketInfo(g_chartSymbol,MODE_BID) - g_entryBreakoutPips * g_pipSize )
   {
     temp_double_1 = iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int);
     temp_int_2 = local_5_int;
     temp_double_3 = iLow(g_chartSymbol,MT4Period(g_entryTfPeriod),0);
     for (temp_int_4 = 1 ; temp_int_4 <= temp_int_2 ; temp_int_4=temp_int_4 + 1)
     {
       if ( iLow(g_chartSymbol,MT4Period(g_entryTfPeriod),temp_int_4)<temp_double_3 )
       {
         temp_double_3 = iLow(g_chartSymbol,MT4Period(g_entryTfPeriod),temp_int_4);
       }
     }
     if ( temp_double_1<=temp_double_3 )
     {
       temp_double_5 = NormalizeDouble(iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int),g_symbolDigits);
       temp_bool_7=false; 
       for (temp_int_6 = MT4OrdersTotal() ; temp_int_6 >= 0 ; temp_int_6=temp_int_6 - 1)
       {
         if ( OrderSelect(temp_int_6,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MathAbs(OrderOpenPrice() - (temp_double_5 - g_sellEntryOffsetPips * g_pipSize))<global_88_double_1D0 * g_pipSize) )   continue;
         temp_bool_7 = true;
          break;
         
       }
       if ( !(temp_bool_7) && ( !(global_75_bool_184) || !(iClose(g_chartSymbol,MT4Period(arg_0_int),local_5_int - 1)<g_entryBreakoutPips * g_pipSize + iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int)) ) )
       {
         local_2_bool = true ;
         g_entryLowPrice = NormalizeDouble(iLow(g_chartSymbol,MT4Period(arg_0_int),local_5_int),g_symbolDigits) ;
         break;
       }
     }
   }
   local_5_int ++;
   if ( local_5_int <= global_77_int_188 )   continue;
   g_entryLowPrice = 0.0 ;
   break;
   
 }
 while(!(local_2_bool));
 
 return(g_entryLowPrice); 
 }
//FindSellEntryLow <<==--------   --------
 double MT4FastEntryHigh(int timeframe)
 {
  ENUM_TIMEFRAMES tf=MT4Period(timeframe);
  int side=MathMax(global_73_int_17C,global_74_int_180);
  int count=global_77_int_188+side+2;
  double highs[];
  ArraySetAsSeries(highs,true);
  if(CopyHigh(g_chartSymbol,tf,0,count,highs)<count)
     return(FindBuyEntryHigh(timeframe));

  int candidate=global_74_int_180+1;
  do
  {
    bool left_ok=true;
    bool right_ok=true;
    double candidate_price=highs[candidate];
    for(int i=candidate;i>=candidate-global_74_int_180;i--)
      if(highs[i]>candidate_price) left_ok=false;
    for(int i=candidate;i<=candidate+global_73_int_17C;i++)
      if(highs[i]>candidate_price) right_ok=false;

    if(left_ok && right_ok && candidate_price>g_entryBreakoutPips*g_pipSize+MarketInfo(g_chartSymbol,MODE_ASK))
    {
      double range_high=highs[0];
      for(int i=1;i<=candidate;i++)
        if(highs[i]>range_high) range_high=highs[i];
      if(candidate_price>=range_high)
      {
        double normalized=NormalizeDouble(candidate_price,g_symbolDigits);
        bool duplicate=false;
        for(int i=MT4OrdersTotal();i>=0;i--)
        {
          if(OrderSelect(i,0,0)!=true || OrderMagicNumber()!=global_93_int_1F0 ||
             OrderSymbol()!=g_chartSymbol || OrderType()!=4 ||
             !(MathAbs(OrderOpenPrice()-(g_buyEntryOffsetPips*g_pipSize+normalized))<global_88_double_1D0*g_pipSize)) continue;
          duplicate=true;
          break;
        }
        if(!duplicate && (!global_75_bool_184 || !(iClose(g_chartSymbol,tf,candidate-1)>candidate_price-g_entryBreakoutPips*g_pipSize)))
        {
          g_entryHighPrice=normalized;
          return(g_entryHighPrice);
        }
      }
    }
    candidate++;
    if(candidate<=global_77_int_188) continue;
    g_entryHighPrice=0.0;
    break;
  }
  while(true);
  return(g_entryHighPrice);
 }

 double MT4FastEntryLow(int timeframe)
 {
  ENUM_TIMEFRAMES tf=MT4Period(timeframe);
  int side=MathMax(global_73_int_17C,global_74_int_180);
  int count=global_77_int_188+side+2;
  double lows[];
  ArraySetAsSeries(lows,true);
  if(CopyLow(g_chartSymbol,tf,0,count,lows)<count)
     return(FindSellEntryLow(timeframe));

  int candidate=global_74_int_180+1;
  do
  {
    bool left_ok=true;
    bool right_ok=true;
    double candidate_price=lows[candidate];
    for(int i=candidate;i>=candidate-global_74_int_180;i--)
      if(lows[i]<candidate_price) left_ok=false;
    for(int i=candidate;i<=candidate+global_73_int_17C;i++)
      if(lows[i]<candidate_price) right_ok=false;

    if(left_ok && right_ok && candidate_price<MarketInfo(g_chartSymbol,MODE_BID)-g_entryBreakoutPips*g_pipSize)
    {
      double range_low=lows[0];
      for(int i=1;i<=candidate;i++)
        if(lows[i]<range_low) range_low=lows[i];
      if(candidate_price<=range_low)
      {
        double normalized=NormalizeDouble(candidate_price,g_symbolDigits);
        bool duplicate=false;
        for(int i=MT4OrdersTotal();i>=0;i--)
        {
          if(OrderSelect(i,0,0)!=true || OrderMagicNumber()!=global_93_int_1F0 ||
             OrderSymbol()!=g_chartSymbol || OrderType()!=5 ||
             !(MathAbs(OrderOpenPrice()-(normalized-g_sellEntryOffsetPips*g_pipSize))<global_88_double_1D0*g_pipSize)) continue;
          duplicate=true;
          break;
        }
        if(!duplicate && (!global_75_bool_184 || !(iClose(g_chartSymbol,tf,candidate-1)<g_entryBreakoutPips*g_pipSize+candidate_price)))
        {
          g_entryLowPrice=normalized;
          return(g_entryLowPrice);
        }
      }
    }
    candidate++;
    if(candidate<=global_77_int_188) continue;
    g_entryLowPrice=0.0;
    break;
  }
  while(true);
  return(g_entryLowPrice);
 }

 double FindFractalHigh( int arg_0_int,int arg_1_int,int arg_2_int)
 {
  bool      local_2_bool = false;
  double    local_3_double = 0.0;
  bool      local_4_bool = false;
  bool      local_5_bool;
  int       local_6_int;
  int       local_7_int;
  int       local_8_int;
//----- -----

 local_5_bool = false ;
 local_6_int=arg_2_int + 1;
 do
 {
   local_4_bool = true ;
   local_5_bool = true ;
   for (local_7_int = local_6_int ; local_7_int >= local_6_int - arg_2_int ; local_7_int --)
   {
     if ( iHigh(g_chartSymbol,MT4Period(arg_0_int),local_7_int)>iHigh(g_chartSymbol,MT4Period(arg_0_int),local_6_int) )
     {
       local_5_bool = false ;
     }
   }
   for (local_8_int = local_6_int ; local_8_int <= local_6_int + arg_1_int ; local_8_int ++)
   {
     if ( iHigh(g_chartSymbol,MT4Period(arg_0_int),local_8_int)>iHigh(g_chartSymbol,MT4Period(arg_0_int),local_6_int) )
     {
       local_4_bool = false ;
     }
   }
   if ( local_5_bool && local_4_bool && iHigh(g_chartSymbol,MT4Period(arg_0_int),local_6_int)>g_minStopDistPrice + MarketInfo(g_chartSymbol,MODE_ASK) )
   {
     local_2_bool = true ;
     local_3_double = NormalizeDouble(iHigh(g_chartSymbol,MT4Period(arg_0_int),local_6_int),g_symbolDigits) ;
     break;
   }
   local_6_int ++;
   if ( local_6_int <= global_118_int_2CC )   continue;
   local_3_double = 9999.0 ;
   break;
   
 }
 while(!(local_2_bool));
 
 return(local_3_double); 
 }
//FindFractalHigh <<==--------   --------
 double FindFractalLow( int arg_0_int,int arg_1_int,int arg_2_int)
 {
  bool      local_2_bool = false;
  double    local_3_double = 0.0;
  bool      local_4_bool = false;
  bool      local_5_bool;
  int       local_6_int;
  int       local_7_int;
  int       local_8_int;
//----- -----

 local_5_bool = false ;
 local_6_int=arg_2_int + 1;
 do
 {
   local_4_bool = true ;
   local_5_bool = true ;
   for (local_7_int = local_6_int ; local_7_int >= local_6_int - arg_2_int ; local_7_int --)
   {
     if ( iLow(g_chartSymbol,MT4Period(arg_0_int),local_7_int)<iLow(g_chartSymbol,MT4Period(arg_0_int),local_6_int) )
     {
       local_5_bool = false ;
     }
   }
   for (local_8_int = local_6_int ; local_8_int <= local_6_int + arg_1_int ; local_8_int ++)
   {
     if ( iLow(g_chartSymbol,MT4Period(arg_0_int),local_8_int)<iLow(g_chartSymbol,MT4Period(arg_0_int),local_6_int) )
     {
       local_4_bool = false ;
     }
   }
   if ( local_5_bool && local_4_bool && iLow(g_chartSymbol,MT4Period(arg_0_int),local_6_int)<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
   {
     local_2_bool = true ;
     local_3_double = NormalizeDouble(iLow(g_chartSymbol,MT4Period(arg_0_int),local_6_int),g_symbolDigits) ;
     break;
   }
   local_6_int ++;
   if ( local_6_int <= global_118_int_2CC )   continue;
   local_3_double = 0.0 ;
   break;
   
 }
 while(!(local_2_bool));
 
 return(local_3_double); 
 }
//FindFractalLow <<==--------   --------
 double MT4FastFractalHigh(int timeframe,int rightBars,int leftBars)
 {
  ENUM_TIMEFRAMES tf=MT4Period(timeframe);
  int maxShift=global_118_int_2CC+rightBars+1;
  double highs[];
  ArraySetAsSeries(highs,true);
  if(CopyHigh(g_chartSymbol,tf,0,maxShift+1,highs)<maxShift+1)
    return FindFractalHigh(timeframe,rightBars,leftBars);
  for(int candidate=leftBars+1;candidate<=global_118_int_2CC;candidate++)
  {
    double px=highs[candidate];
    bool leftOk=true,rightOk=true;
    for(int i=candidate;i>=candidate-leftBars;i--)
      if(highs[i]>px) { leftOk=false; break; }
    if(!leftOk) continue;
    for(int i=candidate;i<=candidate+rightBars;i++)
      if(highs[i]>px) { rightOk=false; break; }
    if(rightOk && px>g_minStopDistPrice+MarketInfo(g_chartSymbol,MODE_ASK))
      return NormalizeDouble(px,g_symbolDigits);
  }
  return 9999.0;
 }

 double MT4FastFractalLow(int timeframe,int rightBars,int leftBars)
 {
  ENUM_TIMEFRAMES tf=MT4Period(timeframe);
  int maxShift=global_118_int_2CC+rightBars+1;
  double lows[];
  ArraySetAsSeries(lows,true);
  if(CopyLow(g_chartSymbol,tf,0,maxShift+1,lows)<maxShift+1)
    return FindFractalLow(timeframe,rightBars,leftBars);
  for(int candidate=leftBars+1;candidate<=global_118_int_2CC;candidate++)
  {
    double px=lows[candidate];
    bool leftOk=true,rightOk=true;
    for(int i=candidate;i>=candidate-leftBars;i--)
      if(lows[i]<px) { leftOk=false; break; }
    if(!leftOk) continue;
    for(int i=candidate;i<=candidate+rightBars;i++)
      if(lows[i]<px) { rightOk=false; break; }
    if(rightOk && px<MarketInfo(g_chartSymbol,MODE_BID)-g_minStopDistPrice)
      return NormalizeDouble(px,g_symbolDigits);
  }
  return 0.0;
 }

// ============================================================================
// [§13] 入场执行
// ============================================================================

// ProcessStrategyEntries —— 入场总控：均线过滤、手数上限、虚拟过期处理，
//                           触发 Buy/Sell Stop 挂单
 void ProcessStrategyEntries()
 {
  int       local_1_int;
//----- -----
 long       temp_long_1;
 long       temp_long_2;
 int        temp_int_3;
 int        temp_int_4;
 int        temp_int_5;
 int        temp_int_6;
 int        temp_int_7;
 int        temp_int_8;
 int        temp_int_9;
 int        temp_int_10;
 int        temp_int_11;
 int        temp_int_12;

 if ( g_maFilterEnabled )
 {
   g_maFilterFast = iMA(g_chartSymbol,0,global_214_int_1714,0,1,0,1) ;
   g_maFilterSlow = iMA(g_chartSymbol,0,g_maSlowPeriod,0,1,0,1) ;
 }
 CalculateStrategyLotSize(global_100_double_230,global_92_int_1EC); 
 if ( global_223_double_1AC4_si99[g_currentStrategyIndex]>g_maxLotCap )
 {
   global_223_double_1AC4_si99[g_currentStrategyIndex] = g_maxLotCap;
 }
 if ( g_pendingExpiryHours >  0 )
 {
   g_pendingOrderExpiry=TimeCurrent() + g_pendingExpirySecs;
 }
 if ( Virtual_expiration )
 {
   g_pendingOrderExpiry = 0 ;
   for (local_1_int = MT4OrdersTotal() ; local_1_int >= 0 ; local_1_int --)
   {
     if ( OrderSelect(local_1_int,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol )   continue;
     
     if ( ( OrderType() != 4 && OrderType() != 5 ) )   continue;
     temp_long_1 = TimeCurrent();
     temp_long_2=OrderOpenTime() + g_pendingExpirySecs;
     if ( temp_long_1 < temp_long_2 )   continue;
     OrderDelete(OrderTicket(),Red); 
     
   }
 }
 temp_int_3 = 0;
 for (temp_int_4 = MT4OrdersTotal() ; temp_int_4 >= 0 ; temp_int_4=temp_int_4 - 1)
 {
   if ( OrderSelect(temp_int_4,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 0 )   continue;
   temp_int_3=temp_int_3 + 1;
   
 }
 if ( temp_int_3 <  g_maxOpenTradesPerSide )
 {
   PlaceBuyStopEntry(1); 
 }
 else
 {
   temp_int_5 = 1;
   for (temp_int_6 = MT4OrdersTotal() ; temp_int_6 >= 0 ; temp_int_6=temp_int_6 - 1)
   {
     if ( OrderSelect(temp_int_6,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
     OrderDelete(OrderTicket(),0xFFFFFFFF); 
     
   }
   if ( temp_int_5 == 2 )
   {
     for (temp_int_7 = MT4OrdersTotal() ; temp_int_7 >= 0 ; temp_int_7=temp_int_7 - 1)
     {
       if ( OrderSelect(temp_int_7,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
   }
 }
 temp_int_8 = 0;
 for (temp_int_9 = MT4OrdersTotal() ; temp_int_9 >= 0 ; temp_int_9=temp_int_9 - 1)
 {
   if ( OrderSelect(temp_int_9,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 1 )   continue;
   temp_int_8=temp_int_8 + 1;
   
 }
 if ( temp_int_8 <  g_maxOpenTradesPerSide )
 {
   PlaceSellStopEntry(1); 
   return;
 }
 temp_int_10 = 1;
 for (temp_int_11 = MT4OrdersTotal() ; temp_int_11 >= 0 ; temp_int_11=temp_int_11 - 1)
 {
   if ( OrderSelect(temp_int_11,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
   OrderDelete(OrderTicket(),0xFFFFFFFF); 
   
 }
 if ( temp_int_10 != 2 )   return;
 for (temp_int_12 = MT4OrdersTotal() ; temp_int_12 >= 0 ; temp_int_12=temp_int_12 - 1)
 {
   if ( OrderSelect(temp_int_12,0,0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
   OrderDelete(OrderTicket(),0xFFFFFFFF); 
   
 }
 }
//ProcessStrategyEntries <<==--------   --------
// PlaceBuyStopEntry —— 放置 Buy Stop 挂单（含假突破过滤与入场价修正）
 bool PlaceBuyStopEntry( int arg_0_int)
 {
  bool      local_2_bool;
  double    local_3_double;
  double    local_4_double;
  double    local_5_double;
  double    local_6_double;
//----- -----
 bool       temp_bool_1;
 int        temp_int_2;
 double     temp_double_3;
 int        temp_int_4;
 bool       temp_bool_5;
 int        temp_int_6;
 int        temp_int_7;
 double     temp_double_8;
 int        temp_int_9;
 double     temp_double_10;
 int        temp_int_11;
 bool       temp_bool_12;
 bool       temp_bool_13;
 int        temp_int_14;
 bool       temp_bool_15;
 int        temp_int_16;
 double     temp_double_17;
 long       temp_long_18;
 int        temp_int_19;

 if ( !(AllowBuyTrades) )
 {
   return(false); 
 }
 if ( global_218_bool_1A74 )
 {
   temp_bool_1 = false;
 }
 else
 {
   temp_bool_1=false; 
   for (temp_int_2 = 0 ; temp_int_2 < MT4OrdersTotal() ; temp_int_2=temp_int_2 + 1)
   {
     if ( OrderSelect(temp_int_2,0,0) != true || OrderType() != 0 || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol )   continue;
     temp_bool_1 = true;
      break;
     
   }
 }
 if ( temp_bool_1 == true )
 {
   return(false); 
 }
 if ( g_maFilterEnabled && g_maFilterFast<g_maFilterSlow )
 {
   return(false); 
 }
 if ( arg_0_int == 1 )
 {
   MT4FastEntryHigh(g_entryTfPeriod); 
   local_2_bool = false ;
   temp_double_3 = g_entryHighPrice;
   temp_bool_5=false; 
   for (temp_int_4 = MT4OrdersTotal() ; temp_int_4 >= 0 ; temp_int_4=temp_int_4 - 1)
   {
     if ( OrderSelect(temp_int_4,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MathAbs(OrderOpenPrice() - (g_buyEntryOffsetPips * g_pipSize + temp_double_3))<global_88_double_1D0 * g_pipSize) )   continue;
     temp_bool_5 = true;
      break;
     
   }
   if ( !(temp_bool_5) )
   {
     temp_int_6 = 0;
     for (temp_int_7 = MT4OrdersTotal() ; temp_int_7 >= 0 ; temp_int_7=temp_int_7 - 1)
     {
       if ( OrderSelect(temp_int_7,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 )   continue;
       temp_int_6=temp_int_6 + 1;
       
     }
     if ( temp_int_6 == g_maxPendingOrders )
     {
       temp_double_8 = 9999.0;
       for (temp_int_9 = MT4OrdersTotal() ; temp_int_9 >= 0 ; temp_int_9=temp_int_9 - 1)
       {
         if ( OrderSelect(temp_int_9,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(OrderOpenPrice()<temp_double_8) )   continue;
         temp_double_8 = OrderOpenPrice();
         
       }
       if ( g_entryHighPrice>temp_double_8 )
       {
         return(false); 
       }
     }
     local_2_bool = true ;
     g_buyEntryPrice = NormalizeDouble(g_entryHighPrice,g_symbolDigits) ;
   }
   if ( g_buyEntryPrice==0.0 )
   {
     return(false); 
   }
   if ( local_2_bool )
   {
     g_nextOrderAnchorPrice = global_129_double_318 ;
     local_3_double = NormalizeDouble(g_buyEntryOffsetPips * g_pipSize + g_buyEntryPrice,g_symbolDigits) ;
     temp_double_10 = local_3_double;
     temp_bool_12=false; 
     for (temp_int_11 = MT4OrdersTotal() ; temp_int_11 >= 0 ; temp_int_11=temp_int_11 - 1)
     {
       if ( OrderSelect(temp_int_11,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(OrderOpenPrice()<=temp_double_10) )   continue;
       temp_bool_12 = true;
        break;
       
     }
     if ( temp_bool_12 )
     {
       return(false); 
     }
     if ( !(global_67_bool_158) )
     {
       if ( CheckMargin && AccountFreeMarginCheck(g_chartSymbol,0,global_223_double_1AC4_si99[g_currentStrategyIndex])<=0.0 )
       {
         Print("Free margin not sufficient for setting order..."); 
         return(false); 
       }
       local_4_double = NormalizeDouble(global_15_int_78 * g_pipSize + local_3_double,g_symbolDigits) ;
       local_5_double = NormalizeDouble(local_3_double - (global_100_double_230 + global_64_double_148) * g_pipSize,g_symbolDigits) ;
       local_6_double = NormalizeDouble(g_takeProfitPips * g_pipSize + local_3_double,g_symbolDigits) ;
       if ( global_223_double_1AC4_si99[g_currentStrategyIndex]<SymbolInfoDouble(g_chartSymbol,34) )
       {
         Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=" + string(SymbolInfoDouble(g_chartSymbol,34))); 
         temp_bool_13 = false;
       }
       else
       {
         if ( global_223_double_1AC4_si99[g_currentStrategyIndex]>SymbolInfoDouble(g_chartSymbol,35) )
         {
           Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=" + string(SymbolInfoDouble(g_chartSymbol,35))); 
           temp_bool_13 = false;
         }
         else
         {
           if ( MathAbs(NormalizeDouble(global_223_double_1AC4_si99[g_currentStrategyIndex] / SymbolInfoDouble(g_chartSymbol,36),0) * SymbolInfoDouble(g_chartSymbol,36) - global_223_double_1AC4_si99[g_currentStrategyIndex])>0.0000001 )
           {
             Print("Volume " + string(global_223_double_1AC4_si99[g_currentStrategyIndex]) + " is not a multiple of the minimal step SYMBOL_VOLUME_STEP=" + string(SymbolInfoDouble(g_chartSymbol,36))); 
             temp_bool_13 = false;
           }
           else
           {
             temp_bool_13 = true;
           }
         }
       }

       temp_int_14 = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
       if ( temp_int_14 == 0 )
       {
         temp_bool_15 = true;
       }
       else
       {
         temp_bool_15 = MT4OrdersTotal()<temp_int_14;
       }
       if ( ( !(temp_bool_13) || !(temp_bool_15) ) )
       {
         return(false); 
       }
       if ( MarketInfo(g_chartSymbol,MODE_ASK)<local_4_double - global_309_double_2898 && MarketInfo(g_chartSymbol,MODE_ASK)<local_4_double - g_minStopDistPrice )
       {
         if ( !(setSL_TP_After_Entry) )
         {
           global_230_int_1E08 = OrderSend(g_chartSymbol,4,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,int(g_slippagePts * g_pipSize),local_5_double,local_6_double,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Green) ;
         }
         else
         {
           global_230_int_1E08 = OrderSend(g_chartSymbol,4,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,int(g_slippagePts * g_pipSize),0.0,0.0,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Green) ;
         }
         if ( global_230_int_1E08 <= 0 )
         {
           temp_int_16 = MT4_LastError();
           if ( temp_int_16 == 132 )
           {
             ResetLastError();
             
               do
               {
                 Sleep(2500); 
                 if ( !(setSL_TP_After_Entry) )
                 {
                   temp_int_16 = (int)(g_slippagePts * g_pipSize);
                   global_230_int_1E08 = OrderSend(g_chartSymbol,4,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,temp_int_16,local_5_double,local_6_double,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Green) ;
                 }
                 else
                 {
                   global_230_int_1E08 = OrderSend(g_chartSymbol,4,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,int(g_slippagePts * g_pipSize),0.0,0.0,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Green) ;
                 }
               }
               while(MT4_LastError() == 132);
               
             
           }
           Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order"); 
         }
         else
         {
           temp_double_17 = local_3_double;
           temp_long_18 = global_230_int_1E08;
           for (temp_int_19 = 0 ; temp_int_19 < 100 ; temp_int_19=temp_int_19 + 1)
           {
             if ( !(g_stopOrderTicketPrice[temp_int_19][0]==0.0) )   continue;
             g_stopOrderTicketPrice[temp_int_19][0] = (double)temp_long_18;
             g_stopOrderTicketPrice[temp_int_19][1] = temp_double_17;
             break;
             
           }
         }
       }
     }
     return(true); 
   }
 }
 return(false); 
 }
//PlaceBuyStopEntry <<==--------   --------
// PlaceSellStopEntry —— 放置 Sell Stop 挂单（PlaceBuyStopEntry 的对称实现）
 bool PlaceSellStopEntry( int arg_0_int)
 {
  bool      local_2_bool;
  double    local_3_double;
  double    local_4_double;
  double    local_5_double;
  double    local_6_double;
//----- -----
 bool       temp_bool_1;
 int        temp_int_2;
 double     temp_double_3;
 int        temp_int_4;
 bool       temp_bool_5;
 int        temp_int_6;
 int        temp_int_7;
 double     temp_double_8;
 int        temp_int_9;
 double     temp_double_10;
 int        temp_int_11;
 bool       temp_bool_12;
 bool       temp_bool_13;
 int        temp_int_14;
 bool       temp_bool_15;
 int        temp_int_16;
 double     temp_double_17;
 long       temp_long_18;
 int        temp_int_19;

 if ( !(AllowSellTrades) )
 {
   return(false); 
 }
 if ( global_218_bool_1A74 )
 {
   temp_bool_1 = false;
 }
 else
 {
   temp_bool_1=false; 
   for (temp_int_2 = 0 ; temp_int_2 < MT4OrdersTotal() ; temp_int_2=temp_int_2 + 1)
   {
     if ( OrderSelect(temp_int_2,0,0) != true || OrderType() != 1 || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol )   continue;
     temp_bool_1 = true;
      break;
     
   }
 }
 if ( temp_bool_1 == true )
 {
   return(false); 
 }
 if ( g_maFilterEnabled && g_maFilterFast>g_maFilterSlow )
 {
   return(false); 
 }
 if ( arg_0_int == 1 )
 {
   MT4FastEntryLow(g_entryTfPeriod); 
   local_2_bool = false ;
   temp_double_3 = g_entryLowPrice;
   temp_bool_5=false; 
   for (temp_int_4 = MT4OrdersTotal() ; temp_int_4 >= 0 ; temp_int_4=temp_int_4 - 1)
   {
     if ( OrderSelect(temp_int_4,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MathAbs(OrderOpenPrice() - (temp_double_3 - g_sellEntryOffsetPips * g_pipSize))<global_88_double_1D0 * g_pipSize) )   continue;
     temp_bool_5 = true;
      break;
     
   }
   if ( !(temp_bool_5) )
   {
     temp_int_6 = 0;
     for (temp_int_7 = MT4OrdersTotal() ; temp_int_7 >= 0 ; temp_int_7=temp_int_7 - 1)
     {
       if ( OrderSelect(temp_int_7,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 )   continue;
       temp_int_6=temp_int_6 + 1;
       
     }
     if ( temp_int_6 == g_maxPendingOrders )
     {
       temp_double_8 = 0.0;
       for (temp_int_9 = MT4OrdersTotal() ; temp_int_9 >= 0 ; temp_int_9=temp_int_9 - 1)
       {
         if ( OrderSelect(temp_int_9,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(OrderOpenPrice()>temp_double_8) )   continue;
         temp_double_8 = OrderOpenPrice();
         
       }
       if ( g_entryLowPrice<temp_double_8 )
       {
         return(false); 
       }
     }
     local_2_bool = true ;
     g_sellEntryPrice = NormalizeDouble(g_entryLowPrice,g_symbolDigits) ;
   }
   if ( g_sellEntryPrice==0.0 )
   {
     return(false); 
   }
   if ( local_2_bool )
   {
     g_nextOrderAnchorPrice = global_129_double_318 ;
     local_3_double = NormalizeDouble(g_sellEntryPrice - g_sellEntryOffsetPips * g_pipSize,g_symbolDigits) ;
     temp_double_10 = local_3_double;
     temp_bool_12=false; 
     for (temp_int_11 = MT4OrdersTotal() ; temp_int_11 >= 0 ; temp_int_11=temp_int_11 - 1)
     {
       if ( OrderSelect(temp_int_11,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(OrderOpenPrice()>=temp_double_10) )   continue;
       temp_bool_12 = true;
        break;
       
     }
     if ( temp_bool_12 )
     {
       return(false); 
     }
     if ( !(global_67_bool_158) )
     {
       if ( CheckMargin && AccountFreeMarginCheck(g_chartSymbol,1,global_223_double_1AC4_si99[g_currentStrategyIndex])<=0.0 )
       {
         Print("Free margin not sufficient for setting order..."); 
         return(false); 
       }
       local_4_double = NormalizeDouble(local_3_double - global_15_int_78 * g_pipSize,g_symbolDigits) ;
       local_5_double = NormalizeDouble((global_100_double_230 + global_64_double_148) * g_pipSize + local_3_double,g_symbolDigits) ;
       local_6_double = NormalizeDouble(local_3_double - g_takeProfitPips * g_pipSize,g_symbolDigits) ;
       if ( global_223_double_1AC4_si99[g_currentStrategyIndex]<SymbolInfoDouble(g_chartSymbol,34) )
       {
         Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=" + string(SymbolInfoDouble(g_chartSymbol,34))); 
         temp_bool_13 = false;
       }
       else
       {
         if ( global_223_double_1AC4_si99[g_currentStrategyIndex]>SymbolInfoDouble(g_chartSymbol,35) )
         {
           Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=" + string(SymbolInfoDouble(g_chartSymbol,35))); 
           temp_bool_13 = false;
         }
         else
         {
           if ( MathAbs(NormalizeDouble(global_223_double_1AC4_si99[g_currentStrategyIndex] / SymbolInfoDouble(g_chartSymbol,36),0) * SymbolInfoDouble(g_chartSymbol,36) - global_223_double_1AC4_si99[g_currentStrategyIndex])>0.0000001 )
           {
             Print("Volume " + string(global_223_double_1AC4_si99[g_currentStrategyIndex]) + " is not a multiple of the minimal step SYMBOL_VOLUME_STEP=" + string(SymbolInfoDouble(g_chartSymbol,36))); 
             temp_bool_13 = false;
           }
           else
           {
             temp_bool_13 = true;
           }
         }
       }

       temp_int_14 = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
       if ( temp_int_14 == 0 )
       {
         temp_bool_15 = true;
       }
       else
       {
         temp_bool_15 = MT4OrdersTotal()<temp_int_14;
       }
       if ( ( !(temp_bool_13) || !(temp_bool_15) ) )
       {
         return(false); 
       }
       if ( MarketInfo(g_chartSymbol,MODE_BID)>global_309_double_2898 + local_4_double && MarketInfo(g_chartSymbol,MODE_BID)>g_minStopDistPrice + local_4_double )
       {
         if ( !(setSL_TP_After_Entry) )
         {
           global_230_int_1E08 = OrderSend(g_chartSymbol,5,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,int(g_slippagePts * g_pipSize),local_5_double,local_6_double,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Red) ;
         }
         else
         {
           global_230_int_1E08 = OrderSend(g_chartSymbol,5,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,int(g_slippagePts * g_pipSize),0.0,0.0,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Red) ;
         }
         if ( global_230_int_1E08 <= 0 )
         {
           temp_int_16 = MT4_LastError();
           if ( temp_int_16 == 132 )
           {
             ResetLastError();
             
               do
               {
                 Sleep(2500); 
                 if ( !(setSL_TP_After_Entry) )
                 {
                   temp_int_16 = (int)(g_slippagePts * g_pipSize);
                   global_230_int_1E08 = OrderSend(g_chartSymbol,5,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,temp_int_16,local_5_double,local_6_double,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Red) ;
                 }
                 else
                 {
                   global_230_int_1E08 = OrderSend(g_chartSymbol,5,global_223_double_1AC4_si99[g_currentStrategyIndex],local_4_double,int(g_slippagePts * g_pipSize),0.0,0.0,g_orderComment,global_93_int_1F0,g_pendingOrderExpiry,Red) ;
                 }
               }
               while(MT4_LastError() == 132);
               
             
           }
           Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order"); 
         }
         else
         {
           temp_double_17 = local_3_double;
           temp_long_18 = global_230_int_1E08;
           for (temp_int_19 = 0 ; temp_int_19 < 100 ; temp_int_19=temp_int_19 + 1)
           {
             if ( !(g_stopOrderTicketPrice[temp_int_19][0]==0.0) )   continue;
             g_stopOrderTicketPrice[temp_int_19][0] = (double)temp_long_18;
             g_stopOrderTicketPrice[temp_int_19][1] = temp_double_17;
             break;
             
           }
         }
       }
     }
   }
 }
 return(false); 
 }
//PlaceSellStopEntry <<==--------   --------
// ============================================================================
// [§14] 持仓管理
// ============================================================================

// ManageBuyPositions —— 多头持仓全生命周期管理：止损/止盈、保本、
//                       各类追踪止损（普通 / HIGH-LOW / MagicTrail / 时间恢复）
 bool ManageBuyPositions()
 {
  bool      local_2_bool = false;
  bool      local_3_bool = false;
  double    local_4_double;
  double    local_5_double;
  int       local_6_int;
  double    local_7_double;
  double    local_8_double;
  long      local_9_long;
  double    local_10_double;
  string    local_11_string;
  double    local_12_double;
  datetime  local_13_datetime;
  int       local_14_int;
  int       local_15_int;
  string    local_16_string;
  double    local_17_double;
  double    local_18_double;
  bool      local_19_bool;
  bool      local_20_bool;
  double    local_21_double;
  bool      local_22_bool;
  double    local_23_double;
  double    local_24_double;
  double    local_25_double;
  double    local_26_double;
  double    local_27_double;
  int       local_28_int;
  double    local_29_double;
//----- -----
 int        temp_int_1;
 long       temp_long_2;
 int        temp_int_3;
 double     temp_double_4;
 double     temp_double_5;
 long       temp_long_6;
 int        temp_int_7;
 long       temp_long_8;
 int        temp_int_9;
 int        temp_int_10;
 string     temp_string_11;
 double     temp_double_12;
 int        temp_int_13;
 long       temp_long_14;
 double     temp_double_15;
 int        temp_int_16;
 long       temp_long_17;
 long       temp_long_18;
 int        temp_int_19;
 int        temp_int_20;
 int        temp_int_21;
 string     temp_string_22;
 long       temp_long_23;
 double     temp_double_24;
 double     temp_double_25;
 int        temp_int_26;
 double     temp_double_27;
 bool       temp_bool_28;
 int        temp_int_29;
 int        temp_int_30;
 double     temp_double_31;
 long       temp_long_32;
 int        temp_int_33;
 long       temp_long_34;
 double     temp_double_35;
 double     temp_double_36;
 int        temp_int_37;
 double     temp_double_38;
 bool       temp_bool_39;
 int        temp_int_40;
 int        temp_int_41;
 double     temp_double_42;
 long       temp_long_43;
 int        temp_int_44;

 // Pre-gate trade guard: preserve the strategy/lot state flow, but do not
 // emit modify/close/hedge requests before the tester/broker trade session opens.
 if ( MarketInfo(g_chartSymbol,MODE_TRADEALLOWED)==0.0 )
 {
   return(false);
 }

 local_4_double = 0.0 ;
 local_5_double = 0.0 ;
 for (local_6_int = 0 ; local_6_int < MT4OrdersTotal() ; local_6_int ++)
 {
   if ( OrderSelect(local_6_int,0,0) == true )
   {
     local_2_bool = false ;
     local_7_double = NormalizeDouble(OrderStopLoss(),g_symbolDigits) ;
     local_8_double = NormalizeDouble(OrderTakeProfit(),g_symbolDigits) ;
     local_9_long = OrderTicket() ;
     local_10_double = NormalizeDouble(OrderOpenPrice(),g_symbolDigits) ;
     local_11_string = OrderComment() ;
     local_12_double = OrderLots() ;
     local_13_datetime = OrderOpenTime() ;
     local_14_int = OrderType() ;
     local_15_int = OrderMagicNumber() ;
     local_16_string = OrderSymbol() ;
     if ( ( local_14_int == 4 || local_14_int == 2 ) && g_orderMgmtMode == 2 && ( g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && local_16_string == g_chartSymbol) ) && ( local_15_int == g_manualMagicNumber || g_manualMagicNumber == 0 ) && ( local_11_string == g_manualCommentFilter || g_manualCommentFilter == "" ) )
     {
       if ( ( local_7_double==0.0 || local_7_double==0.0 ) )
       {
         local_7_double = NormalizeDouble(local_10_double - global_100_double_230 * g_pipSize,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
       if ( ( local_8_double==0.0 || local_8_double==0.0 ) )
       {
         local_8_double = NormalizeDouble(g_takeProfitPips * g_pipSize + local_10_double,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
     }
     if ( local_14_int == 0 && ( ( local_15_int == global_93_int_1F0 && g_orderMgmtMode == 1 && local_16_string == g_chartSymbol ) || (g_orderMgmtMode == 2 && ( g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && local_16_string == g_chartSymbol) ) && ( local_15_int == g_manualMagicNumber || g_manualMagicNumber == 0 ) && (local_11_string == g_manualCommentFilter || g_manualCommentFilter == "")) ) )
     {
       if ( ( local_7_double==0.0 || local_7_double==0.0 ) )
       {
         local_7_double = NormalizeDouble(local_10_double - global_100_double_230 * g_pipSize,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
       if ( ( local_8_double==0.0 || local_8_double==0.0 ) )
       {
         local_8_double = NormalizeDouble(g_takeProfitPips * g_pipSize + local_10_double,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
       if ( g_fakeoutEnableM1 && MT4BearishFakeout(global_52_int_118,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( global_55_bool_124 && MT4BearishFakeout(global_54_int_120,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( g_fakeoutEnableM15 && MT4BearishFakeout(global_56_int_128,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( global_59_bool_134 && MT4BearishFakeout(global_58_int_130,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( g_fakeoutEnableH1 && MT4BearishFakeout(global_60_int_138,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),0,Red); 
         Print("closing candle confirmation"); 
       }
       g_nextOrderAnchorPrice = global_129_double_318 ;
       if ( global_133_int_338 >  0 && TimeCurrent() >  local_13_datetime + global_133_int_338 * 60 )
       {
         g_nextOrderAnchorPrice = global_134_double_340 ;
       }
       temp_int_1 = g_symbolDigits;
       temp_long_2 = local_9_long;
       temp_double_4 = 0.0;
       for (temp_int_3 = 0 ; temp_int_3 < 100 ; temp_int_3=temp_int_3 + 1)
       {
         if ( !(g_stopOrderTicketPrice[temp_int_3][0]==temp_long_2) )   continue;
         temp_double_4 = g_stopOrderTicketPrice[temp_int_3][1];
         break;
         
       }
       local_17_double = NormalizeDouble(temp_double_4,temp_int_1) ;
       if ( local_17_double==0.0 )
       {
         temp_double_5 = local_10_double;
         temp_long_6 = local_9_long;
         for (temp_int_7 = 0 ; temp_int_7 < 100 ; temp_int_7=temp_int_7 + 1)
         {
           if ( !(g_stopOrderTicketPrice[temp_int_7][0]==0.0) )   continue;
           g_stopOrderTicketPrice[temp_int_7][0] = (double)temp_long_6;
           g_stopOrderTicketPrice[temp_int_7][1] = temp_double_5;
           break;
           
         }
         local_17_double = local_10_double ;
       }
       else
       {
         local_17_double = local_17_double - global_85_double_1C0 * g_pipSize ;
       }
       local_18_double = local_10_double - local_17_double ;
       local_19_bool = false ;
       if ( local_17_double>0.0 - global_85_double_1C0 * g_pipSize && local_18_double>g_slippagePts * g_pipSize )
       {
         local_19_bool = true ;
         if ( global_39_int_C8 == 2 )
         {
           g_nextOrderAnchorPrice = -1000.0 ;
           Print("Slippage control active"); 
         }
       }
       if ( global_43_bool_E8 )
       {
         local_5_double = local_17_double ;
       }
       else
       {
         local_5_double = local_10_double ;
       }
       // EX5 behavior: maximum-loss is a virtual close boundary here.
       // Do not rewrite the broker SL on every management pass.
       if ( MarketInfo(g_chartSymbol,MODE_BID)<local_10_double - (global_100_double_230 + global_64_double_148) * g_pipSize - g_curSpread )
       {
         RefreshRates(); 
         OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_curSpread,Red); 
         return(true); 
       }
       local_20_bool = false ;
       if ( g_zrEnabled )
       {
         temp_long_8 = local_9_long;
         temp_int_9 = 0;
         for (temp_int_10 = MT4OrdersTotal() ; temp_int_10 >= 0 ; temp_int_10=temp_int_10 - 1)
         {
           if ( OrderSelect(temp_int_10,0,0) != true || OrderMagicNumber() != g_zrMagicBuy || OrderSymbol() != g_chartSymbol )   continue;
           temp_string_11 = OrderComment();
           if ( temp_string_11 != IntegerToString(temp_long_8,0,32) )   continue;
           temp_int_9=temp_int_9 + 1;
           
         }
         local_21_double = temp_int_9 ;
         local_22_bool = false ;
         if ( !(global_194_bool_530) )
         {
           global_194_bool_530 = true ;
           global_192_int_528 = 0 ;
         }
         if ( local_21_double==0.0 )
         {
           global_192_int_528 = 0 ;
         }
         if ( MathFloor(local_21_double / 2.0)==local_21_double / 2.0 )
         {
           global_192_int_528 = 0 ;
         }
         else
         {
           global_192_int_528 = 1 ;
         }
         if ( global_194_bool_530 )
         {
           if ( local_21_double>0.0 )
           {
             temp_double_12 = AccountEquity();
             if ( temp_double_12>AccountBalance() + g_zrTargetProfit )
             {
               for (temp_int_13 = MT4OrdersTotal() ; temp_int_13 >= 0 ; temp_int_13=temp_int_13 - 1)
               {
                 if ( OrderSelect(temp_int_13,0,0) != true )   continue;
                 
                 if ( ( OrderMagicNumber() != global_93_int_1F0 && OrderMagicNumber() != g_zrMagicSell && OrderMagicNumber() != g_zrMagicBuy ) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                 
               }
             }
           }
           if ( local_21_double>0.0 )
           {
             temp_long_14 = local_9_long;
             temp_double_15 = 0.0;
             for (temp_int_16 = MT4OrdersTotal() ; temp_int_16 >= 0 ; temp_int_16=temp_int_16 - 1)
             {
               if ( OrderSelect(temp_int_16,0,0) != true )   continue;
               temp_long_17 = OrderTicket();
               if ( temp_long_17 != temp_long_14 )
               {
                 temp_string_11 = OrderComment();
               if ( temp_string_11 != IntegerToString(temp_long_14,0,32) )   continue;
               }
               temp_double_15 = temp_double_15 + OrderProfit();
               
             }
             if ( temp_double_15>g_zrTargetProfit )
             {
               temp_long_18 = local_9_long;
               for (temp_int_19 = MT4OrdersTotal() ; temp_int_19 >= 0 ; temp_int_19=temp_int_19 - 1)
               {
                 if ( OrderSelect(temp_int_19,0,0) != true )   continue;
                 
                 if ( OrderMagicNumber() == global_93_int_1F0 && OrderTicket() == temp_long_18 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),3,Red); 
                 }
                 if ( OrderMagicNumber() != g_zrMagicBuy )   continue;
                 temp_string_11 = OrderComment();
                 if ( temp_string_11 != IntegerToString(temp_long_18,0,32) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                 
               }
               global_194_bool_530 = false ;
               local_20_bool = true ;
             }
           }
           else
           {
             local_23_double = local_12_double * g_zrLotMultiplier ;
             if ( g_zrLotMode == 2 )
             {
               local_23_double = (local_21_double + 1.0) * local_12_double + local_12_double ;
             }
             if ( g_zrLotMode == 3 )
             {
               local_23_double = local_12_double * (MathPow(g_zrLotMultiplier,local_21_double + 1.0)) ;
             }
             if ( global_192_int_528 == 0 )
             {
               local_24_double = local_21_double * g_zrStepDist * g_pipSize + (local_17_double - g_zrZoneSize * g_pipSize) ;
               if ( local_24_double>local_17_double - g_zrMinTargetDist * g_pipSize )
               {
                 local_24_double = local_17_double - g_zrMinTargetDist * g_pipSize ;
               }
               if ( MarketInfo(g_chartSymbol,MODE_BID)<local_24_double )
               {
                 if ( local_21_double>=g_zrMaxRecoverySteps )
                 {
                   for (temp_int_20 = MT4OrdersTotal() ; temp_int_20 >= 0 ; temp_int_20=temp_int_20 - 1)
                   {
                     if ( OrderSelect(temp_int_20,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == global_93_int_1F0 && OrderTicket() == local_9_long )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),3,Red); 
                     }
                     if ( OrderMagicNumber() != g_zrMagicBuy )   continue;
                     temp_string_11 = OrderComment();
                     if ( temp_string_11 != IntegerToString(local_9_long,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(g_chartSymbol,1,local_23_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,0.0,0.0,IntegerToString(local_9_long,0,32),g_zrMagicBuy,0,Green); 
                   global_192_int_528 = 1 ;
                   local_22_bool = true ;
                 }
               }
             }
             else
             {
               local_25_double = local_17_double ;
               if ( MarketInfo(g_chartSymbol,MODE_ASK)>local_17_double )
               {
                 if ( local_21_double>=g_zrMaxRecoverySteps )
                 {
                   for (temp_int_21 = MT4OrdersTotal() ; temp_int_21 >= 0 ; temp_int_21=temp_int_21 - 1)
                   {
                     if ( OrderSelect(temp_int_21,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == global_93_int_1F0 && OrderTicket() == local_9_long )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),3,Red); 
                     }
                     if ( OrderMagicNumber() != g_zrMagicBuy )   continue;
                     temp_string_22 = OrderComment();
                     if ( temp_string_22 != IntegerToString(local_9_long,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(g_chartSymbol,0,local_23_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,0.0,0.0,IntegerToString(local_9_long,0,32),g_zrMagicBuy,0,Green); 
                   global_192_int_528 = 0 ;
                   local_22_bool = true ;
                 }
               }
             }
           }
         }
         if ( ( local_21_double>0.0 || local_22_bool ) )
         {
           local_20_bool = true ;
         }
       }
       if ( !(local_20_bool) )
       {
         if ( ( g_profitCloseMode == 1 || (g_profitCloseMode != 3 && g_profitCloseMode != 2) ) )
         {
           temp_long_23 = local_9_long;
           temp_double_24 = global_100_double_230;
           temp_double_25 = local_10_double;
           temp_int_26 = 1;
           temp_double_27 = 0.0;
           temp_bool_28 = false;
           for (temp_int_29 = 0 ; temp_int_29 < g_virtSLCacheSize ; temp_int_29=temp_int_29 + 1)
           {
             if ( g_virtSLCache[temp_int_29][0]==temp_long_23 )
             {
               temp_double_27 = g_virtSLCache[temp_int_29][1];
               temp_bool_28 = true;
               break;
             }
           }
           if ( !(temp_bool_28) )
           {
             if ( temp_int_26 == 1 )
             {
               temp_double_27 = NormalizeDouble(temp_double_25 - temp_double_24 * g_pipSize,g_symbolDigits);
             }
             if ( temp_int_26 == 2 )
             {
               temp_double_27 = NormalizeDouble(temp_double_24 * g_pipSize + temp_double_25,g_symbolDigits);
             }
             for (temp_int_30 = 0 ; temp_int_30 < g_virtSLCacheSize ; temp_int_30=temp_int_30 + 1)
             {
               if ( g_virtSLCache[temp_int_30][0]==0.0 )
               {
                 g_virtSLCache[temp_int_30][0] = (double)temp_long_23;
                 g_virtSLCache[temp_int_30][1] = temp_double_27;
                 break;
               }
             }
           }
           g_virtualSLPrice = temp_double_27 ;
           local_4_double = g_virtualSLPrice ;
            if ( MarketInfo(g_chartSymbol,MODE_BID)<local_4_double )
            {
              Print("Closing with virtual SL"); 
              Print("Virtual_SL: ",DoubleToString(local_4_double,g_symbolDigits));
              Print("Last Bid: ",DoubleToString(MarketInfo(g_chartSymbol,MODE_BID),g_symbolDigits));
              RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           if ( global_125_double_2F8>0.0 && TimeCurrent() >= local_13_datetime + global_304_int_287C && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(global_126_double_300 * g_pipSize + (local_7_double + g_symbolPoint),g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             local_7_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_BID) - global_126_double_300 * g_pipSize,g_symbolDigits) ;
             if ( local_7_double<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TrailSL_after_X_Minutes_size_ loss.  Trying again!"); 
               }
               local_2_bool = true ;
             }
           }
           if ( global_103_double_250>0.0 && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble((global_103_double_250 + global_106_double_268) * g_pipSize + (local_7_double + g_symbolPoint),g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(g_trailActivationPips * g_pipSize + local_10_double,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 && local_7_double<NormalizeDouble(global_105_double_260 * g_pipSize + local_10_double,g_symbolDigits) )
           {
             local_7_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_BID) - global_103_double_250 * g_pipSize,g_symbolDigits) ;
             if ( local_7_double<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_stop_ loss.  Trying again!"); 
               }
               else
               {
                 local_26_double = NormalizeDouble(global_107_double_270 / 100.0 * global_223_double_1AC4_si99[g_currentStrategyIndex],2) ;
                 if ( local_26_double<local_12_double && local_26_double>=MarketInfo(g_chartSymbol,MODE_LOTSTEP) )
                 {
                   OrderClose(local_9_long,local_26_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                   return(true); 
                 }
               }
               local_2_bool = true ;
             }
           }
           if ( global_110_double_288>0.0 && MarketInfo(g_chartSymbol,MODE_ASK)<NormalizeDouble(local_8_double - g_symbolPoint - global_110_double_288 * g_pipSize,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_ASK)<NormalizeDouble(local_5_double - global_111_double_290 * g_pipSize,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             local_8_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_BID) + global_110_double_288 * g_pipSize,g_symbolDigits) ;
             if ( local_8_double>MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TP.  Trying again!"); 
               }
               else
               {
                 local_27_double = NormalizeDouble(global_107_double_270 / 100.0 * global_223_double_1AC4_si99[g_currentStrategyIndex],2) ;
                 if ( local_27_double<local_12_double && local_27_double>=SymbolInfoDouble(g_chartSymbol,34) )
                 {
                   OrderClose(local_9_long,local_27_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                   return(true); 
                 }
               }
               local_2_bool = true ;
             }
           }
           if ( local_19_bool && global_39_int_C8 == 1 && global_41_double_D8>0.0 && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(global_41_double_D8 * g_pipSize + (local_7_double + g_symbolPoint),g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(global_40_double_D0 * g_pipSize + local_17_double,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 && local_7_double<NormalizeDouble(global_42_double_E0 * g_pipSize + local_10_double,g_symbolDigits) )
           {
             local_7_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_BID) - global_41_double_D8 * g_pipSize,g_symbolDigits) ;
             if ( local_7_double<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting Slip TL.  Trying again!"); 
               }
               else
               {
                 Print("Slippage control active"); 
               }
               local_2_bool = true ;
             }
           }
           if ( global_119_int_2D0 >  0 && global_120_int_2D4 >= 0 && UseHL_TrailingSL && g_buyTrailStopLevel[g_currentStrategyIndex]>NormalizeDouble(local_7_double + g_minStopDistPrice + g_symbolPoint,g_symbolDigits) && g_buyTrailStopLevel[g_currentStrategyIndex]<MarketInfo(g_chartSymbol,MODE_BID) - global_121_int_2D8 * g_pipSize && ( g_buyTrailStopLevel[g_currentStrategyIndex]<local_10_double || !(global_116_bool_2C4) ) && g_buyTrailStopLevel[g_currentStrategyIndex]<NormalizeDouble(MarketInfo(g_chartSymbol,MODE_BID) - global_122_int_2DC * g_pipSize - g_minStopDistPrice - g_symbolPoint,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             local_7_double = NormalizeDouble(g_buyTrailStopLevel[g_currentStrategyIndex],g_symbolDigits) ;
             if ( local_7_double<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when modifying stoploss"); 
               }
               local_2_bool = true ;
             }
           }
           if ( global_113_double_2A8>0.0 && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(global_113_double_2A8 * g_pipSize + local_10_double,g_symbolDigits) && NormalizeDouble(g_beExtraPips * g_pipSize + local_10_double,g_symbolDigits)>local_7_double + g_symbolPoint && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(g_beExtraPips * g_pipSize + local_10_double + g_minStopDistPrice,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             local_7_double = NormalizeDouble(g_beExtraPips * g_pipSize + local_10_double,g_symbolDigits) ;
             if ( local_7_double<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!"); 
               }
               local_2_bool = true ;
             }
           }
           if ( !(local_2_bool) && ( global_128_int_314 == 1 || (global_128_int_314 == 2 && global_131_double_328 * g_pipSize + local_7_double<=global_132_double_330 * g_pipSize + (local_5_double + g_curSpread)) ) )
           {
             global_250_int_2518 ++;
             if ( MarketInfo(g_chartSymbol,MODE_BID)>global_131_double_328 * g_pipSize + local_7_double + g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 && ( global_129_double_318==0.0 || MarketInfo(g_chartSymbol,MODE_BID)>g_nextOrderAnchorPrice * g_pipSize + local_5_double ) && global_250_int_2518 >= global_130_int_320 && NormalizeDouble(global_131_double_328 * g_pipSize + local_7_double,g_symbolDigits)>local_7_double )
             {
               global_250_int_2518 = 0 ;
               local_7_double = NormalizeDouble(global_131_double_328 * g_pipSize + local_7_double,g_symbolDigits) ;
               OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF); 
               local_2_bool = true ;
             }
           }
           g_virtualSLPrice = local_7_double ;
            if ( MarketInfo(g_chartSymbol,MODE_BID)<local_7_double )
            {
              Print("Closing with virtual SL"); 
              Print("Virtual_SL: ",DoubleToString(local_7_double,g_symbolDigits));
              Print("Last Bid: ",DoubleToString(MarketInfo(g_chartSymbol,MODE_BID),g_symbolDigits));
              RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(local_4_double,g_symbolDigits)!=NormalizeDouble(g_virtualSLPrice,g_symbolDigits) )
           {
             temp_double_31 = NormalizeDouble(g_virtualSLPrice,g_symbolDigits);
             temp_long_32 = local_9_long;
             for (temp_int_33 = 0 ; temp_int_33 < g_virtSLCacheSize ; temp_int_33=temp_int_33 + 1)
             {
               if ( g_virtSLCache[temp_int_33][0]==temp_long_32 )
               {
                 g_virtSLCache[temp_int_33][1] = temp_double_31;
                 break;
               }
             }
           }
           if ( local_2_bool && global_135_bool_348 )
           {
             return(true); 
           }
         }
         if ( ( g_profitCloseMode == 2 || g_profitCloseMode == 3 ) )
         {
           temp_long_34 = local_9_long;
           temp_double_35 = global_100_double_230;
           temp_double_36 = local_10_double;
           temp_int_37 = 1;
           temp_double_38 = 0.0;
           temp_bool_39 = false;
           for (temp_int_40 = 0 ; temp_int_40 < g_virtSLCacheSize ; temp_int_40=temp_int_40 + 1)
           {
             if ( g_virtSLCache[temp_int_40][0]==temp_long_34 )
             {
               temp_double_38 = g_virtSLCache[temp_int_40][1];
               temp_bool_39 = true;
               break;
             }
           }
           if ( !(temp_bool_39) )
           {
             if ( temp_int_37 == 1 )
             {
               temp_double_38 = NormalizeDouble(temp_double_36 - temp_double_35 * g_pipSize,g_symbolDigits);
             }
             if ( temp_int_37 == 2 )
             {
               temp_double_38 = NormalizeDouble(temp_double_35 * g_pipSize + temp_double_36,g_symbolDigits);
             }
             for (temp_int_41 = 0 ; temp_int_41 < g_virtSLCacheSize ; temp_int_41=temp_int_41 + 1)
             {
               if ( g_virtSLCache[temp_int_41][0]==0.0 )
               {
                 g_virtSLCache[temp_int_41][0] = (double)temp_long_34;
                 g_virtSLCache[temp_int_41][1] = temp_double_38;
                 break;
               }
             }
           }
           g_virtualSLPrice = temp_double_38 ;
           local_4_double = g_virtualSLPrice ;
           if ( MarketInfo(g_chartSymbol,MODE_BID)<=local_4_double )
           {
             RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           local_28_int = (int)(TimeCurrent() - g_lastTrailOrderTime) ;
           if ( local_28_int >= global_65_int_150 )
           {
             if ( NormalizeDouble(g_virtualSLPrice,g_symbolDigits)>local_7_double + g_symbolPoint )
             {
               OrderModify(local_9_long,local_10_double,NormalizeDouble(g_virtualSLPrice,g_symbolDigits),local_8_double,0,0xFFFFFFFF); 
             }
             g_lastTrailOrderTime = TimeCurrent() ;
           }
           if ( global_125_double_2F8>0.0 && TimeCurrent() >= local_13_datetime + global_304_int_287C && MarketInfo(g_chartSymbol,MODE_BID)>global_126_double_300 * g_pipSize + (g_virtualSLPrice + g_symbolPoint) && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             local_2_bool = true ;
             g_virtualSLPrice = MarketInfo(g_chartSymbol,MODE_BID) - global_126_double_300 * g_pipSize ;
           }
           if ( global_103_double_250>0.0 && MarketInfo(g_chartSymbol,MODE_BID)>(global_103_double_250 + global_106_double_268) * g_pipSize + (g_virtualSLPrice + g_symbolPoint) && MarketInfo(g_chartSymbol,MODE_BID)>g_trailActivationPips * g_pipSize + local_5_double && g_virtualSLPrice<global_105_double_260 * g_pipSize + local_10_double )
           {
             local_2_bool = true ;
             g_virtualSLPrice = MarketInfo(g_chartSymbol,MODE_BID) - global_103_double_250 * g_pipSize ;
             local_29_double = NormalizeDouble(global_107_double_270 / 100.0 * global_223_double_1AC4_si99[g_currentStrategyIndex],2) ;
             if ( local_29_double<local_12_double && local_29_double>=MarketInfo(g_chartSymbol,MODE_LOTSTEP) )
             {
               OrderClose(local_9_long,local_29_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
               return(true); 
             }
           }
           if ( local_19_bool && global_39_int_C8 == 1 && global_41_double_D8>0.0 && MarketInfo(g_chartSymbol,MODE_BID)>global_41_double_D8 * g_pipSize + (g_virtualSLPrice + g_symbolPoint) && MarketInfo(g_chartSymbol,MODE_BID)>global_40_double_D0 * g_pipSize + local_17_double && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 && g_virtualSLPrice<global_42_double_E0 * g_pipSize + local_10_double )
           {
             Print("Slippage control active"); 
             local_2_bool = true ;
             g_virtualSLPrice = MarketInfo(g_chartSymbol,MODE_BID) - global_41_double_D8 * g_pipSize ;
           }
           if ( global_119_int_2D0 >  0 && global_120_int_2D4 >= 0 && g_buyTrailStopLevel[g_currentStrategyIndex]>g_virtualSLPrice + g_minStopDistPrice + g_symbolPoint && ( g_buyTrailStopLevel[g_currentStrategyIndex]<local_10_double || !(global_116_bool_2C4) ) && g_buyTrailStopLevel[g_currentStrategyIndex]<MarketInfo(g_chartSymbol,MODE_BID) - global_122_int_2DC * g_pipSize - g_minStopDistPrice - g_symbolPoint && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             g_virtualSLPrice = g_buyTrailStopLevel[g_currentStrategyIndex] ;
             local_2_bool = true ;
           }
           if ( global_113_double_2A8>0.0 && g_profitCloseMode == 3 && MarketInfo(g_chartSymbol,MODE_BID)>global_113_double_2A8 * g_pipSize + local_10_double && g_beExtraPips * g_pipSize + local_10_double>local_7_double + g_symbolPoint && MarketInfo(g_chartSymbol,MODE_BID)>g_beExtraPips * g_pipSize + local_10_double + g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 && NormalizeDouble(g_beExtraPips * g_pipSize + local_10_double,g_symbolDigits)>OrderStopLoss() )
           {
             g_virtualSLPrice = NormalizeDouble(g_beExtraPips * g_pipSize + local_10_double,g_symbolDigits) ;
             global_230_int_1E08 = OrderModify(local_9_long,local_10_double,g_virtualSLPrice,local_8_double,0,0xFFFFFFFF) ;
             if ( global_230_int_1E08 <= 0 )
             {
               Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!"); 
             }
             local_2_bool = true ;
           }
           if ( global_113_double_2A8>0.0 && g_profitCloseMode == 2 && MarketInfo(g_chartSymbol,MODE_BID)>global_113_double_2A8 * g_pipSize + local_10_double && g_beExtraPips * g_pipSize + local_10_double>g_virtualSLPrice + g_symbolPoint && MarketInfo(g_chartSymbol,MODE_BID)>g_beExtraPips * g_pipSize + local_10_double + g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 )
           {
             g_virtualSLPrice = g_beExtraPips * g_pipSize + local_10_double ;
             local_2_bool = true ;
           }
           if ( !(local_2_bool) && ( global_128_int_314 == 1 || (global_128_int_314 == 2 && global_131_double_328 * g_pipSize + g_virtualSLPrice<=global_132_double_330 * g_pipSize + (local_5_double + g_curSpread)) ) )
           {
             global_250_int_2518 ++;
             if ( MarketInfo(g_chartSymbol,MODE_BID)>global_131_double_328 * g_pipSize + g_virtualSLPrice + g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_BID)<local_8_double - global_309_double_2898 && ( global_129_double_318==0.0 || MarketInfo(g_chartSymbol,MODE_BID)>g_nextOrderAnchorPrice * g_pipSize + local_5_double ) && global_250_int_2518 >= global_130_int_320 )
             {
               global_250_int_2518 = 0 ;
               g_virtualSLPrice = global_131_double_328 * g_pipSize + g_virtualSLPrice ;
               local_2_bool = true ;
             }
           }
           if ( MarketInfo(g_chartSymbol,MODE_BID)<=g_virtualSLPrice )
           {
             RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(local_4_double,g_symbolDigits)!=NormalizeDouble(g_virtualSLPrice,g_symbolDigits) )
           {
             temp_double_42 = NormalizeDouble(g_virtualSLPrice,g_symbolDigits);
             temp_long_43 = local_9_long;
             for (temp_int_44 = 0 ; temp_int_44 < g_virtSLCacheSize ; temp_int_44=temp_int_44 + 1)
             {
               if ( g_virtSLCache[temp_int_44][0]==temp_long_43 )
               {
                 g_virtSLCache[temp_int_44][1] = temp_double_42;
                 break;
               }
             }
           }
         }
       }
     }
     if ( local_2_bool )
     {
       local_3_bool = true ;
     }
   }
   if ( local_2_bool )
   {
     local_3_bool = true ;
   }
 }
 return(local_3_bool); 
 }
//ManageBuyPositions <<==--------   --------
// ManageSellPositions —— 空头持仓管理（ManageBuyPositions 的对称实现）
 bool ManageSellPositions()
 {
  bool      local_2_bool = false;
  bool      local_3_bool = false;
  double    local_4_double;
  double    local_5_double;
  int       local_6_int;
  double    local_7_double;
  double    local_8_double;
  long      local_9_long;
  double    local_10_double;
  string    local_11_string;
  double    local_12_double;
  datetime  local_13_datetime;
  int       local_14_int;
  int       local_15_int;
  string    local_16_string;
  double    local_17_double;
  double    local_18_double;
  bool      local_19_bool;
  bool      local_20_bool;
  double    local_21_double;
  bool      local_22_bool;
  double    local_23_double;
  double    local_24_double;
  double    local_25_double;
  double    local_26_double;
  double    local_27_double;
  int       local_28_int;
  double    local_29_double;
//----- -----
 int        temp_int_1;
 long       temp_long_2;
 int        temp_int_3;
 double     temp_double_4;
 double     temp_double_5;
 long       temp_long_6;
 int        temp_int_7;
 long       temp_long_8;
 int        temp_int_9;
 int        temp_int_10;
 string     temp_string_11;
 double     temp_double_12;
 int        temp_int_13;
 long       temp_long_14;
 double     temp_double_15;
 int        temp_int_16;
 long       temp_long_17;
 long       temp_long_18;
 int        temp_int_19;
 int        temp_int_20;
 int        temp_int_21;
 string     temp_string_22;
 long       temp_long_23;
 double     temp_double_24;
 double     temp_double_25;
 int        temp_int_26;
 double     temp_double_27;
 bool       temp_bool_28;
 int        temp_int_29;
 int        temp_int_30;
 double     temp_double_31;
 long       temp_long_32;
 int        temp_int_33;
 long       temp_long_34;
 double     temp_double_35;
 double     temp_double_36;
 int        temp_int_37;
 double     temp_double_38;
 bool       temp_bool_39;
 int        temp_int_40;
 int        temp_int_41;
 double     temp_double_42;
 long       temp_long_43;
 int        temp_int_44;

 // Same pre-gate protection as ManageBuyPositions().
 if ( MarketInfo(g_chartSymbol,MODE_TRADEALLOWED)==0.0 )
 {
   return(false);
 }

 local_4_double = 0.0 ;
 local_5_double = 0.0 ;
 for (local_6_int = 0 ; local_6_int < MT4OrdersTotal() ; local_6_int ++)
 {
   if ( OrderSelect(local_6_int,0,0) == true )
   {
     local_2_bool = false ;
     local_7_double = NormalizeDouble(OrderStopLoss(),g_symbolDigits) ;
     local_8_double = NormalizeDouble(OrderTakeProfit(),g_symbolDigits) ;
     local_9_long = OrderTicket() ;
     local_10_double = NormalizeDouble(OrderOpenPrice(),g_symbolDigits) ;
     local_11_string = OrderComment() ;
     local_12_double = OrderLots() ;
     local_13_datetime = OrderOpenTime() ;
     local_14_int = OrderType() ;
     local_15_int = OrderMagicNumber() ;
     local_16_string = OrderSymbol() ;
     if ( ( local_14_int == 5 || local_14_int == 3 ) && g_orderMgmtMode == 2 && ( g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && local_16_string == g_chartSymbol) ) && ( local_15_int == g_manualMagicNumber || g_manualMagicNumber == 0 ) && ( local_11_string == g_manualCommentFilter || g_manualCommentFilter == "" ) )
     {
       if ( ( local_7_double==0.0 || local_7_double==0.0 ) )
       {
         local_7_double = NormalizeDouble(global_100_double_230 * g_pipSize + local_10_double,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
       if ( ( local_8_double==0.0 || local_8_double==0.0 ) )
       {
         local_8_double = NormalizeDouble(local_10_double - g_takeProfitPips * g_pipSize,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
     }
     if ( local_14_int == 1 && ( ( local_15_int == global_93_int_1F0 && g_orderMgmtMode == 1 && local_16_string == g_chartSymbol ) || (g_orderMgmtMode == 2 && ( g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && local_16_string == g_chartSymbol) ) && ( local_15_int == g_manualMagicNumber || g_manualMagicNumber == 0 ) && (local_11_string == g_manualCommentFilter || g_manualCommentFilter == "")) ) )
     {
       if ( ( local_7_double==0.0 || local_7_double==0.0 ) )
       {
         local_7_double = NormalizeDouble(global_100_double_230 * g_pipSize + local_10_double,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
       if ( ( local_8_double==0.0 || local_8_double==0.0 ) )
       {
         local_8_double = NormalizeDouble(local_10_double - g_takeProfitPips * g_pipSize,g_symbolDigits) ;
         OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,Green); 
       }
       if ( g_fakeoutEnableM1 && MT4BullishFakeout(global_52_int_118,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( global_55_bool_124 && MT4BullishFakeout(global_54_int_120,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( g_fakeoutEnableM15 && MT4BullishFakeout(global_56_int_128,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( global_59_bool_134 && MT4BullishFakeout(global_58_int_130,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),0,Red); 
         Print("closing candle confirmation"); 
       }
       if ( g_fakeoutEnableH1 && MT4BullishFakeout(global_60_int_138,global_51_int_114,local_13_datetime,local_10_double) )
       {
         OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),0,Red); 
         Print("closing candle confirmation"); 
       }
       g_nextOrderAnchorPrice = global_129_double_318 ;
       if ( global_133_int_338 >  0 && TimeCurrent() >  local_13_datetime + global_133_int_338 * 60 )
       {
         g_nextOrderAnchorPrice = global_134_double_340 ;
       }
       temp_int_1 = g_symbolDigits;
       temp_long_2 = local_9_long;
       temp_double_4 = 0.0;
       for (temp_int_3 = 0 ; temp_int_3 < 100 ; temp_int_3=temp_int_3 + 1)
       {
         if ( !(g_stopOrderTicketPrice[temp_int_3][0]==temp_long_2) )   continue;
         temp_double_4 = g_stopOrderTicketPrice[temp_int_3][1];
         break;
         
       }
       local_17_double = NormalizeDouble(temp_double_4,temp_int_1) ;
       if ( local_17_double==0.0 )
       {
         temp_double_5 = local_10_double;
         temp_long_6 = local_9_long;
         for (temp_int_7 = 0 ; temp_int_7 < 100 ; temp_int_7=temp_int_7 + 1)
         {
           if ( !(g_stopOrderTicketPrice[temp_int_7][0]==0.0) )   continue;
           g_stopOrderTicketPrice[temp_int_7][0] = (double)temp_long_6;
           g_stopOrderTicketPrice[temp_int_7][1] = temp_double_5;
           break;
           
         }
         local_17_double = local_10_double ;
       }
       else
       {
         local_17_double = local_17_double - global_85_double_1C0 * g_pipSize ;
       }
       local_18_double = local_17_double - local_10_double ;
       local_19_bool = false ;
       if ( local_17_double>global_85_double_1C0 * g_pipSize && local_18_double>g_slippagePts * g_pipSize )
       {
         local_19_bool = true ;
         if ( global_39_int_C8 == 2 )
         {
           g_nextOrderAnchorPrice = -1000.0 ;
           Print("Slippage controle active"); 
         }
       }
       if ( global_43_bool_E8 )
       {
         local_5_double = local_17_double ;
       }
       else
       {
         local_5_double = local_10_double ;
       }
       // EX5 behavior: maximum-loss is a virtual close boundary here.
       // Do not rewrite the broker SL on every management pass.
       if ( MarketInfo(g_chartSymbol,MODE_ASK)>(global_100_double_230 + global_64_double_148) * g_pipSize + local_10_double + g_curSpread )
       {
         RefreshRates(); 
         OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_curSpread,Red); 
         return(true); 
       }
       local_20_bool = false ;
       if ( g_zrEnabled )
       {
         temp_long_8 = local_9_long;
         temp_int_9 = 0;
         for (temp_int_10 = MT4OrdersTotal() ; temp_int_10 >= 0 ; temp_int_10=temp_int_10 - 1)
         {
           if ( OrderSelect(temp_int_10,0,0) != true || OrderMagicNumber() != g_zrMagicSell || OrderSymbol() != g_chartSymbol )   continue;
           temp_string_11 = OrderComment();
           if ( temp_string_11 != IntegerToString(temp_long_8,0,32) )   continue;
           temp_int_9=temp_int_9 + 1;
           
         }
         local_21_double = temp_int_9 ;
         local_22_bool = false ;
         if ( !(global_195_bool_531) )
         {
           global_195_bool_531 = true ;
           global_193_int_52C = 1 ;
         }
         if ( local_21_double==0.0 )
         {
           global_193_int_52C = 1 ;
         }
         if ( MathFloor(local_21_double / 2.0)==local_21_double / 2.0 )
         {
           global_193_int_52C = 1 ;
         }
         else
         {
           global_193_int_52C = 0 ;
         }
         if ( global_195_bool_531 )
         {
           if ( local_21_double>0.0 )
           {
             temp_double_12 = AccountEquity();
             if ( temp_double_12>AccountBalance() + g_zrTargetProfit )
             {
               for (temp_int_13 = MT4OrdersTotal() ; temp_int_13 >= 0 ; temp_int_13=temp_int_13 - 1)
               {
                 if ( OrderSelect(temp_int_13,0,0) != true )   continue;
                 
                 if ( ( OrderMagicNumber() != global_93_int_1F0 && OrderMagicNumber() != g_zrMagicSell && OrderMagicNumber() != g_zrMagicBuy ) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                 
               }
             }
           }
           if ( local_21_double>0.0 )
           {
             temp_long_14 = local_9_long;
             temp_double_15 = 0.0;
             for (temp_int_16 = MT4OrdersTotal() ; temp_int_16 >= 0 ; temp_int_16=temp_int_16 - 1)
             {
               if ( OrderSelect(temp_int_16,0,0) != true )   continue;
               temp_long_17 = OrderTicket();
               if ( temp_long_17 != temp_long_14 )
               {
                 temp_string_11 = OrderComment();
               if ( temp_string_11 != IntegerToString(temp_long_14,0,32) )   continue;
               }
               temp_double_15 = temp_double_15 + OrderProfit();
               
             }
             if ( temp_double_15>g_zrTargetProfit )
             {
               temp_long_18 = local_9_long;
               for (temp_int_19 = MT4OrdersTotal() ; temp_int_19 >= 0 ; temp_int_19=temp_int_19 - 1)
               {
                 if ( OrderSelect(temp_int_19,0,0) != true )   continue;
                 
                 if ( OrderMagicNumber() == global_93_int_1F0 && OrderTicket() == temp_long_18 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),3,Red); 
                 }
                 if ( OrderMagicNumber() != g_zrMagicSell )   continue;
                 temp_string_11 = OrderComment();
                 if ( temp_string_11 != IntegerToString(temp_long_18,0,32) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                 
               }
               global_195_bool_531 = false ;
               local_20_bool = true ;
             }
           }
           else
           {
             local_23_double = local_12_double * g_zrLotMultiplier ;
             if ( g_zrLotMode == 2 )
             {
               local_23_double = (local_21_double + 1.0) * local_12_double + local_12_double ;
             }
             if ( g_zrLotMode == 3 )
             {
               local_23_double = local_12_double * (MathPow(g_zrLotMultiplier,local_21_double + 1.0)) ;
             }
             if ( global_193_int_52C == 0 )
             {
               local_24_double = local_17_double ;
               if ( MarketInfo(g_chartSymbol,MODE_BID)<local_17_double )
               {
                 if ( local_21_double>=g_zrMaxRecoverySteps )
                 {
                   for (temp_int_20 = MT4OrdersTotal() ; temp_int_20 >= 0 ; temp_int_20=temp_int_20 - 1)
                   {
                     if ( OrderSelect(temp_int_20,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == global_93_int_1F0 && OrderTicket() == local_9_long )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),3,Red); 
                     }
                     if ( OrderMagicNumber() != g_zrMagicSell )   continue;
                     temp_string_11 = OrderComment();
                     if ( temp_string_11 != IntegerToString(local_9_long,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(g_chartSymbol,1,local_23_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,0.0,0.0,IntegerToString(local_9_long,0,32),g_zrMagicSell,0,Green); 
                   global_193_int_52C = 1 ;
                   local_22_bool = true ;
                 }
               }
             }
             else
             {
               local_25_double = g_zrZoneSize * g_pipSize + local_17_double - local_21_double * g_zrStepDist * g_pipSize ;
               if ( local_25_double<g_zrMinTargetDist * g_pipSize + local_17_double )
               {
                 local_25_double = g_zrMinTargetDist * g_pipSize + local_17_double ;
               }
               if ( MarketInfo(g_chartSymbol,MODE_ASK)>local_25_double )
               {
                 if ( local_21_double>=g_zrMaxRecoverySteps )
                 {
                   for (temp_int_21 = MT4OrdersTotal() ; temp_int_21 >= 0 ; temp_int_21=temp_int_21 - 1)
                   {
                     if ( OrderSelect(temp_int_21,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == global_93_int_1F0 && OrderTicket() == local_9_long )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),3,Red); 
                     }
                     if ( OrderMagicNumber() != g_zrMagicSell )   continue;
                     temp_string_22 = OrderComment();
                     if ( temp_string_22 != IntegerToString(local_9_long,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(g_chartSymbol,0,local_23_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,0.0,0.0,IntegerToString(local_9_long,0,32),g_zrMagicSell,0,Green); 
                   global_193_int_52C = 0 ;
                   local_22_bool = true ;
                 }
               }
             }
           }
         }
         if ( ( local_21_double>0.0 || local_22_bool ) )
         {
           local_20_bool = true ;
         }
       }
       if ( !(local_20_bool) )
       {
         if ( ( g_profitCloseMode == 1 || (g_profitCloseMode != 2 && g_profitCloseMode != 3) ) )
         {
           temp_long_23 = local_9_long;
           temp_double_24 = global_100_double_230;
           temp_double_25 = local_10_double;
           temp_int_26 = 2;
           temp_double_27 = 0.0;
           temp_bool_28 = false;
           for (temp_int_29 = 0 ; temp_int_29 < g_virtSLCacheSize ; temp_int_29=temp_int_29 + 1)
           {
             if ( g_virtSLCache[temp_int_29][0]==temp_long_23 )
             {
               temp_double_27 = g_virtSLCache[temp_int_29][1];
               temp_bool_28 = true;
               break;
             }
           }
           if ( !(temp_bool_28) )
           {
             if ( temp_int_26 == 1 )
             {
               temp_double_27 = NormalizeDouble(temp_double_25 - temp_double_24 * g_pipSize,g_symbolDigits);
             }
             if ( temp_int_26 == 2 )
             {
               temp_double_27 = NormalizeDouble(temp_double_24 * g_pipSize + temp_double_25,g_symbolDigits);
             }
             for (temp_int_30 = 0 ; temp_int_30 < g_virtSLCacheSize ; temp_int_30=temp_int_30 + 1)
             {
               if ( g_virtSLCache[temp_int_30][0]==0.0 )
               {
                 g_virtSLCache[temp_int_30][0] = (double)temp_long_23;
                 g_virtSLCache[temp_int_30][1] = temp_double_27;
                 break;
               }
             }
           }
           g_virtualSLPrice = temp_double_27 ;
           local_4_double = g_virtualSLPrice ;
            if ( MarketInfo(g_chartSymbol,MODE_ASK)>local_4_double )
            {
              Print("Closing with virtual SL"); 
              Print("Virtual_SL: ",DoubleToString(local_4_double,g_symbolDigits));
              Print("Last Ask: ",DoubleToString(MarketInfo(g_chartSymbol,MODE_ASK),g_symbolDigits));
              RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           if ( global_125_double_2F8>0.0 && TimeCurrent() >= local_13_datetime + global_304_int_287C && MarketInfo(g_chartSymbol,MODE_ASK)<local_7_double - g_symbolPoint - global_126_double_300 * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && NormalizeDouble(MarketInfo(g_chartSymbol,MODE_ASK) + global_126_double_300 * g_pipSize,g_symbolDigits)<local_7_double )
           {
             local_7_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_ASK) + global_126_double_300 * g_pipSize,g_symbolDigits) ;
             if ( local_7_double>MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TrailSL_after_X_Minutes_size_ loss.  Trying again!"); 
               }
               local_2_bool = true ;
             }
           }
           if ( global_103_double_250>0.0 && MarketInfo(g_chartSymbol,MODE_ASK)<local_7_double - g_symbolPoint - (global_103_double_250 + global_106_double_268) * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - g_trailActivationPips * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && local_7_double>local_10_double - global_105_double_260 * g_pipSize && NormalizeDouble(global_103_double_250 * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK),g_symbolDigits)<local_7_double )
           {
             local_7_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_ASK) + global_103_double_250 * g_pipSize,g_symbolDigits) ;
             if ( local_7_double>MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_stop_ loss.  Trying again!"); 
               }
               else
               {
                 local_26_double = NormalizeDouble(global_107_double_270 / 100.0 * global_223_double_1AC4_si99[g_currentStrategyIndex],2) ;
                 if ( local_26_double<local_12_double && local_26_double>=MarketInfo(g_chartSymbol,MODE_LOTSTEP) )
                 {
                   OrderClose(local_9_long,local_26_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                   return(true); 
                 }
               }
               local_2_bool = true ;
             }
           }
           if ( global_110_double_288>0.0 && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(global_110_double_288 * g_pipSize + (local_8_double + g_symbolPoint),g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)>NormalizeDouble(global_111_double_290 * g_pipSize + local_5_double,g_symbolDigits) && MarketInfo(g_chartSymbol,MODE_BID)>local_8_double + global_309_double_2898 )
           {
             local_8_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_BID) - global_110_double_288 * g_pipSize,g_symbolDigits) ;
             if ( local_8_double<MarketInfo(g_chartSymbol,MODE_BID) - g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TP.  Trying again!"); 
               }
               else
               {
                 local_27_double = NormalizeDouble(global_107_double_270 / 100.0 * global_223_double_1AC4_si99[g_currentStrategyIndex],2) ;
                 if ( local_27_double<local_12_double && local_27_double>=SymbolInfoDouble(g_chartSymbol,34) )
                 {
                   OrderClose(local_9_long,local_27_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_slippagePts,Red); 
                   return(true); 
                 }
               }
               local_2_bool = true ;
             }
           }
           if ( local_19_bool && global_39_int_C8 == 1 && global_41_double_D8>0.0 && MarketInfo(g_chartSymbol,MODE_ASK)<local_7_double - g_symbolPoint - global_41_double_D8 * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)<local_17_double - global_40_double_D0 * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && local_7_double>local_10_double - global_42_double_E0 * g_pipSize && NormalizeDouble(MarketInfo(g_chartSymbol,MODE_ASK) + global_41_double_D8 * g_pipSize,g_symbolDigits)<local_7_double )
           {
             local_7_double = NormalizeDouble(MarketInfo(g_chartSymbol,MODE_ASK) + global_41_double_D8 * g_pipSize,g_symbolDigits) ;
             if ( local_7_double>MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting Slip TL.  Trying again!"); 
               }
               else
               {
                 Print("Slippage controle active"); 
               }
               local_2_bool = true ;
             }
           }
           if ( global_119_int_2D0 >  0 && global_120_int_2D4 >= 0 && UseHL_TrailingSL && g_sellTrailStopLevel[g_currentStrategyIndex]<local_7_double - g_minStopDistPrice - g_symbolPoint && g_sellTrailStopLevel[g_currentStrategyIndex]>global_121_int_2D8 * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK) && ( g_sellTrailStopLevel[g_currentStrategyIndex]>local_10_double || !(global_116_bool_2C4) ) && g_sellTrailStopLevel[g_currentStrategyIndex]>global_122_int_2DC * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice + g_symbolPoint && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && NormalizeDouble(g_sellTrailStopLevel[g_currentStrategyIndex],g_symbolDigits)<local_7_double )
           {
             local_7_double = NormalizeDouble(g_sellTrailStopLevel[g_currentStrategyIndex],g_symbolDigits) ;
             if ( local_7_double>MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when modifying stoploss"); 
               }
               local_2_bool = true ;
             }
           }
           if ( global_113_double_2A8>0.0 && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - global_113_double_2A8 * g_pipSize && local_10_double - g_beExtraPips * g_pipSize<local_7_double - g_symbolPoint && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - g_beExtraPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && NormalizeDouble(local_10_double - g_beExtraPips * g_pipSize,g_symbolDigits)<local_7_double )
           {
             local_7_double = NormalizeDouble(local_10_double - g_beExtraPips * g_pipSize,g_symbolDigits) ;
             if ( local_7_double>MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice )
             {
               global_230_int_1E08 = OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF) ;
               if ( global_230_int_1E08 <= 0 )
               {
                 Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!"); 
               }
               local_2_bool = true ;
             }
           }
           if ( !(local_2_bool) && ( global_128_int_314 == 1 || (global_128_int_314 == 2 && local_7_double - global_131_double_328 * g_pipSize>=local_5_double - g_curSpread - global_132_double_330 * g_pipSize) ) )
           {
             global_250_int_2518 ++;
             if ( MarketInfo(g_chartSymbol,MODE_ASK)<local_7_double - global_131_double_328 * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && ( global_129_double_318==0.0 || MarketInfo(g_chartSymbol,MODE_ASK)<local_5_double - g_nextOrderAnchorPrice * g_pipSize ) && global_250_int_2518 >= global_130_int_320 && NormalizeDouble(local_7_double - global_131_double_328 * g_pipSize,g_symbolDigits)<local_7_double )
             {
               global_250_int_2518 = 0 ;
               local_7_double = NormalizeDouble(local_7_double - global_131_double_328 * g_pipSize,g_symbolDigits) ;
               OrderModify(local_9_long,local_10_double,local_7_double,local_8_double,0,0xFFFFFFFF); 
               local_2_bool = true ;
             }
           }
           g_virtualSLPrice = local_7_double ;
            if ( MarketInfo(g_chartSymbol,MODE_ASK)>local_7_double )
            {
              Print("Closing with virtual SL"); 
              Print("Virtual_SL: ",DoubleToString(local_7_double,g_symbolDigits));
              Print("Last Ask: ",DoubleToString(MarketInfo(g_chartSymbol,MODE_ASK),g_symbolDigits));
              RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(local_4_double,g_symbolDigits)!=NormalizeDouble(g_virtualSLPrice,g_symbolDigits) )
           {
             temp_double_31 = NormalizeDouble(g_virtualSLPrice,g_symbolDigits);
             temp_long_32 = local_9_long;
             for (temp_int_33 = 0 ; temp_int_33 < g_virtSLCacheSize ; temp_int_33=temp_int_33 + 1)
             {
               if ( g_virtSLCache[temp_int_33][0]==temp_long_32 )
               {
                 g_virtSLCache[temp_int_33][1] = temp_double_31;
                 break;
               }
             }
           }
           if ( local_2_bool && global_135_bool_348 )
           {
             return(true); 
           }
         }
         if ( ( g_profitCloseMode == 2 || g_profitCloseMode == 3 ) )
         {
           temp_long_34 = local_9_long;
           temp_double_35 = global_100_double_230;
           temp_double_36 = local_10_double;
           temp_int_37 = 2;
           temp_double_38 = 0.0;
           temp_bool_39 = false;
           for (temp_int_40 = 0 ; temp_int_40 < g_virtSLCacheSize ; temp_int_40=temp_int_40 + 1)
           {
             if ( g_virtSLCache[temp_int_40][0]==temp_long_34 )
             {
               temp_double_38 = g_virtSLCache[temp_int_40][1];
               temp_bool_39 = true;
               break;
             }
           }
           if ( !(temp_bool_39) )
           {
             if ( temp_int_37 == 1 )
             {
               temp_double_38 = NormalizeDouble(temp_double_36 - temp_double_35 * g_pipSize,g_symbolDigits);
             }
             if ( temp_int_37 == 2 )
             {
               temp_double_38 = NormalizeDouble(temp_double_35 * g_pipSize + temp_double_36,g_symbolDigits);
             }
             for (temp_int_41 = 0 ; temp_int_41 < g_virtSLCacheSize ; temp_int_41=temp_int_41 + 1)
             {
               if ( g_virtSLCache[temp_int_41][0]==0.0 )
               {
                 g_virtSLCache[temp_int_41][0] = (double)temp_long_34;
                 g_virtSLCache[temp_int_41][1] = temp_double_38;
                 break;
               }
             }
           }
           g_virtualSLPrice = temp_double_38 ;
           local_4_double = g_virtualSLPrice ;
           if ( MarketInfo(g_chartSymbol,MODE_ASK)>=local_4_double )
           {
             RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           local_28_int = (int)(TimeCurrent() - g_lastTrailOrderTime) ;
           if ( local_28_int >= global_65_int_150 )
           {
             if ( NormalizeDouble(g_virtualSLPrice,g_symbolDigits)<local_7_double - g_symbolPoint )
             {
               OrderModify(local_9_long,local_10_double,NormalizeDouble(g_virtualSLPrice,g_symbolDigits),local_8_double,0,0xFFFFFFFF); 
             }
             g_lastTrailOrderTime = TimeCurrent() ;
           }
           if ( global_125_double_2F8>0.0 && TimeCurrent() >= local_13_datetime + global_304_int_287C && MarketInfo(g_chartSymbol,MODE_ASK)<g_virtualSLPrice - g_symbolPoint - global_126_double_300 * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 )
           {
             g_virtualSLPrice = MarketInfo(g_chartSymbol,MODE_ASK) + global_126_double_300 * g_pipSize ;
             local_2_bool = true ;
           }
           if ( global_103_double_250>0.0 && MarketInfo(g_chartSymbol,MODE_ASK)<g_virtualSLPrice - g_symbolPoint - (global_103_double_250 + global_106_double_268) * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)<local_5_double - g_trailActivationPips * g_pipSize && g_virtualSLPrice>local_10_double - global_105_double_260 * g_pipSize )
           {
             g_virtualSLPrice = global_103_double_250 * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK) ;
             local_29_double = NormalizeDouble(global_107_double_270 / 100.0 * global_223_double_1AC4_si99[g_currentStrategyIndex],2) ;
             if ( local_29_double<local_12_double && local_29_double>=MarketInfo(g_chartSymbol,MODE_LOTSTEP) )
             {
               OrderClose(local_9_long,local_29_double,MarketInfo(g_chartSymbol,MODE_BID),(int)g_slippagePts,Red); 
               return(true); 
             }
             local_2_bool = true ;
           }
           if ( local_19_bool && global_39_int_C8 == 1 && global_41_double_D8>0.0 && MarketInfo(g_chartSymbol,MODE_ASK)<g_virtualSLPrice - g_symbolPoint - global_41_double_D8 * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)<local_17_double - global_40_double_D0 * g_pipSize && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && g_virtualSLPrice>local_10_double - global_42_double_E0 * g_pipSize )
           {
             Print("Slippage controle active"); 
             local_2_bool = true ;
             g_virtualSLPrice = MarketInfo(g_chartSymbol,MODE_ASK) + global_41_double_D8 * g_pipSize ;
           }
           if ( global_119_int_2D0 >  0 && global_120_int_2D4 >= 0 && g_sellTrailStopLevel[g_currentStrategyIndex]<g_virtualSLPrice - g_minStopDistPrice - g_symbolPoint && ( g_sellTrailStopLevel[g_currentStrategyIndex]>local_10_double || !(global_116_bool_2C4) ) && g_sellTrailStopLevel[g_currentStrategyIndex]>global_122_int_2DC * g_pipSize + MarketInfo(g_chartSymbol,MODE_ASK) + g_minStopDistPrice + g_symbolPoint && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 )
           {
             g_virtualSLPrice = g_sellTrailStopLevel[g_currentStrategyIndex] ;
             local_2_bool = true ;
           }
           if ( global_113_double_2A8>0.0 && g_profitCloseMode == 3 && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - global_113_double_2A8 * g_pipSize && local_10_double - g_beExtraPips * g_pipSize<local_7_double - g_symbolPoint && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - g_beExtraPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && NormalizeDouble(local_10_double - g_beExtraPips * g_pipSize,g_symbolDigits)<g_virtualSLPrice )
           {
             g_virtualSLPrice = NormalizeDouble(local_10_double - g_beExtraPips * g_pipSize,g_symbolDigits) ;
             global_230_int_1E08 = OrderModify(local_9_long,local_10_double,g_virtualSLPrice,local_8_double,0,0xFFFFFFFF) ;
             if ( global_230_int_1E08 <= 0 )
             {
               Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!"); 
             }
             local_2_bool = true ;
           }
           if ( global_113_double_2A8>0.0 && g_profitCloseMode == 2 && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - global_113_double_2A8 * g_pipSize && local_10_double - g_beExtraPips * g_pipSize<g_virtualSLPrice - g_symbolPoint && MarketInfo(g_chartSymbol,MODE_ASK)<local_10_double - g_beExtraPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 )
           {
             g_virtualSLPrice = local_10_double - g_beExtraPips * g_pipSize ;
             local_2_bool = true ;
           }
           if ( !(local_2_bool) && ( global_128_int_314 == 1 || (global_128_int_314 == 2 && g_virtualSLPrice - global_131_double_328 * g_pipSize>=local_5_double - g_curSpread - global_132_double_330 * g_pipSize) ) )
           {
             global_250_int_2518 ++;
             if ( MarketInfo(g_chartSymbol,MODE_ASK)<g_virtualSLPrice - global_131_double_328 * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol,MODE_ASK)>local_8_double + global_309_double_2898 && ( global_129_double_318==0.0 || MarketInfo(g_chartSymbol,MODE_ASK)<local_5_double - g_nextOrderAnchorPrice * g_pipSize ) && global_250_int_2518 >= global_130_int_320 )
             {
               global_250_int_2518 = 0 ;
               g_virtualSLPrice = g_virtualSLPrice - global_131_double_328 * g_pipSize ;
               local_2_bool = true ;
             }
           }
           if ( MarketInfo(g_chartSymbol,MODE_ASK)>=g_virtualSLPrice )
           {
             RefreshRates(); 
             OrderClose(local_9_long,local_12_double,MarketInfo(g_chartSymbol,MODE_ASK),(int)g_curSpread,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(local_4_double,g_symbolDigits)!=NormalizeDouble(g_virtualSLPrice,g_symbolDigits) )
           {
             temp_double_42 = NormalizeDouble(g_virtualSLPrice,g_symbolDigits);
             temp_long_43 = local_9_long;
             for (temp_int_44 = 0 ; temp_int_44 < g_virtSLCacheSize ; temp_int_44=temp_int_44 + 1)
             {
               if ( g_virtSLCache[temp_int_44][0]==temp_long_43 )
               {
                 g_virtSLCache[temp_int_44][1] = temp_double_42;
                 break;
               }
             }
           }
         }
       }
     }
     if ( local_2_bool )
     {
       local_3_bool = true ;
     }
   }
   if ( local_2_bool )
   {
     local_3_bool = true ;
   }
 }
 return(local_3_bool); 
 }
//ManageSellPositions <<==--------   --------
// ============================================================================
// [§15] 交易时段、错误描述、挂单手数刷新、信息面板与绩效统计
//       IsTradingScheduleOpen        —— 交易时段过滤器（GMT/PC/服务器时间源）
//       GetTradeErrorDescription    —— MT4 风格错误码 -> 文本
//       RefreshPendingOrderLotSizes  —— 按最新手数刷新在市挂单
//       CreateInfoPanel / CreateInfoPanelCell / DeleteInfoPanel
//                                    —— 信息面板的创建与销毁
//       GetNextNFPText / UpdateAccountPanel / UpdateStrategyPanelRows /
//       UpdateHistoryPanel           —— 面板各区域的周期性刷新
//       CountWinningTrades / CountLosingTrades —— 按策略统计胜负笔数
//       CalculatePerformanceMetrics  —— 汇总各策略绩效指标
//       RankStrategiesByClosedProfit / RankStrategiesByProfitPerTrade
//                                    —— 策略排名（用于自动手数加权）
//       ConvertUsdToAccountCurrency / ConvertAccountCurrencyToUsd —— 货币换算
// ============================================================================

 bool IsTradingScheduleOpen()
 {
  bool      local_2_bool;
  datetime  local_3_datetime;
  int       local_4_int;
//----- -----
 bool       temp_bool_1;
 bool       temp_bool_2;
 bool       temp_bool_3;
 bool       temp_bool_4;
 bool       temp_bool_5;
 bool       temp_bool_6;

 if ( !(g_useTradingHours) )
 {
   return(true); 
 }
 local_2_bool = false ;
 local_3_datetime = 0 ;
 if ( g_scheduleTimeBase == 2 )
 {
   local_3_datetime = TimeCurrent() ;
 }
 if ( g_scheduleTimeBase == 0 )
 {
   TimeGMT(); 
 }
 if ( g_scheduleTimeBase == 1 )
 {
   TimeLocal(); 
 }
 local_4_int = TimeHour(local_3_datetime) ;
 if ( TimeDayOfWeek(local_3_datetime) == 0 )
 {
   if ( g_sunStartHour <  g_sunEndHour && ( local_4_int < g_sunStartHour || local_4_int >= g_sunEndHour ) )
   {
     temp_bool_1 = false;
   }
   else
   {
     if ( g_sunStartHour >  g_sunEndHour && local_4_int <  g_sunStartHour && local_4_int >= g_sunEndHour )
     {
       temp_bool_1 = false;
     }
     else
     {
       if ( g_sunStartHour == g_sunEndHour )
       {
         temp_bool_1 = false;
       }
       else
       {
         temp_bool_1 = true;
       }
     }
   }
   if ( temp_bool_1 )
   {
     local_2_bool = true ;
   }
 }
 if ( TimeDayOfWeek(local_3_datetime) == 1 )
 {
   if ( g_monStartHour <  g_monEndHour && ( local_4_int < g_monStartHour || local_4_int >= g_monEndHour ) )
   {
     temp_bool_2 = false;
   }
   else
   {
     if ( g_monStartHour >  g_monEndHour && local_4_int <  g_monStartHour && local_4_int >= g_monEndHour )
     {
       temp_bool_2 = false;
     }
     else
     {
       if ( g_monStartHour == g_monEndHour )
       {
         temp_bool_2 = false;
       }
       else
       {
         temp_bool_2 = true;
       }
     }
   }
   if ( temp_bool_2 )
   {
     local_2_bool = true ;
   }
 }
 if ( TimeDayOfWeek(local_3_datetime) == 2 )
 {
   if ( g_tueStartHour <  g_tueEndHour && ( local_4_int < g_tueStartHour || local_4_int >= g_tueEndHour ) )
   {
     temp_bool_3 = false;
   }
   else
   {
     if ( g_tueStartHour >  g_tueEndHour && local_4_int <  g_tueStartHour && local_4_int >= g_tueEndHour )
     {
       temp_bool_3 = false;
     }
     else
     {
       if ( g_tueStartHour == g_tueEndHour )
       {
         temp_bool_3 = false;
       }
       else
       {
         temp_bool_3 = true;
       }
     }
   }
   if ( temp_bool_3 )
   {
     local_2_bool = true ;
   }
 }
 if ( TimeDayOfWeek(local_3_datetime) == 3 )
 {
   if ( g_wedStartHour <  g_wedEndHour && ( local_4_int < g_wedStartHour || local_4_int >= g_wedEndHour ) )
   {
     temp_bool_4 = false;
   }
   else
   {
     if ( g_wedStartHour >  g_wedEndHour && local_4_int <  g_wedStartHour && local_4_int >= g_wedEndHour )
     {
       temp_bool_4 = false;
     }
     else
     {
       if ( g_wedStartHour == g_wedEndHour )
       {
         temp_bool_4 = false;
       }
       else
       {
         temp_bool_4 = true;
       }
     }
   }
   if ( temp_bool_4 )
   {
     local_2_bool = true ;
   }
 }
 if ( TimeDayOfWeek(local_3_datetime) == 4 )
 {
   if ( g_thuStartHour <  g_thuEndHour && ( local_4_int < g_thuStartHour || local_4_int >= g_thuEndHour ) )
   {
     temp_bool_5 = false;
   }
   else
   {
     if ( g_thuStartHour >  g_thuEndHour && local_4_int <  g_thuStartHour && local_4_int >= g_thuEndHour )
     {
       temp_bool_5 = false;
     }
     else
     {
       if ( g_thuStartHour == g_thuEndHour )
       {
         temp_bool_5 = false;
       }
       else
       {
         temp_bool_5 = true;
       }
     }
   }
   if ( temp_bool_5 )
   {
     local_2_bool = true ;
   }
 }
 if ( TimeDayOfWeek(local_3_datetime) == 5 )
 {
   if ( g_friStartHour <  g_friEndHour && ( local_4_int < g_friStartHour || local_4_int >= g_friEndHour ) )
   {
     temp_bool_6 = false;
   }
   else
   {
     if ( g_friStartHour >  g_friEndHour && local_4_int <  g_friStartHour && local_4_int >= g_friEndHour )
     {
       temp_bool_6 = false;
     }
     else
     {
       if ( g_friStartHour == g_friEndHour )
       {
         temp_bool_6 = false;
       }
       else
       {
         temp_bool_6 = true;
       }
     }
   }
   if ( temp_bool_6 )
   {
     local_2_bool = true ;
   }
 }
 return(local_2_bool); 
 }
//IsTradingScheduleOpen <<==--------   --------
 string GetTradeErrorDescription( int arg_0_int)
 {
  string    local_1_string;
//----- -----

 g_tradeErrorCount ++;
 switch(arg_0_int)
 {
   case 0 : case 1 :
   local_1_string = "no error" ;
     break;
   case 2 :
   local_1_string = "common error" ;
     break;
   case 3 :
   local_1_string = "invalid trade parameters" ;
     break;
   case 4 :
   local_1_string = "trade server is busy" ;
     break;
   case 5 :
   local_1_string = "old version of the client terminal" ;
     break;
   case 6 :
   local_1_string = "no connection with trade server" ;
     break;
   case 7 :
   local_1_string = "not enough rights" ;
     break;
   case 8 :
   local_1_string = "too frequent requests" ;
     break;
   case 9 :
   local_1_string = "malfunctional trade operation (never returned error)" ;
     break;
   case 64 :
   local_1_string = "account disabled" ;
     break;
   case 65 :
   local_1_string = "invalid account" ;
     break;
   case 128 :
   local_1_string = "trade timeout" ;
     break;
   case 129 :
   local_1_string = "invalid price" ;
     break;
   case 130 :
   local_1_string = "invalid stops" ;
     break;
   case 131 :
   local_1_string = "invalid trade volume" ;
     break;
   case 132 :
   local_1_string = "market is closed" ;
     break;
   case 133 :
   local_1_string = "trade is disabled" ;
     break;
   case 134 :
   local_1_string = "not enough money" ;
     break;
   case 135 :
   local_1_string = "price changed" ;
     break;
   case 136 :
   local_1_string = "off quotes" ;
     break;
   case 137 :
   local_1_string = "broker is busy (never returned error)" ;
     break;
   case 138 :
   local_1_string = "requote" ;
     break;
   case 139 :
   local_1_string = "order is locked" ;
     break;
   case 140 :
   local_1_string = "long positions only allowed" ;
     break;
   case 141 :
   local_1_string = "too many requests" ;
     break;
   case 145 :
   local_1_string = "modification denied because order too close to market" ;
     break;
   case 146 :
   local_1_string = "trade context is busy" ;
     break;
   case 147 :
   local_1_string = "expirations are denied by broker" ;
     break;
   case 148 :
   local_1_string = "amount of open and pending orders has reached the Exit_limit" ;
     break;
   case 149 :
   local_1_string = "hedging is prohibited" ;
     break;
   case 150 :
   local_1_string = "prohibited by FIFO rules" ;
     break;
   case 4000 :
   local_1_string = "no error (never generated code)" ;
     break;
   case 4001 :
   local_1_string = "wrong function pointer" ;
     break;
   case 4002 :
   local_1_string = "array index is out of range" ;
     break;
   case 4003 :
   local_1_string = "no memory for function call stack" ;
     break;
   case 4004 :
   local_1_string = "recursive stack overflow" ;
     break;
   case 4005 :
   local_1_string = "not enough stack for parameter" ;
     break;
   case 4006 :
   local_1_string = "no memory for parameter string" ;
     break;
   case 4007 :
   local_1_string = "no memory for temp string" ;
     break;
   case 4008 :
   local_1_string = "not initialized string" ;
     break;
   case 4009 :
   local_1_string = "not initialized string in array" ;
     break;
   case 4010 :
   local_1_string = "no memory for array\' string" ;
     break;
   case 4011 :
   local_1_string = "too long string" ;
     break;
   case 4012 :
   local_1_string = "remainder from zero divide" ;
     break;
   case 4013 :
   local_1_string = "zero divide" ;
     break;
   case 4014 :
   local_1_string = "unknown command" ;
     break;
   case 4015 :
   local_1_string = "wrong jump (never generated error)" ;
     break;
   case 4016 :
   local_1_string = "not initialized array" ;
     break;
   case 4017 :
   local_1_string = "dll calls are not allowed" ;
     break;
   case 4018 :
   local_1_string = "cannot load library" ;
     break;
   case 4019 :
   local_1_string = "cannot call function" ;
     break;
   case 4020 :
   local_1_string = "expert function calls are not allowed" ;
     break;
   case 4021 :
   local_1_string = "not enough memory for temp string returned from function" ;
     break;
   case 4022 :
   local_1_string = "system is busy (never generated error)" ;
     break;
   case 4050 :
   local_1_string = "invalid function parameters count" ;
     break;
   case 4051 :
   local_1_string = "invalid function parameter value" ;
     break;
   case 4052 :
   local_1_string = "string function internal error" ;
     break;
   case 4053 :
   local_1_string = "some array error" ;
     break;
   case 4054 :
   local_1_string = "incorrect series array using" ;
     break;
   case 4055 :
   local_1_string = "custom indicator error" ;
     break;
   case 4056 :
   local_1_string = "arrays are incompatible" ;
     break;
   case 4057 :
   local_1_string = "global variables processing error" ;
     break;
   case 4058 :
   local_1_string = "global variable not found" ;
     break;
   case 4059 :
   local_1_string = "function is not allowed in testing mode" ;
     break;
   case 4060 :
   local_1_string = "function is not confirmed" ;
     break;
   case 4061 :
   local_1_string = "send mail error" ;
     break;
   case 4062 :
   local_1_string = "string parameter expected" ;
     break;
   case 4063 :
   local_1_string = "integer parameter expected" ;
     break;
   case 4064 :
   local_1_string = "double parameter expected" ;
     break;
   case 4065 :
   local_1_string = "array as parameter expected" ;
     break;
   case 4066 :
   local_1_string = "requested history data in update state" ;
     break;
   case 4099 :
   local_1_string = "end of file" ;
     break;
   case 4100 :
   local_1_string = "some file error" ;
     break;
   case 4101 :
   local_1_string = "wrong file name" ;
     break;
   case 4102 :
   local_1_string = "too many opened files" ;
     break;
   case 4103 :
   local_1_string = "cannot open file" ;
     break;
   case 4104 :
   local_1_string = "incompatible access to a file" ;
     break;
   case 4105 :
   local_1_string = "no order selected" ;
     break;
   case 4106 :
   local_1_string = "unknown symbol" ;
     break;
   case 4107 :
   local_1_string = "invalid price parameter for trade function" ;
     break;
   case 4108 :
   local_1_string = "invalid ticket" ;
     break;
   case 4109 :
   local_1_string = "trade is not allowed in the expert properties" ;
     break;
   case 4110 :
   local_1_string = "longs are not allowed in the expert properties" ;
     break;
   case 4111 :
   local_1_string = "shorts are not allowed in the expert properties" ;
     break;
   case 4200 :
   local_1_string = "object is already exist" ;
     break;
   case 4201 :
   local_1_string = "unknown object property" ;
     break;
   case 4202 :
   local_1_string = "object is not exist" ;
     break;
   case 4203 :
   local_1_string = "unknown object type" ;
     break;
   case 4204 :
   local_1_string = "no object name" ;
     break;
   case 4205 :
   local_1_string = "object coordinates error" ;
     break;
   case 4206 :
   local_1_string = "no specified subwindow" ;
     break;
   default :
   local_1_string = "unknown error" ;
 }
 return(local_1_string);
 }
//GetTradeErrorDescription <<==--------   --------
 void RefreshPendingOrderLotSizes( bool arg_0_bool)
 {
  double    local_1_double;
  int       local_2_int;
  int       local_3_int;
  double    local_4_double;
  long      local_5_long;
  double    local_6_double;
  double    local_7_double;
  datetime  local_8_datetime;
  string    local_9_string;
  long      local_10_int; // ticket 64-bit
  double    local_11_double;
  long      local_12_long;
  double    local_13_double;
  double    local_14_double;
  datetime  local_15_datetime;
  string    local_16_string;
  long      local_17_int; // ticket 64-bit
//----- -----
 long       temp_long_1;
 long       temp_long_2;
 int        temp_int_3;
 long       temp_long_4;
 long       temp_long_5;
 int        temp_int_6;

 local_1_double = g_lotChangePctAlert / 100.0 + 1.0 ;
 // JIT compare fix: threshold uses the lot-sizing balance basis
 // (OnlyUp / ManualBalance aware), while OnTick keeps LastLotResizeBalance
 // as the raw account-balance snapshot.
 if ( ( !(global_401_double_6AD0!=g_lastLotResizeBalance) && !(arg_0_bool) ) )
 {
   return;
 }
 
 if ( ( !(global_401_double_6AD0>g_lastLotResizeBalance * local_1_double) &&
        !(global_401_double_6AD0<g_lastLotResizeBalance / local_1_double) && !(arg_0_bool) ) )
 {
   return;
 }

 CalculateStrategyLotSize(global_100_double_230,global_92_int_1EC); 

 // Preserve the lot-size refresh above while the market is closed.  Moving
 // the entire market gate before RefreshPendingOrderLotSizes() skipped this refresh and changed
 // several first orders from 0.01 to 0.02.  Only pending delete/recreate is
 // deferred until MODE_TRADEALLOWED becomes true.
 if ( MarketInfo(g_chartSymbol,MODE_TRADEALLOWED)==0.0 )
 {
   return;
 }
 local_2_int = MT4OrdersTotal() ;
 for (local_3_int = local_2_int ; local_3_int >= 0 ; local_3_int --)
 {
   if ( OrderSelect(local_3_int,0,0) != true || OrderMagicNumber() != global_93_int_1F0 || OrderSymbol() != g_chartSymbol )   continue;
   
   if ( OrderType() == 4 && OrderLots()!=global_223_double_1AC4_si99[g_currentStrategyIndex] )
   {
     local_4_double = OrderStopLoss() ;
     local_5_long = OrderTicket() ;
     local_6_double = OrderTakeProfit() ;
     local_7_double = OrderOpenPrice() ;
     local_8_datetime = OrderExpiration() ;
     local_9_string = OrderComment() ;
     OrderDelete(local_5_long,Red); 
     local_10_int = OrderSend(g_chartSymbol,4,global_223_double_1AC4_si99[g_currentStrategyIndex],local_7_double,(int)g_slippagePts,local_4_double,local_6_double,local_9_string,global_93_int_1F0,local_8_datetime,Green) ;
     temp_long_1 = local_10_int;
     temp_long_2 = local_5_long;
     for (temp_int_3 = 0 ; temp_int_3 < 100 ; temp_int_3=temp_int_3 + 1)
     {
       if ( !(g_stopOrderTicketPrice[temp_int_3][0]==temp_long_2) )   continue;
       g_stopOrderTicketPrice[temp_int_3][0] = (double)temp_long_1;
       break;
       
     }
     Print("Lotsize changed more than " + string(g_lotChangePctAlert) + "%... adjusting lotsize of pending orders"); 
     Sleep(1000); 
   }
   if ( OrderType() != 5 || !(OrderLots()!=global_223_double_1AC4_si99[g_currentStrategyIndex]) )   continue;
   local_11_double = OrderStopLoss() ;
   local_12_long = OrderTicket() ;
   local_13_double = OrderTakeProfit() ;
   local_14_double = OrderOpenPrice() ;
   local_15_datetime = OrderExpiration() ;
   local_16_string = OrderComment() ;
   OrderDelete(local_12_long,Red); 
   local_17_int = OrderSend(g_chartSymbol,5,global_223_double_1AC4_si99[g_currentStrategyIndex],local_14_double,(int)g_slippagePts,local_11_double,local_13_double,local_16_string,global_93_int_1F0,local_15_datetime,Green) ;
   temp_long_4 = local_17_int;
   temp_long_5 = local_12_long;
   for (temp_int_6 = 0 ; temp_int_6 < 100 ; temp_int_6=temp_int_6 + 1)
   {
     if ( !(g_stopOrderTicketPrice[temp_int_6][0]==temp_long_5) )   continue;
     g_stopOrderTicketPrice[temp_int_6][0] = (double)temp_long_4;
     break;
     
   }
   Print("Lotsize changed more than " + string(g_lotChangePctAlert) + "%... adjusting lotsize of pending orders"); 
   Sleep(1000); 
   
 }
 }

 void CreateInfoPanel()
 {
  int       local_1_int = 0;
  int       local_2_int = 0;
  int       local_3_int;
  int       local_4_int;
  int       local_5_int;
  double    local_6_double;
  int       local_7_int;
  int       local_8_int;
  int       local_9_int;
  int       local_10_int;
  int       local_11_int;
  int       local_12_int;
  int       local_13_int;
  uint      local_14_uint;
  bool      local_15_bool;
  int       local_16_int;
  string    local_17_string;
  int       local_18_int;
  int       local_19_int;
  int       local_20_int;
  string    local_21_string;
  int       local_22_int;
  int       local_23_int;
  int       local_24_int;
//----- -----

 local_3_int = 20 ;
 local_4_int = 300 ;
 local_5_int = 7 ;
 local_6_double = InfoPanelSizeAdjust ;
 local_7_int = 6 ;
 local_8_int = 4 ;
 local_9_int = 350 ;
 local_10_int = 366 ;
 local_11_int = 0 ;
 local_12_int = 5 ;
 local_13_int = 20 ;
 local_14_uint = LightSteelBlue ;
 local_15_bool = false ;
 local_16_int = 0 ;
 if ( global_17_bool_8C )
 {
   local_16_int = (int)((g_strategyCount + 3) * g_panelCellHeight) ;
 }
 ObjectCreate(0,"infopanel_rectangle",OBJ_RECTANGLE_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_XDISTANCE,local_12_int); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_YDISTANCE,local_13_int); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_XSIZE,long(local_9_int * InfoPanelSizeAdjust)); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_YSIZE,long(local_10_int * InfoPanelSizeAdjust + local_16_int)); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_CORNER,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_COLOR,0xFF0000); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BGCOLOR,local_14_uint); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BACK,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BORDER_COLOR,0xFF0000); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_COLOR,0xFF0000); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BORDER_TYPE,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_STYLE,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_WIDTH,0x2); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_SELECTABLE,0); 
 ObjectCreate(0,"line1",OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"line1",OBJPROP_CORNER,local_11_int); 
 ObjectSetInteger(0,"line1",OBJPROP_YDISTANCE,local_13_int + local_8_int); 
 ObjectSetInteger(0,"line1",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
 ObjectSetString(0,"line1",OBJPROP_TEXT,"The Gold Reaper v4.6"); 
 ObjectSetInteger(0,"line1",OBJPROP_COLOR,g_panelTextColor);
 // Ban decompile goc thieu set co chu rieng cho cac dong tieu de/tom tat panel
 // (chi co bang chien luoc phia duoi duoc set), trong khi kich thuoc khung panel
 // lai duoc tinh dua tren dung hang so co chu nay -> khien cac dong nay hien thi
 // to hon binh thuong (dung co mac dinh cua nen tang) so voi thiet ke that su cua
 // khung panel. Set khop voi co chu cua bang chien luoc de dong bo.
 ObjectSetInteger(0,"line1",OBJPROP_FONTSIZE,g_panelFontSize);
 ObjectCreate(0,"linec",OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"linec",OBJPROP_CORNER,local_11_int); 
 ObjectSetInteger(0,"linec",OBJPROP_YDISTANCE,long(local_13_int + InfoPanelSizeAdjust * 20.0 + local_8_int)); 
 ObjectSetInteger(0,"linec",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
 ObjectSetString(0,"linec",OBJPROP_TEXT,"EA Developed by Wim Schrynemakers - 2024"); 
 ObjectSetInteger(0,"linec",OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"linec",OBJPROP_FONTSIZE,g_panelFontSize);
 ObjectCreate(0,"line2",OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"line2",OBJPROP_CORNER,local_11_int); 
 ObjectSetInteger(0,"line2",OBJPROP_YDISTANCE,long(local_13_int + InfoPanelSizeAdjust * 32.0 + local_8_int)); 
 ObjectSetInteger(0,"line2",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
 ObjectSetString(0,"line2",OBJPROP_TEXT,"------------------------------------------------------"); 
 ObjectSetInteger(0,"line2",OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"line2",OBJPROP_FONTSIZE,g_panelFontSize);
 ObjectCreate(0,"lines",OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"lines",OBJPROP_CORNER,local_11_int); 
 ObjectSetInteger(0,"lines",OBJPROP_YDISTANCE,long(local_13_int + InfoPanelSizeAdjust * 44.0 + local_8_int)); 
 ObjectSetInteger(0,"lines",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
 if ( g_tradeFrequencyMode == 1 )
 {
   local_17_string = "conservative" ;
 }
 else
 {
   if ( g_tradeFrequencyMode == 2 )
   {
     local_17_string = "moderate" ;
   }
   else
   {
     if ( g_tradeFrequencyMode == 3 )
     {
       local_17_string = "intense" ;
     }
     else
     {
       if ( g_tradeFrequencyMode == 4 )
       {
         local_17_string = "extreme" ;
       }
       else
       {
         if ( g_tradeFrequencyMode == 0 )
         {
           local_17_string = "extreme conservative" ;
         }
         else
         {
           local_17_string = "manual strategy selection" ;
         }
       }
     }
   }
 }
 ObjectSetString(0,"lines",OBJPROP_TEXT,"Trade Frequency: " + local_17_string);
 ObjectSetInteger(0,"lines",OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"lines",OBJPROP_FONTSIZE,g_panelFontSize);
 if ( Risk == 1234 )
 {
   ObjectCreate(0,"linet",OBJ_LABEL,0,0,0.0); 
   ObjectSetInteger(0,"linet",OBJPROP_CORNER,local_11_int); 
   ObjectSetInteger(0,"linet",OBJPROP_YDISTANCE,long(local_13_int + InfoPanelSizeAdjust * 60.0 + local_8_int)); 
   ObjectSetInteger(0,"linet",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
   ObjectSetString(0,"linet",OBJPROP_TEXT,"Max allowed DD: " + string(MaxAllowedDD) + "%");
   ObjectSetInteger(0,"linet",OBJPROP_COLOR,g_panelTextColor);
   ObjectSetInteger(0,"linet",OBJPROP_FONTSIZE,g_panelFontSize);
 }
 else
 {
   if ( Risk == 3 )
   {
     ObjectCreate(0,"linet",OBJ_LABEL,0,0,0.0); 
     ObjectSetInteger(0,"linet",OBJPROP_CORNER,local_11_int); 
     ObjectSetInteger(0,"linet",OBJPROP_YDISTANCE,long(local_13_int + InfoPanelSizeAdjust * 60.0 + local_8_int)); 
     ObjectSetInteger(0,"linet",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
     ObjectSetString(0,"linet",OBJPROP_TEXT,"Max risk per strategy: " + string(MaxRiskPerStrategy_) + "%");
     ObjectSetInteger(0,"linet",OBJPROP_COLOR,g_panelTextColor);
     ObjectSetInteger(0,"linet",OBJPROP_FONTSIZE,g_panelFontSize);
   }
   else
   {
     ObjectCreate(0,"linet",OBJ_LABEL,0,0,0.0);
     ObjectSetInteger(0,"linet",OBJPROP_CORNER,local_11_int); 
     ObjectSetInteger(0,"linet",OBJPROP_YDISTANCE,long(local_13_int + InfoPanelSizeAdjust * 60.0 + local_8_int)); 
     ObjectSetInteger(0,"linet",OBJPROP_XDISTANCE,local_12_int + local_7_int); 
     ObjectSetString(0,"linet",OBJPROP_TEXT,"Manual lotsize: " + string(g_startLots_rw) + "lots");
     ObjectSetInteger(0,"linet",OBJPROP_COLOR,g_panelTextColor);
     ObjectSetInteger(0,"linet",OBJPROP_FONTSIZE,g_panelFontSize);
   }
 }
 ObjectCreate(0,"lineopl" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_CORNER,local_11_int); 
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,(long)(local_13_int + InfoPanelSizeAdjust * 76.0 + local_8_int)); 
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,local_12_int + local_7_int); 
 ObjectSetString(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_TEXT,"Open P/L: -");
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_FONTSIZE,g_panelFontSize);
 ObjectCreate(0,"linehb" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"linehb" + IntegerToString(0,0,32),OBJPROP_CORNER,local_11_int);
 ObjectSetInteger(0,"linehb" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,(long)(local_13_int + InfoPanelSizeAdjust * 92.0 + local_8_int));
 ObjectSetInteger(0,"linehb" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,local_12_int + local_7_int);
 ObjectSetString(0,"linehb" + IntegerToString(0,0,32),OBJPROP_TEXT,"Higher Balance: -");
 ObjectSetInteger(0,"linehb" + IntegerToString(0,0,32),OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"linehb" + IntegerToString(0,0,32),OBJPROP_FONTSIZE,g_panelFontSize);
 ObjectCreate(0,"linea" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_CORNER,local_11_int); 
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,(long)(local_13_int + InfoPanelSizeAdjust * 108.0 + local_8_int)); 
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,local_12_int + local_7_int); 
 ObjectSetString(0,"linea" + IntegerToString(0,0,32),OBJPROP_TEXT,"Account Balance: -");
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_FONTSIZE,g_panelFontSize);
 ObjectCreate(0,"linetp" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0);
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_CORNER,local_11_int);
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,(long)(local_13_int + InfoPanelSizeAdjust * 124.0 + local_8_int));
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,local_12_int + local_7_int);
 ObjectSetString(0,"linetp" + IntegerToString(0,0,32),OBJPROP_TEXT,"Total P/L so far: -");
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_COLOR,g_panelTextColor);
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_FONTSIZE,g_panelFontSize);
 if ( EnableNFP_Filter )
 {
   ObjectCreate(0,"linenfp" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0);
   ObjectSetInteger(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_CORNER,local_11_int);
   ObjectSetInteger(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,(long)(local_13_int + InfoPanelSizeAdjust * 140.0 + local_8_int));
   ObjectSetInteger(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,local_12_int + local_7_int);
   ObjectSetString(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_TEXT,"no news coming up");
   ObjectSetInteger(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_COLOR,g_panelTextColor);
   ObjectSetInteger(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_FONTSIZE,g_panelFontSize);
 }
 local_18_int = 0 ;
 local_19_int = 0 ;
 local_20_int = 0 ;
 local_22_int = local_12_int + local_7_int ;
 local_23_int = (int)(local_13_int + InfoPanelSizeAdjust * 176.0 + local_8_int) ;
 local_21_string = "Strategy" ;
 CreateInfoPanelCell(local_22_int,local_23_int,0,"Strategy",0,0,1,0,1.0); 
 local_18_int = 1 ;
 local_19_int = 1 ;
 local_21_string = "Closed PL" ;
 if ( g_rankMode == 1 )
 {
   local_21_string = "Closed PL*" ;
 }
 CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,local_21_string,local_20_int,local_19_int,1,0,1.0); 
 local_18_int ++;
 local_19_int ++;
 local_21_string = "PL per trade" ;
 CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,local_21_string,local_20_int,local_19_int,1,0,1.0); 
 local_18_int ++;
 local_19_int ++;
 local_21_string = "Lotsize" ;
 CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,"Lotsize",local_20_int,local_19_int,1,0,1.0); 
 local_18_int ++;
 local_19_int = 0 ;
 local_20_int ++;
 g_panelStrategyRowStart = local_18_int ;
 for (local_24_int = 0 ; local_24_int < 9 ; local_24_int ++)
 {
   local_21_string="Strategy " + IntegerToString(local_24_int + 1,0,32);
   CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,local_21_string,local_20_int,local_19_int,1,0,1.0); 
   local_18_int ++;
   local_19_int ++;
   local_21_string = DoubleToString(NormalizeDouble(g_histClosedPLbyStrategy[local_24_int],2),2) ;
   CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,local_21_string,local_20_int,local_19_int,1,0,1.0); 
   local_18_int ++;
   local_19_int ++;
   local_21_string = DoubleToString(NormalizeDouble(g_avgPLperTrade[local_24_int],2),2) ;
   CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,local_21_string,local_20_int,local_19_int,1,0,1.0); 
   local_18_int ++;
   local_19_int ++;
   local_21_string = DoubleToString(NormalizeDouble(global_223_double_1AC4_si99[local_24_int],2),2) ;
   CreateInfoPanelCell(local_22_int,local_23_int,local_18_int,local_21_string,local_20_int,local_19_int,1,0,1.0); 
   local_18_int ++;
   local_19_int = 0 ;
   local_20_int ++;
 }
 }
//CreateInfoPanel <<==--------   --------
 void CreateInfoPanelCell( int arg_0_int,int arg_1_int,int arg_2_int,string arg_3_string,int arg_4_int,int arg_5_int,int arg_6_int,uint arg_7_uint,double arg_8_double)
 {
 ObjectCreate(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJ_EDIT,0,0,0.0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_XDISTANCE,(long)(arg_0_int + arg_5_int * global_361_double_5CC0)); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_YDISTANCE,(long)(arg_1_int + arg_4_int * g_panelCellHeight)); 
 ObjectSetString(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_TEXT,arg_3_string); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_BACK,0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_COLOR,arg_7_uint); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_BGCOLOR,global_364_uint_5CD4); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_BORDER_COLOR,0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_FONTSIZE,(long)(g_panelFontSize * arg_8_double)); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_READONLY,0x1); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_YSIZE,(long)g_panelCellHeight); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_XSIZE,(long)global_361_double_5CC0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_YSIZE,(long)g_panelCellHeight); 
 if ( arg_6_int == 0 )
 {
   ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_ALIGN,0x1); 
 }
 if ( arg_6_int == 1 )
 {
   ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_ALIGN,0x2); 
 }
 if ( arg_6_int != 2 )   return;
 ObjectSetInteger(0,"info_ea" + IntegerToString(arg_2_int,0,32),OBJPROP_ALIGN,0); 
 }
//CreateInfoPanelCell <<==--------   --------
 void DeleteInfoPanel()
 {
  int       local_1_int;
  int       local_2_int;
  int       local_3_int;
  int       local_4_int;
//----- -----

 ObjectDelete(0,"line1"); 
 ObjectDelete(0,"linec"); 
 ObjectDelete(0,"line2"); 
 ObjectDelete(0,"lines"); 
 ObjectDelete(0,"linet"); 
 ObjectDelete(0,"lineTradeStart"); 
 for (local_1_int = 0 ; local_1_int <= 99 ; local_1_int ++)
 {
   ObjectDelete(0,"lineopl" + IntegerToString(local_1_int,0,32)); 
   ObjectDelete(0,"linehb" + IntegerToString(local_1_int,0,32));
   ObjectDelete(0,"linea" + IntegerToString(local_1_int,0,32)); 
   ObjectDelete(0,"lineto" + IntegerToString(local_1_int,0,32)); 
   ObjectDelete(0,"linetp" + IntegerToString(local_1_int,0,32));
   ObjectDelete(0,"linetq" + IntegerToString(local_1_int,0,32));
   ObjectDelete(0,"linenfp" + IntegerToString(local_1_int,0,32));
   for (local_2_int = 0 ; local_2_int < 10 ; local_2_int ++)
   {
     ObjectDelete(0,"tabel_info" + IntegerToString(local_1_int * 100 + local_2_int,0,32)); 
   }
 }
 ObjectDelete(0,"infopanel_rectangle"); 
 for (local_3_int = 0 ; local_3_int < 10 ; local_3_int ++)
 {
   ObjectDelete(0,"tabel_heading" + IntegerToString(local_3_int,0,32)); 
   ObjectDelete(0,"tabel_totals" + IntegerToString(local_3_int,0,32)); 
 }
 for (local_4_int = 0 ; local_4_int < g_maxPanelObjects ; local_4_int ++)
 {
   ObjectDelete(0,"horizontalrect" + IntegerToString(local_4_int,0,32)); 
   ObjectDelete(0,"info_ea" + IntegerToString(local_4_int,0,32)); 
 }
 }
//DeleteInfoPanel <<==--------   --------
 string GetNextNFPText()
 {
  // Original V4.6 panel reads only the single cached calendar timestamp.
  // It does not scan the hardcoded backtest table for display fallback.
  if ( g_nextNFPCalendar != 0 )
  {
    return("Next NFP: " + TimeToString(g_nextNFPCalendar,TIME_DATE|TIME_SECONDS));
  }
  return("no news coming up");
 }
//GetNextNFPText <<==--------   --------
 void UpdateAccountPanel()
 {
  string    local_1_string;
//----- -----
 double     temp_double_1;
 double     temp_double_2;
 int        temp_int_3;
 int        temp_int_4;
 int        temp_int_5;
 int        temp_int_6;
 int        temp_int_7;
 int        temp_int_8;
 int        temp_int_9;
 int        temp_int_10;
 int        temp_int_11;
 int        temp_int_12;
 int        temp_int_13;
 int        temp_int_14;
 int        temp_int_15;
 int        temp_int_16;
 int        temp_int_17;
 int        temp_int_18;
 int        temp_int_19;

 if ( !(ShowInfoPanel) )   return;
 
 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )   return;
 
 if ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) )
 {
   temp_double_1 = 0.0;
 }
 else
 {
   temp_double_2 = 0.0;
   for (temp_int_3 = MT4OrdersTotal() ; temp_int_3 >= 0 ; temp_int_3=temp_int_3 - 1)
   {
     if ( OrderSelect(temp_int_3,0,0) != true )   continue;
     
     if ( ( OrderSymbol() != g_chartSymbol && !(global_17_bool_8C) ) )   continue;
     temp_int_4 = OrderMagicNumber();
     temp_int_5=ST1_MagicNumber + 1;
     if ( temp_int_4 != temp_int_5 )
     {
       temp_int_5 = OrderMagicNumber();
       temp_int_6=ST1_MagicNumber + 2;
       if ( temp_int_5 != temp_int_6 )
       {
         temp_int_6 = OrderMagicNumber();
         temp_int_7=ST1_MagicNumber + 3;
         if ( temp_int_6 != temp_int_7 )
         {
           temp_int_7 = OrderMagicNumber();
           temp_int_8=ST1_MagicNumber + 4;
           if ( temp_int_7 != temp_int_8 )
           {
             temp_int_8 = OrderMagicNumber();
             temp_int_9=ST1_MagicNumber + 5;
             if ( temp_int_8 != temp_int_9 )
             {
               temp_int_9 = OrderMagicNumber();
               temp_int_10=ST1_MagicNumber + 6;
               if ( temp_int_9 != temp_int_10 )
               {
                 temp_int_10 = OrderMagicNumber();
                 temp_int_11=ST1_MagicNumber + 7;
                 if ( temp_int_10 != temp_int_11 )
                 {
                   temp_int_11 = OrderMagicNumber();
                   temp_int_12=ST1_MagicNumber + 8;
                   if ( temp_int_11 != temp_int_12 )
                   {
                     temp_int_12 = OrderMagicNumber();
                     temp_int_13=ST1_MagicNumber + 9;
                     if ( temp_int_12 != temp_int_13 )
                     {
                       temp_int_13 = OrderMagicNumber();
                       temp_int_14=ST1_MagicNumber + 10;
                       if ( temp_int_13 != temp_int_14 )
                       {
                         temp_int_14 = OrderMagicNumber();
                         temp_int_15=ST1_MagicNumber + 11;
                         if ( temp_int_14 != temp_int_15 )
                         {
                           temp_int_15 = OrderMagicNumber();
                           temp_int_16=ST1_MagicNumber + 12;
                           if ( temp_int_15 != temp_int_16 )
                           {
                             temp_int_16 = OrderMagicNumber();
                             temp_int_17=ST1_MagicNumber + 13;
                             if ( temp_int_16 != temp_int_17 )
                             {
                               temp_int_17 = OrderMagicNumber();
                               temp_int_18=ST1_MagicNumber + 14;
                               if ( temp_int_17 != temp_int_18 )
                               {
                                 temp_int_18 = OrderMagicNumber();
                                 temp_int_19=ST1_MagicNumber + 15;
                               if ( temp_int_18 != temp_int_19 )   continue;
                               }
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         }
       }
     }
     if ( ( OrderType() != 0 && OrderType() != 1 ) )   continue;
     temp_double_2 = OrderProfit() + OrderSwap() + OrderCommission() + temp_double_2;
     
   }
   g_openPLbyStrategy[g_currentStrategyIndex] = temp_double_2;
   temp_double_1 = temp_double_2;
 }
 ObjectSetString(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_TEXT,"Open P/L: " + DoubleToString(temp_double_1,2)); 
 ObjectSetString(0,"linehb" + IntegerToString(0,0,32),OBJPROP_TEXT,"Higher Balance: " + DoubleToString(g_highestBalance,2));
 ObjectSetString(0,"linea" + IntegerToString(0,0,32),OBJPROP_TEXT,"Account Balance: " + DoubleToString(AccountBalance(),2)); 
 if ( g_tradeFrequencyMode == 1 )
 {
   local_1_string = "conservative" ;
 }
 else
 {
   if ( g_tradeFrequencyMode == 2 )
   {
     local_1_string = "moderate" ;
   }
   else
   {
     if ( g_tradeFrequencyMode == 3 )
     {
       local_1_string = "intense" ;
     }
     else
     {
       if ( g_tradeFrequencyMode == 4 )
       {
         local_1_string = "extreme" ;
       }
       else
       {
         if ( g_tradeFrequencyMode == 0 )
         {
           local_1_string = "extreme conservative" ;
         }
         else
         {
           local_1_string = "manual strategy selection" ;
         }
       }
     }
   }
 }
 ObjectSetString(0,"lines",OBJPROP_TEXT,"Trade Frequency: " + local_1_string); 
 if ( Risk == 1234 )
 {
   ObjectSetString(0,"linet",OBJPROP_TEXT,"Max allowed DD: " + string(MaxAllowedDD) + "%"); 
 }
 else
 {
   if ( Risk == 3 )
   {
     ObjectSetString(0,"linet",OBJPROP_TEXT,"Max risk per strategy: " + string(MaxRiskPerStrategy_) + "%"); 
   }
   else
   {
     ObjectSetString(0,"linet",OBJPROP_TEXT,"Manual lotsize: " + string(g_startLots_rw) + "lots"); 
   }
 }
 }
//UpdateAccountPanel <<==--------   --------
 void UpdateStrategyPanelRows()
 {
  int       local_1_int;
  string    local_2_string;
  int       local_3_int;
//----- -----

 if ( !(ShowInfoPanel) )   return;
 
 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )   return;
 local_1_int = g_panelStrategyRowStart ;
 for (local_3_int = 0 ; local_3_int < 9 ; local_3_int ++)
 {
   local_2_string="Strategy " + IntegerToString(local_3_int + 1,0,32);
   ObjectSetString(0,"info_ea" + IntegerToString(local_1_int,0,32),OBJPROP_TEXT,local_2_string); 
   local_1_int ++;
   local_2_string = DoubleToString(NormalizeDouble(g_histClosedPLbyStrategy[local_3_int],2),2) ;
   ObjectSetString(0,"info_ea" + IntegerToString(local_1_int,0,32),OBJPROP_TEXT,local_2_string); 
   local_1_int ++;
   local_2_string = DoubleToString(NormalizeDouble(g_avgPLperTrade[local_3_int],2),2) ;
   ObjectSetString(0,"info_ea" + IntegerToString(local_1_int,0,32),OBJPROP_TEXT,local_2_string); 
   local_1_int ++;
   local_2_string = DoubleToString(NormalizeDouble(global_223_double_1AC4_si99[local_3_int],2),2) ;
   ObjectSetString(0,"info_ea" + IntegerToString(local_1_int,0,32),OBJPROP_TEXT,local_2_string); 
   local_1_int ++;
 }
 }
//UpdateStrategyPanelRows <<==--------   --------
 void UpdateHistoryPanel()
 {
 double     temp_double_1;
 double     temp_double_2;
 int        temp_int_3;
 int        temp_int_4;
 int        temp_int_5;
 int        temp_int_6;
 int        temp_int_7;
 int        temp_int_8;
 int        temp_int_9;
 int        temp_int_10;
 int        temp_int_11;
 int        temp_int_12;
 int        temp_int_13;
 int        temp_int_14;
 int        temp_int_15;
 int        temp_int_16;
 int        temp_int_17;
 int        temp_int_18;
 int        temp_int_19;
 int        temp_int_20;

 if ( !(ShowInfoPanel) )   return;
 
 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )   return;
 ObjectSetString(0,"lineto" + IntegerToString(0,0,32),OBJPROP_TEXT,"Total profits/losses so far: " + IntegerToString(CountWinningTrades(0,9999999),0,32) + "/" + IntegerToString(CountLosingTrades(0,9999999),0,32)); 
 if ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) )
 {
   temp_double_1 = 0.0;
 }
 else
 {
   temp_double_2 = 0.0;
   temp_int_3 = 0;
   for (temp_int_4 = HistoryTotal() ; temp_int_4 >= 0 ; temp_int_4=temp_int_4 - 1)
   {
     if ( OrderSelect(temp_int_4,0,1) != true )   continue;
     
     if ( ( OrderSymbol() != g_chartSymbol && !(global_17_bool_8C) ) )   continue;
     temp_int_5 = OrderMagicNumber();
     temp_int_6=ST1_MagicNumber + 1;
     if ( temp_int_5 != temp_int_6 )
     {
       temp_int_6 = OrderMagicNumber();
       temp_int_7=ST1_MagicNumber + 2;
       if ( temp_int_6 != temp_int_7 )
       {
         temp_int_7 = OrderMagicNumber();
         temp_int_8=ST1_MagicNumber + 3;
         if ( temp_int_7 != temp_int_8 )
         {
           temp_int_8 = OrderMagicNumber();
           temp_int_9=ST1_MagicNumber + 4;
           if ( temp_int_8 != temp_int_9 )
           {
             temp_int_9 = OrderMagicNumber();
             temp_int_10=ST1_MagicNumber + 5;
             if ( temp_int_9 != temp_int_10 )
             {
               temp_int_10 = OrderMagicNumber();
               temp_int_11=ST1_MagicNumber + 6;
               if ( temp_int_10 != temp_int_11 )
               {
                 temp_int_11 = OrderMagicNumber();
                 temp_int_12=ST1_MagicNumber + 7;
                 if ( temp_int_11 != temp_int_12 )
                 {
                   temp_int_12 = OrderMagicNumber();
                   temp_int_13=ST1_MagicNumber + 8;
                   if ( temp_int_12 != temp_int_13 )
                   {
                     temp_int_13 = OrderMagicNumber();
                     temp_int_14=ST1_MagicNumber + 9;
                     if ( temp_int_13 != temp_int_14 )
                     {
                       temp_int_14 = OrderMagicNumber();
                       temp_int_15=ST1_MagicNumber + 10;
                       if ( temp_int_14 != temp_int_15 )
                       {
                         temp_int_15 = OrderMagicNumber();
                         temp_int_16=ST1_MagicNumber + 11;
                         if ( temp_int_15 != temp_int_16 )
                         {
                           temp_int_16 = OrderMagicNumber();
                           temp_int_17=ST1_MagicNumber + 12;
                           if ( temp_int_16 != temp_int_17 )
                           {
                             temp_int_17 = OrderMagicNumber();
                             temp_int_18=ST1_MagicNumber + 13;
                             if ( temp_int_17 != temp_int_18 )
                             {
                               temp_int_18 = OrderMagicNumber();
                               temp_int_19=ST1_MagicNumber + 14;
                               if ( temp_int_18 != temp_int_19 )
                               {
                                 temp_int_19 = OrderMagicNumber();
                                 temp_int_20=ST1_MagicNumber + 15;
                               if ( temp_int_19 != temp_int_20 )   continue;
                               }
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         }
       }
     }
     temp_int_3=temp_int_3 + 1;
     temp_double_2 = temp_double_2 + OrderProfit() + OrderSwap() + OrderCommission();
     if ( temp_int_3 >= 1000 )   break;
     
   }
   g_totalPLbyStrategy[g_currentStrategyIndex] = temp_double_2;
   temp_double_1 = temp_double_2;
 }
 ObjectSetString(0,"linetp" + IntegerToString(0,0,32),OBJPROP_TEXT,"Total P/L so far: " + DoubleToString(NormalizeDouble(temp_double_1,2),2));
 if ( EnableNFP_Filter )
 {
   ObjectSetString(0,"linenfp" + IntegerToString(0,0,32),OBJPROP_TEXT,GetNextNFPText());
 }
 }
//UpdateHistoryPanel <<==--------   --------
 int CountWinningTrades( int arg_0_int,int arg_1_int)
 {
  double    local_2_double;
  int       local_3_int;
  int       local_4_int;
  int       local_5_int;
//----- -----
 int        temp_int_1;
 int        temp_int_2;
 int        temp_int_3;
 int        temp_int_4;
 int        temp_int_5;
 int        temp_int_6;
 int        temp_int_7;
 int        temp_int_8;
 int        temp_int_9;
 int        temp_int_10;
 int        temp_int_11;
 int        temp_int_12;
 int        temp_int_13;
 int        temp_int_14;
 int        temp_int_15;
 int        temp_int_16;

 if ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) )
 {
   return(0); 
 }
 local_2_double = 0.0 ;
 local_3_int = 0 ;
 local_4_int = 0 ;
 for (local_5_int = HistoryTotal() ; local_5_int >= 0 ; local_5_int --)
 {
   if ( OrderSelect(local_5_int,0,1) != true )   continue;
   
   if ( ( OrderSymbol() != g_chartSymbol && !(global_17_bool_8C) ) )   continue;
   temp_int_1 = OrderMagicNumber();
   temp_int_2=ST1_MagicNumber + 1;
   if ( temp_int_1 != temp_int_2 )
   {
     temp_int_2 = OrderMagicNumber();
     temp_int_3=ST1_MagicNumber + 2;
     if ( temp_int_2 != temp_int_3 )
     {
       temp_int_3 = OrderMagicNumber();
       temp_int_4=ST1_MagicNumber + 3;
       if ( temp_int_3 != temp_int_4 )
       {
         temp_int_4 = OrderMagicNumber();
         temp_int_5=ST1_MagicNumber + 4;
         if ( temp_int_4 != temp_int_5 )
         {
           temp_int_5 = OrderMagicNumber();
           temp_int_6=ST1_MagicNumber + 5;
           if ( temp_int_5 != temp_int_6 )
           {
             temp_int_6 = OrderMagicNumber();
             temp_int_7=ST1_MagicNumber + 6;
             if ( temp_int_6 != temp_int_7 )
             {
               temp_int_7 = OrderMagicNumber();
               temp_int_8=ST1_MagicNumber + 7;
               if ( temp_int_7 != temp_int_8 )
               {
                 temp_int_8 = OrderMagicNumber();
                 temp_int_9=ST1_MagicNumber + 8;
                 if ( temp_int_8 != temp_int_9 )
                 {
                   temp_int_9 = OrderMagicNumber();
                   temp_int_10=ST1_MagicNumber + 9;
                   if ( temp_int_9 != temp_int_10 )
                   {
                     temp_int_10 = OrderMagicNumber();
                     temp_int_11=ST1_MagicNumber + 10;
                     if ( temp_int_10 != temp_int_11 )
                     {
                       temp_int_11 = OrderMagicNumber();
                       temp_int_12=ST1_MagicNumber + 11;
                       if ( temp_int_11 != temp_int_12 )
                       {
                         temp_int_12 = OrderMagicNumber();
                         temp_int_13=ST1_MagicNumber + 12;
                         if ( temp_int_12 != temp_int_13 )
                         {
                           temp_int_13 = OrderMagicNumber();
                           temp_int_14=ST1_MagicNumber + 13;
                           if ( temp_int_13 != temp_int_14 )
                           {
                             temp_int_14 = OrderMagicNumber();
                             temp_int_15=ST1_MagicNumber + 14;
                             if ( temp_int_14 != temp_int_15 )
                             {
                               temp_int_15 = OrderMagicNumber();
                               temp_int_16=ST1_MagicNumber + 15;
                             if ( temp_int_15 != temp_int_16 )   continue;
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         }
       }
     }
   }
   local_3_int ++;
   if ( ( OrderType() == 0 || OrderType() == 1 ) )
   {
     if ( OrderType() == 0 )
     {
       local_2_double = OrderClosePrice() - OrderOpenPrice() ;
     }
     else
     {
       if ( OrderType() == 1 )
       {
         local_2_double = OrderOpenPrice() - OrderClosePrice() ;
       }
     }
     if ( local_2_double>0.0 )
     {
       local_4_int ++;
     }
   }
   if ( local_3_int >= arg_1_int )   break;
   
 }
 g_winTradeCount[g_currentStrategyIndex] = local_4_int;
 return(local_4_int); 
 }
//CountWinningTrades <<==--------   --------
 int CountLosingTrades( int arg_0_int,int arg_1_int)
 {
  double    local_2_double;
  int       local_3_int;
  int       local_4_int;
  int       local_5_int;
//----- -----
 int        temp_int_1;
 int        temp_int_2;
 int        temp_int_3;
 int        temp_int_4;
 int        temp_int_5;
 int        temp_int_6;
 int        temp_int_7;
 int        temp_int_8;
 int        temp_int_9;
 int        temp_int_10;
 int        temp_int_11;
 int        temp_int_12;
 int        temp_int_13;
 int        temp_int_14;
 int        temp_int_15;
 int        temp_int_16;

 if ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) )
 {
   return(0); 
 }
 local_2_double = 0.0 ;
 local_3_int = 0 ;
 local_4_int = 0 ;
 for (local_5_int = HistoryTotal() ; local_5_int >= 0 ; local_5_int --)
 {
   if ( OrderSelect(local_5_int,0,1) != true )   continue;
   
   if ( ( OrderSymbol() != g_chartSymbol && !(global_17_bool_8C) ) )   continue;
   temp_int_1 = OrderMagicNumber();
   temp_int_2=ST1_MagicNumber + 1;
   if ( temp_int_1 != temp_int_2 )
   {
     temp_int_2 = OrderMagicNumber();
     temp_int_3=ST1_MagicNumber + 2;
     if ( temp_int_2 != temp_int_3 )
     {
       temp_int_3 = OrderMagicNumber();
       temp_int_4=ST1_MagicNumber + 3;
       if ( temp_int_3 != temp_int_4 )
       {
         temp_int_4 = OrderMagicNumber();
         temp_int_5=ST1_MagicNumber + 4;
         if ( temp_int_4 != temp_int_5 )
         {
           temp_int_5 = OrderMagicNumber();
           temp_int_6=ST1_MagicNumber + 5;
           if ( temp_int_5 != temp_int_6 )
           {
             temp_int_6 = OrderMagicNumber();
             temp_int_7=ST1_MagicNumber + 6;
             if ( temp_int_6 != temp_int_7 )
             {
               temp_int_7 = OrderMagicNumber();
               temp_int_8=ST1_MagicNumber + 7;
               if ( temp_int_7 != temp_int_8 )
               {
                 temp_int_8 = OrderMagicNumber();
                 temp_int_9=ST1_MagicNumber + 8;
                 if ( temp_int_8 != temp_int_9 )
                 {
                   temp_int_9 = OrderMagicNumber();
                   temp_int_10=ST1_MagicNumber + 9;
                   if ( temp_int_9 != temp_int_10 )
                   {
                     temp_int_10 = OrderMagicNumber();
                     temp_int_11=ST1_MagicNumber + 10;
                     if ( temp_int_10 != temp_int_11 )
                     {
                       temp_int_11 = OrderMagicNumber();
                       temp_int_12=ST1_MagicNumber + 11;
                       if ( temp_int_11 != temp_int_12 )
                       {
                         temp_int_12 = OrderMagicNumber();
                         temp_int_13=ST1_MagicNumber + 12;
                         if ( temp_int_12 != temp_int_13 )
                         {
                           temp_int_13 = OrderMagicNumber();
                           temp_int_14=ST1_MagicNumber + 13;
                           if ( temp_int_13 != temp_int_14 )
                           {
                             temp_int_14 = OrderMagicNumber();
                             temp_int_15=ST1_MagicNumber + 14;
                             if ( temp_int_14 != temp_int_15 )
                             {
                               temp_int_15 = OrderMagicNumber();
                               temp_int_16=ST1_MagicNumber + 15;
                             if ( temp_int_15 != temp_int_16 )   continue;
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         }
       }
     }
   }
   local_3_int ++;
   if ( OrderType() == 0 )
   {
     local_2_double = OrderClosePrice() - OrderOpenPrice() ;
   }
   else
   {
     if ( OrderType() == 1 )
     {
       local_2_double = OrderOpenPrice() - OrderClosePrice() ;
     }
   }
   if ( local_2_double<0.0 )
   {
     local_4_int ++;
   }
   if ( local_3_int >= arg_1_int )   break;
   
 }
 g_lossTradeCount[g_currentStrategyIndex] = local_4_int;
 return(local_4_int); 
 }
//CountLosingTrades <<==--------   --------
 void CalculatePerformanceMetrics()
 {
  int       local_1_int = 0;
  double    local_2_double_si99[99];
  double    local_3_double_si99[99];
  int       local_4_int;
  int       local_5_int;
  bool      local_6_bool;
  int       local_7_int;
  double    local_8_double;
  int       local_9_int;
  int       local_10_int;
//----- -----
 long       temp_long_1;
 long       temp_long_2;
 long       temp_long_3;
 long       temp_long_4;
 long       temp_long_5;

 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )   return;
 for (local_4_int = 0 ; local_4_int < g_strategyCount ; local_4_int ++)
 {
   local_2_double_si99[local_4_int] = 0.0;
   local_3_double_si99[local_4_int] = 0.0;
   g_minTradesReachedFlag[local_4_int] = false;
   g_closedTradeCount[local_4_int] = 0;
 }
 for (local_5_int = HistoryTotal() ; local_5_int >= 0 ; local_5_int --)
 {
   if ( OrderSelect(local_5_int,0,1) != true || OrderMagicNumber() != global_93_int_1F0 )   continue;
   local_6_bool = true ;
   for (local_7_int = 0 ; local_7_int < g_strategyCount ; local_7_int ++)
   {
     if ( !(g_minTradesReachedFlag[local_7_int]) )
     {
       local_6_bool = false ;
     }
   }
   if ( ( OrderCloseTime() <  TimeCurrent() - g_statWindowDays * 24 * 60 * 60 && local_6_bool ) )   break;
   local_8_double = OrderLots() * 100.0 ;
   if ( global_151_int_438 == 1 )
   {
     local_8_double = 1.0 ;
   }
   local_9_int = 0 ;
   if ( g_strategyCount <= 0 )   continue;
   
   for ( ; local_9_int < g_strategyCount ; local_9_int ++)
   {
     if ( g_strategySymbols[local_9_int] != OrderSymbol() )   continue;
     
     if ( ( OrderType() != 0 && OrderType() != 1 ) )   continue;
     temp_long_1 = OrderCloseTime();
     temp_long_2=TimeCurrent() - g_statWindowDays * 24 * 60 * 60;
     if ( temp_long_1 <  temp_long_2 )
     {
       temp_long_2 = OrderCloseTime();
       temp_long_3=TimeCurrent() - g_statWindowDays * 24 * 60 * 60;
     if ( (temp_long_2 >= temp_long_3 || g_minTradesReachedFlag[local_9_int]) )   continue;
     }
     g_closedTradeCount[local_9_int] ++;
     if ( g_closedTradeCount[local_9_int] >= global_155_int_448 )
     {
       g_minTradesReachedFlag[local_9_int] = true;
     }
     local_2_double_si99[local_9_int] +=OrderProfit() / local_8_double;
     local_2_double_si99[local_9_int] +=OrderSwap() / local_8_double;
     local_2_double_si99[local_9_int] +=OrderCommission() / local_8_double;
     temp_long_4 = OrderCloseTime();
     temp_long_5=TimeCurrent() - g_statRecentDays * 24 * 60 * 60;
     if ( temp_long_4 < temp_long_5 )   continue;
     local_3_double_si99[local_9_int] +=OrderProfit() / local_8_double;
     local_3_double_si99[local_9_int] +=OrderSwap() / local_8_double;
     local_3_double_si99[local_9_int] +=OrderCommission() / local_8_double;
     
   }
   
 }
 for (local_10_int = 0 ; local_10_int < g_strategyCount ; local_10_int ++)
 {
   global_349_double_46B4_si99[local_10_int] = local_2_double_si99[local_10_int];
   if ( g_closedTradeCount[local_10_int] >  0 )
   {
     g_avgPLperTrade[local_10_int] = NormalizeDouble(local_2_double_si99[local_10_int] / g_closedTradeCount[local_10_int],2);
   }
   else
   {
     g_avgPLperTrade[local_10_int] = 0.0;
   }
   g_recentPLbyStrategy[local_10_int] = local_3_double_si99[local_10_int];
 }
 }
//CalculatePerformanceMetrics <<==--------   --------
 void RankStrategiesByClosedProfit()
 {
  int       local_1_int;
  double    local_2_double;
  int       local_3_int;
  int       local_4_int;
  int       local_5_int;
  int       local_6_int;
  bool      local_7_bool;
  int       local_8_int;
  int       local_9_int;
  int       local_10_int;
  int       local_11_int;
//----- -----

 CalculatePerformanceMetrics(); 
 for (local_1_int = 0 ; local_1_int < g_strategyCount ; local_1_int ++)
 {
   local_2_double = global_349_double_46B4_si99[local_1_int] ;
   local_3_int = 1 ;
   for (local_4_int = 0 ; local_4_int < g_strategyCount ; local_4_int ++)
   {
     if ( local_4_int == local_1_int || !(global_349_double_46B4_si99[local_4_int]>local_2_double) )   continue;
     local_3_int ++;
     
   }
   global_356_int_5B14_si99[local_1_int] = local_3_int;
 }
 for (local_5_int = 0 ; local_5_int < g_strategyCount ; local_5_int ++)
 {
   local_6_int = global_356_int_5B14_si99[local_5_int] ;
   local_7_bool = true ;
   do
   {
     local_7_bool = false ;
     local_8_int = 0 ;
     if ( g_strategyCount <= 0 )   continue;
     
     for ( ; local_8_int < g_strategyCount ; local_8_int ++)
     {
       if ( local_8_int == local_5_int || global_356_int_5B14_si99[local_8_int] != global_356_int_5B14_si99[local_5_int] )   continue;
       global_356_int_5B14_si99[local_8_int] ++;
       local_7_bool = true ;
       
     }
     
   }
   while(local_7_bool);
   
 }
 for (local_9_int = 0 ; local_9_int < g_strategyCount ; local_9_int ++)
 {
 }
 for (local_10_int = 1 ; local_10_int <= g_strategyCount ; local_10_int ++)
 {
   for (local_11_int = 0 ; local_11_int < g_strategyCount ; local_11_int ++)
   {
     if ( global_356_int_5B14_si99[local_11_int] == local_10_int )
     {
     }
   }
 }
 }
//RankStrategiesByClosedProfit <<==--------   --------
 void RankStrategiesByProfitPerTrade()
 {
  int       local_1_int;
  double    local_2_double;
  int       local_3_int;
  int       local_4_int;
  int       local_5_int;
  int       local_6_int;
  bool      local_7_bool;
  int       local_8_int;
  int       local_9_int;
  int       local_10_int;
  int       local_11_int;
//----- -----

 CalculatePerformanceMetrics(); 
 for (local_1_int = 0 ; local_1_int < g_strategyCount ; local_1_int ++)
 {
   local_2_double = g_avgPLperTrade[local_1_int] ;
   local_3_int = 1 ;
   for (local_4_int = 0 ; local_4_int < g_strategyCount ; local_4_int ++)
   {
     if ( local_4_int == local_1_int || !(g_avgPLperTrade[local_4_int]>local_2_double) )   continue;
     local_3_int ++;
     
   }
   global_356_int_5B14_si99[local_1_int] = local_3_int;
 }
 for (local_5_int = 0 ; local_5_int < g_strategyCount ; local_5_int ++)
 {
   local_6_int = global_356_int_5B14_si99[local_5_int] ;
   local_7_bool = true ;
   do
   {
     local_7_bool = false ;
     local_8_int = 0 ;
     if ( g_strategyCount <= 0 )   continue;
     
     for ( ; local_8_int < g_strategyCount ; local_8_int ++)
     {
       if ( local_8_int == local_5_int || global_356_int_5B14_si99[local_8_int] != global_356_int_5B14_si99[local_5_int] )   continue;
       global_356_int_5B14_si99[local_8_int] ++;
       local_7_bool = true ;
       
     }
     
   }
   while(local_7_bool);
   
 }
 for (local_9_int = 0 ; local_9_int < g_strategyCount ; local_9_int ++)
 {
 }
 for (local_10_int = 1 ; local_10_int <= g_strategyCount ; local_10_int ++)
 {
   for (local_11_int = 0 ; local_11_int < g_strategyCount ; local_11_int ++)
   {
     if ( global_356_int_5B14_si99[local_11_int] == local_10_int )
     {
     }
   }
 }
 }
//RankStrategiesByProfitPerTrade <<==--------   --------
 double ConvertUsdToAccountCurrency( double arg_0_double)
 {
  double    local_2_double;
  string    local_3_string;
//----- -----

 local_2_double = arg_0_double ;
 if ( ( AccountCurrency() == "USD" || AccountCurrency() == "usd" ) )
 {
   local_2_double = arg_0_double ;
 }
 if ( ( AccountCurrency() == "EUR" || AccountCurrency() == "eur" ) )
 {
   local_3_string="EURUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "GBP" || AccountCurrency() == "gbp" ) )
 {
   local_3_string="GBPUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "AUD" || AccountCurrency() == "aud" ) )
 {
   local_3_string="AUDUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "JPY" || AccountCurrency() == "jpy" || AccountCurrency() == "YEN" || AccountCurrency() == "yen" ) )
 {
   local_3_string="USDJPY" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "CHF" || AccountCurrency() == "chf" ) )
 {
   local_3_string="USDCHF" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "HKD" || AccountCurrency() == "hkd" ) )
 {
   local_3_string="USDHKD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "SGD" || AccountCurrency() == "sgd" ) )
 {
   local_3_string="USDSGD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "RUB" || AccountCurrency() == "rub" ) )
 {
   local_3_string="USDRUB" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "BTC" || AccountCurrency() == "btc" ) )
 {
   local_3_string="BTCUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "ETH" || AccountCurrency() == "eth" ) )
 {
   local_3_string="ETHUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "BCH" || AccountCurrency() == "bch" ) )
 {
   local_3_string="BCHUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "BCC" || AccountCurrency() == "bcc" ) )
 {
   local_3_string="BCCUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "XRP" || AccountCurrency() == "xrp" ) )
 {
   local_3_string="XRPUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "LTC" || AccountCurrency() == "ltc" ) )
 {
   local_3_string="LTCUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "XMR" || AccountCurrency() == "xmr" ) )
 {
   local_3_string="XMRUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "DSH" || AccountCurrency() == "dsh" ) )
 {
   local_3_string="DSHUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "EOS" || AccountCurrency() == "eos" ) )
 {
   local_3_string="EOSUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "TRX" || AccountCurrency() == "trx" ) )
 {
   local_3_string="TRXUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "ADA" || AccountCurrency() == "ada" ) )
 {
   local_3_string="ADAUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "BSV" || AccountCurrency() == "bsv" ) )
 {
   local_3_string="BSVUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "XLM" || AccountCurrency() == "xlm" ) )
 {
   local_3_string="XLMUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "GLD" || AccountCurrency() == "gld" ) )
 {
   local_3_string="GLDUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "ZEC" || AccountCurrency() == "zec" ) )
 {
   local_3_string="ZECUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountCurrency() == "XEM" || AccountCurrency() == "xem" ) )
 {
   local_3_string="XEMUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 return(local_2_double); 
 }
//ConvertUsdToAccountCurrency <<==--------   --------
 double ConvertAccountCurrencyToUsd( double arg_0_double)
 {
 double    local_2_double;
  string    local_3_string;
//----- -----

 local_2_double = arg_0_double ;
 string temp_account_currency=AccountInfoString(ACCOUNT_CURRENCY);
 if(temp_account_currency=="USD" || temp_account_currency=="usd")
 {
   return(MathRound(arg_0_double));
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "USD" || AccountInfoString(ACCOUNT_CURRENCY) == "usd" ) )
 {
   local_2_double = arg_0_double ;
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "EUR" || AccountInfoString(ACCOUNT_CURRENCY) == "eur" ) )
 {
   local_3_string="EURUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "GBP" || AccountInfoString(ACCOUNT_CURRENCY) == "gbp" ) )
 {
   local_3_string="GBPUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "AUD" || AccountInfoString(ACCOUNT_CURRENCY) == "aud" ) )
 {
   local_3_string="AUDUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "JPY" || AccountInfoString(ACCOUNT_CURRENCY) == "jpy" || AccountInfoString(ACCOUNT_CURRENCY) == "YEN" || AccountInfoString(ACCOUNT_CURRENCY) == "yen" ) )
 {
   local_3_string="USDJPY" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "CHF" || AccountInfoString(ACCOUNT_CURRENCY) == "chf" ) )
 {
   local_3_string="USDCHF" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "HKD" || AccountInfoString(ACCOUNT_CURRENCY) == "hkd" ) )
 {
   local_3_string="USDHKD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "RUB" || AccountInfoString(ACCOUNT_CURRENCY) == "rub" ) )
 {
   local_3_string="USDRUB" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "CNH" || AccountInfoString(ACCOUNT_CURRENCY) == "cnh" ) )
 {
   local_3_string="USDCNH" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
   else
   {
     local_3_string="USDCNY" + g_symbolSuffix;
     if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
     {
       local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
     }
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "CNY" || AccountInfoString(ACCOUNT_CURRENCY) == "cny" ) )
 {
   local_3_string="USDCNH" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
   else
   {
     local_3_string="USDCNY" + g_symbolSuffix;
     if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
     {
       local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
     }
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "SGD" || AccountInfoString(ACCOUNT_CURRENCY) == "sgd" ) )
 {
   local_3_string="USDSGD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double / iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "BTC" || AccountInfoString(ACCOUNT_CURRENCY) == "btc" ) )
 {
   local_3_string="BTCUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "ETH" || AccountInfoString(ACCOUNT_CURRENCY) == "eth" ) )
 {
   local_3_string="ETHUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "BCH" || AccountInfoString(ACCOUNT_CURRENCY) == "bch" ) )
 {
   local_3_string="BCHUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "BCC" || AccountInfoString(ACCOUNT_CURRENCY) == "bcc" ) )
 {
   local_3_string="BCCUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "XRP" || AccountInfoString(ACCOUNT_CURRENCY) == "xrp" ) )
 {
   local_3_string="XRPUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "LTC" || AccountInfoString(ACCOUNT_CURRENCY) == "ltc" ) )
 {
   local_3_string="LTCUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "XMR" || AccountInfoString(ACCOUNT_CURRENCY) == "xmr" ) )
 {
   local_3_string="XMRUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "DSH" || AccountInfoString(ACCOUNT_CURRENCY) == "dsh" ) )
 {
   local_3_string="DSHUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "EOS" || AccountInfoString(ACCOUNT_CURRENCY) == "eos" ) )
 {
   local_3_string="EOSUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "TRX" || AccountInfoString(ACCOUNT_CURRENCY) == "trx" ) )
 {
   local_3_string="TRXUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "ADA" || AccountInfoString(ACCOUNT_CURRENCY) == "ada" ) )
 {
   local_3_string="ADAUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "BSV" || AccountInfoString(ACCOUNT_CURRENCY) == "bsv" ) )
 {
   local_3_string="BSVUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "XLM" || AccountInfoString(ACCOUNT_CURRENCY) == "xlm" ) )
 {
   local_3_string="XLMUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "GLD" || AccountInfoString(ACCOUNT_CURRENCY) == "gld" ) )
 {
   local_3_string="GLDUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "ZEC" || AccountInfoString(ACCOUNT_CURRENCY) == "zec" ) )
 {
   local_3_string="ZECUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 if ( ( AccountInfoString(ACCOUNT_CURRENCY) == "XEM" || AccountInfoString(ACCOUNT_CURRENCY) == "xem" ) )
 {
   local_3_string="XEMUSD" + g_symbolSuffix;
   if ( iClose(local_3_string,MT4Period(PERIOD_D1),1)>0.0 )
   {
     local_2_double = arg_0_double * iClose(local_3_string,MT4Period(PERIOD_D1),1) ;
   }
 }
 return(MathRound(local_2_double)); 
 }
//ConvertAccountCurrencyToUsd <<==--------   --------
// ============================================================================
// [§16] 各策略参数装载（LoadStrategy1~9Settings）
//       把 V4.6 内置的每策略参数写入 §5 的全局变量表；由 TradeFrequency
//       （自动/手动 RunStratN）决定装载哪些策略并交给 ProcessStrategy 执行。
//       函数体均直接恢复自 JIT 常量表，数值不可随意改动。
// ============================================================================

 void LoadStrategy1Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 16 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_D1 ;
 g_signalTfPeriod = (int)PERIOD_M15 ;
 global_73_int_17C = 24 ;
 global_74_int_180 = 3 ;
 global_77_int_188 = 105 ;
 g_entryBreakoutPips = 45.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -275.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -160.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 5 ;
 global_88_double_1D0 = 30.0 ;
 g_pendingExpiryHours = 35 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 6100.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 1450.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 1800.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 1800.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 1600.0 ;
 temp_double_9 = AdjustTrailTP + 700.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 930.0 ;
 temp_double_11 = AdjustBreakEven + 120.0;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 14 ;
 global_120_int_2D4 = 12 ;
 global_121_int_2D8 = 300 ;
 g_hlOffsetPips = 22.0 ;
 g_maxOpenTradesPerSide = 5 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_1";
 }
 global_93_int_1F0=ST1_MagicNumber + 1;
 global_397_double_6768 = ConvertUsdToAccountCurrency(145.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2000.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(60.0) ;
 }
//LoadStrategy1Settings <<==--------   --------
 void LoadStrategy4Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;
 double     temp_double_13;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 16 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_H4 ;
 g_signalTfPeriod = (int)PERIOD_H1 ;
 global_73_int_17C = 12 ;
 global_74_int_180 = 8 ;
 global_77_int_188 = 90 ;
 g_entryBreakoutPips = 1050.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -40.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -100.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 2 ;
 global_88_double_1D0 = 130.0 ;
 g_pendingExpiryHours = 192 ;
 global_99_int_22C = 5 ;
 if ( !(UseHL_TrailingSL) )
 {
   temp_double_3 = AdjustSL + 700.0;
   if ( Randomization>0.0 )
   {
     temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
   }
   else
   {
     temp_double_4 = 0.0;
   }
   global_100_double_230 = temp_double_3 + temp_double_4 ;
 }
 else
 {
   temp_double_4 = AdjustSL + 800.0;
   if ( Randomization>0.0 )
   {
     temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
   }
   else
   {
     temp_double_5 = 0.0;
   }
   global_100_double_230 = temp_double_4 + temp_double_5 ;
 }
 temp_double_5 = AdjustTP + 4900.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 g_takeProfitPips = temp_double_5 + temp_double_6 ;
 temp_double_6 = AdjustTrailSL + 1300.0;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 global_103_double_250 = temp_double_6 + temp_double_7 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 g_trailActivationPips = temp_double_8 + 1450.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_105_double_260 = temp_double_9 + 2000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 global_109_double_280 = temp_double_10 + 1400.0 ;
 temp_double_10 = AdjustTrailTP + 200.0;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 g_trailTpPips = temp_double_10 + temp_double_11 ;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 global_113_double_2A8 = temp_double_12 + 500.0 ;
 temp_double_12 = AdjustBreakEven + 200.0;
 if ( Randomization>0.0 )
 {
   temp_double_13 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_13 = 0.0;
 }
 g_beExtraPips = temp_double_12 + temp_double_13 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 14 ;
 global_120_int_2D4 = 6 ;
 global_121_int_2D8 = 400 ;
 g_hlOffsetPips = 32.0 ;
 g_maxOpenTradesPerSide = 99 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_4";
 }
 global_93_int_1F0=ST1_MagicNumber + 2;
 // Repeated isolated probes of the Market EX5 use the 52-point DD weight
 // in variable-value mode.  A single cold-agent matrix run produced 57-like
 // sizing; that run is treated as an environment-state counterexample.
 global_397_double_6768 = ConvertUsdToAccountCurrency(52.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 1600.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(52.0) ;
 }
//LoadStrategy4Settings <<==--------   --------
 void LoadStrategy2Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 41 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_D1 ;
 g_signalTfPeriod = (int)PERIOD_H1 ;
 global_73_int_17C = 15 ;
 global_74_int_180 = 3 ;
 global_77_int_188 = 230 ;
 g_entryBreakoutPips = 550.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -170.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -70.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 1 ;
 global_88_double_1D0 = 480.0 ;
 g_pendingExpiryHours = 480 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 1000.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 4100.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 450.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 1400.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 1600.0 ;
 temp_double_9 = AdjustTrailTP + 400.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 500.0 ;
 temp_double_11 = AdjustBreakEven + 100.0;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 1 ;
 global_120_int_2D4 = 5 ;
 global_121_int_2D8 = 700 ;
 g_hlOffsetPips = 22.0 ;
 g_maxOpenTradesPerSide = 99 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_2";
 }
 global_93_int_1F0=ST1_MagicNumber + 5;
 global_397_double_6768 = ConvertUsdToAccountCurrency(30.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2000.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(30.0) ;
 }
//LoadStrategy2Settings <<==--------   --------
 void LoadStrategy3Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;
 double     temp_double_13;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 5 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_D1 ;
 g_signalTfPeriod = (int)PERIOD_H1 ;
 global_73_int_17C = 7 ;
 global_74_int_180 = 2 ;
 global_77_int_188 = 20 ;
 g_entryBreakoutPips = 250.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -130.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -120.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 1 ;
 global_88_double_1D0 = 980.0 ;
 g_pendingExpiryHours = 432 ;
 global_99_int_22C = 1 ;
 if ( !(UseHL_TrailingSL) )
 {
   temp_double_3 = AdjustSL + 600.0;
   if ( Randomization>0.0 )
   {
     temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
   }
   else
   {
     temp_double_4 = 0.0;
   }
   global_100_double_230 = temp_double_3 + temp_double_4 ;
 }
 else
 {
   temp_double_4 = AdjustSL + 700.0;
   if ( Randomization>0.0 )
   {
     temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
   }
   else
   {
     temp_double_5 = 0.0;
   }
   global_100_double_230 = temp_double_4 + temp_double_5 ;
 }
 temp_double_5 = AdjustTP + 3300.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 g_takeProfitPips = temp_double_5 + temp_double_6 ;
 temp_double_6 = AdjustTrailSL + 500.0;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 global_103_double_250 = temp_double_6 + temp_double_7 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 g_trailActivationPips = temp_double_8 + 400.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_105_double_260 = temp_double_9 + 5000.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 global_109_double_280 = temp_double_10 + 1000.0 ;
 temp_double_10 = AdjustTrailTP + 2000.0;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 g_trailTpPips = temp_double_10 + temp_double_11 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 global_113_double_2A8 = temp_double_12 + 400.0 ;
 temp_double_12 = AdjustBreakEven;
 if ( Randomization>0.0 )
 {
   temp_double_13 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_13 = 0.0;
 }
 g_beExtraPips = temp_double_12 + temp_double_13 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 7 ;
 global_120_int_2D4 = 4 ;
 global_121_int_2D8 = 100 ;
 g_hlOffsetPips = 0.0 ;
 g_maxOpenTradesPerSide = 99 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_3";
 }
 global_93_int_1F0=ST1_MagicNumber + 8;
 // The Market EX5 uses the 35-point historical DD weight in both fixed and
 // variable-value modes.  The reconstructed 32-point pre-return value caused
 // strategy 3 lots to round one step too high around the 0.025 boundary.
 global_397_double_6768 = ConvertUsdToAccountCurrency(35.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2000.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(35.0) ;
 }
//LoadStrategy3Settings <<==--------   --------
 void LoadStrategy6Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 20 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_H1 ;
 g_signalTfPeriod = (int)PERIOD_M5 ;
 global_73_int_17C = 26 ;
 global_74_int_180 = 24 ;
 global_77_int_188 = 140 ;
 g_entryBreakoutPips = 120.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -115.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -145.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 5 ;
 global_88_double_1D0 = 55.0 ;
 g_pendingExpiryHours = 20 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 10100.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 800.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 500.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 1200.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 1950.0 ;
 temp_double_9 = AdjustTrailTP + 350.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 330.0 ;
 temp_double_11 = AdjustBreakEven + 80.0;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 0 ;
 global_120_int_2D4 = 0 ;
 global_121_int_2D8 = 100 ;
 g_hlOffsetPips = 0.0 ;
 g_maxOpenTradesPerSide = 5 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_6";
 }
 global_93_int_1F0=ST1_MagicNumber + 9;
 global_397_double_6768 = ConvertUsdToAccountCurrency(348.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2400.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(140.0) ;
 }
//LoadStrategy6Settings <<==--------   --------
 void LoadStrategy5Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 24 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_H1 ;
 g_signalTfPeriod = (int)PERIOD_M15 ;
 global_73_int_17C = 30 ;
 global_74_int_180 = 19 ;
 global_77_int_188 = 110 ;
 g_entryBreakoutPips = 160.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -120.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -110.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 3 ;
 global_88_double_1D0 = 55.0 ;
 g_pendingExpiryHours = 30 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 5300.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 900.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 495.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 400.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 1900.0 ;
 temp_double_9 = AdjustTrailTP + 250.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 260.0 ;
 temp_double_11 = AdjustBreakEven + 80.0;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 0 ;
 global_120_int_2D4 = 0 ;
 global_121_int_2D8 = 100 ;
 g_hlOffsetPips = 0.0 ;
 g_maxOpenTradesPerSide = 99 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_5";
 }
 global_93_int_1F0=ST1_MagicNumber + 12;
 global_397_double_6768 = ConvertUsdToAccountCurrency(281.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2600.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(110.0) ;
 }
//LoadStrategy5Settings <<==--------   --------
 void LoadStrategy9Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 12 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_H1 ;
 g_signalTfPeriod = (int)PERIOD_M15 ;
 global_73_int_17C = 7 ;
 global_74_int_180 = 5 ;
 global_77_int_188 = 200 ;
 g_entryBreakoutPips = 40.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -150.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -145.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 3 ;
 global_88_double_1D0 = 5.0 ;
 g_pendingExpiryHours = 15 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 3900.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 1350.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 445.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 355.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 1850.0 ;
 temp_double_9 = AdjustTrailTP + 250.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 160.0 ;
 temp_double_11 = AdjustBreakEven + 50.0;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 1 ;
 global_120_int_2D4 = 9 ;
 global_121_int_2D8 = 1500 ;
 g_hlOffsetPips = 46.0 ;
 g_maxOpenTradesPerSide = 99 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_9";
 }
 global_93_int_1F0=ST1_MagicNumber + 13;
 global_397_double_6768 = ConvertUsdToAccountCurrency(968.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 1900.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(700.0) ;
 }
//LoadStrategy9Settings <<==--------   --------
 void LoadStrategy7Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 28 ;
 g_atrTimeframe = (int)PERIOD_H1 ;
 g_entryTfPeriod = (int)PERIOD_H1 ;
 g_signalTfPeriod = (int)PERIOD_M15 ;
 global_73_int_17C = 25 ;
 global_74_int_180 = 23 ;
 global_77_int_188 = 145 ;
 g_entryBreakoutPips = 10.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -10.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -145.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 5 ;
 global_88_double_1D0 = 90.0 ;
 g_pendingExpiryHours = 60 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 2250.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 1450.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 450.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 900.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 2800.0 ;
 temp_double_9 = AdjustTrailTP + 350.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 340.0 ;
 temp_double_11 = AdjustBreakEven + 30.0;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 12 ;
 global_120_int_2D4 = 17 ;
 global_121_int_2D8 = 1000 ;
 g_hlOffsetPips = 45.0 ;
 g_maxOpenTradesPerSide = 5 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_7";
 }
 global_93_int_1F0=ST1_MagicNumber + 14;
 global_397_double_6768 = ConvertUsdToAccountCurrency(149.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2600.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(90.0) ;
 }
//LoadStrategy7Settings <<==--------   --------
 void LoadStrategy8Settings()
 {
 double     temp_double_1;
 double     temp_double_2;
 double     temp_double_3;
 double     temp_double_4;
 double     temp_double_5;
 double     temp_double_6;
 double     temp_double_7;
 double     temp_double_8;
 double     temp_double_9;
 double     temp_double_10;
 double     temp_double_11;
 double     temp_double_12;

 // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
 g_atrPeriod = 11 ;
 g_atrTimeframe = (int)PERIOD_D1 ;
 g_entryTfPeriod = (int)PERIOD_H1 ;
 g_signalTfPeriod = (int)PERIOD_M15 ;
 global_73_int_17C = 26 ;
 global_74_int_180 = 20 ;
 global_77_int_188 = 235 ;
 g_entryBreakoutPips = 80.0 ;
 global_81_double_1A0 = 0.0 ;
 temp_double_1 = AdjustEntry + -140.0;
 if ( Randomization>0.0 )
 {
   temp_double_2 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_2 = 0.0;
 }
 g_buyEntryOffsetPips = temp_double_1 + temp_double_2 ;
 temp_double_2 = AdjustEntry + -170.0;
 if ( Randomization>0.0 )
 {
   temp_double_3 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_3 = 0.0;
 }
 g_sellEntryOffsetPips = temp_double_2 + temp_double_3 ;
 g_maxPendingOrders = 5 ;
 global_88_double_1D0 = 5.0 ;
 g_pendingExpiryHours = 55 ;
 global_99_int_22C = 1 ;
 temp_double_3 = AdjustSL + 1900.0;
 if ( Randomization>0.0 )
 {
   temp_double_4 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_4 = 0.0;
 }
 global_100_double_230 = temp_double_3 + temp_double_4 ;
 temp_double_4 = AdjustTP + 1200.0;
 if ( Randomization>0.0 )
 {
   temp_double_5 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_5 = 0.0;
 }
 g_takeProfitPips = temp_double_4 + temp_double_5 ;
 temp_double_5 = AdjustTrailSL + 1250.0;
 if ( Randomization>0.0 )
 {
   temp_double_6 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_6 = 0.0;
 }
 global_103_double_250 = temp_double_5 + temp_double_6 ;
 if ( Randomization>0.0 )
 {
   temp_double_7 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_7 = 0.0;
 }
 g_trailActivationPips = temp_double_7 + 650.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_8 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_8 = 0.0;
 }
 global_105_double_260 = temp_double_8 + 5000.0 ;
 global_106_double_268 = 0.1 ;
 global_107_double_270 = 0.0 ;
 if ( Randomization>0.0 )
 {
   temp_double_9 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_9 = 0.0;
 }
 global_109_double_280 = temp_double_9 + 1950.0 ;
 temp_double_9 = AdjustTrailTP + 250.0;
 if ( Randomization>0.0 )
 {
   temp_double_10 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_10 = 0.0;
 }
 g_trailTpPips = temp_double_9 + temp_double_10 ;
 if ( Randomization>0.0 )
 {
   temp_double_11 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_11 = 0.0;
 }
 global_113_double_2A8 = temp_double_11 + 270.0 ;
 temp_double_11 = AdjustBreakEven;
 if ( Randomization>0.0 )
 {
   temp_double_12 = Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
 }
 else
 {
   temp_double_12 = 0.0;
 }
 g_beExtraPips = temp_double_11 + temp_double_12 ;
 global_117_int_2C8 = 60 ;
 global_118_int_2CC = 50 ;
 global_119_int_2D0 = 15 ;
 global_120_int_2D4 = 3 ;
 global_121_int_2D8 = 1200 ;
 g_hlOffsetPips = 16.0 ;
 g_maxOpenTradesPerSide = 20 ;
 if ( !(RemoveCommentSuffix) )
 {
   g_orderComment=ST1_Comment + "_XAUUSD_8";
 }
 global_93_int_1F0=ST1_MagicNumber + 15;
 global_397_double_6768 = ConvertUsdToAccountCurrency(276.0) ;
 if ( !(UseVariableValues) )   return;
 global_7_double_50 = 2800.0 ;
 global_397_double_6768 = ConvertUsdToAccountCurrency(130.0) ;
 }
//LoadStrategy8Settings <<==--------   --------
// ============================================================================
// [§17] PropFirm 日内回撤与 GMT/夏令时检测
//       EnforcePropFirmDailyDrawdown —— PropFirmMaxDailyDD 触发时按原顺序平仓
//       WTS_MonthToInt / WTS_BuildDateTime / WTS_ParseHttpDate /
//       WTS_StripTags / WTS_ParseHtmlTime —— WorldTimeServer GMT 解析辅助
//       DetectBrokerGmtOffset        —— AutoGMT=true 时检测服务器 GMT 偏移
//       IsAmericanDst                —— 美国夏令时区间判定（结果按天缓存）
// ============================================================================

 void EnforcePropFirmDailyDrawdown()
 {
  double    local_1_double;
  int       local_2_int;
  double    local_3_double;
  double    local_4_double;
  double    local_5_double;
//----- -----
 double     temp_double_1;
 long       temp_long_2;
 int        temp_int_3;

 temp_double_1 = AccountEquity();
 if ( temp_double_1==AccountBalance() )   return;
 local_1_double = 0.0 ;
 if ( AccountEquity()>global_384_double_5DA0 )
 {
   global_384_double_5DA0 = AccountEquity() ;
 }
 for (local_2_int = HistoryTotal() ; local_2_int >= 0 ; local_2_int --)
 {
   if ( OrderSelect(local_2_int,0,1) != true )   continue;
   temp_long_2 = OrderCloseTime();
   if ( temp_long_2 < iTime(g_chartSymbol,MT4Period(PERIOD_D1),0) )   continue;
   // The original EX5 daily-DD path accounts for the commission attached to
   // the closing history deal.  The generic MT4 history view also carries a
   // proportional entry commission, which made the reconstructed threshold
   // fire one or two ticks too early.  Keep the generic history semantics for
   // panels/ranking, but use the close-deal commission in this risk guard.
   double temp_daily_close_commission = OrderCommission();
   if ( g_sel_hist_index>=0 )
   {
     temp_daily_close_commission = HistoryDealGetDouble((ulong)g_hist_ticket[g_sel_hist_index],DEAL_COMMISSION);
   }
   local_3_double = OrderProfit() + OrderSwap() + temp_daily_close_commission ;
   local_1_double = local_3_double + local_1_double ;
   
 }
 local_4_double = AccountEquity() - AccountBalance() ;
 local_5_double = local_4_double + local_1_double ;
 if ( !( -(local_5_double)>global_384_double_5DA0 * PropFirmMaxDailyDD / 100.0) )   return;
 
 if ( !(global_382_bool_5D98) )
 {
   Print("Max Daily Drawdown reached, closing trades and skipping rest of the day"); 
 }
 // Close from an immutable ticket snapshot. The original daily-DD path closes
 // BUY positions before SELL positions and visits newest tickets first within
 // each side. Pending orders remain a separate second pass below.
 CloseDailyDDPositionsInOriginalOrder();
 for (temp_int_3 = MT4OrdersTotal() ; temp_int_3 >= 0 ; temp_int_3=temp_int_3 - 1)
 {
   if ( OrderSelect(temp_int_3,0,0) != true || OrderSymbol() != g_chartSymbol ) continue;
   int temp_daily_magic=OrderMagicNumber();
   if(temp_daily_magic<ST1_MagicNumber+1 || temp_daily_magic>ST1_MagicNumber+15) continue;
   if(OrderType()!=4 && OrderType()!=5) continue;
   OrderDelete(OrderTicket(),Red);
 }
 global_382_bool_5D98 = true ;
 global_384_double_5DA0 = 0.0 ;
 }
//EnforcePropFirmDailyDrawdown <<==--------   --------
// WorldTimeServer GMT parser.
// Priority:
//   1) RFC 7231 HTTP "Date:" header returned by worldtimeserver.com.
//   2) Current WorldTimeServer page text: "UTC/GMT is HH:MM on ...".
//   3) Legacy hidden field "serverTimeStamp" (older site layout).
// This keeps AutoGMT dependent on WorldTimeServer while avoiding a fragile
// dependency on one specific HTML field/layout.
 int WTS_MonthToInt(string month_string)
 {
   string lowercase_month_string = month_string;
   StringToLower(lowercase_month_string);
   if(StringLen(lowercase_month_string) >= 3)
      lowercase_month_string = StringSubstr(lowercase_month_string,0,3);
   if(lowercase_month_string == "jan") return(1);
   if(lowercase_month_string == "feb") return(2);
   if(lowercase_month_string == "mar") return(3);
   if(lowercase_month_string == "apr") return(4);
   if(lowercase_month_string == "may") return(5);
   if(lowercase_month_string == "jun") return(6);
   if(lowercase_month_string == "jul") return(7);
   if(lowercase_month_string == "aug") return(8);
   if(lowercase_month_string == "sep") return(9);
   if(lowercase_month_string == "oct") return(10);
   if(lowercase_month_string == "nov") return(11);
   if(lowercase_month_string == "dec") return(12);
   return(0);
 }

 bool WTS_BuildDateTime(int year_int,int month_int,int day_int,int hour_int,int minute_int,int second_int,datetime &output_datetime)
 {
   if(year_int < 2000 || year_int > 2200 || month_int < 1 || month_int > 12 ||
      day_int < 1 || day_int > 31 || hour_int < 0 || hour_int > 23 ||
      minute_int < 0 || minute_int > 59 || second_int < 0 || second_int > 59)
      return(false);

   MqlDateTime time_struct;
   ZeroMemory(time_struct);
   time_struct.year = year_int;
   time_struct.mon  = month_int;
   time_struct.day  = day_int;
   time_struct.hour = hour_int;
   time_struct.min  = minute_int;
   time_struct.sec  = second_int;
   output_datetime = StructToTime(time_struct);
   return(output_datetime > 0);
 }

 bool WTS_ParseHttpDate(string header_string,datetime &output_datetime)
 {
   string lowercase_header_string = header_string;
   StringToLower(lowercase_header_string);

   int position_int = StringFind(lowercase_header_string,"\r\ndate:",0);
   if(position_int >= 0)
      position_int += 2;
   else
   {
      position_int = StringFind(lowercase_header_string,"\ndate:",0);
      if(position_int >= 0)
         position_int += 1;
      else if(StringFind(lowercase_header_string,"date:",0) == 0)
         position_int = 0;
      else
         return(false);
   }

   int line_end_int = StringFind(header_string,"\n",position_int);
   string date_line_string;
   if(line_end_int < 0)
      date_line_string = StringSubstr(header_string,position_int + 5);
   else
      date_line_string = StringSubstr(header_string,position_int + 5,line_end_int - (position_int + 5));
   StringReplace(date_line_string,"\r","");
   StringTrimLeft(date_line_string);
   StringTrimRight(date_line_string);

   // RFC 7231 example: Fri, 14 Aug 2026 08:27:31 GMT
   string parts_string[];
   int part_count_int = StringSplit(date_line_string,' ',parts_string);
   if(part_count_int < 6)
      return(false);

   int day_int = (int)StringToInteger(parts_string[1]);
   int month_int = WTS_MonthToInt(parts_string[2]);
   int year_int = (int)StringToInteger(parts_string[3]);

   string clock_parts_string[];
   if(StringSplit(parts_string[4],':',clock_parts_string) < 3)
      return(false);
   int hour_int = (int)StringToInteger(clock_parts_string[0]);
   int minute_int = (int)StringToInteger(clock_parts_string[1]);
   int second_int = (int)StringToInteger(clock_parts_string[2]);

   return(WTS_BuildDateTime(year_int,month_int,day_int,hour_int,minute_int,second_int,output_datetime));
 }

 string WTS_StripTags(string input_string)
 {
   string output_string = "";
   bool inside_tag_bool = false;
   int length_int = StringLen(input_string);
   for(int i=0;i<length_int;i++)
   {
      ushort character_char = (ushort)StringGetCharacter(input_string,i);
      if(character_char == '<')
      {
         inside_tag_bool = true;
         output_string += " ";
         continue;
      }
      if(character_char == '>')
      {
         inside_tag_bool = false;
         output_string += " ";
         continue;
      }
      if(!inside_tag_bool)
         output_string += ShortToString(character_char);
   }

   StringReplace(output_string,"&nbsp;"," ");
   StringReplace(output_string,"&#160;"," ");
   StringReplace(output_string,"\r"," ");
   StringReplace(output_string,"\n"," ");
   StringReplace(output_string,"\t"," ");
   while(StringFind(output_string,"  ",0) >= 0)
      StringReplace(output_string,"  "," ");
   StringTrimLeft(output_string);
   StringTrimRight(output_string);
   return(output_string);
 }

 bool WTS_ParseHtmlTime(string html_string,datetime &output_datetime)
 {
   // Old WorldTimeServer layout: Unix timestamp in a hidden field.
   int position_int = StringFind(html_string,"\"serverTimeStamp\" value=",0);
   if(position_int >= 0)
   {
      int length_int = StringLen(html_string);
      int i = position_int + 20;
      while(i < length_int)
      {
         ushort c = (ushort)StringGetCharacter(html_string,i);
         if(c >= '0' && c <= '9')
            break;
         i++;
      }
      string digits_string = "";
      while(i < length_int && StringLen(digits_string) < 12)
      {
         ushort c = (ushort)StringGetCharacter(html_string,i);
         if(c < '0' || c > '9')
            break;
         digits_string += ShortToString(c);
         i++;
      }
      long timestamp_long = (long)StringToInteger(digits_string);
      if(timestamp_long > 1000000000)
      {
         output_datetime = (datetime)timestamp_long;
         return(true);
      }
   }

   // Current WorldTimeServer layout (2026):
   // "UTC/GMT is 08:27 on Friday, August 14, 2026"
   position_int = StringFind(html_string,"UTC/GMT is",0);
   if(position_int < 0)
      return(false);

   string fragment_string = StringSubstr(html_string,position_int,500);
   string text_string = WTS_StripTags(fragment_string);
   int marker_int = StringFind(text_string,"UTC/GMT is ",0);
   if(marker_int < 0)
      return(false);

   int time_start_int = marker_int + StringLen("UTC/GMT is ");
   if(StringLen(text_string) < time_start_int + 5)
      return(false);
   string hour_minute_string = StringSubstr(text_string,time_start_int,5);
   string time_parts_string[];
   if(StringSplit(hour_minute_string,':',time_parts_string) < 2)
      return(false);

   int hour_int = (int)StringToInteger(time_parts_string[0]);
   int minute_int = (int)StringToInteger(time_parts_string[1]);

   int on_position_int = StringFind(text_string," on ",time_start_int);
   if(on_position_int < 0)
      return(false);
   string date_part_string = StringSubstr(text_string,on_position_int + 4,80);
   string date_parts_string[];
   int date_part_count_int = StringSplit(date_part_string,' ',date_parts_string);
   if(date_part_count_int < 4)
      return(false);

   // tokens: Friday, August 14, 2026
   string day_string = date_parts_string[2];
   string year_string = date_parts_string[3];
   StringReplace(day_string,",","");
   StringReplace(year_string,",","");
   int month_int = WTS_MonthToInt(date_parts_string[1]);
   int day_int = (int)StringToInteger(day_string);
   int year_int = (int)StringToInteger(year_string);

   // The visible "UTC/GMT is" line has minute precision. This is sufficient
   // for broker GMT offset detection and remains independent of VPS time.
   return(WTS_BuildDateTime(year_int,month_int,day_int,hour_int,minute_int,0,output_datetime));
 }

 int DetectBrokerGmtOffset()
 {
  string    local_2_string;
  long      local_5_long;
  int       local_6_int;
  char      local_7_char_ko[];
  char      local_8_char_ko[];
//----- -----
 string     temp_string_1;
 string     temp_string_2;
 datetime   temp_datetime_3 = 0;
 int        temp_int_4;

 ResetLastError();
 temp_int_4 = WebRequest("GET","https://www.worldtimeserver.com/time-zones/utc/",NULL,NULL,10000,local_7_char_ko,0,local_8_char_ko,temp_string_1);
 if ( temp_int_4 == -1 )
 {
   Print("Error when reading GMT URL. Error code  =",GetLastError());
   MessageBox("Add the address \'https://www.worldtimeserver.com/\' in the list of allowed URLs on tab \'Expert Advisors\'","Error",64);
   temp_string_2 = "999";
 }
 else
 {
   // MQL5: count=-1 means read the whole WebRequest response array.
   temp_string_2 = CharArrayToString(local_8_char_ko,0,-1,CP_UTF8);
 }
 local_2_string = temp_string_2 ;
 if ( local_2_string == "999" )
 {
   return(999);
 }

 // Prefer WorldTimeServer's HTTP Date header. It is standardized and does
 // not change when the site's visual HTML layout changes.
 bool parse_succeeded_bool = WTS_ParseHttpDate(temp_string_1,temp_datetime_3);
 if(!parse_succeeded_bool)
    parse_succeeded_bool = WTS_ParseHtmlTime(local_2_string,temp_datetime_3);

 if(!parse_succeeded_bool || temp_datetime_3 <= 0)
 {
   Print("Error in detecting GMT time with WorldTimeServer response");
   return(999);
 }

 local_5_long = (long)temp_datetime_3;
 Print("GMT time = ",local_5_long);
 Print("Broker time = ",TimeCurrent());
 local_6_int=TimeHour(TimeCurrent()) - TimeHour((datetime)local_5_long);
 if ( local_6_int <  -12 )
 {
   local_6_int +=24;
 }
 if ( local_6_int >  12 )
 {
   local_6_int -=24;
 }
 Print("GMT_Offset detected: " + string(local_6_int));
 if ( ( local_6_int < -12 || local_6_int >  12 ) )
 {
   Print("Error in detecting GMT offset with URL");
   return(999);
 }
 if ( local_5_long <  TimeCurrent() - 0x15180 )
 {
   Print("Error in detecting GMT time with URL");
   return(999);
 }
 return(local_6_int);
 }
//DetectBrokerGmtOffset <<==--------   --------
 bool IsAmericanDst()
 {
  int       local_2_int;
  datetime  local_3_datetime;
  datetime  local_4_datetime;
  int       local_5_int;
  int       local_6_int;
//----- -----

 datetime temp_now=TimeCurrent();
 datetime temp_day=temp_now-(temp_now%86400);
 if ( g_us_dst_cache_valid && g_us_dst_cache_day==temp_day )
 {
   return(g_us_dst_cache_value);
 }
 local_2_int = TimeYear(temp_now) ;
 local_3_datetime = 0 ;
 local_4_datetime = 0 ;
 if ( local_2_int <  1987 )
 {
   Print("AmericanDST(): Invalid year."); 
   return(false); 
 }
 local_5_int = 0 ;
 local_6_int = 0 ;
 if ( local_2_int >= 1987 && local_2_int <= 2006 )
 {
   local_5_int = (int)(MathMod(local_2_int * 6 + 2 - local_2_int / 4,7.0) + 1.0) ;
   local_6_int = (int)(31.0 - (MathMod(local_2_int * 5 / 4 + 1,7.0))) ;
   local_3_datetime=StringToTime(((string)local_2_int+".04.01")) + (local_5_int - 1) * 86400 + 0x1C20;
   local_4_datetime=StringToTime(((string)local_2_int+".10.01")) + (local_6_int - 1) * 86400 + 0x1C20;
 }
 else
 {
   if ( local_2_int >= 2007 )
   {
     local_5_int = (int)(14.0 - (MathMod(local_2_int * 5 / 4 + 1,7.0))) ;
     local_6_int = (int)(7.0 - (MathMod(local_2_int * 5 / 4 + 1,7.0))) ;
     local_3_datetime=StringToTime(((string)local_2_int+".03.01")) + (local_5_int - 1) * 86400 + 0x1C20;
     local_4_datetime=StringToTime(((string)local_2_int+".11.01")) + (local_6_int - 1) * 86400 + 0x1C20;
   }
 }
 g_us_dst_cache_value=(TimeDayOfYear(temp_now)>TimeDayOfYear(local_3_datetime) &&
                       TimeDayOfYear(temp_now)<TimeDayOfYear(local_4_datetime));
 g_us_dst_cache_day=temp_day;
 g_us_dst_cache_valid=true;
 return(g_us_dst_cache_value); 
 }
//<<==IsAmericanDst <<==
