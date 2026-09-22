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
//    §0  手工做单逻辑说明（人工可读的架构总览，纯注释）
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
//    §18 参数速查表（67 个 input 分类总表，纯注释）
// ============================================================================

// ============================================================================
// [§0] 手工做单逻辑说明 —— 把这套 EA 翻译成"人手工做单"的完整步骤
// ----------------------------------------------------------------------------
//  说明：本节为纯注释，不参与编译；目的是让不熟悉代码的人（以及后续维护者）
//        能用"手工交易员的日常操作"来理解整个架构。
//        行号会随后续编辑漂移，故本节一律用「函数名」定位，不使用行号。
// ----------------------------------------------------------------------------
//  【一句话定位】
//    只做黄金的「多策略分形预埋单」系统：9 套打法并行，各自独立 magic / 手数 /
//    止损参数，靠挂单埋伏进场、自动管仓出场。
//    账户必须是 HEDGING（对冲）模式：netting 会把同品种多空单合并成一个净持仓，
//    彻底破坏本 EA 的逐单管理逻辑。
//
//  【一、盘前准备：每个 tick 都走一遍的前置流水线（见 OnTick）】
//    1. 限速     DumpBacktestSpeedAllowTick        —— 回测加速时跳过部分 tick
//               （仅回测生效；三档结果不等价，正式验证必须用 speed_normal，
//                 详见该函数上方的专项说明）
//    2. 记账     UpdateEffectiveBalanceTracking    —— 本金 / 历史最高余额
//    3. 过滤档   ApplyFakeoutFilterMode            —— 假突破过滤强度
//    4. 对表     UpdateGmtDstDetection             —— 券商 GMT 偏移 + 夏令时
//    5. 翻日历   RefreshNfpCalendarCache           —— 查本月非农（NFP）时间
//    6. 打几套   ApplyTradeFrequencyTiers          —— 档位 0~4 逐级解锁策略 4→9
//    7. 过闸门   CheckDailyRolloverAndPropFirmGate —— 换日结算 + 日内回撤熔断
//               （命中即 return，当天不再开新仓）
//    8. 等新棒   DetectNewH1Bar                    —— H1 收出新 K 线才重评估信号
//    9. 跑策略   RunAllStrategies                  —— 按固定次序调用 9 个槽位
//
//    槽位次序是写死的：1 → 4 → 2 → 3 → 6 → 5 → 9 → 7 → 8。
//    它决定同一 tick 内谁先占用保证金、谁先撞上挂单上限，重构时必须原样保留。
//    品种不是黄金（Symbol 含 XAUUSD / GOLD / GLD）时，只跑策略 1。
//
//  【二、单套打法：看盘 → 挂单的四个动作（见 ProcessStrategy）】
//    动作 1 找位置（找"分形"）：FindBuyEntryHigh / FindSellEntryLow
//          · 左右 fractalLeftBars / fractalRightBars 根 K 线内无更高（更低）点
//          · 该极值必须高出（低于）当前价至少 entryBreakoutPips
//          · 且不低于（不高于）入场周期区间极值
//          · 且不与本策略已有挂单重复（容差 pendingDupTolerancePips）
//          注意：iATR 句柄只作为"就绪门"，不参与任何价位计算。
//    动作 2 定方向：MA 快慢线过滤 —— 多需 fast > slow，空需 fast < slow
//    动作 3 埋单（最关键、最反直觉的一步）：
//          Buy  Stop 价 = 分形高点 + buyEntryOffsetPips  （偏移为负 → 高点下方）
//          Sell Stop 价 = 分形低点 - sellEntryOffsetPips （偏移为负 → 低点上方）
//          即：多单埋在前高下方、空单埋在前低上方 —— 这是「埋在水平位内侧、
//          未破先入」的预埋单，不是追突破。最后再叠加 Randomization 随机抖动。
//    动作 4 设止损止盈与控量：
//          SL = 挂单价 - (stopLossPips + stopExtraPips)
//          TP = 挂单价 + takeProfitPips
//          校验保证金、最小/最大手数与手数步长；挂单上限 maxPendingOrders
//          点差过大 → RemovePendingOrdersDuringHighSpread 撤单暂存
//          点差恢复 → RestoreStoredPendingOrders 补回
//          Virtual_expiration = true 时不设真实到期，改为虚拟到期删单
//
//  【三、手数：按止损距离折算（见 CalculateStrategyLotSize）】
//    lots = (Risk/1000 × 有效余额) / (TickValue × 止损点数) × lotScalePercent/100
//      · Risk = 0           → 固定 StartLots
//      · OnlyUp = true      → 用历史最高余额 g_highestBalance（只增不减的复利）
//      · ManualBalance > 0  → 强制使用指定本金
//      · Risk = 9999 / 1234 → 走 g_ddTierDivisor 档位除数，回撤越大手数越小
//      · 余额变动后挂单手数会重建（RefreshPendingOrderLotSizes）
//    无马丁格尔；仅 ZR 对冲乘数。
//
//  【四、持仓管理：人盯盘做的那些事（ManageBuyPositions / ManageSellPositions）】
//    虚拟止损 → 时间追踪 → 利润追踪（> trailActivationPips 且 < profitTrailCapPips）
//    → TP 追踪 → 滑点追踪 → HL 分形追踪（UseHL_TrailingSL）
//    → 保本（盈利超过 beTriggerPips 后，SL 移到 开仓价 + beExtraPips）
//    → 分批平仓（g_partialClosePct，当前 9 套策略均为 0，等于关闭）
//    → 网格锚点推进
//
//  【五、日程纪律】
//    交易时段  IsTradingScheduleOpen（星期 + 小时）
//    周五收工  FridayStopHour 强平 + 撤挂单，周一恢复
//    点差门    MaxSpread
//    NFP 回避  前后 N 分钟撤挂单并平仓（GetNextNFPFromCalendar /
//              CloseNfpOpenTradesInOriginalOrder）
//    日内熔断  EnforcePropFirmDailyDrawdown —— 本系统唯一的强制停手：
//              日内亏损 = (equity - balance) + 当日已平盈亏，
//              超过 峰值权益 × PropFirmMaxDailyDD% → 平仓 + 撤挂单 + 当日停手
//
//    重要：MaxAllowedDD（"Max Allowed TOTAL Drawdown"）并不是强平线，
//          它只驱动手数档位除数与策略启用档位（逐级解锁策略 4→9），别被名字误导。
//
//  【六、9 套策略的差异】
//    同一套「分形埋单 + 追踪止损」骨架的参数变体：
//    入场周期 D1 / H4 / H1、信号周期 M15 / H1 / M5、分形左右棒、
//    entryBreakoutPips（10 ~ 1050）、SL / TP、挂单上限（1 ~ 5）、
//    单侧最大持仓（5 / 20 / 99）、手数权重（30 ~ 968）。
//    靠 9 个 magic 号（ST1_MagicNumber + 1/5/8/2/12/9/14/15/13）隔离管理。
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
datetime g_us_dst_cache_day = 0;
bool g_us_dst_cache_valid = false;
bool g_us_dst_cache_value = false;
datetime g_eu_dst_cache_day = 0;
bool g_eu_dst_cache_valid = false;
bool g_eu_dst_cache_value = false;

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
    if (CopyRates(g_chartSymbol, MT4Period(timeframe), 0, need, rates) < need) return false;
    return rates[anchorShift].time <= anchor && rates[0].time > anchor &&
        rates[1].close < rates[1].open && rates[1].close < level;
}

bool MT4BullishFakeout(int timeframe, int anchorShift, datetime anchor, double level)
{
    int need = (anchorShift + 1 > 2) ? anchorShift + 1 : 2;
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(g_chartSymbol, MT4Period(timeframe), 0, need, rates) < need) return false;
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


// ============================================================================
// [§3] 输入参数枚举定义（与 input 参数对应的可选项，取值与 V4.6 原版一致）
// ============================================================================

enum BacktestSpeedOptions {
    speed_normal = 1,//normal
    speed_fast = 2,//fast
    speed_super = 3//ultra fast
};
enum enum_TradeFrequency {
    Extreme_cons_Frequency = 0,//extreme conservative
    Conservative_Frequency = 1,//conservative
    Moderate_Frequency = 2,//moderate
    Intens_Frequency = 3,//Intense
    Extreme_Frequency = 4,//Extreme (high risk!)
    Auto_Frequency = 5,//Auto (based on balance and risk)
    Manual_Strategy_Selection = 6//Manual strategy selection
};
enum e_SlippageControlMode { SCT_1 = 1, SCT_2 = 2 };
enum FakeoutFilters {
    Filter_Off = 0,//OFF
    Filter_Low = 1,//Low
    Filter_Medium = 2,//Medium
    Filter_High = 3//High
};
enum e_VirtualStopMode { VSL_OFF = 1, VSL_BASIC = 2, VSL_ADV = 3 };
enum Select_Entry_Strategy { Strategy_ONE = 1, Strategy_TWO = 2 };
enum e_TimeFrame_St_ONE { ST1_M1 = 1, ST1_M5 = 5, ST1_M15 = 15, ST1_M30 = 30, ST1_H1 = 60, ST1_H4 = 240, ST1_Daily = 1440, ST1_Chart = 0 };
enum e_TimeFrame_Entry_Timing { Entry_T_Tick = 0, Entry_T_M1 = 1, Entry_T_M5 = 5, Entry_T_M15 = 15, Entry_T_M30 = 30, Entry_T_H1 = 60, Entry_T_H4 = 240 };
enum e_UseOfCompound { no_compound = 0, one_trade = 1, Multi_trades = 2 };
enum e_MonitorTradesFilter { MT_all = 0, MT_PairOfChart = 1 };
enum e_TimeFrame_Exit_Timing { ET_Tick = 0, ET_M1 = 1, ET_M5 = 5, ET_M15 = 15, ET_M30 = 30, ET_H1 = 60 };
enum e_Exit_HL_trailingSL_timeframe { HLT_Chart = 0, HLT_M1 = 1, HLT_M5 = 5, HLT_M15 = 15, HLT_M30 = 30, HLT_H1 = 60, HLT_H4 = 240, HLT_D1 = 1440 };
enum ST1_e_MagicTrail_Mode { ST1_MT_M_O = 0, ST1_MT_M_F = 1, ST1_MT_M_B = 2 };
enum e_Risk {
    Manual_Lotsize = 0,//use StartLots
    MaxHistoricalDD = 1234,//Max Allowed Total Drawdown
    MaxRiskStrat = 3//Max Risk Per Strategy
};
enum Performance_options { NormalizedProfit = 2, RealProfit = 1 };
enum RankingOptions { ranking_profit = 1, ranking_pertrade = 2 };
enum Reduction_choices { Red_10 = 10, Red_20 = 20, Red_30 = 30, Red_40 = 40, Red_50 = 50, Red_60 = 60, Red_70 = 70, Red_80 = 80, Red_90 = 90 };
enum e_factortype { factor_type_1 = 1, factor_type_2 = 2, factor_type_3 = 3 };
enum e_TimeSource { TZ_GMT = 0, TZ_PC = 1, TZ_Broker = 2 };


//------------------
// ============================================================================
// [§4] 输入参数（input）—— 分组顺序与 V4.6 原版输入面板一致
// ============================================================================
input string lijntje = "=============================================================";   //- - -
input bool UseVariableValues = true;
input bool AdjustLotsizeToVariableValues = true;
input bool ShowInfoPanel = true;
input bool UpdateInfoTesting = false;    //update infopanel during testing
input double InfoPanelSizeAdjust = 1;    //Adjustment for Infopanel size
input int   SetFontSize = 0;    //Force Font Size (0=disabled)
input string BacktestSpeed_string = "------------------------------ Backtest Speed settings ------------------------------";  //- - -
input BacktestSpeedOptions BacktestSpeed = speed_normal;
input string spreadfilter = "------------------------------ settings ------------------------------";   //- - -
input bool AllowBuyTrades = true;    //Allow Buy Trades
input bool AllowSellTrades = true;    //Allow Sell Trades
input  enum_TradeFrequency  TradeFrequency = Extreme_Frequency;
input double MaxSpread = 60;    //Maximum allowed spread
input bool UseHL_TrailingSL = true;
input int   FridayStopHour = 25;    //Friday stop hour (brokertime; close all trades)
input bool FridayClosePending = true;
input bool FridayCloseOpen = true;
input bool setSL_TP_After_Entry = true;
input bool Virtual_expiration = false;    //Use Virtual Expiration
input double Randomization = 0;    //Randomization (entries and exit) in pips
input  FakeoutFilters  FakeOutFilter = 2;    //Fake Breakout Filter
input int   ST1_MagicNumber = 8000;    //BaseMagicnumber
input string ST1_Comment = "The Gold Reaper";   //Comment for trades
input bool RemoveCommentSuffix = false;
input string NFP_FILTER = "----------------------- NFP Filter -----------------------";  //- - -
input bool EnableNFP_Filter = true;
input bool UseMQL5Calendar = true;
input bool AutoGMT = true;
input int   Broker_GMT_OFFSET_Winter = 2;    //GMT_OFFSET_Winter (AutoGMT=false or backtesting)
input int   Broker_GMT_OFFSET_Summer = 3;    //MT_OFFSET_Summer (AutoGMT=false or backtesting)
input bool NFP_CloseOpenTrades = true;
input bool NFP_ClosePendingOrders = true;
input int   NFP_MinutesBefore = 100;
input int   NFP_MinutesAfter = 60;
input string propfirmsettings = "----------------------- Propfirm unique trades settings -----------------------";   //- - -
input double AdjustEntry = 0;
input double AdjustSL = 0;
input double AdjustTP = 0;
input double AdjustTrailSL = 0;
input double AdjustTrailTP = 0;
input double AdjustBreakEven = 0;
input string LotSizeSettings = "----------------------- LotSize Settings -----------------------";   //- - -
input double ManualBalance = 0.0;    //manually set balance to use (if > 0)
input  e_Risk  Risk = 1234;    //Lotsize Calculation method
input double StartLots = 0.01;
double g_startLots_rw = 0.0;
bool g_initialLegacyRiskLotPending = true;
input double MaxAllowedDD = 30;    //Max Allowed TOTAL Drawdown
//  ★ 重要澄清（非强平、非监控）：
//    MaxAllowedDD 与实际回撤、与"从最高权益跌了多少"毫无关系，代码里从不拿它
//    与任何实际回撤比较，也不会在触线时平仓或停手。它只是一个"回撤预算"输入，
//    EA 拿它反推手数并参与档位判定（详见 ApplyTradeFrequencyTiers 上方说明）。
//    生效范围（两者都要满足才参与档位；手数部分只与 Risk 有关）：
//      · 手数：仅在 Risk = 9999 / 1234 时作为分子参与（Risk = 0 时完全无效）
//      · 档位：仅在 TradeFrequency == 5 (Auto) 且 Risk == 1234 时参与
//    → 用 Risk = 0（固定手数）或 TradeFrequency 选固定档时，本参数不参与计算。
input bool UseWeightedLots = true;    //Weighted Lotsize
input double MaxRiskPerStrategy_ = 1;    //Max Risk Per Strat
input double PropFirmMaxDailyDD = 0;    //Set Max DAILY Drawdown (Prop Firms)
input double PropFirmDailyLossUSD = 200;  //Set Max DAILY Loss in account currency (0 = use % above)
input bool   PropFirmDailyLossStatic = false;  //% mode: lock baseline to day-start equity (no trailing up)
input bool OnlyUp = true;
input bool ResetHighestBalance = false;
input bool CheckMargin = true;    //check for free margin before setting trades
input bool UseEquity = false;    //Use Equity Instead of Balance
input string ManualStratSelect = "------------------------- Manual Strategy Selection -------------------------";   //- - -
input string ManStratWarn = "!! DO NOT RUN MANUAL STRATEGIES WHILE USING \'MAX ALLOWED TOTAL DD\' OPTION !! ";   //- - -
input bool RunStrat1 = true;    //Run Strategy 1 (low risk)
input bool RunStrat2 = true;    //Run Strategy 2 (low risk)
input bool RunStrat3 = true;    //Run Strategy 3 (low risk)
input bool RunStrat4 = true;    //Run Strategy 4 (med risk)
input bool RunStrat5 = true;    //Run Strategy 5 (med risk)
input bool RunStrat6 = true;    //Run Strategy 6 (med risk)
input bool RunStrat7 = true;    //Run Strategy 7 (med risk)
input bool RunStrat8 = true;    //Run Strategy 8 (high risk)
input bool RunStrat9 = true;    //Run Strategy 9 (high risk)
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
//
// ---- 批次7 剩余 101 个变量语义命名（2026-09，纯重命名）----
//   前述批次后仅存 101 个 global_* 声明，逐个读取全部用况后按语义命名
//   （含手数/网格/追踪/保本/部分平仓参数、统计排名数组、面板几何、
//   GMT/夏令时、PropFirm 日内回撤、NFP 日期表等，完整映射见 §5 对照表）。
//   验证：token 级边界替换；新名零冲突零缺失；逆向替换逐行字节一致；
//   删后代码中 global_* 声明与 token 均为 0（仅 §5 注释表保留旧名对照）。
//   至此 214 个反编译残留 global_* 全部语义化或删除。
//
// ---- 批次8 入场集群局部变量语义命名（7 个函数 / 85 个变量，2026-09，纯重命名）----
//   RestoreStoredPendingOrders / RemovePendingOrdersDuringHighSpread /
//   FindBuyEntryHigh+FindSellEntryLow(孪生) / ProcessStrategyEntries /
//   PlaceBuyStopEntry+PlaceSellStopEntry(孪生)：local_/temp_/arg_ 全部语义化
//   （孪生函数共用一份映射）。作用域受限：每函数独立行区间，避免同名 token
//   跨函数语义冲突。验证：新名域内零冲突；逆向替换逐行字节一致；域外行零改动；
//   域内 arg_/local_/temp_ 残留=0。注意：本批改用环视断言 (?<!\w)x(?!\w) 替换，
//   修复了边界捕获组吞并相邻 token 分隔符的缺陷（如 for(i=0;;i=i+1) 第三子句）。
//
// ---- 批次9 面板/统计集群局部变量语义命名（7 个函数约 110 变量 + 8 死变量，2026-09）----
//   RefreshPendingOrderLotSizes / CreateInfoPanel / UpdateAccountPanel /
//   UpdateHistoryPanel / CountWinningTrades+CountLosingTrades(孪生) /
//   CalculatePerformanceMetrics：local_/temp_/arg_ 全部语义化。
//   反编译展开的 15 层 magic 比对阶梯统一命名为 magicVal/magicRef 对。
//   另删 8 个写而不读死局部（CreateInfoPanel 7 个 + CalculatePerformanceMetrics
//   1 个，共 13 行声明/赋值，删前逐个验证零读点）。
//   验证同批次8：域内新名零冲突、逆向逐行字节一致、域外零改动、残留=0。
// ============================================================================

double    g_curSpread = 0.0;
int       g_atrPeriod = 30;
int       g_atrTimeframe = (int)PERIOD_D1;
int       g_atrHandle = 0;
double    g_atrBuffer[];
double    g_varValueScalePrice = 0.0;
double    g_variableRatio = 0.0;
double    g_lotRatioInv = 0.0;
int       g_randomEntryOffsetPips = 0;
string    g_hdrTradingFilters = "------------------------------ trading filters ------------------------------";
bool      g_manageAllSymbols = false;
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
bool      g_managePendingsBySpread = true;
int       g_pendingMinGapPips = 2;
double    g_maxSpreadPts = 0.0;
double    g_slippagePts = 5000.0;
int       g_trailMode = 1;
double    g_trailStopBufferPips = 40.0;
double    g_trailDistancePips = 10.0;
double    g_trailCapAboveEntryPips = 30.0;
bool      g_trailUseFillPrice = false; // v106: marketplace trace uses actual fill as trailing-reference threshold
string    g_hdrTimeFilters = "------------------------------ time filters ------------------------------";
bool      g_useFridayStop = false;
bool      g_restorePendingsAfterFriday = false;
string    g_hdrOtherFilters = "------------------------------ other filters ------------------------------";
int       g_fakeoutBarsBack = 1;
int       g_fakeoutTfM1 = 1;
bool      g_fakeoutEnableM1 = false;
int       g_fakeoutTfM5 = 5;
bool      g_fakeoutEnableM5 = false;
int       g_fakeoutTfM15 = 15;
bool      g_fakeoutEnableM15 = false;
int       g_fakeoutTfM30 = 30;
bool      g_fakeoutEnableM30 = false;
int       g_fakeoutTfH1 = 60;
bool      g_fakeoutEnableH1 = false;
int       g_profitCloseMode = 1;
double    g_stopExtraPips = 0.0;
int       g_trailModifyMinSec = 99;
bool      g_limitPendingToOne = false;
int       g_orderMgmtMode = 1;
string    g_hdrTradeEntryMgmt = "------------------------------ Trade Entry management ------------------------------";
int       g_entryTfPeriod = 0;
int       g_signalTfPeriod = 60;
int       g_fractalRightBars = 10;
int       g_fractalLeftBars = 3;
bool      g_fractalRequireUnbrokenLevel = false;
int       g_fractalMinLookback = 120;
double    g_entryBreakoutPips = 30.0;
double    g_entryBreakoutPct = 0.0;
double    g_buyEntryOffsetPips = 0.5;
double    g_sellEntryOffsetPips = 0.0;
double    g_trailRefSlippagePips = 0.0;
int       g_maxPendingOrders = 1;
int       g_maxOpenTradesPerSide = 99;
double    g_pendingDupTolerancePips = 1.0;
int       g_pendingExpiryHours = 24;
int       g_lotScalePercent = 100;
int       g_curStrategyMagic = 0;
int       g_manualSymbolMode = 1;
int       g_manualMagicNumber = 1991199118;
string    g_manualCommentFilter = "";
int       g_entryTfMinutes = 0;
double    g_stopLossPips = 20.0;
double    g_takeProfitPips = 100.0;
double    g_profitTrailDistancePips = 10.0;
double    g_trailActivationPips = 10.0;
double    g_profitTrailCapPips = 100.0;
double    g_profitTrailBufferPips = 0.1;
double    g_partialClosePct = 0.0;
double    g_trailTpPips = 0.0;
double    g_profitTargetPips = 0.0;
double    g_tpTrailPips = 0.0;
double    g_tpTrailMinGapPips = 0.0;
double    g_beTriggerPips = 0.0;
double    g_beExtraPips = 0.0;
bool      g_trailOnlyTighten = false;
int       g_hlFractalTfMinutes = 0;
int       g_fractalMaxShift = 0;
int       g_hlFractalRightBars = 0;
int       g_hlFractalLeftBars = 0;
int       g_hlTrailMinGapPips = 0;
int       g_hlTrailBrokerGapPips = 0;
double    g_hlOffsetPips = 2.0;
double    g_timeTrailDelayMin = 0.0;
double    g_timeTrailDistancePips = 0.0;
int       g_partialCloseMode = 0;
double    g_gridAnchorPips = 0.1;
int       g_gridMaxOrdersPerAnchor = 1;
double    g_gridSpacingPips = 0.1;
double    g_gridMaxSpacingPips = 1.0;
int       g_orderTimeoutMin = 0;
double    g_gridTimeoutAnchorPips = 0.0;
bool      g_returnAfterOrderModify = false;
double    g_lotChangePctAlert = 5.0;
double    g_maxLotCap = 99.0;
int       g_ddTierDivisor = 600;
double    g_ddLotFactor = 1.0;
double    g_risk999BalancePct = 2.0;
string    g_perfOverviewHeader = "==== Performance numbers overview ====";
int       g_statWeightPerTrade = 1;
int       g_rankMode = 1;
int       g_statWindowDays = 90;
int       g_statRecentDays = 30;
int       g_statMinTrades = 10;
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
bool      g_closePendingsOnWeekend = false;
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
int       g_randomEntryMaxBars = 0;
double    g_buyEntryPrice = 0.0;
double    g_sellEntryPrice = 0.0;
int       g_symbolDigits = 0;
double    g_virtualSLPrice = 0.0;
int       g_buyFirstModDone = 0;
int       g_sellFirstModDone = 0;
bool      g_buyOrderSeen = false;
bool      g_sellOrderSeen = false;
double    g_virtSLCache[20][2];
double    g_virtualPendingOrders[100][3];
double    g_stopOrderTicketPrice[100][2];
int       g_virtSLCacheSize = 20;
int       g_virtualOrderSlots = 100;
bool      g_maFilterEnabled = false;
int       g_maFilterPeriod = 1;
datetime  g_lastEntryBarTime[99];
int       g_maSlowPeriod = 370;
bool      g_allowMultipleEntries = true;
double    g_minStopDistPrice = 4.0;
double    g_strategyStartLots[99];
double    g_pipSize = 0.0;
long      g_lastOrderResult = 0; // ticket OrderSend la 64-bit; bool OrderModify van gan duoc 0/1
int       g_pendingExpirySecs = 0;
double    g_sellTrailStopLevel[99];
double    g_buyTrailStopLevel[99];
double    g_nextOrderAnchorPrice = 0.0;
int       g_ordersSinceAnchor = 0;
string    g_commentBuy1;
string    g_commentBuy2;
string    g_commentSell1;
string    g_commentSell2;
double    g_entryLowPrice = 0.0;
double    g_entryHighPrice = 0.0;
int       g_lastHour = 0;
double    g_maFilterFast = 0.0;
double    g_maFilterSlow = 0.0;
int       g_tradeErrorCount = 0;
string    g_symbolSuffix;
datetime  g_pendingOrderExpiry = 0;
bool      g_marketClosedFlag = false;
int       g_timeTrailDelaySec = 0;
bool      g_fridayStopDone = false;
double    g_freezeDistPrice = 0.0;
bool      g_isDemoAccount = false;
double    g_lastLotResizeBalance = 0.0;
datetime  g_lastTrailOrderTime = 0;
bool      g_nfpWindowActive = false;
int       g_lastEntryBarsCount[99];
int       g_lastSignalBarsCount[99];
double    g_openPLbyStrategy[30];
double    g_winTradeCount[30];
double    g_lossTradeCount[30];
double    g_totalPLbyStrategy[30];
int       g_currentStrategyIndex = 0;
color     g_panelTextColor = C'244,248,252';   // 深色面板主题下的正文色（原 DarkBlue，仅适配浅色底）
color     g_panelAccentColor = C'66,153,225';
color     g_panelMutedColor = C'150,164,181';
color     g_panelOkColor = C'88,199,135';
color     g_panelWarnColor = C'255,183,77';
color     g_panelBadColor = C'239,100,97';
string    g_orderComment;
string    g_chartSymbol;
double    g_symbolPoint = 0.0;
int       g_panelStrategyRowStart = 0;
bool      g_minTradesReachedFlag[99];
int       g_closedTradeCount[99];
double    g_avgPLperTrade[99];
string    g_strategySymbols[99] = {};
double    g_statTotalPL[99];
double    g_recentPLbyStrategy[99];
int       g_statRankScore[99];
int       g_maxPanelObjects = 0;
double    g_panelCellWidth = 0.0;
double    g_panelCellHeight = 0.0;
uint      g_panelCellBgColor = LightSteelBlue;
int       g_panelFontSize = 7;
int       g_panelTableY = 0;      // 卡片渲染后策略表格的起始 Y（由 DrawTGRCards 计算）
int       g_panelX = 5;           // 面板位置/尺寸（创建时写入，供卡片渲染跨函数使用）
int       g_panelY = 20;
int       g_panelWidth = 350;
double    g_panelWidthScale = 0.45;
double    g_panelRowHeightFactor = 0.6;
int       g_strategyCount = 0;
datetime  g_lastM5BarTime = 0;
bool      g_propfirmDailyDDOn = false;
int       g_lotResizeTickCount = 0;
bool      g_propfirmDailyDDHit = false;
int       g_lastD1BarsCount = 0;
double    g_propfirmDailyPeakEquity = 0.0;
double    g_propfirmDailyStartEquity = 0.0;
int       g_ddTierThreshold1 = 200;
int       g_ddTierThreshold2Usd = 330;
int       g_ddTierThreshold3 = 560;
int       g_ddTierThreshold4Usd = 810;
int       g_ddTierThreshold5 = 1150;
datetime  g_nfpAdjustedNow = 0;
datetime  g_nfpDateTable[300];
int       g_hardcoded_nfp_year = -1;
int       g_hardcoded_nfp_month = -1;
datetime  g_hardcoded_nfp_value = 0;
bool      g_isSummerTime = false;
bool      g_euDstActive = false;
bool      g_gmtDetectDone = false;
int       g_brokerGmtOffset = 0;
int       g_detectedGmtOffset = 0;
double    g_usdToAccountRate = 0.0;
double    g_riskFactorByTier = 0.0;
datetime  g_lastH1BarTime = 0;
double    g_histClosedPLbyStrategy[99];
double    g_effectiveBalance = 0.0;
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
    datetime now = TimeTradeServer();
    MqlCalendarEvent usdEvents[];
    int usdEventCount = CalendarEventByCurrency("USD", usdEvents);
    if (usdEventCount <= 0)   return(0);

    ulong nfpEventId = 0;
    bool nfpFound = false;
    for (int evIdx = 0; evIdx < usdEventCount; evIdx++)
    {
        if (StringFind(usdEvents[evIdx].name, "Nonfarm Payrolls") >= 0)
        {
            nfpEventId = usdEvents[evIdx].id;
            nfpFound = true;
            break;
        }
    }
    if (!(nfpFound))   return(0);

    MqlCalendarValue nfpValues[];
    datetime rangeFrom = now - 86400;
    datetime rangeTo = now + 2592000;
    int valueCount = CalendarValueHistoryByEvent(nfpEventId, nfpValues, rangeFrom, rangeTo);
    if (valueCount <= 0)   return(0);

    datetime nextNfpTime = 0;
    for (int valIdx = 0; valIdx < valueCount; valIdx++)
    {
        datetime eventTime = nfpValues[valIdx].time;
        // JIT compares against the lower query bound (now-1 day), not strictly now.
        if (eventTime <= rangeFrom)   continue;
        if (nextNfpTime == 0 || eventTime < nextNfpTime)   nextNfpTime = eventTime;
    }
    return(nextNfpTime);
}
//GetNextNFPFromCalendar <<==--------   --------

datetime MT4HardcodedNFPForCurrentMonth()
{
    int year = Year();
    int month = Month();
    if (year == g_hardcoded_nfp_year && month == g_hardcoded_nfp_month)
        return(g_hardcoded_nfp_value);

    g_hardcoded_nfp_year = year;
    g_hardcoded_nfp_month = month;
    g_hardcoded_nfp_value = 0;
    for (int i = 0; i < 300; i++)
    {
        datetime event_time = g_nfpDateTable[i];
        if (TimeYear(event_time) != year || TimeMonth(event_time) != month) continue;
        g_hardcoded_nfp_value = event_time;
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

void CloseManagedPositionsByType(const int order_type, const int close_slippage)
{
    long tickets[];
    int ticket_count = 0;
    int total = MT4OrdersTotal();
    for (int index = 0; index < total; index++)
    {
        if (OrderSelect(index, SELECT_BY_POS, MODE_TRADES) != true) continue;
        if (OrderSymbol() != g_chartSymbol) continue;
        if (OrderType() != order_type) continue;
        if (!IsNfpManagedMagic(OrderMagicNumber())) continue;
        ArrayResize(tickets, ticket_count + 1);
        tickets[ticket_count++] = OrderTicket();
    }

    ArraySort(tickets);
    for (int index = ticket_count - 1; index >= 0; index--)
    {
        if (OrderSelect(tickets[index], SELECT_BY_TICKET, MODE_TRADES) != true) continue;
        if (OrderSymbol() != g_chartSymbol || OrderType() != order_type) continue;
        if (!IsNfpManagedMagic(OrderMagicNumber())) continue;
        double close_price = (order_type == OP_BUY)
            ? MarketInfo(g_chartSymbol, MODE_BID)
            : MarketInfo(g_chartSymbol, MODE_ASK);
        OrderClose(OrderTicket(), OrderLots(), close_price, close_slippage, Red);
    }
}

void CloseNfpOpenTradesInOriginalOrder()
{
    CloseManagedPositionsByType(OP_BUY, 99999);
    CloseManagedPositionsByType(OP_SELL, 99999);
}

void CloseDailyDDPositionsInOriginalOrder()
{
    CloseManagedPositionsByType(OP_BUY, (int)g_slippagePts);
    CloseManagedPositionsByType(OP_SELL, (int)g_slippagePts);
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
    g_startLots_rw = StartLots;
    g_initialLegacyRiskLotPending = true;
    // Recovered from original JIT: BacktestSpeed is active only in Strategy Tester.
    g_backtestSpeedFast = false;
    g_backtestSpeedEnabled = false;
    g_backtestSpeedLastTime = 0;
    g_backtestSpeedLastM1 = 0;
    g_backtestSpeedLastProbeMinute = 0;
    if (MQLInfoInteger(MQL_TESTER) == 1)
    {
        if (BacktestSpeed == speed_fast)
        {
            g_backtestSpeedFast = true;
            g_backtestSpeedEnabled = true;
        }
        else if (BacktestSpeed == speed_super)
        {
            g_backtestSpeedFast = false;
            g_backtestSpeedEnabled = true;
        }
    }
    double    usdBalance;
    double    maxDdUsd;
    int       virtSlSlotIdx;
    int       virtSlFieldIdx;
    int       vpoSlotIdx;
    int       vpoFieldIdx;
    int       vpoExtraSlotIdx;
    int       strategyInitIdx;
    //----- -----
     // MQL4 tu dong khoi tao bool local ve false; MQL5 thi khong, nen phai gan
     // ro rang de giu dung hanh vi ban goc (bien nay khong duoc gan truoc khi
     // dung o duoi, IsDemo() ket qua bi bo qua trong ca ban mq4 goc).
    bool       isDemoFlag = false;

    // SetFontSize >0: ghi de co chu panel (0 = co mac dinh theo thiet ke goc)
    if (SetFontSize > 0)   g_panelFontSize = SetFontSize;

    // Recovered directly from original V4.6 JIT around 0x19aa50b0f47-0x19aa50b13c7.
    // Important ordering in the original:
    //   1) account BALANCE, optionally EQUITY;
    //   2) ResetHighestBalance => GlobalVariableSet("HighestBalance",0) + Sleep(5000);
    //   3) read the single terminal Global Variable "HighestBalance";
    //   4) highest = max(account value, stored value), write it back unconditionally;
    //   5) only AFTER that, ManualBalance may override the working risk balance.
    g_effectiveBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (UseEquity)
    {
        g_effectiveBalance = AccountInfoDouble(ACCOUNT_EQUITY);
    }
    if (ResetHighestBalance)
    {
        GlobalVariableSet("HighestBalance", 0.0);
        Sleep(5000);
    }
    double storedHighest = GlobalVariableGet("HighestBalance");
    if (storedHighest > g_effectiveBalance)
    {
        Print("HighestBalance value found: ", storedHighest);
        g_highestBalance = storedHighest;
    }
    else
    {
        g_highestBalance = g_effectiveBalance;
    }
    GlobalVariableSet("HighestBalance", g_highestBalance);
    if (ManualBalance > 0.0)
    {
        g_effectiveBalance = ManualBalance;
    }
    g_isSummerTime = false;
    g_euDstActive = false;
    g_nfpDateTable[0] = D'2026.12.04 12:30';
    g_nfpDateTable[1] = D'2026.11.06 12:30';
    g_nfpDateTable[2] = D'2026.10.02 12:30';
    g_nfpDateTable[3] = D'2026.09.04 12:30';
    g_nfpDateTable[4] = D'2026.08.07 12:30';
    g_nfpDateTable[5] = D'2026.07.02 12:30';
    g_nfpDateTable[6] = D'2026.06.05 12:30';
    g_nfpDateTable[7] = D'2026.05.08 12:30';
    g_nfpDateTable[8] = D'2026.04.03 12:30';
    g_nfpDateTable[9] = D'2026.03.06 12:30';
    g_nfpDateTable[10] = D'2026.02.06 12:30';
    g_nfpDateTable[11] = D'2026.01.09 12:30';
    g_nfpDateTable[12] = D'2025.12.16 12:30';
    g_nfpDateTable[13] = D'2025.11.07 12:30';
    g_nfpDateTable[14] = D'2025.10.03 12:30';
    g_nfpDateTable[15] = D'2025.09.05 12:30';
    g_nfpDateTable[16] = D'2025.08.01 12:30';
    g_nfpDateTable[17] = D'2025.07.03 12:30';
    g_nfpDateTable[18] = D'2025.06.06 12:30';
    g_nfpDateTable[19] = D'2025.05.02 12:30';
    g_nfpDateTable[20] = D'2025.04.04 12:30';
    g_nfpDateTable[21] = D'2025.03.07 12:30';
    g_nfpDateTable[22] = D'2025.02.07 12:30';
    g_nfpDateTable[23] = D'2025.01.10 12:30';
    g_nfpDateTable[24] = D'2024.12.06 12:30';
    g_nfpDateTable[25] = D'2024.11.01 12:30';
    g_nfpDateTable[26] = D'2024.10.04 12:30';
    g_nfpDateTable[27] = D'2024.09.06 12:30';
    g_nfpDateTable[28] = D'2024.08.02 12:30';
    g_nfpDateTable[29] = D'2024.07.05 12:30';
    g_nfpDateTable[30] = D'2024.06.07 12:30';
    g_nfpDateTable[31] = D'2024.05.03 12:30';
    g_nfpDateTable[32] = D'2024.04.05 12:30';
    g_nfpDateTable[33] = D'2024.03.08 12:30';
    g_nfpDateTable[34] = D'2024.02.02 12:30';
    g_nfpDateTable[35] = D'2024.01.05 12:30';
    g_nfpDateTable[36] = D'2023.12.08 12:30';
    g_nfpDateTable[37] = D'2023.11.03 12:30';
    g_nfpDateTable[38] = D'2023.10.06 12:30';
    g_nfpDateTable[39] = D'2023.09.01 12:30';
    g_nfpDateTable[40] = D'2023.08.04 12:30';
    g_nfpDateTable[41] = D'2023.07.07 12:30';
    g_nfpDateTable[42] = D'2023.06.02 12:30';
    g_nfpDateTable[43] = D'2023.05.05 12:30';
    g_nfpDateTable[44] = D'2023.04.07 12:30';
    g_nfpDateTable[45] = D'2023.03.10 12:30';
    g_nfpDateTable[46] = D'2023.02.03 12:30';
    g_nfpDateTable[47] = D'2023.01.06 12:30';
    g_nfpDateTable[48] = D'2022.12.02 12:30';
    g_nfpDateTable[49] = D'2022.11.04 12:30';
    g_nfpDateTable[50] = D'2022.10.07 12:30';
    g_nfpDateTable[51] = D'2022.09.02 12:30';
    g_nfpDateTable[52] = D'2022.08.05 12:30';
    g_nfpDateTable[53] = D'2022.07.08 12:30';
    g_nfpDateTable[54] = D'2022.06.03 12:30';
    g_nfpDateTable[55] = D'2022.05.06 12:30';
    g_nfpDateTable[56] = D'2022.04.01 12:30';
    g_nfpDateTable[57] = D'2022.03.04 12:30';
    g_nfpDateTable[58] = D'2022.02.04 12:30';
    g_nfpDateTable[59] = D'2022.01.07 12:30';
    g_nfpDateTable[60] = D'2021.12.03 12:30';
    g_nfpDateTable[61] = D'2021.11.05 12:30';
    g_nfpDateTable[62] = D'2021.10.08 12:30';
    g_nfpDateTable[63] = D'2021.09.03 12:30';
    g_nfpDateTable[64] = D'2021.08.06 12:30';
    g_nfpDateTable[65] = D'2021.07.02 12:30';
    g_nfpDateTable[66] = D'2021.06.04 12:30';
    g_nfpDateTable[67] = D'2021.05.07 12:30';
    g_nfpDateTable[68] = D'2021.04.02 12:30';
    g_nfpDateTable[69] = D'2021.03.05 12:30';
    g_nfpDateTable[70] = D'2021.02.05 12:30';
    g_nfpDateTable[71] = D'2021.01.08 12:30';
    g_nfpDateTable[72] = D'2020.12.04 12:30';
    g_nfpDateTable[73] = D'2020.11.06 12:30';
    g_nfpDateTable[74] = D'2020.10.02 12:30';
    g_nfpDateTable[75] = D'2020.09.04 12:30';
    g_nfpDateTable[76] = D'2020.08.07 12:30';
    g_nfpDateTable[77] = D'2020.07.02 12:30';
    g_nfpDateTable[78] = D'2020.06.05 12:30';
    g_nfpDateTable[79] = D'2020.05.08 12:30';
    g_nfpDateTable[80] = D'2020.04.03 12:30';
    g_nfpDateTable[81] = D'2020.03.06 12:30';
    g_nfpDateTable[82] = D'2020.02.07 12:30';
    g_nfpDateTable[83] = D'2020.01.10 12:30';
    g_nfpDateTable[84] = D'2019.12.06 12:30';
    g_nfpDateTable[85] = D'2019.11.01 12:30';
    g_nfpDateTable[86] = D'2019.10.04 12:30';
    g_nfpDateTable[87] = D'2019.09.06 12:30';
    g_nfpDateTable[88] = D'2019.08.02 12:30';
    g_nfpDateTable[89] = D'2019.07.05 12:30';
    g_nfpDateTable[90] = D'2019.06.07 12:30';
    g_nfpDateTable[91] = D'2019.05.03 12:30';
    g_nfpDateTable[92] = D'2019.04.05 12:30';
    g_nfpDateTable[93] = D'2019.03.08 12:30';
    g_nfpDateTable[94] = D'2019.02.01 12:30';
    g_nfpDateTable[95] = D'2019.01.04 12:30';
    g_nfpDateTable[96] = D'2018.12.07 12:30';
    g_nfpDateTable[97] = D'2018.11.02 12:30';
    g_nfpDateTable[98] = D'2018.10.05 12:30';
    g_nfpDateTable[99] = D'2018.09.07 12:30';
    g_nfpDateTable[100] = D'2018.08.03 12:30';
    g_nfpDateTable[101] = D'2018.07.06 12:30';
    g_nfpDateTable[102] = D'2018.06.01 12:30';
    g_nfpDateTable[103] = D'2018.05.04 12:30';
    g_nfpDateTable[104] = D'2018.04.06 12:30';
    g_nfpDateTable[105] = D'2018.03.09 12:30';
    g_nfpDateTable[106] = D'2018.02.02 12:30';
    g_nfpDateTable[107] = D'2018.01.05 12:30';
    g_nfpDateTable[108] = D'2017.12.08 12:30';
    g_nfpDateTable[109] = D'2017.11.03 12:30';
    g_nfpDateTable[110] = D'2017.10.06 12:30';
    g_nfpDateTable[111] = D'2017.09.01 12:30';
    g_nfpDateTable[112] = D'2017.08.04 12:30';
    g_nfpDateTable[113] = D'2017.07.07 12:30';
    g_nfpDateTable[114] = D'2017.06.02 12:30';
    g_nfpDateTable[115] = D'2017.05.05 12:30';
    g_nfpDateTable[116] = D'2017.04.07 12:30';
    g_nfpDateTable[117] = D'2017.03.10 12:30';
    g_nfpDateTable[118] = D'2017.02.03 12:30';
    g_nfpDateTable[119] = D'2017.01.06 12:30';
    g_nfpDateTable[120] = D'2016.12.02 12:30';
    g_nfpDateTable[121] = D'2016.11.04 12:30';
    g_nfpDateTable[122] = D'2016.10.07 12:30';
    g_nfpDateTable[123] = D'2016.09.02 12:30';
    g_nfpDateTable[124] = D'2016.08.05 12:30';
    g_nfpDateTable[125] = D'2016.07.08 12:30';
    g_nfpDateTable[126] = D'2016.06.03 12:30';
    g_nfpDateTable[127] = D'2016.05.06 12:30';
    g_nfpDateTable[128] = D'2016.04.01 12:30';
    g_nfpDateTable[129] = D'2016.03.04 12:30';
    g_nfpDateTable[130] = D'2016.02.05 12:30';
    g_nfpDateTable[131] = D'2016.01.08 12:30';
    g_nfpDateTable[132] = D'2015.12.04 12:30';
    g_nfpDateTable[133] = D'2015.11.06 12:30';
    g_nfpDateTable[134] = D'2015.10.02 12:30';
    g_nfpDateTable[135] = D'2015.09.04 12:30';
    g_nfpDateTable[136] = D'2015.08.07 12:30';
    g_nfpDateTable[137] = D'2015.07.02 12:30';
    g_nfpDateTable[138] = D'2015.06.05 12:30';
    g_nfpDateTable[139] = D'2015.05.08 12:30';
    g_nfpDateTable[140] = D'2015.04.03 12:30';
    g_nfpDateTable[141] = D'2015.03.06 12:30';
    g_nfpDateTable[142] = D'2015.02.06 12:30';
    g_nfpDateTable[143] = D'2015.01.09 12:30';
    g_nfpDateTable[144] = D'2014.12.05 12:30';
    g_nfpDateTable[145] = D'2014.11.07 12:30';
    g_nfpDateTable[146] = D'2014.10.03 12:30';
    g_nfpDateTable[147] = D'2014.09.05 12:30';
    g_nfpDateTable[148] = D'2014.08.01 12:30';
    g_nfpDateTable[149] = D'2014.07.03 12:30';
    g_nfpDateTable[150] = D'2014.06.06 12:30';
    g_nfpDateTable[151] = D'2014.05.02 12:30';
    g_nfpDateTable[152] = D'2014.04.04 12:30';
    g_nfpDateTable[153] = D'2014.03.07 12:30';
    g_nfpDateTable[154] = D'2014.02.07 12:30';
    g_nfpDateTable[155] = D'2014.01.10 12:30';
    g_nfpDateTable[156] = D'2013.12.06 12:30';
    g_nfpDateTable[157] = D'2013.11.08 12:30';
    g_nfpDateTable[158] = D'2013.10.22 12:30';
    g_nfpDateTable[159] = D'2013.09.06 12:30';
    g_nfpDateTable[160] = D'2013.08.02 12:30';
    g_nfpDateTable[161] = D'2013.07.05 12:30';
    g_nfpDateTable[162] = D'2013.06.07 12:30';
    g_nfpDateTable[163] = D'2013.05.03 12:30';
    g_nfpDateTable[164] = D'2013.04.05 12:30';
    g_nfpDateTable[165] = D'2013.03.08 12:30';
    g_nfpDateTable[166] = D'2013.02.01 12:30';
    g_nfpDateTable[167] = D'2013.01.04 12:30';
    g_nfpDateTable[168] = D'2012.12.07 12:30';
    g_nfpDateTable[169] = D'2012.11.02 12:30';
    g_nfpDateTable[170] = D'2012.10.05 12:30';
    g_nfpDateTable[171] = D'2012.09.07 12:30';
    g_nfpDateTable[172] = D'2012.08.03 12:30';
    g_nfpDateTable[173] = D'2012.07.06 12:30';
    g_nfpDateTable[174] = D'2012.06.01 12:30';
    g_nfpDateTable[175] = D'2012.05.04 12:30';
    g_nfpDateTable[176] = D'2012.04.06 12:30';
    g_nfpDateTable[177] = D'2012.03.09 12:30';
    g_nfpDateTable[178] = D'2012.02.03 12:30';
    g_nfpDateTable[179] = D'2012.01.06 12:30';
    g_nfpDateTable[180] = D'2011.12.02 12:30';
    g_nfpDateTable[181] = D'2011.11.04 12:30';
    g_nfpDateTable[182] = D'2011.10.07 12:30';
    g_nfpDateTable[183] = D'2011.09.02 12:30';
    g_nfpDateTable[184] = D'2011.08.05 12:30';
    g_nfpDateTable[185] = D'2011.07.08 12:30';
    g_nfpDateTable[186] = D'2011.06.03 12:30';
    g_nfpDateTable[187] = D'2011.05.06 12:30';
    g_nfpDateTable[188] = D'2011.04.01 12:30';
    g_nfpDateTable[189] = D'2011.03.04 12:30';
    g_nfpDateTable[190] = D'2011.02.04 12:30';
    g_nfpDateTable[191] = D'2011.01.07 12:30';
    g_nfpDateTable[192] = D'2010.12.03 12:30';
    g_nfpDateTable[193] = D'2010.11.05 12:30';
    g_nfpDateTable[194] = D'2010.10.08 12:30';
    g_nfpDateTable[195] = D'2010.09.03 12:30';
    g_nfpDateTable[196] = D'2010.08.06 12:30';
    g_nfpDateTable[197] = D'2010.07.02 12:30';
    g_nfpDateTable[198] = D'2010.06.04 12:30';
    g_nfpDateTable[199] = D'2010.05.07 12:30';
    g_nfpDateTable[200] = D'2010.04.02 12:30';
    g_nfpDateTable[201] = D'2010.03.05 12:30';
    g_nfpDateTable[202] = D'2010.02.05 12:30';
    g_nfpDateTable[203] = D'2010.01.08 12:30';
    g_nfpDateTable[204] = D'2009.12.04 12:30';
    g_nfpDateTable[205] = D'2009.11.06 12:30';
    g_nfpDateTable[206] = D'2009.10.02 12:30';
    g_nfpDateTable[207] = D'2009.09.04 12:30';
    g_nfpDateTable[208] = D'2009.08.07 12:30';
    g_nfpDateTable[209] = D'2009.07.02 12:30';
    g_nfpDateTable[210] = D'2009.06.05 12:30';
    g_nfpDateTable[211] = D'2009.05.08 12:30';
    g_nfpDateTable[212] = D'2009.04.03 12:30';
    g_nfpDateTable[213] = D'2009.03.06 12:30';
    g_nfpDateTable[214] = D'2009.02.06 12:30';
    g_nfpDateTable[215] = D'2009.01.09 12:30';
    g_nfpDateTable[216] = D'2008.12.05 12:30';
    g_nfpDateTable[217] = D'2008.11.07 12:30';
    g_nfpDateTable[218] = D'2008.10.03 12:30';
    g_nfpDateTable[219] = D'2008.09.05 12:30';
    g_nfpDateTable[220] = D'2008.08.01 12:30';
    g_nfpDateTable[221] = D'2008.07.03 12:30';
    g_nfpDateTable[222] = D'2008.06.06 12:30';
    g_nfpDateTable[223] = D'2008.05.02 12:30';
    g_nfpDateTable[224] = D'2008.04.04 12:30';
    g_nfpDateTable[225] = D'2008.03.07 12:30';
    g_nfpDateTable[226] = D'2008.02.01 12:30';
    g_nfpDateTable[227] = D'2008.01.04 12:30';
    g_nfpDateTable[228] = D'2007.12.07 12:30';
    g_nfpDateTable[229] = D'2007.11.02 12:30';
    g_nfpDateTable[230] = D'2007.10.05 12:30';
    g_nfpDateTable[231] = D'2007.09.07 12:30';
    g_nfpDateTable[232] = D'2007.08.03 12:30';
    g_nfpDateTable[233] = D'2007.07.06 12:30';
    g_nfpDateTable[234] = D'2007.06.01 12:30';
    g_nfpDateTable[235] = D'2007.05.04 12:30';
    g_nfpDateTable[236] = D'2007.04.06 12:30';
    g_nfpDateTable[237] = D'2007.03.09 12:30';
    g_nfpDateTable[238] = D'2007.02.02 12:30';
    g_nfpDateTable[239] = D'2007.01.05 12:30';
    // Original OnInit calls the calendar helper whenever the NFP filter is enabled.
    // In Strategy Tester the calendar normally returns 0; runtime then uses hardcoded dates.
    if (EnableNFP_Filter)   g_nextNFPCalendar = GetNextNFPFromCalendar();
    g_nfpCalendarLastRefresh = 0;
    if (Risk == 1234)
    {
        g_startLots_rw = MarketInfo(g_chartSymbol, MODE_MINLOT);
    }
    if (TradeFrequency == 5 && Risk == 1234)
    {
        usdBalance = ConvertAccountCurrencyToUsd(AccountInfoDouble(ACCOUNT_BALANCE));
        maxDdUsd = MaxAllowedDD / 100.0 * usdBalance;
        if (maxDdUsd > g_ddTierThreshold4Usd)
        {
            g_tradeFrequencyMode = 3;
        }
        else
        {
            if (maxDdUsd > g_ddTierThreshold3)
            {
                g_tradeFrequencyMode = 2;
            }
            else
            {
                if (maxDdUsd > g_ddTierThreshold2Usd)
                {
                    g_tradeFrequencyMode = 1;
                }
                else
                {
                    g_tradeFrequencyMode = 0;
                }
            }
        }
    }
    else
    {
        g_tradeFrequencyMode = TradeFrequency;
    }
    if (g_tradeFrequencyMode == 0)
    {
        g_runStrategy4 = false;
        g_runStrategy5 = false;
        g_runStrategy6 = false;
        g_runStrategy7 = false;
        g_runStrategy8 = false;
        g_runStrategy9 = false;
        g_riskFactorByTier = 2.4;
        if (UseVariableValues)
        {
            g_riskFactorByTier = 3.0;
        }
    }
    else
    {
        if (g_tradeFrequencyMode == 1)
        {
            g_runStrategy4 = true;
            g_runStrategy5 = true;
            g_runStrategy6 = false;
            g_runStrategy7 = false;
            g_runStrategy8 = false;
            g_runStrategy9 = false;
            g_riskFactorByTier = 3.4;
            if (UseVariableValues)
            {
                g_riskFactorByTier = 4.0;
            }
        }
        else
        {
            if (g_tradeFrequencyMode == 2)
            {
                g_runStrategy4 = true;
                g_runStrategy5 = true;
                g_runStrategy6 = true;
                g_runStrategy7 = true;
                g_runStrategy8 = false;
                g_runStrategy9 = false;
                g_riskFactorByTier = 4.1;
                if (UseVariableValues)
                {
                    g_riskFactorByTier = 5.0;
                }
            }
            else
            {
                if (g_tradeFrequencyMode == 3)
                {
                    g_runStrategy4 = true;
                    g_runStrategy5 = true;
                    g_runStrategy6 = true;
                    g_runStrategy7 = true;
                    g_runStrategy8 = true;
                    g_runStrategy9 = false;
                    g_riskFactorByTier = 4.8;
                    if (UseVariableValues)
                    {
                        g_riskFactorByTier = 5.6;
                    }
                }
                else
                {
                    if (g_tradeFrequencyMode == 4)
                    {
                        g_runStrategy4 = true;
                        g_runStrategy5 = true;
                        g_runStrategy6 = true;
                        g_runStrategy7 = true;
                        g_runStrategy8 = true;
                        g_runStrategy9 = true;
                        g_riskFactorByTier = 5.1;
                        if (UseVariableValues)
                        {
                            g_riskFactorByTier = 6.0;
                        }
                    }
                    else
                    {
                        if (g_tradeFrequencyMode == 6)
                        {
                            g_runStrategy1 = RunStrat1;
                            g_runStrategy2 = RunStrat2;
                            g_runStrategy3 = RunStrat3;
                            g_runStrategy4 = RunStrat4;
                            g_runStrategy5 = RunStrat5;
                            g_runStrategy6 = RunStrat6;
                            g_runStrategy7 = RunStrat7;
                            g_runStrategy8 = RunStrat8;
                            g_runStrategy9 = RunStrat9;
                        }
                    }
                }
            }
        }
    }
    g_orderComment = ST1_Comment;
    g_propfirmDailyPeakEquity = 0.0;
    g_propfirmDailyStartEquity = 0.0;
    g_propfirmDailyDDHit = false;
    g_lastM5BarTime = 0;
    g_propfirmDailyDDOn = true;
    g_curStrategyMagic = ST1_MagicNumber;
    g_maxPanelObjects = 300;
    g_panelCellWidth = g_panelFontSize * 25 * g_panelWidthScale * InfoPanelSizeAdjust;
    g_panelCellHeight = g_panelFontSize * 3.5 * g_panelRowHeightFactor * InfoPanelSizeAdjust;
    g_currentStrategyIndex = 0;
    g_chartSymbol = Symbol();
    g_symbolPoint = SymbolInfoDouble(g_chartSymbol, 16);
    g_pipSize = g_symbolPoint;
    if ((MarketInfo(g_chartSymbol, MODE_DIGITS) == 3.0 || MarketInfo(g_chartSymbol, MODE_DIGITS) == 5.0))
    {
        g_pipSize = g_symbolPoint * 10.0;
    }
    if (SymbolInfoInteger(g_chartSymbol, 17) == 0x1)
    {
        g_pipSize = g_symbolPoint / 10.0;
    }
    g_symbolDigits = (int)MarketInfo(g_chartSymbol, MODE_DIGITS);
    if (FridayStopHour < 0)
    {
        g_useFridayStop = false;
    }
    else
    {
        g_useFridayStop = true;
    }
    g_curSpread = MarketInfo(g_chartSymbol, MODE_ASK) - MarketInfo(g_chartSymbol, MODE_BID);
    g_strategyStartLots[g_currentStrategyIndex] = NormalizeDouble(MathFloor(g_startLots_rw * 100.0) / 100.0, 2);
    if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.1)
    {
        g_strategyStartLots[g_currentStrategyIndex] = NormalizeDouble((MathFloor(g_startLots_rw * 10.0)) / 10.0, 1);
        if (g_strategyStartLots[g_currentStrategyIndex] < 0.1)
        {
            g_strategyStartLots[g_currentStrategyIndex] = 0.1;
        }
    }
    if (g_strategyStartLots[g_currentStrategyIndex] < MarketInfo(g_chartSymbol, MODE_MINLOT))
    {
        g_strategyStartLots[g_currentStrategyIndex] = MarketInfo(g_chartSymbol, MODE_MINLOT);
    }
    if (g_strategyStartLots[g_currentStrategyIndex] > MarketInfo(g_chartSymbol, MODE_MAXLOT))
    {
        g_strategyStartLots[g_currentStrategyIndex] = MarketInfo(g_chartSymbol, MODE_MAXLOT);
    }
    if (g_gridSpacingPips * g_pipSize < g_symbolPoint)
    {
        g_gridSpacingPips = g_symbolPoint / g_pipSize;
    }
    g_minStopDistPrice = MarketInfo(g_chartSymbol, MODE_STOPLEVEL) * g_symbolPoint;
    g_freezeDistPrice = MarketInfo(g_chartSymbol, MODE_FREEZELEVEL) * g_symbolPoint;
    g_symbolSuffix = StringSubstr(Symbol(), 6, 10);
    if (g_symbolSuffix != "")
    {
        Print("Suffix detected: " + g_symbolSuffix);
    }
    if ((StringFind(Symbol(), "XAUUSD", 0) >= 0 || StringFind(Symbol(), "xauusd", 0) >= 0 || StringFind(Symbol(), "GOLD", 0) >= 0 || StringFind(Symbol(), "gold", 0) >= 0 || StringFind(Symbol(), "Gold", 0) >= 0 || StringFind(Symbol(), "GLD", 0) >= 0))
    {
        g_chartSymbol = Symbol();
        g_strategySymbols[g_strategyCount] = Symbol();
        LoadStrategy1Settings();
        LoadStrategyRuntimeSettings(0);
        g_strategyCount++;
    }
    else
    {
        g_chartSymbol = Symbol();
        LoadStrategyRuntimeSettings(0);
    }
    // Original dump contains no separate pair-initialisation failure message here.
    if (g_stopLossPips <= 0.0)
    {
        g_stopLossPips = 1.0;
    }
    if (g_takeProfitPips <= 0.0)
    {
        g_takeProfitPips = 1.0;
    }
    if (g_beExtraPips > g_beTriggerPips)
    {
        g_beExtraPips = g_beTriggerPips + 0.1;
    }
    if (g_pendingMinGapPips < g_freezeDistPrice / g_pipSize)
    {
        g_pendingMinGapPips = (int)(g_freezeDistPrice / g_pipSize);
    }
    if (g_profitTrailDistancePips != 0.0 && g_profitTrailDistancePips < g_freezeDistPrice / g_pipSize)
    {
        g_profitTrailDistancePips = g_freezeDistPrice / g_pipSize;
    }
    if (g_profitTrailDistancePips != 0.0 && g_profitTrailDistancePips < g_minStopDistPrice / g_pipSize)
    {
        g_profitTrailDistancePips = g_minStopDistPrice / g_pipSize;
    }
    if (g_timeTrailDelayMin > 0.0 && g_timeTrailDistancePips < g_freezeDistPrice / g_pipSize)
    {
        g_timeTrailDistancePips = g_freezeDistPrice / g_pipSize;
    }
    if (g_timeTrailDelayMin > 0.0 && g_timeTrailDistancePips < g_minStopDistPrice / g_pipSize)
    {
        g_timeTrailDistancePips = g_minStopDistPrice / g_pipSize;
    }
    if (g_stopLossPips < g_minStopDistPrice * 2.0 / g_pipSize)
    {
        g_stopLossPips = g_minStopDistPrice * 2.0 / g_pipSize;
    }
    if (g_takeProfitPips < g_minStopDistPrice * 2.0 / g_pipSize)
    {
        g_takeProfitPips = g_minStopDistPrice * 2.0 / g_pipSize;
    }
    if (g_entryBreakoutPips < g_minStopDistPrice * 2.0 / g_pipSize)
    {
        g_entryBreakoutPips = g_minStopDistPrice * 2.0 / g_pipSize;
    }
    if (g_fractalRightBars < 1)
    {
        g_fractalRightBars = 1;
    }
    if (g_fractalLeftBars < 1)
    {
        g_fractalLeftBars = 1;
    }
    if (g_entryBreakoutPips < 0.1)
    {
        g_entryBreakoutPips = 0.1;
    }
    g_pendingExpirySecs = g_pendingExpiryHours * 60 * 60;
    if (g_pendingExpiryHours > 0)
    {
        g_pendingOrderExpiry = TimeCurrent() + g_pendingExpirySecs;
    }
    else
    {
        g_pendingOrderExpiry = 0;
    }
    if (Virtual_expiration)
    {
        g_pendingOrderExpiry = 0;
    }
    g_nfpWindowActive = false;
    g_lastTrailOrderTime = TimeCurrent();
    g_buyOrderSeen = false;
    g_sellOrderSeen = false;
    if (g_maxSpreadPts > g_MaxSpread_rw)
    {
        g_maxSpreadPts = g_MaxSpread_rw;
    }
    FindBuyEntryHigh(g_entryTfPeriod);
    FindSellEntryLow(g_entryTfPeriod);
    g_buyEntryPrice = NormalizeDouble(g_entryHighPrice, g_symbolDigits);
    g_sellEntryPrice = NormalizeDouble(g_entryLowPrice, g_symbolDigits);
    g_ordersSinceAnchor = 0;
    g_timeTrailDelaySec = (int)(g_timeTrailDelayMin * 60.0);
    g_marketClosedFlag = true;
    g_freezeDistPrice = MarketInfo(g_chartSymbol, MODE_FREEZELEVEL) * g_symbolPoint;
    if (!(g_useTradingHours))
    {
        g_marketClosedFlag = false;
    }
    g_virtualSLPrice = 0.0;
    g_symbolSuffix = StringSubstr(g_chartSymbol, 6, 0);
    if (Risk > 0)
    {
    }
    if (g_startLots_rw < 0.0)
    {
        g_startLots_rw = 0.01;
    }
    if (g_maxLotCap > MarketInfo(g_chartSymbol, MODE_MAXLOT))
    {
        g_maxLotCap = MarketInfo(g_chartSymbol, MODE_MAXLOT);
    }
    for (virtSlSlotIdx = 0; virtSlSlotIdx < g_virtSLCacheSize; virtSlSlotIdx++)
    {
        for (virtSlFieldIdx = 0; virtSlFieldIdx < 2; virtSlFieldIdx++)
        {
            g_virtSLCache[virtSlSlotIdx][virtSlFieldIdx] = 0.0;
        }
    }
    for (vpoSlotIdx = 0; vpoSlotIdx < g_virtualOrderSlots; vpoSlotIdx++)
    {
        for (vpoFieldIdx = 0; vpoFieldIdx < 3; vpoFieldIdx++)
        {
            g_virtualPendingOrders[vpoSlotIdx][vpoFieldIdx] = 0.0;
        }
    }
    for (vpoExtraSlotIdx = 0; vpoExtraSlotIdx < 100; vpoExtraSlotIdx++)
    {
        g_virtualPendingOrders[vpoExtraSlotIdx][0] = 0.0;
        g_virtualPendingOrders[vpoExtraSlotIdx][1] = 0.0;
    }
    g_fridayStopDone = false;
    g_commentBuy1 = ST1_Comment + "B1";
    g_commentBuy2 = ST1_Comment + "B2";
    g_commentSell1 = ST1_Comment + "S1";
    g_commentSell2 = ST1_Comment + "S2";
    g_lastHour = Hour();
    if (g_limitPendingToOne)
    {
        g_maxPendingOrders = 1;
    }
    for (strategyInitIdx = 0; strategyInitIdx < 99; strategyInitIdx++)
    {
        g_lastSignalBarsCount[strategyInitIdx] = 0;
        g_lastEntryBarsCount[strategyInitIdx] = 0;
        g_lastEntryBarTime[strategyInitIdx] = iTime(g_chartSymbol, MT4Period(g_entryTfPeriod), 1);
        if (!(g_strategyStartLots[strategyInitIdx] < g_startLots_rw))   continue;
        g_strategyStartLots[strategyInitIdx] = g_startLots_rw;

    }
    if (g_profitCloseMode == 1)
    {
        g_stopExtraPips = 0.0;
    }
    g_symbolDigits = (int)MarketInfo(g_chartSymbol, MODE_DIGITS);
    g_isDemoAccount = false;
    IsDemo();

    if (isDemoFlag == true)
    {
        g_isDemoAccount = true;
    }
    if (ShowInfoPanel)
    {
        if (g_rankMode == 1)
        {
            RankStrategiesByClosedProfit();
        }
        else
        {
            if (g_rankMode == 2)
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
// ============================================================================
// DumpBacktestSpeedAllowTick —— 专项说明（纯注释，供维护者与回测者阅读）
// ----------------------------------------------------------------------------
//  【启用条件】仅在 OnInit 中当 MQLInfoInteger(MQL_TESTER)==1 时启用，
//              即只在策略测试器生效，实盘不节流。
//              注意：可视化回测的 MQL_TESTER 同样为 1，因此可视化时也会跳 tick，
//              容易误判为"EA 漏单"。
//
//  【三档语义】
//    speed_normal : g_backtestSpeedEnabled=false → 恒返回 true，每个 tick 全跑
//    speed_fast   : 秒级节流 —— TimeCurrent() 距上次放行超过 1 秒才放行；
//                   且出现新的已收 M1 棒（iTime(M1,1) 变化）时无条件放行
//    speed_super  : 分钟级节流 —— 60 秒探针窗口内直接 return false；
//                   窗口到期后仅当出现新的已收 M1 棒才放行
//
//    本函数是 OnTick 的第一道门：一旦 return false，后续模块全部不执行，
//    包括 UpdateEffectiveBalanceTracking、UpdateGmtDstDetection、
//    RefreshNfpCalendarCache、ApplyTradeFrequencyTiers、
//    CheckDailyRolloverAndPropFirmGate、DetectNewH1Bar、
//    RunAllStrategies（含挂单管理与 ManageBuyPositions / ManageSellPositions）。
//
//  【已知问题（已核验；行为与 V4.6 原版一致，当前未修改）】
//    1) 三档结果不等价：被跳过的不仅是"找信号"，还有虚拟止损、利润/时间/TP/
//       滑点/分形追踪、保本、点差撤补挂单、周五强平、NFP 平仓。
//       → 正式差分回测必须使用 speed_normal。
//    2) speed_super 可能整分钟漏处理：每分钟探针的提前 return 位于 M1 棒检查
//       之前，若分钟开始时 iTime(M1,1) 尚未翻到新棒（数据缺口、节假日后、
//       tick 时间戳与 bar 时间错位），该分钟内其余 tick 会被全部吞掉，
//       只能等到下一分钟的探针窗口才恢复。
//    3) speed_fast 的"每秒一次"并不严格：新 M1 棒的放行分支不刷新
//       g_backtestSpeedLastTime，导致放行后紧邻的 tick 可能再次放行，
//       实际放行率高于 1 次/秒。
//    4) 跳过的 H1 新棒会丢：DetectNewH1Bar 为"比较并覆盖"式实现，
//       节流窗口内若跨过多根 H1 棒，只会补触发一次新棒信号，中间评估机会丢失。
//
//  【建议改法（尚未实施；实施前请确认是否需要与原版保持逐 tick 一致）】
//    · speed_super：把 M1 新棒判断提到分钟探针的提前 return 之前
//    · speed_fast：新棒放行分支同步刷新 g_backtestSpeedLastTime
//    · 两者都会改变回测结果，需与 V4.6 原版对照后再决定是否采纳
// ============================================================================
// DumpBacktestSpeedAllowTick —— 回测加速节流：fast=每秒最多 1 个 tick，
//                               super=每根已收 M1 K 线最多处理一次
bool DumpBacktestSpeedAllowTick()
{
    if (!(g_backtestSpeedEnabled))   return(true);

    bool skipTick = false;
    if (g_backtestSpeedFast)
    {
        datetime now = TimeCurrent();
        if (now > g_backtestSpeedLastTime + 1)
        {
            g_backtestSpeedLastTime = now;
            skipTick = false;
        }
        else
        {
            skipTick = true;
        }
    }
    else
    {
        // speed_super: only a new closed M1 bar is accepted.  Avoid the expensive
        // iTime() series lookup on every real tick: a closed M1 bar cannot change
        // again while TimeCurrent() is still inside the same server minute.
        datetime now = TimeCurrent();
        if (now < g_backtestSpeedLastProbeMinute + 60)   return(false);
        datetime minuteStart = now - (now % 60);
        g_backtestSpeedLastProbeMinute = minuteStart;
        skipTick = true;
    }

    datetime m1BarTime = iTime(Symbol(), PERIOD_M1, 1);
    if (m1BarTime > g_backtestSpeedLastM1)
    {
        g_backtestSpeedLastM1 = m1BarTime;
        return(true);
    }
    if (skipTick)   return(false);
    return(true);
}
//DumpBacktestSpeedAllowTick <<==--------   --------

// =====================================================================
// OnTick 语义模块拆分（批次：2026-09）
// 原反编译 OnTick 约~600 行平铺过程。以下模块按原语句顺序 1:1 抽取。
// 语句本体保持原样（未改写、未重排），仅消除 9 个策略调度块的字面重复：
//   UpdateEffectiveBalanceTracking      有效余额/OnlyUp 高水位 + ManualBalance 覆盖
//   ApplyFakeoutFilterMode              FakeOutFilter -> M1/M15/H1 使能映射
//   UpdateGmtDstDetection               US/EU 夏令时状态机 + GMT 偏移探测
//   RefreshNfpCalendarCache             NFP 日历缓存：900 秒刷新；回测用硬编码日期。
//   EnforceManualHistoricalDDCompat     原版非法输入组合兼容（零除行为复现）
//   ApplyTradeFrequencyTiers            交易频率档位 -> 策略开关/风险系数
//   CheckDailyRolloverAndPropFirmGate   D1 换日重置 + PropFirm 日内回撤闸门
//   DetectNewH1Bar                      H1 收盘 K 线变化检测
//   RunAllStrategies / RunStrategySlot   9 策略槽位调度（顺序保持原版 1,4,2,3,6,5,9,7,8）
//   UpdatePanelsOnNewM5Bar              M5 新 K 线 -> 策略/历史面板刷新
//   FinishTickLotResizeThrottle         每 2 tick 的余额快照手数再平衡
// =====================================================================

// UpdateEffectiveBalanceTracking —— 有效余额（OnlyUp 高水位 + ManualBalance 覆盖）
void UpdateEffectiveBalanceTracking()
{
    g_effectiveBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (UseEquity)
    {
        g_effectiveBalance = AccountInfoDouble(ACCOUNT_EQUITY);
    }
    if (OnlyUp && g_highestBalance > g_effectiveBalance)
    {
        g_effectiveBalance = g_highestBalance;
    }
    if (g_effectiveBalance > g_highestBalance)
    {
        g_highestBalance = g_effectiveBalance;
        GlobalVariableSet("HighestBalance", g_highestBalance);
    }
    if (ManualBalance > 0.0)
    {
        g_effectiveBalance = ManualBalance;
    }
}

// ApplyFakeoutFilterMode —— FakeOutFilter 输入 -> M1/M15/H1 假突破过滤器使能
void ApplyFakeoutFilterMode()
{
    if (FakeOutFilter == 0)
    {
        g_fakeoutEnableM1 = false;
        g_fakeoutEnableM15 = false;
        g_fakeoutEnableH1 = false;
    }
    else
    {
        if (FakeOutFilter == 1)
        {
            g_fakeoutEnableM1 = true;
            g_fakeoutEnableM15 = false;
            g_fakeoutEnableH1 = false;
        }
        else
        {
            if (FakeOutFilter == 2)
            {
                g_fakeoutEnableM1 = true;
                g_fakeoutEnableM15 = true;
                g_fakeoutEnableH1 = false;
            }
            else
            {
                if (FakeOutFilter == 3)
                {
                    g_fakeoutEnableM1 = true;
                    g_fakeoutEnableM15 = true;
                    g_fakeoutEnableH1 = true;
                }
            }
        }
    }
}

// UpdateGmtDstDetection —— US/EU 夏令时状态机：偏移切换时重新探测 GMT；
//                         非 AutoGMT（或回测）直接用冬/夏配置偏移推 NFP 时间
void UpdateGmtDstDetection()
{
    bool   dstHandled = false;   // 原 local_1_bool：本次 tick 是否已处理过 DST 切换
    if (IsAmericanDst())
    {
        g_brokerGmtOffset = Broker_GMT_OFFSET_Summer;
        if ((!(g_isSummerTime) || !(g_gmtDetectDone)) && AutoGMT && !(dstHandled))
        {
            g_isSummerTime = true;
            g_euDstActive = true;
            g_detectedGmtOffset = DetectBrokerGmtOffset();
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset wrongly detected.  Trying againg!");
                Sleep(2000);
                g_detectedGmtOffset = DetectBrokerGmtOffset();
            }
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
            }
            g_gmtDetectDone = true;
            dstHandled = true;
            Print("DST_US on");
        }
    }
    else
    {
        g_brokerGmtOffset = Broker_GMT_OFFSET_Winter;
        if ((g_isSummerTime || !(g_gmtDetectDone)) && AutoGMT && !(dstHandled))
        {
            g_isSummerTime = false;
            g_euDstActive = false;
            g_detectedGmtOffset = DetectBrokerGmtOffset();
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset wrongly detected.  Trying againg!");
                Sleep(2000);
                g_detectedGmtOffset = DetectBrokerGmtOffset();
            }
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
            }
            g_gmtDetectDone = true;
            dstHandled = true;
            Print("DST_US off");
        }
    }
    bool isEuDst = MT4EuropeanDST();
    if (isEuDst)
    {
        if ((!(g_euDstActive) || !(g_gmtDetectDone)) && AutoGMT && !(dstHandled))
        {
            g_euDstActive = true;
            g_detectedGmtOffset = DetectBrokerGmtOffset();
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset wrongly detected.  Trying againg!");
                Sleep(2000);
                g_detectedGmtOffset = DetectBrokerGmtOffset();
            }
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
            }
            g_gmtDetectDone = true;
            dstHandled = true;
            Print("DST_EU on");
        }
    }
    else
    {
        if ((g_euDstActive || !(g_gmtDetectDone)) && AutoGMT && !(dstHandled))
        {
            g_euDstActive = false;
            g_detectedGmtOffset = DetectBrokerGmtOffset();
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset wrongly detected.  Trying againg!");
                Sleep(2000);
                g_detectedGmtOffset = DetectBrokerGmtOffset();
            }
            if (g_detectedGmtOffset == 999)
            {
                Print("GMT_Offset still wrong.  Using VPS time for GMT detection!");
            }
            g_gmtDetectDone = true;
            dstHandled = true;
            Print("DST_EU off");
        }
    }
    if (AutoGMT && MQLInfoInteger(MQL_TESTER) != 1)
    {
        if (g_detectedGmtOffset != 999)
        {
            g_nfpAdjustedNow = TimeCurrent() - g_detectedGmtOffset * 3600;
        }
        else
        {
            g_nfpAdjustedNow = TimeGMT();
        }
    }
    else
    {
        g_nfpAdjustedNow = TimeCurrent() - g_brokerGmtOffset * 3600;
    }
}

// RefreshNfpCalendarCache —— 原版 V4.6 实盘日历缓存：距上次刷新 900 秒
// 或当前无缓存事件时立即拉取；回测不走此路径（使用硬编码 NFP 日期）
void RefreshNfpCalendarCache()
{
    if (EnableNFP_Filter && UseMQL5Calendar && MQLInfoInteger(MQL_TESTER) != 1)
    {
        datetime nfpRefreshNow = TimeTradeServer();
        if (nfpRefreshNow > g_nfpCalendarLastRefresh + 900 || g_nextNFPCalendar == 0)
        {
            g_nextNFPCalendar = GetNextNFPFromCalendar();
            g_nfpCalendarLastRefresh = TimeTradeServer();
        }
    }
}

// EnforceManualHistoricalDDCompat —— 原版 Market EX5 对该不兼容输入组合的行为：
// 手动频率从不初始化历史 DD 除数，首个 tick 以零除严重错误终止；此处按原样复现。
void EnforceManualHistoricalDDCompat()
{
    if (TradeFrequency == Manual_Strategy_Selection && Risk == MaxHistoricalDD && UseWeightedLots &&
        (RunStrat1 || RunStrat2 || RunStrat3 || RunStrat4 || RunStrat5 ||
            RunStrat6 || RunStrat7 || RunStrat8 || RunStrat9))
    {
        string original_manual_dd_empty = StringSubstr(Symbol(), 0, 0);
        int original_manual_dd_divisor = (int)StringToInteger(original_manual_dd_empty);
        int original_manual_dd_result = (int)AccountInfoInteger(ACCOUNT_LOGIN) / original_manual_dd_divisor;
        Print("manual historical-DD compatibility result: ", original_manual_dd_result);
    }
}

// ApplyTradeFrequencyTiers —— 交易频率档位选择；随后将档位映射为策略开关与风险系数
// ----------------------------------------------------------------------------
//  【档位的两种来源】
//    A. 仅当 TradeFrequency == 5 (Auto) 且 Risk == 1234 时：
//         档位由「账户余额」与「MaxAllowedDD」共同算出：
//           tierUsdBalance = ConvertAccountCurrencyToUsd(AccountInfoDouble(ACCOUNT_BALANCE))
//           tierMaxDDUsd   = MaxAllowedDD / 100.0 * tierUsdBalance
//         再将 tierMaxDDUsd 与下面四个「绝对 USD 阈值」比较，得到档位 0~3：
//           > 810 → 档位 3 ；> 560 → 档位 2 ；> 330 → 档位 1 ；否则 → 档位 0
//       · 用的是当前账户 BALANCE（已实现资金，不含浮动盈亏），不是某一天的余额，
//         也不是 equity；每个 tick 都在本函数里重算。
//       · tierMaxDDUsd 是一个"预算金额"（我声明能承受多少美元回撤），
//         与实际发生的盈亏无关。
//
//    B. 其余所有情况（TradeFrequency 不为 Auto，或 Risk 不为 1234）：
//         直接执行 g_tradeFrequencyMode = TradeFrequency;
//       → 档位完全由 TradeFrequency 直接指定，
//         MaxAllowedDD 与账户余额都不再参与任何档位计算。
//
//  【档位 → 策略开关与风险系数】（UseVariableValues = true 时）
//    档位 0 : 策略 1,2,3                      riskFactor 3.0
//    档位 1 : + 4,5                           riskFactor 4.0
//    档位 2 : + 6,7                           riskFactor 5.0
//    档位 3 : + 8                             riskFactor 5.6
//    档位 4 : + 9                             riskFactor 6.0（仅手动档可选）
//    （UseVariableValues = false 时对应 2.4 / 3.4 / 4.1 / 4.8 / 5.1）
//
//  【升档的两个后果（同时发生）】
//    1) 启用更多策略 → 并行单子变多
//    2) riskFactor 变大 → 它在手数公式里是分母（g_ddLotFactor = MaxAllowedDD / riskFactor）
//       → 单策略手数反而变小（防止总暴露随余额爆炸）
//
//  【实操建议】
//    · Auto 模式会随余额增长自动改「策略集合 + 手数系数」，导致：
//      同参数在不同余额下结果不可比、回测不可复现、中途可能悄悄升档。
//    · Prop Firm / 固定本金场景建议用固定档（如 Conservative_Frequency = 1），
//      档位与手数完全可预测；此时 MaxAllowedDD 对档位不起作用。
//    · 注意口径不一致：档位判定硬编码用 ACCOUNT_BALANCE（不受 UseEquity 影响），
//      而手数基准 g_effectiveBalance 在 UseEquity = true 时会改用 equity。
//      建议保持 UseEquity = false 使两者口径统一。
// ============================================================================
void ApplyTradeFrequencyTiers()
{
    double   tierUsdBalance;
    double   tierMaxDDUsd;
    if (TradeFrequency == 5 && Risk == 1234)
    {
        tierUsdBalance = ConvertAccountCurrencyToUsd(AccountInfoDouble(ACCOUNT_BALANCE));
        tierMaxDDUsd = MaxAllowedDD / 100.0 * tierUsdBalance;
        if (tierMaxDDUsd > g_ddTierThreshold4Usd)
        {
            g_tradeFrequencyMode = 3;
        }
        else
        {
            if (tierMaxDDUsd > g_ddTierThreshold3)
            {
                g_tradeFrequencyMode = 2;
            }
            else
            {
                if (tierMaxDDUsd > g_ddTierThreshold2Usd)
                {
                    g_tradeFrequencyMode = 1;
                }
                else
                {
                    g_tradeFrequencyMode = 0;
                }
            }
        }
    }
    else
    {
        g_tradeFrequencyMode = TradeFrequency;
    }
    if (g_tradeFrequencyMode == 0)
    {
        g_runStrategy4 = false;
        g_runStrategy5 = false;
        g_runStrategy6 = false;
        g_runStrategy7 = false;
        g_runStrategy8 = false;
        g_runStrategy9 = false;
        g_riskFactorByTier = 2.4;
        if (UseVariableValues)
        {
            g_riskFactorByTier = 3.0;
        }
    }
    else
    {
        if (g_tradeFrequencyMode == 1)
        {
            g_runStrategy4 = true;
            g_runStrategy5 = true;
            g_runStrategy6 = false;
            g_runStrategy7 = false;
            g_runStrategy8 = false;
            g_runStrategy9 = false;
            g_riskFactorByTier = 3.4;
            if (UseVariableValues)
            {
                g_riskFactorByTier = 4.0;
            }
        }
        else
        {
            if (g_tradeFrequencyMode == 2)
            {
                g_runStrategy4 = true;
                g_runStrategy5 = true;
                g_runStrategy6 = true;
                g_runStrategy7 = true;
                g_runStrategy8 = false;
                g_runStrategy9 = false;
                g_riskFactorByTier = 4.1;
                if (UseVariableValues)
                {
                    g_riskFactorByTier = 5.0;
                }
            }
            else
            {
                if (g_tradeFrequencyMode == 3)
                {
                    g_runStrategy4 = true;
                    g_runStrategy5 = true;
                    g_runStrategy6 = true;
                    g_runStrategy7 = true;
                    g_runStrategy8 = true;
                    g_runStrategy9 = false;
                    g_riskFactorByTier = 4.8;
                    if (UseVariableValues)
                    {
                        g_riskFactorByTier = 5.6;
                    }
                }
                else
                {
                    if (g_tradeFrequencyMode == 4)
                    {
                        g_runStrategy4 = true;
                        g_runStrategy5 = true;
                        g_runStrategy6 = true;
                        g_runStrategy7 = true;
                        g_runStrategy8 = true;
                        g_runStrategy9 = true;
                        g_riskFactorByTier = 5.1;
                        if (UseVariableValues)
                        {
                            g_riskFactorByTier = 6.0;
                        }
                    }
                    else
                    {
                        if (g_tradeFrequencyMode == 6)
                        {
                            g_runStrategy1 = RunStrat1;
                            g_runStrategy2 = RunStrat2;
                            g_runStrategy3 = RunStrat3;
                            g_runStrategy4 = RunStrat4;
                            g_runStrategy5 = RunStrat5;
                            g_runStrategy6 = RunStrat6;
                            g_runStrategy7 = RunStrat7;
                            g_runStrategy8 = RunStrat8;
                            g_runStrategy9 = RunStrat9;
                        }
                    }
                }
            }
        }
    }
}

// CheckDailyRolloverAndPropFirmGate —— D1 换日时重置日内回撤基准；执行 PropFirm
// 日内回撤强平；返回 false 表示本 tick 应立即返回（原版内联 return）
bool CheckDailyRolloverAndPropFirmGate()
{
    if (iBars(g_chartSymbol, MT4Period(PERIOD_D1)) != g_lastD1BarsCount)
    {
        g_lastD1BarsCount = iBars(g_chartSymbol, MT4Period(PERIOD_D1));
        g_propfirmDailyDDHit = false;
        g_propfirmDailyPeakEquity = 0.0;
        g_propfirmDailyStartEquity = AccountEquity();
    }
    if (PropFirmMaxDailyDD > 0.0)
    {
        EnforcePropFirmDailyDrawdown();
    }
    if (g_propfirmDailyDDHit || !(g_propfirmDailyDDOn))   return(false);
    return(true);
}

// DetectNewH1Bar —— H1 收盘 K 线变化检测（原 local_4_bool）
bool DetectNewH1Bar()
{
    if (g_lastH1BarTime != iTime(g_chartSymbol, MT4Period(PERIOD_H1), 1))
    {
        g_lastH1BarTime = iTime(g_chartSymbol, MT4Period(PERIOD_H1), 1);
        return(true);
    }
    return(false);
}

// RunStrategySlot —— 单策略槽位：加载策略设置 -> 运行时设置 -> 处理策略。
// 槽位 0 额外检测初始旧版风险手数挂单；H1 新 K 线时刷新该策略历史平仓盈亏统计
// （统计读数沿用原版：使用 g_currentStrategyIndex 而非槽位号）
void RunStrategySlot(const int strategyIndex, const bool newH1Bar)
{
    switch (strategyIndex)
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
    if (strategyIndex == 0)
    {
        if (g_initialLegacyRiskLotPending)
        {
            for (int legacyOrderIdx = MT4OrdersTotal(); legacyOrderIdx >= 0; legacyOrderIdx--)
            {
                if (OrderSelect(legacyOrderIdx, 0, 0) && OrderSymbol() == g_chartSymbol &&
                    OrderMagicNumber() == ST1_MagicNumber + 1)
                {
                    g_initialLegacyRiskLotPending = false;
                    break;
                }
            }
        }
    }
    if (newH1Bar)
    {
        double histClosedPL = 0.0;
        if (!(MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting)))
        {
            double statsClosedPL = 0.0;
            MT4HistoryStats(g_chartSymbol, g_curStrategyMagic, g_closedTradeCount[g_currentStrategyIndex], statsClosedPL);
            histClosedPL = statsClosedPL;
        }
        g_histClosedPLbyStrategy[strategyIndex] = histClosedPL;
        if (g_histClosedPLbyStrategy[strategyIndex] != 0.0 && g_closedTradeCount[strategyIndex] > 0)
        {
            g_avgPLperTrade[strategyIndex] = g_histClosedPLbyStrategy[strategyIndex] / g_closedTradeCount[strategyIndex];
        }
    }
}

// RunAllStrategies —— 品种为黄金类时按原版固定顺序调度策略槽位（1,4,2,3,6,5,9,7,8）；
//                     非黄金品种仅以槽位 0 运行（原版行为）
void RunAllStrategies(const bool newH1Bar)
{
    if ((StringFind(Symbol(), "XAUUSD", 0) >= 0 || StringFind(Symbol(), "xauusd", 0) >= 0 || StringFind(Symbol(), "GOLD", 0) >= 0 || StringFind(Symbol(), "GLD", 0) >= 0 || StringFind(Symbol(), "gold", 0) >= 0 || StringFind(Symbol(), "Gold", 0) >= 0))
    {
        g_chartSymbol = Symbol();
        if (g_runStrategy1)  RunStrategySlot(0, newH1Bar);
        if (g_runStrategy4)  RunStrategySlot(3, newH1Bar);
        if (g_runStrategy2)  RunStrategySlot(1, newH1Bar);
        if (g_runStrategy3)  RunStrategySlot(2, newH1Bar);
        if (g_runStrategy6)  RunStrategySlot(5, newH1Bar);
        if (g_runStrategy5)  RunStrategySlot(4, newH1Bar);
        if (g_runStrategy9)  RunStrategySlot(8, newH1Bar);
        if (g_runStrategy7)  RunStrategySlot(6, newH1Bar);
        if (g_runStrategy8)  RunStrategySlot(7, newH1Bar);
    }
    else
    {
        g_chartSymbol = Symbol();
        ProcessStrategy(0);
    }
}

// UpdatePanelsOnNewM5Bar —— M5 收盘 K 线变化时刷新策略/历史面板
void UpdatePanelsOnNewM5Bar()
{
    if (iTime(Symbol(), PERIOD_M5, 1) != g_lastM5BarTime)
    {
        g_lastM5BarTime = iTime(Symbol(), PERIOD_M5, 1);
        UpdateStrategyPanelRows();
        UpdateHistoryPanel();
    }
}

// FinishTickLotResizeThrottle —— 2-tick 节流的余额快照（驱动挂单手数再平衡）
void FinishTickLotResizeThrottle()
{
    g_lotResizeTickCount++;
    if (g_lotResizeTickCount < 2)
    {
        return;
    }
    g_lastLotResizeBalance = AccountBalance(); // JIT sync: original LastLotResizeBalance snapshots ACCOUNT_BALANCE
    g_lotResizeTickCount = 0;
}

// OnTick —— 主处理循环：各过滤器 -> 逐策略 LoadStrategyNSettings +
//           ProcessStrategy -> 面板更新（语义模块化后，语句顺序与原版一致）
void OnTick()
{
    if (!(DumpBacktestSpeedAllowTick())) return;
    g_live_valid = false;

    UpdateEffectiveBalanceTracking();
    ApplyFakeoutFilterMode();
    UpdateGmtDstDetection();
    RefreshNfpCalendarCache();
    EnforceManualHistoricalDDCompat();
    ApplyTradeFrequencyTiers();
    if (!(CheckDailyRolloverAndPropFirmGate()))   return;

    bool newH1Bar = DetectNewH1Bar();
    RunAllStrategies(newH1Bar);

    UpdateAccountPanel();
    UpdatePanelsOnNewM5Bar();
    FinishTickLotResizeThrottle();
}
//OnTick <<==--------   --------
// OnDeinit —— 释放 9 个 iATR 指标句柄并删除信息面板
void OnDeinit(const int reason)
{
    for (int i = 0; i < 9; i++)
    {
        if (g_atr_handles[i] > 0) IndicatorRelease(g_atr_handles[i]);
        g_atr_handles[i] = 0;
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
void LoadStrategyRuntimeSettings(int strategyIdx)
{
    // -----------------------------------------------------------------
    // Recovered from the original MetaTester64 full-memory dump/JIT.
    // The original creates an iATR handle on every strategy activation,
    // copies 100 values, sets the buffer as series and touches [1].
    // This is a history/indicator-readiness gate; the ATR value itself is
    // not used in the trading arithmetic that follows.
    // -----------------------------------------------------------------
    int atrIndex = strategyIdx;
    if (atrIndex < 0 || atrIndex>8) atrIndex = 0;
    ENUM_TIMEFRAMES atrTimeframe = MT4Period(g_atrTimeframe);
    if (g_atr_handles[atrIndex] <= 0 ||
        g_atr_periods[atrIndex] != g_atrPeriod ||
        g_atr_timeframes[atrIndex] != atrTimeframe)
    {
        if (g_atr_handles[atrIndex] > 0) IndicatorRelease(g_atr_handles[atrIndex]);
        g_atr_handles[atrIndex] = iATR(g_chartSymbol, atrTimeframe, g_atrPeriod);
        g_atr_periods[atrIndex] = g_atrPeriod;
        g_atr_timeframes[atrIndex] = atrTimeframe;
        g_atr_checked_bars[atrIndex] = 0;
        g_atr_cached_values[atrIndex] = 0.0;
        g_atr_ready[atrIndex] = false;
    }
    g_atrHandle = g_atr_handles[atrIndex];
    if (g_atrHandle < 0)
    {
        Print("The creation of iATR has failed: Runtime error =" + IntegerToString(GetLastError()));
        return;
    }
    // ATR is a readiness gate only; its value is never used by the trading
    // arithmetic.  Refresh once per ATR bar and keep retrying until the buffer is
    // ready, instead of issuing several CopyBuffer calls on every market tick.
    datetime atrBarTime = iTime(g_chartSymbol, atrTimeframe, 0);
    if (!(g_atr_ready[atrIndex]) || g_atr_checked_bars[atrIndex] != atrBarTime)
    {
        if (CopyBuffer(g_atrHandle, 0, 0, 2, g_atrBuffer) == 0)
        {
            return;
        }
        ArraySetAsSeries(g_atrBuffer, true);
        // Original JIT contains the bounds check for element [1].
        g_atr_cached_values[atrIndex] = g_atrBuffer[1];
        g_atr_checked_bars[atrIndex] = atrBarTime;
        g_atr_ready[atrIndex] = true;
    }

    // Original JIT first derives the variable-value ratio, then selects
    // either that ratio or 1.0 according to UseVariableValues.  The 1000
    // threshold and the absence of NormalizeDouble() on entry offsets are
    // both visible in the dump (e.g. -170 -> -402.49625 at ratio 2.367625).
    double variableRatio = 1.0;
    if (g_varValueScalePrice >= 1000.0)
    {
        variableRatio = iOpen(g_chartSymbol, MT4Period(PERIOD_D1), 1) / g_varValueScalePrice;
    }
    if (UseVariableValues)
    {
        g_variableRatio = variableRatio;
    }
    else
    {
        g_variableRatio = 1.0;
    }
    if (AdjustLotsizeToVariableValues)
    {
        g_lotRatioInv = 1.0 / g_variableRatio;
    }
    else
    {
        g_lotRatioInv = 1.0;
    }
    if (g_variableRatio == 0.0)
    {
        g_variableRatio = 1.0;
    }


    g_currentStrategyIndex = strategyIdx;

    // The original explicitly checks that a current tick is available.
    // Failure is logged, but execution continues exactly as in the dump.
    MqlTick currentTick;
    if (!(SymbolInfoTick(g_chartSymbol, currentTick)))
    {
        Print("Tick not ok");
    }

    g_symbolPoint = SymbolInfoDouble(g_chartSymbol, 16);
    g_pipSize = g_symbolPoint;
    if ((MarketInfo(g_chartSymbol, MODE_DIGITS) == 3.0 || MarketInfo(g_chartSymbol, MODE_DIGITS) == 5.0))
    {
        g_pipSize = g_symbolPoint * 10.0;
    }
    if (SymbolInfoInteger(g_chartSymbol, 17) == 0x1)
    {
        g_pipSize = g_symbolPoint / 10.0;
    }
    g_symbolDigits = (int)MarketInfo(g_chartSymbol, MODE_DIGITS);
    g_curSpread = MarketInfo(g_chartSymbol, MODE_ASK) - MarketInfo(g_chartSymbol, MODE_BID);
    g_minStopDistPrice = MarketInfo(g_chartSymbol, MODE_STOPLEVEL) * g_symbolPoint;
    g_freezeDistPrice = MarketInfo(g_chartSymbol, MODE_FREEZELEVEL) * g_symbolPoint;

    // Recovered working-value transform from original JIT.  The nine strategy
    // setup functions rewrite every raw field before LoadStrategyRuntimeSettings(), so in-place use
    // is behaviorally safe for fields without an explicit shadow in the rebuild.
    g_MaxSpread_rw = MaxSpread * g_variableRatio;
    g_entryBreakoutPips = g_entryBreakoutPips * g_variableRatio;
    g_buyEntryOffsetPips = g_buyEntryOffsetPips * g_variableRatio;
    g_sellEntryOffsetPips = g_sellEntryOffsetPips * g_variableRatio;
    g_pendingDupTolerancePips = g_pendingDupTolerancePips * g_variableRatio;
    g_stopLossPips = g_stopLossPips * g_variableRatio;
    g_takeProfitPips = g_takeProfitPips * g_variableRatio;
    g_profitTrailDistancePips = g_profitTrailDistancePips * g_variableRatio;
    g_trailActivationPips = g_trailActivationPips * g_variableRatio;
    g_profitTrailCapPips = g_profitTrailCapPips * g_variableRatio;
    g_profitTrailBufferPips = g_profitTrailBufferPips * g_variableRatio;
    // Original keeps raw trailing-TP settings and writes scaled shadows.
    g_tpTrailPips = g_trailTpPips * g_variableRatio;
    g_tpTrailMinGapPips = g_profitTargetPips * g_variableRatio;
    g_beTriggerPips = g_beTriggerPips * g_variableRatio;
    g_beExtraPips = g_beExtraPips * g_variableRatio;

    // These clamps are part of LoadStrategyRuntimeSettings() in the original JIT and therefore
    // must run for every strategy, not only once during OnInit().
    if (g_stopLossPips <= 0.0)
    {
        g_stopLossPips = 1.0;
    }
    if (g_takeProfitPips <= 0.0)
    {
        g_takeProfitPips = 1.0;
    }
    if (g_beExtraPips > g_beTriggerPips)
    {
        g_beExtraPips = g_beTriggerPips + 0.1;
    }
    if (g_maxSpreadPts > g_MaxSpread_rw)
    {
        g_maxSpreadPts = g_MaxSpread_rw;
    }
    if (g_pendingMinGapPips < g_freezeDistPrice / g_pipSize)
    {
        g_pendingMinGapPips = (int)(g_freezeDistPrice / g_pipSize);
    }
    if (g_profitTrailDistancePips != 0.0 && g_profitTrailDistancePips < g_freezeDistPrice / g_pipSize)
    {
        g_profitTrailDistancePips = g_freezeDistPrice / g_pipSize;
    }
    if (g_profitTrailDistancePips != 0.0 && g_profitTrailDistancePips < g_minStopDistPrice / g_pipSize)
    {
        g_profitTrailDistancePips = g_minStopDistPrice / g_pipSize;
    }
    if (g_timeTrailDelayMin > 0.0 && g_timeTrailDistancePips < g_freezeDistPrice / g_pipSize)
    {
        g_timeTrailDistancePips = g_freezeDistPrice / g_pipSize;
    }
    if (g_timeTrailDelayMin > 0.0 && g_timeTrailDistancePips < g_minStopDistPrice / g_pipSize)
    {
        g_timeTrailDistancePips = g_minStopDistPrice / g_pipSize;
    }
    if (g_stopLossPips < g_minStopDistPrice * 2.0 / g_pipSize)
    {
        g_stopLossPips = g_minStopDistPrice * 2.0 / g_pipSize;
    }
    if (g_takeProfitPips < g_minStopDistPrice * 2.0 / g_pipSize)
    {
        g_takeProfitPips = g_minStopDistPrice * 2.0 / g_pipSize;
    }
    if (g_entryBreakoutPips < g_minStopDistPrice * 2.0 / g_pipSize)
    {
        g_entryBreakoutPips = g_minStopDistPrice * 2.0 / g_pipSize;
    }
    if (g_fractalRightBars < 1)
    {
        g_fractalRightBars = 1;
    }
    if (g_fractalLeftBars < 1)
    {
        g_fractalLeftBars = 1;
    }
    if (g_entryBreakoutPips < 0.1)
    {
        g_entryBreakoutPips = 0.1;
    }

    g_pendingExpirySecs = g_pendingExpiryHours * 60 * 60;
    if (g_pendingExpiryHours > 0)
    {
        g_pendingOrderExpiry = TimeCurrent() + g_pendingExpirySecs;
    }
    else
    {
        g_pendingOrderExpiry = 0;
    }
    if (Virtual_expiration)
    {
        g_pendingOrderExpiry = 0;
    }
}
//LoadStrategyRuntimeSettings <<==--------   --------
// ============================================================================
// [§9] 策略核心处理
// ============================================================================

// ProcessStrategy —— 单个策略的主处理函数（过滤器、挂单/持仓状态机），
//                    strategyIdx 为策略索引（0..8）
int ProcessStrategy(int strategyIdx)
{
    bool      managementActionPerformed;
    datetime  nfpReleaseTime;
    int       nfpGmtOffsetMin;
    string    nfpDateString;
    datetime  nfpFallbackReleaseTime;
    int       randomEntryBars;
    int       entrySlotIdx;
    //----- -----
    int        vpoSlotClearIdx;
    int        vpoFieldClearIdx;
    int        vpoStoreIdx;
    int        weekendStoreScanIdx;
    int        buyStopDelMode;
    int        buyStopDelScanIdx;
    int        manualBuyStopDelScanIdx;
    int        sellStopDelMode;
    int        sellStopDelScanIdx;
    int        manualSellStopDelScanIdx;
    int        buyStopDelMode2;
    int        manualBuyStopDelScanIdx2;
    int        sellStopDelMode2;
    int        manualSellStopDelScanIdx2;
    int        nfpBuyStopDelMode;
    int        nfpBuyStopDelScanIdx;
    int        nfpManualBuyStopDelScanIdx;
    int        nfpSellStopDelMode;
    int        nfpSellStopDelScanIdx;
    int        nfpManualSellStopDelScanIdx;
    int        nfpBuyStopDelMode2;
    int        nfpManualBuyStopDelScanIdx2;
    int        nfpSellStopDelMode2;
    int        nfpManualSellStopDelScanIdx2;
    int        fbBuyStopDelMode;
    int        fbBuyStopDelScanIdx;
    int        fbManualBuyStopDelScanIdx;
    int        fbSellStopDelMode;
    int        fbSellStopDelScanIdx;
    int        fbManualSellStopDelScanIdx;
    int        fbBuyStopDelMode2;
    int        fbManualBuyStopDelScanIdx2;
    int        fbSellStopDelMode2;
    int        fbManualSellStopDelScanIdx2;
    int        fridayScanIdx;
    int        fridayOrderMagic;
    int        fridayMagicCmp1;
    int        fridayMagicCmp2;
    int        fridayMagicCmp3;
    int        fridayMagicCmp4;
    int        fridayMagicCmp5;
    int        fridayMagicCmp6;
    int        fridayMagicCmp7;
    int        fridayMagicCmp8;
    int        fridayMagicCmp9;
    int        fridayMagicCmp10;
    int        fridayMagicCmp11;
    int        fridayMagicCmp12;
    int        fridayMagicCmp13;
    int        fridayMagicCmp14;
    int        fridayMagicCmp15;
    int        buyStopCount;
    int        buyStopCountScanIdx;
    double     highestBuyStopPrice;
    long       highestBuyStopTicket;
    int        highestBuyStopScanIdx;
    long       clearedBuyStopTicket;
    int        clearedBuyStopSlotIdx;
    int        sellStopCount;
    int        sellStopCountScanIdx;
    double     lowestSellStopPrice;
    long       lowestSellStopTicket;
    int        lowestSellStopScanIdx;
    long       clearedSellStopTicket;
    int        clearedSellStopSlotIdx;
    int        openBuyCount;
    int        openBuyCountScanIdx;
    int        openSellCount;
    int        openSellCountScanIdx;
    bool       cacheEntryLive;
    int        virtSlCacheScanIdx;
    int        virtSlCacheTicketScanIdx;
    bool       soCacheEntryLive;
    int        soCacheHourlyScanIdx;
    long       soCacheStoredTicket;
    int        soCacheTicketScanIdx;
    long       soCacheScanTicket;

    g_currentStrategyIndex = strategyIdx;
    managementActionPerformed = false;

    if (g_entryBreakoutPct > 0.0)
    {
        g_entryBreakoutPips = g_entryBreakoutPct / 100.0 * MarketInfo(g_chartSymbol, MODE_ASK) * 10.0;
    }
    bool tradeAllowedForManagement = (MarketInfo(g_chartSymbol, MODE_TRADEALLOWED) != 0.0);
    if (g_entryTfMinutes == 0)
    {
        if (tradeAllowedForManagement)
        {
            if (ManageBuyPositions())
            {
                managementActionPerformed = true;
            }
            if (ManageSellPositions())
            {
                managementActionPerformed = true;
            }
            if (managementActionPerformed)
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
        if (tradeAllowedForManagement &&
            g_lastEntryBarsCount[g_currentStrategyIndex] != iBars(g_chartSymbol, MT4Period(g_entryTfMinutes)))
        {
            g_lastEntryBarsCount[g_currentStrategyIndex] = iBars(g_chartSymbol, MT4Period(g_entryTfMinutes));
            if (ManageBuyPositions())
            {
                managementActionPerformed = true;
            }
            if (ManageSellPositions())
            {
                managementActionPerformed = true;
            }
            if (managementActionPerformed)
            {
                return(0);
            }
        }
    }
    RefreshPendingOrderLotSizes(false);
    if (MarketInfo(g_chartSymbol, MODE_TRADEALLOWED) == 0.0)
    {
        return(0);
    }
    if (g_useTradingHours)
    {
        if (IsTradingScheduleOpen() && g_marketClosedFlag)
        {
            if (g_closePendingsOnWeekend)
            {
                RestoreStoredPendingOrders();
            }
            g_marketClosedFlag = false;
        }
        if (!(IsTradingScheduleOpen()) && !(g_marketClosedFlag))
        {
            Print("Weekend starting! closing trades..");
            if (g_closePendingsOnWeekend)
            {
                for (vpoSlotClearIdx = 0; vpoSlotClearIdx < g_virtualOrderSlots; vpoSlotClearIdx = vpoSlotClearIdx + 1)
                {
                    for (vpoFieldClearIdx = 0; vpoFieldClearIdx < 2; vpoFieldClearIdx = vpoFieldClearIdx + 1)
                    {
                        g_virtualPendingOrders[vpoSlotClearIdx][vpoFieldClearIdx] = 0.0;
                    }
                }
                vpoStoreIdx = 0;
                for (weekendStoreScanIdx = MT4OrdersTotal(); weekendStoreScanIdx >= 0; weekendStoreScanIdx = weekendStoreScanIdx - 1)
                {
                    if (OrderSelect(weekendStoreScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol)   continue;

                    if ((OrderType() != 4 && OrderType() != 5))   continue;
                    Print("Storing pending order nr " + string(OrderTicket()));
                    g_virtualPendingOrders[vpoStoreIdx][1] = OrderType();
                    g_virtualPendingOrders[vpoStoreIdx][0] = OrderOpenPrice();
                    g_virtualPendingOrders[vpoStoreIdx][2] = OrderLots();
                    vpoStoreIdx = vpoStoreIdx + 1;

                }
            }
            buyStopDelMode = 1;
            for (buyStopDelScanIdx = MT4OrdersTotal(); buyStopDelScanIdx >= 0; buyStopDelScanIdx = buyStopDelScanIdx - 1)
            {
                if (OrderSelect(buyStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                OrderDelete(OrderTicket(), 0xFFFFFFFF);

            }
            if (buyStopDelMode == 2)
            {
                for (manualBuyStopDelScanIdx = MT4OrdersTotal(); manualBuyStopDelScanIdx >= 0; manualBuyStopDelScanIdx = manualBuyStopDelScanIdx - 1)
                {
                    if (OrderSelect(manualBuyStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                    OrderDelete(OrderTicket(), 0xFFFFFFFF);

                }
            }
            sellStopDelMode = 1;
            for (sellStopDelScanIdx = MT4OrdersTotal(); sellStopDelScanIdx >= 0; sellStopDelScanIdx = sellStopDelScanIdx - 1)
            {
                if (OrderSelect(sellStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                OrderDelete(OrderTicket(), 0xFFFFFFFF);

            }
            if (sellStopDelMode == 2)
            {
                for (manualSellStopDelScanIdx = MT4OrdersTotal(); manualSellStopDelScanIdx >= 0; manualSellStopDelScanIdx = manualSellStopDelScanIdx - 1)
                {
                    if (OrderSelect(manualSellStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                    OrderDelete(OrderTicket(), 0xFFFFFFFF);

                }
            }
            buyStopDelMode2 = 2;
            if (1 == 0) //condition_not_met
            {
                do
                {
                    if (OrderSelect(1, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                    OrderDelete(OrderTicket(), 0xFFFFFFFF);

                } while (-1 >= 0);

            }
            if (buyStopDelMode2 == 2)
            {
                for (manualBuyStopDelScanIdx2 = MT4OrdersTotal(); manualBuyStopDelScanIdx2 >= 0; manualBuyStopDelScanIdx2 = manualBuyStopDelScanIdx2 - 1)
                {
                    if (OrderSelect(manualBuyStopDelScanIdx2, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                    OrderDelete(OrderTicket(), 0xFFFFFFFF);

                }
            }
            sellStopDelMode2 = 2;
            if (1 == 0) //condition_not_met
            {
                do
                {
                    if (OrderSelect(1, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                    OrderDelete(OrderTicket(), 0xFFFFFFFF);

                } while (-1 >= 0);

            }
            if (sellStopDelMode2 == 2)
            {
                for (manualSellStopDelScanIdx2 = MT4OrdersTotal(); manualSellStopDelScanIdx2 >= 0; manualSellStopDelScanIdx2 = manualSellStopDelScanIdx2 - 1)
                {
                    if (OrderSelect(manualSellStopDelScanIdx2, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                    OrderDelete(OrderTicket(), 0xFFFFFFFF);

                }
            }
            g_marketClosedFlag = true;
            return(0);
        }
    }
    if (EnableNFP_Filter)
    {
        bool nfpLiveCalendar = (UseMQL5Calendar && MQLInfoInteger(MQL_TESTER) != 1 && g_nextNFPCalendar != 0);
        // Exact original fallback rule: if live Calendar is disabled/unavailable (timestamp=0),
        // continue into the hardcoded table; after 2026 use the first-Friday fallback.
        if (nfpLiveCalendar || Year() <= 2026)
        {
            nfpReleaseTime = 0;
            nfpGmtOffsetMin = 0;
            datetime nfpCompareNow = TimeCurrent();
            if (nfpLiveCalendar)
            {
                // Calendar timestamps are already in trade-server time. No GMT conversion here.
                nfpReleaseTime = g_nextNFPCalendar;
            }
            else
            {
                nfpReleaseTime = MT4HardcodedNFPForCurrentMonth();
                // Hardcoded table is GMT-based: NFP is 13:30 GMT in US winter, 12:30 in DST.
                nfpGmtOffsetMin = 60;
                if (IsAmericanDst())   nfpGmtOffsetMin = 0;
                nfpCompareNow = g_nfpAdjustedNow;
            }
            if (nfpCompareNow >= nfpReleaseTime - NFP_MinutesBefore * 60 + nfpGmtOffsetMin * 60 && nfpCompareNow <= nfpReleaseTime + NFP_MinutesAfter * 60 + nfpGmtOffsetMin * 60)
            {
                if (NFP_ClosePendingOrders)
                {
                    nfpBuyStopDelMode = 1;
                    for (nfpBuyStopDelScanIdx = MT4OrdersTotal(); nfpBuyStopDelScanIdx >= 0; nfpBuyStopDelScanIdx = nfpBuyStopDelScanIdx - 1)
                    {
                        if (OrderSelect(nfpBuyStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice))   continue;
                        OrderDelete(OrderTicket(), 0xFFFFFFFF);

                    }
                    if (nfpBuyStopDelMode == 2)
                    {
                        for (nfpManualBuyStopDelScanIdx = MT4OrdersTotal(); nfpManualBuyStopDelScanIdx >= 0; nfpManualBuyStopDelScanIdx = nfpManualBuyStopDelScanIdx - 1)
                        {
                            if (OrderSelect(nfpManualBuyStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice))   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        }
                    }
                    nfpSellStopDelMode = 1;
                    for (nfpSellStopDelScanIdx = MT4OrdersTotal(); nfpSellStopDelScanIdx >= 0; nfpSellStopDelScanIdx = nfpSellStopDelScanIdx - 1)
                    {
                        if (OrderSelect(nfpSellStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol, MODE_BID) > OrderOpenPrice() + g_freezeDistPrice))   continue;
                        OrderDelete(OrderTicket(), 0xFFFFFFFF);

                    }
                    if (nfpSellStopDelMode == 2)
                    {
                        for (nfpManualSellStopDelScanIdx = MT4OrdersTotal(); nfpManualSellStopDelScanIdx >= 0; nfpManualSellStopDelScanIdx = nfpManualSellStopDelScanIdx - 1)
                        {
                            if (OrderSelect(nfpManualSellStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol, MODE_BID) > OrderOpenPrice() + g_freezeDistPrice))   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        }
                    }
                    nfpBuyStopDelMode2 = 2;
                    if (1 == 0) //condition_not_met
                    {
                        do
                        {
                            if (OrderSelect(1, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        } while (-1 >= 0);

                    }
                    if (nfpBuyStopDelMode2 == 2)
                    {
                        for (nfpManualBuyStopDelScanIdx2 = MT4OrdersTotal(); nfpManualBuyStopDelScanIdx2 >= 0; nfpManualBuyStopDelScanIdx2 = nfpManualBuyStopDelScanIdx2 - 1)
                        {
                            if (OrderSelect(nfpManualBuyStopDelScanIdx2, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice))   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        }
                    }
                    nfpSellStopDelMode2 = 2;
                    if (1 == 0) //condition_not_met
                    {
                        do
                        {
                            if (OrderSelect(1, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        } while (-1 >= 0);

                    }
                    if (nfpSellStopDelMode2 == 2)
                    {
                        for (nfpManualSellStopDelScanIdx2 = MT4OrdersTotal(); nfpManualSellStopDelScanIdx2 >= 0; nfpManualSellStopDelScanIdx2 = nfpManualSellStopDelScanIdx2 - 1)
                        {
                            if (OrderSelect(nfpManualSellStopDelScanIdx2, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol, MODE_BID) > OrderOpenPrice() + g_freezeDistPrice))   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        }
                    }
                }
                if (NFP_CloseOpenTrades)
                {
                    CloseNfpOpenTradesInOriginalOrder();
                }
                if (!(g_nfpWindowActive))
                {
                    Print("NFP!! deleting trades!!");
                }
                g_nfpWindowActive = true;
            }
            else
            {
                g_nfpWindowActive = false;
            }
        }
        else
        {
            if (Day() <= 7 && DayOfWeek() == 5)
            {
                nfpDateString = IntegerToString(Year(), 0, 32) + IntegerToString(Month(), 0, 32) + IntegerToString(Day(), 0, 32) + " " + IntegerToString(0x4CE, 0, 32);
                nfpFallbackReleaseTime = StringToTime(nfpDateString);
                if (g_nfpAdjustedNow >= nfpFallbackReleaseTime - NFP_MinutesBefore * 60 && g_nfpAdjustedNow <= nfpFallbackReleaseTime + NFP_MinutesAfter * 60)
                {
                    if (NFP_ClosePendingOrders)
                    {
                        fbBuyStopDelMode = 1;
                        for (fbBuyStopDelScanIdx = MT4OrdersTotal(); fbBuyStopDelScanIdx >= 0; fbBuyStopDelScanIdx = fbBuyStopDelScanIdx - 1)
                        {
                            if (OrderSelect(fbBuyStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice))   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        }
                        if (fbBuyStopDelMode == 2)
                        {
                            for (fbManualBuyStopDelScanIdx = MT4OrdersTotal(); fbManualBuyStopDelScanIdx >= 0; fbManualBuyStopDelScanIdx = fbManualBuyStopDelScanIdx - 1)
                            {
                                if (OrderSelect(fbManualBuyStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice))   continue;
                                OrderDelete(OrderTicket(), 0xFFFFFFFF);

                            }
                        }
                        fbSellStopDelMode = 1;
                        for (fbSellStopDelScanIdx = MT4OrdersTotal(); fbSellStopDelScanIdx >= 0; fbSellStopDelScanIdx = fbSellStopDelScanIdx - 1)
                        {
                            if (OrderSelect(fbSellStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol, MODE_BID) > OrderOpenPrice() + g_freezeDistPrice))   continue;
                            OrderDelete(OrderTicket(), 0xFFFFFFFF);

                        }
                        if (fbSellStopDelMode == 2)
                        {
                            for (fbManualSellStopDelScanIdx = MT4OrdersTotal(); fbManualSellStopDelScanIdx >= 0; fbManualSellStopDelScanIdx = fbManualSellStopDelScanIdx - 1)
                            {
                                if (OrderSelect(fbManualSellStopDelScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol, MODE_BID) > OrderOpenPrice() + g_freezeDistPrice))   continue;
                                OrderDelete(OrderTicket(), 0xFFFFFFFF);

                            }
                        }
                        fbBuyStopDelMode2 = 2;
                        if (1 == 0) //condition_not_met
                        {
                            do
                            {
                                if (OrderSelect(1, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                                OrderDelete(OrderTicket(), 0xFFFFFFFF);

                            } while (-1 >= 0);

                        }
                        if (fbBuyStopDelMode2 == 2)
                        {
                            for (fbManualBuyStopDelScanIdx2 = MT4OrdersTotal(); fbManualBuyStopDelScanIdx2 >= 0; fbManualBuyStopDelScanIdx2 = fbManualBuyStopDelScanIdx2 - 1)
                            {
                                if (OrderSelect(fbManualBuyStopDelScanIdx2, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice))   continue;
                                OrderDelete(OrderTicket(), 0xFFFFFFFF);

                            }
                        }
                        fbSellStopDelMode2 = 2;
                        if (1 == 0) //condition_not_met
                        {
                            do
                            {
                                if (OrderSelect(1, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                                OrderDelete(OrderTicket(), 0xFFFFFFFF);

                            } while (-1 >= 0);

                        }
                        if (fbSellStopDelMode2 == 2)
                        {
                            for (fbManualSellStopDelScanIdx2 = MT4OrdersTotal(); fbManualSellStopDelScanIdx2 >= 0; fbManualSellStopDelScanIdx2 = fbManualSellStopDelScanIdx2 - 1)
                            {
                                if (OrderSelect(fbManualSellStopDelScanIdx2, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MarketInfo(g_chartSymbol, MODE_BID) > OrderOpenPrice() + g_freezeDistPrice))   continue;
                                OrderDelete(OrderTicket(), 0xFFFFFFFF);

                            }
                        }
                    }
                    if (NFP_CloseOpenTrades)
                    {
                        CloseNfpOpenTradesInOriginalOrder();
                    }
                    if (!(g_nfpWindowActive))
                    {
                        Print("NFP!! deleting trades!!");
                    }
                    g_nfpWindowActive = true;
                }
                else
                {
                    g_nfpWindowActive = false;
                }
            }
        }
    }
    if (g_nfpWindowActive)
    {
        return(0);
    }
    if (g_useFridayStop)
    {
        if (DayOfWeek() == 5 && Hour() >= FridayStopHour && !(g_fridayStopDone))
        {
            // The original MT4 trade pool visits live positions before pending orders
            // during the reverse Friday-cleanup pass.  The MQL5 compatibility cache
            // stores positions before orders, so its reverse pass would otherwise
            // cancel pending orders first.  Close managed positions explicitly in
            // newest-ticket-first order, then let the legacy pass delete pendings.
            if (FridayCloseOpen)
            {
                long friday_position_tickets[];
                int friday_position_count = 0;
                int friday_live_total = MT4OrdersTotal();
                for (int friday_scan = 0; friday_scan < friday_live_total; friday_scan++)
                {
                    if (OrderSelect(friday_scan, SELECT_BY_POS, MODE_TRADES) != true ||
                        OrderSymbol() != g_chartSymbol ||
                        (OrderType() != OP_BUY && OrderType() != OP_SELL) ||
                        !IsNfpManagedMagic(OrderMagicNumber()))
                        continue;
                    ArrayResize(friday_position_tickets, friday_position_count + 1);
                    friday_position_tickets[friday_position_count++] = OrderTicket();
                }
                ArraySort(friday_position_tickets);
                for (int friday_close = friday_position_count - 1; friday_close >= 0; friday_close--)
                {
                    if (OrderSelect(friday_position_tickets[friday_close], SELECT_BY_TICKET, MODE_TRADES) != true)
                        continue;
                    int friday_type = OrderType();
                    double friday_price = (friday_type == OP_BUY)
                        ? MarketInfo(g_chartSymbol, MODE_BID)
                        : MarketInfo(g_chartSymbol, MODE_ASK);
                    OrderClose(OrderTicket(), OrderLots(), friday_price, (int)g_slippagePts, Red);
                }
            }
            for (fridayScanIdx = MT4OrdersTotal(); fridayScanIdx >= 0; fridayScanIdx = fridayScanIdx - 1)
            {
                if (OrderSelect(fridayScanIdx, 0, 0) != true || OrderSymbol() != g_chartSymbol)   continue;
                fridayOrderMagic = OrderMagicNumber();
                fridayMagicCmp1 = ST1_MagicNumber + 1;
                if (fridayOrderMagic != fridayMagicCmp1)
                {
                    fridayMagicCmp1 = OrderMagicNumber();
                    fridayMagicCmp2 = ST1_MagicNumber + 2;
                    if (fridayMagicCmp1 != fridayMagicCmp2)
                    {
                        fridayMagicCmp2 = OrderMagicNumber();
                        fridayMagicCmp3 = ST1_MagicNumber + 3;
                        if (fridayMagicCmp2 != fridayMagicCmp3)
                        {
                            fridayMagicCmp3 = OrderMagicNumber();
                            fridayMagicCmp4 = ST1_MagicNumber + 4;
                            if (fridayMagicCmp3 != fridayMagicCmp4)
                            {
                                fridayMagicCmp4 = OrderMagicNumber();
                                fridayMagicCmp5 = ST1_MagicNumber + 5;
                                if (fridayMagicCmp4 != fridayMagicCmp5)
                                {
                                    fridayMagicCmp5 = OrderMagicNumber();
                                    fridayMagicCmp6 = ST1_MagicNumber + 6;
                                    if (fridayMagicCmp5 != fridayMagicCmp6)
                                    {
                                        fridayMagicCmp6 = OrderMagicNumber();
                                        fridayMagicCmp7 = ST1_MagicNumber + 7;
                                        if (fridayMagicCmp6 != fridayMagicCmp7)
                                        {
                                            fridayMagicCmp7 = OrderMagicNumber();
                                            fridayMagicCmp8 = ST1_MagicNumber + 8;
                                            if (fridayMagicCmp7 != fridayMagicCmp8)
                                            {
                                                fridayMagicCmp8 = OrderMagicNumber();
                                                fridayMagicCmp9 = ST1_MagicNumber + 9;
                                                if (fridayMagicCmp8 != fridayMagicCmp9)
                                                {
                                                    fridayMagicCmp9 = OrderMagicNumber();
                                                    fridayMagicCmp10 = ST1_MagicNumber + 10;
                                                    if (fridayMagicCmp9 != fridayMagicCmp10)
                                                    {
                                                        fridayMagicCmp10 = OrderMagicNumber();
                                                        fridayMagicCmp11 = ST1_MagicNumber + 11;
                                                        if (fridayMagicCmp10 != fridayMagicCmp11)
                                                        {
                                                            fridayMagicCmp11 = OrderMagicNumber();
                                                            fridayMagicCmp12 = ST1_MagicNumber + 12;
                                                            if (fridayMagicCmp11 != fridayMagicCmp12)
                                                            {
                                                                fridayMagicCmp12 = OrderMagicNumber();
                                                                fridayMagicCmp13 = ST1_MagicNumber + 13;
                                                                if (fridayMagicCmp12 != fridayMagicCmp13)
                                                                {
                                                                    fridayMagicCmp13 = OrderMagicNumber();
                                                                    fridayMagicCmp14 = ST1_MagicNumber + 14;
                                                                    if (fridayMagicCmp13 != fridayMagicCmp14)
                                                                    {
                                                                        fridayMagicCmp14 = OrderMagicNumber();
                                                                        fridayMagicCmp15 = ST1_MagicNumber + 15;
                                                                        if (fridayMagicCmp14 != fridayMagicCmp15)   continue;
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
                if ((OrderType() != 4 && OrderType() != 5) || !(FridayClosePending))   continue;
                OrderDelete(OrderTicket(), Red);

            }
            Print("Weekend starting! closing trades..");
            g_fridayStopDone = true;
            return(0);
        }
        if (DayOfWeek() != 5 && g_fridayStopDone == true)
        {
            g_fridayStopDone = false;
            if (g_restorePendingsAfterFriday)
            {
                RestoreStoredPendingOrders();
                return(0);
            }
        }
    }
    g_curSpread = MarketInfo(g_chartSymbol, MODE_ASK) - MarketInfo(g_chartSymbol, MODE_BID);
    if (g_managePendingsBySpread)
    {
        if (g_curSpread > g_MaxSpread_rw * g_pipSize)
        {
            RemovePendingOrdersDuringHighSpread();
            return(0);
        }
        if (g_curSpread <= g_maxSpreadPts * g_pipSize && (!(g_useFridayStop) || DayOfWeek() != 5 || Hour() < FridayStopHour) && (!(g_useTradingHours) || IsTradingScheduleOpen()))
        {
            RestoreStoredPendingOrders();
        }
    }
    if (g_orderMgmtMode == 1)
    {
        buyStopCount = 0;
        for (buyStopCountScanIdx = MT4OrdersTotal(); buyStopCountScanIdx >= 0; buyStopCountScanIdx = buyStopCountScanIdx - 1)
        {
            if (OrderSelect(buyStopCountScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
            buyStopCount = buyStopCount + 1;

        }
        if (buyStopCount > g_maxPendingOrders)
        {
            highestBuyStopPrice = 0.0;
            highestBuyStopTicket = 0;
            for (highestBuyStopScanIdx = MT4OrdersTotal(); highestBuyStopScanIdx >= 0; highestBuyStopScanIdx = highestBuyStopScanIdx - 1)
            {
                if (OrderSelect(highestBuyStopScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(OrderOpenPrice() > highestBuyStopPrice))   continue;
                highestBuyStopTicket = OrderTicket();
                highestBuyStopPrice = OrderOpenPrice();

            }
            if (highestBuyStopTicket != 0)
            {
                OrderDelete(highestBuyStopTicket, Green);
                clearedBuyStopTicket = highestBuyStopTicket;
                for (clearedBuyStopSlotIdx = 0; clearedBuyStopSlotIdx < 100; clearedBuyStopSlotIdx = clearedBuyStopSlotIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[clearedBuyStopSlotIdx][0] == clearedBuyStopTicket))   continue;
                    g_stopOrderTicketPrice[clearedBuyStopSlotIdx][0] = 0.0;
                    g_stopOrderTicketPrice[clearedBuyStopSlotIdx][1] = 0.0;
                    break;

                }
                Print("Max number of pending buy orders reached... deleting highest buystop order!");
            }
        }
        sellStopCount = 0;
        for (sellStopCountScanIdx = MT4OrdersTotal(); sellStopCountScanIdx >= 0; sellStopCountScanIdx = sellStopCountScanIdx - 1)
        {
            if (OrderSelect(sellStopCountScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
            sellStopCount = sellStopCount + 1;

        }
        if (sellStopCount > g_maxPendingOrders)
        {
            lowestSellStopPrice = 9999.0;
            lowestSellStopTicket = 0;
            for (lowestSellStopScanIdx = MT4OrdersTotal(); lowestSellStopScanIdx >= 0; lowestSellStopScanIdx = lowestSellStopScanIdx - 1)
            {
                if (OrderSelect(lowestSellStopScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(OrderOpenPrice() < lowestSellStopPrice))   continue;
                lowestSellStopTicket = OrderTicket();
                lowestSellStopPrice = OrderOpenPrice();

            }
            if (lowestSellStopTicket != 0)
            {
                OrderDelete(lowestSellStopTicket, Green);
                clearedSellStopTicket = lowestSellStopTicket;
                for (clearedSellStopSlotIdx = 0; clearedSellStopSlotIdx < 100; clearedSellStopSlotIdx = clearedSellStopSlotIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[clearedSellStopSlotIdx][0] == clearedSellStopTicket))   continue;
                    g_stopOrderTicketPrice[clearedSellStopSlotIdx][0] = 0.0;
                    g_stopOrderTicketPrice[clearedSellStopSlotIdx][1] = 0.0;
                    break;

                }
                Print("Max number of pending sell orders reached... deleting lowest sellstop order!");
            }
        }
    }
    if (!(g_fridayStopDone) && g_orderMgmtMode == 1 && !(g_marketClosedFlag))
    {
        if ((g_lastSignalBarsCount[g_currentStrategyIndex] != iBars(g_chartSymbol, MT4Period(g_signalTfPeriod)) || g_signalTfPeriod == 0))
        {
            g_lastSignalBarsCount[g_currentStrategyIndex] = iBars(g_chartSymbol, MT4Period(g_signalTfPeriod));
            if (g_hlFractalRightBars > 0 && g_hlFractalLeftBars >= 0)
            {
                g_sellTrailStopLevel[g_currentStrategyIndex] = g_hlOffsetPips * g_pipSize + (MT4FastFractalHigh(g_hlFractalTfMinutes, g_hlFractalRightBars, g_hlFractalLeftBars) + g_curSpread);
                g_buyTrailStopLevel[g_currentStrategyIndex] = MT4FastFractalLow(g_hlFractalTfMinutes, g_hlFractalRightBars, g_hlFractalLeftBars) - g_hlOffsetPips * g_pipSize;
            }
            if (g_randomEntryMaxBars > 0)
            {
                randomEntryBars = MathRand() * g_randomEntryMaxBars / 32768 + 1;
                g_randomEntryOffsetPips = randomEntryBars;
            }
            if (g_profitCloseMode != 1)
            {
                openBuyCount = 0;
                for (openBuyCountScanIdx = MT4OrdersTotal(); openBuyCountScanIdx >= 0; openBuyCountScanIdx = openBuyCountScanIdx - 1)
                {
                    if (OrderSelect(openBuyCountScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 0)   continue;
                    openBuyCount = openBuyCount + 1;

                }
                if (openBuyCount == 0)
                {
                    openSellCount = 0;
                    for (openSellCountScanIdx = MT4OrdersTotal(); openSellCountScanIdx >= 0; openSellCountScanIdx = openSellCountScanIdx - 1)
                    {
                        if (OrderSelect(openSellCountScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 1)   continue;
                        openSellCount = openSellCount + 1;

                    }
                    if (openSellCount == 0)
                    {
                        cacheEntryLive = false;
                        for (virtSlCacheScanIdx = 0; virtSlCacheScanIdx < g_virtSLCacheSize; virtSlCacheScanIdx = virtSlCacheScanIdx + 1)
                        {
                            if (!(g_virtSLCache[virtSlCacheScanIdx][0] > 0.0))   continue;
                            cacheEntryLive = false;
                            for (virtSlCacheTicketScanIdx = MT4OrdersTotal(); virtSlCacheTicketScanIdx >= 0; virtSlCacheTicketScanIdx = virtSlCacheTicketScanIdx - 1)
                            {
                                if (OrderSelect(virtSlCacheTicketScanIdx, 0, 0) != true)   continue;

                                if ((OrderType() != 0 && OrderType() != 1) || !(OrderTicket() == g_virtSLCache[virtSlCacheScanIdx][0]))   continue;
                                cacheEntryLive = true;

                            }
                            if (cacheEntryLive)   continue;
                            g_virtSLCache[virtSlCacheScanIdx][0] = 0.0;
                            g_virtSLCache[virtSlCacheScanIdx][1] = 0.0;

                        }
                    }
                }
            }
            for (entrySlotIdx = 0; entrySlotIdx < g_maxPendingOrders; entrySlotIdx++)
            {
                ProcessStrategyEntries();
            }
        }
        UpdateHistoryPanel();
        if (g_lastHour != Hour())
        {
            g_lastHour = Hour();
            soCacheEntryLive = false;
            for (soCacheHourlyScanIdx = 0; soCacheHourlyScanIdx < 100; soCacheHourlyScanIdx = soCacheHourlyScanIdx + 1)
            {
                soCacheStoredTicket = (long)g_stopOrderTicketPrice[soCacheHourlyScanIdx][0];
                soCacheEntryLive = false;
                for (soCacheTicketScanIdx = MT4OrdersTotal(); soCacheTicketScanIdx >= 0; soCacheTicketScanIdx = soCacheTicketScanIdx - 1)
                {
                    if (!(OrderSelect(soCacheTicketScanIdx, 0, 0)))   continue;
                    soCacheScanTicket = OrderTicket();
                    if (soCacheStoredTicket != soCacheScanTicket)   continue;
                    soCacheEntryLive = true;

                }
                if (soCacheEntryLive)   continue;
                g_stopOrderTicketPrice[soCacheHourlyScanIdx][0] = 0.0;
                g_stopOrderTicketPrice[soCacheHourlyScanIdx][1] = 0.0;

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
    int       slotIdx;
    //----- -----
    double     buyStoredPrice;
    long       buyTicket;
    int        buySlotScanIdx;
    double     buyRetryStoredPrice;
    long       buyRetryTicket;
    int        buyRetrySlotScanIdx;
    double     sellStoredPrice;
    long       sellTicket;
    int        sellSlotScanIdx;
    double     sellRetryStoredPrice;
    long       sellRetryTicket;
    int        sellRetrySlotScanIdx;
    int        clearSlotIdx;

    for (slotIdx = 0; slotIdx < g_virtualOrderSlots; slotIdx++)
    {
        if (!(g_virtualPendingOrders[slotIdx][0] > 0.0))   continue;

        if (g_virtualPendingOrders[slotIdx][1] == 4.0 && MarketInfo(g_chartSymbol, MODE_ASK) < g_virtualPendingOrders[slotIdx][0] - g_minStopDistPrice)
        {
            Print("Restoring pending buy-order");
            g_lastOrderResult = OrderSend(g_chartSymbol, 4, g_virtualPendingOrders[slotIdx][2], g_virtualPendingOrders[slotIdx][0], int(g_slippagePts * g_pipSize), g_virtualPendingOrders[slotIdx][0] - (g_stopLossPips + g_stopExtraPips) * g_pipSize, g_takeProfitPips * g_pipSize + g_virtualPendingOrders[slotIdx][0], g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry + 0x2A300, Green);
            buyStoredPrice = g_virtualPendingOrders[slotIdx][0];
            buyTicket = g_lastOrderResult;
            for (buySlotScanIdx = 0; buySlotScanIdx < 100; buySlotScanIdx = buySlotScanIdx + 1)
            {
                if (!(g_stopOrderTicketPrice[buySlotScanIdx][0] == 0.0))   continue;
                g_stopOrderTicketPrice[buySlotScanIdx][0] = (double)buyTicket;
                g_stopOrderTicketPrice[buySlotScanIdx][1] = buyStoredPrice;
                break;

            }
            if (g_lastOrderResult <= 0)
            {
                if (MT4_LastError() == 132)
                {
                    ResetLastError();

                    do
                    {
                        Sleep(2500);
                        g_lastOrderResult = OrderSend(g_chartSymbol, 4, g_virtualPendingOrders[slotIdx][2], g_virtualPendingOrders[slotIdx][0], int(g_slippagePts * g_pipSize), g_virtualPendingOrders[slotIdx][0] - (g_stopLossPips + g_stopExtraPips) * g_pipSize, g_takeProfitPips * g_pipSize + g_virtualPendingOrders[slotIdx][0], g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry + 0x2A300, Green);
                        buyRetryStoredPrice = g_virtualPendingOrders[slotIdx][0];
                        buyRetryTicket = g_lastOrderResult;
                        for (buyRetrySlotScanIdx = 0; buyRetrySlotScanIdx < 100; buyRetrySlotScanIdx = buyRetrySlotScanIdx + 1)
                        {
                            if (!(g_stopOrderTicketPrice[buyRetrySlotScanIdx][0] == 0.0))   continue;
                            g_stopOrderTicketPrice[buyRetrySlotScanIdx][0] = (double)buyRetryTicket;
                            g_stopOrderTicketPrice[buyRetrySlotScanIdx][1] = buyRetryStoredPrice;
                            break;

                        }
                    } while (MT4_LastError() == 132);


                }
                Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order");
            }
        }
        if (!(g_virtualPendingOrders[slotIdx][1] == 5.0) || !(MarketInfo(g_chartSymbol, MODE_BID) > g_virtualPendingOrders[slotIdx][0] + g_minStopDistPrice))   continue;
        Print("Restoring pending sell-order");
        g_lastOrderResult = OrderSend(g_chartSymbol, 5, g_virtualPendingOrders[slotIdx][2], g_virtualPendingOrders[slotIdx][0], int(g_slippagePts * g_pipSize), (g_stopLossPips + g_stopExtraPips) * g_pipSize + g_virtualPendingOrders[slotIdx][0], g_virtualPendingOrders[slotIdx][0] - g_takeProfitPips * g_pipSize, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry + 0x2A300, Green);
        sellStoredPrice = g_virtualPendingOrders[slotIdx][0];
        sellTicket = g_lastOrderResult;
        for (sellSlotScanIdx = 0; sellSlotScanIdx < 100; sellSlotScanIdx = sellSlotScanIdx + 1)
        {
            if (!(g_stopOrderTicketPrice[sellSlotScanIdx][0] == 0.0))   continue;
            g_stopOrderTicketPrice[sellSlotScanIdx][0] = (double)sellTicket;
            g_stopOrderTicketPrice[sellSlotScanIdx][1] = sellStoredPrice;
            break;

        }
        if (g_lastOrderResult > 0)   continue;

        if (MT4_LastError() == 132)
        {
            ResetLastError();

            do
            {
                Sleep(2500);
                g_lastOrderResult = OrderSend(g_chartSymbol, 5, g_virtualPendingOrders[slotIdx][2], g_virtualPendingOrders[slotIdx][0], int(g_slippagePts * g_pipSize), (g_stopLossPips + g_stopExtraPips) * g_pipSize + g_virtualPendingOrders[slotIdx][0], g_virtualPendingOrders[slotIdx][0] - g_takeProfitPips * g_pipSize, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry + 0x2A300, Green);
                sellRetryStoredPrice = g_virtualPendingOrders[slotIdx][0];
                sellRetryTicket = g_lastOrderResult;
                for (sellRetrySlotScanIdx = 0; sellRetrySlotScanIdx < 100; sellRetrySlotScanIdx = sellRetrySlotScanIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[sellRetrySlotScanIdx][0] == 0.0))   continue;
                    g_stopOrderTicketPrice[sellRetrySlotScanIdx][0] = (double)sellRetryTicket;
                    g_stopOrderTicketPrice[sellRetrySlotScanIdx][1] = sellRetryStoredPrice;
                    break;

                }
            } while (MT4_LastError() == 132);


        }
        Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order");

    }
    for (clearSlotIdx = 0; clearSlotIdx < g_virtualOrderSlots; clearSlotIdx = clearSlotIdx + 1)
    {
        g_virtualPendingOrders[clearSlotIdx][0] = 0.0;
        g_virtualPendingOrders[clearSlotIdx][1] = 0.0;
        g_virtualPendingOrders[clearSlotIdx][2] = 0.0;
    }
}
//RestoreStoredPendingOrders <<==--------   --------
// RemovePendingOrdersDuringHighSpread —— 点差超过 MaxSpread 时移除挂单
bool RemovePendingOrdersDuringHighSpread()
{
    int       orderScanIdx;
    int       buySlotIdx;
    int       sellSlotIdx;
    //----- -----
    long       buyStoredTicket;
    int        buyTicketSlotScanIdx;
    long       buyDeletedTicket;
    int        buyDeleteSlotScanIdx;
    double     sellOpenPrice;
    double     sellBidPrice;
    long       sellStoredTicket;
    int        sellTicketSlotScanIdx;
    long       sellDeletedTicket;
    int        sellDeleteSlotScanIdx;

    for (orderScanIdx = MT4OrdersTotal(); orderScanIdx >= 0; orderScanIdx--)
    {
        if (OrderSelect(orderScanIdx, 0, 0) != true)   continue;

        if ((OrderMagicNumber() != g_curStrategyMagic && OrderMagicNumber() != g_manualMagicNumber) || OrderSymbol() != g_chartSymbol)   continue;

        if (OrderType() == 4 && OrderOpenPrice() < g_pendingMinGapPips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK) && MarketInfo(g_chartSymbol, MODE_ASK) < OrderOpenPrice() - g_freezeDistPrice)
        {
            if (g_maxSpreadPts > 0.0)
            {
                Print("Spread too high..(" + string(g_curSpread) + ") storing and deleting order " + string(OrderTicket()));
                for (buySlotIdx = 0; buySlotIdx < g_virtualOrderSlots; buySlotIdx++)
                {
                    if (g_virtualPendingOrders[buySlotIdx][0] == 0.0)
                    {
                        Print("Storing pending order nr " + string(OrderTicket()));
                        g_virtualPendingOrders[buySlotIdx][1] = OrderType();
                        g_virtualPendingOrders[buySlotIdx][0] = OrderOpenPrice();
                        g_virtualPendingOrders[buySlotIdx][2] = OrderLots();
                        break;
                    }
                }
                buyStoredTicket = OrderTicket();
                for (buyTicketSlotScanIdx = 0; buyTicketSlotScanIdx < 100; buyTicketSlotScanIdx = buyTicketSlotScanIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[buyTicketSlotScanIdx][0] == buyStoredTicket))   continue;
                    g_stopOrderTicketPrice[buyTicketSlotScanIdx][0] = 0.0;
                    g_stopOrderTicketPrice[buyTicketSlotScanIdx][1] = 0.0;
                    break;

                }
                OrderDelete(OrderTicket(), Green);
            }
            else
            {
                Print("Spread too high..(" + string(g_curSpread) + ") deleting order " + string(OrderTicket()));
                buyDeletedTicket = OrderTicket();
                for (buyDeleteSlotScanIdx = 0; buyDeleteSlotScanIdx < 100; buyDeleteSlotScanIdx = buyDeleteSlotScanIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[buyDeleteSlotScanIdx][0] == buyDeletedTicket))   continue;
                    g_stopOrderTicketPrice[buyDeleteSlotScanIdx][0] = 0.0;
                    g_stopOrderTicketPrice[buyDeleteSlotScanIdx][1] = 0.0;
                    break;

                }
                OrderDelete(OrderTicket(), Green);
            }
        }
        if (OrderType() != 5)   continue;
        sellOpenPrice = OrderOpenPrice();
        if (!(sellOpenPrice > MarketInfo(g_chartSymbol, MODE_BID) - g_pendingMinGapPips * g_pipSize))   continue;
        sellBidPrice = MarketInfo(g_chartSymbol, MODE_BID);
        if (!(sellBidPrice > OrderOpenPrice() + g_freezeDistPrice))   continue;

        if (g_maxSpreadPts > 0.0)
        {
            Print("Spread too high..(" + string(g_curSpread) + ") storing and deleting order " + string(OrderTicket()));
            for (sellSlotIdx = 0; sellSlotIdx < g_virtualOrderSlots; sellSlotIdx++)
            {
                if (g_virtualPendingOrders[sellSlotIdx][0] == 0.0)
                {
                    Print("Storing pending order nr " + string(OrderTicket()));
                    g_virtualPendingOrders[sellSlotIdx][1] = OrderType();
                    g_virtualPendingOrders[sellSlotIdx][0] = OrderOpenPrice();
                    g_virtualPendingOrders[sellSlotIdx][2] = OrderLots();
                    break;
                }
            }
            sellStoredTicket = OrderTicket();
            for (sellTicketSlotScanIdx = 0; sellTicketSlotScanIdx < 100; sellTicketSlotScanIdx = sellTicketSlotScanIdx + 1)
            {
                if (!(g_stopOrderTicketPrice[sellTicketSlotScanIdx][0] == sellStoredTicket))   continue;
                g_stopOrderTicketPrice[sellTicketSlotScanIdx][0] = 0.0;
                g_stopOrderTicketPrice[sellTicketSlotScanIdx][1] = 0.0;
                break;

            }
            OrderDelete(OrderTicket(), Green);
            continue;
        }
        Print("Spread too high..(" + string(g_curSpread) + ") deleting order " + string(OrderTicket()));
        sellDeletedTicket = OrderTicket();
        for (sellDeleteSlotScanIdx = 0; sellDeleteSlotScanIdx < 100; sellDeleteSlotScanIdx = sellDeleteSlotScanIdx + 1)
        {
            if (!(g_stopOrderTicketPrice[sellDeleteSlotScanIdx][0] == sellDeletedTicket))   continue;
            g_stopOrderTicketPrice[sellDeleteSlotScanIdx][0] = 0.0;
            g_stopOrderTicketPrice[sellDeleteSlotScanIdx][1] = 0.0;
            break;

        }
        OrderDelete(OrderTicket(), Green);

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
void CalculateStrategyLotSize(double stopLossPips, int lotScalePercent)
{
    double    computedLots;
    double    slPipsAdjusted;
    double    riskPercent;
    double    riskBalanceAmount;
    double    risk999Balance;
    double    balanceInUsd;
    //----- -----

    computedLots = g_strategyStartLots[g_currentStrategyIndex];
    g_effectiveBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (UseEquity)
    {
        g_effectiveBalance = AccountInfoDouble(ACCOUNT_EQUITY);
    }
    if (OnlyUp && g_highestBalance > g_effectiveBalance)
    {
        g_effectiveBalance = g_highestBalance;
    }
    if (g_effectiveBalance > g_highestBalance)
    {
        g_highestBalance = g_effectiveBalance;
        GlobalVariableSet("HighestBalance", g_highestBalance);
    }
    if (ManualBalance > 0.0)
    {
        g_effectiveBalance = ManualBalance;
    }
    // Original JIT 0x19aa50e89e7-0x19aa50e8a29: lot-sizing guard.
    if (g_effectiveBalance == 0.0)
    {
        g_effectiveBalance = 0.01;
    }
    slPipsAdjusted = stopLossPips;
    if ((g_symbolDigits == 2 || g_symbolDigits == 4))
    {
        slPipsAdjusted = stopLossPips / 10.0;
    }
    if (Risk < 999 && Risk >  0)
    {
        riskPercent = Risk;
        riskBalanceAmount = riskPercent / 1000.0 * g_effectiveBalance;
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.1)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * (riskBalanceAmount / (MarketInfo(g_chartSymbol, MODE_TICKVALUE) * slPipsAdjusted) * 0.1), 1);
        }
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.01)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * (riskBalanceAmount / (MarketInfo(g_chartSymbol, MODE_TICKVALUE) * slPipsAdjusted) * 0.1), 2);
        }
    }
    if (Risk == 999)
    {
        risk999Balance = g_risk999BalancePct / 100.0 * g_effectiveBalance;
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.1)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * (risk999Balance / (MarketInfo(g_chartSymbol, MODE_TICKVALUE) * slPipsAdjusted) * 0.1), 1);
        }
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.01)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * (risk999Balance / (MarketInfo(g_chartSymbol, MODE_TICKVALUE) * slPipsAdjusted) * 0.1), 2);
        }
    }
    if (Risk == 0)
    {
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.1)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * g_startLots_rw, 1);
        }
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.01)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * g_startLots_rw, 2);
        }
    }
    if (Risk == 9999)
    {
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.1)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * (g_effectiveBalance / g_ddTierDivisor * 0.01), 1);
        }
        if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.01)
        {
            computedLots = NormalizeDouble(lotScalePercent * 0.01 * (g_effectiveBalance / g_ddTierDivisor * 0.01), 2);
        }
    }
    if (Risk == 1234)
    {
        if (UseWeightedLots)
        {
            if (g_usdToAccountRate == 0.0)
            {
                g_usdToAccountRate = 100000.0;
            }
            g_ddLotFactor = MaxAllowedDD / g_riskFactorByTier;
            if (SymbolInfoDouble(g_chartSymbol, 36) == 0.1)
            {
                computedLots = NormalizeDouble(g_ddLotFactor / g_usdToAccountRate * g_effectiveBalance / 100.0 * 0.01, 1);
            }
            if (SymbolInfoDouble(g_chartSymbol, 36) == 0.01)
            {
                computedLots = NormalizeDouble(g_ddLotFactor / g_usdToAccountRate * g_effectiveBalance / 100.0 * 0.01, 2);
            }
        }
        else
        {
            if (g_usdToAccountRate == 0.0)
            {
                g_usdToAccountRate = 100000.0;
            }
            balanceInUsd = ConvertAccountCurrencyToUsd(g_effectiveBalance);
            if (g_tradeFrequencyMode == 0)
            {
                g_ddTierDivisor = (int)(g_ddTierThreshold1 / (MaxAllowedDD / 100.0));
            }
            if (g_tradeFrequencyMode == 1)
            {
                g_ddTierDivisor = (int)(g_ddTierThreshold2Usd / (MaxAllowedDD / 100.0));
            }
            if (g_tradeFrequencyMode == 2)
            {
                g_ddTierDivisor = (int)(g_ddTierThreshold3 / (MaxAllowedDD / 100.0));
            }
            if (g_tradeFrequencyMode == 3)
            {
                g_ddTierDivisor = (int)(g_ddTierThreshold4Usd / (MaxAllowedDD / 100.0));
            }
            if (g_tradeFrequencyMode == 4)
            {
                g_ddTierDivisor = (int)(g_ddTierThreshold5 / (MaxAllowedDD / 100.0));
            }
            if (SymbolInfoDouble(g_chartSymbol, 36) == 0.1)
            {
                computedLots = NormalizeDouble(lotScalePercent * 0.01 * (balanceInUsd / g_ddTierDivisor * 0.01), 1);
            }
            if (SymbolInfoDouble(g_chartSymbol, 36) == 0.01)
            {
                computedLots = NormalizeDouble(lotScalePercent * 0.01 * (balanceInUsd / g_ddTierDivisor * 0.01), 2);
            }
        }
    }
    if (Risk == 3)
    {
        if (SymbolInfoDouble(g_chartSymbol, 36) == 0.1)
        {
            computedLots = NormalizeDouble(MaxRiskPerStrategy_ / g_usdToAccountRate * g_effectiveBalance / 100.0 * 0.01, 1);
        }
        if (SymbolInfoDouble(g_chartSymbol, 36) == 0.01)
        {
            computedLots = NormalizeDouble(MaxRiskPerStrategy_ / g_usdToAccountRate * g_effectiveBalance / 100.0 * 0.01, 2);
        }
    }
    // Legacy hidden Risk values 1/2 preserve strategy 1's manual lot until its
    // first pending order exists.  With no variable lot adjustment they retain
    // StartLots for strategy 1, while the remaining strategies use dynamic risk.
    if (g_currentStrategyIndex == 0 && (Risk == 1 || Risk == 2) &&
        (g_initialLegacyRiskLotPending || MathAbs(g_lotRatioInv - 1.0) < 0.0000001))
    {
        computedLots = g_startLots_rw;
    }
    computedLots = computedLots * g_lotRatioInv;
    if (computedLots < MarketInfo(g_chartSymbol, MODE_LOTSTEP))
    {
        computedLots = MarketInfo(g_chartSymbol, MODE_LOTSTEP);
    }
    if (computedLots > g_maxLotCap)
    {
        computedLots = g_maxLotCap;
    }
    if (computedLots < MarketInfo(g_chartSymbol, MODE_MINLOT))
    {
        computedLots = MarketInfo(g_chartSymbol, MODE_MINLOT);
    }
    if (computedLots > MarketInfo(g_chartSymbol, MODE_MAXLOT) && MarketInfo(g_chartSymbol, MODE_MAXLOT) != 0.0)
    {
        computedLots = MarketInfo(g_chartSymbol, MODE_MAXLOT);
    }
    if (MarketInfo(g_chartSymbol, MODE_LOTSTEP) == 0.1)
    {
        g_strategyStartLots[g_currentStrategyIndex] = NormalizeDouble((MathFloor(computedLots * 10.0)) / 10.0, 1);
        return;
    }
    g_strategyStartLots[g_currentStrategyIndex] = NormalizeDouble(MathFloor(computedLots * 100.0) / 100.0, 2);
}
//CalculateStrategyLotSize <<==--------   --------
// ============================================================================
// [§12] 入场价位探测
//       FindBuyEntryHigh / FindSellEntryLow     —— 逐 bar 扫描版（慢速）
//       MT4FastEntryHigh / MT4FastEntryLow     —— 直接读价格序列版（快速）
//       FindFractalHigh / FindFractalLow       —— 分形高/低点扫描
//       MT4FastFractalHigh / MT4FastFractalLow —— 分形快速版
// ============================================================================

double FindBuyEntryHigh(int scanTfPeriod)
{
    bool      fractalFound = false;
    bool      rightSideClear = false;
    bool      leftSideClear;
    int       fractalBarIdx;
    int       leftScanIdx;
    int       rightScanIdx;
    //----- -----
    double     fractalPrice;
    int        scanLimitBar;
    double     entryTfExtreme;
    int        entryTfScanIdx;
    double     normalizedFractalPrice;
    int        dupScanIdx;
    bool       duplicatePending;

    leftSideClear = false;
    fractalBarIdx = g_fractalLeftBars + 1;
    do
    {
        rightSideClear = true;
        leftSideClear = true;
        for (leftScanIdx = fractalBarIdx; leftScanIdx >= fractalBarIdx - g_fractalLeftBars; leftScanIdx--)
        {
            if (iHigh(g_chartSymbol, MT4Period(scanTfPeriod), leftScanIdx) > iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx))
            {
                leftSideClear = false;
            }
        }
        for (rightScanIdx = fractalBarIdx; rightScanIdx <= fractalBarIdx + g_fractalRightBars; rightScanIdx++)
        {
            if (iHigh(g_chartSymbol, MT4Period(scanTfPeriod), rightScanIdx) > iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx))
            {
                rightSideClear = false;
            }
        }
        if (leftSideClear && rightSideClear && iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx) > g_entryBreakoutPips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK))
        {
            fractalPrice = iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx);
            scanLimitBar = fractalBarIdx;
            entryTfExtreme = iHigh(g_chartSymbol, MT4Period(g_entryTfPeriod), 0);
            for (entryTfScanIdx = 1; entryTfScanIdx <= scanLimitBar; entryTfScanIdx = entryTfScanIdx + 1)
            {
                if (iHigh(g_chartSymbol, MT4Period(g_entryTfPeriod), entryTfScanIdx) > entryTfExtreme)
                {
                    entryTfExtreme = iHigh(g_chartSymbol, MT4Period(g_entryTfPeriod), entryTfScanIdx);
                }
            }
            if (fractalPrice >= entryTfExtreme)
            {
                normalizedFractalPrice = NormalizeDouble(iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx), g_symbolDigits);
                duplicatePending = false;
                for (dupScanIdx = MT4OrdersTotal(); dupScanIdx >= 0; dupScanIdx = dupScanIdx - 1)
                {
                    if (OrderSelect(dupScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MathAbs(OrderOpenPrice() - (g_buyEntryOffsetPips * g_pipSize + normalizedFractalPrice)) < g_pendingDupTolerancePips * g_pipSize))   continue;
                    duplicatePending = true;
                    break;

                }
                if (!(duplicatePending) && (!(g_fractalRequireUnbrokenLevel) || !(iClose(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx - 1) > iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx) - g_entryBreakoutPips * g_pipSize)))
                {
                    fractalFound = true;
                    g_entryHighPrice = NormalizeDouble(iHigh(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx), g_symbolDigits);
                    break;
                }
            }
        }
        fractalBarIdx++;
        if (fractalBarIdx <= g_fractalMinLookback)   continue;
        g_entryHighPrice = 0.0;
        break;

    } while (!(fractalFound));

    return(g_entryHighPrice);
}
//FindBuyEntryHigh <<==--------   --------
double FindSellEntryLow(int scanTfPeriod)
{
    bool      fractalFound = false;
    bool      rightSideClear = false;
    bool      leftSideClear;
    int       fractalBarIdx;
    int       leftScanIdx;
    int       rightScanIdx;
    //----- -----
    double     fractalPrice;
    int        scanLimitBar;
    double     entryTfExtreme;
    int        entryTfScanIdx;
    double     normalizedFractalPrice;
    int        dupScanIdx;
    bool       duplicatePending;

    leftSideClear = false;
    fractalBarIdx = g_fractalLeftBars + 1;
    do
    {
        rightSideClear = true;
        leftSideClear = true;
        for (leftScanIdx = fractalBarIdx; leftScanIdx >= fractalBarIdx - g_fractalLeftBars; leftScanIdx--)
        {
            if (iLow(g_chartSymbol, MT4Period(scanTfPeriod), leftScanIdx) < iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx))
            {
                leftSideClear = false;
            }
        }
        for (rightScanIdx = fractalBarIdx; rightScanIdx <= fractalBarIdx + g_fractalRightBars; rightScanIdx++)
        {
            if (iLow(g_chartSymbol, MT4Period(scanTfPeriod), rightScanIdx) < iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx))
            {
                rightSideClear = false;
            }
        }
        if (leftSideClear && rightSideClear && iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx) < MarketInfo(g_chartSymbol, MODE_BID) - g_entryBreakoutPips * g_pipSize)
        {
            fractalPrice = iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx);
            scanLimitBar = fractalBarIdx;
            entryTfExtreme = iLow(g_chartSymbol, MT4Period(g_entryTfPeriod), 0);
            for (entryTfScanIdx = 1; entryTfScanIdx <= scanLimitBar; entryTfScanIdx = entryTfScanIdx + 1)
            {
                if (iLow(g_chartSymbol, MT4Period(g_entryTfPeriod), entryTfScanIdx) < entryTfExtreme)
                {
                    entryTfExtreme = iLow(g_chartSymbol, MT4Period(g_entryTfPeriod), entryTfScanIdx);
                }
            }
            if (fractalPrice <= entryTfExtreme)
            {
                normalizedFractalPrice = NormalizeDouble(iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx), g_symbolDigits);
                duplicatePending = false;
                for (dupScanIdx = MT4OrdersTotal(); dupScanIdx >= 0; dupScanIdx = dupScanIdx - 1)
                {
                    if (OrderSelect(dupScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MathAbs(OrderOpenPrice() - (normalizedFractalPrice - g_sellEntryOffsetPips * g_pipSize)) < g_pendingDupTolerancePips * g_pipSize))   continue;
                    duplicatePending = true;
                    break;

                }
                if (!(duplicatePending) && (!(g_fractalRequireUnbrokenLevel) || !(iClose(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx - 1) < g_entryBreakoutPips * g_pipSize + iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx))))
                {
                    fractalFound = true;
                    g_entryLowPrice = NormalizeDouble(iLow(g_chartSymbol, MT4Period(scanTfPeriod), fractalBarIdx), g_symbolDigits);
                    break;
                }
            }
        }
        fractalBarIdx++;
        if (fractalBarIdx <= g_fractalMinLookback)   continue;
        g_entryLowPrice = 0.0;
        break;

    } while (!(fractalFound));

    return(g_entryLowPrice);
}
//FindSellEntryLow <<==--------   --------
double MT4FastEntryHigh(int timeframe)
{
    ENUM_TIMEFRAMES tf = MT4Period(timeframe);
    int side = MathMax(g_fractalRightBars, g_fractalLeftBars);
    int count = g_fractalMinLookback + side + 2;
    double highs[];
    ArraySetAsSeries(highs, true);
    if (CopyHigh(g_chartSymbol, tf, 0, count, highs) < count)
        return(FindBuyEntryHigh(timeframe));

    int candidate = g_fractalLeftBars + 1;
    do
    {
        bool left_ok = true;
        bool right_ok = true;
        double candidate_price = highs[candidate];
        for (int i = candidate; i >= candidate - g_fractalLeftBars; i--)
            if (highs[i] > candidate_price) left_ok = false;
        for (int i = candidate; i <= candidate + g_fractalRightBars; i++)
            if (highs[i] > candidate_price) right_ok = false;

        if (left_ok && right_ok && candidate_price > g_entryBreakoutPips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK))
        {
            double range_high = highs[0];
            for (int i = 1; i <= candidate; i++)
                if (highs[i] > range_high) range_high = highs[i];
            if (candidate_price >= range_high)
            {
                double normalized = NormalizeDouble(candidate_price, g_symbolDigits);
                bool duplicate = false;
                for (int i = MT4OrdersTotal(); i >= 0; i--)
                {
                    if (OrderSelect(i, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic ||
                        OrderSymbol() != g_chartSymbol || OrderType() != 4 ||
                        !(MathAbs(OrderOpenPrice() - (g_buyEntryOffsetPips * g_pipSize + normalized)) < g_pendingDupTolerancePips * g_pipSize)) continue;
                    duplicate = true;
                    break;
                }
                if (!duplicate && (!g_fractalRequireUnbrokenLevel || !(iClose(g_chartSymbol, tf, candidate - 1) > candidate_price - g_entryBreakoutPips * g_pipSize)))
                {
                    g_entryHighPrice = normalized;
                    return(g_entryHighPrice);
                }
            }
        }
        candidate++;
        if (candidate <= g_fractalMinLookback) continue;
        g_entryHighPrice = 0.0;
        break;
    } while (true);
    return(g_entryHighPrice);
}

double MT4FastEntryLow(int timeframe)
{
    ENUM_TIMEFRAMES tf = MT4Period(timeframe);
    int side = MathMax(g_fractalRightBars, g_fractalLeftBars);
    int count = g_fractalMinLookback + side + 2;
    double lows[];
    ArraySetAsSeries(lows, true);
    if (CopyLow(g_chartSymbol, tf, 0, count, lows) < count)
        return(FindSellEntryLow(timeframe));

    int candidate = g_fractalLeftBars + 1;
    do
    {
        bool left_ok = true;
        bool right_ok = true;
        double candidate_price = lows[candidate];
        for (int i = candidate; i >= candidate - g_fractalLeftBars; i--)
            if (lows[i] < candidate_price) left_ok = false;
        for (int i = candidate; i <= candidate + g_fractalRightBars; i++)
            if (lows[i] < candidate_price) right_ok = false;

        if (left_ok && right_ok && candidate_price < MarketInfo(g_chartSymbol, MODE_BID) - g_entryBreakoutPips * g_pipSize)
        {
            double range_low = lows[0];
            for (int i = 1; i <= candidate; i++)
                if (lows[i] < range_low) range_low = lows[i];
            if (candidate_price <= range_low)
            {
                double normalized = NormalizeDouble(candidate_price, g_symbolDigits);
                bool duplicate = false;
                for (int i = MT4OrdersTotal(); i >= 0; i--)
                {
                    if (OrderSelect(i, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic ||
                        OrderSymbol() != g_chartSymbol || OrderType() != 5 ||
                        !(MathAbs(OrderOpenPrice() - (normalized - g_sellEntryOffsetPips * g_pipSize)) < g_pendingDupTolerancePips * g_pipSize)) continue;
                    duplicate = true;
                    break;
                }
                if (!duplicate && (!g_fractalRequireUnbrokenLevel || !(iClose(g_chartSymbol, tf, candidate - 1) < g_entryBreakoutPips * g_pipSize + candidate_price)))
                {
                    g_entryLowPrice = normalized;
                    return(g_entryLowPrice);
                }
            }
        }
        candidate++;
        if (candidate <= g_fractalMinLookback) continue;
        g_entryLowPrice = 0.0;
        break;
    } while (true);
    return(g_entryLowPrice);
}

double FindFractalHigh(int tfMinutes, int rightBars, int leftBars)
{
    bool      fractalFound = false;
    double    fractalPrice = 0.0;
    bool      rightSideClear = false;
    bool      leftSideClear;
    int       candidateShift;
    int       leftScanShift;
    int       rightScanShift;
    //----- -----

    leftSideClear = false;
    candidateShift = leftBars + 1;
    do
    {
        rightSideClear = true;
        leftSideClear = true;
        for (leftScanShift = candidateShift; leftScanShift >= candidateShift - leftBars; leftScanShift--)
        {
            if (iHigh(g_chartSymbol, MT4Period(tfMinutes), leftScanShift) > iHigh(g_chartSymbol, MT4Period(tfMinutes), candidateShift))
            {
                leftSideClear = false;
            }
        }
        for (rightScanShift = candidateShift; rightScanShift <= candidateShift + rightBars; rightScanShift++)
        {
            if (iHigh(g_chartSymbol, MT4Period(tfMinutes), rightScanShift) > iHigh(g_chartSymbol, MT4Period(tfMinutes), candidateShift))
            {
                rightSideClear = false;
            }
        }
        if (leftSideClear && rightSideClear && iHigh(g_chartSymbol, MT4Period(tfMinutes), candidateShift) > g_minStopDistPrice + MarketInfo(g_chartSymbol, MODE_ASK))
        {
            fractalFound = true;
            fractalPrice = NormalizeDouble(iHigh(g_chartSymbol, MT4Period(tfMinutes), candidateShift), g_symbolDigits);
            break;
        }
        candidateShift++;
        if (candidateShift <= g_fractalMaxShift)   continue;
        fractalPrice = 9999.0;
        break;

    } while (!(fractalFound));

    return(fractalPrice);
}
//FindFractalHigh <<==--------   --------
double FindFractalLow(int tfMinutes, int rightBars, int leftBars)
{
    bool      fractalFound = false;
    double    fractalPrice = 0.0;
    bool      rightSideClear = false;
    bool      leftSideClear;
    int       candidateShift;
    int       leftScanShift;
    int       rightScanShift;
    //----- -----

    leftSideClear = false;
    candidateShift = leftBars + 1;
    do
    {
        rightSideClear = true;
        leftSideClear = true;
        for (leftScanShift = candidateShift; leftScanShift >= candidateShift - leftBars; leftScanShift--)
        {
            if (iLow(g_chartSymbol, MT4Period(tfMinutes), leftScanShift) < iLow(g_chartSymbol, MT4Period(tfMinutes), candidateShift))
            {
                leftSideClear = false;
            }
        }
        for (rightScanShift = candidateShift; rightScanShift <= candidateShift + rightBars; rightScanShift++)
        {
            if (iLow(g_chartSymbol, MT4Period(tfMinutes), rightScanShift) < iLow(g_chartSymbol, MT4Period(tfMinutes), candidateShift))
            {
                rightSideClear = false;
            }
        }
        if (leftSideClear && rightSideClear && iLow(g_chartSymbol, MT4Period(tfMinutes), candidateShift) < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
        {
            fractalFound = true;
            fractalPrice = NormalizeDouble(iLow(g_chartSymbol, MT4Period(tfMinutes), candidateShift), g_symbolDigits);
            break;
        }
        candidateShift++;
        if (candidateShift <= g_fractalMaxShift)   continue;
        fractalPrice = 0.0;
        break;

    } while (!(fractalFound));

    return(fractalPrice);
}
//FindFractalLow <<==--------   --------
double MT4FastFractalHigh(int timeframe, int rightBars, int leftBars)
{
    ENUM_TIMEFRAMES tf = MT4Period(timeframe);
    int maxShift = g_fractalMaxShift + rightBars + 1;
    double highs[];
    ArraySetAsSeries(highs, true);
    if (CopyHigh(g_chartSymbol, tf, 0, maxShift + 1, highs) < maxShift + 1)
        return FindFractalHigh(timeframe, rightBars, leftBars);
    for (int candidate = leftBars + 1; candidate <= g_fractalMaxShift; candidate++)
    {
        double px = highs[candidate];
        bool leftOk = true, rightOk = true;
        for (int i = candidate; i >= candidate - leftBars; i--)
            if (highs[i] > px) { leftOk = false; break; }
        if (!leftOk) continue;
        for (int i = candidate; i <= candidate + rightBars; i++)
            if (highs[i] > px) { rightOk = false; break; }
        if (rightOk && px > g_minStopDistPrice + MarketInfo(g_chartSymbol, MODE_ASK))
            return NormalizeDouble(px, g_symbolDigits);
    }
    return 9999.0;
}

double MT4FastFractalLow(int timeframe, int rightBars, int leftBars)
{
    ENUM_TIMEFRAMES tf = MT4Period(timeframe);
    int maxShift = g_fractalMaxShift + rightBars + 1;
    double lows[];
    ArraySetAsSeries(lows, true);
    if (CopyLow(g_chartSymbol, tf, 0, maxShift + 1, lows) < maxShift + 1)
        return FindFractalLow(timeframe, rightBars, leftBars);
    for (int candidate = leftBars + 1; candidate <= g_fractalMaxShift; candidate++)
    {
        double px = lows[candidate];
        bool leftOk = true, rightOk = true;
        for (int i = candidate; i >= candidate - leftBars; i--)
            if (lows[i] < px) { leftOk = false; break; }
        if (!leftOk) continue;
        for (int i = candidate; i <= candidate + rightBars; i++)
            if (lows[i] < px) { rightOk = false; break; }
        if (rightOk && px < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
            return NormalizeDouble(px, g_symbolDigits);
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
    int       expiryScanIdx;
    //----- -----
    long       nowTime;
    long       orderExpiryTime;
    int        buyOpenCount;
    int        buyCountScanIdx;
    int        manualBuyDeleteMode;
    int        strategyBuyPendingScanIdx;
    int        manualBuyPendingScanIdx;
    int        sellOpenCount;
    int        sellCountScanIdx;
    int        manualSellDeleteMode;
    int        strategySellPendingScanIdx;
    int        manualSellPendingScanIdx;

    if (g_maFilterEnabled)
    {
        g_maFilterFast = iMA(g_chartSymbol, 0, g_maFilterPeriod, 0, 1, 0, 1);
        g_maFilterSlow = iMA(g_chartSymbol, 0, g_maSlowPeriod, 0, 1, 0, 1);
    }
    CalculateStrategyLotSize(g_stopLossPips, g_lotScalePercent);
    if (g_strategyStartLots[g_currentStrategyIndex] > g_maxLotCap)
    {
        g_strategyStartLots[g_currentStrategyIndex] = g_maxLotCap;
    }
    if (g_pendingExpiryHours > 0)
    {
        g_pendingOrderExpiry = TimeCurrent() + g_pendingExpirySecs;
    }
    if (Virtual_expiration)
    {
        g_pendingOrderExpiry = 0;
        for (expiryScanIdx = MT4OrdersTotal(); expiryScanIdx >= 0; expiryScanIdx--)
        {
            if (OrderSelect(expiryScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol)   continue;

            if ((OrderType() != 4 && OrderType() != 5))   continue;
            nowTime = TimeCurrent();
            orderExpiryTime = OrderOpenTime() + g_pendingExpirySecs;
            if (nowTime < orderExpiryTime)   continue;
            OrderDelete(OrderTicket(), Red);

        }
    }
    buyOpenCount = 0;
    for (buyCountScanIdx = MT4OrdersTotal(); buyCountScanIdx >= 0; buyCountScanIdx = buyCountScanIdx - 1)
    {
        if (OrderSelect(buyCountScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 0)   continue;
        buyOpenCount = buyOpenCount + 1;

    }
    if (buyOpenCount < g_maxOpenTradesPerSide)
    {
        PlaceBuyStopEntry(1);
    }
    else
    {
        manualBuyDeleteMode = 1;
        for (strategyBuyPendingScanIdx = MT4OrdersTotal(); strategyBuyPendingScanIdx >= 0; strategyBuyPendingScanIdx = strategyBuyPendingScanIdx - 1)
        {
            if (OrderSelect(strategyBuyPendingScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
            OrderDelete(OrderTicket(), 0xFFFFFFFF);

        }
        if (manualBuyDeleteMode == 2)
        {
            for (manualBuyPendingScanIdx = MT4OrdersTotal(); manualBuyPendingScanIdx >= 0; manualBuyPendingScanIdx = manualBuyPendingScanIdx - 1)
            {
                if (OrderSelect(manualBuyPendingScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                OrderDelete(OrderTicket(), 0xFFFFFFFF);

            }
        }
    }
    sellOpenCount = 0;
    for (sellCountScanIdx = MT4OrdersTotal(); sellCountScanIdx >= 0; sellCountScanIdx = sellCountScanIdx - 1)
    {
        if (OrderSelect(sellCountScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 1)   continue;
        sellOpenCount = sellOpenCount + 1;

    }
    if (sellOpenCount < g_maxOpenTradesPerSide)
    {
        PlaceSellStopEntry(1);
        return;
    }
    manualSellDeleteMode = 1;
    for (strategySellPendingScanIdx = MT4OrdersTotal(); strategySellPendingScanIdx >= 0; strategySellPendingScanIdx = strategySellPendingScanIdx - 1)
    {
        if (OrderSelect(strategySellPendingScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
        OrderDelete(OrderTicket(), 0xFFFFFFFF);

    }
    if (manualSellDeleteMode != 2)   return;
    for (manualSellPendingScanIdx = MT4OrdersTotal(); manualSellPendingScanIdx >= 0; manualSellPendingScanIdx = manualSellPendingScanIdx - 1)
    {
        if (OrderSelect(manualSellPendingScanIdx, 0, 0) != true || OrderMagicNumber() != g_manualMagicNumber || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
        OrderDelete(OrderTicket(), 0xFFFFFFFF);

    }
}
//ProcessStrategyEntries <<==--------   --------
// PlaceBuyStopEntry —— 放置 Buy Stop 挂单（含假突破过滤与入场价修正）
bool PlaceBuyStopEntry(int placeMode)
{
    bool      entryPriceSet;
    double    baseEntryPrice;
    double    orderPrice;
    double    stopLossPrice;
    double    takeProfitPrice;
    //----- -----
    bool       positionExists;
    int        posScanIdx;
    double     entryExtremePrice;
    int        dupScanIdx;
    bool       duplicatePending;
    int        pendingCount;
    int        pendingScanIdx;
    double     extremePendingPrice;
    int        extremeScanIdx;
    double     pendingAtTriggerPrice;
    int        overlapScanIdx;
    bool       pendingAtTrigger;
    bool       volumeValid;
    int        accountLimitOrders;
    bool       limitOrdersOk;
    int        errorCode;
    double     storedEntryPrice;
    long       orderTicket;
    int        slotIdx;

    if (!(AllowBuyTrades))
    {
        return(false);
    }
    if (g_allowMultipleEntries)
    {
        positionExists = false;
    }
    else
    {
        positionExists = false;
        for (posScanIdx = 0; posScanIdx < MT4OrdersTotal(); posScanIdx = posScanIdx + 1)
        {
            if (OrderSelect(posScanIdx, 0, 0) != true || OrderType() != 0 || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol)   continue;
            positionExists = true;
            break;

        }
    }
    if (positionExists == true)
    {
        return(false);
    }
    if (g_maFilterEnabled && g_maFilterFast < g_maFilterSlow)
    {
        return(false);
    }
    if (placeMode == 1)
    {
        MT4FastEntryHigh(g_entryTfPeriod);
        entryPriceSet = false;
        entryExtremePrice = g_entryHighPrice;
        duplicatePending = false;
        for (dupScanIdx = MT4OrdersTotal(); dupScanIdx >= 0; dupScanIdx = dupScanIdx - 1)
        {
            if (OrderSelect(dupScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(MathAbs(OrderOpenPrice() - (g_buyEntryOffsetPips * g_pipSize + entryExtremePrice)) < g_pendingDupTolerancePips * g_pipSize))   continue;
            duplicatePending = true;
            break;

        }
        if (!(duplicatePending))
        {
            pendingCount = 0;
            for (pendingScanIdx = MT4OrdersTotal(); pendingScanIdx >= 0; pendingScanIdx = pendingScanIdx - 1)
            {
                if (OrderSelect(pendingScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4)   continue;
                pendingCount = pendingCount + 1;

            }
            if (pendingCount == g_maxPendingOrders)
            {
                extremePendingPrice = 9999.0;
                for (extremeScanIdx = MT4OrdersTotal(); extremeScanIdx >= 0; extremeScanIdx = extremeScanIdx - 1)
                {
                    if (OrderSelect(extremeScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(OrderOpenPrice() < extremePendingPrice))   continue;
                    extremePendingPrice = OrderOpenPrice();

                }
                if (g_entryHighPrice > extremePendingPrice)
                {
                    return(false);
                }
            }
            entryPriceSet = true;
            g_buyEntryPrice = NormalizeDouble(g_entryHighPrice, g_symbolDigits);
        }
        if (g_buyEntryPrice == 0.0)
        {
            return(false);
        }
        if (entryPriceSet)
        {
            g_nextOrderAnchorPrice = g_gridAnchorPips;
            baseEntryPrice = NormalizeDouble(g_buyEntryOffsetPips * g_pipSize + g_buyEntryPrice, g_symbolDigits);
            pendingAtTriggerPrice = baseEntryPrice;
            pendingAtTrigger = false;
            for (overlapScanIdx = MT4OrdersTotal(); overlapScanIdx >= 0; overlapScanIdx = overlapScanIdx - 1)
            {
                if (OrderSelect(overlapScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 4 || !(OrderOpenPrice() <= pendingAtTriggerPrice))   continue;
                pendingAtTrigger = true;
                break;

            }
            if (pendingAtTrigger)
            {
                return(false);
            }
            if (!(g_limitPendingToOne))
            {
                if (CheckMargin && AccountFreeMarginCheck(g_chartSymbol, 0, g_strategyStartLots[g_currentStrategyIndex]) <= 0.0)
                {
                    Print("Free margin not sufficient for setting order...");
                    return(false);
                }
                orderPrice = NormalizeDouble(g_randomEntryOffsetPips * g_pipSize + baseEntryPrice, g_symbolDigits);
                stopLossPrice = NormalizeDouble(baseEntryPrice - (g_stopLossPips + g_stopExtraPips) * g_pipSize, g_symbolDigits);
                takeProfitPrice = NormalizeDouble(g_takeProfitPips * g_pipSize + baseEntryPrice, g_symbolDigits);
                if (g_strategyStartLots[g_currentStrategyIndex] < SymbolInfoDouble(g_chartSymbol, 34))
                {
                    Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=" + string(SymbolInfoDouble(g_chartSymbol, 34)));
                    volumeValid = false;
                }
                else
                {
                    if (g_strategyStartLots[g_currentStrategyIndex] > SymbolInfoDouble(g_chartSymbol, 35))
                    {
                        Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=" + string(SymbolInfoDouble(g_chartSymbol, 35)));
                        volumeValid = false;
                    }
                    else
                    {
                        if (MathAbs(NormalizeDouble(g_strategyStartLots[g_currentStrategyIndex] / SymbolInfoDouble(g_chartSymbol, 36), 0) * SymbolInfoDouble(g_chartSymbol, 36) - g_strategyStartLots[g_currentStrategyIndex]) > 0.0000001)
                        {
                            Print("Volume " + string(g_strategyStartLots[g_currentStrategyIndex]) + " is not a multiple of the minimal step SYMBOL_VOLUME_STEP=" + string(SymbolInfoDouble(g_chartSymbol, 36)));
                            volumeValid = false;
                        }
                        else
                        {
                            volumeValid = true;
                        }
                    }
                }

                accountLimitOrders = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
                if (accountLimitOrders == 0)
                {
                    limitOrdersOk = true;
                }
                else
                {
                    limitOrdersOk = MT4OrdersTotal() < accountLimitOrders;
                }
                if ((!(volumeValid) || !(limitOrdersOk)))
                {
                    return(false);
                }
                if (MarketInfo(g_chartSymbol, MODE_ASK) < orderPrice - g_freezeDistPrice && MarketInfo(g_chartSymbol, MODE_ASK) < orderPrice - g_minStopDistPrice)
                {
                    if (!(setSL_TP_After_Entry))
                    {
                        g_lastOrderResult = OrderSend(g_chartSymbol, 4, g_strategyStartLots[g_currentStrategyIndex], orderPrice, int(g_slippagePts * g_pipSize), stopLossPrice, takeProfitPrice, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Green);
                    }
                    else
                    {
                        g_lastOrderResult = OrderSend(g_chartSymbol, 4, g_strategyStartLots[g_currentStrategyIndex], orderPrice, int(g_slippagePts * g_pipSize), 0.0, 0.0, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Green);
                    }
                    if (g_lastOrderResult <= 0)
                    {
                        errorCode = MT4_LastError();
                        if (errorCode == 132)
                        {
                            ResetLastError();

                            do
                            {
                                Sleep(2500);
                                if (!(setSL_TP_After_Entry))
                                {
                                    errorCode = (int)(g_slippagePts * g_pipSize);
                                    g_lastOrderResult = OrderSend(g_chartSymbol, 4, g_strategyStartLots[g_currentStrategyIndex], orderPrice, errorCode, stopLossPrice, takeProfitPrice, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Green);
                                }
                                else
                                {
                                    g_lastOrderResult = OrderSend(g_chartSymbol, 4, g_strategyStartLots[g_currentStrategyIndex], orderPrice, int(g_slippagePts * g_pipSize), 0.0, 0.0, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Green);
                                }
                            } while (MT4_LastError() == 132);


                        }
                        Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order");
                    }
                    else
                    {
                        storedEntryPrice = baseEntryPrice;
                        orderTicket = g_lastOrderResult;
                        for (slotIdx = 0; slotIdx < 100; slotIdx = slotIdx + 1)
                        {
                            if (!(g_stopOrderTicketPrice[slotIdx][0] == 0.0))   continue;
                            g_stopOrderTicketPrice[slotIdx][0] = (double)orderTicket;
                            g_stopOrderTicketPrice[slotIdx][1] = storedEntryPrice;
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
bool PlaceSellStopEntry(int placeMode)
{
    bool      entryPriceSet;
    double    baseEntryPrice;
    double    orderPrice;
    double    stopLossPrice;
    double    takeProfitPrice;
    //----- -----
    bool       positionExists;
    int        posScanIdx;
    double     entryExtremePrice;
    int        dupScanIdx;
    bool       duplicatePending;
    int        pendingCount;
    int        pendingScanIdx;
    double     extremePendingPrice;
    int        extremeScanIdx;
    double     pendingAtTriggerPrice;
    int        overlapScanIdx;
    bool       pendingAtTrigger;
    bool       volumeValid;
    int        accountLimitOrders;
    bool       limitOrdersOk;
    int        errorCode;
    double     storedEntryPrice;
    long       orderTicket;
    int        slotIdx;

    if (!(AllowSellTrades))
    {
        return(false);
    }
    if (g_allowMultipleEntries)
    {
        positionExists = false;
    }
    else
    {
        positionExists = false;
        for (posScanIdx = 0; posScanIdx < MT4OrdersTotal(); posScanIdx = posScanIdx + 1)
        {
            if (OrderSelect(posScanIdx, 0, 0) != true || OrderType() != 1 || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol)   continue;
            positionExists = true;
            break;

        }
    }
    if (positionExists == true)
    {
        return(false);
    }
    if (g_maFilterEnabled && g_maFilterFast > g_maFilterSlow)
    {
        return(false);
    }
    if (placeMode == 1)
    {
        MT4FastEntryLow(g_entryTfPeriod);
        entryPriceSet = false;
        entryExtremePrice = g_entryLowPrice;
        duplicatePending = false;
        for (dupScanIdx = MT4OrdersTotal(); dupScanIdx >= 0; dupScanIdx = dupScanIdx - 1)
        {
            if (OrderSelect(dupScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(MathAbs(OrderOpenPrice() - (entryExtremePrice - g_sellEntryOffsetPips * g_pipSize)) < g_pendingDupTolerancePips * g_pipSize))   continue;
            duplicatePending = true;
            break;

        }
        if (!(duplicatePending))
        {
            pendingCount = 0;
            for (pendingScanIdx = MT4OrdersTotal(); pendingScanIdx >= 0; pendingScanIdx = pendingScanIdx - 1)
            {
                if (OrderSelect(pendingScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5)   continue;
                pendingCount = pendingCount + 1;

            }
            if (pendingCount == g_maxPendingOrders)
            {
                extremePendingPrice = 0.0;
                for (extremeScanIdx = MT4OrdersTotal(); extremeScanIdx >= 0; extremeScanIdx = extremeScanIdx - 1)
                {
                    if (OrderSelect(extremeScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(OrderOpenPrice() > extremePendingPrice))   continue;
                    extremePendingPrice = OrderOpenPrice();

                }
                if (g_entryLowPrice < extremePendingPrice)
                {
                    return(false);
                }
            }
            entryPriceSet = true;
            g_sellEntryPrice = NormalizeDouble(g_entryLowPrice, g_symbolDigits);
        }
        if (g_sellEntryPrice == 0.0)
        {
            return(false);
        }
        if (entryPriceSet)
        {
            g_nextOrderAnchorPrice = g_gridAnchorPips;
            baseEntryPrice = NormalizeDouble(g_sellEntryPrice - g_sellEntryOffsetPips * g_pipSize, g_symbolDigits);
            pendingAtTriggerPrice = baseEntryPrice;
            pendingAtTrigger = false;
            for (overlapScanIdx = MT4OrdersTotal(); overlapScanIdx >= 0; overlapScanIdx = overlapScanIdx - 1)
            {
                if (OrderSelect(overlapScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol || OrderType() != 5 || !(OrderOpenPrice() >= pendingAtTriggerPrice))   continue;
                pendingAtTrigger = true;
                break;

            }
            if (pendingAtTrigger)
            {
                return(false);
            }
            if (!(g_limitPendingToOne))
            {
                if (CheckMargin && AccountFreeMarginCheck(g_chartSymbol, 1, g_strategyStartLots[g_currentStrategyIndex]) <= 0.0)
                {
                    Print("Free margin not sufficient for setting order...");
                    return(false);
                }
                orderPrice = NormalizeDouble(baseEntryPrice - g_randomEntryOffsetPips * g_pipSize, g_symbolDigits);
                stopLossPrice = NormalizeDouble((g_stopLossPips + g_stopExtraPips) * g_pipSize + baseEntryPrice, g_symbolDigits);
                takeProfitPrice = NormalizeDouble(baseEntryPrice - g_takeProfitPips * g_pipSize, g_symbolDigits);
                if (g_strategyStartLots[g_currentStrategyIndex] < SymbolInfoDouble(g_chartSymbol, 34))
                {
                    Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=" + string(SymbolInfoDouble(g_chartSymbol, 34)));
                    volumeValid = false;
                }
                else
                {
                    if (g_strategyStartLots[g_currentStrategyIndex] > SymbolInfoDouble(g_chartSymbol, 35))
                    {
                        Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=" + string(SymbolInfoDouble(g_chartSymbol, 35)));
                        volumeValid = false;
                    }
                    else
                    {
                        if (MathAbs(NormalizeDouble(g_strategyStartLots[g_currentStrategyIndex] / SymbolInfoDouble(g_chartSymbol, 36), 0) * SymbolInfoDouble(g_chartSymbol, 36) - g_strategyStartLots[g_currentStrategyIndex]) > 0.0000001)
                        {
                            Print("Volume " + string(g_strategyStartLots[g_currentStrategyIndex]) + " is not a multiple of the minimal step SYMBOL_VOLUME_STEP=" + string(SymbolInfoDouble(g_chartSymbol, 36)));
                            volumeValid = false;
                        }
                        else
                        {
                            volumeValid = true;
                        }
                    }
                }

                accountLimitOrders = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
                if (accountLimitOrders == 0)
                {
                    limitOrdersOk = true;
                }
                else
                {
                    limitOrdersOk = MT4OrdersTotal() < accountLimitOrders;
                }
                if ((!(volumeValid) || !(limitOrdersOk)))
                {
                    return(false);
                }
                if (MarketInfo(g_chartSymbol, MODE_BID) > g_freezeDistPrice + orderPrice && MarketInfo(g_chartSymbol, MODE_BID) > g_minStopDistPrice + orderPrice)
                {
                    if (!(setSL_TP_After_Entry))
                    {
                        g_lastOrderResult = OrderSend(g_chartSymbol, 5, g_strategyStartLots[g_currentStrategyIndex], orderPrice, int(g_slippagePts * g_pipSize), stopLossPrice, takeProfitPrice, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Red);
                    }
                    else
                    {
                        g_lastOrderResult = OrderSend(g_chartSymbol, 5, g_strategyStartLots[g_currentStrategyIndex], orderPrice, int(g_slippagePts * g_pipSize), 0.0, 0.0, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Red);
                    }
                    if (g_lastOrderResult <= 0)
                    {
                        errorCode = MT4_LastError();
                        if (errorCode == 132)
                        {
                            ResetLastError();

                            do
                            {
                                Sleep(2500);
                                if (!(setSL_TP_After_Entry))
                                {
                                    errorCode = (int)(g_slippagePts * g_pipSize);
                                    g_lastOrderResult = OrderSend(g_chartSymbol, 5, g_strategyStartLots[g_currentStrategyIndex], orderPrice, errorCode, stopLossPrice, takeProfitPrice, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Red);
                                }
                                else
                                {
                                    g_lastOrderResult = OrderSend(g_chartSymbol, 5, g_strategyStartLots[g_currentStrategyIndex], orderPrice, int(g_slippagePts * g_pipSize), 0.0, 0.0, g_orderComment, g_curStrategyMagic, g_pendingOrderExpiry, Red);
                                }
                            } while (MT4_LastError() == 132);


                        }
                        Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting entry order");
                    }
                    else
                    {
                        storedEntryPrice = baseEntryPrice;
                        orderTicket = g_lastOrderResult;
                        for (slotIdx = 0; slotIdx < 100; slotIdx = slotIdx + 1)
                        {
                            if (!(g_stopOrderTicketPrice[slotIdx][0] == 0.0))   continue;
                            g_stopOrderTicketPrice[slotIdx][0] = (double)orderTicket;
                            g_stopOrderTicketPrice[slotIdx][1] = storedEntryPrice;
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
    bool      orderModified = false;
    bool      anyOrderTouched = false;
    double    prevVirtualSL;
    double    entryRefPrice;
    int       orderScanIdx;
    double    currentStopLoss;
    double    currentTakeProfit;
    long      orderTicket;
    double    orderOpenPrice;
    string    orderComment;
    double    orderLots;
    datetime  orderOpenTime;
    int       orderType;
    int       orderMagic;
    string    orderSymbol;
    double    stopOrderRefPrice;
    double    slippageDistance;
    bool      slippageDetected;
    bool      zoneRecoveryDone;
    double    zrHedgeCount;
    bool      zrOrderPlaced;
    double    zrNextLotSize;
    double    zrTargetPrice;
    double    zrRecoveryLevel;
    double    slTrailPartialLots;
    double    tpTrailPartialLots;
    int       trailElapsedSec;
    double    virtTrailPartialLots;
    //----- -----
    int        soDigits;
    long       soTicket;
    int        soScanIdx;
    double     soCachedPrice;
    double     soStorePrice;
    long       soStoreTicket;
    int        soStoreScanIdx;
    long       zrTicketRef;
    int        zrHedgeCountInt;
    int        zrScanIdx;
    string     zrScanComment;
    double     accountEquity;
    int        zrCloseAllScanIdx;
    long       zrBasketTicket;
    double     zrBasketProfit;
    int        zrBasketScanIdx;
    long       zrScanTicket;
    long       zrCloseTicket;
    int        zrCloseScanIdx;
    int        zrMaxStepsScanIdx;
    int        zrRecoveryScanIdx;
    string     zrRecoveryScanComment;
    long       virtSlTicket1;
    double     virtSlPips1;
    double     virtSlOpenPrice1;
    int        virtSlMode1;
    double     virtSlPrice1;
    bool       virtSlFound1;
    int        virtSlScanIdx1;
    int        virtSlStoreIdx1;
    double     virtSlUpdatePrice1;
    long       virtSlUpdateTicket1;
    int        virtSlUpdateIdx1;
    long       virtSlTicket2;
    double     virtSlPips2;
    double     virtSlOpenPrice2;
    int        virtSlMode2;
    double     virtSlPrice2;
    bool       virtSlFound2;
    int        virtSlScanIdx2;
    int        virtSlStoreIdx2;
    double     virtSlUpdatePrice2;
    long       virtSlUpdateTicket2;
    int        virtSlUpdateIdx2;

    // Pre-gate trade guard: preserve the strategy/lot state flow, but do not
    // emit modify/close/hedge requests before the tester/broker trade session opens.
    if (MarketInfo(g_chartSymbol, MODE_TRADEALLOWED) == 0.0)
    {
        return(false);
    }

    prevVirtualSL = 0.0;
    entryRefPrice = 0.0;
    for (orderScanIdx = 0; orderScanIdx < MT4OrdersTotal(); orderScanIdx++)
    {
        if (OrderSelect(orderScanIdx, 0, 0) == true)
        {
            orderModified = false;
            currentStopLoss = NormalizeDouble(OrderStopLoss(), g_symbolDigits);
            currentTakeProfit = NormalizeDouble(OrderTakeProfit(), g_symbolDigits);
            orderTicket = OrderTicket();
            orderOpenPrice = NormalizeDouble(OrderOpenPrice(), g_symbolDigits);
            orderComment = OrderComment();
            orderLots = OrderLots();
            orderOpenTime = OrderOpenTime();
            orderType = OrderType();
            orderMagic = OrderMagicNumber();
            orderSymbol = OrderSymbol();
            if ((orderType == 4 || orderType == 2) && g_orderMgmtMode == 2 && (g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && orderSymbol == g_chartSymbol)) && (orderMagic == g_manualMagicNumber || g_manualMagicNumber == 0) && (orderComment == g_manualCommentFilter || g_manualCommentFilter == ""))
            {
                if ((currentStopLoss == 0.0 || currentStopLoss == 0.0))
                {
                    currentStopLoss = NormalizeDouble(orderOpenPrice - g_stopLossPips * g_pipSize, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
                if ((currentTakeProfit == 0.0 || currentTakeProfit == 0.0))
                {
                    currentTakeProfit = NormalizeDouble(g_takeProfitPips * g_pipSize + orderOpenPrice, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
            }
            if (orderType == 0 && ((orderMagic == g_curStrategyMagic && g_orderMgmtMode == 1 && orderSymbol == g_chartSymbol) || (g_orderMgmtMode == 2 && (g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && orderSymbol == g_chartSymbol)) && (orderMagic == g_manualMagicNumber || g_manualMagicNumber == 0) && (orderComment == g_manualCommentFilter || g_manualCommentFilter == ""))))
            {
                if ((currentStopLoss == 0.0 || currentStopLoss == 0.0))
                {
                    currentStopLoss = NormalizeDouble(orderOpenPrice - g_stopLossPips * g_pipSize, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
                if ((currentTakeProfit == 0.0 || currentTakeProfit == 0.0))
                {
                    currentTakeProfit = NormalizeDouble(g_takeProfitPips * g_pipSize + orderOpenPrice, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
                if (g_fakeoutEnableM1 && MT4BearishFakeout(g_fakeoutTfM1, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableM5 && MT4BearishFakeout(g_fakeoutTfM5, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableM15 && MT4BearishFakeout(g_fakeoutTfM15, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableM30 && MT4BearishFakeout(g_fakeoutTfM30, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableH1 && MT4BearishFakeout(g_fakeoutTfH1, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), 0, Red);
                    Print("closing candle confirmation");
                }
                g_nextOrderAnchorPrice = g_gridAnchorPips;
                if (g_orderTimeoutMin > 0 && TimeCurrent() > orderOpenTime + g_orderTimeoutMin * 60)
                {
                    g_nextOrderAnchorPrice = g_gridTimeoutAnchorPips;
                }
                soDigits = g_symbolDigits;
                soTicket = orderTicket;
                soCachedPrice = 0.0;
                for (soScanIdx = 0; soScanIdx < 100; soScanIdx = soScanIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[soScanIdx][0] == soTicket))   continue;
                    soCachedPrice = g_stopOrderTicketPrice[soScanIdx][1];
                    break;

                }
                stopOrderRefPrice = NormalizeDouble(soCachedPrice, soDigits);
                if (stopOrderRefPrice == 0.0)
                {
                    soStorePrice = orderOpenPrice;
                    soStoreTicket = orderTicket;
                    for (soStoreScanIdx = 0; soStoreScanIdx < 100; soStoreScanIdx = soStoreScanIdx + 1)
                    {
                        if (!(g_stopOrderTicketPrice[soStoreScanIdx][0] == 0.0))   continue;
                        g_stopOrderTicketPrice[soStoreScanIdx][0] = (double)soStoreTicket;
                        g_stopOrderTicketPrice[soStoreScanIdx][1] = soStorePrice;
                        break;

                    }
                    stopOrderRefPrice = orderOpenPrice;
                }
                else
                {
                    stopOrderRefPrice = stopOrderRefPrice - g_trailRefSlippagePips * g_pipSize;
                }
                slippageDistance = orderOpenPrice - stopOrderRefPrice;
                slippageDetected = false;
                if (stopOrderRefPrice > 0.0 - g_trailRefSlippagePips * g_pipSize && slippageDistance > g_slippagePts * g_pipSize)
                {
                    slippageDetected = true;
                    if (g_trailMode == 2)
                    {
                        g_nextOrderAnchorPrice = -1000.0;
                        Print("Slippage control active");
                    }
                }
                if (g_trailUseFillPrice)
                {
                    entryRefPrice = stopOrderRefPrice;
                }
                else
                {
                    entryRefPrice = orderOpenPrice;
                }
                // EX5 behavior: maximum-loss is a virtual close boundary here.
                // Do not rewrite the broker SL on every management pass.
                if (MarketInfo(g_chartSymbol, MODE_BID) < orderOpenPrice - (g_stopLossPips + g_stopExtraPips) * g_pipSize - g_curSpread)
                {
                    RefreshRates();
                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_curSpread, Red);
                    return(true);
                }
                zoneRecoveryDone = false;
                if (g_zrEnabled)
                {
                    zrTicketRef = orderTicket;
                    zrHedgeCountInt = 0;
                    for (zrScanIdx = MT4OrdersTotal(); zrScanIdx >= 0; zrScanIdx = zrScanIdx - 1)
                    {
                        if (OrderSelect(zrScanIdx, 0, 0) != true || OrderMagicNumber() != g_zrMagicBuy || OrderSymbol() != g_chartSymbol)   continue;
                        zrScanComment = OrderComment();
                        if (zrScanComment != IntegerToString(zrTicketRef, 0, 32))   continue;
                        zrHedgeCountInt = zrHedgeCountInt + 1;

                    }
                    zrHedgeCount = zrHedgeCountInt;
                    zrOrderPlaced = false;
                    if (!(g_buyOrderSeen))
                    {
                        g_buyOrderSeen = true;
                        g_buyFirstModDone = 0;
                    }
                    if (zrHedgeCount == 0.0)
                    {
                        g_buyFirstModDone = 0;
                    }
                    if (MathFloor(zrHedgeCount / 2.0) == zrHedgeCount / 2.0)
                    {
                        g_buyFirstModDone = 0;
                    }
                    else
                    {
                        g_buyFirstModDone = 1;
                    }
                    if (g_buyOrderSeen)
                    {
                        if (zrHedgeCount > 0.0)
                        {
                            accountEquity = AccountEquity();
                            if (accountEquity > AccountBalance() + g_zrTargetProfit)
                            {
                                for (zrCloseAllScanIdx = MT4OrdersTotal(); zrCloseAllScanIdx >= 0; zrCloseAllScanIdx = zrCloseAllScanIdx - 1)
                                {
                                    if (OrderSelect(zrCloseAllScanIdx, 0, 0) != true)   continue;

                                    if ((OrderMagicNumber() != g_curStrategyMagic && OrderMagicNumber() != g_zrMagicSell && OrderMagicNumber() != g_zrMagicBuy))   continue;

                                    if (OrderType() == 0)
                                    {
                                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                    }
                                    if (OrderType() != 1)   continue;
                                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                }
                            }
                        }
                        if (zrHedgeCount > 0.0)
                        {
                            zrBasketTicket = orderTicket;
                            zrBasketProfit = 0.0;
                            for (zrBasketScanIdx = MT4OrdersTotal(); zrBasketScanIdx >= 0; zrBasketScanIdx = zrBasketScanIdx - 1)
                            {
                                if (OrderSelect(zrBasketScanIdx, 0, 0) != true)   continue;
                                zrScanTicket = OrderTicket();
                                if (zrScanTicket != zrBasketTicket)
                                {
                                    zrScanComment = OrderComment();
                                    if (zrScanComment != IntegerToString(zrBasketTicket, 0, 32))   continue;
                                }
                                zrBasketProfit = zrBasketProfit + OrderProfit();

                            }
                            if (zrBasketProfit > g_zrTargetProfit)
                            {
                                zrCloseTicket = orderTicket;
                                for (zrCloseScanIdx = MT4OrdersTotal(); zrCloseScanIdx >= 0; zrCloseScanIdx = zrCloseScanIdx - 1)
                                {
                                    if (OrderSelect(zrCloseScanIdx, 0, 0) != true)   continue;

                                    if (OrderMagicNumber() == g_curStrategyMagic && OrderTicket() == zrCloseTicket)
                                    {
                                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), 3, Red);
                                    }
                                    if (OrderMagicNumber() != g_zrMagicBuy)   continue;
                                    zrScanComment = OrderComment();
                                    if (zrScanComment != IntegerToString(zrCloseTicket, 0, 32))   continue;

                                    if (OrderType() == 0)
                                    {
                                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                    }
                                    if (OrderType() != 1)   continue;
                                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                }
                                g_buyOrderSeen = false;
                                zoneRecoveryDone = true;
                            }
                        }
                        else
                        {
                            zrNextLotSize = orderLots * g_zrLotMultiplier;
                            if (g_zrLotMode == 2)
                            {
                                zrNextLotSize = (zrHedgeCount + 1.0) * orderLots + orderLots;
                            }
                            if (g_zrLotMode == 3)
                            {
                                zrNextLotSize = orderLots * (MathPow(g_zrLotMultiplier, zrHedgeCount + 1.0));
                            }
                            if (g_buyFirstModDone == 0)
                            {
                                zrTargetPrice = zrHedgeCount * g_zrStepDist * g_pipSize + (stopOrderRefPrice - g_zrZoneSize * g_pipSize);
                                if (zrTargetPrice > stopOrderRefPrice - g_zrMinTargetDist * g_pipSize)
                                {
                                    zrTargetPrice = stopOrderRefPrice - g_zrMinTargetDist * g_pipSize;
                                }
                                if (MarketInfo(g_chartSymbol, MODE_BID) < zrTargetPrice)
                                {
                                    if (zrHedgeCount >= g_zrMaxRecoverySteps)
                                    {
                                        for (zrMaxStepsScanIdx = MT4OrdersTotal(); zrMaxStepsScanIdx >= 0; zrMaxStepsScanIdx = zrMaxStepsScanIdx - 1)
                                        {
                                            if (OrderSelect(zrMaxStepsScanIdx, 0, 0) != true)   continue;

                                            if (OrderMagicNumber() == g_curStrategyMagic && OrderTicket() == orderTicket)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), 3, Red);
                                            }
                                            if (OrderMagicNumber() != g_zrMagicBuy)   continue;
                                            zrScanComment = OrderComment();
                                            if (zrScanComment != IntegerToString(orderTicket, 0, 32))   continue;

                                            if (OrderType() == 0)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                            }
                                            if (OrderType() != 1)   continue;
                                            OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                        }
                                    }
                                    else
                                    {
                                        OrderSend(g_chartSymbol, 1, zrNextLotSize, MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, 0.0, 0.0, IntegerToString(orderTicket, 0, 32), g_zrMagicBuy, 0, Green);
                                        g_buyFirstModDone = 1;
                                        zrOrderPlaced = true;
                                    }
                                }
                            }
                            else
                            {
                                zrRecoveryLevel = stopOrderRefPrice;
                                if (MarketInfo(g_chartSymbol, MODE_ASK) > stopOrderRefPrice)
                                {
                                    if (zrHedgeCount >= g_zrMaxRecoverySteps)
                                    {
                                        for (zrRecoveryScanIdx = MT4OrdersTotal(); zrRecoveryScanIdx >= 0; zrRecoveryScanIdx = zrRecoveryScanIdx - 1)
                                        {
                                            if (OrderSelect(zrRecoveryScanIdx, 0, 0) != true)   continue;

                                            if (OrderMagicNumber() == g_curStrategyMagic && OrderTicket() == orderTicket)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), 3, Red);
                                            }
                                            if (OrderMagicNumber() != g_zrMagicBuy)   continue;
                                            zrRecoveryScanComment = OrderComment();
                                            if (zrRecoveryScanComment != IntegerToString(orderTicket, 0, 32))   continue;

                                            if (OrderType() == 0)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                            }
                                            if (OrderType() != 1)   continue;
                                            OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                        }
                                    }
                                    else
                                    {
                                        OrderSend(g_chartSymbol, 0, zrNextLotSize, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, 0.0, 0.0, IntegerToString(orderTicket, 0, 32), g_zrMagicBuy, 0, Green);
                                        g_buyFirstModDone = 0;
                                        zrOrderPlaced = true;
                                    }
                                }
                            }
                        }
                    }
                    if ((zrHedgeCount > 0.0 || zrOrderPlaced))
                    {
                        zoneRecoveryDone = true;
                    }
                }
                if (!(zoneRecoveryDone))
                {
                    if ((g_profitCloseMode == 1 || (g_profitCloseMode != 3 && g_profitCloseMode != 2)))
                    {
                        virtSlTicket1 = orderTicket;
                        virtSlPips1 = g_stopLossPips;
                        virtSlOpenPrice1 = orderOpenPrice;
                        virtSlMode1 = 1;
                        virtSlPrice1 = 0.0;
                        virtSlFound1 = false;
                        for (virtSlScanIdx1 = 0; virtSlScanIdx1 < g_virtSLCacheSize; virtSlScanIdx1 = virtSlScanIdx1 + 1)
                        {
                            if (g_virtSLCache[virtSlScanIdx1][0] == virtSlTicket1)
                            {
                                virtSlPrice1 = g_virtSLCache[virtSlScanIdx1][1];
                                virtSlFound1 = true;
                                break;
                            }
                        }
                        if (!(virtSlFound1))
                        {
                            if (virtSlMode1 == 1)
                            {
                                virtSlPrice1 = NormalizeDouble(virtSlOpenPrice1 - virtSlPips1 * g_pipSize, g_symbolDigits);
                            }
                            if (virtSlMode1 == 2)
                            {
                                virtSlPrice1 = NormalizeDouble(virtSlPips1 * g_pipSize + virtSlOpenPrice1, g_symbolDigits);
                            }
                            for (virtSlStoreIdx1 = 0; virtSlStoreIdx1 < g_virtSLCacheSize; virtSlStoreIdx1 = virtSlStoreIdx1 + 1)
                            {
                                if (g_virtSLCache[virtSlStoreIdx1][0] == 0.0)
                                {
                                    g_virtSLCache[virtSlStoreIdx1][0] = (double)virtSlTicket1;
                                    g_virtSLCache[virtSlStoreIdx1][1] = virtSlPrice1;
                                    break;
                                }
                            }
                        }
                        g_virtualSLPrice = virtSlPrice1;
                        prevVirtualSL = g_virtualSLPrice;
                        if (MarketInfo(g_chartSymbol, MODE_BID) < prevVirtualSL)
                        {
                            Print("Closing with virtual SL");
                            Print("Virtual_SL: ", DoubleToString(prevVirtualSL, g_symbolDigits));
                            Print("Last Bid: ", DoubleToString(MarketInfo(g_chartSymbol, MODE_BID), g_symbolDigits));
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        if (g_timeTrailDelayMin > 0.0 && TimeCurrent() >= orderOpenTime + g_timeTrailDelaySec && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_timeTrailDistancePips * g_pipSize + (currentStopLoss + g_symbolPoint), g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            currentStopLoss = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_BID) - g_timeTrailDistancePips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TrailSL_after_X_Minutes_size_ loss.  Trying again!");
                                }
                                orderModified = true;
                            }
                        }
                        if (g_profitTrailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble((g_profitTrailDistancePips + g_profitTrailBufferPips) * g_pipSize + (currentStopLoss + g_symbolPoint), g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_trailActivationPips * g_pipSize + orderOpenPrice, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice && currentStopLoss < NormalizeDouble(g_profitTrailCapPips * g_pipSize + orderOpenPrice, g_symbolDigits))
                        {
                            currentStopLoss = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_BID) - g_profitTrailDistancePips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_stop_ loss.  Trying again!");
                                }
                                else
                                {
                                    slTrailPartialLots = NormalizeDouble(g_partialClosePct / 100.0 * g_strategyStartLots[g_currentStrategyIndex], 2);
                                    if (slTrailPartialLots < orderLots && slTrailPartialLots >= MarketInfo(g_chartSymbol, MODE_LOTSTEP))
                                    {
                                        OrderClose(orderTicket, slTrailPartialLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                        return(true);
                                    }
                                }
                                orderModified = true;
                            }
                        }
                        if (g_tpTrailPips > 0.0 && MarketInfo(g_chartSymbol, MODE_ASK) < NormalizeDouble(currentTakeProfit - g_symbolPoint - g_tpTrailPips * g_pipSize, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_ASK) < NormalizeDouble(entryRefPrice - g_tpTrailMinGapPips * g_pipSize, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            currentTakeProfit = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_BID) + g_tpTrailPips * g_pipSize, g_symbolDigits);
                            if (currentTakeProfit > MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TP.  Trying again!");
                                }
                                else
                                {
                                    tpTrailPartialLots = NormalizeDouble(g_partialClosePct / 100.0 * g_strategyStartLots[g_currentStrategyIndex], 2);
                                    if (tpTrailPartialLots < orderLots && tpTrailPartialLots >= SymbolInfoDouble(g_chartSymbol, 34))
                                    {
                                        OrderClose(orderTicket, tpTrailPartialLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                        return(true);
                                    }
                                }
                                orderModified = true;
                            }
                        }
                        if (slippageDetected && g_trailMode == 1 && g_trailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_trailDistancePips * g_pipSize + (currentStopLoss + g_symbolPoint), g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_trailStopBufferPips * g_pipSize + stopOrderRefPrice, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice && currentStopLoss < NormalizeDouble(g_trailCapAboveEntryPips * g_pipSize + orderOpenPrice, g_symbolDigits))
                        {
                            currentStopLoss = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_BID) - g_trailDistancePips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting Slip TL.  Trying again!");
                                }
                                else
                                {
                                    Print("Slippage control active");
                                }
                                orderModified = true;
                            }
                        }
                        if (g_hlFractalRightBars > 0 && g_hlFractalLeftBars >= 0 && UseHL_TrailingSL && g_buyTrailStopLevel[g_currentStrategyIndex] > NormalizeDouble(currentStopLoss + g_minStopDistPrice + g_symbolPoint, g_symbolDigits) && g_buyTrailStopLevel[g_currentStrategyIndex] < MarketInfo(g_chartSymbol, MODE_BID) - g_hlTrailMinGapPips * g_pipSize && (g_buyTrailStopLevel[g_currentStrategyIndex] < orderOpenPrice || !(g_trailOnlyTighten)) && g_buyTrailStopLevel[g_currentStrategyIndex] < NormalizeDouble(MarketInfo(g_chartSymbol, MODE_BID) - g_hlTrailBrokerGapPips * g_pipSize - g_minStopDistPrice - g_symbolPoint, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            currentStopLoss = NormalizeDouble(g_buyTrailStopLevel[g_currentStrategyIndex], g_symbolDigits);
                            if (currentStopLoss < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when modifying stoploss");
                                }
                                orderModified = true;
                            }
                        }
                        if (g_beTriggerPips > 0.0 && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_beTriggerPips * g_pipSize + orderOpenPrice, g_symbolDigits) && NormalizeDouble(g_beExtraPips * g_pipSize + orderOpenPrice, g_symbolDigits) > currentStopLoss + g_symbolPoint && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_beExtraPips * g_pipSize + orderOpenPrice + g_minStopDistPrice, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            currentStopLoss = NormalizeDouble(g_beExtraPips * g_pipSize + orderOpenPrice, g_symbolDigits);
                            if (currentStopLoss < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!");
                                }
                                orderModified = true;
                            }
                        }
                        if (!(orderModified) && (g_partialCloseMode == 1 || (g_partialCloseMode == 2 && g_gridSpacingPips * g_pipSize + currentStopLoss <= g_gridMaxSpacingPips * g_pipSize + (entryRefPrice + g_curSpread))))
                        {
                            g_ordersSinceAnchor++;
                            if (MarketInfo(g_chartSymbol, MODE_BID) > g_gridSpacingPips * g_pipSize + currentStopLoss + g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice && (g_gridAnchorPips == 0.0 || MarketInfo(g_chartSymbol, MODE_BID) > g_nextOrderAnchorPrice * g_pipSize + entryRefPrice) && g_ordersSinceAnchor >= g_gridMaxOrdersPerAnchor && NormalizeDouble(g_gridSpacingPips * g_pipSize + currentStopLoss, g_symbolDigits) > currentStopLoss)
                            {
                                g_ordersSinceAnchor = 0;
                                currentStopLoss = NormalizeDouble(g_gridSpacingPips * g_pipSize + currentStopLoss, g_symbolDigits);
                                OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                orderModified = true;
                            }
                        }
                        g_virtualSLPrice = currentStopLoss;
                        if (MarketInfo(g_chartSymbol, MODE_BID) < currentStopLoss)
                        {
                            Print("Closing with virtual SL");
                            Print("Virtual_SL: ", DoubleToString(currentStopLoss, g_symbolDigits));
                            Print("Last Bid: ", DoubleToString(MarketInfo(g_chartSymbol, MODE_BID), g_symbolDigits));
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        if (NormalizeDouble(prevVirtualSL, g_symbolDigits) != NormalizeDouble(g_virtualSLPrice, g_symbolDigits))
                        {
                            virtSlUpdatePrice1 = NormalizeDouble(g_virtualSLPrice, g_symbolDigits);
                            virtSlUpdateTicket1 = orderTicket;
                            for (virtSlUpdateIdx1 = 0; virtSlUpdateIdx1 < g_virtSLCacheSize; virtSlUpdateIdx1 = virtSlUpdateIdx1 + 1)
                            {
                                if (g_virtSLCache[virtSlUpdateIdx1][0] == virtSlUpdateTicket1)
                                {
                                    g_virtSLCache[virtSlUpdateIdx1][1] = virtSlUpdatePrice1;
                                    break;
                                }
                            }
                        }
                        if (orderModified && g_returnAfterOrderModify)
                        {
                            return(true);
                        }
                    }
                    if ((g_profitCloseMode == 2 || g_profitCloseMode == 3))
                    {
                        virtSlTicket2 = orderTicket;
                        virtSlPips2 = g_stopLossPips;
                        virtSlOpenPrice2 = orderOpenPrice;
                        virtSlMode2 = 1;
                        virtSlPrice2 = 0.0;
                        virtSlFound2 = false;
                        for (virtSlScanIdx2 = 0; virtSlScanIdx2 < g_virtSLCacheSize; virtSlScanIdx2 = virtSlScanIdx2 + 1)
                        {
                            if (g_virtSLCache[virtSlScanIdx2][0] == virtSlTicket2)
                            {
                                virtSlPrice2 = g_virtSLCache[virtSlScanIdx2][1];
                                virtSlFound2 = true;
                                break;
                            }
                        }
                        if (!(virtSlFound2))
                        {
                            if (virtSlMode2 == 1)
                            {
                                virtSlPrice2 = NormalizeDouble(virtSlOpenPrice2 - virtSlPips2 * g_pipSize, g_symbolDigits);
                            }
                            if (virtSlMode2 == 2)
                            {
                                virtSlPrice2 = NormalizeDouble(virtSlPips2 * g_pipSize + virtSlOpenPrice2, g_symbolDigits);
                            }
                            for (virtSlStoreIdx2 = 0; virtSlStoreIdx2 < g_virtSLCacheSize; virtSlStoreIdx2 = virtSlStoreIdx2 + 1)
                            {
                                if (g_virtSLCache[virtSlStoreIdx2][0] == 0.0)
                                {
                                    g_virtSLCache[virtSlStoreIdx2][0] = (double)virtSlTicket2;
                                    g_virtSLCache[virtSlStoreIdx2][1] = virtSlPrice2;
                                    break;
                                }
                            }
                        }
                        g_virtualSLPrice = virtSlPrice2;
                        prevVirtualSL = g_virtualSLPrice;
                        if (MarketInfo(g_chartSymbol, MODE_BID) <= prevVirtualSL)
                        {
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        trailElapsedSec = (int)(TimeCurrent() - g_lastTrailOrderTime);
                        if (trailElapsedSec >= g_trailModifyMinSec)
                        {
                            if (NormalizeDouble(g_virtualSLPrice, g_symbolDigits) > currentStopLoss + g_symbolPoint)
                            {
                                OrderModify(orderTicket, orderOpenPrice, NormalizeDouble(g_virtualSLPrice, g_symbolDigits), currentTakeProfit, 0, 0xFFFFFFFF);
                            }
                            g_lastTrailOrderTime = TimeCurrent();
                        }
                        if (g_timeTrailDelayMin > 0.0 && TimeCurrent() >= orderOpenTime + g_timeTrailDelaySec && MarketInfo(g_chartSymbol, MODE_BID) > g_timeTrailDistancePips * g_pipSize + (g_virtualSLPrice + g_symbolPoint) && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            orderModified = true;
                            g_virtualSLPrice = MarketInfo(g_chartSymbol, MODE_BID) - g_timeTrailDistancePips * g_pipSize;
                        }
                        if (g_profitTrailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_BID) > (g_profitTrailDistancePips + g_profitTrailBufferPips) * g_pipSize + (g_virtualSLPrice + g_symbolPoint) && MarketInfo(g_chartSymbol, MODE_BID) > g_trailActivationPips * g_pipSize + entryRefPrice && g_virtualSLPrice < g_profitTrailCapPips * g_pipSize + orderOpenPrice)
                        {
                            orderModified = true;
                            g_virtualSLPrice = MarketInfo(g_chartSymbol, MODE_BID) - g_profitTrailDistancePips * g_pipSize;
                            virtTrailPartialLots = NormalizeDouble(g_partialClosePct / 100.0 * g_strategyStartLots[g_currentStrategyIndex], 2);
                            if (virtTrailPartialLots < orderLots && virtTrailPartialLots >= MarketInfo(g_chartSymbol, MODE_LOTSTEP))
                            {
                                OrderClose(orderTicket, virtTrailPartialLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                return(true);
                            }
                        }
                        if (slippageDetected && g_trailMode == 1 && g_trailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_BID) > g_trailDistancePips * g_pipSize + (g_virtualSLPrice + g_symbolPoint) && MarketInfo(g_chartSymbol, MODE_BID) > g_trailStopBufferPips * g_pipSize + stopOrderRefPrice && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice && g_virtualSLPrice < g_trailCapAboveEntryPips * g_pipSize + orderOpenPrice)
                        {
                            Print("Slippage control active");
                            orderModified = true;
                            g_virtualSLPrice = MarketInfo(g_chartSymbol, MODE_BID) - g_trailDistancePips * g_pipSize;
                        }
                        if (g_hlFractalRightBars > 0 && g_hlFractalLeftBars >= 0 && g_buyTrailStopLevel[g_currentStrategyIndex] > g_virtualSLPrice + g_minStopDistPrice + g_symbolPoint && (g_buyTrailStopLevel[g_currentStrategyIndex] < orderOpenPrice || !(g_trailOnlyTighten)) && g_buyTrailStopLevel[g_currentStrategyIndex] < MarketInfo(g_chartSymbol, MODE_BID) - g_hlTrailBrokerGapPips * g_pipSize - g_minStopDistPrice - g_symbolPoint && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            g_virtualSLPrice = g_buyTrailStopLevel[g_currentStrategyIndex];
                            orderModified = true;
                        }
                        if (g_beTriggerPips > 0.0 && g_profitCloseMode == 3 && MarketInfo(g_chartSymbol, MODE_BID) > g_beTriggerPips * g_pipSize + orderOpenPrice && g_beExtraPips * g_pipSize + orderOpenPrice > currentStopLoss + g_symbolPoint && MarketInfo(g_chartSymbol, MODE_BID) > g_beExtraPips * g_pipSize + orderOpenPrice + g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice && NormalizeDouble(g_beExtraPips * g_pipSize + orderOpenPrice, g_symbolDigits) > OrderStopLoss())
                        {
                            g_virtualSLPrice = NormalizeDouble(g_beExtraPips * g_pipSize + orderOpenPrice, g_symbolDigits);
                            g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, g_virtualSLPrice, currentTakeProfit, 0, 0xFFFFFFFF);
                            if (g_lastOrderResult <= 0)
                            {
                                Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!");
                            }
                            orderModified = true;
                        }
                        if (g_beTriggerPips > 0.0 && g_profitCloseMode == 2 && MarketInfo(g_chartSymbol, MODE_BID) > g_beTriggerPips * g_pipSize + orderOpenPrice && g_beExtraPips * g_pipSize + orderOpenPrice > g_virtualSLPrice + g_symbolPoint && MarketInfo(g_chartSymbol, MODE_BID) > g_beExtraPips * g_pipSize + orderOpenPrice + g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice)
                        {
                            g_virtualSLPrice = g_beExtraPips * g_pipSize + orderOpenPrice;
                            orderModified = true;
                        }
                        if (!(orderModified) && (g_partialCloseMode == 1 || (g_partialCloseMode == 2 && g_gridSpacingPips * g_pipSize + g_virtualSLPrice <= g_gridMaxSpacingPips * g_pipSize + (entryRefPrice + g_curSpread))))
                        {
                            g_ordersSinceAnchor++;
                            if (MarketInfo(g_chartSymbol, MODE_BID) > g_gridSpacingPips * g_pipSize + g_virtualSLPrice + g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_BID) < currentTakeProfit - g_freezeDistPrice && (g_gridAnchorPips == 0.0 || MarketInfo(g_chartSymbol, MODE_BID) > g_nextOrderAnchorPrice * g_pipSize + entryRefPrice) && g_ordersSinceAnchor >= g_gridMaxOrdersPerAnchor)
                            {
                                g_ordersSinceAnchor = 0;
                                g_virtualSLPrice = g_gridSpacingPips * g_pipSize + g_virtualSLPrice;
                                orderModified = true;
                            }
                        }
                        if (MarketInfo(g_chartSymbol, MODE_BID) <= g_virtualSLPrice)
                        {
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        if (NormalizeDouble(prevVirtualSL, g_symbolDigits) != NormalizeDouble(g_virtualSLPrice, g_symbolDigits))
                        {
                            virtSlUpdatePrice2 = NormalizeDouble(g_virtualSLPrice, g_symbolDigits);
                            virtSlUpdateTicket2 = orderTicket;
                            for (virtSlUpdateIdx2 = 0; virtSlUpdateIdx2 < g_virtSLCacheSize; virtSlUpdateIdx2 = virtSlUpdateIdx2 + 1)
                            {
                                if (g_virtSLCache[virtSlUpdateIdx2][0] == virtSlUpdateTicket2)
                                {
                                    g_virtSLCache[virtSlUpdateIdx2][1] = virtSlUpdatePrice2;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            if (orderModified)
            {
                anyOrderTouched = true;
            }
        }
        if (orderModified)
        {
            anyOrderTouched = true;
        }
    }
    return(anyOrderTouched);
}
//ManageBuyPositions <<==--------   --------
// ManageSellPositions —— 空头持仓管理（ManageBuyPositions 的对称实现）
bool ManageSellPositions()
{
    bool      orderModified = false;
    bool      anyOrderTouched = false;
    double    prevVirtualSL;
    double    entryRefPrice;
    int       orderScanIdx;
    double    currentStopLoss;
    double    currentTakeProfit;
    long      orderTicket;
    double    orderOpenPrice;
    string    orderComment;
    double    orderLots;
    datetime  orderOpenTime;
    int       orderType;
    int       orderMagic;
    string    orderSymbol;
    double    stopOrderRefPrice;
    double    slippageDistance;
    bool      slippageDetected;
    bool      zoneRecoveryDone;
    double    zrHedgeCount;
    bool      zrOrderPlaced;
    double    zrNextLotSize;
    double    zrRecoveryLevel;
    double    zrTargetPrice;
    double    slTrailPartialLots;
    double    tpTrailPartialLots;
    int       trailElapsedSec;
    double    virtTrailPartialLots;
    //----- -----
    int        soDigits;
    long       soTicket;
    int        soScanIdx;
    double     soCachedPrice;
    double     soStorePrice;
    long       soStoreTicket;
    int        soStoreScanIdx;
    long       zrTicketRef;
    int        zrHedgeCountInt;
    int        zrScanIdx;
    string     zrScanComment;
    double     accountEquity;
    int        zrCloseAllScanIdx;
    long       zrBasketTicket;
    double     zrBasketProfit;
    int        zrBasketScanIdx;
    long       zrScanTicket;
    long       zrCloseTicket;
    int        zrCloseScanIdx;
    int        zrMaxStepsScanIdx;
    int        zrRecoveryScanIdx;
    string     zrRecoveryScanComment;
    long       virtSlTicket1;
    double     virtSlPips1;
    double     virtSlOpenPrice1;
    int        virtSlMode1;
    double     virtSlPrice1;
    bool       virtSlFound1;
    int        virtSlScanIdx1;
    int        virtSlStoreIdx1;
    double     virtSlUpdatePrice1;
    long       virtSlUpdateTicket1;
    int        virtSlUpdateIdx1;
    long       virtSlTicket2;
    double     virtSlPips2;
    double     virtSlOpenPrice2;
    int        virtSlMode2;
    double     virtSlPrice2;
    bool       virtSlFound2;
    int        virtSlScanIdx2;
    int        virtSlStoreIdx2;
    double     virtSlUpdatePrice2;
    long       virtSlUpdateTicket2;
    int        virtSlUpdateIdx2;

    // Same pre-gate protection as ManageBuyPositions().
    if (MarketInfo(g_chartSymbol, MODE_TRADEALLOWED) == 0.0)
    {
        return(false);
    }

    prevVirtualSL = 0.0;
    entryRefPrice = 0.0;
    for (orderScanIdx = 0; orderScanIdx < MT4OrdersTotal(); orderScanIdx++)
    {
        if (OrderSelect(orderScanIdx, 0, 0) == true)
        {
            orderModified = false;
            currentStopLoss = NormalizeDouble(OrderStopLoss(), g_symbolDigits);
            currentTakeProfit = NormalizeDouble(OrderTakeProfit(), g_symbolDigits);
            orderTicket = OrderTicket();
            orderOpenPrice = NormalizeDouble(OrderOpenPrice(), g_symbolDigits);
            orderComment = OrderComment();
            orderLots = OrderLots();
            orderOpenTime = OrderOpenTime();
            orderType = OrderType();
            orderMagic = OrderMagicNumber();
            orderSymbol = OrderSymbol();
            if ((orderType == 5 || orderType == 3) && g_orderMgmtMode == 2 && (g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && orderSymbol == g_chartSymbol)) && (orderMagic == g_manualMagicNumber || g_manualMagicNumber == 0) && (orderComment == g_manualCommentFilter || g_manualCommentFilter == ""))
            {
                if ((currentStopLoss == 0.0 || currentStopLoss == 0.0))
                {
                    currentStopLoss = NormalizeDouble(g_stopLossPips * g_pipSize + orderOpenPrice, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
                if ((currentTakeProfit == 0.0 || currentTakeProfit == 0.0))
                {
                    currentTakeProfit = NormalizeDouble(orderOpenPrice - g_takeProfitPips * g_pipSize, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
            }
            if (orderType == 1 && ((orderMagic == g_curStrategyMagic && g_orderMgmtMode == 1 && orderSymbol == g_chartSymbol) || (g_orderMgmtMode == 2 && (g_manualSymbolMode == 0 || (g_manualSymbolMode == 1 && orderSymbol == g_chartSymbol)) && (orderMagic == g_manualMagicNumber || g_manualMagicNumber == 0) && (orderComment == g_manualCommentFilter || g_manualCommentFilter == ""))))
            {
                if ((currentStopLoss == 0.0 || currentStopLoss == 0.0))
                {
                    currentStopLoss = NormalizeDouble(g_stopLossPips * g_pipSize + orderOpenPrice, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
                if ((currentTakeProfit == 0.0 || currentTakeProfit == 0.0))
                {
                    currentTakeProfit = NormalizeDouble(orderOpenPrice - g_takeProfitPips * g_pipSize, g_symbolDigits);
                    OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, Green);
                }
                if (g_fakeoutEnableM1 && MT4BullishFakeout(g_fakeoutTfM1, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableM5 && MT4BullishFakeout(g_fakeoutTfM5, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableM15 && MT4BullishFakeout(g_fakeoutTfM15, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableM30 && MT4BullishFakeout(g_fakeoutTfM30, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), 0, Red);
                    Print("closing candle confirmation");
                }
                if (g_fakeoutEnableH1 && MT4BullishFakeout(g_fakeoutTfH1, g_fakeoutBarsBack, orderOpenTime, orderOpenPrice))
                {
                    OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), 0, Red);
                    Print("closing candle confirmation");
                }
                g_nextOrderAnchorPrice = g_gridAnchorPips;
                if (g_orderTimeoutMin > 0 && TimeCurrent() > orderOpenTime + g_orderTimeoutMin * 60)
                {
                    g_nextOrderAnchorPrice = g_gridTimeoutAnchorPips;
                }
                soDigits = g_symbolDigits;
                soTicket = orderTicket;
                soCachedPrice = 0.0;
                for (soScanIdx = 0; soScanIdx < 100; soScanIdx = soScanIdx + 1)
                {
                    if (!(g_stopOrderTicketPrice[soScanIdx][0] == soTicket))   continue;
                    soCachedPrice = g_stopOrderTicketPrice[soScanIdx][1];
                    break;

                }
                stopOrderRefPrice = NormalizeDouble(soCachedPrice, soDigits);
                if (stopOrderRefPrice == 0.0)
                {
                    soStorePrice = orderOpenPrice;
                    soStoreTicket = orderTicket;
                    for (soStoreScanIdx = 0; soStoreScanIdx < 100; soStoreScanIdx = soStoreScanIdx + 1)
                    {
                        if (!(g_stopOrderTicketPrice[soStoreScanIdx][0] == 0.0))   continue;
                        g_stopOrderTicketPrice[soStoreScanIdx][0] = (double)soStoreTicket;
                        g_stopOrderTicketPrice[soStoreScanIdx][1] = soStorePrice;
                        break;

                    }
                    stopOrderRefPrice = orderOpenPrice;
                }
                else
                {
                    stopOrderRefPrice = stopOrderRefPrice - g_trailRefSlippagePips * g_pipSize;
                }
                slippageDistance = stopOrderRefPrice - orderOpenPrice;
                slippageDetected = false;
                if (stopOrderRefPrice > g_trailRefSlippagePips * g_pipSize && slippageDistance > g_slippagePts * g_pipSize)
                {
                    slippageDetected = true;
                    if (g_trailMode == 2)
                    {
                        g_nextOrderAnchorPrice = -1000.0;
                        Print("Slippage controle active");
                    }
                }
                if (g_trailUseFillPrice)
                {
                    entryRefPrice = stopOrderRefPrice;
                }
                else
                {
                    entryRefPrice = orderOpenPrice;
                }
                // EX5 behavior: maximum-loss is a virtual close boundary here.
                // Do not rewrite the broker SL on every management pass.
                if (MarketInfo(g_chartSymbol, MODE_ASK) > (g_stopLossPips + g_stopExtraPips) * g_pipSize + orderOpenPrice + g_curSpread)
                {
                    RefreshRates();
                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_curSpread, Red);
                    return(true);
                }
                zoneRecoveryDone = false;
                if (g_zrEnabled)
                {
                    zrTicketRef = orderTicket;
                    zrHedgeCountInt = 0;
                    for (zrScanIdx = MT4OrdersTotal(); zrScanIdx >= 0; zrScanIdx = zrScanIdx - 1)
                    {
                        if (OrderSelect(zrScanIdx, 0, 0) != true || OrderMagicNumber() != g_zrMagicSell || OrderSymbol() != g_chartSymbol)   continue;
                        zrScanComment = OrderComment();
                        if (zrScanComment != IntegerToString(zrTicketRef, 0, 32))   continue;
                        zrHedgeCountInt = zrHedgeCountInt + 1;

                    }
                    zrHedgeCount = zrHedgeCountInt;
                    zrOrderPlaced = false;
                    if (!(g_sellOrderSeen))
                    {
                        g_sellOrderSeen = true;
                        g_sellFirstModDone = 1;
                    }
                    if (zrHedgeCount == 0.0)
                    {
                        g_sellFirstModDone = 1;
                    }
                    if (MathFloor(zrHedgeCount / 2.0) == zrHedgeCount / 2.0)
                    {
                        g_sellFirstModDone = 1;
                    }
                    else
                    {
                        g_sellFirstModDone = 0;
                    }
                    if (g_sellOrderSeen)
                    {
                        if (zrHedgeCount > 0.0)
                        {
                            accountEquity = AccountEquity();
                            if (accountEquity > AccountBalance() + g_zrTargetProfit)
                            {
                                for (zrCloseAllScanIdx = MT4OrdersTotal(); zrCloseAllScanIdx >= 0; zrCloseAllScanIdx = zrCloseAllScanIdx - 1)
                                {
                                    if (OrderSelect(zrCloseAllScanIdx, 0, 0) != true)   continue;

                                    if ((OrderMagicNumber() != g_curStrategyMagic && OrderMagicNumber() != g_zrMagicSell && OrderMagicNumber() != g_zrMagicBuy))   continue;

                                    if (OrderType() == 0)
                                    {
                                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                    }
                                    if (OrderType() != 1)   continue;
                                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                }
                            }
                        }
                        if (zrHedgeCount > 0.0)
                        {
                            zrBasketTicket = orderTicket;
                            zrBasketProfit = 0.0;
                            for (zrBasketScanIdx = MT4OrdersTotal(); zrBasketScanIdx >= 0; zrBasketScanIdx = zrBasketScanIdx - 1)
                            {
                                if (OrderSelect(zrBasketScanIdx, 0, 0) != true)   continue;
                                zrScanTicket = OrderTicket();
                                if (zrScanTicket != zrBasketTicket)
                                {
                                    zrScanComment = OrderComment();
                                    if (zrScanComment != IntegerToString(zrBasketTicket, 0, 32))   continue;
                                }
                                zrBasketProfit = zrBasketProfit + OrderProfit();

                            }
                            if (zrBasketProfit > g_zrTargetProfit)
                            {
                                zrCloseTicket = orderTicket;
                                for (zrCloseScanIdx = MT4OrdersTotal(); zrCloseScanIdx >= 0; zrCloseScanIdx = zrCloseScanIdx - 1)
                                {
                                    if (OrderSelect(zrCloseScanIdx, 0, 0) != true)   continue;

                                    if (OrderMagicNumber() == g_curStrategyMagic && OrderTicket() == zrCloseTicket)
                                    {
                                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), 3, Red);
                                    }
                                    if (OrderMagicNumber() != g_zrMagicSell)   continue;
                                    zrScanComment = OrderComment();
                                    if (zrScanComment != IntegerToString(zrCloseTicket, 0, 32))   continue;

                                    if (OrderType() == 0)
                                    {
                                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                    }
                                    if (OrderType() != 1)   continue;
                                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                }
                                g_sellOrderSeen = false;
                                zoneRecoveryDone = true;
                            }
                        }
                        else
                        {
                            zrNextLotSize = orderLots * g_zrLotMultiplier;
                            if (g_zrLotMode == 2)
                            {
                                zrNextLotSize = (zrHedgeCount + 1.0) * orderLots + orderLots;
                            }
                            if (g_zrLotMode == 3)
                            {
                                zrNextLotSize = orderLots * (MathPow(g_zrLotMultiplier, zrHedgeCount + 1.0));
                            }
                            if (g_sellFirstModDone == 0)
                            {
                                zrRecoveryLevel = stopOrderRefPrice;
                                if (MarketInfo(g_chartSymbol, MODE_BID) < stopOrderRefPrice)
                                {
                                    if (zrHedgeCount >= g_zrMaxRecoverySteps)
                                    {
                                        for (zrMaxStepsScanIdx = MT4OrdersTotal(); zrMaxStepsScanIdx >= 0; zrMaxStepsScanIdx = zrMaxStepsScanIdx - 1)
                                        {
                                            if (OrderSelect(zrMaxStepsScanIdx, 0, 0) != true)   continue;

                                            if (OrderMagicNumber() == g_curStrategyMagic && OrderTicket() == orderTicket)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), 3, Red);
                                            }
                                            if (OrderMagicNumber() != g_zrMagicSell)   continue;
                                            zrScanComment = OrderComment();
                                            if (zrScanComment != IntegerToString(orderTicket, 0, 32))   continue;

                                            if (OrderType() == 0)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                            }
                                            if (OrderType() != 1)   continue;
                                            OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                        }
                                    }
                                    else
                                    {
                                        OrderSend(g_chartSymbol, 1, zrNextLotSize, MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, 0.0, 0.0, IntegerToString(orderTicket, 0, 32), g_zrMagicSell, 0, Green);
                                        g_sellFirstModDone = 1;
                                        zrOrderPlaced = true;
                                    }
                                }
                            }
                            else
                            {
                                zrTargetPrice = g_zrZoneSize * g_pipSize + stopOrderRefPrice - zrHedgeCount * g_zrStepDist * g_pipSize;
                                if (zrTargetPrice < g_zrMinTargetDist * g_pipSize + stopOrderRefPrice)
                                {
                                    zrTargetPrice = g_zrMinTargetDist * g_pipSize + stopOrderRefPrice;
                                }
                                if (MarketInfo(g_chartSymbol, MODE_ASK) > zrTargetPrice)
                                {
                                    if (zrHedgeCount >= g_zrMaxRecoverySteps)
                                    {
                                        for (zrRecoveryScanIdx = MT4OrdersTotal(); zrRecoveryScanIdx >= 0; zrRecoveryScanIdx = zrRecoveryScanIdx - 1)
                                        {
                                            if (OrderSelect(zrRecoveryScanIdx, 0, 0) != true)   continue;

                                            if (OrderMagicNumber() == g_curStrategyMagic && OrderTicket() == orderTicket)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), 3, Red);
                                            }
                                            if (OrderMagicNumber() != g_zrMagicSell)   continue;
                                            zrRecoveryScanComment = OrderComment();
                                            if (zrRecoveryScanComment != IntegerToString(orderTicket, 0, 32))   continue;

                                            if (OrderType() == 0)
                                            {
                                                OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                            }
                                            if (OrderType() != 1)   continue;
                                            OrderClose(OrderTicket(), OrderLots(), MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);

                                        }
                                    }
                                    else
                                    {
                                        OrderSend(g_chartSymbol, 0, zrNextLotSize, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, 0.0, 0.0, IntegerToString(orderTicket, 0, 32), g_zrMagicSell, 0, Green);
                                        g_sellFirstModDone = 0;
                                        zrOrderPlaced = true;
                                    }
                                }
                            }
                        }
                    }
                    if ((zrHedgeCount > 0.0 || zrOrderPlaced))
                    {
                        zoneRecoveryDone = true;
                    }
                }
                if (!(zoneRecoveryDone))
                {
                    if ((g_profitCloseMode == 1 || (g_profitCloseMode != 2 && g_profitCloseMode != 3)))
                    {
                        virtSlTicket1 = orderTicket;
                        virtSlPips1 = g_stopLossPips;
                        virtSlOpenPrice1 = orderOpenPrice;
                        virtSlMode1 = 2;
                        virtSlPrice1 = 0.0;
                        virtSlFound1 = false;
                        for (virtSlScanIdx1 = 0; virtSlScanIdx1 < g_virtSLCacheSize; virtSlScanIdx1 = virtSlScanIdx1 + 1)
                        {
                            if (g_virtSLCache[virtSlScanIdx1][0] == virtSlTicket1)
                            {
                                virtSlPrice1 = g_virtSLCache[virtSlScanIdx1][1];
                                virtSlFound1 = true;
                                break;
                            }
                        }
                        if (!(virtSlFound1))
                        {
                            if (virtSlMode1 == 1)
                            {
                                virtSlPrice1 = NormalizeDouble(virtSlOpenPrice1 - virtSlPips1 * g_pipSize, g_symbolDigits);
                            }
                            if (virtSlMode1 == 2)
                            {
                                virtSlPrice1 = NormalizeDouble(virtSlPips1 * g_pipSize + virtSlOpenPrice1, g_symbolDigits);
                            }
                            for (virtSlStoreIdx1 = 0; virtSlStoreIdx1 < g_virtSLCacheSize; virtSlStoreIdx1 = virtSlStoreIdx1 + 1)
                            {
                                if (g_virtSLCache[virtSlStoreIdx1][0] == 0.0)
                                {
                                    g_virtSLCache[virtSlStoreIdx1][0] = (double)virtSlTicket1;
                                    g_virtSLCache[virtSlStoreIdx1][1] = virtSlPrice1;
                                    break;
                                }
                            }
                        }
                        g_virtualSLPrice = virtSlPrice1;
                        prevVirtualSL = g_virtualSLPrice;
                        if (MarketInfo(g_chartSymbol, MODE_ASK) > prevVirtualSL)
                        {
                            Print("Closing with virtual SL");
                            Print("Virtual_SL: ", DoubleToString(prevVirtualSL, g_symbolDigits));
                            Print("Last Ask: ", DoubleToString(MarketInfo(g_chartSymbol, MODE_ASK), g_symbolDigits));
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        if (g_timeTrailDelayMin > 0.0 && TimeCurrent() >= orderOpenTime + g_timeTrailDelaySec && MarketInfo(g_chartSymbol, MODE_ASK) < currentStopLoss - g_symbolPoint - g_timeTrailDistancePips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && NormalizeDouble(MarketInfo(g_chartSymbol, MODE_ASK) + g_timeTrailDistancePips * g_pipSize, g_symbolDigits) < currentStopLoss)
                        {
                            currentStopLoss = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_ASK) + g_timeTrailDistancePips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss > MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TrailSL_after_X_Minutes_size_ loss.  Trying again!");
                                }
                                orderModified = true;
                            }
                        }
                        if (g_profitTrailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_ASK) < currentStopLoss - g_symbolPoint - (g_profitTrailDistancePips + g_profitTrailBufferPips) * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_trailActivationPips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && currentStopLoss > orderOpenPrice - g_profitTrailCapPips * g_pipSize && NormalizeDouble(g_profitTrailDistancePips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK), g_symbolDigits) < currentStopLoss)
                        {
                            currentStopLoss = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_ASK) + g_profitTrailDistancePips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss > MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_stop_ loss.  Trying again!");
                                }
                                else
                                {
                                    slTrailPartialLots = NormalizeDouble(g_partialClosePct / 100.0 * g_strategyStartLots[g_currentStrategyIndex], 2);
                                    if (slTrailPartialLots < orderLots && slTrailPartialLots >= MarketInfo(g_chartSymbol, MODE_LOTSTEP))
                                    {
                                        OrderClose(orderTicket, slTrailPartialLots, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);
                                        return(true);
                                    }
                                }
                                orderModified = true;
                            }
                        }
                        if (g_tpTrailPips > 0.0 && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_tpTrailPips * g_pipSize + (currentTakeProfit + g_symbolPoint), g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) > NormalizeDouble(g_tpTrailMinGapPips * g_pipSize + entryRefPrice, g_symbolDigits) && MarketInfo(g_chartSymbol, MODE_BID) > currentTakeProfit + g_freezeDistPrice)
                        {
                            currentTakeProfit = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_BID) - g_tpTrailPips * g_pipSize, g_symbolDigits);
                            if (currentTakeProfit < MarketInfo(g_chartSymbol, MODE_BID) - g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting trailing Exit_TP.  Trying again!");
                                }
                                else
                                {
                                    tpTrailPartialLots = NormalizeDouble(g_partialClosePct / 100.0 * g_strategyStartLots[g_currentStrategyIndex], 2);
                                    if (tpTrailPartialLots < orderLots && tpTrailPartialLots >= SymbolInfoDouble(g_chartSymbol, 34))
                                    {
                                        OrderClose(orderTicket, tpTrailPartialLots, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_slippagePts, Red);
                                        return(true);
                                    }
                                }
                                orderModified = true;
                            }
                        }
                        if (slippageDetected && g_trailMode == 1 && g_trailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_ASK) < currentStopLoss - g_symbolPoint - g_trailDistancePips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) < stopOrderRefPrice - g_trailStopBufferPips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && currentStopLoss > orderOpenPrice - g_trailCapAboveEntryPips * g_pipSize && NormalizeDouble(MarketInfo(g_chartSymbol, MODE_ASK) + g_trailDistancePips * g_pipSize, g_symbolDigits) < currentStopLoss)
                        {
                            currentStopLoss = NormalizeDouble(MarketInfo(g_chartSymbol, MODE_ASK) + g_trailDistancePips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss > MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("TrailStop error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when setting Slip TL.  Trying again!");
                                }
                                else
                                {
                                    Print("Slippage controle active");
                                }
                                orderModified = true;
                            }
                        }
                        if (g_hlFractalRightBars > 0 && g_hlFractalLeftBars >= 0 && UseHL_TrailingSL && g_sellTrailStopLevel[g_currentStrategyIndex]<currentStopLoss - g_minStopDistPrice - g_symbolPoint && g_sellTrailStopLevel[g_currentStrategyIndex]>g_hlTrailMinGapPips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK) && (g_sellTrailStopLevel[g_currentStrategyIndex] > orderOpenPrice || !(g_trailOnlyTighten)) && g_sellTrailStopLevel[g_currentStrategyIndex] > g_hlTrailBrokerGapPips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice + g_symbolPoint && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && NormalizeDouble(g_sellTrailStopLevel[g_currentStrategyIndex], g_symbolDigits) < currentStopLoss)
                        {
                            currentStopLoss = NormalizeDouble(g_sellTrailStopLevel[g_currentStrategyIndex], g_symbolDigits);
                            if (currentStopLoss > MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("error: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' when modifying stoploss");
                                }
                                orderModified = true;
                            }
                        }
                        if (g_beTriggerPips > 0.0 && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_beTriggerPips * g_pipSize && orderOpenPrice - g_beExtraPips * g_pipSize < currentStopLoss - g_symbolPoint && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_beExtraPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && NormalizeDouble(orderOpenPrice - g_beExtraPips * g_pipSize, g_symbolDigits) < currentStopLoss)
                        {
                            currentStopLoss = NormalizeDouble(orderOpenPrice - g_beExtraPips * g_pipSize, g_symbolDigits);
                            if (currentStopLoss > MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice)
                            {
                                g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                if (g_lastOrderResult <= 0)
                                {
                                    Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!");
                                }
                                orderModified = true;
                            }
                        }
                        if (!(orderModified) && (g_partialCloseMode == 1 || (g_partialCloseMode == 2 && currentStopLoss - g_gridSpacingPips * g_pipSize >= entryRefPrice - g_curSpread - g_gridMaxSpacingPips * g_pipSize)))
                        {
                            g_ordersSinceAnchor++;
                            if (MarketInfo(g_chartSymbol, MODE_ASK) < currentStopLoss - g_gridSpacingPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && (g_gridAnchorPips == 0.0 || MarketInfo(g_chartSymbol, MODE_ASK) < entryRefPrice - g_nextOrderAnchorPrice * g_pipSize) && g_ordersSinceAnchor >= g_gridMaxOrdersPerAnchor && NormalizeDouble(currentStopLoss - g_gridSpacingPips * g_pipSize, g_symbolDigits) < currentStopLoss)
                            {
                                g_ordersSinceAnchor = 0;
                                currentStopLoss = NormalizeDouble(currentStopLoss - g_gridSpacingPips * g_pipSize, g_symbolDigits);
                                OrderModify(orderTicket, orderOpenPrice, currentStopLoss, currentTakeProfit, 0, 0xFFFFFFFF);
                                orderModified = true;
                            }
                        }
                        g_virtualSLPrice = currentStopLoss;
                        if (MarketInfo(g_chartSymbol, MODE_ASK) > currentStopLoss)
                        {
                            Print("Closing with virtual SL");
                            Print("Virtual_SL: ", DoubleToString(currentStopLoss, g_symbolDigits));
                            Print("Last Ask: ", DoubleToString(MarketInfo(g_chartSymbol, MODE_ASK), g_symbolDigits));
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        if (NormalizeDouble(prevVirtualSL, g_symbolDigits) != NormalizeDouble(g_virtualSLPrice, g_symbolDigits))
                        {
                            virtSlUpdatePrice1 = NormalizeDouble(g_virtualSLPrice, g_symbolDigits);
                            virtSlUpdateTicket1 = orderTicket;
                            for (virtSlUpdateIdx1 = 0; virtSlUpdateIdx1 < g_virtSLCacheSize; virtSlUpdateIdx1 = virtSlUpdateIdx1 + 1)
                            {
                                if (g_virtSLCache[virtSlUpdateIdx1][0] == virtSlUpdateTicket1)
                                {
                                    g_virtSLCache[virtSlUpdateIdx1][1] = virtSlUpdatePrice1;
                                    break;
                                }
                            }
                        }
                        if (orderModified && g_returnAfterOrderModify)
                        {
                            return(true);
                        }
                    }
                    if ((g_profitCloseMode == 2 || g_profitCloseMode == 3))
                    {
                        virtSlTicket2 = orderTicket;
                        virtSlPips2 = g_stopLossPips;
                        virtSlOpenPrice2 = orderOpenPrice;
                        virtSlMode2 = 2;
                        virtSlPrice2 = 0.0;
                        virtSlFound2 = false;
                        for (virtSlScanIdx2 = 0; virtSlScanIdx2 < g_virtSLCacheSize; virtSlScanIdx2 = virtSlScanIdx2 + 1)
                        {
                            if (g_virtSLCache[virtSlScanIdx2][0] == virtSlTicket2)
                            {
                                virtSlPrice2 = g_virtSLCache[virtSlScanIdx2][1];
                                virtSlFound2 = true;
                                break;
                            }
                        }
                        if (!(virtSlFound2))
                        {
                            if (virtSlMode2 == 1)
                            {
                                virtSlPrice2 = NormalizeDouble(virtSlOpenPrice2 - virtSlPips2 * g_pipSize, g_symbolDigits);
                            }
                            if (virtSlMode2 == 2)
                            {
                                virtSlPrice2 = NormalizeDouble(virtSlPips2 * g_pipSize + virtSlOpenPrice2, g_symbolDigits);
                            }
                            for (virtSlStoreIdx2 = 0; virtSlStoreIdx2 < g_virtSLCacheSize; virtSlStoreIdx2 = virtSlStoreIdx2 + 1)
                            {
                                if (g_virtSLCache[virtSlStoreIdx2][0] == 0.0)
                                {
                                    g_virtSLCache[virtSlStoreIdx2][0] = (double)virtSlTicket2;
                                    g_virtSLCache[virtSlStoreIdx2][1] = virtSlPrice2;
                                    break;
                                }
                            }
                        }
                        g_virtualSLPrice = virtSlPrice2;
                        prevVirtualSL = g_virtualSLPrice;
                        if (MarketInfo(g_chartSymbol, MODE_ASK) >= prevVirtualSL)
                        {
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        trailElapsedSec = (int)(TimeCurrent() - g_lastTrailOrderTime);
                        if (trailElapsedSec >= g_trailModifyMinSec)
                        {
                            if (NormalizeDouble(g_virtualSLPrice, g_symbolDigits) < currentStopLoss - g_symbolPoint)
                            {
                                OrderModify(orderTicket, orderOpenPrice, NormalizeDouble(g_virtualSLPrice, g_symbolDigits), currentTakeProfit, 0, 0xFFFFFFFF);
                            }
                            g_lastTrailOrderTime = TimeCurrent();
                        }
                        if (g_timeTrailDelayMin > 0.0 && TimeCurrent() >= orderOpenTime + g_timeTrailDelaySec && MarketInfo(g_chartSymbol, MODE_ASK) < g_virtualSLPrice - g_symbolPoint - g_timeTrailDistancePips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice)
                        {
                            g_virtualSLPrice = MarketInfo(g_chartSymbol, MODE_ASK) + g_timeTrailDistancePips * g_pipSize;
                            orderModified = true;
                        }
                        if (g_profitTrailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_ASK) < g_virtualSLPrice - g_symbolPoint - (g_profitTrailDistancePips + g_profitTrailBufferPips) * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) < entryRefPrice - g_trailActivationPips * g_pipSize && g_virtualSLPrice > orderOpenPrice - g_profitTrailCapPips * g_pipSize)
                        {
                            g_virtualSLPrice = g_profitTrailDistancePips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK);
                            virtTrailPartialLots = NormalizeDouble(g_partialClosePct / 100.0 * g_strategyStartLots[g_currentStrategyIndex], 2);
                            if (virtTrailPartialLots < orderLots && virtTrailPartialLots >= MarketInfo(g_chartSymbol, MODE_LOTSTEP))
                            {
                                OrderClose(orderTicket, virtTrailPartialLots, MarketInfo(g_chartSymbol, MODE_BID), (int)g_slippagePts, Red);
                                return(true);
                            }
                            orderModified = true;
                        }
                        if (slippageDetected && g_trailMode == 1 && g_trailDistancePips > 0.0 && MarketInfo(g_chartSymbol, MODE_ASK) < g_virtualSLPrice - g_symbolPoint - g_trailDistancePips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) < stopOrderRefPrice - g_trailStopBufferPips * g_pipSize && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && g_virtualSLPrice > orderOpenPrice - g_trailCapAboveEntryPips * g_pipSize)
                        {
                            Print("Slippage controle active");
                            orderModified = true;
                            g_virtualSLPrice = MarketInfo(g_chartSymbol, MODE_ASK) + g_trailDistancePips * g_pipSize;
                        }
                        if (g_hlFractalRightBars > 0 && g_hlFractalLeftBars >= 0 && g_sellTrailStopLevel[g_currentStrategyIndex]<g_virtualSLPrice - g_minStopDistPrice - g_symbolPoint && (g_sellTrailStopLevel[g_currentStrategyIndex] > orderOpenPrice || !(g_trailOnlyTighten)) && g_sellTrailStopLevel[g_currentStrategyIndex]>g_hlTrailBrokerGapPips * g_pipSize + MarketInfo(g_chartSymbol, MODE_ASK) + g_minStopDistPrice + g_symbolPoint && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice)
                        {
                            g_virtualSLPrice = g_sellTrailStopLevel[g_currentStrategyIndex];
                            orderModified = true;
                        }
                        if (g_beTriggerPips > 0.0 && g_profitCloseMode == 3 && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_beTriggerPips * g_pipSize && orderOpenPrice - g_beExtraPips * g_pipSize < currentStopLoss - g_symbolPoint && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_beExtraPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && NormalizeDouble(orderOpenPrice - g_beExtraPips * g_pipSize, g_symbolDigits) < g_virtualSLPrice)
                        {
                            g_virtualSLPrice = NormalizeDouble(orderOpenPrice - g_beExtraPips * g_pipSize, g_symbolDigits);
                            g_lastOrderResult = OrderModify(orderTicket, orderOpenPrice, g_virtualSLPrice, currentTakeProfit, 0, 0xFFFFFFFF);
                            if (g_lastOrderResult <= 0)
                            {
                                Print("error when setting breakeven: \'" + GetTradeErrorDescription(MT4_LastError()) + "\' ..\'Exit_BE_start_\' to close to \'Exit_BE_extra_pips_\' ..trying again!");
                            }
                            orderModified = true;
                        }
                        if (g_beTriggerPips > 0.0 && g_profitCloseMode == 2 && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_beTriggerPips * g_pipSize && orderOpenPrice - g_beExtraPips * g_pipSize < g_virtualSLPrice - g_symbolPoint && MarketInfo(g_chartSymbol, MODE_ASK) < orderOpenPrice - g_beExtraPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice)
                        {
                            g_virtualSLPrice = orderOpenPrice - g_beExtraPips * g_pipSize;
                            orderModified = true;
                        }
                        if (!(orderModified) && (g_partialCloseMode == 1 || (g_partialCloseMode == 2 && g_virtualSLPrice - g_gridSpacingPips * g_pipSize >= entryRefPrice - g_curSpread - g_gridMaxSpacingPips * g_pipSize)))
                        {
                            g_ordersSinceAnchor++;
                            if (MarketInfo(g_chartSymbol, MODE_ASK) < g_virtualSLPrice - g_gridSpacingPips * g_pipSize - g_minStopDistPrice && MarketInfo(g_chartSymbol, MODE_ASK) > currentTakeProfit + g_freezeDistPrice && (g_gridAnchorPips == 0.0 || MarketInfo(g_chartSymbol, MODE_ASK) < entryRefPrice - g_nextOrderAnchorPrice * g_pipSize) && g_ordersSinceAnchor >= g_gridMaxOrdersPerAnchor)
                            {
                                g_ordersSinceAnchor = 0;
                                g_virtualSLPrice = g_virtualSLPrice - g_gridSpacingPips * g_pipSize;
                                orderModified = true;
                            }
                        }
                        if (MarketInfo(g_chartSymbol, MODE_ASK) >= g_virtualSLPrice)
                        {
                            RefreshRates();
                            OrderClose(orderTicket, orderLots, MarketInfo(g_chartSymbol, MODE_ASK), (int)g_curSpread, 0xFFFFFFFF);
                            return(true);
                        }
                        if (NormalizeDouble(prevVirtualSL, g_symbolDigits) != NormalizeDouble(g_virtualSLPrice, g_symbolDigits))
                        {
                            virtSlUpdatePrice2 = NormalizeDouble(g_virtualSLPrice, g_symbolDigits);
                            virtSlUpdateTicket2 = orderTicket;
                            for (virtSlUpdateIdx2 = 0; virtSlUpdateIdx2 < g_virtSLCacheSize; virtSlUpdateIdx2 = virtSlUpdateIdx2 + 1)
                            {
                                if (g_virtSLCache[virtSlUpdateIdx2][0] == virtSlUpdateTicket2)
                                {
                                    g_virtSLCache[virtSlUpdateIdx2][1] = virtSlUpdatePrice2;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            if (orderModified)
            {
                anyOrderTouched = true;
            }
        }
        if (orderModified)
        {
            anyOrderTouched = true;
        }
    }
    return(anyOrderTouched);
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
    bool      scheduleOpen;
    datetime  scheduleNow;
    int       currentHour;
    //----- -----
    bool       sundayOpen;
    bool       mondayOpen;
    bool       tuesdayOpen;
    bool       wednesdayOpen;
    bool       thursdayOpen;
    bool       fridayOpen;

    if (!(g_useTradingHours))
    {
        return(true);
    }
    scheduleOpen = false;
    scheduleNow = 0;
    if (g_scheduleTimeBase == 2)
    {
        scheduleNow = TimeCurrent();
    }
    if (g_scheduleTimeBase == 0)
    {
        TimeGMT();
    }
    if (g_scheduleTimeBase == 1)
    {
        TimeLocal();
    }
    currentHour = TimeHour(scheduleNow);
    if (TimeDayOfWeek(scheduleNow) == 0)
    {
        if (g_sunStartHour < g_sunEndHour && (currentHour < g_sunStartHour || currentHour >= g_sunEndHour))
        {
            sundayOpen = false;
        }
        else
        {
            if (g_sunStartHour > g_sunEndHour && currentHour < g_sunStartHour && currentHour >= g_sunEndHour)
            {
                sundayOpen = false;
            }
            else
            {
                if (g_sunStartHour == g_sunEndHour)
                {
                    sundayOpen = false;
                }
                else
                {
                    sundayOpen = true;
                }
            }
        }
        if (sundayOpen)
        {
            scheduleOpen = true;
        }
    }
    if (TimeDayOfWeek(scheduleNow) == 1)
    {
        if (g_monStartHour < g_monEndHour && (currentHour < g_monStartHour || currentHour >= g_monEndHour))
        {
            mondayOpen = false;
        }
        else
        {
            if (g_monStartHour > g_monEndHour && currentHour < g_monStartHour && currentHour >= g_monEndHour)
            {
                mondayOpen = false;
            }
            else
            {
                if (g_monStartHour == g_monEndHour)
                {
                    mondayOpen = false;
                }
                else
                {
                    mondayOpen = true;
                }
            }
        }
        if (mondayOpen)
        {
            scheduleOpen = true;
        }
    }
    if (TimeDayOfWeek(scheduleNow) == 2)
    {
        if (g_tueStartHour < g_tueEndHour && (currentHour < g_tueStartHour || currentHour >= g_tueEndHour))
        {
            tuesdayOpen = false;
        }
        else
        {
            if (g_tueStartHour > g_tueEndHour && currentHour < g_tueStartHour && currentHour >= g_tueEndHour)
            {
                tuesdayOpen = false;
            }
            else
            {
                if (g_tueStartHour == g_tueEndHour)
                {
                    tuesdayOpen = false;
                }
                else
                {
                    tuesdayOpen = true;
                }
            }
        }
        if (tuesdayOpen)
        {
            scheduleOpen = true;
        }
    }
    if (TimeDayOfWeek(scheduleNow) == 3)
    {
        if (g_wedStartHour < g_wedEndHour && (currentHour < g_wedStartHour || currentHour >= g_wedEndHour))
        {
            wednesdayOpen = false;
        }
        else
        {
            if (g_wedStartHour > g_wedEndHour && currentHour < g_wedStartHour && currentHour >= g_wedEndHour)
            {
                wednesdayOpen = false;
            }
            else
            {
                if (g_wedStartHour == g_wedEndHour)
                {
                    wednesdayOpen = false;
                }
                else
                {
                    wednesdayOpen = true;
                }
            }
        }
        if (wednesdayOpen)
        {
            scheduleOpen = true;
        }
    }
    if (TimeDayOfWeek(scheduleNow) == 4)
    {
        if (g_thuStartHour < g_thuEndHour && (currentHour < g_thuStartHour || currentHour >= g_thuEndHour))
        {
            thursdayOpen = false;
        }
        else
        {
            if (g_thuStartHour > g_thuEndHour && currentHour < g_thuStartHour && currentHour >= g_thuEndHour)
            {
                thursdayOpen = false;
            }
            else
            {
                if (g_thuStartHour == g_thuEndHour)
                {
                    thursdayOpen = false;
                }
                else
                {
                    thursdayOpen = true;
                }
            }
        }
        if (thursdayOpen)
        {
            scheduleOpen = true;
        }
    }
    if (TimeDayOfWeek(scheduleNow) == 5)
    {
        if (g_friStartHour < g_friEndHour && (currentHour < g_friStartHour || currentHour >= g_friEndHour))
        {
            fridayOpen = false;
        }
        else
        {
            if (g_friStartHour > g_friEndHour && currentHour < g_friStartHour && currentHour >= g_friEndHour)
            {
                fridayOpen = false;
            }
            else
            {
                if (g_friStartHour == g_friEndHour)
                {
                    fridayOpen = false;
                }
                else
                {
                    fridayOpen = true;
                }
            }
        }
        if (fridayOpen)
        {
            scheduleOpen = true;
        }
    }
    return(scheduleOpen);
}
//IsTradingScheduleOpen <<==--------   --------
string GetTradeErrorDescription(int errorCode)
{
    string    errorDescription;
    //----- -----

    g_tradeErrorCount++;
    switch (errorCode)
    {
    case 0: case 1:
        errorDescription = "no error";
        break;
    case 2:
        errorDescription = "common error";
        break;
    case 3:
        errorDescription = "invalid trade parameters";
        break;
    case 4:
        errorDescription = "trade server is busy";
        break;
    case 5:
        errorDescription = "old version of the client terminal";
        break;
    case 6:
        errorDescription = "no connection with trade server";
        break;
    case 7:
        errorDescription = "not enough rights";
        break;
    case 8:
        errorDescription = "too frequent requests";
        break;
    case 9:
        errorDescription = "malfunctional trade operation (never returned error)";
        break;
    case 64:
        errorDescription = "account disabled";
        break;
    case 65:
        errorDescription = "invalid account";
        break;
    case 128:
        errorDescription = "trade timeout";
        break;
    case 129:
        errorDescription = "invalid price";
        break;
    case 130:
        errorDescription = "invalid stops";
        break;
    case 131:
        errorDescription = "invalid trade volume";
        break;
    case 132:
        errorDescription = "market is closed";
        break;
    case 133:
        errorDescription = "trade is disabled";
        break;
    case 134:
        errorDescription = "not enough money";
        break;
    case 135:
        errorDescription = "price changed";
        break;
    case 136:
        errorDescription = "off quotes";
        break;
    case 137:
        errorDescription = "broker is busy (never returned error)";
        break;
    case 138:
        errorDescription = "requote";
        break;
    case 139:
        errorDescription = "order is locked";
        break;
    case 140:
        errorDescription = "long positions only allowed";
        break;
    case 141:
        errorDescription = "too many requests";
        break;
    case 145:
        errorDescription = "modification denied because order too close to market";
        break;
    case 146:
        errorDescription = "trade context is busy";
        break;
    case 147:
        errorDescription = "expirations are denied by broker";
        break;
    case 148:
        errorDescription = "amount of open and pending orders has reached the Exit_limit";
        break;
    case 149:
        errorDescription = "hedging is prohibited";
        break;
    case 150:
        errorDescription = "prohibited by FIFO rules";
        break;
    case 4000:
        errorDescription = "no error (never generated code)";
        break;
    case 4001:
        errorDescription = "wrong function pointer";
        break;
    case 4002:
        errorDescription = "array index is out of range";
        break;
    case 4003:
        errorDescription = "no memory for function call stack";
        break;
    case 4004:
        errorDescription = "recursive stack overflow";
        break;
    case 4005:
        errorDescription = "not enough stack for parameter";
        break;
    case 4006:
        errorDescription = "no memory for parameter string";
        break;
    case 4007:
        errorDescription = "no memory for temp string";
        break;
    case 4008:
        errorDescription = "not initialized string";
        break;
    case 4009:
        errorDescription = "not initialized string in array";
        break;
    case 4010:
        errorDescription = "no memory for array\' string";
        break;
    case 4011:
        errorDescription = "too long string";
        break;
    case 4012:
        errorDescription = "remainder from zero divide";
        break;
    case 4013:
        errorDescription = "zero divide";
        break;
    case 4014:
        errorDescription = "unknown command";
        break;
    case 4015:
        errorDescription = "wrong jump (never generated error)";
        break;
    case 4016:
        errorDescription = "not initialized array";
        break;
    case 4017:
        errorDescription = "dll calls are not allowed";
        break;
    case 4018:
        errorDescription = "cannot load library";
        break;
    case 4019:
        errorDescription = "cannot call function";
        break;
    case 4020:
        errorDescription = "expert function calls are not allowed";
        break;
    case 4021:
        errorDescription = "not enough memory for temp string returned from function";
        break;
    case 4022:
        errorDescription = "system is busy (never generated error)";
        break;
    case 4050:
        errorDescription = "invalid function parameters count";
        break;
    case 4051:
        errorDescription = "invalid function parameter value";
        break;
    case 4052:
        errorDescription = "string function internal error";
        break;
    case 4053:
        errorDescription = "some array error";
        break;
    case 4054:
        errorDescription = "incorrect series array using";
        break;
    case 4055:
        errorDescription = "custom indicator error";
        break;
    case 4056:
        errorDescription = "arrays are incompatible";
        break;
    case 4057:
        errorDescription = "global variables processing error";
        break;
    case 4058:
        errorDescription = "global variable not found";
        break;
    case 4059:
        errorDescription = "function is not allowed in testing mode";
        break;
    case 4060:
        errorDescription = "function is not confirmed";
        break;
    case 4061:
        errorDescription = "send mail error";
        break;
    case 4062:
        errorDescription = "string parameter expected";
        break;
    case 4063:
        errorDescription = "integer parameter expected";
        break;
    case 4064:
        errorDescription = "double parameter expected";
        break;
    case 4065:
        errorDescription = "array as parameter expected";
        break;
    case 4066:
        errorDescription = "requested history data in update state";
        break;
    case 4099:
        errorDescription = "end of file";
        break;
    case 4100:
        errorDescription = "some file error";
        break;
    case 4101:
        errorDescription = "wrong file name";
        break;
    case 4102:
        errorDescription = "too many opened files";
        break;
    case 4103:
        errorDescription = "cannot open file";
        break;
    case 4104:
        errorDescription = "incompatible access to a file";
        break;
    case 4105:
        errorDescription = "no order selected";
        break;
    case 4106:
        errorDescription = "unknown symbol";
        break;
    case 4107:
        errorDescription = "invalid price parameter for trade function";
        break;
    case 4108:
        errorDescription = "invalid ticket";
        break;
    case 4109:
        errorDescription = "trade is not allowed in the expert properties";
        break;
    case 4110:
        errorDescription = "longs are not allowed in the expert properties";
        break;
    case 4111:
        errorDescription = "shorts are not allowed in the expert properties";
        break;
    case 4200:
        errorDescription = "object is already exist";
        break;
    case 4201:
        errorDescription = "unknown object property";
        break;
    case 4202:
        errorDescription = "object is not exist";
        break;
    case 4203:
        errorDescription = "unknown object type";
        break;
    case 4204:
        errorDescription = "no object name";
        break;
    case 4205:
        errorDescription = "object coordinates error";
        break;
    case 4206:
        errorDescription = "no specified subwindow";
        break;
    default:
        errorDescription = "unknown error";
    }
    return(errorDescription);
}
//GetTradeErrorDescription <<==--------   --------
void RefreshPendingOrderLotSizes(bool forceRefresh)
{
    double    lotChangeRatio;
    int       ordersTotal;
    int       orderScanIdx;
    double    buyStopLoss;
    long      buyTicket;
    double    buyTakeProfit;
    double    buyOpenPrice;
    datetime  buyExpiry;
    string    buyComment;
    long      buyNewTicket; // ticket 64-bit
    double    sellStopLoss;
    long      sellTicket;
    double    sellTakeProfit;
    double    sellOpenPrice;
    datetime  sellExpiry;
    string    sellComment;
    long      sellNewTicket; // ticket 64-bit
    //----- -----
    long       buyNewTicketVal;
    long       buyOldTicketVal;
    int        buySlotScanIdx;
    long       sellNewTicketVal;
    long       sellOldTicketVal;
    int        sellSlotScanIdx;

    lotChangeRatio = g_lotChangePctAlert / 100.0 + 1.0;
    // JIT compare fix: threshold uses the lot-sizing balance basis
    // (OnlyUp / ManualBalance aware), while OnTick keeps LastLotResizeBalance
    // as the raw account-balance snapshot.
    if ((!(g_effectiveBalance != g_lastLotResizeBalance) && !(forceRefresh)))
    {
        return;
    }

    if ((!(g_effectiveBalance > g_lastLotResizeBalance * lotChangeRatio) &&
        !(g_effectiveBalance < g_lastLotResizeBalance / lotChangeRatio) && !(forceRefresh)))
    {
        return;
    }

    CalculateStrategyLotSize(g_stopLossPips, g_lotScalePercent);

    // Preserve the lot-size refresh above while the market is closed.  Moving
    // the entire market gate before RefreshPendingOrderLotSizes() skipped this refresh and changed
    // several first orders from 0.01 to 0.02.  Only pending delete/recreate is
    // deferred until MODE_TRADEALLOWED becomes true.
    if (MarketInfo(g_chartSymbol, MODE_TRADEALLOWED) == 0.0)
    {
        return;
    }
    ordersTotal = MT4OrdersTotal();
    for (orderScanIdx = ordersTotal; orderScanIdx >= 0; orderScanIdx--)
    {
        if (OrderSelect(orderScanIdx, 0, 0) != true || OrderMagicNumber() != g_curStrategyMagic || OrderSymbol() != g_chartSymbol)   continue;

        if (OrderType() == 4 && OrderLots() != g_strategyStartLots[g_currentStrategyIndex])
        {
            buyStopLoss = OrderStopLoss();
            buyTicket = OrderTicket();
            buyTakeProfit = OrderTakeProfit();
            buyOpenPrice = OrderOpenPrice();
            buyExpiry = OrderExpiration();
            buyComment = OrderComment();
            OrderDelete(buyTicket, Red);
            buyNewTicket = OrderSend(g_chartSymbol, 4, g_strategyStartLots[g_currentStrategyIndex], buyOpenPrice, (int)g_slippagePts, buyStopLoss, buyTakeProfit, buyComment, g_curStrategyMagic, buyExpiry, Green);
            buyNewTicketVal = buyNewTicket;
            buyOldTicketVal = buyTicket;
            for (buySlotScanIdx = 0; buySlotScanIdx < 100; buySlotScanIdx = buySlotScanIdx + 1)
            {
                if (!(g_stopOrderTicketPrice[buySlotScanIdx][0] == buyOldTicketVal))   continue;
                g_stopOrderTicketPrice[buySlotScanIdx][0] = (double)buyNewTicketVal;
                break;

            }
            Print("Lotsize changed more than " + string(g_lotChangePctAlert) + "%... adjusting lotsize of pending orders");
            Sleep(1000);
        }
        if (OrderType() != 5 || !(OrderLots() != g_strategyStartLots[g_currentStrategyIndex]))   continue;
        sellStopLoss = OrderStopLoss();
        sellTicket = OrderTicket();
        sellTakeProfit = OrderTakeProfit();
        sellOpenPrice = OrderOpenPrice();
        sellExpiry = OrderExpiration();
        sellComment = OrderComment();
        OrderDelete(sellTicket, Red);
        sellNewTicket = OrderSend(g_chartSymbol, 5, g_strategyStartLots[g_currentStrategyIndex], sellOpenPrice, (int)g_slippagePts, sellStopLoss, sellTakeProfit, sellComment, g_curStrategyMagic, sellExpiry, Green);
        sellNewTicketVal = sellNewTicket;
        sellOldTicketVal = sellTicket;
        for (sellSlotScanIdx = 0; sellSlotScanIdx < 100; sellSlotScanIdx = sellSlotScanIdx + 1)
        {
            if (!(g_stopOrderTicketPrice[sellSlotScanIdx][0] == sellOldTicketVal))   continue;
            g_stopOrderTicketPrice[sellSlotScanIdx][0] = (double)sellNewTicketVal;
            break;

        }
        Print("Lotsize changed more than " + string(g_lotChangePctAlert) + "%... adjusting lotsize of pending orders");
        Sleep(1000);

    }
}

void CreateInfoPanel()
{
    int       textOffsetX;
    int       textOffsetY;
    int       panelWidth;
    int       panelBaseHeight;
    int       panelCorner;
    int       panelX;
    int       panelY;
    uint      panelBgColor;
    int       extraHeightAllSymbols;
    string    frequencyText;
    int       cellColumnIdx;
    int       cellSubIdx;
    int       cellRowIdx;
    string    cellText;
    int       tableX;
    int       tableY;
    int       strategyIdx;
    //----- -----

    textOffsetX = 6;
    textOffsetY = 4;
    panelWidth = 350;
    panelBaseHeight = 530;   // 卡片式布局后头部+三张卡片约占 338px，下方留给策略表格与历史面板
    g_panelWidth = panelWidth;
    panelCorner = 0;
    panelX = 5;
    panelY = 20;
    g_panelX = panelX;
    g_panelY = panelY;
    panelBgColor = C'15,20,27';          // 深色主题底（麒麟King 风格，原 LightSteelBlue）
    extraHeightAllSymbols = 0;
    if (g_manageAllSymbols)
    {
        extraHeightAllSymbols = (int)((g_strategyCount + 3) * g_panelCellHeight);
    }
    ObjectCreate(0, "infopanel_rectangle", OBJ_RECTANGLE_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_XDISTANCE, panelX);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_YDISTANCE, panelY);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_XSIZE, long(panelWidth * InfoPanelSizeAdjust));
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_YSIZE, long(panelBaseHeight * InfoPanelSizeAdjust + extraHeightAllSymbols));
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_CORNER, 0);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_COLOR, C'45,58,74');
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_BGCOLOR, panelBgColor);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_BACK, 0);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_BORDER_COLOR, C'45,58,74');
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_COLOR, C'45,58,74');
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_BORDER_TYPE, 0);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_STYLE, 0);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_WIDTH, 0x2);
    ObjectSetInteger(0, "infopanel_rectangle", OBJPROP_SELECTABLE, 0);
    // [深色主题] 头部条 + 左侧强调竖条（麒麟King 风格）
    ObjectCreate(0, "infopanel_header", OBJ_RECTANGLE_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "infopanel_header", OBJPROP_XDISTANCE, panelX);
    ObjectSetInteger(0, "infopanel_header", OBJPROP_YDISTANCE, panelY);
    ObjectSetInteger(0, "infopanel_header", OBJPROP_XSIZE, long(panelWidth * InfoPanelSizeAdjust));
    ObjectSetInteger(0, "infopanel_header", OBJPROP_YSIZE, long(48 * InfoPanelSizeAdjust));
    ObjectSetInteger(0, "infopanel_header", OBJPROP_CORNER, 0);
    ObjectSetInteger(0, "infopanel_header", OBJPROP_BGCOLOR, C'20,29,40');
    ObjectSetInteger(0, "infopanel_header", OBJPROP_BORDER_COLOR, C'45,58,74');
    ObjectSetInteger(0, "infopanel_header", OBJPROP_BORDER_TYPE, 0);
    ObjectSetInteger(0, "infopanel_header", OBJPROP_BACK, 0);
    ObjectSetInteger(0, "infopanel_header", OBJPROP_SELECTABLE, 0);
    ObjectCreate(0, "infopanel_accent", OBJ_RECTANGLE_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_XDISTANCE, panelX);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_YDISTANCE, panelY);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_XSIZE, long(4 * InfoPanelSizeAdjust));
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_YSIZE, long(48 * InfoPanelSizeAdjust));
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_CORNER, 0);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_BGCOLOR, g_panelAccentColor);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_BORDER_COLOR, g_panelAccentColor);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_BORDER_TYPE, 0);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_BACK, 0);
    ObjectSetInteger(0, "infopanel_accent", OBJPROP_SELECTABLE, 0);
    ObjectCreate(0, "line1", OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "line1", OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "line1", OBJPROP_YDISTANCE, panelY + textOffsetY);
    ObjectSetInteger(0, "line1", OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "line1", OBJPROP_TEXT, "The Gold Reaper v4.6");
    ObjectSetInteger(0, "line1", OBJPROP_COLOR, g_panelTextColor);
    // Ban decompile goc thieu set co chu rieng cho cac dong tieu de/tom tat panel
    // (chi co bang chien luoc phia duoi duoc set), trong khi kich thuoc khung panel
    // lai duoc tinh dua tren dung hang so co chu nay -> khien cac dong nay hien thi
    // to hon binh thuong (dung co mac dinh cua nen tang) so voi thiet ke that su cua
    // khung panel. Set khop voi co chu cua bang chien luoc de dong bo.
    ObjectSetInteger(0, "line1", OBJPROP_FONTSIZE, g_panelFontSize);
    ObjectCreate(0, "linec", OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "linec", OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "linec", OBJPROP_YDISTANCE, long(panelY + InfoPanelSizeAdjust * 20.0 + textOffsetY));
    ObjectSetInteger(0, "linec", OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "linec", OBJPROP_TEXT, "EA Developed by Wim Schrynemakers - 2024");
    ObjectSetInteger(0, "linec", OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "linec", OBJPROP_FONTSIZE, g_panelFontSize);
    ObjectCreate(0, "line2", OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "line2", OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "line2", OBJPROP_YDISTANCE, long(panelY + InfoPanelSizeAdjust * 32.0 + textOffsetY));
    ObjectSetInteger(0, "line2", OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "line2", OBJPROP_TEXT, "------------------------------------------------------");
    ObjectSetInteger(0, "line2", OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "line2", OBJPROP_FONTSIZE, g_panelFontSize);
    ObjectCreate(0, "lines", OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "lines", OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "lines", OBJPROP_YDISTANCE, long(panelY + InfoPanelSizeAdjust * 44.0 + textOffsetY));
    ObjectSetInteger(0, "lines", OBJPROP_XDISTANCE, panelX + textOffsetX);
    if (g_tradeFrequencyMode == 1)
    {
        frequencyText = "conservative";
    }
    else
    {
        if (g_tradeFrequencyMode == 2)
        {
            frequencyText = "moderate";
        }
        else
        {
            if (g_tradeFrequencyMode == 3)
            {
                frequencyText = "intense";
            }
            else
            {
                if (g_tradeFrequencyMode == 4)
                {
                    frequencyText = "extreme";
                }
                else
                {
                    if (g_tradeFrequencyMode == 0)
                    {
                        frequencyText = "extreme conservative";
                    }
                    else
                    {
                        frequencyText = "manual strategy selection";
                    }
                }
            }
        }
    }
    ObjectSetString(0, "lines", OBJPROP_TEXT, "Trade Frequency: " + frequencyText);
    ObjectSetInteger(0, "lines", OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "lines", OBJPROP_FONTSIZE, g_panelFontSize);
    if (Risk == 1234)
    {
        ObjectCreate(0, "linet", OBJ_LABEL, 0, 0, 0.0);
        ObjectSetInteger(0, "linet", OBJPROP_CORNER, panelCorner);
        ObjectSetInteger(0, "linet", OBJPROP_YDISTANCE, long(panelY + InfoPanelSizeAdjust * 60.0 + textOffsetY));
        ObjectSetInteger(0, "linet", OBJPROP_XDISTANCE, panelX + textOffsetX);
        ObjectSetString(0, "linet", OBJPROP_TEXT, "Max allowed DD: " + string(MaxAllowedDD) + "%");
        ObjectSetInteger(0, "linet", OBJPROP_COLOR, g_panelTextColor);
        ObjectSetInteger(0, "linet", OBJPROP_FONTSIZE, g_panelFontSize);
    }
    else
    {
        if (Risk == 3)
        {
            ObjectCreate(0, "linet", OBJ_LABEL, 0, 0, 0.0);
            ObjectSetInteger(0, "linet", OBJPROP_CORNER, panelCorner);
            ObjectSetInteger(0, "linet", OBJPROP_YDISTANCE, long(panelY + InfoPanelSizeAdjust * 60.0 + textOffsetY));
            ObjectSetInteger(0, "linet", OBJPROP_XDISTANCE, panelX + textOffsetX);
            ObjectSetString(0, "linet", OBJPROP_TEXT, "Max risk per strategy: " + string(MaxRiskPerStrategy_) + "%");
            ObjectSetInteger(0, "linet", OBJPROP_COLOR, g_panelTextColor);
            ObjectSetInteger(0, "linet", OBJPROP_FONTSIZE, g_panelFontSize);
        }
        else
        {
            ObjectCreate(0, "linet", OBJ_LABEL, 0, 0, 0.0);
            ObjectSetInteger(0, "linet", OBJPROP_CORNER, panelCorner);
            ObjectSetInteger(0, "linet", OBJPROP_YDISTANCE, long(panelY + InfoPanelSizeAdjust * 60.0 + textOffsetY));
            ObjectSetInteger(0, "linet", OBJPROP_XDISTANCE, panelX + textOffsetX);
            ObjectSetString(0, "linet", OBJPROP_TEXT, "Manual lotsize: " + string(g_startLots_rw) + "lots");
            ObjectSetInteger(0, "linet", OBJPROP_COLOR, g_panelTextColor);
            ObjectSetInteger(0, "linet", OBJPROP_FONTSIZE, g_panelFontSize);
        }
    }
    ObjectCreate(0, "lineopl" + IntegerToString(0, 0, 32), OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_YDISTANCE, (long)(panelY + InfoPanelSizeAdjust * 76.0 + textOffsetY));
    ObjectSetInteger(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Open P/L: -");
    ObjectSetInteger(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_FONTSIZE, g_panelFontSize);
    ObjectCreate(0, "linehb" + IntegerToString(0, 0, 32), OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_YDISTANCE, (long)(panelY + InfoPanelSizeAdjust * 92.0 + textOffsetY));
    ObjectSetInteger(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Higher Balance: -");
    ObjectSetInteger(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_FONTSIZE, g_panelFontSize);
    // [新增] linesp —— 实时点差显示：当前点差(价格单位) / 换算点数 / MaxSpread 上限
    //         超过上限时变红并追加 HIGH 标记（与 RemovePendingOrdersDuringHighSpread
    //         的判定口径一致：g_curSpread > MaxSpread * variableRatio * g_pipSize）。
    ObjectCreate(0, "linesp" + IntegerToString(0, 0, 32), OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "linesp" + IntegerToString(0, 0, 32), OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "linesp" + IntegerToString(0, 0, 32), OBJPROP_YDISTANCE, (long)(panelY + InfoPanelSizeAdjust * 156.0 + textOffsetY));
    ObjectSetInteger(0, "linesp" + IntegerToString(0, 0, 32), OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "linesp" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Spread: -");
    ObjectSetInteger(0, "linesp" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "linesp" + IntegerToString(0, 0, 32), OBJPROP_FONTSIZE, g_panelFontSize);
    ObjectCreate(0, "linea" + IntegerToString(0, 0, 32), OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_YDISTANCE, (long)(panelY + InfoPanelSizeAdjust * 108.0 + textOffsetY));
    ObjectSetInteger(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Account Balance: -");
    ObjectSetInteger(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_FONTSIZE, g_panelFontSize);
    ObjectCreate(0, "linetp" + IntegerToString(0, 0, 32), OBJ_LABEL, 0, 0, 0.0);
    ObjectSetInteger(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_CORNER, panelCorner);
    ObjectSetInteger(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_YDISTANCE, (long)(panelY + InfoPanelSizeAdjust * 124.0 + textOffsetY));
    ObjectSetInteger(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_XDISTANCE, panelX + textOffsetX);
    ObjectSetString(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Total P/L so far: -");
    ObjectSetInteger(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelTextColor);
    ObjectSetInteger(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_FONTSIZE, g_panelFontSize);
    if (EnableNFP_Filter)
    {
        ObjectCreate(0, "linenfp" + IntegerToString(0, 0, 32), OBJ_LABEL, 0, 0, 0.0);
        ObjectSetInteger(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_CORNER, panelCorner);
        ObjectSetInteger(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_YDISTANCE, (long)(panelY + InfoPanelSizeAdjust * 140.0 + textOffsetY));
        ObjectSetInteger(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_XDISTANCE, panelX + textOffsetX);
        ObjectSetString(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "no news coming up");
        ObjectSetInteger(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelTextColor);
        ObjectSetInteger(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_FONTSIZE, g_panelFontSize);
    }
    cellColumnIdx = 0;
    cellSubIdx = 0;
    cellRowIdx = 0;
    tableX = panelX + textOffsetX;
    // [卡片式布局] 移除旧的单行标签，改为「账户 / 风控 / 状态」三张卡片，
    // 表格起点改用 DrawTGRCards 计算出的 g_panelTableY。
    DeleteLegacyPanelLines();
    DrawTGRCards();
    tableY = g_panelTableY;
    cellText = "Strategy";
    CreateInfoPanelCell(tableX, tableY, 0, "Strategy", 0, 0, 1, 0, 1.0);
    cellColumnIdx = 1;
    cellSubIdx = 1;
    cellText = "Closed PL";
    if (g_rankMode == 1)
    {
        cellText = "Closed PL*";
    }
    CreateInfoPanelCell(tableX, tableY, cellColumnIdx, cellText, cellRowIdx, cellSubIdx, 1, 0, 1.0);
    cellColumnIdx++;
    cellSubIdx++;
    cellText = "PL per trade";
    CreateInfoPanelCell(tableX, tableY, cellColumnIdx, cellText, cellRowIdx, cellSubIdx, 1, 0, 1.0);
    cellColumnIdx++;
    cellSubIdx++;
    cellText = "Lotsize";
    CreateInfoPanelCell(tableX, tableY, cellColumnIdx, "Lotsize", cellRowIdx, cellSubIdx, 1, 0, 1.0);
    cellColumnIdx++;
    cellSubIdx = 0;
    cellRowIdx++;
    g_panelStrategyRowStart = cellColumnIdx;
    for (strategyIdx = 0; strategyIdx < 9; strategyIdx++)
    {
        cellText = "Strategy " + IntegerToString(strategyIdx + 1, 0, 32);
        CreateInfoPanelCell(tableX, tableY, cellColumnIdx, cellText, cellRowIdx, cellSubIdx, 1, 0, 1.0);
        cellColumnIdx++;
        cellSubIdx++;
        cellText = DoubleToString(NormalizeDouble(g_histClosedPLbyStrategy[strategyIdx], 2), 2);
        CreateInfoPanelCell(tableX, tableY, cellColumnIdx, cellText, cellRowIdx, cellSubIdx, 1, 0, 1.0);
        cellColumnIdx++;
        cellSubIdx++;
        cellText = DoubleToString(NormalizeDouble(g_avgPLperTrade[strategyIdx], 2), 2);
        CreateInfoPanelCell(tableX, tableY, cellColumnIdx, cellText, cellRowIdx, cellSubIdx, 1, 0, 1.0);
        cellColumnIdx++;
        cellSubIdx++;
        cellText = DoubleToString(NormalizeDouble(g_strategyStartLots[strategyIdx], 2), 2);
        CreateInfoPanelCell(tableX, tableY, cellColumnIdx, cellText, cellRowIdx, cellSubIdx, 1, 0, 1.0);
        cellColumnIdx++;
        cellSubIdx = 0;
        cellRowIdx++;
    }
}
//CreateInfoPanel <<==--------   --------
void CreateInfoPanelCell(int baseX, int baseY, int objectIdx, string cellText, int rowOffset, int colOffset, int alignMode, uint textColor, double fontScale)
{
    ObjectCreate(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJ_EDIT, 0, 0, 0.0);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_XDISTANCE, (long)(baseX + colOffset * g_panelCellWidth));
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_YDISTANCE, (long)(baseY + rowOffset * g_panelCellHeight));
    ObjectSetString(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_TEXT, cellText);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_BACK, 0);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_COLOR, textColor);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_BGCOLOR, g_panelCellBgColor);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_BORDER_COLOR, 0);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_FONTSIZE, (long)(g_panelFontSize * fontScale));
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_READONLY, 0x1);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_YSIZE, (long)g_panelCellHeight);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_XSIZE, (long)g_panelCellWidth);
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_YSIZE, (long)g_panelCellHeight);
    if (alignMode == 0)
    {
        ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_ALIGN, 0x1);
    }
    if (alignMode == 1)
    {
        ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_ALIGN, 0x2);
    }
    if (alignMode != 2)   return;
    ObjectSetInteger(0, "info_ea" + IntegerToString(objectIdx, 0, 32), OBJPROP_ALIGN, 0);
}
//CreateInfoPanelCell <<==--------   --------
void DeleteInfoPanel()
{
    int       mainObjIdx;
    int       subObjIdx;
    int       headingObjIdx;
    int       rectObjIdx;
    //----- -----

    ObjectDelete(0, "line1");
    ObjectDelete(0, "linec");
    ObjectDelete(0, "line2");
    ObjectDelete(0, "lines");
    ObjectDelete(0, "linet");
    ObjectDelete(0, "lineTradeStart");
    for (mainObjIdx = 0; mainObjIdx <= 99; mainObjIdx++)
    {
        ObjectDelete(0, "lineopl" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "linehb" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "linesp" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "linea" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "lineto" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "linetp" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "linetq" + IntegerToString(mainObjIdx, 0, 32));
        ObjectDelete(0, "linenfp" + IntegerToString(mainObjIdx, 0, 32));
        for (subObjIdx = 0; subObjIdx < 10; subObjIdx++)
        {
            ObjectDelete(0, "tabel_info" + IntegerToString(mainObjIdx * 100 + subObjIdx, 0, 32));
        }
    }
    ObjectDelete(0, "infopanel_rectangle");
    ObjectDelete(0, "infopanel_header");
    ObjectDelete(0, "infopanel_accent");
    for (headingObjIdx = 0; headingObjIdx < 10; headingObjIdx++)
    {
        ObjectDelete(0, "tabel_heading" + IntegerToString(headingObjIdx, 0, 32));
        ObjectDelete(0, "tabel_totals" + IntegerToString(headingObjIdx, 0, 32));
    }
    for (rectObjIdx = 0; rectObjIdx < g_maxPanelObjects; rectObjIdx++)
    {
        ObjectDelete(0, "horizontalrect" + IntegerToString(rectObjIdx, 0, 32));
        ObjectDelete(0, "info_ea" + IntegerToString(rectObjIdx, 0, 32));
    }
}
//DeleteInfoPanel <<==--------   --------
string GetNextNFPText()
{
    // Original V4.6 panel reads only the single cached calendar timestamp.
    // It does not scan the hardcoded backtest table for display fallback.
    if (g_nextNFPCalendar != 0)
    {
        return("Next NFP: " + TimeToString(g_nextNFPCalendar, TIME_DATE | TIME_SECONDS));
    }
    return("no news coming up");
}
//GetNextNFPText <<==--------   --------
// ============================================================================
// 面板卡片式渲染（麒麟King 风格移植）
//   ScalePx / EnsureRect / EnsureText 为声明式绘制原语：对象不存在则创建，
//   已存在则就地更新，因此可在每次刷新时安全重复调用。
//   DrawTGRCards() 绘制头部下方的「账户 / 风控 / 状态」三张卡片，
//   并把策略表格的起始 Y 写入 g_panelTableY。
// ============================================================================
int ScalePx(const int value)
{
    return((int)MathRound(value * InfoPanelSizeAdjust));
}
void EnsureRect(const string name, const int x, const int y, const int w, const int h, const color bg, const color border)
{
    if (ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}
void EnsureText(const string name, const string text, const int x, const int y, const int font_size, const color clr)
{
    if (ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetString(0, name, OBJPROP_FONT, "Microsoft YaHei");
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}
void DeleteLegacyPanelLines()
{
    ObjectDelete(0, "line1");
    ObjectDelete(0, "linec");
    ObjectDelete(0, "line2");
    ObjectDelete(0, "lines");
    ObjectDelete(0, "linet");
    ObjectDelete(0, "lineTradeStart");
    for (int dlIdx = 0; dlIdx <= 99; dlIdx++)
    {
        ObjectDelete(0, "lineopl" + IntegerToString(dlIdx, 0, 32));
        ObjectDelete(0, "linehb" + IntegerToString(dlIdx, 0, 32));
        ObjectDelete(0, "linea" + IntegerToString(dlIdx, 0, 32));
        ObjectDelete(0, "linesp" + IntegerToString(dlIdx, 0, 32));
        ObjectDelete(0, "linetp" + IntegerToString(dlIdx, 0, 32));
        ObjectDelete(0, "linenfp" + IntegerToString(dlIdx, 0, 32));
    }
}
string GetTradeFrequencyText()
{
    if (g_tradeFrequencyMode == 0)   return("extreme conservative");
    if (g_tradeFrequencyMode == 1)   return("conservative");
    if (g_tradeFrequencyMode == 2)   return("moderate");
    if (g_tradeFrequencyMode == 3)   return("intense");
    if (g_tradeFrequencyMode == 4)   return("extreme");
    return("manual strategy selection");
}
string GetRiskText()
{
    if (Risk == 1234)   return("Max allowed DD: " + DoubleToString(MaxAllowedDD, 1) + "%");
    if (Risk == 3)      return("Max risk/strategy: " + DoubleToString(MaxRiskPerStrategy_, 2) + "%");
    return("Manual lotsize: " + DoubleToString(g_startLots_rw, 2) + " lots");
}
string GetDailyLimitText()
{
    if (PropFirmDailyLossUSD > 0.0)
    {
        return("Daily limit: " + DoubleToString(PropFirmDailyLossUSD, 2) + " USD (fixed)");
    }
    if (PropFirmMaxDailyDD > 0.0)
    {
        return("Daily limit: " + DoubleToString(PropFirmMaxDailyDD, 2) + "% of " +
               (PropFirmDailyLossStatic ? "day-start equity" : "peak equity"));
    }
    return("Daily limit: off");
}
string GetWorkStateText(const bool spreadHigh)
{
    if (g_propfirmDailyDDHit)     return("日内熔断 / daily DD hit");
    if (g_fridayStopDone)         return("周五收工 / friday stop");
    if (spreadHigh)               return("点差过大 / spread too high");
    return("工作中 / running");
}
color GetWorkStateColor(const bool spreadHigh)
{
    if (g_propfirmDailyDDHit)     return(g_panelBadColor);
    if (g_fridayStopDone)         return(g_panelWarnColor);
    if (spreadHigh)               return(g_panelBadColor);
    return(g_panelOkColor);
}
void DrawTGRCards()
{
    const int px = g_panelX;
    const int py = g_panelY;
    const int pw = (int)(g_panelWidth * InfoPanelSizeAdjust);
    const int pad = ScalePx(10);
    const int rowH = ScalePx(15);
    const int titleH = ScalePx(16);
    const int gap = ScalePx(8);
    const int fRow = g_panelFontSize + 1;
    const int fTitle = g_panelFontSize + 2;
    const int tx = px + pad + ScalePx(6);

    double oplNow = AccountEquity() - AccountBalance();
    double spreadNow = MarketInfo(g_chartSymbol, MODE_ASK) - MarketInfo(g_chartSymbol, MODE_BID);
    double spreadUnit = (g_pipSize > 0.0) ? g_pipSize : g_symbolPoint;
    double spreadLimit = MaxSpread * spreadUnit;
    bool  spreadHigh = (spreadNow > spreadLimit);

    int y = py + ScalePx(48) + gap;

    // ---------- 卡片 1：账户 ----------
    EnsureRect("card_account", px, y, pw, pad * 2 + titleH + 4 * rowH, C'24,33,45', C'45,58,74');
    y += pad;
    EnsureText("ca_title", "账 户   ACCOUNT", tx, y, fTitle, g_panelAccentColor);
    y += titleH;
    EnsureText("ca_balance", "Balance: " + DoubleToString(AccountBalance(), 2), tx, y, fRow, g_panelTextColor);
    y += rowH;
    EnsureText("ca_equity", "Equity: " + DoubleToString(AccountEquity(), 2), tx, y, fRow, g_panelTextColor);
    y += rowH;
    EnsureText("ca_peak", "Peak Balance: " + DoubleToString(g_highestBalance, 2), tx, y, fRow, g_panelMutedColor);
    y += rowH;
    EnsureText("ca_opl", "Open P/L: " + DoubleToString(oplNow, 2), tx, y, fRow,
               (oplNow > 0.0) ? g_panelOkColor : ((oplNow < 0.0) ? g_panelBadColor : g_panelTextColor));
    y += rowH + pad + gap;

    // ---------- 卡片 2：风控 ----------
    EnsureRect("card_risk", px, y, pw, pad * 2 + titleH + 4 * rowH, C'24,33,45', C'45,58,74');
    y += pad;
    EnsureText("cr_title", "风 控   RISK", tx, y, fTitle, g_panelAccentColor);
    y += titleH;
    EnsureText("cr_freq", "Frequency: " + GetTradeFrequencyText(), tx, y, fRow, g_panelTextColor);
    y += rowH;
    EnsureText("cr_risk", GetRiskText(), tx, y, fRow, g_panelTextColor);
    y += rowH;
    EnsureText("cr_daily", GetDailyLimitText(), tx, y, fRow,
               (g_propfirmDailyDDHit ? g_panelBadColor : g_panelTextColor));
    y += rowH;
    EnsureText("cr_spread", "Spread: " + DoubleToString(spreadNow, g_symbolDigits) +
               "  (" + DoubleToString(spreadNow / spreadUnit, 0) + " / " + DoubleToString(MaxSpread, 0) + ")" +
               (spreadHigh ? "  HIGH" : ""), tx, y, fRow,
               spreadHigh ? g_panelBadColor : g_panelTextColor);
    y += rowH + pad + gap;

    // ---------- 卡片 3：状态 ----------
    EnsureRect("card_state", px, y, pw, pad * 2 + titleH + 2 * rowH, C'24,33,45', C'45,58,74');
    y += pad;
    EnsureText("cs_title", "状 态   STATUS", tx, y, fTitle, g_panelAccentColor);
    y += titleH;
    EnsureText("cs_state", "State: " + GetWorkStateText(spreadHigh), tx, y, fRow, GetWorkStateColor(spreadHigh));
    y += rowH;
    EnsureText("cs_nfp", GetNextNFPText(), tx, y, fRow, g_panelMutedColor);
    y += rowH + pad;

    g_panelTableY = y + gap;
}
//DrawTGRCards <<==--------   --------
void UpdateAccountPanel()
{
    string    frequencyText;
    //----- -----
    double     openPLDisplay;
    double     openPLSum;
    int        orderScanIdx;
    int        magicVal1;
    int        magicRef1;
    int        magicVal2;
    int        magicRef2;
    int        magicVal3;
    int        magicRef3;
    int        magicVal4;
    int        magicRef4;
    int        magicVal5;
    int        magicRef5;
    int        magicVal6;
    int        magicRef6;
    int        magicVal7;
    int        magicRef7;
    int        magicVal8;
    int        magicRef8;

    if (!(ShowInfoPanel))   return;

    if ((MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting)))   return;

    if (MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting))
    {
        openPLDisplay = 0.0;
    }
    else
    {
        openPLSum = 0.0;
        for (orderScanIdx = MT4OrdersTotal(); orderScanIdx >= 0; orderScanIdx = orderScanIdx - 1)
        {
            if (OrderSelect(orderScanIdx, 0, 0) != true)   continue;

            if ((OrderSymbol() != g_chartSymbol && !(g_manageAllSymbols)))   continue;
            magicVal1 = OrderMagicNumber();
            magicRef1 = ST1_MagicNumber + 1;
            if (magicVal1 != magicRef1)
            {
                magicRef1 = OrderMagicNumber();
                magicVal2 = ST1_MagicNumber + 2;
                if (magicRef1 != magicVal2)
                {
                    magicVal2 = OrderMagicNumber();
                    magicRef2 = ST1_MagicNumber + 3;
                    if (magicVal2 != magicRef2)
                    {
                        magicRef2 = OrderMagicNumber();
                        magicVal3 = ST1_MagicNumber + 4;
                        if (magicRef2 != magicVal3)
                        {
                            magicVal3 = OrderMagicNumber();
                            magicRef3 = ST1_MagicNumber + 5;
                            if (magicVal3 != magicRef3)
                            {
                                magicRef3 = OrderMagicNumber();
                                magicVal4 = ST1_MagicNumber + 6;
                                if (magicRef3 != magicVal4)
                                {
                                    magicVal4 = OrderMagicNumber();
                                    magicRef4 = ST1_MagicNumber + 7;
                                    if (magicVal4 != magicRef4)
                                    {
                                        magicRef4 = OrderMagicNumber();
                                        magicVal5 = ST1_MagicNumber + 8;
                                        if (magicRef4 != magicVal5)
                                        {
                                            magicVal5 = OrderMagicNumber();
                                            magicRef5 = ST1_MagicNumber + 9;
                                            if (magicVal5 != magicRef5)
                                            {
                                                magicRef5 = OrderMagicNumber();
                                                magicVal6 = ST1_MagicNumber + 10;
                                                if (magicRef5 != magicVal6)
                                                {
                                                    magicVal6 = OrderMagicNumber();
                                                    magicRef6 = ST1_MagicNumber + 11;
                                                    if (magicVal6 != magicRef6)
                                                    {
                                                        magicRef6 = OrderMagicNumber();
                                                        magicVal7 = ST1_MagicNumber + 12;
                                                        if (magicRef6 != magicVal7)
                                                        {
                                                            magicVal7 = OrderMagicNumber();
                                                            magicRef7 = ST1_MagicNumber + 13;
                                                            if (magicVal7 != magicRef7)
                                                            {
                                                                magicRef7 = OrderMagicNumber();
                                                                magicVal8 = ST1_MagicNumber + 14;
                                                                if (magicRef7 != magicVal8)
                                                                {
                                                                    magicVal8 = OrderMagicNumber();
                                                                    magicRef8 = ST1_MagicNumber + 15;
                                                                    if (magicVal8 != magicRef8)   continue;
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
            if ((OrderType() != 0 && OrderType() != 1))   continue;
            openPLSum = OrderProfit() + OrderSwap() + OrderCommission() + openPLSum;

        }
        g_openPLbyStrategy[g_currentStrategyIndex] = openPLSum;
        openPLDisplay = openPLSum;
    }
    ObjectSetString(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Open P/L: " + DoubleToString(openPLDisplay, 2));
    ObjectSetInteger(0, "lineopl" + IntegerToString(0, 0, 32), OBJPROP_COLOR,
                     (openPLDisplay > 0.0) ? g_panelOkColor : ((openPLDisplay < 0.0) ? g_panelBadColor : g_panelTextColor));
    ObjectSetString(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Higher Balance: " + DoubleToString(g_highestBalance, 2));
    ObjectSetInteger(0, "linehb" + IntegerToString(0, 0, 32), OBJPROP_COLOR, g_panelMutedColor);
    ObjectSetString(0, "linea" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Account Balance: " + DoubleToString(AccountBalance(), 2));
    if (g_tradeFrequencyMode == 1)
    {
        frequencyText = "conservative";
    }
    else
    {
        if (g_tradeFrequencyMode == 2)
        {
            frequencyText = "moderate";
        }
        else
        {
            if (g_tradeFrequencyMode == 3)
            {
                frequencyText = "intense";
            }
            else
            {
                if (g_tradeFrequencyMode == 4)
                {
                    frequencyText = "extreme";
                }
                else
                {
                    if (g_tradeFrequencyMode == 0)
                    {
                        frequencyText = "extreme conservative";
                    }
                    else
                    {
                        frequencyText = "manual strategy selection";
                    }
                }
            }
        }
    }
    ObjectSetString(0, "lines", OBJPROP_TEXT, "Trade Frequency: " + frequencyText);
    if (Risk == 1234)
    {
        ObjectSetString(0, "linet", OBJPROP_TEXT, "Max allowed DD: " + string(MaxAllowedDD) + "%");
    }
    else
    {
        if (Risk == 3)
        {
            ObjectSetString(0, "linet", OBJPROP_TEXT, "Max risk per strategy: " + string(MaxRiskPerStrategy_) + "%");
        }
        else
        {
            ObjectSetString(0, "linet", OBJPROP_TEXT, "Manual lotsize: " + string(g_startLots_rw) + "lots");
        }
    }
    // 卡片式渲染（含点差、状态、风控等信息）；旧的散装标签在面板重建时已移除
    DrawTGRCards();
}
//UpdateAccountPanel <<==--------   --------
void UpdateStrategyPanelRows()
{
    int       cellObjIdx;
    string    cellText;
    int       strategyIdx;
    //----- -----

    if (!(ShowInfoPanel))   return;

    if ((MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting)))   return;
    cellObjIdx = g_panelStrategyRowStart;
    for (strategyIdx = 0; strategyIdx < 9; strategyIdx++)
    {
        cellText = "Strategy " + IntegerToString(strategyIdx + 1, 0, 32);
        ObjectSetString(0, "info_ea" + IntegerToString(cellObjIdx, 0, 32), OBJPROP_TEXT, cellText);
        cellObjIdx++;
        cellText = DoubleToString(NormalizeDouble(g_histClosedPLbyStrategy[strategyIdx], 2), 2);
        ObjectSetString(0, "info_ea" + IntegerToString(cellObjIdx, 0, 32), OBJPROP_TEXT, cellText);
        cellObjIdx++;
        cellText = DoubleToString(NormalizeDouble(g_avgPLperTrade[strategyIdx], 2), 2);
        ObjectSetString(0, "info_ea" + IntegerToString(cellObjIdx, 0, 32), OBJPROP_TEXT, cellText);
        cellObjIdx++;
        cellText = DoubleToString(NormalizeDouble(g_strategyStartLots[strategyIdx], 2), 2);
        ObjectSetString(0, "info_ea" + IntegerToString(cellObjIdx, 0, 32), OBJPROP_TEXT, cellText);
        cellObjIdx++;
    }
}
//UpdateStrategyPanelRows <<==--------   --------
void UpdateHistoryPanel()
{
    double     totalPLDisplay;
    double     totalPLSum;
    int        countedTrades;
    int        historyScanIdx;
    int        magicVal1;
    int        magicRef1;
    int        magicVal2;
    int        magicRef2;
    int        magicVal3;
    int        magicRef3;
    int        magicVal4;
    int        magicRef4;
    int        magicVal5;
    int        magicRef5;
    int        magicVal6;
    int        magicRef6;
    int        magicVal7;
    int        magicRef7;
    int        magicVal8;
    int        magicRef8;

    if (!(ShowInfoPanel))   return;

    if ((MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting)))   return;
    ObjectSetString(0, "lineto" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Total profits/losses so far: " + IntegerToString(CountWinningTrades(0, 9999999), 0, 32) + "/" + IntegerToString(CountLosingTrades(0, 9999999), 0, 32));
    if (MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting))
    {
        totalPLDisplay = 0.0;
    }
    else
    {
        totalPLSum = 0.0;
        countedTrades = 0;
        for (historyScanIdx = HistoryTotal(); historyScanIdx >= 0; historyScanIdx = historyScanIdx - 1)
        {
            if (OrderSelect(historyScanIdx, 0, 1) != true)   continue;

            if ((OrderSymbol() != g_chartSymbol && !(g_manageAllSymbols)))   continue;
            magicVal1 = OrderMagicNumber();
            magicRef1 = ST1_MagicNumber + 1;
            if (magicVal1 != magicRef1)
            {
                magicRef1 = OrderMagicNumber();
                magicVal2 = ST1_MagicNumber + 2;
                if (magicRef1 != magicVal2)
                {
                    magicVal2 = OrderMagicNumber();
                    magicRef2 = ST1_MagicNumber + 3;
                    if (magicVal2 != magicRef2)
                    {
                        magicRef2 = OrderMagicNumber();
                        magicVal3 = ST1_MagicNumber + 4;
                        if (magicRef2 != magicVal3)
                        {
                            magicVal3 = OrderMagicNumber();
                            magicRef3 = ST1_MagicNumber + 5;
                            if (magicVal3 != magicRef3)
                            {
                                magicRef3 = OrderMagicNumber();
                                magicVal4 = ST1_MagicNumber + 6;
                                if (magicRef3 != magicVal4)
                                {
                                    magicVal4 = OrderMagicNumber();
                                    magicRef4 = ST1_MagicNumber + 7;
                                    if (magicVal4 != magicRef4)
                                    {
                                        magicRef4 = OrderMagicNumber();
                                        magicVal5 = ST1_MagicNumber + 8;
                                        if (magicRef4 != magicVal5)
                                        {
                                            magicVal5 = OrderMagicNumber();
                                            magicRef5 = ST1_MagicNumber + 9;
                                            if (magicVal5 != magicRef5)
                                            {
                                                magicRef5 = OrderMagicNumber();
                                                magicVal6 = ST1_MagicNumber + 10;
                                                if (magicRef5 != magicVal6)
                                                {
                                                    magicVal6 = OrderMagicNumber();
                                                    magicRef6 = ST1_MagicNumber + 11;
                                                    if (magicVal6 != magicRef6)
                                                    {
                                                        magicRef6 = OrderMagicNumber();
                                                        magicVal7 = ST1_MagicNumber + 12;
                                                        if (magicRef6 != magicVal7)
                                                        {
                                                            magicVal7 = OrderMagicNumber();
                                                            magicRef7 = ST1_MagicNumber + 13;
                                                            if (magicVal7 != magicRef7)
                                                            {
                                                                magicRef7 = OrderMagicNumber();
                                                                magicVal8 = ST1_MagicNumber + 14;
                                                                if (magicRef7 != magicVal8)
                                                                {
                                                                    magicVal8 = OrderMagicNumber();
                                                                    magicRef8 = ST1_MagicNumber + 15;
                                                                    if (magicVal8 != magicRef8)   continue;
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
            countedTrades = countedTrades + 1;
            totalPLSum = totalPLSum + OrderProfit() + OrderSwap() + OrderCommission();
            if (countedTrades >= 1000)   break;

        }
        g_totalPLbyStrategy[g_currentStrategyIndex] = totalPLSum;
        totalPLDisplay = totalPLSum;
    }
    ObjectSetString(0, "linetp" + IntegerToString(0, 0, 32), OBJPROP_TEXT, "Total P/L so far: " + DoubleToString(NormalizeDouble(totalPLDisplay, 2), 2));
    if (EnableNFP_Filter)
    {
        ObjectSetString(0, "linenfp" + IntegerToString(0, 0, 32), OBJPROP_TEXT, GetNextNFPText());
    }
}
//UpdateHistoryPanel <<==--------   --------
int CountWinningTrades(int scanFromIdx, int maxTradesToScan)
{
    double    tradePriceDiff;
    int       scannedCount;
    int       winCount;
    int       historyScanIdx;
    //----- -----
    int        magicVal1;
    int        magicRef1;
    int        magicVal2;
    int        magicRef2;
    int        magicVal3;
    int        magicRef3;
    int        magicVal4;
    int        magicRef4;
    int        magicVal5;
    int        magicRef5;
    int        magicVal6;
    int        magicRef6;
    int        magicVal7;
    int        magicRef7;
    int        magicVal8;
    int        magicRef8;

    if (MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting))
    {
        return(0);
    }
    tradePriceDiff = 0.0;
    scannedCount = 0;
    winCount = 0;
    for (historyScanIdx = HistoryTotal(); historyScanIdx >= 0; historyScanIdx--)
    {
        if (OrderSelect(historyScanIdx, 0, 1) != true)   continue;

        if ((OrderSymbol() != g_chartSymbol && !(g_manageAllSymbols)))   continue;
        magicVal1 = OrderMagicNumber();
        magicRef1 = ST1_MagicNumber + 1;
        if (magicVal1 != magicRef1)
        {
            magicRef1 = OrderMagicNumber();
            magicVal2 = ST1_MagicNumber + 2;
            if (magicRef1 != magicVal2)
            {
                magicVal2 = OrderMagicNumber();
                magicRef2 = ST1_MagicNumber + 3;
                if (magicVal2 != magicRef2)
                {
                    magicRef2 = OrderMagicNumber();
                    magicVal3 = ST1_MagicNumber + 4;
                    if (magicRef2 != magicVal3)
                    {
                        magicVal3 = OrderMagicNumber();
                        magicRef3 = ST1_MagicNumber + 5;
                        if (magicVal3 != magicRef3)
                        {
                            magicRef3 = OrderMagicNumber();
                            magicVal4 = ST1_MagicNumber + 6;
                            if (magicRef3 != magicVal4)
                            {
                                magicVal4 = OrderMagicNumber();
                                magicRef4 = ST1_MagicNumber + 7;
                                if (magicVal4 != magicRef4)
                                {
                                    magicRef4 = OrderMagicNumber();
                                    magicVal5 = ST1_MagicNumber + 8;
                                    if (magicRef4 != magicVal5)
                                    {
                                        magicVal5 = OrderMagicNumber();
                                        magicRef5 = ST1_MagicNumber + 9;
                                        if (magicVal5 != magicRef5)
                                        {
                                            magicRef5 = OrderMagicNumber();
                                            magicVal6 = ST1_MagicNumber + 10;
                                            if (magicRef5 != magicVal6)
                                            {
                                                magicVal6 = OrderMagicNumber();
                                                magicRef6 = ST1_MagicNumber + 11;
                                                if (magicVal6 != magicRef6)
                                                {
                                                    magicRef6 = OrderMagicNumber();
                                                    magicVal7 = ST1_MagicNumber + 12;
                                                    if (magicRef6 != magicVal7)
                                                    {
                                                        magicVal7 = OrderMagicNumber();
                                                        magicRef7 = ST1_MagicNumber + 13;
                                                        if (magicVal7 != magicRef7)
                                                        {
                                                            magicRef7 = OrderMagicNumber();
                                                            magicVal8 = ST1_MagicNumber + 14;
                                                            if (magicRef7 != magicVal8)
                                                            {
                                                                magicVal8 = OrderMagicNumber();
                                                                magicRef8 = ST1_MagicNumber + 15;
                                                                if (magicVal8 != magicRef8)   continue;
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
        scannedCount++;
        if ((OrderType() == 0 || OrderType() == 1))
        {
            if (OrderType() == 0)
            {
                tradePriceDiff = OrderClosePrice() - OrderOpenPrice();
            }
            else
            {
                if (OrderType() == 1)
                {
                    tradePriceDiff = OrderOpenPrice() - OrderClosePrice();
                }
            }
            if (tradePriceDiff > 0.0)
            {
                winCount++;
            }
        }
        if (scannedCount >= maxTradesToScan)   break;

    }
    g_winTradeCount[g_currentStrategyIndex] = winCount;
    return(winCount);
}
//CountWinningTrades <<==--------   --------
int CountLosingTrades(int scanFromIdx, int maxTradesToScan)
{
    double    tradePriceDiff;
    int       scannedCount;
    int       loseCount;
    int       historyScanIdx;
    //----- -----
    int        magicVal1;
    int        magicRef1;
    int        magicVal2;
    int        magicRef2;
    int        magicVal3;
    int        magicRef3;
    int        magicVal4;
    int        magicRef4;
    int        magicVal5;
    int        magicRef5;
    int        magicVal6;
    int        magicRef6;
    int        magicVal7;
    int        magicRef7;
    int        magicVal8;
    int        magicRef8;

    if (MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting))
    {
        return(0);
    }
    tradePriceDiff = 0.0;
    scannedCount = 0;
    loseCount = 0;
    for (historyScanIdx = HistoryTotal(); historyScanIdx >= 0; historyScanIdx--)
    {
        if (OrderSelect(historyScanIdx, 0, 1) != true)   continue;

        if ((OrderSymbol() != g_chartSymbol && !(g_manageAllSymbols)))   continue;
        magicVal1 = OrderMagicNumber();
        magicRef1 = ST1_MagicNumber + 1;
        if (magicVal1 != magicRef1)
        {
            magicRef1 = OrderMagicNumber();
            magicVal2 = ST1_MagicNumber + 2;
            if (magicRef1 != magicVal2)
            {
                magicVal2 = OrderMagicNumber();
                magicRef2 = ST1_MagicNumber + 3;
                if (magicVal2 != magicRef2)
                {
                    magicRef2 = OrderMagicNumber();
                    magicVal3 = ST1_MagicNumber + 4;
                    if (magicRef2 != magicVal3)
                    {
                        magicVal3 = OrderMagicNumber();
                        magicRef3 = ST1_MagicNumber + 5;
                        if (magicVal3 != magicRef3)
                        {
                            magicRef3 = OrderMagicNumber();
                            magicVal4 = ST1_MagicNumber + 6;
                            if (magicRef3 != magicVal4)
                            {
                                magicVal4 = OrderMagicNumber();
                                magicRef4 = ST1_MagicNumber + 7;
                                if (magicVal4 != magicRef4)
                                {
                                    magicRef4 = OrderMagicNumber();
                                    magicVal5 = ST1_MagicNumber + 8;
                                    if (magicRef4 != magicVal5)
                                    {
                                        magicVal5 = OrderMagicNumber();
                                        magicRef5 = ST1_MagicNumber + 9;
                                        if (magicVal5 != magicRef5)
                                        {
                                            magicRef5 = OrderMagicNumber();
                                            magicVal6 = ST1_MagicNumber + 10;
                                            if (magicRef5 != magicVal6)
                                            {
                                                magicVal6 = OrderMagicNumber();
                                                magicRef6 = ST1_MagicNumber + 11;
                                                if (magicVal6 != magicRef6)
                                                {
                                                    magicRef6 = OrderMagicNumber();
                                                    magicVal7 = ST1_MagicNumber + 12;
                                                    if (magicRef6 != magicVal7)
                                                    {
                                                        magicVal7 = OrderMagicNumber();
                                                        magicRef7 = ST1_MagicNumber + 13;
                                                        if (magicVal7 != magicRef7)
                                                        {
                                                            magicRef7 = OrderMagicNumber();
                                                            magicVal8 = ST1_MagicNumber + 14;
                                                            if (magicRef7 != magicVal8)
                                                            {
                                                                magicVal8 = OrderMagicNumber();
                                                                magicRef8 = ST1_MagicNumber + 15;
                                                                if (magicVal8 != magicRef8)   continue;
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
        scannedCount++;
        if (OrderType() == 0)
        {
            tradePriceDiff = OrderClosePrice() - OrderOpenPrice();
        }
        else
        {
            if (OrderType() == 1)
            {
                tradePriceDiff = OrderOpenPrice() - OrderClosePrice();
            }
        }
        if (tradePriceDiff < 0.0)
        {
            loseCount++;
        }
        if (scannedCount >= maxTradesToScan)   break;

    }
    g_lossTradeCount[g_currentStrategyIndex] = loseCount;
    return(loseCount);
}
//CountLosingTrades <<==--------   --------
void CalculatePerformanceMetrics()
{
    double    statPL[99];
    double    recentPL[99];
    int       strategyIdx;
    int       historyScanIdx;
    bool      allMinTradesReached;
    int       checkScanIdx;
    double    tradeWeight;
    int       strategyMatchIdx;
    int       publishIdx;
    //----- -----
    long       closeTimeChk;
    long       windowStartChk;
    long       windowStartChk2;
    long       closeTimeRecent;
    long       recentStartChk;

    if ((MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting)))   return;
    for (strategyIdx = 0; strategyIdx < g_strategyCount; strategyIdx++)
    {
        statPL[strategyIdx] = 0.0;
        recentPL[strategyIdx] = 0.0;
        g_minTradesReachedFlag[strategyIdx] = false;
        g_closedTradeCount[strategyIdx] = 0;
    }
    for (historyScanIdx = HistoryTotal(); historyScanIdx >= 0; historyScanIdx--)
    {
        if (OrderSelect(historyScanIdx, 0, 1) != true || OrderMagicNumber() != g_curStrategyMagic)   continue;
        allMinTradesReached = true;
        for (checkScanIdx = 0; checkScanIdx < g_strategyCount; checkScanIdx++)
        {
            if (!(g_minTradesReachedFlag[checkScanIdx]))
            {
                allMinTradesReached = false;
            }
        }
        if ((OrderCloseTime() < TimeCurrent() - g_statWindowDays * 24 * 60 * 60 && allMinTradesReached))   break;
        tradeWeight = OrderLots() * 100.0;
        if (g_statWeightPerTrade == 1)
        {
            tradeWeight = 1.0;
        }
        strategyMatchIdx = 0;
        if (g_strategyCount <= 0)   continue;

        for (; strategyMatchIdx < g_strategyCount; strategyMatchIdx++)
        {
            if (g_strategySymbols[strategyMatchIdx] != OrderSymbol())   continue;

            if ((OrderType() != 0 && OrderType() != 1))   continue;
            closeTimeChk = OrderCloseTime();
            windowStartChk = TimeCurrent() - g_statWindowDays * 24 * 60 * 60;
            if (closeTimeChk < windowStartChk)
            {
                windowStartChk = OrderCloseTime();
                windowStartChk2 = TimeCurrent() - g_statWindowDays * 24 * 60 * 60;
                if ((windowStartChk >= windowStartChk2 || g_minTradesReachedFlag[strategyMatchIdx]))   continue;
            }
            g_closedTradeCount[strategyMatchIdx]++;
            if (g_closedTradeCount[strategyMatchIdx] >= g_statMinTrades)
            {
                g_minTradesReachedFlag[strategyMatchIdx] = true;
            }
            statPL[strategyMatchIdx] += OrderProfit() / tradeWeight;
            statPL[strategyMatchIdx] += OrderSwap() / tradeWeight;
            statPL[strategyMatchIdx] += OrderCommission() / tradeWeight;
            closeTimeRecent = OrderCloseTime();
            recentStartChk = TimeCurrent() - g_statRecentDays * 24 * 60 * 60;
            if (closeTimeRecent < recentStartChk)   continue;
            recentPL[strategyMatchIdx] += OrderProfit() / tradeWeight;
            recentPL[strategyMatchIdx] += OrderSwap() / tradeWeight;
            recentPL[strategyMatchIdx] += OrderCommission() / tradeWeight;

        }

    }
    for (publishIdx = 0; publishIdx < g_strategyCount; publishIdx++)
    {
        g_statTotalPL[publishIdx] = statPL[publishIdx];
        if (g_closedTradeCount[publishIdx] > 0)
        {
            g_avgPLperTrade[publishIdx] = NormalizeDouble(statPL[publishIdx] / g_closedTradeCount[publishIdx], 2);
        }
        else
        {
            g_avgPLperTrade[publishIdx] = 0.0;
        }
        g_recentPLbyStrategy[publishIdx] = recentPL[publishIdx];
    }
}
//CalculatePerformanceMetrics <<==--------   --------
void RankStrategiesByClosedProfit()
{
    int       stratIdx;
    double    stratMetric;
    int       rankScore;
    int       cmpIdx;
    int       ownerIdx;
    bool      ranksAdjusted;
    int       bumpScanIdx;
    //----- -----

    CalculatePerformanceMetrics();
    for (stratIdx = 0; stratIdx < g_strategyCount; stratIdx++)
    {
        stratMetric = g_statTotalPL[stratIdx];
        rankScore = 1;
        for (cmpIdx = 0; cmpIdx < g_strategyCount; cmpIdx++)
        {
            if (cmpIdx == stratIdx || !(g_statTotalPL[cmpIdx] > stratMetric))   continue;
            rankScore++;

        }
        g_statRankScore[stratIdx] = rankScore;
    }
    for (ownerIdx = 0; ownerIdx < g_strategyCount; ownerIdx++)
    {
        ranksAdjusted = true;
        do
        {
            ranksAdjusted = false;
            bumpScanIdx = 0;
            if (g_strategyCount <= 0)   continue;

            for (; bumpScanIdx < g_strategyCount; bumpScanIdx++)
            {
                if (bumpScanIdx == ownerIdx || g_statRankScore[bumpScanIdx] != g_statRankScore[ownerIdx])   continue;
                g_statRankScore[bumpScanIdx]++;
                ranksAdjusted = true;

            }

        } while (ranksAdjusted);

    }
}
//RankStrategiesByClosedProfit <<==--------   --------
void RankStrategiesByProfitPerTrade()
{
    int       stratIdx;
    double    stratMetric;
    int       rankScore;
    int       cmpIdx;
    int       ownerIdx;
    bool      ranksAdjusted;
    int       bumpScanIdx;
    //----- -----

    CalculatePerformanceMetrics();
    for (stratIdx = 0; stratIdx < g_strategyCount; stratIdx++)
    {
        stratMetric = g_avgPLperTrade[stratIdx];
        rankScore = 1;
        for (cmpIdx = 0; cmpIdx < g_strategyCount; cmpIdx++)
        {
            if (cmpIdx == stratIdx || !(g_avgPLperTrade[cmpIdx] > stratMetric))   continue;
            rankScore++;

        }
        g_statRankScore[stratIdx] = rankScore;
    }
    for (ownerIdx = 0; ownerIdx < g_strategyCount; ownerIdx++)
    {
        ranksAdjusted = true;
        do
        {
            ranksAdjusted = false;
            bumpScanIdx = 0;
            if (g_strategyCount <= 0)   continue;

            for (; bumpScanIdx < g_strategyCount; bumpScanIdx++)
            {
                if (bumpScanIdx == ownerIdx || g_statRankScore[bumpScanIdx] != g_statRankScore[ownerIdx])   continue;
                g_statRankScore[bumpScanIdx]++;
                ranksAdjusted = true;

            }

        } while (ranksAdjusted);

    }
}
//RankStrategiesByProfitPerTrade <<==--------   --------
double ConvertUsdToAccountCurrency(double usdAmount)
{
    double    accountAmount;
    string    rateSymbol;
    //----- -----

    accountAmount = usdAmount;
    if ((AccountCurrency() == "USD" || AccountCurrency() == "usd"))
    {
        accountAmount = usdAmount;
    }
    if ((AccountCurrency() == "EUR" || AccountCurrency() == "eur"))
    {
        rateSymbol = "EURUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "GBP" || AccountCurrency() == "gbp"))
    {
        rateSymbol = "GBPUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "AUD" || AccountCurrency() == "aud"))
    {
        rateSymbol = "AUDUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "JPY" || AccountCurrency() == "jpy" || AccountCurrency() == "YEN" || AccountCurrency() == "yen"))
    {
        rateSymbol = "USDJPY" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "CHF" || AccountCurrency() == "chf"))
    {
        rateSymbol = "USDCHF" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "HKD" || AccountCurrency() == "hkd"))
    {
        rateSymbol = "USDHKD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "SGD" || AccountCurrency() == "sgd"))
    {
        rateSymbol = "USDSGD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "RUB" || AccountCurrency() == "rub"))
    {
        rateSymbol = "USDRUB" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "BTC" || AccountCurrency() == "btc"))
    {
        rateSymbol = "BTCUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "ETH" || AccountCurrency() == "eth"))
    {
        rateSymbol = "ETHUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "BCH" || AccountCurrency() == "bch"))
    {
        rateSymbol = "BCHUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "BCC" || AccountCurrency() == "bcc"))
    {
        rateSymbol = "BCCUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "XRP" || AccountCurrency() == "xrp"))
    {
        rateSymbol = "XRPUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "LTC" || AccountCurrency() == "ltc"))
    {
        rateSymbol = "LTCUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "XMR" || AccountCurrency() == "xmr"))
    {
        rateSymbol = "XMRUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "DSH" || AccountCurrency() == "dsh"))
    {
        rateSymbol = "DSHUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "EOS" || AccountCurrency() == "eos"))
    {
        rateSymbol = "EOSUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "TRX" || AccountCurrency() == "trx"))
    {
        rateSymbol = "TRXUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "ADA" || AccountCurrency() == "ada"))
    {
        rateSymbol = "ADAUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "BSV" || AccountCurrency() == "bsv"))
    {
        rateSymbol = "BSVUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "XLM" || AccountCurrency() == "xlm"))
    {
        rateSymbol = "XLMUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "GLD" || AccountCurrency() == "gld"))
    {
        rateSymbol = "GLDUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "ZEC" || AccountCurrency() == "zec"))
    {
        rateSymbol = "ZECUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountCurrency() == "XEM" || AccountCurrency() == "xem"))
    {
        rateSymbol = "XEMUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            accountAmount = usdAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    return(accountAmount);
}
//ConvertUsdToAccountCurrency <<==--------   --------
double ConvertAccountCurrencyToUsd(double accountAmount)
{
    double    usdAmount;
    string    rateSymbol;
    //----- -----

    usdAmount = accountAmount;
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    if (accountCurrency == "USD" || accountCurrency == "usd")
    {
        return(MathRound(accountAmount));
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "USD" || AccountInfoString(ACCOUNT_CURRENCY) == "usd"))
    {
        usdAmount = accountAmount;
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "EUR" || AccountInfoString(ACCOUNT_CURRENCY) == "eur"))
    {
        rateSymbol = "EURUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "GBP" || AccountInfoString(ACCOUNT_CURRENCY) == "gbp"))
    {
        rateSymbol = "GBPUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "AUD" || AccountInfoString(ACCOUNT_CURRENCY) == "aud"))
    {
        rateSymbol = "AUDUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "JPY" || AccountInfoString(ACCOUNT_CURRENCY) == "jpy" || AccountInfoString(ACCOUNT_CURRENCY) == "YEN" || AccountInfoString(ACCOUNT_CURRENCY) == "yen"))
    {
        rateSymbol = "USDJPY" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "CHF" || AccountInfoString(ACCOUNT_CURRENCY) == "chf"))
    {
        rateSymbol = "USDCHF" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "HKD" || AccountInfoString(ACCOUNT_CURRENCY) == "hkd"))
    {
        rateSymbol = "USDHKD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "RUB" || AccountInfoString(ACCOUNT_CURRENCY) == "rub"))
    {
        rateSymbol = "USDRUB" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "CNH" || AccountInfoString(ACCOUNT_CURRENCY) == "cnh"))
    {
        rateSymbol = "USDCNH" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
        else
        {
            rateSymbol = "USDCNY" + g_symbolSuffix;
            if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
            {
                usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
            }
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "CNY" || AccountInfoString(ACCOUNT_CURRENCY) == "cny"))
    {
        rateSymbol = "USDCNH" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
        else
        {
            rateSymbol = "USDCNY" + g_symbolSuffix;
            if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
            {
                usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
            }
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "SGD" || AccountInfoString(ACCOUNT_CURRENCY) == "sgd"))
    {
        rateSymbol = "USDSGD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount / iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "BTC" || AccountInfoString(ACCOUNT_CURRENCY) == "btc"))
    {
        rateSymbol = "BTCUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "ETH" || AccountInfoString(ACCOUNT_CURRENCY) == "eth"))
    {
        rateSymbol = "ETHUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "BCH" || AccountInfoString(ACCOUNT_CURRENCY) == "bch"))
    {
        rateSymbol = "BCHUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "BCC" || AccountInfoString(ACCOUNT_CURRENCY) == "bcc"))
    {
        rateSymbol = "BCCUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "XRP" || AccountInfoString(ACCOUNT_CURRENCY) == "xrp"))
    {
        rateSymbol = "XRPUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "LTC" || AccountInfoString(ACCOUNT_CURRENCY) == "ltc"))
    {
        rateSymbol = "LTCUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "XMR" || AccountInfoString(ACCOUNT_CURRENCY) == "xmr"))
    {
        rateSymbol = "XMRUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "DSH" || AccountInfoString(ACCOUNT_CURRENCY) == "dsh"))
    {
        rateSymbol = "DSHUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "EOS" || AccountInfoString(ACCOUNT_CURRENCY) == "eos"))
    {
        rateSymbol = "EOSUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "TRX" || AccountInfoString(ACCOUNT_CURRENCY) == "trx"))
    {
        rateSymbol = "TRXUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "ADA" || AccountInfoString(ACCOUNT_CURRENCY) == "ada"))
    {
        rateSymbol = "ADAUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "BSV" || AccountInfoString(ACCOUNT_CURRENCY) == "bsv"))
    {
        rateSymbol = "BSVUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "XLM" || AccountInfoString(ACCOUNT_CURRENCY) == "xlm"))
    {
        rateSymbol = "XLMUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "GLD" || AccountInfoString(ACCOUNT_CURRENCY) == "gld"))
    {
        rateSymbol = "GLDUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "ZEC" || AccountInfoString(ACCOUNT_CURRENCY) == "zec"))
    {
        rateSymbol = "ZECUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    if ((AccountInfoString(ACCOUNT_CURRENCY) == "XEM" || AccountInfoString(ACCOUNT_CURRENCY) == "xem"))
    {
        rateSymbol = "XEMUSD" + g_symbolSuffix;
        if (iClose(rateSymbol, MT4Period(PERIOD_D1), 1) > 0.0)
        {
            usdAmount = accountAmount * iClose(rateSymbol, MT4Period(PERIOD_D1), 1);
        }
    }
    return(MathRound(usdAmount));
}
//ConvertAccountCurrencyToUsd <<==--------   --------
// ============================================================================
// [§16] 各策略参数装载（LoadStrategy1~9Settings）
//       把 V4.6 内置的每策略参数写入 §5 的全局变量表；由 TradeFrequency
//       （自动/手动 RunStratN）决定装载哪些策略并交给 ProcessStrategy 执行。
//       函数体均直接恢复自 JIT 常量表，数值不可随意改动。
// ----------------------------------------------------------------------------
//  【九套策略的挂单节奏总表】
//    · 挂单（进场）只在「信号周期出现新 K 线」时评估一次，不是每个 tick 都挂单。
//      判定见 ProcessStrategy：iBars(信号周期) 变化才进入 ProcessStrategyEntries，
//      随后循环尝试 g_maxPendingOrders 次（多数尝试因条件不满足而放弃）。
//    · 挂单还必须同时满足：找到分形 / 距现价 ≥ entryBreakoutPips / 不低于-不高于
//      入场周期区间极值 / MA 方向正确 / 不与已有挂单重复 / 挂单数未满 / 点差正常 /
//      时段开放 / 非周五收工 / 非 NFP 窗口 / 保证金充足。
//    · 日志里频繁的"撤了再挂"并非新信号，而是：手数变化重建（余额变动 >5%）、
//      挂单到期、点差过大暂存后补回、NFP 窗口撤单后重挂。
//
//    策略   magic   入场TF   信号周期   评估频率    每次最多尝试   挂单上限   过期
//    S1     +1      D1       M15       每 15 分钟      5            5        35h
//    S2     +5      D1       H1        每 1 小时       1            1        480h
//    S3     +8      D1       H1        每 1 小时       1            1        432h
//    S4     +2      H4       H1        每 1 小时       2            2        192h
//    S5     +12     H1       M15       每 15 分钟      3            3        30h
//    S6     +9      H1       M5        每 5 分钟       5            5        20h
//    S7     +14     H1       M15       每 15 分钟      5            5        60h
//    S8     +15     H1       M15       每 15 分钟      5            5        55h
//    S9     +13     H1       M15       每 15 分钟      3            3        15h
//
//  【九套策略的核心调参（pips）】
//    XAUUSD 两位/三位小数时 g_pipSize = 0.01，即 1 pip ≈ 0.01 美元（= 1 point）。
//    （g_pipSize 见 OnInit：默认 = SYMBOL_POINT；3/5 位小数时 ×10；
//      SymbolInfoInteger(...,17)==1 时 ÷10。）
//
//    策略   突破距离   买偏移    卖偏移    名义SL     TP      保本触发   追踪启动
//    S1     45        -275      -160      6100      1450     930       1800
//    S2     550       -170      -70       1000      4100     500       1400
//    S3     250       -130      -120      600       3300     400       400
//    S4     1050      -40       -100      700       4900     500       1450
//    S5     160       -120      -110      5300      900      260       400
//    S6     120       -115      -145      10100     800      330       1200
//    S7     10        -10       -145      2250      1450     340       900
//    S8     80        -140      -170      1900      1200     270       650
//    S9     40        -150      -145      3900      1350     160       355
//
//    折合美元/盎司（1 pip = 0.01 美元，未计 variableRatio 缩放）：
//    策略   名义SL      TP       保本      追踪
//    S1     61         14.5     9.3       18
//    S2     10         41       5         14
//    S3     6          33       4         4
//    S4     7          49       5         14.5
//    S5     53         9        2.6       4
//    S6     101        8        3.3       12
//    S7     22.5       14.5     3.4       9
//    S8     19         12       2.7       6.5
//    S9     39         13.5     1.6       3.55
//
//    → 盈亏比（TP/SL）只有 S2 / S3 / S4 大于 1；其余六套 TP 小于 SL，
//      实际出场主要依赖「保本触发（1.6~9.3 美元）」与「利润追踪（3.55~18 美元）」，
//      名义 SL 多数属于灾难性止损（不会轻易触发）。
// ============================================================================

// Uniform +/- Randomization jitter applied to preset baseline values.
double RandomizedJitter()
{
    if (Randomization > 0.0)
        return Randomization * 2.0 * MathRand() / 32768.0 + (0.0 - Randomization);
    return 0.0;
}

void LoadStrategy1Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 16;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_D1;
    g_signalTfPeriod = (int)PERIOD_M15;
    g_fractalRightBars = 24;
    g_fractalLeftBars = 3;
    g_fractalMinLookback = 105;
    g_entryBreakoutPips = 45.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -275.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -160.0 + RandomizedJitter();
    g_maxPendingOrders = 5;
    g_pendingDupTolerancePips = 30.0;
    g_pendingExpiryHours = 35;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 6100.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 1450.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 1800.0 + RandomizedJitter();
    g_trailActivationPips = 1800.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1600.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 700.0 + RandomizedJitter();
    g_beTriggerPips = 930.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 120.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 14;
    g_hlFractalLeftBars = 12;
    g_hlTrailMinGapPips = 300;
    g_hlOffsetPips = 22.0;
    g_maxOpenTradesPerSide = 5;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_1";
    }
    g_curStrategyMagic = ST1_MagicNumber + 1;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(145.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2000.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(60.0);
}
//LoadStrategy1Settings <<==--------   --------
void LoadStrategy4Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 16;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_H4;
    g_signalTfPeriod = (int)PERIOD_H1;
    g_fractalRightBars = 12;
    g_fractalLeftBars = 8;
    g_fractalMinLookback = 90;
    g_entryBreakoutPips = 1050.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -40.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -100.0 + RandomizedJitter();
    g_maxPendingOrders = 2;
    g_pendingDupTolerancePips = 130.0;
    g_pendingExpiryHours = 192;
    g_entryTfMinutes = 5;
    if (!(UseHL_TrailingSL))
    {
        g_stopLossPips = AdjustSL + 700.0 + RandomizedJitter();
    }
    else
    {
        g_stopLossPips = AdjustSL + 800.0 + RandomizedJitter();
    }
    g_takeProfitPips = AdjustTP + 4900.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 1300.0 + RandomizedJitter();
    g_trailActivationPips = 1450.0 + RandomizedJitter();
    g_profitTrailCapPips = 2000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1400.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 200.0 + RandomizedJitter();
    g_beTriggerPips = 500.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 200.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 14;
    g_hlFractalLeftBars = 6;
    g_hlTrailMinGapPips = 400;
    g_hlOffsetPips = 32.0;
    g_maxOpenTradesPerSide = 99;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_4";
    }
    g_curStrategyMagic = ST1_MagicNumber + 2;
    // Repeated isolated probes of the Market EX5 use the 52-point DD weight
    // in variable-value mode.  A single cold-agent matrix run produced 57-like
    // sizing; that run is treated as an environment-state counterexample.
    g_usdToAccountRate = ConvertUsdToAccountCurrency(52.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 1600.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(52.0);
}
//LoadStrategy4Settings <<==--------   --------
void LoadStrategy2Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 41;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_D1;
    g_signalTfPeriod = (int)PERIOD_H1;
    g_fractalRightBars = 15;
    g_fractalLeftBars = 3;
    g_fractalMinLookback = 230;
    g_entryBreakoutPips = 550.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -170.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -70.0 + RandomizedJitter();
    g_maxPendingOrders = 1;
    g_pendingDupTolerancePips = 480.0;
    g_pendingExpiryHours = 480;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 1000.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 4100.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 450.0 + RandomizedJitter();
    g_trailActivationPips = 1400.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1600.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 400.0 + RandomizedJitter();
    g_beTriggerPips = 500.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 100.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 1;
    g_hlFractalLeftBars = 5;
    g_hlTrailMinGapPips = 700;
    g_hlOffsetPips = 22.0;
    g_maxOpenTradesPerSide = 99;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_2";
    }
    g_curStrategyMagic = ST1_MagicNumber + 5;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(30.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2000.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(30.0);
}
//LoadStrategy2Settings <<==--------   --------
void LoadStrategy3Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 5;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_D1;
    g_signalTfPeriod = (int)PERIOD_H1;
    g_fractalRightBars = 7;
    g_fractalLeftBars = 2;
    g_fractalMinLookback = 20;
    g_entryBreakoutPips = 250.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -130.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -120.0 + RandomizedJitter();
    g_maxPendingOrders = 1;
    g_pendingDupTolerancePips = 980.0;
    g_pendingExpiryHours = 432;
    g_entryTfMinutes = 1;
    if (!(UseHL_TrailingSL))
    {
        g_stopLossPips = AdjustSL + 600.0 + RandomizedJitter();
    }
    else
    {
        g_stopLossPips = AdjustSL + 700.0 + RandomizedJitter();
    }
    g_takeProfitPips = AdjustTP + 3300.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 500.0 + RandomizedJitter();
    g_trailActivationPips = 400.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTargetPips = 1000.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 2000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_beTriggerPips = 400.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 7;
    g_hlFractalLeftBars = 4;
    g_hlTrailMinGapPips = 100;
    g_hlOffsetPips = 0.0;
    g_maxOpenTradesPerSide = 99;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_3";
    }
    g_curStrategyMagic = ST1_MagicNumber + 8;
    // The Market EX5 uses the 35-point historical DD weight in both fixed and
    // variable-value modes.  The reconstructed 32-point pre-return value caused
    // strategy 3 lots to round one step too high around the 0.025 boundary.
    g_usdToAccountRate = ConvertUsdToAccountCurrency(35.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2000.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(35.0);
}
//LoadStrategy3Settings <<==--------   --------
void LoadStrategy6Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 20;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_H1;
    g_signalTfPeriod = (int)PERIOD_M5;
    g_fractalRightBars = 26;
    g_fractalLeftBars = 24;
    g_fractalMinLookback = 140;
    g_entryBreakoutPips = 120.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -115.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -145.0 + RandomizedJitter();
    g_maxPendingOrders = 5;
    g_pendingDupTolerancePips = 55.0;
    g_pendingExpiryHours = 20;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 10100.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 800.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 500.0 + RandomizedJitter();
    g_trailActivationPips = 1200.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1950.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 350.0 + RandomizedJitter();
    g_beTriggerPips = 330.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 80.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 0;
    g_hlFractalLeftBars = 0;
    g_hlTrailMinGapPips = 100;
    g_hlOffsetPips = 0.0;
    g_maxOpenTradesPerSide = 5;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_6";
    }
    g_curStrategyMagic = ST1_MagicNumber + 9;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(348.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2400.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(140.0);
}
//LoadStrategy6Settings <<==--------   --------
void LoadStrategy5Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 24;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_H1;
    g_signalTfPeriod = (int)PERIOD_M15;
    g_fractalRightBars = 30;
    g_fractalLeftBars = 19;
    g_fractalMinLookback = 110;
    g_entryBreakoutPips = 160.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -120.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -110.0 + RandomizedJitter();
    g_maxPendingOrders = 3;
    g_pendingDupTolerancePips = 55.0;
    g_pendingExpiryHours = 30;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 5300.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 900.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 495.0 + RandomizedJitter();
    g_trailActivationPips = 400.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1900.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 250.0 + RandomizedJitter();
    g_beTriggerPips = 260.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 80.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 0;
    g_hlFractalLeftBars = 0;
    g_hlTrailMinGapPips = 100;
    g_hlOffsetPips = 0.0;
    g_maxOpenTradesPerSide = 99;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_5";
    }
    g_curStrategyMagic = ST1_MagicNumber + 12;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(281.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2600.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(110.0);
}
//LoadStrategy5Settings <<==--------   --------
void LoadStrategy9Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 12;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_H1;
    g_signalTfPeriod = (int)PERIOD_M15;
    g_fractalRightBars = 7;
    g_fractalLeftBars = 5;
    g_fractalMinLookback = 200;
    g_entryBreakoutPips = 40.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -150.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -145.0 + RandomizedJitter();
    g_maxPendingOrders = 3;
    g_pendingDupTolerancePips = 5.0;
    g_pendingExpiryHours = 15;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 3900.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 1350.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 445.0 + RandomizedJitter();
    g_trailActivationPips = 355.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1850.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 250.0 + RandomizedJitter();
    g_beTriggerPips = 160.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 50.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 1;
    g_hlFractalLeftBars = 9;
    g_hlTrailMinGapPips = 1500;
    g_hlOffsetPips = 46.0;
    g_maxOpenTradesPerSide = 99;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_9";
    }
    g_curStrategyMagic = ST1_MagicNumber + 13;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(968.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 1900.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(700.0);
}
//LoadStrategy9Settings <<==--------   --------
void LoadStrategy7Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 28;
    g_atrTimeframe = (int)PERIOD_H1;
    g_entryTfPeriod = (int)PERIOD_H1;
    g_signalTfPeriod = (int)PERIOD_M15;
    g_fractalRightBars = 25;
    g_fractalLeftBars = 23;
    g_fractalMinLookback = 145;
    g_entryBreakoutPips = 10.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -10.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -145.0 + RandomizedJitter();
    g_maxPendingOrders = 5;
    g_pendingDupTolerancePips = 90.0;
    g_pendingExpiryHours = 60;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 2250.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 1450.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 450.0 + RandomizedJitter();
    g_trailActivationPips = 900.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 2800.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 350.0 + RandomizedJitter();
    g_beTriggerPips = 340.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + 30.0 + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 12;
    g_hlFractalLeftBars = 17;
    g_hlTrailMinGapPips = 1000;
    g_hlOffsetPips = 45.0;
    g_maxOpenTradesPerSide = 5;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_7";
    }
    g_curStrategyMagic = ST1_MagicNumber + 14;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(149.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2600.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(90.0);
}
//LoadStrategy7Settings <<==--------   --------
void LoadStrategy8Settings()
{

    // Recovered from original MetaTester JIT dump: internal ATR readiness gate.
    g_atrPeriod = 11;
    g_atrTimeframe = (int)PERIOD_D1;
    g_entryTfPeriod = (int)PERIOD_H1;
    g_signalTfPeriod = (int)PERIOD_M15;
    g_fractalRightBars = 26;
    g_fractalLeftBars = 20;
    g_fractalMinLookback = 235;
    g_entryBreakoutPips = 80.0;
    g_entryBreakoutPct = 0.0;
    g_buyEntryOffsetPips = AdjustEntry + -140.0 + RandomizedJitter();
    g_sellEntryOffsetPips = AdjustEntry + -170.0 + RandomizedJitter();
    g_maxPendingOrders = 5;
    g_pendingDupTolerancePips = 5.0;
    g_pendingExpiryHours = 55;
    g_entryTfMinutes = 1;
    g_stopLossPips = AdjustSL + 1900.0 + RandomizedJitter();
    g_takeProfitPips = AdjustTP + 1200.0 + RandomizedJitter();
    g_profitTrailDistancePips = AdjustTrailSL + 1250.0 + RandomizedJitter();
    g_trailActivationPips = 650.0 + RandomizedJitter();
    g_profitTrailCapPips = 5000.0 + RandomizedJitter();
    g_profitTrailBufferPips = 0.1;
    g_partialClosePct = 0.0;
    g_profitTargetPips = 1950.0 + RandomizedJitter();
    g_trailTpPips = AdjustTrailTP + 250.0 + RandomizedJitter();
    g_beTriggerPips = 270.0 + RandomizedJitter();
    g_beExtraPips = AdjustBreakEven + RandomizedJitter();
    g_hlFractalTfMinutes = 60;
    g_fractalMaxShift = 50;
    g_hlFractalRightBars = 15;
    g_hlFractalLeftBars = 3;
    g_hlTrailMinGapPips = 1200;
    g_hlOffsetPips = 16.0;
    g_maxOpenTradesPerSide = 20;
    if (!(RemoveCommentSuffix))
    {
        g_orderComment = ST1_Comment + "_XAUUSD_8";
    }
    g_curStrategyMagic = ST1_MagicNumber + 15;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(276.0);
    if (!(UseVariableValues))   return;
    g_varValueScalePrice = 2800.0;
    g_usdToAccountRate = ConvertUsdToAccountCurrency(130.0);
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
// EnforcePropFirmDailyDrawdown —— 日内回撤熔断的两种口径（新增，2026-09）
// ----------------------------------------------------------------------------
//  触发量：totalDailyResult = (Equity - Balance)  + 今日已平仓净盈亏(含佣金+swap)
//
//  口径 A（新增，推荐用于 Static 规则的 Prop Firm）
//      PropFirmDailyLossUSD > 0  →  阈值 = PropFirmDailyLossUSD（账户币种固定金额）
//      例：6000 账户、日限 300 → 设 300，每天都是固定 300，不随盈利上移。
//
//  口径 B（原版行为，默认）
//      PropFirmDailyLossUSD = 0  →  阈值 = 基线 × PropFirmMaxDailyDD / 100
//      基线默认取 g_propfirmDailyPeakEquity（当日内最高权益，只增不减 = trailing）
//      PropFirmDailyLossStatic = true 时，基线改用 g_propfirmDailyStartEquity
//      （换日瞬间的权益快照，当天内不再上移，接近 Static 口径）
//
//  换日重置在 CheckDailyRolloverAndPropFirmGate 中完成（D1 新 K 线）：
//      g_propfirmDailyDDHit=false、g_propfirmDailyPeakEquity=0、
//      g_propfirmDailyStartEquity=AccountEquity()
//
//  已知缺口（与新增参数无关，未修改以保持原版行为）：
//      函数开头 "if (currentEquity == AccountBalance()) return;" 会在无持仓时
//      直接返回 —— 若当日亏损全部来自已平仓单且此刻空仓，熔断不会触发。
// ============================================================================

void EnforcePropFirmDailyDrawdown()
{
    double    closedTodayProfit;
    int       historyScanIdx;
    double    dealNetProfit;
    double    floatingDelta;
    double    totalDailyResult;
    //----- -----
    double     currentEquity;
    long       orderCloseTime;
    int        pendingScanIdx;

    currentEquity = AccountEquity();
    if (currentEquity == AccountBalance())   return;
    closedTodayProfit = 0.0;
    if (AccountEquity() > g_propfirmDailyPeakEquity)
    {
        g_propfirmDailyPeakEquity = AccountEquity();
    }
    for (historyScanIdx = HistoryTotal(); historyScanIdx >= 0; historyScanIdx--)
    {
        if (OrderSelect(historyScanIdx, 0, 1) != true)   continue;
        orderCloseTime = OrderCloseTime();
        if (orderCloseTime < iTime(g_chartSymbol, MT4Period(PERIOD_D1), 0))   continue;
        // The original EX5 daily-DD path accounts for the commission attached to
        // the closing history deal.  The generic MT4 history view also carries a
        // proportional entry commission, which made the reconstructed threshold
        // fire one or two ticks too early.  Keep the generic history semantics for
        // panels/ranking, but use the close-deal commission in this risk guard.
        double dailyCloseCommission = OrderCommission();
        if (g_sel_hist_index >= 0)
        {
            dailyCloseCommission = HistoryDealGetDouble((ulong)g_hist_ticket[g_sel_hist_index], DEAL_COMMISSION);
        }
        dealNetProfit = OrderProfit() + OrderSwap() + dailyCloseCommission;
        closedTodayProfit = dealNetProfit + closedTodayProfit;

    }
    floatingDelta = AccountEquity() - AccountBalance();
    totalDailyResult = floatingDelta + closedTodayProfit;
    double    dailyLossLimit = 0.0;
    if (PropFirmDailyLossUSD > 0.0)
    {
        dailyLossLimit = PropFirmDailyLossUSD;
    }
    else
    {
        double dailyLossBaseline = g_propfirmDailyPeakEquity;
        if (PropFirmDailyLossStatic)
        {
            if (g_propfirmDailyStartEquity <= 0.0)
            {
                g_propfirmDailyStartEquity = AccountEquity();
            }
            dailyLossBaseline = g_propfirmDailyStartEquity;
        }
        dailyLossLimit = dailyLossBaseline * PropFirmMaxDailyDD / 100.0;
    }
    if (!(-(totalDailyResult) > dailyLossLimit))   return;

    if (!(g_propfirmDailyDDHit))
    {
        Print("Max Daily Drawdown reached, closing trades and skipping rest of the day");
    }
    // Close from an immutable ticket snapshot. The original daily-DD path closes
    // BUY positions before SELL positions and visits newest tickets first within
    // each side. Pending orders remain a separate second pass below.
    CloseDailyDDPositionsInOriginalOrder();
    for (pendingScanIdx = MT4OrdersTotal(); pendingScanIdx >= 0; pendingScanIdx = pendingScanIdx - 1)
    {
        if (OrderSelect(pendingScanIdx, 0, 0) != true || OrderSymbol() != g_chartSymbol) continue;
        int dailyMagic = OrderMagicNumber();
        if (dailyMagic<ST1_MagicNumber + 1 || dailyMagic>ST1_MagicNumber + 15) continue;
        if (OrderType() != 4 && OrderType() != 5) continue;
        OrderDelete(OrderTicket(), Red);
    }
    g_propfirmDailyDDHit = true;
    g_propfirmDailyPeakEquity = 0.0;
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
    if (StringLen(lowercase_month_string) >= 3)
        lowercase_month_string = StringSubstr(lowercase_month_string, 0, 3);
    if (lowercase_month_string == "jan") return(1);
    if (lowercase_month_string == "feb") return(2);
    if (lowercase_month_string == "mar") return(3);
    if (lowercase_month_string == "apr") return(4);
    if (lowercase_month_string == "may") return(5);
    if (lowercase_month_string == "jun") return(6);
    if (lowercase_month_string == "jul") return(7);
    if (lowercase_month_string == "aug") return(8);
    if (lowercase_month_string == "sep") return(9);
    if (lowercase_month_string == "oct") return(10);
    if (lowercase_month_string == "nov") return(11);
    if (lowercase_month_string == "dec") return(12);
    return(0);
}

bool WTS_BuildDateTime(int year_int, int month_int, int day_int, int hour_int, int minute_int, int second_int, datetime& output_datetime)
{
    if (year_int < 2000 || year_int > 2200 || month_int < 1 || month_int > 12 ||
        day_int < 1 || day_int > 31 || hour_int < 0 || hour_int > 23 ||
        minute_int < 0 || minute_int > 59 || second_int < 0 || second_int > 59)
        return(false);

    MqlDateTime time_struct;
    ZeroMemory(time_struct);
    time_struct.year = year_int;
    time_struct.mon = month_int;
    time_struct.day = day_int;
    time_struct.hour = hour_int;
    time_struct.min = minute_int;
    time_struct.sec = second_int;
    output_datetime = StructToTime(time_struct);
    return(output_datetime > 0);
}

bool WTS_ParseHttpDate(string header_string, datetime& output_datetime)
{
    string lowercase_header_string = header_string;
    StringToLower(lowercase_header_string);

    int position_int = StringFind(lowercase_header_string, "\r\ndate:", 0);
    if (position_int >= 0)
        position_int += 2;
    else
    {
        position_int = StringFind(lowercase_header_string, "\ndate:", 0);
        if (position_int >= 0)
            position_int += 1;
        else if (StringFind(lowercase_header_string, "date:", 0) == 0)
            position_int = 0;
        else
            return(false);
    }

    int line_end_int = StringFind(header_string, "\n", position_int);
    string date_line_string;
    if (line_end_int < 0)
        date_line_string = StringSubstr(header_string, position_int + 5);
    else
        date_line_string = StringSubstr(header_string, position_int + 5, line_end_int - (position_int + 5));
    StringReplace(date_line_string, "\r", "");
    StringTrimLeft(date_line_string);
    StringTrimRight(date_line_string);

    // RFC 7231 example: Fri, 14 Aug 2026 08:27:31 GMT
    string parts_string[];
    int part_count_int = StringSplit(date_line_string, ' ', parts_string);
    if (part_count_int < 6)
        return(false);

    int day_int = (int)StringToInteger(parts_string[1]);
    int month_int = WTS_MonthToInt(parts_string[2]);
    int year_int = (int)StringToInteger(parts_string[3]);

    string clock_parts_string[];
    if (StringSplit(parts_string[4], ':', clock_parts_string) < 3)
        return(false);
    int hour_int = (int)StringToInteger(clock_parts_string[0]);
    int minute_int = (int)StringToInteger(clock_parts_string[1]);
    int second_int = (int)StringToInteger(clock_parts_string[2]);

    return(WTS_BuildDateTime(year_int, month_int, day_int, hour_int, minute_int, second_int, output_datetime));
}

string WTS_StripTags(string input_string)
{
    string output_string = "";
    bool inside_tag_bool = false;
    int length_int = StringLen(input_string);
    for (int i = 0; i < length_int; i++)
    {
        ushort character_char = (ushort)StringGetCharacter(input_string, i);
        if (character_char == '<')
        {
            inside_tag_bool = true;
            output_string += " ";
            continue;
        }
        if (character_char == '>')
        {
            inside_tag_bool = false;
            output_string += " ";
            continue;
        }
        if (!inside_tag_bool)
            output_string += ShortToString(character_char);
    }

    StringReplace(output_string, "&nbsp;", " ");
    StringReplace(output_string, "&#160;", " ");
    StringReplace(output_string, "\r", " ");
    StringReplace(output_string, "\n", " ");
    StringReplace(output_string, "\t", " ");
    while (StringFind(output_string, "  ", 0) >= 0)
        StringReplace(output_string, "  ", " ");
    StringTrimLeft(output_string);
    StringTrimRight(output_string);
    return(output_string);
}

bool WTS_ParseHtmlTime(string html_string, datetime& output_datetime)
{
    // Old WorldTimeServer layout: Unix timestamp in a hidden field.
    int position_int = StringFind(html_string, "\"serverTimeStamp\" value=", 0);
    if (position_int >= 0)
    {
        int length_int = StringLen(html_string);
        int i = position_int + 20;
        while (i < length_int)
        {
            ushort c = (ushort)StringGetCharacter(html_string, i);
            if (c >= '0' && c <= '9')
                break;
            i++;
        }
        string digits_string = "";
        while (i < length_int && StringLen(digits_string) < 12)
        {
            ushort c = (ushort)StringGetCharacter(html_string, i);
            if (c < '0' || c > '9')
                break;
            digits_string += ShortToString(c);
            i++;
        }
        long timestamp_long = (long)StringToInteger(digits_string);
        if (timestamp_long > 1000000000)
        {
            output_datetime = (datetime)timestamp_long;
            return(true);
        }
    }

    // Current WorldTimeServer layout (2026):
    // "UTC/GMT is 08:27 on Friday, August 14, 2026"
    position_int = StringFind(html_string, "UTC/GMT is", 0);
    if (position_int < 0)
        return(false);

    string fragment_string = StringSubstr(html_string, position_int, 500);
    string text_string = WTS_StripTags(fragment_string);
    int marker_int = StringFind(text_string, "UTC/GMT is ", 0);
    if (marker_int < 0)
        return(false);

    int time_start_int = marker_int + StringLen("UTC/GMT is ");
    if (StringLen(text_string) < time_start_int + 5)
        return(false);
    string hour_minute_string = StringSubstr(text_string, time_start_int, 5);
    string time_parts_string[];
    if (StringSplit(hour_minute_string, ':', time_parts_string) < 2)
        return(false);

    int hour_int = (int)StringToInteger(time_parts_string[0]);
    int minute_int = (int)StringToInteger(time_parts_string[1]);

    int on_position_int = StringFind(text_string, " on ", time_start_int);
    if (on_position_int < 0)
        return(false);
    string date_part_string = StringSubstr(text_string, on_position_int + 4, 80);
    string date_parts_string[];
    int date_part_count_int = StringSplit(date_part_string, ' ', date_parts_string);
    if (date_part_count_int < 4)
        return(false);

    // tokens: Friday, August 14, 2026
    string day_string = date_parts_string[2];
    string year_string = date_parts_string[3];
    StringReplace(day_string, ",", "");
    StringReplace(year_string, ",", "");
    int month_int = WTS_MonthToInt(date_parts_string[1]);
    int day_int = (int)StringToInteger(day_string);
    int year_int = (int)StringToInteger(year_string);

    // The visible "UTC/GMT is" line has minute precision. This is sufficient
    // for broker GMT offset detection and remains independent of VPS time.
    return(WTS_BuildDateTime(year_int, month_int, day_int, hour_int, minute_int, 0, output_datetime));
}

int DetectBrokerGmtOffset()
{
    string    wtsResponseBody;
    long      gmtTimeLong;
    int       gmtOffsetHours;
    char      webRequestData[];
    char      webResponseData[];
    //----- -----
    string     httpResultHeaders;
    string     responseText;
    datetime   gmtTimeParsed = 0;
    int        requestStatus;

    ResetLastError();
    requestStatus = WebRequest("GET", "https://www.worldtimeserver.com/time-zones/utc/", NULL, NULL, 10000, webRequestData, 0, webResponseData, httpResultHeaders);
    if (requestStatus == -1)
    {
        Print("Error when reading GMT URL. Error code  =", GetLastError());
        MessageBox("Add the address \'https://www.worldtimeserver.com/\' in the list of allowed URLs on tab \'Expert Advisors\'", "Error", 64);
        responseText = "999";
    }
    else
    {
        // MQL5: count=-1 means read the whole WebRequest response array.
        responseText = CharArrayToString(webResponseData, 0, -1, CP_UTF8);
    }
    wtsResponseBody = responseText;
    if (wtsResponseBody == "999")
    {
        return(999);
    }

    // Prefer WorldTimeServer's HTTP Date header. It is standardized and does
    // not change when the site's visual HTML layout changes.
    bool parse_succeeded_bool = WTS_ParseHttpDate(httpResultHeaders, gmtTimeParsed);
    if (!parse_succeeded_bool)
        parse_succeeded_bool = WTS_ParseHtmlTime(wtsResponseBody, gmtTimeParsed);

    if (!parse_succeeded_bool || gmtTimeParsed <= 0)
    {
        Print("Error in detecting GMT time with WorldTimeServer response");
        return(999);
    }

    gmtTimeLong = (long)gmtTimeParsed;
    Print("GMT time = ", gmtTimeLong);
    Print("Broker time = ", TimeCurrent());
    gmtOffsetHours = TimeHour(TimeCurrent()) - TimeHour((datetime)gmtTimeLong);
    if (gmtOffsetHours < -12)
    {
        gmtOffsetHours += 24;
    }
    if (gmtOffsetHours > 12)
    {
        gmtOffsetHours -= 24;
    }
    Print("GMT_Offset detected: " + string(gmtOffsetHours));
    if ((gmtOffsetHours < -12 || gmtOffsetHours >  12))
    {
        Print("Error in detecting GMT offset with URL");
        return(999);
    }
    if (gmtTimeLong < TimeCurrent() - 0x15180)
    {
        Print("Error in detecting GMT time with URL");
        return(999);
    }
    return(gmtOffsetHours);
}
//DetectBrokerGmtOffset <<==--------   --------
bool IsAmericanDst()
{
    int       dstYear;
    datetime  dstStart;
    datetime  dstEnd;
    int       dstStartDay;
    int       dstEndDay;
    //----- -----

    datetime now = TimeCurrent();
    datetime dayStart = now - (now % 86400);
    if (g_us_dst_cache_valid && g_us_dst_cache_day == dayStart)
    {
        return(g_us_dst_cache_value);
    }
    dstYear = TimeYear(now);
    dstStart = 0;
    dstEnd = 0;
    if (dstYear < 1987)
    {
        Print("AmericanDST(): Invalid year.");
        return(false);
    }
    dstStartDay = 0;
    dstEndDay = 0;
    if (dstYear >= 1987 && dstYear <= 2006)
    {
        dstStartDay = (int)(MathMod(dstYear * 6 + 2 - dstYear / 4, 7.0) + 1.0);
        dstEndDay = (int)(31.0 - (MathMod(dstYear * 5 / 4 + 1, 7.0)));
        dstStart = StringToTime(((string)dstYear + ".04.01")) + (dstStartDay - 1) * 86400 + 0x1C20;
        dstEnd = StringToTime(((string)dstYear + ".10.01")) + (dstEndDay - 1) * 86400 + 0x1C20;
    }
    else
    {
        if (dstYear >= 2007)
        {
            dstStartDay = (int)(14.0 - (MathMod(dstYear * 5 / 4 + 1, 7.0)));
            dstEndDay = (int)(7.0 - (MathMod(dstYear * 5 / 4 + 1, 7.0)));
            dstStart = StringToTime(((string)dstYear + ".03.01")) + (dstStartDay - 1) * 86400 + 0x1C20;
            dstEnd = StringToTime(((string)dstYear + ".11.01")) + (dstEndDay - 1) * 86400 + 0x1C20;
        }
    }
    g_us_dst_cache_value = (TimeDayOfYear(now) > TimeDayOfYear(dstStart) &&
        TimeDayOfYear(now) < TimeDayOfYear(dstEnd));
    g_us_dst_cache_day = dayStart;
    g_us_dst_cache_valid = true;
    return(g_us_dst_cache_value);
}
//<<==IsAmericanDst <<==

// ============================================================================
// [§18] 参数速查表（共 67 个 input，其中 8 个为纯显示分隔条）—— 纯注释
// ----------------------------------------------------------------------------
//  格式：参数名  [默认值]  作用一句话   → PF/实操建议
//  建议列标注的是「6000 账户 / 日限 300 / 总回撤 600 / Static」场景下的取值。
// ============================================================================
//
// ---- A. 账户与风控（9 项）· PF 核心 ------------------------------------
//   MaxAllowedDD              [30]     回撤预算：手数分子 + Auto档位；非强平     → 10
//   PropFirmMaxDailyDD        [0]      日限：百分比 × 当日峰值权益               → 0
//   PropFirmDailyLossUSD      [0]      日限：固定金额（>0 时优先于百分比）        → 300
//   PropFirmDailyLossStatic   [false]  百分比模式基线锁为"当日起始权益"           → false
//   ManualBalance             [0]      强制手数基准；>0 会让收益率越来越小        → 0
//   OnlyUp                    [true]   手数基准取峰值余额（只增不减）            → true
//   ResetHighestBalance       [false]  清终端全局变量 HighestBalance             → 回测前 true 跑一次
//   UseEquity                 [false]  手数基准用 equity 而非 balance            → false
//   CheckMargin               [true]   下单前检查可用保证金                      → true
//
// ---- B. 手数与风险（6 项）----------------------------------------------
//   Risk                      [1234]   手数模式：0固定 / 3单策略风险 / 999 / 9999 / 1234按总回撤 → 0
//   StartLots                 [0.01]   固定手数；仅 Risk=0 生效                  → 0.01
//   UseWeightedLots           [true]   加权手数；仅 Risk=1234 生效                → 保持
//   MaxRiskPerStrategy_       [1]      单策略风险系数                            → 0.5
//   UseVariableValues         [true]   影响 riskFactor 与可变比例                 → false（配 Risk=0）
//   AdjustLotsizeToVariableValues [true] 手数随可变值调整                        → 保持
//
// ---- C. 策略选择与档位（18 项）-----------------------------------------
//   TradeFrequency            [Auto(5)] 档位；非 Auto 时直接指定档位             → Conservative(1)
//   RunStrat1 / 2 / 3         [true]   低风险三套                                → true
//   RunStrat4 / 5 / 6 / 7     [true]   中风险四套                                → false（先关）
//   RunStrat8 / 9             [true]   高风险两套                                → false
//   AllowBuyTrades            [true]   允许做多                                  → true
//   AllowSellTrades           [true]   允许做空                                  → true
//   AdjustEntry / SL / TP     [0]      全局入场 / 止损 / 止盈偏移                 → 0
//   AdjustTrailSL / TrailTP   [0]      追踪止损 / 止盈偏移                        → 0
//   AdjustBreakEven           [0]      保本偏移                                  → 0
//
// ---- D. 时段与新闻过滤（15 项）-----------------------------------------
//   FridayStopHour            [25]     周五收工小时（券商时间 0-23；>=24 永不触发≈关闭，<0 才是真正关闭）→ 22
//   FridayClosePending        [true]   周末前撤挂单                               → true
//   FridayCloseOpen           [true]   周末前平仓                                 → true
//   EnableNFP_Filter          [true]   非农过滤总开关                             → true
//   UseMQL5Calendar           [true]   用 MT5 日历（回测取不到时回落硬编码日期）   → true
//   AutoGMT                   [true]   自动检测券商 GMT 偏移                      → true
//   Broker_GMT_OFFSET_Winter  [2]      冬令时偏移（AutoGMT=false 时生效）         → 保持
//   Broker_GMT_OFFSET_Summer  [3]      夏令时偏移                                 → 保持
//   NFP_CloseOpenTrades       [true]   NFP 窗口内平仓                             → true
//   NFP_ClosePendingOrders    [true]   NFP 窗口内撤挂单                           → true
//   NFP_MinutesBefore         [100]    事前窗口（分钟）                           → 120
//   NFP_MinutesAfter          [60]     事后窗口（分钟）                           → 90
//   MaxSpread                 [60]     点差上限（撤单阈值=MaxSpread×variableRatio×pipSize；
//                                       XAUUSD 下 60 ≈ 0.60 美元。恢复阈值更小，构成滞回，
//                                       避免点差抖动时反复撤挂。500 会导致该功能永不触发）→ 保持 60
//   FakeOutFilter             [2]      假突破过滤档                               → 保持
//   Randomization             [0]      入场/出场随机抖动（pips）                  → 0（保证可复现）
//
// ---- E. 订单与持仓管理（6 项）------------------------------------------
//   ST1_MagicNumber           [8000]   基础 magic；九套分别为 +1/+5/+8/+2/+12/+9/+14/+15/+13 → 别动
//   ST1_Comment               ["The Gold Reaper"] 订单注释                        → 保持
//   RemoveCommentSuffix       [false]  去掉注释后缀                               → 保持
//   setSL_TP_After_Entry      [false]  成交后再补设 SL/TP                         → false
//   Virtual_expiration        [false]  虚拟到期（不设真实到期时间）                → false
//   UseHL_TrailingSL          [true]   分形高低点追踪止损                          → true
//
// ---- F. 面板与显示（4 项）----------------------------------------------
//   ShowInfoPanel             [true]   信息面板                                   → 回测 false（提速）
//   UpdateInfoTesting         [false]  回测中刷新面板                             → false
//   InfoPanelSizeAdjust       [1]      面板缩放                                   → 保持
//   SetFontSize               [0]      字号（0 = 自动）                           → 保持
//
// ---- G. 回测（1 项）----------------------------------------------------
//   BacktestSpeed             [speed_normal] 回测加速节流                        → 粗筛 fast / 定稿 normal
//
// ---- H. 纯显示分隔条（8 项，无逻辑作用）--------------------------------
//   lijntje / BacktestSpeed_string / spreadfilter / NFP_FILTER /
//   propfirmsettings / LotSizeSettings / ManualStratSelect / ManStratWarn
//   —— 仅为参数面板的分组标题，改动不影响任何行为。
//
// ---- 资金链路：哪些参数真正影响你的钱 ----------------------------------
//   账户余额
//     → [档位] TradeFrequency（固定档）或 Auto + MaxAllowedDD + 余额
//          └ 决定：跑哪几套策略 + riskFactor（手数分母）
//     → [手数] Risk=0 时取 StartLots；Risk=1234 时取 MaxAllowedDD/riskFactor × 余额
//          └ 再过三道闸：0.01 步长取整 → 最小手数 → 保证金检查
//     → [下单] 分形信号 + MA 方向过滤 + 点差/时段/周五/NFP 过滤
//     → [管仓] 追踪止损 / 保本 / 虚拟止损
//     → [熔断] PropFirmDailyLossUSD（日限）—— 目前唯一的真实保护
//              ※ 总回撤强平：本 EA 未实现
//
// ---- 四条务必记住 ------------------------------------------------------
//   1. 只有 PropFirmDailyLossUSD 是真保护；其余风控参数都只是"影响手数"。
//   2. TradeFrequency 别用 Auto —— 余额一变，策略集合与手数系数会悄悄变，
//      导致回测不可复现、不同初始金额之间不可比。
//   3. ManualBalance 实盘必须为 0 —— 否则手数锁死，盈利百分比越来越小。
//   4. MaxAllowedDD 不保护你 —— 它只是"声明我打算承受多大回撤"，EA 据此
//      放大或缩小手数；触线时不会平仓、不会停手。
// ============================================================================
