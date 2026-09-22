//+------------------------------------------------------------------+
//| MQL4Compat.mqh                                                    |
//| MQL4 -> MQL5 compatibility layer (standalone include version)     |
//|                                                                  |
//| Source: extracted from The Gold Reaper English MT5.mq5 [S2].      |
//| Purpose: run MQL4-style code (OrderSend/OrderSelect/OrderModify/  |
//|          MarketInfo/iMA/Time* ...) under MQL5.                    |
//|                                                                  |
//| Only one change during extraction: g_chartSymbol -> Symbol(),     |
//| so this include has no dependency on host EA globals.             |
//|                                                                  |
//| NOTE: hedging account is REQUIRED for multi-position EAs.         |
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

int  g_mt4_lastError = 0;

//====================================================================
// Quy doi timeframe kieu "so phut" (MQL4 cu) -> ENUM_TIMEFRAMES MQL5.
// Neu tham so da la hang PERIOD_xxx cua MQL5 (gia tri >= 16385) thi
// tra ve nguyen (pass-through) vi da dung.
//====================================================================
ENUM_TIMEFRAMES MT4Period(int minutes)
{
    switch (minutes)
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
double MarketInfo(string symbol, int mode)
{
    switch (mode)
    {
    case MODE_BID:
        return SymbolInfoDouble(symbol, SYMBOL_BID);
    case MODE_ASK:
        return SymbolInfoDouble(symbol, SYMBOL_ASK);
    case MODE_POINT:         return SymbolInfoDouble(symbol, SYMBOL_POINT);
    case MODE_DIGITS:        return (double)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    case MODE_STOPLEVEL:     return (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    case MODE_TICKVALUE:     return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    case MODE_TRADEALLOWED:  return MT4SessionMarket(symbol) ? 1.0 : 0.0;
    case MODE_MINLOT:        return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    case MODE_LOTSTEP:       return SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    case MODE_MAXLOT:        return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    case MODE_FREEZELEVEL:   return (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    }
    return 0.0;
}

//====================================================================
// MQL4 风格时间序列函数的 int 周期重载
//   MQL4 源码中周期多以“分钟数字”传递（60 / 240 / 1440 ...），而 MQL5 原生
//   iTime / iClose / ... 要求 ENUM_TIMEFRAMES。此处的 int 重载统一经
//   MT4Period() 转换（0 = 当前图表周期），从而无需改动 EA 主体代码。
//====================================================================
datetime iTime(string symbol, int timeframe, int shift) { return iTime(symbol, MT4Period(timeframe), shift); }
double   iOpen(string symbol, int timeframe, int shift) { return iOpen(symbol, MT4Period(timeframe), shift); }
double   iHigh(string symbol, int timeframe, int shift) { return iHigh(symbol, MT4Period(timeframe), shift); }
double   iLow(string symbol, int timeframe, int shift) { return iLow(symbol, MT4Period(timeframe), shift); }
double   iClose(string symbol, int timeframe, int shift) { return iClose(symbol, MT4Period(timeframe), shift); }
long     iVolume(string symbol, int timeframe, int shift) { return iVolume(symbol, MT4Period(timeframe), shift); }
int      iBars(string symbol, int timeframe) { return iBars(symbol, MT4Period(timeframe)); }
int      iBarShift(string symbol, int timeframe, datetime time, bool exact = false) { return iBarShift(symbol, MT4Period(timeframe), time, exact); }

//====================================================================
// 独立 include 版补充：宿主文件 [§1] 中被兼容层依赖的全局对象/变量
//   · CTrade trade        —— MT4ConfigureMarketFilling 等使用
//   · g_eu_dst_cache_*    —— MT4EuropeanDST 的按天缓存
//====================================================================
#include <Trade\Trade.mqh>
CTrade trade;
datetime g_eu_dst_cache_day = 0;
bool     g_eu_dst_cache_valid = false;
bool     g_eu_dst_cache_value = false;

//====================================================================
// Account*() kieu MQL4
//====================================================================
double AccountBalance() { return AccountInfoDouble(ACCOUNT_BALANCE); }
double AccountEquity() { return AccountInfoDouble(ACCOUNT_EQUITY); }
string AccountCurrency() { return AccountInfoString(ACCOUNT_CURRENCY); }

bool MT4EuropeanDST()
{
    datetime now = TimeCurrent();
    datetime day = now - (now % 86400);
    if (g_eu_dst_cache_valid && g_eu_dst_cache_day == day)
        return g_eu_dst_cache_value;

    MqlDateTime marchEnd;
    MqlDateTime octoberEnd;
    int year = TimeYear(now);
    datetime march = StringToTime(string(year) + ".03.31 01:00");
    datetime october = StringToTime(string(year) + ".10.31 02:00");
    TimeToStruct(march, marchEnd);
    TimeToStruct(october, octoberEnd);
    g_eu_dst_cache_value = (TimeDayOfYear(now) > TimeDayOfYear(march - marchEnd.day_of_week * 86400) &&
        TimeDayOfYear(now) < TimeDayOfYear(october - octoberEnd.day_of_week * 86400));
    g_eu_dst_cache_day = day;
    g_eu_dst_cache_valid = true;
    return g_eu_dst_cache_value;
}

double AccountFreeMarginCheck(string symbol, int cmd, double volume)
{
    if (volume <= 0.0)
        return 0.0;

    // Recovered from the original V4.6 JIT: for ordinary symbols the check
    // requires at least 70 account-currency units of both equity and free
    // margin per 0.01 lot.  The original helper returns a boolean result even
    // though its legacy call site compares the value with zero.
    double lot_units = volume / 0.01;
    if (lot_units <= 0.0)
        return 0.0;
    if (AccountInfoDouble(ACCOUNT_EQUITY) / lot_units < 70.0)
    {
        Print("equity too low");
        return 0.0;
    }
    if (AccountInfoDouble(ACCOUNT_MARGIN_FREE) / lot_units < 70.0)
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
bool IsDemo() { return AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO; }
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
bool MT4SessionMarketCore(string symbol, datetime when)
{
    long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    // Preserve the original EA rule: MODE_TRADEALLOWED was true only in FULL mode.
    if (trade_mode != SYMBOL_TRADE_MODE_FULL)
        return false;

    if (when <= 0)
    {
        if (IsTesting())
            when = TimeCurrent();
        else
            when = TimeTradeServer();

        if (when <= 0)
            when = TimeCurrent();
    }

    if (when <= 0)
        return false;

    MqlDateTime now_struct;
    TimeToStruct(when, now_struct);
    ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)now_struct.day_of_week;
    int now_seconds = now_struct.hour * 3600 + now_struct.min * 60 + now_struct.sec;

    datetime session_from = 0;
    datetime session_to = 0;
    for (uint session_index = 0; session_index < 64; session_index++)
    {
        if (!SymbolInfoSessionTrade(symbol, dow, session_index, session_from, session_to))
            break;

        MqlDateTime from_struct;
        MqlDateTime to_struct;
        TimeToStruct(session_from, from_struct);
        TimeToStruct(session_to, to_struct);
        int from_seconds = from_struct.hour * 3600 + from_struct.min * 60 + from_struct.sec;
        int to_seconds = to_struct.hour * 3600 + to_struct.min * 60 + to_struct.sec;

        // Some brokers encode a 24-hour session as 00:00 -> 00:00.
        if (from_seconds == to_seconds)
            return true;

        if (from_seconds < to_seconds)
        {
            if (now_seconds >= from_seconds && now_seconds < to_seconds)
                return true;
        }
        else
        {
            // Session crosses midnight.
            if (now_seconds >= from_seconds || now_seconds < to_seconds)
                return true;
        }
    }

    // No matching session means market closed. If the broker/tester does not
    // expose session metadata, fail closed instead of risking an unwanted order.
    return false;
}

string g_session_market_symbol = "";
datetime g_session_market_when = 0;
bool g_session_market_valid = false;
bool g_session_market_result = false;

bool MT4SessionMarket(string symbol, datetime when = 0)
{
    if (when <= 0)
    {
        if (IsTesting()) when = TimeCurrent();
        else when = TimeTradeServer();
        if (when <= 0) when = TimeCurrent();
    }
    if (g_session_market_valid && g_session_market_symbol == symbol && g_session_market_when == when)
        return g_session_market_result;

    g_session_market_symbol = symbol;
    g_session_market_when = when;
    g_session_market_result = MT4SessionMarketCore(symbol, when);
    g_session_market_valid = true;
    return g_session_market_result;
}

//====================================================================
// Cac ham thoi gian kieu MQL4 (khong con trong MQL5)
//====================================================================
datetime g_mt4_time_parts_at = 0;
MqlDateTime g_mt4_time_parts;
void MT4GetTimeParts(datetime t, MqlDateTime& s)
{
    if (t != g_mt4_time_parts_at)
    {
        TimeToStruct(t, g_mt4_time_parts);
        g_mt4_time_parts_at = t;
    }
    s = g_mt4_time_parts;
}
int TimeYear(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.year; }
int TimeMonth(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.mon; }
int TimeDay(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.day; }
int TimeHour(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.hour; }
int TimeMinute(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.min; }
int TimeSeconds(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.sec; }
int TimeDayOfWeek(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.day_of_week; }
int TimeDayOfYear(datetime t) { MqlDateTime s; MT4GetTimeParts(t, s); return s.day_of_year; }

// Ban khong doi so (ngam dinh TimeCurrent()) - kieu MQL4 rat cu
int Year() { return TimeYear(TimeCurrent()); }
int Month() { return TimeMonth(TimeCurrent()); }
int Day() { return TimeDay(TimeCurrent()); }
int Hour() { return TimeHour(TimeCurrent()); }
int Minute() { return TimeMinute(TimeCurrent()); }
int Seconds() { return TimeSeconds(TimeCurrent()); }
int DayOfWeek() { return TimeDayOfWeek(TimeCurrent()); }

//====================================================================
// iMA()/iFractals() ban tra ve gia tri truc tiep (kieu MQL4), du lieu
// lay qua CopyBuffer tu handle indicator (MQL5 tu dong cache handle
// theo bo tham so nen goi lai moi tick khong gay ro ri tai nguyen).
//====================================================================
ENUM_APPLIED_PRICE MT4AppliedPrice(int p) { return (ENUM_APPLIED_PRICE)(p + 1); }

double iMA(string symbol, int timeframe, int period, int ma_shift, int ma_method, int applied_price, int shift)
{
    int handle = iMA(symbol, MT4Period(timeframe), period, ma_shift, (ENUM_MA_METHOD)ma_method, MT4AppliedPrice(applied_price));
    if (handle == INVALID_HANDLE) return 0.0;
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(handle, 0, shift, 1, buf) <= 0) return 0.0;
    return buf[0];
}

double iFractals(string symbol, int timeframe, int mode, int shift)
{
    // The EA calls this compatibility wrapper only with shift=1 during OnInit.
    // A standard Bill Williams fractal needs two newer bars for confirmation,
    // therefore shift 0/1 cannot contain a confirmed fractal and is exactly 0.0.
    // Returning here avoids creating visual iFractals handles in MT5 Visual Tester.
    if (shift < 2) return 0.0;

    // Preserve the original compatibility path for any unexpected call at shift>=2.
    int handle = iFractals(symbol, MT4Period(timeframe));
    if (handle == INVALID_HANDLE) return 0.0;
    int bufIndex = (mode == 1) ? 0 : 1; // 1=MODE_UPPER->buffer0, 2=MODE_LOWER->buffer1
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(handle, bufIndex, shift, 1, buf) <= 0) return 0.0;
    return buf[0];
}

bool MT4BearishFakeout(int timeframe, int anchorShift, datetime anchor, double level)
{
    int need = (anchorShift + 1 > 2) ? anchorShift + 1 : 2;
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(Symbol(), MT4Period(timeframe), 0, need, rates) < need) return false;
    return rates[anchorShift].time <= anchor && rates[0].time > anchor &&
        rates[1].close < rates[1].open && rates[1].close < level;
}

bool MT4BullishFakeout(int timeframe, int anchorShift, datetime anchor, double level)
{
    int need = (anchorShift + 1 > 2) ? anchorShift + 1 : 2;
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(Symbol(), MT4Period(timeframe), 0, need, rates) < need) return false;
    return rates[anchorShift].time <= anchor && rates[0].time > anchor &&
        rates[1].close > rates[1].open && rates[1].close > level;
}


//====================================================================
// Chuyen doi retcode cua MQL5 -> ma loi kieu MQL4 (de cac doan retry
// "if(MT4_LastError()==132) ..." trong code goc hoat dong dung y nghia)
//====================================================================
int MT4_LastError() { return g_mt4_lastError; }

int TradeRetcodeToMT4Error(uint retcode)
{
    switch (retcode)
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
    long mask = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    if ((mask & SYMBOL_FILLING_FOK) != 0)  return ORDER_FILLING_FOK;
    if ((mask & SYMBOL_FILLING_IOC) != 0)  return ORDER_FILLING_IOC;
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
    switch (t)
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
    if (!trade.SetTypeFillingBySymbol(symbol))
        trade.SetTypeFilling(MT4SelectFilling(symbol));
}

//====================================================================
// MQL4-style OrderSend interface backed by the same CTrade execution
// family recovered in the original binary (CTrade::OrderOpen /
// PositionOpen).  The strategy body remains byte-for-byte unchanged.
//====================================================================
long OrderSend(string symbol, int cmd, double volume, double price, int slippage,
    double stoploss, double takeprofit, string comment = "", int magic = 0,
    datetime expiration = 0, color arrow_color = clrNONE)
{
    ENUM_ORDER_TYPE type;
    switch (cmd)
    {
    case OP_BUY:       type = ORDER_TYPE_BUY;        break;
    case OP_SELL:      type = ORDER_TYPE_SELL;       break;
    case OP_BUYLIMIT:  type = ORDER_TYPE_BUY_LIMIT;  break;
    case OP_SELLLIMIT: type = ORDER_TYPE_SELL_LIMIT; break;
    case OP_BUYSTOP:   type = ORDER_TYPE_BUY_STOP;   break;
    case OP_SELLSTOP:  type = ORDER_TYPE_SELL_STOP;  break;
    default:
        g_mt4_lastError = 3; // ERR_INVALID_TRADE_PARAMETERS
        g_mt4_lastTicket = -1;
        return -1;
    }

    trade.SetExpertMagicNumber((ulong)magic);
    trade.SetDeviationInPoints((ulong)MathMax(slippage, 0));

    bool accepted = false;
    double executionPrice = price;
    if (type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
    {
        MT4ConfigureMarketFilling(symbol);
        executionPrice = (type == ORDER_TYPE_BUY)
            ? SymbolInfoDouble(symbol, SYMBOL_ASK)
            : SymbolInfoDouble(symbol, SYMBOL_BID);
        accepted = trade.PositionOpen(symbol, type, volume, executionPrice,
            stoploss, takeprofit, comment);
    }
    else
    {
        trade.SetTypeFilling(ORDER_FILLING_RETURN);
        ENUM_ORDER_TYPE_TIME timeType = (expiration > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
        accepted = trade.OrderOpen(symbol, type, volume, 0.0, price,
            stoploss, takeprofit, timeType, expiration, comment);
    }

    uint retcode = trade.ResultRetcode();
    if (!accepted && retcode == 0) retcode = TRADE_RETCODE_ERROR;
    g_mt4_lastError = TradeRetcodeToMT4Error(retcode);
    if (accepted && (retcode == TRADE_RETCODE_DONE ||
        retcode == TRADE_RETCODE_DONE_PARTIAL ||
        retcode == TRADE_RETCODE_PLACED))
    {
        g_mt4_lastError = 0;
        ulong ticket = trade.ResultOrder();
        if (ticket == 0) ticket = trade.ResultDeal();
        g_mt4_lastTicket = (long)ticket;
        PrintFormat("open #%I64d %s %.2f %s at %.5f sl: %.5f tp: %.5f ok",
            g_mt4_lastTicket, MT4OrderTypeName((int)type), volume,
            symbol, executionPrice, stoploss, takeprofit);
        MT4InvalidateHistoryCache();
        return g_mt4_lastTicket;
    }

    PrintFormat("failed open %s %.2f %s at %.5f sl: %.5f tp: %.5f [%s] (retcode=%u)",
        MT4OrderTypeName((int)type), volume, symbol, executionPrice,
        stoploss, takeprofit, trade.ResultRetcodeDescription(), retcode);
    g_mt4_lastTicket = -1;
    return -1;
}

bool OrderModify(long ticket, double price, double stoploss, double takeprofit, datetime expiration, color arrow_color = clrNONE)
{
    bool accepted = false;
    string symbol = "";
    double logPrice = price;

    if (PositionSelectByTicket((ulong)ticket))
    {
        symbol = PositionGetString(POSITION_SYMBOL);
        logPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
        accepted = trade.PositionModify((ulong)ticket, stoploss, takeprofit);
    }
    else if (::OrderSelect((ulong)ticket))
    {
        symbol = ::OrderGetString(ORDER_SYMBOL);
        trade.SetExpertMagicNumber((ulong)::OrderGetInteger(ORDER_MAGIC));
        ENUM_ORDER_TYPE_TIME timeType = (expiration > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
        accepted = trade.OrderModify((ulong)ticket, price, stoploss, takeprofit,
            timeType, expiration, 0.0);
        logPrice = price;
    }
    else
    {
        g_mt4_lastError = 4108;
        return false;
    }

    uint retcode = trade.ResultRetcode();
    if (!accepted && retcode == 0) retcode = TRADE_RETCODE_ERROR;
    g_mt4_lastError = TradeRetcodeToMT4Error(retcode);
    if (accepted && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
    {
        g_mt4_lastError = 0;
        PrintFormat("modify #%I64d %s price: %.5f sl: %.5f tp: %.5f ok",
            ticket, symbol, logPrice, stoploss, takeprofit);
        MT4InvalidateHistoryCache();
        return true;
    }

    PrintFormat("failed modify %s at %.5f sl: %.5f tp: %.5f [%s] (retcode=%u, ticket=%I64d)",
        symbol, logPrice, stoploss, takeprofit,
        trade.ResultRetcodeDescription(), retcode, ticket);
    return false;
}

bool OrderClose(long ticket, double lots, double price, int slippage, color arrow_color = clrNONE)
{
    if (!PositionSelectByTicket((ulong)ticket))
    {
        g_mt4_lastError = 4108;
        return false;
    }

    string symbol = PositionGetString(POSITION_SYMBOL);
    double positionVolume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
    double closeVolume = (lots > 0.0 && lots < positionVolume) ? lots : positionVolume;
    ulong deviation = (ulong)MathMax(slippage, 0);
    trade.SetDeviationInPoints(deviation);
    MT4ConfigureMarketFilling(symbol);

    bool accepted = (closeVolume >= positionVolume)
        ? trade.PositionClose((ulong)ticket, deviation)
        : trade.PositionClosePartial((ulong)ticket, closeVolume, deviation);

    uint retcode = trade.ResultRetcode();
    if (!accepted && retcode == 0) retcode = TRADE_RETCODE_ERROR;
    g_mt4_lastError = TradeRetcodeToMT4Error(retcode);
    if (accepted && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
    {
        g_mt4_lastError = 0;
        PrintFormat("close #%I64d %s %.2f %s at %.5f ok", ticket,
            (positionType == POSITION_TYPE_BUY) ? "buy" : "sell",
            closeVolume, symbol, trade.ResultPrice());
        MT4InvalidateHistoryCache();
        return true;
    }

    PrintFormat("failed close %s %.2f %s [%s] (retcode=%u, ticket=%I64d)",
        (positionType == POSITION_TYPE_BUY) ? "buy" : "sell", closeVolume, symbol,
        trade.ResultRetcodeDescription(), retcode, ticket);
    return false;
}

bool OrderDelete(long ticket, color arrow_color = clrNONE)
{
    string orderName = "order";
    double orderVolume = 0.0;
    double orderPrice = 0.0;
    string symbol = "";

    if (::OrderSelect((ulong)ticket))
    {
        orderName = MT4OrderTypeName((int)::OrderGetInteger(ORDER_TYPE));
        orderVolume = ::OrderGetDouble(ORDER_VOLUME_CURRENT);
        orderPrice = ::OrderGetDouble(ORDER_PRICE_OPEN);
        symbol = ::OrderGetString(ORDER_SYMBOL);
        trade.SetExpertMagicNumber((ulong)::OrderGetInteger(ORDER_MAGIC));
    }

    bool accepted = trade.OrderDelete((ulong)ticket);
    uint retcode = trade.ResultRetcode();
    if (!accepted && retcode == 0) retcode = TRADE_RETCODE_ERROR;
    g_mt4_lastError = TradeRetcodeToMT4Error(retcode);
    if (accepted && retcode == TRADE_RETCODE_DONE)
    {
        g_mt4_lastError = 0;
        PrintFormat("delete #%I64d %s %.2f %s at %.5f ok",
            ticket, orderName, orderVolume, symbol, orderPrice);
        MT4InvalidateHistoryCache();
        return true;
    }

    PrintFormat("failed delete %s %.2f %s at %.5f [%s] (retcode=%u, ticket=%I64d)",
        orderName, orderVolume, symbol, orderPrice,
        trade.ResultRetcodeDescription(), retcode, ticket);
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
int g_sel_hist_index = -1;
int g_sel_live_index = -1;
MT4SelectedOrder g_live_orders[];
int  g_live_count = 0;
bool g_live_valid = false;

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
int      g_hist_stat_size = 0;
int      g_hist_count = 0;
datetime g_hist_builtAt = 0;
int      g_hist_source_deals = -1;

void MT4InvalidateHistoryCache()
{
    g_hist_builtAt = 0;
    g_live_valid = false;
}

void MT4BuildLiveCache()
{
    if (g_live_valid) return;
    g_live_count = 0;
    ArrayResize(g_live_orders, PositionsTotal() + ::OrdersTotal());

    int positions = PositionsTotal();
    for (int i = 0; i < positions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        int n = g_live_count++;
        g_live_orders[n].ticket = (long)ticket;
        g_live_orders[n].symbol = PositionGetString(POSITION_SYMBOL);
        g_live_orders[n].type = (int)PositionGetInteger(POSITION_TYPE);
        g_live_orders[n].lots = PositionGetDouble(POSITION_VOLUME);
        g_live_orders[n].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        g_live_orders[n].closePrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        g_live_orders[n].sl = PositionGetDouble(POSITION_SL);
        g_live_orders[n].tp = PositionGetDouble(POSITION_TP);
        g_live_orders[n].openTime = (datetime)PositionGetInteger(POSITION_TIME);
        g_live_orders[n].closeTime = 0;
        g_live_orders[n].expiration = 0;
        g_live_orders[n].profit = PositionGetDouble(POSITION_PROFIT);
        g_live_orders[n].swap = PositionGetDouble(POSITION_SWAP);
        g_live_orders[n].commission = 0.0;
        g_live_orders[n].comment = PositionGetString(POSITION_COMMENT);
        g_live_orders[n].magic = (int)PositionGetInteger(POSITION_MAGIC);
    }

    int orders = ::OrdersTotal();
    for (int i = 0; i < orders; i++)
    {
        ulong ticket = ::OrderGetTicket(i);
        if (ticket == 0) continue;
        datetime expiration = (datetime)::OrderGetInteger(ORDER_TIME_EXPIRATION);
        int n = g_live_count++;
        g_live_orders[n].ticket = (long)ticket;
        g_live_orders[n].symbol = ::OrderGetString(ORDER_SYMBOL);
        g_live_orders[n].type = (int)::OrderGetInteger(ORDER_TYPE);
        g_live_orders[n].lots = ::OrderGetDouble(ORDER_VOLUME_CURRENT);
        g_live_orders[n].openPrice = ::OrderGetDouble(ORDER_PRICE_OPEN);
        g_live_orders[n].closePrice = 0.0;
        g_live_orders[n].sl = ::OrderGetDouble(ORDER_SL);
        g_live_orders[n].tp = ::OrderGetDouble(ORDER_TP);
        g_live_orders[n].openTime = (datetime)::OrderGetInteger(ORDER_TIME_SETUP);
        g_live_orders[n].closeTime = 0;
        g_live_orders[n].expiration = expiration;
        g_live_orders[n].profit = 0.0;
        g_live_orders[n].swap = 0.0;
        g_live_orders[n].commission = 0.0;
        g_live_orders[n].comment = ::OrderGetString(ORDER_COMMENT);
        g_live_orders[n].magic = (int)::OrderGetInteger(ORDER_MAGIC);
    }

    ArrayResize(g_live_orders, g_live_count);
    g_live_valid = true;
}

void MT4BuildHistoryCache()
{
    // Poll at most once per server second so server-side SL/TP deals are visible,
    // but rebuild the expensive MQL4 history view only when the deal set changes.
    if (TimeCurrent() == g_hist_builtAt) return;
    g_hist_builtAt = TimeCurrent();

    if (!HistorySelect(0, TimeCurrent())) return;
    int deals = HistoryDealsTotal();
    if (deals == g_hist_source_deals) return;
    g_hist_source_deals = deals;

    g_hist_count = 0;
    g_hist_stat_size = 0;
    ArrayResize(g_hist_stat_symbol, 0);
    ArrayResize(g_hist_stat_magic, 0);
    ArrayResize(g_hist_stat_count, 0);
    ArrayResize(g_hist_stat_pnl, 0);

    if (deals <= 0)
    {
        ArrayResize(g_hist_ticket, 0); ArrayResize(g_hist_symbol, 0);
        ArrayResize(g_hist_type, 0); ArrayResize(g_hist_lots, 0);
        ArrayResize(g_hist_openPrice, 0); ArrayResize(g_hist_closePrice, 0);
        ArrayResize(g_hist_openTime, 0); ArrayResize(g_hist_closeTime, 0);
        ArrayResize(g_hist_profit, 0); ArrayResize(g_hist_swap, 0);
        ArrayResize(g_hist_commission, 0); ArrayResize(g_hist_comment, 0);
        ArrayResize(g_hist_magic, 0); ArrayResize(g_hist_expiration, 0);
        return;
    }

    // One allocation per array and rebuild. The previous incremental resize
    // copied all accumulated strings/numbers again for every OUT deal.
    ArrayResize(g_hist_ticket, deals); ArrayResize(g_hist_symbol, deals);
    ArrayResize(g_hist_type, deals); ArrayResize(g_hist_lots, deals);
    ArrayResize(g_hist_openPrice, deals); ArrayResize(g_hist_closePrice, deals);
    ArrayResize(g_hist_openTime, deals); ArrayResize(g_hist_closeTime, deals);
    ArrayResize(g_hist_profit, deals); ArrayResize(g_hist_swap, deals);
    ArrayResize(g_hist_commission, deals); ArrayResize(g_hist_comment, deals);
    ArrayResize(g_hist_magic, deals); ArrayResize(g_hist_expiration, deals);

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
    int posCount = 0;
    ArrayResize(posIds, deals); ArrayResize(posEntryVol, deals);
    ArrayResize(posOpenPxVol, deals); ArrayResize(posOpenTime, deals);
    ArrayResize(posType, deals); ArrayResize(posSymbol, deals);
    ArrayResize(posMagic, deals); ArrayResize(posComment, deals);
    ArrayResize(posEntryCommission, deals);

    // Pass 1: collect opening metadata for every position id.
    for (int i = 0; i < deals; i++)
    {
        ulong d = HistoryDealGetTicket(i);
        if (d == 0) continue;
        long dt = HistoryDealGetInteger(d, DEAL_TYPE);
        if (dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL) continue;
        long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
        if (entry != DEAL_ENTRY_IN) continue;
        long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
        int pos = -1;
        for (int k = 0; k < posCount; k++) if (posIds[k] == pid) { pos = k; break; }
        if (pos < 0)
        {
            pos = posCount++;
            posIds[pos] = pid;
            posEntryVol[pos] = 0.0;
            posOpenPxVol[pos] = 0.0;
            posOpenTime[pos] = 0;
            posType[pos] = (dt == DEAL_TYPE_BUY) ? OP_BUY : OP_SELL;
            posSymbol[pos] = HistoryDealGetString(d, DEAL_SYMBOL);
            posMagic[pos] = (int)HistoryDealGetInteger(d, DEAL_MAGIC);
            posComment[pos] = HistoryDealGetString(d, DEAL_COMMENT);
            posEntryCommission[pos] = 0.0;
        }
        double v = HistoryDealGetDouble(d, DEAL_VOLUME);
        double px = HistoryDealGetDouble(d, DEAL_PRICE);
        datetime ot = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
        posEntryVol[pos] += v;
        posOpenPxVol[pos] += px * v;
        if (posOpenTime[pos] == 0 || ot < posOpenTime[pos]) posOpenTime[pos] = ot;
        posEntryCommission[pos] += HistoryDealGetDouble(d, DEAL_COMMISSION);
    }

    // Pass 2: every OUT/OUT_BY deal is an independent closed-history item.
    for (int i = 0; i < deals; i++)
    {
        ulong d = HistoryDealGetTicket(i);
        if (d == 0) continue;
        long dt = HistoryDealGetInteger(d, DEAL_TYPE);
        if (dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL) continue;
        long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
        if (entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;

        long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
        int pos = -1;
        for (int k = 0; k < posCount; k++) if (posIds[k] == pid) { pos = k; break; }

        int n = g_hist_count + 1;

        double closeVol = HistoryDealGetDouble(d, DEAL_VOLUME);
        string sym = HistoryDealGetString(d, DEAL_SYMBOL);
        int magic = (int)HistoryDealGetInteger(d, DEAL_MAGIC);
        string comment = HistoryDealGetString(d, DEAL_COMMENT);
        int originalType = (dt == DEAL_TYPE_SELL) ? OP_BUY : OP_SELL; // fallback: close deal is opposite side
        double openPrice = 0.0;
        datetime openTime = 0;
        double entryCommissionShare = 0.0;
        if (pos >= 0)
        {
            if (posSymbol[pos] != "") sym = posSymbol[pos];
            if (posMagic[pos] != 0) magic = posMagic[pos];
            if (posComment[pos] != "") comment = posComment[pos];
            originalType = posType[pos];
            openTime = posOpenTime[pos];
            if (posEntryVol[pos] > 0.0)
            {
                openPrice = posOpenPxVol[pos] / posEntryVol[pos];
                entryCommissionShare = posEntryCommission[pos] * (closeVol / posEntryVol[pos]);
            }
        }

        int h = g_hist_count;
        g_hist_ticket[h] = (long)d; // unique close-deal ticket; preserves partial-close records
        g_hist_symbol[h] = sym;
        g_hist_type[h] = originalType;
        g_hist_lots[h] = closeVol;
        g_hist_openPrice[h] = openPrice;
        g_hist_closePrice[h] = HistoryDealGetDouble(d, DEAL_PRICE);
        g_hist_openTime[h] = openTime;
        g_hist_closeTime[h] = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
        g_hist_profit[h] = HistoryDealGetDouble(d, DEAL_PROFIT);
        g_hist_swap[h] = HistoryDealGetDouble(d, DEAL_SWAP);
        g_hist_commission[h] = HistoryDealGetDouble(d, DEAL_COMMISSION) + entryCommissionShare;
        g_hist_comment[h] = comment;
        g_hist_magic[h] = magic;
        g_hist_expiration[h] = 0;
        g_hist_count = n;
    }

    ArrayResize(g_hist_ticket, g_hist_count); ArrayResize(g_hist_symbol, g_hist_count);
    ArrayResize(g_hist_type, g_hist_count); ArrayResize(g_hist_lots, g_hist_count);
    ArrayResize(g_hist_openPrice, g_hist_count); ArrayResize(g_hist_closePrice, g_hist_count);
    ArrayResize(g_hist_openTime, g_hist_count); ArrayResize(g_hist_closeTime, g_hist_count);
    ArrayResize(g_hist_profit, g_hist_count); ArrayResize(g_hist_swap, g_hist_count);
    ArrayResize(g_hist_commission, g_hist_count); ArrayResize(g_hist_comment, g_hist_count);
    ArrayResize(g_hist_magic, g_hist_count); ArrayResize(g_hist_expiration, g_hist_count);

    // Panel statistics are keyed by symbol+magic and change only when history
    // changes. Build them once here instead of rescanning all closed deals for
    // every enabled strategy on every H1 update.
    for (int i = 0; i < g_hist_count; i++)
    {
        if (g_hist_type[i] != OP_BUY && g_hist_type[i] != OP_SELL) continue;
        int stat = -1;
        for (int k = 0; k < g_hist_stat_size; k++)
            if (g_hist_stat_magic[k] == g_hist_magic[i] &&
                g_hist_stat_symbol[k] == g_hist_symbol[i]) {
                stat = k; break;
            }
        if (stat < 0)
        {
            stat = g_hist_stat_size++;
            ArrayResize(g_hist_stat_symbol, g_hist_stat_size);
            ArrayResize(g_hist_stat_magic, g_hist_stat_size);
            ArrayResize(g_hist_stat_count, g_hist_stat_size);
            ArrayResize(g_hist_stat_pnl, g_hist_stat_size);
            g_hist_stat_symbol[stat] = g_hist_symbol[i];
            g_hist_stat_magic[stat] = g_hist_magic[i];
            g_hist_stat_count[stat] = 0;
            g_hist_stat_pnl[stat] = 0.0;
        }
        g_hist_stat_count[stat]++;
        g_hist_stat_pnl[stat] += g_hist_profit[i] + g_hist_swap[i] + g_hist_commission[i];
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

void MT4HistoryStats(const string symbol, const int magic, int& count, double& pnl)
{
    MT4BuildHistoryCache();
    count = 0;
    pnl = 0.0;
    for (int i = 0; i < g_hist_stat_size; i++)
    {
        if (g_hist_stat_symbol[i] != symbol || g_hist_stat_magic[i] != magic) continue;
        count = g_hist_stat_count[i];
        pnl = g_hist_stat_pnl[i];
        return;
    }
}

//====================================================================
// OrderSelect() kieu MQL4 (3 tham so, khac chu ky voi ham OrderSelect
// 1-tham-so co san cua MQL5 nen khong xung dot).
//====================================================================
bool OrderSelect(long index_or_ticket, int select, int pool = MODE_TRADES)
{
    g_sel_hist_index = -1;
    g_sel_live_index = -1;
    if (select == SELECT_BY_TICKET)
    {
        long ticket = (long)index_or_ticket;
        if (!g_live_valid) MT4BuildLiveCache();
        for (int i = 0; i < g_live_count; i++)
        {
            if (g_live_orders[i].ticket == ticket)
            {
                g_sel_live_index = i;
                return true;
            }
        }
        if (PositionSelectByTicket((ulong)ticket))
        {
            g_selOrder.ticket = ticket;
            g_selOrder.symbol = PositionGetString(POSITION_SYMBOL);
            g_selOrder.type = (int)PositionGetInteger(POSITION_TYPE);
            g_selOrder.lots = PositionGetDouble(POSITION_VOLUME);
            g_selOrder.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            g_selOrder.closePrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            g_selOrder.sl = PositionGetDouble(POSITION_SL);
            g_selOrder.tp = PositionGetDouble(POSITION_TP);
            g_selOrder.openTime = (datetime)PositionGetInteger(POSITION_TIME);
            g_selOrder.closeTime = 0;
            g_selOrder.expiration = 0;
            g_selOrder.profit = PositionGetDouble(POSITION_PROFIT);
            g_selOrder.swap = PositionGetDouble(POSITION_SWAP);
            g_selOrder.commission = 0.0;
            g_selOrder.comment = PositionGetString(POSITION_COMMENT);
            g_selOrder.magic = (int)PositionGetInteger(POSITION_MAGIC);
            return true;
        }
        if (::OrderSelect((ulong)ticket))
        {
            g_selOrder.ticket = ticket;
            g_selOrder.symbol = ::OrderGetString(ORDER_SYMBOL);
            g_selOrder.type = (int)::OrderGetInteger(ORDER_TYPE);
            g_selOrder.lots = ::OrderGetDouble(ORDER_VOLUME_CURRENT);
            g_selOrder.openPrice = ::OrderGetDouble(ORDER_PRICE_OPEN);
            g_selOrder.closePrice = 0.0;
            g_selOrder.sl = ::OrderGetDouble(ORDER_SL);
            g_selOrder.tp = ::OrderGetDouble(ORDER_TP);
            g_selOrder.openTime = (datetime)::OrderGetInteger(ORDER_TIME_SETUP);
            g_selOrder.closeTime = 0;
            g_selOrder.expiration = (datetime)::OrderGetInteger(ORDER_TIME_EXPIRATION);
            g_selOrder.profit = 0.0;
            g_selOrder.swap = 0.0;
            g_selOrder.commission = 0.0;
            g_selOrder.comment = ::OrderGetString(ORDER_COMMENT);
            g_selOrder.magic = (int)::OrderGetInteger(ORDER_MAGIC);
            return true;
        }
        MT4BuildHistoryCache();
        for (int i = 0; i < g_hist_count; i++)
        {
            if (g_hist_ticket[i] == ticket)
            {
                g_sel_hist_index = i;
                return true;
            }
        }
        return false;
    }

    // SELECT_BY_POS
    if (pool == MODE_HISTORY)
    {
        MT4BuildHistoryCache();
        if (index_or_ticket < 0 || index_or_ticket >= g_hist_count) return false;
        int i = (int)index_or_ticket; // da kiem tra nam trong [0, g_hist_count)
        g_sel_hist_index = i;
        return true;
    }

    // pool==MODE_TRADES: vi the dang mo (index 0..PositionsTotal()-1) roi
    // toi lenh cho dang mo (index PositionsTotal()..total-1)
    if (!g_live_valid) MT4BuildLiveCache();
    if (index_or_ticket >= 0 && index_or_ticket < g_live_count)
    {
        g_sel_live_index = (int)index_or_ticket;
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

//====================================================================
// Standalone-include additions: helpers used by Gold Trade Pro
//====================================================================
int AccountNumber() { return (int)AccountInfoInteger(ACCOUNT_LOGIN); }
string AccountName() { return AccountInfoString(ACCOUNT_NAME); }
double AccountFreeMargin() { return AccountInfoDouble(ACCOUNT_MARGIN_FREE); }
double AccountMargin() { return AccountInfoDouble(ACCOUNT_MARGIN); }
double AccountCredit() { return AccountInfoDouble(ACCOUNT_CREDIT); }
double AccountProfit() { return AccountInfoDouble(ACCOUNT_PROFIT); }
int AccountLeverage() { return (int)AccountInfoInteger(ACCOUNT_LEVERAGE); }
bool IsConnected() { return (bool)TerminalInfoInteger(TERMINAL_CONNECTED); }
bool IsTradeAllowed() { return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED); }

